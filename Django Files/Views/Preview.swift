import SwiftUI
import AVKit

struct ContentPreview: View {
    let mimeType: String
    let fileURL: URL
    
    init(mimeType: String, fileURL: URL?) {
        self.mimeType = mimeType
        self.fileURL = fileURL ?? URL(string: "about:blank")!
    }
    
    @State private var content: Data?
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Error: \(error.localizedDescription)")
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else {
                contentView
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    // Determine the appropriate view based on MIME type
    private var contentView: some View {
        Group {
            if mimeType.starts(with: "text/") {
                textPreview
            } else if mimeType.starts(with: "image/") {
                imagePreview
            } else if mimeType.starts(with: "video/") {
                videoPreview
            } else {
                genericFilePreview
            }
        }
    }
    
    // Text Preview
    private var textPreview: some View {
        ScrollView {
            if let content = content, let text = String(data: content, encoding: .utf8) {
                Text(text)
                    .padding()
            } else {
                Text("Unable to decode text content")
                    .foregroundColor(.red)
            }
        }
    }
    
    // Image Preview
    private var imagePreview: some View {
        ScrollView {
            if let content = content, let uiImage = UIImage(data: content) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Unable to load image")
                    .foregroundColor(.red)
            }
        }
    }
    
    // Video Preview
    private var videoPreview: some View {
        VideoPlayer(player: AVPlayer(url: fileURL))
            .aspectRatio(contentMode: .fit)
    }
    
    // Generic File Preview
    private var genericFilePreview: some View {
        VStack {
            Image(systemName: "doc")
                .font(.system(size: 72))
                .foregroundColor(.gray)
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .padding(.top)
            Text(mimeType)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // Load content from URL
    private func loadContent() {
        isLoading = true
        
        // For video, we don't need to download the content as we'll use the URL directly
        if mimeType.starts(with: "video/") {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: fileURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.error = error
                    return
                }
                
                self.content = data
            }
        }.resume()
    }
}

// Preview
struct ContentPreview_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Text Preview
            ContentPreview(
                mimeType: "text/plain",
                fileURL: URL(string: "https://example.com/sample.txt")!
            )
            .previewDisplayName("Text Preview")
            
            // Image Preview
            ContentPreview(
                mimeType: "image/jpeg",
                fileURL: URL(string: "https://example.com/sample.jpg")!
            )
            .previewDisplayName("Image Preview")
            
            // Video Preview
            ContentPreview(
                mimeType: "video/mp4",
                fileURL: URL(string: "https://example.com/sample.mp4")!
            )
            .previewDisplayName("Video Preview")
            
            // Generic File Preview
            ContentPreview(
                mimeType: "application/pdf",
                fileURL: URL(string: "https://example.com/sample.pdf")!
            )
            .previewDisplayName("Generic File Preview")
        }
    }
}
