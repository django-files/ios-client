import SwiftUI
import AVKit
import HighlightSwift
import UIKit

extension UIPageViewController {
    var scrollView: UIScrollView? {
        return view.subviews.first { $0 is UIScrollView } as? UIScrollView
    }
}


struct ContentPreview: View {
    let mimeType: String
    let fileURL: URL
    let file: DFFile
    var showFileInfo: Binding<Bool>
    @Binding var selectedFileDetails: DFFile?
    @Binding var isContentScrolling: Bool

    @State private var content: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0
    @State private var isPreviewing: Bool = false
    @State private var fileDetails: DFFile?
    @State private var videoPlayRequested = false
    
    var body: some View {
        Group {
            contentView
        }
        .onAppear {
//            print("📱 ContentPreview: View appeared - URL: \(fileURL)")
            loadContent()
            loadFileDetails()
            isPreviewing = true
        }
        .onDisappear {
//            print("👋 ContentPreview: View disappeared")
            isPreviewing = false
        }
    }

    // Determine the appropriate view based on MIME type
    private var contentView: some View {
        Group {
            if mimeType == "application/pdf" {
                pdfPreview
            } else if mimeType.starts(with: "text/") || (mimeType.starts(with: "application/") && mimeType.contains("json")) {
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
        .ignoresSafeArea()
        .id(fileURL)
    }

    // Text Preview
    private var textPreview: some View {
        TextPreview(
            content: content,
            mimeType: mimeType,
            fileName: fileURL.lastPathComponent,
            isLoading: isLoading,
            error: error,
            isContentScrolling: $isContentScrolling
        )
        .background(.black)
    }

    private var imagePreview: some View {
        GeometryReader { geometry in
            if let content = content {
                if mimeType == "image/gif" {
                    AnimatedImageScrollView(data: content)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let uiImage = UIImage(data: content) {
                    ImageScrollView(image: uiImage, isContentScrolling: $isContentScrolling)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Text("Unable to load image")
                }
            } else if error != nil {
                Text("Unable to load image \(String(describing: error))")
            }
        }
        .ignoresSafeArea()
        .background(.black)
    }
    
    // Video Preview
    private var videoPreview: some View {
        GeometryReader { geometry in
            ZStack {
                if videoPlayRequested {
                    VideoPlayerView(url: fileURL, isLoading: $isLoading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .padding(.top, geometry.size.height > geometry.size.width ? 100 : 0)

                    if isLoading {
                        LoadingView()
                            .frame(width: 100, height: 100)
                    }
                } else {
                    if let thumbURL = URL(string: file.thumb), !file.thumb.isEmpty {
                        CachedAsyncImage(url: thumbURL) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Color.black
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Button(action: { videoPlayRequested = true }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.white)
                            .shadow(radius: 10)
                    }
                }
            }
        }
        .background(.black)
    }
    
    // Audio Preview
    private var audioPreview: some View {
        AudioPlayerView(url: fileURL)
            .padding()
            .background(.black)
    }
    
    // PDF Preview
    private var pdfPreview: some View {
        PDFView(url: fileURL)
            .padding(.top, 45)
            .background(.black)

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
        .background(.black)
    }
    
    private func loadContent() {
//        print("📥 ContentPreview: Starting content load")
        
        // For video, audio, and PDF, we don't need to download the content as we'll use the URL directly
        if mimeType.starts(with: "video/") || mimeType.starts(with: "audio/") || mimeType == "application/pdf" {
//            print("🎥 ContentPreview: Using direct URL for media/PDF")
            isLoading = false
            return
        }
        
        // Check if content is already cached
        if let cachedData = ImageCache.shared.getContent(for: fileURL.absoluteString) {
//            print("✅ ContentPreview: Found cached content")
            self.content = cachedData
            self.isLoading = false
            return
        }
        
//        print("📥 ContentPreview: Downloading content from URL")
        isLoading = true
        
        Task {
            do {
                let data = try await CachedContentLoader.loadContent(from: fileURL)
                await MainActor.run {
                    self.content = data
                    self.isLoading = false
                }
            } catch {
//                print("❌ ContentPreview: Download error - \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    private func loadFileDetails() {
//        print("📋 ContentPreview: Loading file details")
        guard let serverURL = URL(string: file.url)?.host else {
//            print("❌ ContentPreview: Could not extract server URL from file URL")
            return
        }
        let baseURL = URL(string: "https://\(serverURL)")!
        let api = DFAPI(url: baseURL, token: "")
        
        Task {
//            print("🌐 ContentPreview: Fetching file details from API")
            if let details = await api.getFileDetails(fileID: file.id) {
//                print("✅ ContentPreview: Successfully fetched file details")
                await MainActor.run {
                    self.fileDetails = details
                    self.selectedFileDetails = details
                }
            }
        }
    }
}

func textWidth(text: String, font: UIFont) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let size = text.size(withAttributes: attributes)
    return size.width
}

struct PageViewController: UIViewControllerRepresentable {
    var files: [DFFile]
    var currentIndex: Int
    var redirectURLs: [String: String]
    var showFileInfo: Binding<Bool>
    @Binding var selectedFileDetails: DFFile?
    @Binding var isContentScrolling: Bool
    var onPageChange: (Int) -> Void
    var onLoadMore: (() async -> Void)?
    var isDragging: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        
        if let initialVC = context.coordinator.createContentViewController(for: currentIndex) {
            pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
        }
        
        return pageViewController
    }
    
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        
        // Disable scrolling when dragging is active
        pageViewController.scrollView?.isScrollEnabled = !isDragging
        
        // Only update if the current index has changed and we're not in the middle of a transition
        if let currentVC = pageViewController.viewControllers?.first as? UIHostingController<ContentPreview>,
           let currentFileIndex = files.firstIndex(where: { $0.id == currentVC.rootView.file.id }),
           currentFileIndex != currentIndex,
           !context.coordinator.isTransitioning {
            // Update to the new index if it's different
            if let newVC = context.coordinator.createContentViewController(for: currentIndex) {
                let direction: UIPageViewController.NavigationDirection = currentFileIndex > currentIndex ? .reverse : .forward
                context.coordinator.isTransitioning = true
                pageViewController.setViewControllers([newVC], direction: direction, animated: true) { _ in
                    context.coordinator.isTransitioning = false
                }
            }
        }
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageViewController
        var isTransitioning: Bool = false
        private var preloadedViewControllers: [Int: UIHostingController<ContentPreview>] = [:]
        private var preloadTask: Task<Void, Never>?
        private var isLoadingMore: Bool = false
        
        init(_ pageViewController: PageViewController) {
            self.parent = pageViewController
            super.init()
            preloadAdjacentPages()
        }
        
        deinit {
            preloadTask?.cancel()
        }
        
        private func preloadAdjacentPages() {
            preloadTask?.cancel()
            preloadTask = Task {
                // Preload current and adjacent pages
                let indicesToPreload = [-2, -1, 0, 1, 2].map { parent.currentIndex + $0 }
                    .filter { $0 >= 0 && $0 < parent.files.count }
                
                for index in indicesToPreload {
                    if preloadedViewControllers[index] == nil {
                        await MainActor.run {
                            preloadedViewControllers[index] = createContentViewController(for: index)
                        }
                    }
                }
            }
        }
        
        func createContentViewController(for index: Int) -> UIHostingController<ContentPreview>? {
            guard index >= 0 && index < parent.files.count else { return nil }
            
            // Check if we already have a preloaded controller
            if let preloadedVC = preloadedViewControllers[index] {
                return preloadedVC
            }
            
            let file = parent.files[index]
            let contentPreview = ContentPreview(
                mimeType: file.mime,
                fileURL: URL(string: parent.redirectURLs[file.raw] ?? file.raw)!,
                file: file,
                showFileInfo: parent.showFileInfo,
                selectedFileDetails: parent.$selectedFileDetails,
                isContentScrolling: parent.$isContentScrolling
            )
            let vc = UIHostingController(rootView: contentPreview)
            vc.view.backgroundColor = .clear
            vc.view.isOpaque = false
            preloadedViewControllers[index] = vc
            
            // Trigger content loading for this view controller
            Task {
                await preloadContentForViewController(vc, file: file)
            }
            
            return vc
        }
        
        private func preloadContentForViewController(_ vc: UIHostingController<ContentPreview>, file: DFFile) async {
            // Only preload content for files that need it (not video, audio, or PDF)
            if file.mime.starts(with: "video/") || file.mime.starts(with: "audio/") || file.mime == "application/pdf" {
                return
            }
            
            let urlString = parent.redirectURLs[file.raw] ?? file.raw
            guard let url = URL(string: urlString) else { return }
            
            // Check if content is already cached
            if ImageCache.shared.getContent(for: url.absoluteString) != nil {
                return
            }
            
            // Preload the content
            do {
                let _ = try await CachedContentLoader.loadContent(from: url)
//                print("✅ PageViewController preloaded content for: \(file.name)")
            } catch {
//                print("❌ PageViewController failed to preload content for: \(file.name) - \(error.localizedDescription)")
            }
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let currentVC = viewController as? UIHostingController<ContentPreview>,
                  let currentIndex = parent.files.firstIndex(where: { $0.id == currentVC.rootView.file.id }),
                  currentIndex > 0
            else { return nil }
            
            return createContentViewController(for: currentIndex - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let currentVC = viewController as? UIHostingController<ContentPreview>,
                  let currentIndex = parent.files.firstIndex(where: { $0.id == currentVC.rootView.file.id })
            else { return nil }
            
            if currentIndex >= parent.files.count - 2 && !isLoadingMore {
                Task {
                    isLoadingMore = true
                    await parent.onLoadMore?()
                    isLoadingMore = false
                    
                    if currentIndex == parent.files.count - 2 {
                        await MainActor.run {
                            preloadedViewControllers.removeAll()
                            preloadAdjacentPages()
                            // If we're at the second-to-last file, update to show the last file
                            if let nextVC = createContentViewController(for: currentIndex + 1) {
                                pageViewController.setViewControllers([nextVC], direction: .forward, animated: false)
                            }
                        }
                    }
                }
            }
            
            if currentIndex < parent.files.count - 1 {
                return createContentViewController(for: currentIndex + 1)
            }
            
            return nil
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? UIHostingController<ContentPreview>,
                  let currentIndex = parent.files.firstIndex(where: { $0.id == currentVC.rootView.file.id })
            else { return }
            
            parent.onPageChange(currentIndex)
            preloadAdjacentPages()
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }
    }
}

extension View {
    @ViewBuilder
    func adaptiveSystemButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

struct FilePreviewView: View {
    @Binding var file: DFFile
    let server: Binding<DjangoFilesSession?>
    @Binding var showingPreview: Bool
    @Binding var showFileInfo: Bool
    let fileListDelegate: FileListDelegate?
    @Binding var allFiles: [DFFile]
    let currentIndex: Int
    let onNavigate: (Int) -> Void
    let onLoadMore: (() async -> Void)?
    
    init(file: Binding<DFFile>, server: Binding<DjangoFilesSession?>, showingPreview: Binding<Bool>, showFileInfo: Binding<Bool>, fileListDelegate: FileListDelegate?, allFiles: Binding<[DFFile]>, currentIndex: Int, onNavigate: @escaping (Int) -> Void, onLoadMore: (() async -> Void)? = nil) {
        self._file = file
        self.server = server
        self._showingPreview = showingPreview
        self._showFileInfo = showFileInfo
        self.fileListDelegate = fileListDelegate
        self._allFiles = allFiles
        self.currentIndex = currentIndex
        self.onNavigate = onNavigate
        self.onLoadMore = onLoadMore
    }
    
    @State private var redirectURLs: [String: String] = [:]
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var selectedFileDetails: DFFile?
    
    @State private var showingDeleteConfirmation = false
    @State private var fileIDsToDelete: [Int] = []
    @State private var fileNameToDelete: String = ""
    
    @State private var showingExpirationDialog = false
    @State private var expirationText = ""
    @State private var fileToExpire: DFFile? = nil
    
    @State private var showingPasswordDialog = false
    @State private var passwordText = ""
    @State private var fileToPassword: DFFile? = nil
    
    @State private var showingRenameDialog = false
    @State private var fileNameText = ""
    @State private var fileToRename: DFFile? = nil
    
    @State private var showingShareSheet = false
    
    @State private var isOverlayVisible = true
    @State private var isContentScrolling = false
    
    @State private var marqueeOffset = 3.0
    @State private var animationID = UUID()
    
    private var isDeepLinkPreview: Bool {
        fileListDelegate == nil
    }
    
    private func resetMarqueeAnimation() {
        // Generate new animation ID to cancel previous animations
        animationID = UUID()
        
        // Immediately reset the offset to initial position without animation
        marqueeOffset = 3.0
        
        // Start animation if filename is long enough
        if file.name.count > 26 {
            // Use a slight delay to ensure the reset happens first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let baseAnimation = Animation.linear(duration: 8).delay(6).repeatForever()
                withAnimation(baseAnimation) {
                    marqueeOffset = -textWidth(text: file.name, font: UIFont.systemFont(ofSize: 5))
                }
            }
        }
    }
    
    @MainActor
    private func preloadFiles() async {
        // Load the current file and preload adjacent files
        let filesToLoad = [-2, -1, 0, 1, 2]
            .map { currentIndex + $0 }
            .filter { $0 >= 0 && $0 < allFiles.count }
            .map { allFiles[$0] }
        
        await withTaskGroup(of: Void.self) { group in
            for fileToLoad in filesToLoad {
                group.addTask {
                    await loadSingleFileRedirect(fileToLoad)
                    // Also preload content for files that need it
                    await preloadFileContent(fileToLoad)
                }
            }
        }
    }
    
    @MainActor
    private func preloadFileContent(_ file: DFFile) async {
        // Only preload content for files that need it (not video, audio, or PDF)
        if file.mime.starts(with: "video/") || file.mime.starts(with: "audio/") || file.mime == "application/pdf" {
            return
        }
        
        // Get the redirect URL if available, otherwise use the raw URL
        let urlString = redirectURLs[file.raw] ?? file.raw
        guard let url = URL(string: urlString) else { return }
        
        // Check if content is already cached
        if ImageCache.shared.getContent(for: url.absoluteString) != nil {
            return
        }
        
        // Preload the content
        do {
            let _ = try await CachedContentLoader.loadContent(from: url)
//            print("✅ Preloaded content for: \(file.name)")
        } catch {
//            print("❌ Failed to preload content for: \(file.name) - \(error.localizedDescription)")
        }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    if redirectURLs[file.raw] == nil {
                        LoadingView()
                        .frame(width: 100, height: 100)
                        .onAppear {
                            Task {
                                await preloadFiles()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ZStack {
                    PageViewController(
                        files: allFiles,
                        currentIndex: currentIndex,
                        redirectURLs: redirectURLs,
                        showFileInfo: $showFileInfo,
                        selectedFileDetails: $selectedFileDetails,
                        isContentScrolling: $isContentScrolling,
                        onPageChange: { newIndex in
                            onNavigate(newIndex)
                            Task {
                                await preloadFiles()
                            }
                        },
                        onLoadMore: onLoadMore,
                        isDragging: isDragging
                    )
                    .ignoresSafeArea()
                    .background(.black)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isOverlayVisible.toggle()
                        }
                    }
                    .background(
                        FileDialogs(
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            fileIDsToDelete: $fileIDsToDelete,
                            fileNameToDelete: $fileNameToDelete,
                            showingExpirationDialog: $showingExpirationDialog,
                            expirationText: $expirationText,
                            fileToExpire: $fileToExpire,
                            showingPasswordDialog: $showingPasswordDialog,
                            passwordText: $passwordText,
                            fileToPassword: $fileToPassword,
                            showingRenameDialog: $showingRenameDialog,
                            fileNameText: $fileNameText,
                            fileToRename: $fileToRename,
                            onDelete: { fileIDs in
                                if await deleteFiles(fileIDs: fileIDs) {
                                    showingPreview = false
                                    return true
                                }
                                return false
                            },
                            onSetExpiration: { file, expr in
                                await setFileExpr(file: file, expr: expr)
                            },
                            onSetPassword: { file, password in
                                await setFilePassword(file: file, password: password)
                            },
                            onRename: { file, name in
                                await renameFile(file: file, name: name)
                            }
                        )
                    )
            }
            .onChange(of: currentIndex) { _, _ in
                // Preload files when current index changes externally
                Task {
                    await preloadFiles()
                }
            }
            .sheet(isPresented: $showFileInfo) {
                if let details = selectedFileDetails {
                    PreviewFileInfo(file: details)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                } else {
                    PreviewFileInfo(file: file)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        showingPreview = false
                    }) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        showFileInfo = true
                    }) {
                        VStack {
                            Text(file.name)
                                .hidden()
                                .overlay(alignment: file.name.count > 26 ? .leading : .center) {
                                    Text(file.name)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .font(.subheadline)

                                }
                                .offset(x: file.name.count > 26 ? marqueeOffset : 0)
                                .id(animationID)
                                .onAppear {
                                    resetMarqueeAnimation()
                                }
                                .onChange(of: file.name) { _, _ in
                                    resetMarqueeAnimation()
                                }
                                .mask(
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .clear, location: 0.0),   // Fades in from left
                                            .init(color: .black, location: file.name.count < 26 ? 0.0 : 0.04),   // Fully visible area starts
                                            .init(color: .black, location: file.name.count < 26 ? 1.0 : 0.96),   // Fully visible area ends
                                            .init(color: .clear, location: 1.0)    // Fades out on right
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(maxWidth: .infinity)
                            
                            ZStack {
                                Text(file.formattedDate())
                                    .font(.caption)
                            }
//                            if let gpsArea = file.meta?["GPSArea"]?.value as? String {
//                                Text(gpsArea)
//                                    .font(.custom("SF Pro", size: 11, relativeTo: .caption))
//                            }
                        }
                    }
                    .frame(minWidth: 200)
                    .adaptiveSystemButtonStyle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isDeepLinkPreview {
                        Menu {
                            fileContextMenu(for: file, isPreviewing: true, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(Color.white)
                        }

                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .sheet(isPresented: $showingShareSheet) {
                        if let url = URL(string: file.url) {
                            ShareSheet(url: url)
                                .presentationDetents([.medium])
                        }
                    }
                    Spacer()
//                    Menu {
//                        fileShareMenu(for: file)
//                    } label: {
//                        Image(systemName: "link.icloud")
//                    }
//                    Button(action: {
//                        showFileInfo = true
//                    }) {
//                        Image(systemName: "info.circle")
//                    }
//                    Spacer()
                    Button(action: {
                        fileIDsToDelete = [file.id]
                        fileNameToDelete = file.name
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                    }
                }
            }
            .toolbarVisibility(isOverlayVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarVisibility(isOverlayVisible ? .visible : .hidden, for: .bottomBar)
            }
        }
       .offset(dragOffset)
       .simultaneousGesture(
           DragGesture(minimumDistance: 100)
               .onChanged { gesture in
                   // Don't trigger dismiss if content is currently scrolling
                   guard !isContentScrolling else { return }
                   
                   // Only trigger dismiss if gesture is clearly a dismiss intent
                   // Check if this is a vertical downward gesture with minimal horizontal movement
                   let isVerticalGesture = abs(gesture.translation.height) > abs(gesture.translation.width) * 2
                   let isDownwardGesture = gesture.translation.height > 0
                   let hasMinimalHorizontalMovement = abs(gesture.translation.width) < 20
                   
                   if isVerticalGesture && isDownwardGesture && hasMinimalHorizontalMovement && gesture.translation.height > 15 {
                       dragOffset = gesture.translation
                       isDragging = true
                   }
               }
               .onEnded { gesture in
                   isDragging = false
                   
                   // Don't dismiss if content was scrolling
                   guard !isContentScrolling else {
                       dragOffset = .zero
                       return
                   }
                   
                   // Only dismiss if gesture was clearly a dismiss intent
                   let isVerticalGesture = abs(gesture.translation.height) > abs(gesture.translation.width) * 2
                   let isDownwardGesture = gesture.translation.height > 0
                   let hasMinimalHorizontalMovement = abs(gesture.translation.width) < 30
                   
                   if isVerticalGesture && isDownwardGesture && hasMinimalHorizontalMovement && gesture.translation.height > 120 {
                       withAnimation(.spring()) {
                           showingPreview = false
                       }
                   } else {
                       withAnimation(.spring()) {
                           dragOffset = .zero
                       }
                   }
               }
       )
    }
    
    @MainActor
    private func loadSingleFileRedirect(_ file: DFFile) async {
        guard redirectURLs[file.raw] == nil else {
            return
        }
        
        // For deep link previews without a server session, use the raw URL directly
        if server.wrappedValue == nil {
            redirectURLs[file.raw] = file.raw
            return
        }
        
        guard let serverURL = URL(string: file.url)?.host else {
            return
        }
        
        let baseURL = URL(string: "https://\(serverURL)")!
        let api = DFAPI(url: baseURL, token: "")  // Token will be handled by cookies
        
        if let redirectURL = await api.checkRedirect(url: file.raw) {
            redirectURLs[file.raw] = redirectURL
        } else {
            // If redirect fails, use the original URL
            redirectURLs[file.raw] = file.raw
        }
    }
    
    @MainActor
    private func toggleFilePrivacy(file: DFFile) async {
        if let delegate = fileListDelegate {
            let _ = await delegate.setFilePrivate(fileID: file.id, isPrivate: !file.private, onSuccess: nil)
        } else {
            guard let serverInstance = server.wrappedValue,
                  let url = URL(string: serverInstance.url) else {
                return
            }
            let api = DFAPI(url: url, token: serverInstance.token)
            let _ = await api.editFiles(fileIDs: [file.id], changes: ["private": !file.private], selectedServer: serverInstance)
        }
    }
    
    @MainActor
    private func setFileExpr(file: DFFile, expr: String?) async {
        if let delegate = fileListDelegate {
            let _ = await delegate.setFileExpiration(fileID: file.id, expr: expr ?? "", onSuccess: nil)
        } else {
            guard let serverInstance = server.wrappedValue,
                  let url = URL(string: serverInstance.url) else {
                return
            }
            let api = DFAPI(url: url, token: serverInstance.token)
            let _ = await api.editFiles(fileIDs: [file.id], changes: ["expr": expr ?? ""], selectedServer: serverInstance)
        }
    }
    
    @MainActor
    private func setFilePassword(file: DFFile, password: String?) async {
        if let delegate = fileListDelegate {
            let _ = await delegate.setFilePassword(fileID: file.id, password: password ?? "", onSuccess: nil)
        } else {
            guard let serverInstance = server.wrappedValue,
                  let url = URL(string: serverInstance.url) else {
                return
            }
            let api = DFAPI(url: url, token: serverInstance.token)
            let _ = await api.editFiles(fileIDs: [file.id], changes: ["password": password ?? ""], selectedServer: serverInstance)
        }
    }
    
    
    @MainActor
    private func renameFile(file: DFFile, name: String) async {
        if let delegate = fileListDelegate {
            let _ = await delegate.renameFile(fileID: file.id, newName: name, onSuccess: nil)
        } else {
            guard let serverInstance = server.wrappedValue,
                  let url = URL(string: serverInstance.url) else {
                return
            }
            let api = DFAPI(url: url, token: serverInstance.token)
            let _ = await api.renameFile(fileID: file.id, name: name, selectedServer: serverInstance)
        }
    }
    
    @MainActor
    private func deleteFiles(fileIDs: [Int]) async -> Bool {
        if let delegate = fileListDelegate {
            return await delegate.deleteFiles(fileIDs: fileIDs) {
                // No additional success callback needed as the delegate handles list updates
            }
        } else {
            return false
        }
    }
    
    private func fileContextMenu(for file: DFFile, isPreviewing: Bool, isPrivate: Bool, expirationText: Binding<String>, passwordText: Binding<String>, fileNameText: Binding<String>) -> FileContextMenuButtons {
        FileContextMenuButtons(
            isPreviewing: isPreviewing,
            isPrivate: isPrivate,
            onPreview: {
                // No-op since we're already previewing
            },
            onCopyShareLink: {
                UIPasteboard.general.string = file.url
            },
            onCopyRawLink: {
                if redirectURLs[file.raw] == nil {
                    Task {
                        await loadSingleFileRedirect(file)
                        // Only copy the URL after we've loaded the redirect
                        if let redirectURL = redirectURLs[file.raw] {
                            await MainActor.run {
                                UIPasteboard.general.string = redirectURL
                            }
                        } else {
                            await MainActor.run {
                                UIPasteboard.general.string = file.raw
                            }
                        }
                    }
                } else if let redirectURL = redirectURLs[file.raw] {
                    UIPasteboard.general.string = redirectURL
                } else {
                    UIPasteboard.general.string = file.raw
                }
            },
            openRawBrowser: {
                if let url = URL(string: file.raw), UIApplication.shared.canOpenURL(url) {
                    if redirectURLs[file.raw] == nil {
                        Task {
                            await loadSingleFileRedirect(file)
                            // Only open the URL after we've loaded the redirect
                            if let redirectURL = redirectURLs[file.raw], let finalURL = URL(string: redirectURL) {
                                await MainActor.run {
                                    UIApplication.shared.open(finalURL)
                                }
                            } else {
                                await MainActor.run {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } else if let redirectURL = redirectURLs[file.raw], let finalURL = URL(string: redirectURL) {
                        UIApplication.shared.open(finalURL)
                    } else {
                        UIApplication.shared.open(url)
                    }
                }
            },
            onTogglePrivate: {
                Task {
                    await toggleFilePrivacy(file: file)
                }
            },
            setExpire: {
                fileToExpire = file
                expirationText.wrappedValue = fileToExpire?.expr ?? ""
                showingExpirationDialog = true
            },
            setPassword: {
                fileToPassword = file
                passwordText.wrappedValue = fileToPassword?.password ?? ""
                showingPasswordDialog = true
            },
            renameFile: {
                fileToRename = file
                fileNameText.wrappedValue = fileToRename?.name ?? ""
                showingRenameDialog = true
            },
            deleteFile: {
                fileIDsToDelete = [file.id]
                fileNameToDelete = file.name
                showingDeleteConfirmation = true
            }
        )
    }
    
    private func fileShareMenu(for file: DFFile) -> FileShareMenu {
        FileShareMenu(
            onCopyShareLink: {
                UIPasteboard.general.string = file.url
            },
            onCopyRawLink: {
                if redirectURLs[file.raw] == nil {
                    Task {
                        await loadSingleFileRedirect(file)
                        // Only copy the URL after we've loaded the redirect
                        if let redirectURL = redirectURLs[file.raw] {
                            await MainActor.run {
                                UIPasteboard.general.string = redirectURL
                            }
                        } else {
                            await MainActor.run {
                                UIPasteboard.general.string = file.raw
                            }
                        }
                    }
                } else if let redirectURL = redirectURLs[file.raw] {
                    UIPasteboard.general.string = redirectURL
                } else {
                    UIPasteboard.general.string = file.raw
                }
            },
            openRawBrowser: {
                if let url = URL(string: file.raw), UIApplication.shared.canOpenURL(url) {
                    if redirectURLs[file.raw] == nil {
                        Task {
                            await loadSingleFileRedirect(file)
                            // Only open the URL after we've loaded the redirect
                            if let redirectURL = redirectURLs[file.raw], let finalURL = URL(string: redirectURL) {
                                await MainActor.run {
                                    UIApplication.shared.open(finalURL)
                                }
                            } else {
                                await MainActor.run {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } else if let redirectURL = redirectURLs[file.raw], let finalURL = URL(string: redirectURL) {
                        UIApplication.shared.open(finalURL)
                    } else {
                        UIApplication.shared.open(url)
                    }
                }
            }
        )
    }
}

// PDF View SwiftUI Wrapper


struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ActivityViewController(activityItems: [url])
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


