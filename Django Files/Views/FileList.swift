//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation


struct FileListView: View {
    let server: Binding<DjangoFilesSession?>
    
    @State private var files: [DFFile] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    @State private var previewFile: Bool = true
    @State private var selectedFile: DFFile? = nil
    @State private var navigationPath = NavigationPath()
    
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
        ZStack {
            if isLoading && files.isEmpty {
                LoadingView()
                    .frame(width: 100, height: 100)
            } else if let error = errorMessage {
                VStack {
                    Text("Error loading files")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadFiles()
                    }
                    .padding(.top)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 5)
            } else if files.isEmpty {
                VStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 50))
                        .padding(.bottom)
                    Text("No files found")
                        .font(.headline)
                    Text("Upload some files to get started")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                NavigationStack(path: $navigationPath) {
                    List {
                        ForEach(files, id: \.id) { file in
                            NavigationLink(value: file) {
                                FileRowView(file: file, isPrivate: file.private, hasPassword: (file.password != ""), hasExpiration: (file.expr != ""))
                                    .contextMenu {
                                        createFileMenuButtons(for: file, isPreviewing: false, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                    }
                            }
                            .id(file.id)
                            
                            // If this is the last item and we have more pages, load more when it appears
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
                                                createFileMenuButtons(for: file, isPreviewing: true, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
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
                                    // Upload action
                                }) {
                                    Label("Upload File", systemImage: "arrow.up.doc")
                                }
                                
                                Button(action: {
                                    Task {
                                        await refreshFiles()
                                    }
                                }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .onChange(of: selectedFile) { oldValue, newValue in
                    if let file = newValue {
                        navigationPath.append(file)
                        selectedFile = nil // Reset after navigation
                    }
                }
                .alert("Delete File", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteFiles(fileIDs: fileIDsToDelete)
                            
                            // Return to the file list if we're in a detail view
                            if navigationPath.count > 0 {
                                navigationPath.removeLast()
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
                            let expirationValue = expirationText // Capture the value
                            Task {
                                await setFileExpr(file: file, expr: expirationValue)
                                // Only clear after the API call completes
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
                            let passwordValue = passwordText // Capture the value
                            Task {
                                await setFilePassword(file: file, password: passwordValue)
                                // Only clear after the API call completes
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
                            let fileNameValue = fileNameText // Capture the value
                            Task {
                                await renameFile(file: file, name: fileNameValue)
                                // Only clear after the API call completes
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
            }
        }
        .onAppear {
            loadFiles()
        }
    }
    
    // Helper function to create consistent FileContextMenuButtons
    private func createFileMenuButtons(for file: DFFile, isPreviewing: Bool, isPrivate: Bool, expirationText: Binding<String>, passwordText: Binding<String>, fileNameText: Binding<String>) -> FileContextMenuButtons {
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
        
        if let filesResponse = await api.getFiles(page: page) {
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
        await api.deleteFiles(fileIDs: fileIDs)
        
        // Refresh the file list after deletion
        await refreshFiles()
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
    
    @MainActor
    private func toggleFilePrivacy(file: DFFile) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        // Toggle the private status (if currently private, make it public and vice versa)
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["private": !file.private])
        
        await refreshFiles()
    }
    
    @MainActor
    private func setFileExpr(file: DFFile, expr: String?) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        // Send the expiration value to the API
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["expr": expr ?? ""])
        
        await refreshFiles()
    }
    
    @MainActor
    private func setFilePassword(file: DFFile, password: String?) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        // Send the expiration value to the API
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["password": password ?? ""])
        
        await refreshFiles()
    }
    
    @MainActor
    private func renameFile(file: DFFile, name: String) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        // Send the expiration value to the API
        let _ = await api.editFiles(fileIDs: [file.id], changes: ["name": name])
        
        await refreshFiles()
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
    let file: DFFile
    @State var isPrivate: Bool
    @State var hasPassword: Bool
    @State var hasExpiration: Bool
    
    private func getIcon() -> String {
        switch file.mime {
        case "image/jpeg":
            return "photo.artframe"
        default:
            return "doc.fill"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.blue)
            
            HStack(spacing: 5) {
                Label(file.mime, systemImage: getIcon())
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
                
                Label(file.userUsername!, systemImage: "person")
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
                
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
                
                
                Text(file.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
