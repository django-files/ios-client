import SwiftUI
import FLAnimatedImage

struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> FLAnimatedImageView {
        let imageView = FLAnimatedImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }
    
    func updateUIView(_ imageView: FLAnimatedImageView, context: Context) {
        if let animatedImage = FLAnimatedImage(animatedGIFData: data) {
            imageView.animatedImage = animatedImage
        }
    }
}

struct AnimatedImageScrollView: UIViewRepresentable {
    let data: Data
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CustomScrollView()
        scrollView.delegate = context.coordinator
        
        let imageView = FLAnimatedImageView()
        if let animatedImage = FLAnimatedImage(animatedGIFData: data) {
            imageView.animatedImage = animatedImage
        }
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: imageView.animatedImage?.size ?? .zero)
        scrollView.addSubview(imageView)
        
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        // Calculate initial zoom scale
        if let size = imageView.animatedImage?.size {
            let widthScale = UIScreen.main.bounds.width / size.width
            let heightScale = UIScreen.main.bounds.height / size.height
            let minScale = min(widthScale, heightScale)
            
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = 5.0
            
            // Set content size to image size
            scrollView.contentSize = size
            
            // Set initial zoom scale
            scrollView.zoomScale = minScale
        }
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if let imageView = context.coordinator.imageView,
           let animatedImage = FLAnimatedImage(animatedGIFData: data) {
            imageView.animatedImage = animatedImage
            context.coordinator.updateZoomScaleForSize(scrollView.bounds.size)
        }
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: AnimatedImageScrollView
        weak var imageView: FLAnimatedImageView?
        weak var scrollView: UIScrollView?
        
        init(_ parent: AnimatedImageScrollView) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func updateZoomScaleForSize(_ size: CGSize) {
            guard let imageView = imageView,
                  let animatedImage = imageView.animatedImage,
                  let scrollView = scrollView,
                  size.width > 0,
                  size.height > 0,
                  animatedImage.size.width > 0,
                  animatedImage.size.height > 0 else { return }
            
            let widthScale = size.width / animatedImage.size.width
            let heightScale = size.height / animatedImage.size.height
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
                let w = size.width / (scrollView.maximumZoomScale / 5)
                let h = size.height / (scrollView.maximumZoomScale / 5)
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
