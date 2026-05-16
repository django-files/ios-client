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

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let scale: CGFloat
    let transaction: Transaction
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var cachedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    
    init(
        url: URL?,
        scale: CGFloat = 1.0,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let cachedImage = cachedImage {
                content(Image(uiImage: cachedImage))
            } else if isLoading || loadFailed {
                placeholder()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }

        let urlString = url.absoluteString

        if let cached = ImageCache.shared.get(for: urlString) {
            self.cachedImage = cached
            return
        }

        isLoading = true

        Task {
            // Download and decode entirely off the main thread.
            // Task{} alone inherits the main actor, making UIImage(data:) block the UI.
            // Task.detached runs on the cooperative pool; we await its result, then
            // update SwiftUI state once we're back on the main actor.
            let decoded: UIImage? = await Task.detached(priority: .utility) {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                return UIImage(data: data)
            }.value

            if let uiImage = decoded {
                ImageCache.shared.set(uiImage, for: urlString)
                self.cachedImage = uiImage
            } else {
                self.loadFailed = true
            }
            self.isLoading = false
        }
    }
}

// Add a new generic content loader
struct CachedContentLoader {
    static func loadContent(from url: URL) async throws -> Data {
        let urlString = url.absoluteString
        
        // Check cache first
        if let cachedData = ImageCache.shared.getContent(for: urlString) {
            return cachedData
        }
        
        // Download and cache if not found
        let (data, _) = try await URLSession.shared.data(from: url)
        ImageCache.shared.setContent(data, for: urlString)
        return data
    }
}
