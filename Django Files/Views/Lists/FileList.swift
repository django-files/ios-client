//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

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
    // Survives view-identity resets (e.g. when iOS 26's bottom-accessory
    // modifier toggles on/off and re-mounts the tab content) so the file list
    // doesn't paint empty for a frame before refetching.
    private static var cache: [String: [DFFile]] = [:]

    @Published var files: [DFFile] = []
    var server: Binding<DjangoFilesSession?>
    private let cacheKey: String
    private var fileDeleteObserver: NSObjectProtocol?
    private var fileNewObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    init(server: Binding<DjangoFilesSession?>, albumID: Int?) {
        self.server = server
        let serverURL = server.wrappedValue?.url ?? ""
        let scope = albumID.map(String.init) ?? "root"
        self.cacheKey = "\(serverURL)|\(scope)"
        self.files = Self.cache[self.cacheKey] ?? []

        $files
            .sink { [weak self] newFiles in
                guard let self else { return }
                Self.cache[self.cacheKey] = newFiles
            }
            .store(in: &cancellables)

        fileDeleteObserver = NotificationCenter.default.addObserver(
            forName: DFWebSocket.fileDeleteNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let id = notification.userInfo?["id"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                withAnimation {
                    self.files.removeAll { $0.id == id }
                }
            }
        }
        fileNewObserver = NotificationCenter.default.addObserver(
            forName: DFWebSocket.fileNewNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let file = notification.userInfo?["file"] as? DFFile else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.files.contains(where: { $0.id == file.id }) { return }
                withAnimation {
                    self.files.insert(file, at: 0)
                }
            }
        }
    }

    deinit {
        if let fileDeleteObserver {
            NotificationCenter.default.removeObserver(fileDeleteObserver)
        }
        if let fileNewObserver {
            NotificationCenter.default.removeObserver(fileNewObserver)
        }
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
    
    @State private var resolvedAlbum: DFAlbum?
    @State private var showFileInfo: Bool = false
    @State private var users: [DFUser] = []
    @State private var selectedMimeTypes: Set<MimeTypeFilter> = []
    @AppStorage("fileListShowingMap") private var showingMap: Bool = false
    @AppStorage("fileListIsGridView") private var isGridView: Bool = false
    @AppStorage("fileListGridColumns") private var gridColumnCount: Int = 2

    @State private var mapFileCount: Int = 0
    @State private var mapIsLoading: Bool = false

    init(server: Binding<DjangoFilesSession?>, albumID: Int?, navigationPath: Binding<NavigationPath>, albumName: String?) {
        self.server = server
        self.albumID = albumID
        self.navigationPath = navigationPath
        self.albumName = albumName
        _fileListManager = StateObject(wrappedValue: FileListManager(server: server, albumID: albumID))
        if let currentUserID = server.wrappedValue?.userID {
            _filterUserID = State(initialValue: currentUserID)
        }
    }

    private var files: [DFFile] {
        get { fileListManager.files }
        nonmutating set { fileListManager.files = newValue }
    }

    private var filteredFiles: [DFFile] {
        guard !selectedMimeTypes.isEmpty else { return fileListManager.files }
        return fileListManager.files.filter { file in
            selectedMimeTypes.contains { file.mime.hasPrefix($0.rawValue) }
        }
    }

    private func getTitle(server: Binding<DjangoFilesSession?>, albumName: String?) -> String {
        resolvedAlbum?.name ?? albumName ?? "Files"
    }

    private var canUpload: Bool {
        guard let token = server.wrappedValue?.token, !token.isEmpty else { return false }
        guard albumID != nil else { return true }
        if server.wrappedValue?.superUser == true { return true }
        guard let album = resolvedAlbum else { return false }
        return album.user != nil && album.user == server.wrappedValue?.userID
    }

    private var viewModeBinding: Binding<String> {
        Binding(
            get: {
                if showingMap { return "map" }
                if isGridView { return "grid" }
                return "list"
            },
            set: { newMode in
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch newMode {
                    case "list": showingMap = false; isGridView = false
                    case "grid": showingMap = false; isGridView = true
                    case "map":  showingMap = true;  isGridView = false
                    default: break
                    }
                }
            }
        )
    }

    private var gridColumnsBinding: Binding<Int> {
        Binding(
            get: { gridColumnCount },
            set: { count in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingMap = false
                    isGridView = true
                    gridColumnCount = count
                }
            }
        )
    }


    private var hasActiveFilters: Bool {
        !selectedMimeTypes.isEmpty || filterUserID != server.wrappedValue?.userID
    }

    private var viewModeIcon: String {
        if showingMap { return "map" }
        if isGridView { return "square.grid.2x2" }
        return "list.bullet"
    }

    private func thumbnailURL(file: DFFile) -> URL? {
        guard let serverURL = server.wrappedValue.flatMap({ URL(string: $0.url) }) else { return nil }
        var components = URLComponents(url: serverURL.appendingPathComponent("/raw/\(file.name)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return components?.url
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
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumnCount)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(filteredFiles) { file in
                    Button {
                        selectedFile = file
                        showingPreview = true
                    } label: {
                        FileGridItemView(
                            file: file,
                            serverURL: server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        fileContextMenu(for: file, isPreviewing: false, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                    }
                    .onAppear {
                        if hasNextPage && fileListManager.files.suffix(5).contains(where: { $0.id == file.id }) {
                            loadNextPage()
                        }
                    }
                }
            }

            if isLoading && hasNextPage {
                HStack {
                    Spacer()
                    LoadingView()
                        .frame(width: 60, height: 60)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .refreshable {
            Task {
                await refreshFiles()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    var body: some View {
        Group {
            if showingMap {
                FileMapView(
                    server: server,
                    inlineMode: true,
                    albumID: albumID,
                    externalFileCount: $mapFileCount,
                    externalIsLoading: $mapIsLoading
                )
            } else if isGridView {
                gridContent
            } else {
                List {
            ForEach(filteredFiles) { file in
                Button {
                    selectedFile = file
                    showingPreview = true
                } label: {
                    if let realIndex = fileListManager.files.firstIndex(where: { $0.id == file.id }) {
                        if file.mime.starts(with: "image/") {
                            FileRowView(
                                file: $fileListManager.files[realIndex],
                                serverURL: server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
                            )
                            .contextMenu {
                                fileContextMenu(for: file, isPreviewing: false, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                            } preview: {
                                CachedAsyncImage(url: thumbnailURL(file: file)) { image in
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
                                file: $fileListManager.files[realIndex],
                                serverURL: server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
                            )
                            .contextMenu {
                                fileContextMenu(for: file, isPreviewing: false, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                            }
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    let fileIsOwned = (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
                    if fileIsOwned {
                        Button {
                            fileIDsToDelete = [file.id]
                            fileNameToDelete = file.name
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }

                if hasNextPage && fileListManager.files.suffix(5).contains(where: { $0.id == file.id }) {
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
                .listStyle(.plain)
                .refreshable {
                    Task {
                        await refreshFiles()
                    }
                }
            }
        }
        .overlay {
            if !showingMap && files.isEmpty {
                if let errorMessage {
                    ListStatusView.error(message: errorMessage) {
                        Task { await refreshFiles() }
                    }
                } else if !isLoading {
                    ListStatusView(
                        icon: "document.on.document.fill",
                        title: "No files found",
                        message: "Upload a file to get started"
                    )
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
                            loadNextPage()
                        }
                    }
                )
            }
        }
        .navigationTitle(showingMap ? "" : getTitle(server: server, albumName: albumName))
        .navigationBarTitleDisplayMode(showingMap ? .inline : .automatic)
        .toolbar {
            if showingMap, let albumTitle = resolvedAlbum?.name ?? albumName {
                ToolbarItem(placement: .principal) {
                    Text(albumTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                }
            }
            ToolbarItem(placement: canUpload ? .navigationBarLeading : .navigationBarTrailing) {
                Menu {
                    Picker("View", selection: viewModeBinding) {
                        Image(systemName: "list.bullet").tag("list")
                        Image(systemName: "square.grid.2x2").tag("grid")
                        Image(systemName: "map").tag("map")
                    }
                    .pickerStyle(.segmented)

                    if isGridView {
                        Picker("Columns", selection: gridColumnsBinding) {
                            Image(systemName: "rectangle.grid.1x2").tag(1)
                            Image(systemName: "square.grid.2x2").tag(2)
                            Image(systemName: "square.grid.3x3").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    Section("Filters") {
                    Menu {
                        ForEach(MimeTypeFilter.allCases.filter { $0 != .all }, id: \.rawValue) { filter in
                            Toggle(isOn: Binding(
                                get: { selectedMimeTypes.contains(filter) },
                                set: { isOn in
                                    if isOn { selectedMimeTypes.insert(filter) }
                                    else { selectedMimeTypes.remove(filter) }
                                }
                            )) {
                                Label(filter.label, systemImage: filter.icon)
                            }
                        }
                        if !selectedMimeTypes.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                selectedMimeTypes.removeAll()
                            } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        }
                    } label: {
                        Label("File Type", systemImage: "doc.badge.gearshape")
                            .symbolVariant(selectedMimeTypes.isEmpty ? .none : .fill)
                    }

                    if server.wrappedValue?.superUser ?? false {
                        Menu {
                            Picker("", selection: Binding(
                                get: { filterUserID },
                                set: { newValue in
                                    filterUserID = newValue
                                    Task { await refreshFiles() }
                                }
                            )) {
                                Label("All Users", systemImage: "person.2")
                                    .tag(Optional<Int>.none)
                                ForEach(users, id: \.id) { user in
                                    Label(user.username, systemImage: "person.circle")
                                        .tag(Optional(user.id))
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Users", systemImage: "person.2")
                                .symbolVariant(filterUserID != server.wrappedValue?.userID ? .fill : .none)
                        }
                    }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.primary)
                }
                .accessibilityIdentifier("fileListViewOptionsMenu")
            }


            if showingMap && (mapIsLoading || mapFileCount > 0) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        if mapIsLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(mapFileCount) \(mapFileCount == 1 ? "file" : "files")")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.default, value: mapIsLoading)
                    .animation(.default, value: mapFileCount)
                }
            }

            if canUpload {
                ToolbarItem(placement: .navigationBarTrailing) {
                    UploadMenuButton(
                        server: server,
                        showPurpleShadow: files.isEmpty
                    )
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
            fetchAlbumIfNeeded()
            if server.wrappedValue?.superUser == true {
                Task {
                    if let serverInstance = server.wrappedValue,
                       let url = URL(string: serverInstance.url) {
                        let api = DFAPI(url: url, token: serverInstance.token)
                        users = await api.getAllUsers(selectedServer: serverInstance)
                    }
                }
            }
        }
        .onChange(of: previewStateManager.deepLinkTargetFileID) { _, newValue in
            if newValue != nil {
                checkForDeepLinkTarget()
            }
        }
    }
    
    private func fileContextMenu(for file: DFFile, isPreviewing: Bool, isPrivate: Bool, expirationText: Binding<String>, passwordText: Binding<String>, fileNameText: Binding<String>) -> FileContextMenuButtons {
        var isPrivate: Bool = isPrivate
        let isOwner = (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
        return FileContextMenuButtons(
            isPreviewing: isPreviewing,
            isPrivate: isPrivate,
            isOwner: isOwner,
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
    
    private func fetchAlbumIfNeeded() {
        guard let id = albumID else { return }
        guard let token = server.wrappedValue?.token, !token.isEmpty else { return }
        Task {
            guard let serverInstance = server.wrappedValue,
                  let url = URL(string: serverInstance.url) else { return }
            let api = DFAPI(url: url, token: token)
            if let album = await api.getAlbum(albumId: id, selectedServer: serverInstance) {
                resolvedAlbum = album
            }
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
            let errorMsg = "Invalid server URL"
            errorMessage = errorMsg
            isLoading = false
            ToastManager.shared.showToast(message: errorMsg)
            return
        }

        let api = DFAPI(url: url, token: serverInstance.token)

        do {
            let filesResponse = try await api.getFiles(page: page, album: albumID, selectedServer: serverInstance, filterUserID: filterUserID, filterMime: nil)
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
            errorMessage = nil
        } catch {
            if !append { files = [] }
            let errorMsg = error.localizedDescription
            errorMessage = errorMsg
            isLoading = false
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

struct FileGridItemView: View {
    let file: DFFile
    let serverURL: URL

    private var isMedia: Bool {
        file.mime.hasPrefix("image/") || file.mime.hasPrefix("video/")
    }

    private var thumbnailURL: URL {
        var components = URLComponents(url: serverURL.appendingPathComponent("/raw/\(file.name)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return components?.url ?? serverURL
    }

    private func getIcon() -> String {
        if file.mime.hasPrefix("video/") { return "video.fill" }
        if file.mime.hasPrefix("audio/") { return "waveform" }
        if file.mime.hasPrefix("text/") || file.mime == "application/json" { return "doc.text.fill" }
        if file.mime == "application/pdf" { return "doc.richtext.fill" }
        if file.mime.contains("zip") || file.mime.contains("archive") { return "archivebox.fill" }
        return "doc.fill"
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    if isMedia {
                        CachedAsyncImage(url: thumbnailURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5)
                        }
                    } else {
                        Color(.systemGray5)
                            .overlay {
                                Image(systemName: getIcon())
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary)
                            }
                    }

                    if !isMedia {
                        Text(file.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.5))
                    }

                }
                .clipped()
            }
            .overlay(alignment: .bottomTrailing) {
                if file.private || file.password != "" || file.expr != "" {
                    HStack(spacing: 2) {
                        if file.private { Image(systemName: "lock.fill").font(.system(size: 8)) }
                        if file.password != "" { Image(systemName: "key.fill").font(.system(size: 8)) }
                        if file.expr != "" { Image(systemName: "clock.fill").font(.system(size: 8)) }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum MimeTypeFilter: String, CaseIterable {
    case all = ""
    case image = "image/"
    case video = "video/"
    case audio = "audio/"
    case text = "text/"
    case document = "application/"

    var label: String {
        switch self {
        case .all: "All Files"
        case .image: "Images"
        case .video: "Videos"
        case .audio: "Audio"
        case .text: "Text"
        case .document: "Documents"
        }
    }

    var icon: String {
        switch self {
        case .all:      "doc.on.doc"
        case .image:    "photo"
        case .video:    "play.rectangle"
        case .audio:    "waveform"
        case .text:     "doc.plaintext"
        case .document: "doc.richtext"
        }
    }
}

