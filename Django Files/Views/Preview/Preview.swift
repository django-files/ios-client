import SwiftUI
import AVKit
import HighlightSwift
import UIKit


struct ContentPreview: View {
    let mimeType: String
    let fileURL: URL
    let file: DFFile
    var showFileInfo: Binding<Bool>
    @Binding var selectedFileDetails: DFFile?

    @State private var content: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0
    @State private var isPreviewing: Bool = false
    @State private var fileDetails: DFFile?
    
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
                    .padding(.top, 60)
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
            fileName: fileURL.lastPathComponent
        )
    }

    private var imagePreview: some View {
        GeometryReader { geometry in
            if let content = content {
                if mimeType == "image/gif" {
                    AnimatedImageScrollView(data: content)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if let uiImage = UIImage(data: content) {
                    ImageScrollView(image: uiImage)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Text("Unable to load image")
                }
            } else {
                Text("Unable to load image")
            }
        }
        .ignoresSafeArea()
    }
    
    // Video Preview
    private var videoPreview: some View {
        GeometryReader { geometry in
            ZStack {
                VideoPlayerView(url: fileURL, isLoading: $isLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .padding(.top, geometry.size.height > geometry.size.width ? 100 : 0)
                
                if isLoading {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            LoadingView()
                                .frame(width: 100, height: 100)
                            Spacer()
                        }
                        Spacer()
                    }
                    .background(Color.black.opacity(0.3))
                }
            }
        }
    }
    
    // Audio Preview
    private var audioPreview: some View {
        AudioPlayerView(url: fileURL)
            .padding()
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

struct PageViewController: UIViewControllerRepresentable {
    var files: [DFFile]
    var currentIndex: Int
    var redirectURLs: [String: String]
    var showFileInfo: Binding<Bool>
    @Binding var selectedFileDetails: DFFile?
    var onPageChange: (Int) -> Void
    var onLoadMore: (() async -> Void)?
    
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
                selectedFileDetails: parent.$selectedFileDetails
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
    @GestureState private var dragState = DragState.inactive
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
    
    private var isDeepLinkPreview: Bool {
        fileListDelegate == nil
    }
    
    private enum DragState {
        case inactive
        case dragging(translation: CGSize)
        
        var translation: CGSize {
            switch self {
            case .inactive:
                return .zero
            case .dragging(let translation):
                return translation
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
        GeometryReader { geometry in
            ZStack {
                if redirectURLs[file.raw] == nil {
                    VStack{
                        Spacer()

                        HStack{
                            Spacer()
                            LoadingView()
                                .frame(width: 100, height: 100)

                            Spacer()
                        }
                        Spacer()
                    }
                    .onAppear {
                        Task {
                            await preloadFiles()
                        }
                    }

                } else {
                    PageViewController(
                        files: allFiles,
                        currentIndex: currentIndex,
                        redirectURLs: redirectURLs,
                        showFileInfo: $showFileInfo,
                        selectedFileDetails: $selectedFileDetails,
                        onPageChange: { newIndex in
                            onNavigate(newIndex)
                            Task {
                                await preloadFiles()
                            }
                        },
                        onLoadMore: onLoadMore
                    )
                    .ignoresSafeArea()
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

                    ZStack(alignment: .top) {
                        if isOverlayVisible {
                            VStack {
                                HStack{
                                    Button(action: {
                                        showingPreview = false
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 17))
                                            .foregroundColor(.blue)
                                            .padding()
                                    }
                                    .background(.ultraThinMaterial)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(16)
                                    .padding(.leading, 15)
                                    Spacer()
                                    Text(file.name)
                                        .padding(5)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .foregroundColor(file.mime.starts(with: "text") ? .primary : .white)
                                        .shadow(color: .black, radius: file.mime.starts(with: "text") ? 0 : 3)
                                    Spacer()
                                    Menu {
                                        fileContextMenu(for: file, isPreviewing: true, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                            .padding()
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 20))
                                            .padding()
                                    }
                                    .menuStyle(.button)
                                    .background(.ultraThinMaterial)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(16)
                                    .padding(.trailing, 10)
                                }
                                .background(.ultraThinMaterial)
                                .frame(width: 32, height: 32)
                                .cornerRadius(16)
                                .padding(.leading, 15)
                                Spacer()
                                Text(file.name)
                                    .padding(5)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .foregroundColor(file.mime.starts(with: "text") ? .primary : .white)
                                    .shadow(color: .black, radius: file.mime.starts(with: "text") ? 0 : 3)
                                Spacer()
                                if !isDeepLinkPreview {
                                    Menu {
                                        fileContextMenu(for: file, isPreviewing: true, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                            .padding()
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 20))
                                            .padding()
                                    }
                                    .menuStyle(.button)
                                    .background(.ultraThinMaterial)
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(16)
                                    .padding(.trailing, 10)
                                }
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background {
                                if file.mime.starts(with: "text") || file.mime.starts(with: "application") {
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .ignoresSafeArea()
                                }
                            }
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: {
                                    showFileInfo = true
                                }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 20))
                                        .padding(8)
                                }
                                .buttonStyle(.borderless)
                                
                                Menu {
                                    fileShareMenu(for: file)
                                } label: {
                                    Image(systemName: "link.icloud")
                                        .font(.system(size: 20))
                                        .padding(8)
                                }
                                .menuStyle(.button)
                                
                                Button(action: {
                                    showingShareSheet = true
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 20))
                                        .offset(y: -2)
                                        .padding(8)
                                }
                                .buttonStyle(.borderless)
                                .padding(.leading, 1)
                                .sheet(isPresented: $showingShareSheet) {
                                    if let url = URL(string: file.url) {
                                        ShareSheet(url: url)
                                            .presentationDetents([.medium])
                                    }
                                }
                                Spacer()
                                // Only show bottom overlay for non-video content to avoid covering video controls
                                if !file.mime.starts(with: "video/") {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            showFileInfo = true
                                        }) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 20))
                                                .padding(8)
                                        }
                                        .buttonStyle(.borderless)
                                        
                                        Menu {
                                            fileShareMenu(for: file)
                                        } label: {
                                            Image(systemName: "link.icloud")
                                                .font(.system(size: 20))
                                                .padding(8)
                                        }
                                        .menuStyle(.button)
                                        
                                        Button(action: {
                                            showingShareSheet = true
                                        }) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 20))
                                                .offset(y: -2)
                                                .padding(8)
                                        }
                                        .buttonStyle(.borderless)
                                        .padding(.leading, 1)
                                        .sheet(isPresented: $showingShareSheet) {
                                            if let url = URL(string: file.url) {
                                                ShareSheet(url: url)
                                                    .presentationDetents([.medium])
                                            }
                                        }
                                        Spacer()
                                    }
                                    .background(.ultraThinMaterial)
                                    .frame(width: 155, height: 44)
                                    .cornerRadius(25)
                                }
                            }
                        }
                    }
                }
            }
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragState) { value, state, _ in
                        state = .dragging(translation: value.translation)
                    }
                    .onChanged { value in
                        let translation = value.translation
                        // Only allow vertical dragging with initial resistance
                        let dampingFactor: CGFloat = 0.5 // Increase this value for more resistance
                        let dampenedHeight = pow(translation.height, dampingFactor) * 8
                        dragOffset = CGSize(width: 0, height: max(0, dampenedHeight))
                    }
                    .onEnded { value in
                        let translation = value.translation
                        let velocity = CGSize(
                            width: value.predictedEndLocation.x - value.location.x,
                            height: value.predictedEndLocation.y - value.location.y
                        )
                        
                        // Only handle vertical gestures for dismissal
                        let progress = translation.height / geometry.size.height
                        let velocityThreshold: CGFloat = 300
                        let progressThreshold: CGFloat = 0.3
                        
                        if progress > progressThreshold || velocity.height > velocityThreshold {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = CGSize(width: 0, height: geometry.size.height)
                                showingPreview = false
                            }
                        } else {
                            // Reset position if not dismissed
                            withAnimation(.spring()) {
                                dragOffset = .zero
                            }
                        }
                    }
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

// Custom Video Player View with Loading State
struct VideoPlayerView: View {
    let url: URL
    @Binding var isLoading: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func setupPlayer() {
        isLoading = true
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        
        // Monitor the player item status
        if let currentItem = newPlayer.currentItem {
            // Check initial status
            if currentItem.status == .readyToPlay {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } else if currentItem.status == .failed {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
            
            // Set up status observation
            let statusObserver = currentItem.observe(\.status, options: [.new]) { item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        self.isLoading = false
                    case .failed:
                        self.isLoading = false
                    case .unknown:
                        // Keep loading
                        break
                    @unknown default:
                        break
                    }
                }
            }
            
            // Set up periodic checking for video readiness (fallback)
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if currentItem.status == .readyToPlay {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    timer.invalidate()
                } else if currentItem.status == .failed {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    timer.invalidate()
                }
            }
        }
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
    }
}

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


