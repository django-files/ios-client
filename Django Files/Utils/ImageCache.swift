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

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        contentCache.countLimit = 100
        contentCache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
    }

    func set(_ image: UIImage, for key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
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
}

/// Drop-in replacement for AsyncImage with an in-memory NSCache layer.
///
/// Uses `.task(id: url)` for correct structured-concurrency lifecycle:
/// - Automatically cancelled when the view disappears or the url changes.
/// - Re-started when the view reappears or the url changes.
/// - Cache hits are applied synchronously (no placeholder flash).
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var cachedImage: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let cachedImage {
                content(Image(uiImage: cachedImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load(url)
        }
    }

    private func load(_ url: URL?) async {
        guard let url else {
            cachedImage = nil
            return
        }
        let key = url.absoluteString
        if let hit = ImageCache.shared.get(for: key) {
            cachedImage = hit
            return
        }
        // Not cached — show placeholder while downloading.
        cachedImage = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse).map({ $0.statusCode < 300 }) ?? true else { return }
            // UIImage init is fast for thumbnails; running on the main actor is acceptable.
            guard let image = UIImage(data: data) else { return }
            ImageCache.shared.set(image, for: key)
            cachedImage = image
        } catch {
            // URLError.cancelled is expected on view disappear / url change — ignore silently.
        }
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
