//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation

protocol FileListDelegate: AnyObject {
    @MainActor
    func deleteFiles(fileIDs: [Int], onSuccess: (() -> Void)?) async -> Bool
    @MainActor
    func renameFile(fileID: Int, newName: String, onSuccess: (() -> Void)?) async -> Bool
    @MainActor
    func setFilePassword(fileID: Int, password: String, onSuccess: (() -> Void)?) async -> Bool
    @MainActor
    func setFilePrivate(fileID: Int, isPrivate: Bool, onSuccess: (() -> Void)?) async -> Bool
    @MainActor
    func setFileExpiration(fileID: Int, expr: String, onSuccess: (() -> Void)?) async -> Bool
}

@MainActor
class FileListManager: ObservableObject, FileListDelegate {
    @Published var files: [DFFile] = []
    var server: Binding<DjangoFilesSession?>
    
    init(server: Binding<DjangoFilesSession?>) {
        self.server = server
    }
    
    func deleteFiles(fileIDs: [Int], onSuccess: (() -> Void)?) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.deleteFiles(fileIDs: fileIDs, selectedServer: serverInstance)
        if status {
            withAnimation {
                files.removeAll { file in
                    fileIDs.contains(file.id)
                }
                onSuccess?()
            }
        }
        return status
    }
    
    func renameFile(fileID: Int, newName: String, onSuccess: (() -> Void)?) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.renameFile(fileID: fileID, name: newName, selectedServer: serverInstance)
        if status {
            withAnimation {
                if let index = files.firstIndex(where: { $0.id == fileID }) {
                    var updatedFiles = files
                    
                    // Update the name
                    updatedFiles[index].name = newName
                    
                    // Update URLs that contain the filename
                    let file = updatedFiles[index]
                    
                    // Update raw URL
                    if let oldRawURL = URL(string: file.raw) {
                        let newRawURL = oldRawURL.deletingLastPathComponent().appendingPathComponent(newName)
                        updatedFiles[index].raw = newRawURL.absoluteString
                    }
                    
                    // Update thumb URL
                    if let oldThumbURL = URL(string: file.thumb) {
                        let newThumbURL = oldThumbURL.deletingLastPathComponent().appendingPathComponent(newName)
                        updatedFiles[index].thumb = newThumbURL.absoluteString
                    }
                    
                    // Update main URL
                    if let oldURL = URL(string: file.url) {
                        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
                        updatedFiles[index].url = newURL.absoluteString
                    }
                    
                    // Reassign the entire array to trigger a view update
                    files = updatedFiles
                }
                onSuccess?()
            }
        }
        return status
    }

    func setFilePassword(fileID: Int, password: String, onSuccess: (() -> Void)?) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.editFiles(fileIDs: [fileID], changes: ["password": password], selectedServer: serverInstance)
        if status {
            withAnimation {
                if let index = files.firstIndex(where: { $0.id == fileID }) {
                    var updatedFiles = files
                    updatedFiles[index].password = password
                    files = updatedFiles
                }
                onSuccess?()
            }
        }
        return status
    }

    func setFilePrivate(fileID: Int, isPrivate: Bool, onSuccess: (() -> Void)?) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.editFiles(fileIDs: [fileID], changes: ["private": isPrivate], selectedServer: serverInstance)
        if status {
            withAnimation {
                if let index = files.firstIndex(where: { $0.id == fileID }) {
                    var updatedFiles = files
                    updatedFiles[index].private = isPrivate
                    files = updatedFiles
                }
                onSuccess?()
            }
        }
        return status
    }

    func setFileExpiration(fileID: Int, expr: String, onSuccess: (() -> Void)?) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.editFiles(fileIDs: [fileID], changes: ["expr": expr], selectedServer: serverInstance)
        if status {
            withAnimation {
                if let index = files.firstIndex(where: { $0.id == fileID }) {
                    var updatedFiles = files
                    updatedFiles[index].expr = expr
                    files = updatedFiles
                }
                onSuccess?()
            }
        }
        return status
    }
}

struct CustomLabel: LabelStyle {
    var spacing: Double = 0.0
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

struct FileRowView: View {
    @Binding var file: DFFile
    var isPrivate: Bool { file.private }
    var hasPassword: Bool { file.password != "" }
    var hasExpiration: Bool { file.expr != "" }
    let serverURL: URL
    
