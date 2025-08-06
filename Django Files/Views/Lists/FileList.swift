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

struct FileListView: View {
    let server: Binding<DjangoFilesSession?>
    let albumID: Int?
    let navigationPath: Binding<NavigationPath>
    let albumName: String?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var previewStateManager: PreviewStateManager
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
    @State private var filterUserID: Int? = nil
    
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
    @State private var deepLinkTargetFileID: Int? = nil
    
    @State private var redirectURLs: [String: String] = [:]
    
    @State private var showFileInfo: Bool = false
    @State private var showingUserFilter: Bool = false
    @State private var users: [DFUser] = []
    
    // Add computed property for selected username
    private var selectedUsername: String? {
        if let userID = filterUserID {
            return users.first(where: { $0.id == userID })?.username
        }
        return nil
    }
    
    init(server: Binding<DjangoFilesSession?>, albumID: Int?, navigationPath: Binding<NavigationPath>, albumName: String?) {
        self.server = server
        self.albumID = albumID
        self.navigationPath = navigationPath
        self.albumName = albumName
        _fileListManager = StateObject(wrappedValue: FileListManager(server: server))
        // Set initial filter to current user's ID
        if let currentUserID = server.wrappedValue?.userID {
            _filterUserID = State(initialValue: currentUserID)
        }
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
    
    private func checkForDeepLinkTarget() {
        print("checkForDeepLinkTarget Called with target: \(String(describing: previewStateManager.deepLinkTargetFileID))")
        if let targetFileID = previewStateManager.deepLinkTargetFileID {
            Task {
                var currentPage = 1
                var foundFile = false
                while !foundFile {
                    await fetchFiles(page: currentPage, append: currentPage > 1)
                    if let index = files.firstIndex(where: { $0.id == targetFileID }) {
                        await MainActor.run {
                            selectedFile = files[index]
                            showingPreview = true
                            previewStateManager.deepLinkTargetFileID = nil
                        }
                        foundFile = true
                    } else if !hasNextPage || errorMessage != nil {
                        // Stop if we hit an error or no more pages
                        break
                    }
                    currentPage += 1
                }
            }
        }
    }
    
    private func loadFiles() {
        if (files.count > 0) { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        Task {
            await fetchFiles(page: currentPage)
            checkForDeepLinkTarget()
        }
    }
    
    var body: some View {
        List {
            if files.count == 0 && !isLoading {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        if let errorMessage = errorMessage {
                            // Show error message instead of "no files found"
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                                .padding(.bottom)
                                .shadow(color: .orange, radius: 15)
                            Text("Error loading files")
                                .font(.headline)
                                .shadow(color: .orange, radius: 20)
                            Text(errorMessage)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Retry") {
                                Task {
                                    await refreshFiles()
                                }
                            }
                            .padding(.top)
                            .buttonStyle(.borderedProminent)
                        } else {
                            // Show "no files found" when there's no error
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
            if let index = fileListManager.files.firstIndex(where: { $0.id == selectedFile?.id }) {
                FilePreviewView(
                    file: $fileListManager.files[index],
                    server: server,
                    showingPreview: $showingPreview,
                    showFileInfo: $showFileInfo,
                    fileListDelegate: fileListManager,
                    allFiles: Binding(
                        get: { fileListManager.files },
                        set: { fileListManager.files = $0 }
                    ),
                    currentIndex: index,
                    onNavigate: { newIndex in
                        if newIndex >= 0 && newIndex < fileListManager.files.count {
                            selectedFile = fileListManager.files[newIndex]
                        }
                    },
                    onLoadMore: {
                        if hasNextPage && !isLoading {
                            await loadNextPage()
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
            ToolbarItem(placement: .navigationBarLeading) {
                HStack {
                    Menu {
                        if server.wrappedValue?.superUser ?? false {
                            Button(action: {
                                showingUserFilter = true
                                Task {
                                    if let serverInstance = server.wrappedValue,
                                       let url = URL(string: serverInstance.url) {
                                        let api = DFAPI(url: url, token: serverInstance.token)
                                        users = await api.getAllUsers(selectedServer: serverInstance)
                                    }
                                }
                            }) {
                                Label("User Filter", systemImage: "person.2.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    if selectedUsername != server.wrappedValue?.username {
                        if let username = selectedUsername {
                            Text("User: \(username)")
                                .font(.caption)
                                .padding(4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                        if filterUserID == 0 {
                            Text("User: *")
                                .font(.caption)
                                .padding(4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                }
            }
            
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
        .sheet(isPresented: $showingUserFilter, onDismiss: {
            Task {
                await refreshFiles()
            }
        }) {
            if let _ = server.wrappedValue {
                UserFilterView(users: $users, selectedUserID: $filterUserID)
                    .onChange(of: filterUserID) { oldValue, newValue in
                        Task {
                            await refreshFiles()
                        }
                    }
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
        .onChange(of: previewStateManager.deepLinkTargetFileID) { _, newValue in
            if newValue != nil {
                checkForDeepLinkTarget()
            }
        }
    }
    
    @MainActor
    private func uploadClipboard() async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            ToastManager.shared.showToast(message: "Invalid server configuration")
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
                let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                if response != nil {
                    await refreshFiles()
                    ToastManager.shared.showToast(message: "Text uploaded successfully")
                } else {
                    ToastManager.shared.showToast(message: "Failed to upload text")
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                print("Error uploading clipboard text: \(error)")
                ToastManager.shared.showToast(message: "Error uploading text: \(error.localizedDescription)")
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
                    let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                    try? FileManager.default.removeItem(at: tempURL)
                    if response != nil {
                        await refreshFiles()
                        ToastManager.shared.showToast(message: "Image uploaded successfully")
                    } else {
                        ToastManager.shared.showToast(message: "Failed to upload image")
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    print("Error uploading clipboard image: \(error)")
                    ToastManager.shared.showToast(message: "Error uploading image: \(error.localizedDescription)")
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
                let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                if response != nil {
                    await refreshFiles()
                    ToastManager.shared.showToast(message: "Video uploaded successfully")
                } else {
                    ToastManager.shared.showToast(message: "Failed to upload video")
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                print("Error uploading clipboard video: \(error)")
                ToastManager.shared.showToast(message: "Error uploading video: \(error.localizedDescription)")
            }
            return
        }
        
        // If we get here, no content was found in clipboard
        ToastManager.shared.showToast(message: "No content found in clipboard")
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
            let errorMsg = "Invalid server URL"
            errorMessage = errorMsg
            isLoading = false
            // Show toast message for the error
            ToastManager.shared.showToast(message: errorMsg)
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        
        do {
            if let filesResponse = await api.getFiles(page: page, album: albumID, selectedServer: serverInstance, filterUserID: filterUserID) {
                if append {
                    // Only append new files that aren't already in the list
                    let newFiles = filesResponse.files.filter { newFile in
                        !files.contains { $0.id == newFile.id }
                    }
                    files.append(contentsOf: newFiles)
                } else {
                    files = filesResponse.files
                }
                
                hasNextPage = filesResponse.next != nil
                currentPage = page
                isLoading = false
                // Clear any previous error message on success
                errorMessage = nil
            } else {
                if !append {
                    files = []
                }
                let errorMsg = "Failed to load files from server"
                errorMessage = errorMsg
                isLoading = false
                // Show toast message for the error
                ToastManager.shared.showToast(message: errorMsg)
            }
        } catch {
            if !append {
                files = []
            }
            let errorMsg = "Error loading files: \(error.localizedDescription)"
            errorMessage = errorMsg
            isLoading = false
            // Show toast message for the error
            ToastManager.shared.showToast(message: errorMsg)
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

struct UserFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var users: [DFUser]
    @Binding var selectedUserID: Int?
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    selectedUserID = 0
                    Task {
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }) {
                    HStack {
                        Text("All Users")
                        Spacer()
                        if selectedUserID == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                ForEach(users, id: \.id) { user in
                    Button(action: {
                        selectedUserID = user.id
                        Task {
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }) {
                        HStack {
                            Text(user.username)
                            Spacer()
                            if selectedUserID == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
