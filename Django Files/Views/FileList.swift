//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation


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
    let file: DFFile
    @State var isPrivate: Bool
    @State var hasPassword: Bool
    @State var hasExpiration: Bool
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
                    Label(file.mime, systemImage: getIcon())
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .lineLimit(1)
                    
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
    
    @State private var files: [DFFile] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showingUploadSheet = false
    @State private var showingShortCreator = false
    
    @State private var previewFile: Bool = true
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
    
    var body: some View {
        List {
            ForEach(files, id: \.id) { file in
                NavigationLink(value: file) {
                    FileRowView(file: file, isPrivate: file.private, hasPassword: (file.password != ""), hasExpiration: (file.expr != ""), serverURL: URL(string: server.wrappedValue!.url)!)
                        .contextMenu {
                            fileContextMenu(for: file, isPreviewing: false, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                        }
                }
                .id(file.id)
                
                if hasNextPage && file.id == files.last?.id {
                    Color.clear
                        .frame(height: 20)
                        .onAppear {
                            loadNextPage()
                        }
                }
            }
            
            if isLoading && hasNextPage {
                HStack {
                    ProgressView()
                }
            }
        }
        .navigationDestination(for: DFFile.self) { file in
            ZStack {
                if redirectURLs[file.raw] == nil {
                    ProgressView()
                        .onAppear {
                            Task {
                                await loadRedirectURL(for: file)
                            }
                        }
                } else {
                    ContentPreview(mimeType: file.mime, fileURL: URL(string: redirectURLs[file.raw]!))
                        .navigationTitle(file.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Menu {
                                    fileShareMenu(for: file)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Menu {
                                    fileContextMenu(for: file, isPreviewing: true, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            Task {
                await refreshFiles()
            }
        }
        .navigationTitle(server.wrappedValue != nil ? "Files (\(URL(string: server.wrappedValue!.url)?.host ?? "unknown"))" : "Files")
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
                        // Create an Album
                    }) {
                        Label("Create Album", systemImage: "photo.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
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
        .alert("Delete File", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteFiles(fileIDs: fileIDsToDelete)
                    
                    // Return to the file list if we're in a detail view
                    if navigationPath.wrappedValue.count > 0 {
                        navigationPath.wrappedValue.removeLast()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(fileNameToDelete)\"?")
        }
        .alert("Set File Expiration", isPresented: $showingExpirationDialog) {
            TextField("Enter expiration", text: $expirationText)
            Button("Cancel", role: .cancel) {
                fileToExpire = nil
            }
            Button("Set") {
                if let file = fileToExpire {
                    let expirationValue = expirationText
                    Task {
                        await setFileExpr(file: file, expr: expirationValue)
                        await MainActor.run {
                            expirationText = ""
                            fileToExpire = nil
                        }
                    }
                }
            }
        } message: {
            Text("Enter time until file expiration. Examples: 1h, 5days, 2y")
        }
        .alert("Set File Password", isPresented: $showingPasswordDialog) {
            TextField("Enter password", text: $passwordText)
            Button("Cancel", role: .cancel) {
                fileToPassword = nil
            }
            Button("Set") {
                if let file = fileToPassword {
                    let passwordValue = passwordText
                    Task {
                        await setFilePassword(file: file, password: passwordValue)
                        await MainActor.run {
                            passwordText = ""
                            fileToPassword = nil
                        }
                    }
                }
            }
        } message: {
            Text("Enter a password for the file.")
        }
        .alert("Rename File", isPresented: $showingRenameDialog) {
            TextField("New File Name", text: $fileNameText)
            Button("Cancel", role: .cancel) {
                fileToRename = nil
            }
            Button("Set") {
                if let file = fileToRename {
                    let fileNameValue = fileNameText
                    Task {
                        await renameFile(file: file, name: fileNameValue)
                        await MainActor.run {
                            fileNameText = ""
                            fileToRename = nil
                        }
                    }
                }
            }
        } message: {
            Text("Enter a new name for this file.")
        }
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
    private func deleteFiles(fileIDs: [Int]) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        await api.deleteFiles(fileIDs: fileIDs, selectedServer: serverInstance)
        
        // Remove the deleted files from the local array
        files.removeAll { file in
            fileIDs.contains(file.id)
        }
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
            print("fail")
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
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        // Toggle the private status (if currently private, make it public and vice versa)
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["private": !file.private], selectedServer: serverInstance)
        
        await refreshFiles()
    }
    
    @MainActor
    private func setFileExpr(file: DFFile, expr: String?) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["expr": expr ?? ""], selectedServer: serverInstance)
        await refreshFiles()
    }
    
    @MainActor
    private func setFilePassword(file: DFFile, password: String?) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        let api = DFAPI(url: url, token: serverInstance.token)
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["password": password ?? ""], selectedServer: serverInstance)
        await refreshFiles()
    }
    
    @MainActor
    private func renameFile(file: DFFile, name: String) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        let api = DFAPI(url: url, token: serverInstance.token)
        if await api.renameFile(fileID: file.id, name: name, selectedServer: serverInstance) {
            await refreshFiles()
        }
    }
    
}