    private func getIcon() -> String {
        if file.mime.hasPrefix("image/") {
            return "photo.artframe"
        } else if file.mime.hasPrefix("video/") {
            return "video.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private var thumbnailURL: URL {
        var components = URLComponents(url: serverURL.appendingPathComponent("/raw/\(file.name)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return components?.url ?? serverURL
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(spacing: 0) {
                if file.mime.hasPrefix("image/") {
                    CachedAsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 64, height: 64)
                    .clipped()
                    .cornerRadius(8)
                } else {
                    Image(systemName: getIcon())
                        .font(.system(size: 50))
                        .frame(width: 64, height: 64)
                        .foregroundColor(Color.primary)
                        .clipped()
                }
            }
            .listRowSeparator(.visible)

            
            VStack(alignment: .leading, spacing: 5) {
                
                HStack(spacing: 5) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.blue)
                }
                
                
                HStack(spacing: 6) {
                    Text(file.mime)
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .lineLimit(1)
                    
                    Label("", systemImage: "lock")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(isPrivate ? 1 : 0)
                    
                    Label("", systemImage: "key")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(hasPassword ? 1 : 0)
                    
                    Label("", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(hasExpiration ? 1 : 0)
                }
                
                HStack(spacing: 5) {

                    
                    Label(file.userUsername, systemImage: "person")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .lineLimit(1)
                    
                    
                    Text(file.formattedDate())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                }

            }
        }
    }
}


struct FileListView: View {
    let server: Binding<DjangoFilesSession?>
    let albumID: Int?
    let navigationPath: Binding<NavigationPath>
    let albumName: String?
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var fileListManager: FileListManager
    
    @State private var currentPage = 1
    @State private var hasNextPage: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var showingUploadSheet: Bool = false
    @State private var showingShortCreator: Bool = false
    @State private var showingAlbumCreator: Bool = false
    @State private var showingPreview: Bool = false
    @State private var selectedFile: DFFile? = nil
    
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
    
    @State private var redirectURLs: [String: String] = [:]
    
    @State private var showFileInfo: Bool = false
    
    init(server: Binding<DjangoFilesSession?>, albumID: Int?, navigationPath: Binding<NavigationPath>, albumName: String?) {
        self.server = server
        self.albumID = albumID
        self.navigationPath = navigationPath
        self.albumName = albumName
        _fileListManager = StateObject(wrappedValue: FileListManager(server: server))
    }

    private var files: [DFFile] {
        get { fileListManager.files }
        nonmutating set { fileListManager.files = newValue }
    }
    
    private func getTitle(server: Binding<DjangoFilesSession?>, albumName: String?) -> String {
        if server.wrappedValue != nil && albumName == nil {
            return "Files (\(String(describing: URL(string: server.wrappedValue?.url ?? "host")!.host ?? "unknown")))"
        } else if server.wrappedValue != nil && albumName != nil {
            return "\(String(describing: albumName!)) (\(String(describing: URL(string: server.wrappedValue?.url ?? "host")!.host ?? "unknown")))"
        } else {
            return "Files"
        }
    }
    
