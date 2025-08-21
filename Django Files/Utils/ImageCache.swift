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
        // Cache is unlimited
    }
    
    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func get(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setContent(_ data: Data, for key: String) {
        contentCache.setObject(data as NSData, forKey: key as NSString)
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
            } else {
                if isLoading {
                    placeholder()
                } else {
                    placeholder()
                        .onAppear {
                            loadImage()
                        }
                }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url else { return }
        
        let urlString = url.absoluteString
        
        // Check cache first
        if let cached = ImageCache.shared.get(for: urlString) {
            self.cachedImage = cached
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        ImageCache.shared.set(uiImage, for: urlString)
                        self.cachedImage = uiImage
                        self.isLoading = false
                    }
                }
            } catch {
                print("Error loading image: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
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
