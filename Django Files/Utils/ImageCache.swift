//
//  ImageCache.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/20/25.
//

import SwiftUI
import Foundation

class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let contentCache = NSCache<NSString, NSData>()

    // Disk-backed session: thumbnails survive app restarts and memory pressure evictions.
    static let thumbnailSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "df_thumbnails"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private init() {
        // Dense grid zoom (25 columns ≈ 1400 visible cells) needs more entries than 500;
        // downsampled thumbs are tiny, so totalCostLimit stays the real memory ceiling.
        cache.countLimit = 4000
        // Scale-factor-aware cost limit: retina devices use 4× the pixel bytes of logical size.
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
        contentCache.countLimit = 100
        contentCache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
    }

    func set(_ image: UIImage, for key: String) {
        // Use actual pixel bytes so NSCache evicts accurately on retina displays.
        let scale = image.scale
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.size.height * scale * scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func get(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func setContent(_ data: Data, for key: String) {
        contentCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }

    func getContent(for key: String) -> Data? {
        return contentCache.object(forKey: key as NSString) as Data?
    }

    /// Combined disk cache bytes (URLCache) + best-effort memory cache estimate.
    var totalCacheBytes: Int {
        let disk = Self.thumbnailSession.configuration.urlCache?.currentDiskUsage ?? 0
        let mem  = Self.thumbnailSession.configuration.urlCache?.currentMemoryUsage ?? 0
        return disk + mem
    }

    func clearAll() {
        cache.removeAllObjects()
        contentCache.removeAllObjects()
        Self.thumbnailSession.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// Drop-in replacement for AsyncImage with in-memory NSCache + disk URLCache.
///
/// Uses `.task(id:)` for correct structured-concurrency lifecycle:
/// - Automatically cancelled when the view disappears or the url/size changes.
/// - Re-started when the view reappears or the url/size changes.
/// - Cache hits are applied synchronously (no placeholder flash).
///
/// Pass `targetSize` (the view's max dimension in points) to decode a downsampled
/// thumbnail instead of the full image — dense grids composite hundreds of cells,
/// and full-resolution decodes are the main scroll-hitch source.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGFloat?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var cachedImage: UIImage?

    init(
        url: URL?,
        targetSize: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    private static var buckets: [Int] { [64, 128, 256, 512, 1024] }

    // Bucketed max pixel dimension so nearby zoom levels share one decoded image.
    private var pixelBucket: Int? {
        guard let targetSize, targetSize > 0 else { return nil }
        let pixels = targetSize * displayScale
        return Self.buckets.first { CGFloat($0) >= pixels } ?? 1024
    }

    private var cacheKey: String? {
        guard let url else { return nil }
        guard let pixelBucket else { return url.absoluteString }
        return "\(url.absoluteString)#\(pixelBucket)"
    }

    var body: some View {
        // Key built once per evaluation, and the cache read is synchronous: appearing
        // cells render their image on the very first frame instead of flashing the
        // placeholder until `.task` fires a tick later — and a cache hit never dirties
        // @State, so scrolling through already-decoded content causes zero invalidations.
        let key = cacheKey
        let hit = key.flatMap { ImageCache.shared.get(for: $0) } ?? cachedImage
        Group {
            if let hit {
                content(Image(uiImage: hit))
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            await load(url, key: key, maxPixels: pixelBucket)
        }
    }

    private func load(_ url: URL?, key: String?, maxPixels: Int?) async {
        guard let url, let key else {
            cachedImage = nil
            return
        }
        // Already rendered synchronously via displayImage — skip the @State write.
        if ImageCache.shared.get(for: key) != nil { return }
        // Stale-while-revalidate: when zoom changes the bucket, keep showing any
        // already-decoded size of this image (GPU rescales it) instead of flashing
        // a placeholder while the correct size decodes below.
        let stale = Self.nearestDecoded(urlString: url.absoluteString, preferring: maxPixels)
        if stale !== cachedImage {
            cachedImage = stale
        }
        do {
            let (data, response) = try await ImageCache.thumbnailSession.data(from: url)
            guard !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? true else { return }
            // Decode + GPU-prep on a background thread so the main actor never stalls.
            let image = await Task.detached(priority: .userInitiated) {
                Self.decode(data, maxPixels: maxPixels)
            }.value
            guard !Task.isCancelled, let image else { return }
            ImageCache.shared.set(image, for: key)
            cachedImage = image
        } catch {
            // URLError.cancelled is expected on view disappear / url change — ignore silently.
        }
    }

    /// Best already-decoded version of this URL at another bucket size — larger
    /// sizes first (sharper when scaled down), then smaller, then the legacy
    /// unbucketed key.
    private static func nearestDecoded(urlString: String, preferring maxPixels: Int?) -> UIImage? {
        guard let maxPixels else { return nil }
        let larger = buckets.filter { $0 > maxPixels }
        let smaller = buckets.filter { $0 < maxPixels }.reversed()
        for bucket in larger + smaller {
            if let hit = ImageCache.shared.get(for: "\(urlString)#\(bucket)") {
                return hit
            }
        }
        return ImageCache.shared.get(for: urlString)
    }

    // nonisolated: View members inherit @MainActor, but this pure function must run
    // inside Task.detached — decoding on the main actor is the hitch we're avoiding.
    private nonisolated static func decode(_ data: Data, maxPixels: Int?) -> UIImage? {
        guard let raw = UIImage(data: data) else { return nil }
        if let maxPixels {
            let rawMax = max(raw.size.width, raw.size.height) * raw.scale
            if rawMax > CGFloat(maxPixels) {
                let ratio = CGFloat(maxPixels) / rawMax
                let target = CGSize(
                    width: (raw.size.width * raw.scale * ratio).rounded(),
                    height: (raw.size.height * raw.scale * ratio).rounded()
                )
                return raw.preparingThumbnail(of: target) ?? raw.preparingForDisplay()
            }
        }
        return raw.preparingForDisplay()
    }
}

struct CachedContentLoader {
    static func loadContent(from url: URL) async throws -> Data {
        let urlString = url.absoluteString
        if let cachedData = ImageCache.shared.getContent(for: urlString) {
            return cachedData
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        ImageCache.shared.setContent(data, for: urlString)
        return data
    }
}