    private func thumbnailURL(file: DFFile) ->  URL {
        var components = URLComponents(url: URL(string: server.wrappedValue!.url)!.appendingPathComponent("/raw/\(file.name)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return components?.url ?? URL(string: server.wrappedValue!.url)!
    }
    
    var body: some View {
        List {
            if files.count == 0 && !isLoading {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        Image(systemName: "document.on.document.fill")
                            .font(.system(size: 50))
                            .padding(.bottom)
                            .shadow(color: .purple, radius: 15)
                        Text("No files found")
                            .font(.headline)
                            .shadow(color: .purple, radius: 20)
                        Text("Upload a file to get started")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }

            ForEach(files.indices, id: \.self) { index in
                Button {
                    selectedFile = files[index]
                    showingPreview = true
                } label: {
                    if files[index].mime.starts(with: "image/") {
                        FileRowView(
                            file: $fileListManager.files[index],
                            serverURL: URL(string: server.wrappedValue!.url)!
                        )
                        .contextMenu {
                            fileContextMenu(for: files[index], isPreviewing: false, isPrivate: files[index].private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                        } preview: {
                            CachedAsyncImage(url: thumbnailURL(file: files[index])) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 512, height: 512)
                            .cornerRadius(8)
                        }
                    } else {
                        FileRowView(
                            file: $fileListManager.files[index],
                            serverURL: URL(string: server.wrappedValue!.url)!
                        )
                        .contextMenu {
                            fileContextMenu(for: files[index], isPreviewing: false, isPrivate: files[index].private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                        }
                    }
                }
                .id(files[index].id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button() {
                        fileIDsToDelete = [files[index].id]
                        fileNameToDelete = files[index].name
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }

                if hasNextPage && files.suffix(5).contains(where: { $0.id == files[index].id }) {
                    Color.clear
                        .frame(height: 20)
                        .onAppear {
                            loadNextPage()
                        }
                }
            }
            
            if isLoading && hasNextPage {
                HStack {
                    Spacer()
                    LoadingView()
                        .frame(width: 100, height: 100)
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $showingPreview) {
            if let index = files.firstIndex(where: { $0.id == selectedFile?.id }) {
                FilePreviewView(
                    file: $fileListManager.files[index],
                    server: server,
                    showingPreview: $showingPreview,
                    showFileInfo: $showFileInfo,
                    fileListDelegate: fileListManager,
                    allFiles: files,
                    currentIndex: index,
                    onNavigate: { newIndex in
                        if newIndex >= 0 && newIndex < files.count {
                            selectedFile = files[newIndex]
                        }
                    }
                )
            }
        }

        .listStyle(.plain)
        .refreshable {
            Task {
                await refreshFiles()
            }
        }
        .navigationTitle(getTitle(server: server, albumName: albumName))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        showingUploadSheet = true
                    }) {
                        Label("Upload File", systemImage: "arrow.up.doc")
                    }
                    Button(action: {
                        Task {
                            await uploadClipboard()
                        }
                    }) {
                        Label("Upload Clipboard", systemImage: "clipboard")
                    }
                    Button(action: {
                        showingShortCreator = true
                    }) {
                        Label("Create Short", systemImage: "link.badge.plus")
                    }
                    Button(action: {
                        showingAlbumCreator = true
                    }) {
                        Label("Create Album", systemImage: "photo.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .shadow(color: .purple, radius: files.isEmpty ? 3 : 0)
            }
            
        }
        .sheet(isPresented: $showingUploadSheet,
               onDismiss: { Task { await refreshFiles()} }
        ) {
            if let serverInstance = server.wrappedValue {
                FileUploadView(server: serverInstance)
            }
        }
        .sheet(isPresented: $showingShortCreator) {
            if let serverInstance = server.wrappedValue {
                ShortCreatorView(server: serverInstance)
            }
        }
        .sheet(isPresented: $showingAlbumCreator) {
            if let serverInstance = server.wrappedValue {
                CreateAlbumView(server: serverInstance)
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
                    await deleteFiles(fileIDs: fileIDs)
                },
                onSetExpiration: { file, expr in
                    await setFileExpiration(file: file, expr: expr)
                },
                onSetPassword: { file, password in
                    await setFilePassword(file: file, password: password)
                },
                onRename: { file, name in
                    await renameFile(file: file, name: name)
                }
            )
        )
        .onAppear {
            loadFiles()
        }
    }
    
    @MainActor
    private func uploadClipboard() async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let pasteboard = UIPasteboard.general
        
        // Handle text content
        if let text = pasteboard.string {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("ios-clip.txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
                let delegate = UploadProgressDelegate { _ in }
                _ = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                await refreshFiles()
            } catch {
                print("Error uploading clipboard text: \(error)")
            }
            return
        }
        
        // Handle image content
        if let image = pasteboard.image {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("image.jpg")
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try imageData.write(to: tempURL)
                    let delegate = UploadProgressDelegate { _ in }
                    _ = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                    try? FileManager.default.removeItem(at: tempURL)
                    await refreshFiles()
                } catch {
                    print("Error uploading clipboard image: \(error)")
                }
            }
            return
        }
        
        // Handle video content
        if let videoData = pasteboard.data(forPasteboardType: "public.mpeg-4"),
           let tempURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("video.mp4") {
            do {
                try videoData.write(to: tempURL)
                let delegate = UploadProgressDelegate { _ in }
                _ = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                await refreshFiles()
            } catch {
                print("Error uploading clipboard video: \(error)")
            }
            return
        }
    }
    
