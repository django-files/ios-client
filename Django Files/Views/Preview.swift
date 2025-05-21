import SwiftUI
import AVKit
import HighlightSwift
import UIKit

struct ContentPreview: View {
    let mimeType: String
    let fileURL: URL
    let file: DFFile
    var showFileInfo: Binding<Bool>

    @State private var content: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0

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
        .sheet(isPresented: showFileInfo, onDismiss: { showFileInfo.wrappedValue = false }) {
            PreviewFileInfo(file: file)
                .presentationBackground(.ultraThinMaterial)

        }

        
    }

    // Text Preview
    private var textPreview: some View {
        ScrollView {
            if let content = content, let text = String(data: content, encoding: .utf8) {
                CodeText(text)
                    .padding()
            } else {
                Text("Unable to decode text content")
                    .foregroundColor(.red)
            }
        }
    }

    // Image Preview
    private var imagePreview: some View {
        GeometryReader { geometry in
            if let content = content, let uiImage = UIImage(data: content) {
                ImageScrollView(image: uiImage)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Text("Unable to load image")
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

struct PreviewFileInfo: View {
    let file: DFFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(file.name)")
                .font(.title)
            Label("\(file.mime)", systemImage: "document")
            HStack {
                Label("\(file.userUsername)", systemImage: "person")
                Label("\(file.view)", systemImage: "eye")
                Label("\(file.size)", systemImage: "internaldrive")
            }
            HStack {
                Label("", systemImage: (file.password != "") ? "key" : "")
                Label("", systemImage: file.private ? "lock" : "")
                Label("", systemImage: (file.expr != "") ? "calendar.badge.exclamationmark" : "")
                if file.maxv != 0 {
                    Label("Max Views: \(String(file.maxv))", systemImage: "eye.circle")
                }
            }
            Label("\(file.formattedDate())", systemImage: "calendar")
            
            Text("\(file.info)")
        }
        .padding(50)
    }
}

struct ImageScrollView: UIViewRepresentable {
    let image: UIImage
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CustomScrollView()
        scrollView.delegate = context.coordinator
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
    
        // Calculate initial zoom scale
        let widthScale = UIScreen.main.bounds.width / image.size.width
        let heightScale = UIScreen.main.bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)
            
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = 5.0
        
        // Set content size to image size
        scrollView.contentSize = image.size
        
        // Set initial zoom scale
        scrollView.zoomScale = minScale
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.updateZoomScaleForSize(scrollView.bounds.size)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ImageScrollView
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        
        init(_ parent: ImageScrollView) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
       func updateZoomScaleForSize(_ size: CGSize) {
           guard let imageView = imageView,
               let image = imageView.image,
               let scrollView = scrollView,
               size.width > 0,
               size.height > 0,
               image.size.width > 0,
               image.size.height > 0 else { return }
           
           let widthScale = size.width / image.size.width
           let heightScale = size.height / image.size.height
           let minScale = min(widthScale, heightScale)
            
           scrollView.minimumZoomScale = minScale
           scrollView.maximumZoomScale = max(minScale * 5, 5.0)
        }
       
       @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
           guard let scrollView = gesture.view as? UIScrollView else { return }
           
           if scrollView.zoomScale > scrollView.minimumZoomScale {
               scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
           } else {
               let point = gesture.location(in: imageView)
               let size = scrollView.bounds.size
               let w = size.width / scrollView.maximumZoomScale
               let h = size.height / scrollView.maximumZoomScale
               let x = point.x - (w / 2.0)
               let y = point.y - (h / 2.0)
               let rect = CGRect(x: x, y: y, width: w, height: h)
               scrollView.zoom(to: rect, animated: true)
           }
       }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame
            
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }
            
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }
            
            imageView.frame = frameToCenter
        }
    }
}

class CustomScrollView: UIScrollView {
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Center the image after layout
        if let imageView = subviews.first as? UIImageView {
            var frameToCenter = imageView.frame
            
            if frameToCenter.size.width < bounds.size.width {
                frameToCenter.origin.x = (bounds.size.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }
            
            if frameToCenter.size.height < bounds.size.height {
                frameToCenter.origin.y = (bounds.size.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }
            
            imageView.frame = frameToCenter
        }
    }
}
