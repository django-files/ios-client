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
    @State private var isPreviewing: Bool = false
    @State private var fileDetails: DFFile?
    
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
            loadFileDetails()
            isPreviewing = true
        }
        .onDisappear {
            isPreviewing = false
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
            } else if mimeType.starts(with: "audio/") {
                audioPreview
            } else {
                genericFilePreview
            }
        }
        .sheet(isPresented: showFileInfo, onDismiss: { showFileInfo.wrappedValue = false }) {
            if let details = fileDetails {
                PreviewFileInfo(file: details)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            } else {
                PreviewFileInfo(file: file)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
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
    
    // Audio Preview
    private var audioPreview: some View {
        AudioPlayerView(url: fileURL)
            .padding()
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
        
        // For video, audio, and audio, we don't need to download the content as we'll use the URL directly
        if mimeType.starts(with: "video/") || mimeType.starts(with: "audio/") {
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

    private func loadFileDetails() {
        guard let serverURL = URL(string: file.url)?.host else { return }
        
        // Construct the base URL from the file's URL
        let baseURL = URL(string: "https://\(serverURL)")!
        
        // Create DFAPI instance
        let api = DFAPI(url: baseURL, token: "")  // Token will be handled by cookies
        
        Task {
            if let details = await api.getFileDetails(fileID: file.id) {
                await MainActor.run {
                    self.fileDetails = details
                }
            }
        }
    }
}

struct PreviewFileInfo: View {
    let file: DFFile
    
    // Helper function to format EXIF date string
    private func formatExifDate(_ dateString: String) -> String {
        let exifFormatter = DateFormatter()
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        
        guard let date = exifFormatter.date(from: dateString) else {
            return dateString
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper function to convert decimal to fraction string
    private func formatExposureTime(_ exposure: String) -> String {
        if let value = Double(exposure) {
            if value >= 1 {
                return "\(Int(value))"
            } else {
                let denominator = Int(round(1.0 / value))
                return "1/\(denominator)"
            }
        }
        return exposure
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(file.name)")
                .font(.title)
            HStack {
                HStack {
                    Image(systemName: "document")
                        .frame(width: 20, height: 20)
                    Text("\(file.mime)")
                }
                if file.password != "" {
                    Image(systemName: "key")
                        .frame(width: 20, height: 20)
                }
                if file.private {
                    Image(systemName: "lock")
                        .frame(width: 20, height: 20)
                }
                if file.expr != "" {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .frame(width: 20, height: 20)
                }
                if file.maxv != 0 {
                    HStack {
                        Image(systemName: "eye.circle")
                            .frame(width: 20, height: 20)
                        Text("Max Views: \(String(file.maxv))")
                    }
                }
            }
            HStack {
                HStack {
                    Image(systemName: "person")
                        .frame(width: 20, height: 20)
                    Text("\(file.userUsername)")
                }
                Spacer()
                HStack {
                    Image(systemName: "eye")
                        .frame(width: 20, height: 20)
                    Text("\(file.view)")
                }
                Spacer()
                HStack {
                    Image(systemName: "internaldrive")
                        .frame(width: 20, height: 20)
                    Text(file.formatSize())
                }
            }

            HStack {
                Image(systemName: "calendar")
                    .frame(width: 20, height: 20)
                Text("\(file.formattedDate())")
            }
            
            // Photo Information Section
            if let dateTime = file.exif?["DateTimeOriginal"]?.value as? String {
                HStack {
                    Image(systemName: "camera")
                        .frame(width: 20, height: 20)
                    Text("Captured: \(formatExifDate(dateTime))")
                }
            }
            
            if let gpsArea = file.meta?["GPSArea"]?.value as? String {
                HStack {
                    Image(systemName: "location")
                        .frame(width: 20, height: 20)
                    Text(gpsArea)
                }
            }
            
            if let elevation = file.exif?["GPSInfo"]?.value as? [String: Any],
               let altitude = elevation["6"] as? Double {
                HStack{
                    Image(systemName: "mountain.2")
                        .frame(width: 20, height: 20)
                    Text(String(format: "Elevation: %.1f m", altitude))
                }
            }
            
            // Camera Information Section
            Group {
                if let model = file.exif?["Model"]?.value as? String {
                    let make = file.exif?["Make"]?.value as? String ?? ""
                    let cameraName = make.isEmpty || model.contains(make) ? model : "\(make) \(model)"
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text("Camera: \(cameraName)")
                    }
                }
                
                if let lens = file.exif?["LensModel"]?.value as? String {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text("Lens: \(lens)")
                    }
                }
                
                if let focalLength = file.exif?["FocalLength"]?.value as? Double {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text(String(format: "Focal Length: %.0fmm", focalLength))
                    }
                }
                
                if let fNumber = file.exif?["FNumber"]?.value as? Double {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text(String(format: "Aperture: 𝑓%.1f", fNumber))
                    }
                }
                
                if let iso = file.exif?["ISOSpeedRatings"]?.value as? Int {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text("ISO: \(iso)")
                    }
                }
                
                if let exposureTime = file.exif?["ExposureTime"]?.value as? String {
                    HStack {
                        Image(systemName: "camera.aperture")
                            .frame(width: 20, height: 20)
                        Text("Exposure: \(formatExposureTime(exposureTime))s")
                    }
                }
                
                if let software = file.exif?["Software"]?.value as? String {
                    HStack {
                        Image(systemName: "app")
                            .frame(width: 20, height: 20)
                        Text("Software: \(software)")
                    }
                }
            }
            
            if !file.info.isEmpty {
                Text(file.info)
            }
        }
        .padding(40)
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

// Custom Audio Player View
struct AudioPlayerView: View {
    let url: URL
    @StateObject private var playerViewModel = AudioPlayerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundColor(.gray)
                .padding(.bottom)

            HStack {
                Text(playerViewModel.currentTimeString)
                    .font(.caption)
                    .monospacedDigit()
                
                Slider(value: $playerViewModel.progress, in: 0...1) { editing in
                    if !editing {
                        playerViewModel.seek(to: playerViewModel.progress)
                    }
                }
                
                Text(playerViewModel.durationString)
                    .font(.caption)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            
            // Playback Controls
            HStack(spacing: 30) {
                Button(action: { playerViewModel.skipBackward() }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button(action: { playerViewModel.togglePlayback() }) {
                    Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                
                Button(action: { playerViewModel.skipForward() }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
        }
        .onAppear {
            playerViewModel.setupPlayer(with: url)
        }
        .onDisappear {
            playerViewModel.cleanup()
        }
    }
}

// Audio Player View Model
class AudioPlayerViewModel: ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObserver: NSKeyValueObservation?
    
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTimeString = "00:00"
    @Published var durationString = "00:00"
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func setupPlayer(with url: URL) {
        configureAudioSession()
        player = AVPlayer(url: url)
        
        // Add periodic time observer
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self,
                  let duration = self.player?.currentItem?.duration.seconds,
                  !duration.isNaN else { return }
            
            let currentTime = time.seconds
            self.progress = currentTime / duration
            self.currentTimeString = self.formatTime(currentTime)
            self.durationString = self.formatTime(duration)
        }
        
        // Observe player item status for completion
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem,
                                             queue: .main) { [weak self] _ in
            self?.handlePlaybackCompletion()
        }
        
        // Update duration when item is ready
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) as? CMTime,
               !duration.seconds.isNaN {
                await MainActor.run {
                    self.durationString = self.formatTime(duration.seconds)
                }
            }
        }
    }
    
    private func handlePlaybackCompletion() {
        isPlaying = false
        // Reset to beginning
        seek(to: 0)
    }
    
    func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            // If we're at the end, seek to beginning before playing
            if let currentTime = player?.currentTime().seconds,
               let duration = player?.currentItem?.duration.seconds,
               currentTime >= duration {
                seek(to: 0)
            }
            player?.play()
            isPlaying = true
        }
    }
    
    func seek(to progress: Double) {
        guard let duration = player?.currentItem?.duration else { return }
        let time = CMTime(seconds: progress * duration.seconds, preferredTimescale: 600)
        player?.seek(to: time)
    }
    
    func skipForward() {
        guard let currentTime = player?.currentTime().seconds else { return }
        seek(to: (currentTime + 15) / (player?.currentItem?.duration.seconds ?? currentTime + 15))
    }
    
    func skipBackward() {
        guard let currentTime = player?.currentTime().seconds else { return }
        seek(to: (currentTime - 15) / (player?.currentItem?.duration.seconds ?? currentTime))
    }
    
    func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        player = nil
    }
    
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds / 60)
        let seconds = Int(timeInSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
