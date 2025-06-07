import SwiftUI
import AVKit
import HighlightSwift
import UIKit

extension AnyTransition {
    static func slideTransition(edge: Edge, dragOffset: CGFloat = 0) -> AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge.opposite).combined(with: .opacity)
        )
    }
}

extension Edge {
    var opposite: Edge {
        switch self {
        case .leading: return .trailing
        case .trailing: return .leading
        case .top: return .bottom
        case .bottom: return .top
        }
    }
}

struct ContentPreview: View {
    let mimeType: String
    let fileURL: URL
    @Binding var file: DFFile
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
            } else if mimeType.starts(with: "application/") {
                if mimeType == "application/pdf" {
                    pdfPreview
                } else if mimeType.contains("json") {
                    textPreview
                } else {
                    genericFilePreview
                }
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
            ZStack {
                if let content = content, let text = String(data: content, encoding: .utf8) {
                    CodeText(text)
                        .highlightLanguage(determineLanguage(from: mimeType, fileName: fileURL.lastPathComponent))
                        .padding()
                } else {
                    Text("Unable to decode text content")
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 40)
        }
    }

    // Helper function to determine the highlight language based on file type
    private func determineLanguage(from mimeType: String, fileName: String) -> HighlightLanguage {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        
        switch fileExtension {
        case "swift":
            return .swift
        case "py", "python":
            return .python
        case "js", "javascript":
            return .javaScript
        case "java":
            return .java
        case "cpp", "c", "h", "hpp":
            return .cPlusPlus
        case "html":
            return .html
        case "css":
            return .css
        case "json":
            return .json
        case "md", "markdown":
            return .markdown
        case "sh", "bash":
            return .bash
        case "rb", "ruby":
            return .ruby
        case "go":
            return .go
        case "rs":
            return .rust
        case "php":
            return .php
        case "sql":
            return .sql
        case "ts", "typescript":
            return .typeScript
        case "yaml", "yml":
            return .yaml
        default:
            // For plain text or unknown types
            if mimeType == "text/plain" {
                return .plaintext
            }
            // Try to determine from mime type if extension didn't match
            let mimePrimeType = mimeType.split(separator: "/").first?.lowercased() ?? ""
            let mimeSubtype = mimeType.split(separator: "/").last?.lowercased() ?? ""

            switch mimePrimeType {
            case "application":
                switch mimeSubtype {
                    case "json", "x-ndjson":
                        return .json
                default:
                    return .plaintext
                }
            case "text":
                switch mimeSubtype {
                case "javascript":
                    return .javaScript
                case "python":
                    return .python
                case "java":
                    return .java
                case "html":
                    return .html
                case "css":
                    return .css
                case "json", "x-ndjson":
                    return .json
                case "markdown":
                    return .markdown
                case "xml":
                    return .html
                default:
                    return .plaintext
                }
            default:
                return .plaintext
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
    @State private var previousIndex: Int? = nil
    @State private var finalOffset: CGFloat = 0
    
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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if redirectURLs[file.raw] == nil {
                    ProgressView()
                        .onAppear {
                            Task {
                                await loadRedirectURL(for: file)
                            }
                        }
                } else {
                    ContentPreview(mimeType: file.mime, fileURL: URL(string: redirectURLs[file.raw]!)!, file: $file, showFileInfo: $showFileInfo)
                        .id(file.id)
                        .offset(x: dragState.translation.width + finalOffset, y: dragState.translation.height)
                        .transition(.move(edge: previousIndex ?? 0 > currentIndex ? .leading : .trailing))
                        .onChange(of: currentIndex) { oldIndex, newIndex in
                            previousIndex = oldIndex
                            finalOffset = 0
                        }
                        .onDisappear {
                            showingPreview = false
                        }
                        .gesture(
                            DragGesture()
                                .updating($dragState) { value, state, _ in
                                    state = .dragging(translation: value.translation)
                                }
                                .onEnded { value in
                                    let translation = value.translation
                                    let velocity = CGSize(
                                        width: (value.predictedEndLocation.x - value.location.x) / 1.5,
                                        height: (value.predictedEndLocation.y - value.location.y) / 1.5
                                    )
                                    
                                    // Determine if the gesture is more horizontal or vertical
                                    let isHorizontal = abs(translation.width) > abs(translation.height)
                                    
                                    if isHorizontal {
                                        let offsetX = translation.width
                                        let progress = offsetX / geometry.size.width
                                        let velocityThreshold: CGFloat = 200
                                        let progressThreshold: CGFloat = 0.2
                                        
                                        if (progress > progressThreshold || velocity.width > velocityThreshold) && currentIndex > 0 {
                                            finalOffset = geometry.size.width
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                onNavigate(currentIndex - 1)
                                            }
                                        } else if (progress < -progressThreshold || velocity.width < -velocityThreshold) && currentIndex < allFiles.count - 1 {
                                            finalOffset = -geometry.size.width
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                onNavigate(currentIndex + 1)
                                            }
                                        } else {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                finalOffset = 0
                                            }
                                        }
                                    } else {
                                        let offsetY = translation.height
                                        let progress = offsetY / geometry.size.height
                                        let velocityThreshold: CGFloat = 200
                                        let progressThreshold: CGFloat = 0.2
                                        
                                        if progress > progressThreshold || velocity.height > velocityThreshold {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                showingPreview = false
                                            }
                                        }
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
        }
    }
    
    @MainActor
    private func loadRedirectURL(for file: DFFile) async {
        guard redirectURLs[file.raw] == nil,
              let serverURL = URL(string: file.url)?.host else {
            return
        }
        
        let baseURL = URL(string: "https://\(serverURL)")!
        let api = DFAPI(url: baseURL, token: "")  // Token will be handled by cookies
        
        if let redirectURL = await api.checkRedirect(url: file.raw) {
            redirectURLs[file.raw] = redirectURL
            
            // Preload adjacent files
            if currentIndex > 0 {
                let prevFile = allFiles[currentIndex - 1]
                if redirectURLs[prevFile.raw] == nil {
                    if let prevRedirectURL = await api.checkRedirect(url: prevFile.raw) {
                        redirectURLs[prevFile.raw] = prevRedirectURL
                    }
                }
            }
            if currentIndex < allFiles.count - 1 {
                let nextFile = allFiles[currentIndex + 1]
                if redirectURLs[nextFile.raw] == nil {
                    if let nextRedirectURL = await api.checkRedirect(url: nextFile.raw) {
                        redirectURLs[nextFile.raw] = nextRedirectURL
                    }
                }
            }
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