    private func fileContextMenu(for file: DFFile, isPreviewing: Bool, isPrivate: Bool, expirationText: Binding<String>, passwordText: Binding<String>, fileNameText: Binding<String>) -> FileContextMenuButtons {
        var isPrivate: Bool = isPrivate
        return FileContextMenuButtons(
            isPreviewing: isPreviewing,
            isPrivate: isPrivate,
            onPreview: {
                selectedFile = file
                showingPreview = true
            },
            onCopyShareLink: {
                UIPasteboard.general.string = file.url
            },
            onCopyRawLink: {
                if redirectURLs[file.raw] == nil {
                    Task {
                        await loadRedirectURL(for: file)
                        // Only open the URL after we've loaded the redirect
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
                } else if let redirectURL = redirectURLs[file.raw], let finalURL = URL(string: redirectURL) {
                    UIPasteboard.general.string = finalURL.absoluteString
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
                    isPrivate = !isPrivate
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
    
    private func loadFiles() {
        if (files.count > 0) { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        Task {
            await fetchFiles(page: currentPage)
        }
    }
    
    private func loadNextPage() {
        guard hasNextPage else { return }
        guard !isLoading else { return }  // Prevent multiple simultaneous loading requests
        isLoading = true
        Task {
            await fetchFiles(page: currentPage + 1, append: true)
        }
    }
    
    @MainActor
    private func refreshFiles() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        files = []
        await fetchFiles(page: currentPage)
    }
    
    @MainActor
    private func fetchFiles(page: Int, append: Bool = false) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            errorMessage = "Invalid server URL"
            isLoading = false
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        
        if let filesResponse = await api.getFiles(page: page, album: albumID, selectedServer: serverInstance) {
            if append {
                files.append(contentsOf: filesResponse.files)
            } else {
                files = filesResponse.files
            }
            
            hasNextPage = filesResponse.next != nil
            currentPage = page
            isLoading = false
        } else {
            if !append {
                files = []
            }
            errorMessage = "Failed to load files from server"
            isLoading = false
        }
    }
    
    @MainActor
    private func deleteFiles(fileIDs: [Int], onSuccess: (() -> Void)? = nil) async -> Bool {
        return await fileListManager.deleteFiles(fileIDs: fileIDs, onSuccess: onSuccess)
    }
    
    @MainActor
    private func loadRedirectURL(for file: DFFile) async {
        guard redirectURLs[file.raw] == nil,
              let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        
        if let redirectURL = await api.checkRedirect(url: file.raw) {
            redirectURLs[file.raw] = redirectURL
        } else {
            // If redirect fails, use the original URL
            redirectURLs[file.raw] = file.raw
        }
    }
    
    private func fileShareMenu(for file: DFFile) -> FileShareMenu {
        FileShareMenu(
            onCopyShareLink: {
                UIPasteboard.general.string = file.url
            },
            onCopyRawLink: {
                UIPasteboard.general.string = file.raw
            }
        )
    }
    
    @MainActor
    private func toggleFilePrivacy(file: DFFile) async {
        let _ = await fileListManager.setFilePrivate(fileID: file.id, isPrivate: !file.private, onSuccess: nil)
    }
    
    @MainActor
    private func setFileExpiration(file: DFFile, expr: String) async {
        let _ = await fileListManager.setFileExpiration(fileID: file.id, expr: expr, onSuccess: nil)
    }
    
    @MainActor
    private func setFilePassword(file: DFFile, password: String) async {
        let _ = await fileListManager.setFilePassword(fileID: file.id, password: password, onSuccess: nil)
    }
    
    @MainActor
    private func renameFile(file: DFFile, name: String) async {
        let _ = await fileListManager.renameFile(fileID: file.id, newName: name, onSuccess: nil)
    }
    
}
