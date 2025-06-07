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
            fileName: fileURL.lastPathComponent
        )
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
        .ignoresSafeArea()
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
    
    // Load content from URL
    private func loadContent() {
        isLoading = true
        
        // For video, audio, and PDF, we don't need to download the content as we'll use the URL directly
        if mimeType.starts(with: "video/") || mimeType.starts(with: "audio/") || mimeType == "application/pdf" {
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
        let baseURL = URL(string: "https://\(serverURL)")!
        let api = DFAPI(url: baseURL, token: "")
        
        Task {
            if let details = await api.getFileDetails(fileID: file.id) {
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
        
        // Create and set the initial view controller
        if let initialVC = context.coordinator.createContentViewController(for: currentIndex) {
            pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
        }
        
        return pageViewController
    }
    
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        if let currentVC = pageViewController.viewControllers?.first as? UIHostingController<ContentPreview>,
           let currentFileIndex = files.firstIndex(where: { $0.id == currentVC.rootView.file.id }),
           currentFileIndex != currentIndex {
            // Update to the new index if it's different
            if let newVC = context.coordinator.createContentViewController(for: currentIndex) {
                let direction: UIPageViewController.NavigationDirection = currentFileIndex > currentIndex ? .reverse : .forward
                pageViewController.setViewControllers([newVC], direction: direction, animated: true)
            }
        }
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageViewController
        
        init(_ pageViewController: PageViewController) {
            self.parent = pageViewController
        }
        
        func createContentViewController(for index: Int) -> UIHostingController<ContentPreview>? {
            guard index >= 0 && index < parent.files.count else { return nil }
            let file = parent.files[index]
            let contentPreview = ContentPreview(
                mimeType: file.mime,
                fileURL: URL(string: parent.redirectURLs[file.raw] ?? file.raw)!,
                file: file,
                showFileInfo: parent.showFileInfo,
                selectedFileDetails: parent.$selectedFileDetails
            )
            return UIHostingController(rootView: contentPreview)
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
                  let currentIndex = parent.files.firstIndex(where: { $0.id == currentVC.rootView.file.id }),
                  currentIndex < parent.files.count - 1
            else { return nil }
            
            return createContentViewController(for: currentIndex + 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? UIHostingController<ContentPreview>,
                  let currentIndex = parent.files.firstIndex(where: { $0.id == currentVC.rootView.file.id })
            else { return }
            
            parent.onPageChange(currentIndex)
        }
    }
}

struct FilePreviewView: View {
    @Binding var file: DFFile
    let server: Binding<DjangoFilesSession?>
    @Binding var showingPreview: Bool
    @Binding var showFileInfo: Bool
    let fileListDelegate: FileListDelegate?
    let allFiles: [DFFile]
    let currentIndex: Int
    let onNavigate: (Int) -> Void
    
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
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if redirectURLs[file.raw] == nil {
                    ProgressView()
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
                        }
                    )
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
                            }
                            .background(.ultraThinMaterial)
                            .frame(width: 155, height: 44)
                            .cornerRadius(20)
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
    private func loadRedirectURL(for file: DFFile) async {
        await preloadFiles()
    }
    
    @MainActor
    private func loadSingleFileRedirect(_ file: DFFile) async {
        guard redirectURLs[file.raw] == nil,
              let serverURL = URL(string: file.url)?.host else {
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
                        await loadRedirectURL(for: file)
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
                            await loadRedirectURL(for: file)
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
                        await loadRedirectURL(for: file)
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
                            await loadRedirectURL(for: file)
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


