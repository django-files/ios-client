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

    func updateFileAlbums(fileID: Int, albumIDs: [Int]) {
        withAnimation {
            if let index = files.firstIndex(where: { $0.id == fileID }) {
                var updated = files
                updated[index].albums = albumIDs
                files = updated
            }
        }
    }

    func updateFilesAlbums(updates: [Int: [Int]]) {
        withAnimation {
            var updated = files
            for (fileID, albumIDs) in updates {
                if let index = updated.firstIndex(where: { $0.id == fileID }) {
                    updated[index].albums = albumIDs
                }
            }
            files = updated
        }
    }

    func setFilesPrivate(fileIDs: [Int], isPrivate: Bool) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return false }
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.editFiles(fileIDs: fileIDs, changes: ["private": isPrivate], selectedServer: serverInstance)
        if status {
            withAnimation {
                var updated = files
                for id in fileIDs {
                    if let index = updated.firstIndex(where: { $0.id == id }) {
                        updated[index].private = isPrivate
                    }
                }
                files = updated
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
    @EnvironmentObject private var sessionManager: SessionManager
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
    @State private var showingAlbumPicker = false
    @State private var fileForAlbumPicker: DFFile? = nil

    @State private var isSelectMode: Bool = false
    @State private var selectedFileIDs: Set<Int> = []
    @State private var showingBulkAlbumPicker: Bool = false
    
    @State private var redirectURLs: [String: String] = [:]
    
    @State private var resolvedAlbum: DFAlbum?
    @State private var showFileInfo: Bool = false
    @State private var users: [DFUser] = []
    @State private var selectedMimeTypes: Set<MimeTypeFilter> = []
    @AppStorage("fileListShowingMap") private var showingMap: Bool = false
    @AppStorage("fileListIsGridView") private var isGridView: Bool = false
    @AppStorage("fileListGridColumns") private var gridColumnCount: Int = 2
    @AppStorage("fileListGridNaturalAspect") private var naturalAspect: Bool = false

    @AppStorage("fileListSortField") private var sortField: String = "created"
    @AppStorage("fileListSortAscending") private var sortAscending: Bool = false

    private var sortOption: String {
        sortAscending ? sortField : "-\(sortField)"
    }

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
        fileListManager.files
    }

    private var filterTypeParam: String? {
        guard !selectedMimeTypes.isEmpty else { return nil }
        return selectedMimeTypes.map(\.rawValue).sorted().joined(separator: ",")
    }

    private var resolvedServerURL: URL {
        server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
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

    private var hasActiveFilters: Bool {
        !selectedMimeTypes.isEmpty
            || filterUserID != server.wrappedValue?.userID
            || (sessionManager.supportsOrdering && (sortField != "created" || sortAscending))
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
        let showDetails = gridColumnCount <= 5
        let serverURL = resolvedServerURL
        return PinchableGridContainer(gridColumnCount: $gridColumnCount) { topPad, bottomPad in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(filteredFiles) { file in
                        let isSelected = selectedFileIDs.contains(file.id)
                        Button {
                            if isSelectMode {
                                toggleSelection(file: file)
                            } else {
                                selectedFile = file
                                showingPreview = true
                            }
                        } label: {
                            FileGridItemView(
                                file: file,
                                serverURL: serverURL,
                                showDetails: showDetails,
                                naturalAspect: naturalAspect
                            )
                            .contentShape(Rectangle())
                            .overlay(alignment: .topLeading) {
                                if isSelectMode {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(isSelected ? Color.accentColor : .white)
                                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                                        .padding(6)
                                }
                            }
                            .opacity(isSelectMode && !isSelected ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !isSelectMode {
                                fileContextMenu(for: file, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                            }
                        }
                        .onAppear {
                            if hasNextPage && fileListManager.files.suffix(5).contains(where: { $0.id == file.id }) {
                                loadNextPage()
                            }
                        }
                    }
                }
                .padding(.top, topPad + 8)
                .padding(.bottom, bottomPad + 8)

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
            .ignoresSafeArea()
            .refreshable {
                Task {
                    await refreshFiles()
                }
            }
        }
    }

    var body: some View {
        Group {
            if showingMap {
                FileMapView(
                    server: server,
                    inlineMode: true,
                    albumID: albumID,
                    selectedMimeTypes: selectedMimeTypes,
                    filterUserID: filterUserID,
                    externalFileCount: $mapFileCount,
                    externalIsLoading: $mapIsLoading
                )
            } else if isGridView {
                gridContent
            } else {
                List {
            ForEach(filteredFiles) { file in
                let isSelected = selectedFileIDs.contains(file.id)
                Button {
                    if isSelectMode {
                        toggleSelection(file: file)
                    } else {
                        selectedFile = file
                        showingPreview = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isSelectMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .animation(.easeInOut(duration: 0.15), value: isSelected)
                        }
                        if let realIndex = fileListManager.files.firstIndex(where: { $0.id == file.id }) {
                            if file.mime.starts(with: "image/") && !isSelectMode {
                                FileRowView(
                                    file: $fileListManager.files[realIndex],
                                    serverURL: server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
                                )
                                .contextMenu {
                                    fileContextMenu(for: file, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
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
                                    if !isSelectMode {
                                        fileContextMenu(for: file, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                    }
                                }
                            }
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !isSelectMode {
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
        .safeAreaInset(edge: .bottom) {
            if isSelectMode {
                bulkActionBar
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

                    Divider()

                    Section("Filters") {
                    if sessionManager.supportsOrdering {
                        Menu {
                            Picker("Sort by", selection: $sortField) {
                                ForEach(FileSortField.allCases, id: \.rawValue) { field in
                                    Label(field.label, systemImage: field.icon).tag(field.rawValue)
                                }
                            }
                            .pickerStyle(.inline)

                            Divider()

                            Picker("Direction", selection: $sortAscending) {
                                Label("Ascending", systemImage: "arrow.up").tag(true)
                                Label("Descending", systemImage: "arrow.down").tag(false)
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                                .symbolVariant((sortField != "created" || sortAscending) ? .fill : .none)
                        }
                    }
                    Menu {
                        Toggle(isOn: Binding(
                            get: { selectedMimeTypes.isEmpty },
                            set: { isAll in if isAll { selectedMimeTypes.removeAll() } }
                        )) {
                            Label("All", systemImage: "doc.on.doc")
                        }
                        Divider()
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

                    if !showingMap {
                        Divider()
                        Button {
                            isSelectMode = true
                            selectedFileIDs = []
                        } label: {
                            Label("Bulk Select", systemImage: "checklist")
                        }
                        .disabled(filteredFiles.isEmpty)
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

            if isSelectMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isSelectMode = false
                        selectedFileIDs = []
                    }
                }
            }

            if canUpload && !isSelectMode {
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
                    let success = await deleteFiles(fileIDs: fileIDs)
                    if success && isSelectMode {
                        selectedFileIDs.subtract(fileIDs)
                        if selectedFileIDs.isEmpty { isSelectMode = false }
                    }
                    return success
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
        .sheet(isPresented: $showingAlbumPicker) {
            if let file = fileForAlbumPicker {
                AlbumPickerSheet(file: file, server: server.wrappedValue) { newAlbumIDs in
                    fileListManager.updateFileAlbums(fileID: file.id, albumIDs: newAlbumIDs)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingBulkAlbumPicker) {
            BulkAlbumPickerSheet(
                files: selectedFiles,
                server: server.wrappedValue
            ) { updates in
                fileListManager.updateFilesAlbums(updates: updates)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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
        .onChange(of: sortField) { _, _ in
            Task { await refreshFiles() }
        }
        .onChange(of: sortAscending) { _, _ in
            Task { await refreshFiles() }
        }
        .onChange(of: selectedMimeTypes) { _, _ in
            Task { await refreshFiles() }
        }
    }
    
    private func toggleSelection(file: DFFile) {
        let owned = (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
        guard owned else { return }
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
        } else {
            selectedFileIDs.insert(file.id)
        }
    }

    private var ownedSelectedIDs: [Int] {
        filteredFiles
            .filter { selectedFileIDs.contains($0.id) }
            .filter { file in
                (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
            }
            .map(\.id)
    }

    private var selectedFiles: [DFFile] {
        filteredFiles.filter { selectedFileIDs.contains($0.id) }
    }

    @ViewBuilder
    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                let allOwned = filteredFiles.filter { file in
                    (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
                }
                let allOwnedSelected = !allOwned.isEmpty && allOwned.allSatisfy { selectedFileIDs.contains($0.id) }

                Button {
                    if allOwnedSelected {
                        selectedFileIDs = []
                    } else {
                        selectedFileIDs = Set(allOwned.map(\.id))
                    }
                } label: {
                    Text(allOwnedSelected ? "Deselect All" : "Select All")
                        .font(.subheadline)
                }

                Spacer()

                if !selectedFileIDs.isEmpty {
                    Text("\(selectedFileIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 20) {
                    Menu {
                        Button {
                            Task { await fileListManager.setFilesPrivate(fileIDs: Array(selectedFileIDs), isPrivate: true) }
                        } label: {
                            Label("Make Private", systemImage: "lock.fill")
                        }
                        Button {
                            Task { await fileListManager.setFilesPrivate(fileIDs: Array(selectedFileIDs), isPrivate: false) }
                        } label: {
                            Label("Make Public", systemImage: "lock.open.fill")
                        }
                    } label: {
                        Label("Privacy", systemImage: "lock")
                            .font(.subheadline)
                    }
                    .disabled(selectedFileIDs.isEmpty)

                    Button {
                        showingBulkAlbumPicker = true
                    } label: {
                        Label("Albums", systemImage: "photo.stack")
                            .font(.subheadline)
                    }
                    .disabled(selectedFileIDs.isEmpty)

                    Button(role: .destructive) {
                        let ids = ownedSelectedIDs
                        guard !ids.isEmpty else { return }
                        fileIDsToDelete = ids
                        fileNameToDelete = ids.count == 1
                            ? (filteredFiles.first(where: { $0.id == ids[0] })?.name ?? "")
                            : "\(ids.count) files"
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .disabled(ownedSelectedIDs.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func fileContextMenu(for file: DFFile, isPrivate: Bool, expirationText: Binding<String>, passwordText: Binding<String>, fileNameText: Binding<String>) -> FileContextMenuButtons {
        var isPrivate: Bool = isPrivate
        let isOwner = (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID) || (server.wrappedValue?.superUser == true)
        return FileContextMenuButtons(
            isPrivate: isPrivate,
            isOwner: isOwner,
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
            manageAlbums: {
                fileForAlbumPicker = file
                showingAlbumPicker = true
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
            // Superuser with no user selected means "all users"; backend expects user=0 for that case
            let effectiveFilterUserID = filterUserID ?? (serverInstance.superUser ? 0 : nil)
            let filesResponse = try await api.getFiles(page: page, album: albumID, selectedServer: serverInstance, filterUserID: effectiveFilterUserID, filterType: filterTypeParam, ordering: sessionManager.supportsOrdering ? sortOption : nil)
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

private struct PinchableGridContainer<Content: View>: View {
    @Binding var gridColumnCount: Int
    @ViewBuilder let content: (_ topPad: CGFloat, _ bottomPad: CGFloat) -> Content
    @State private var gestureScale: CGFloat = 1.0
    @State private var scaleAnchor: UnitPoint = .center
    @State private var anchorCaptured: Bool = false
    @State private var topPadding: CGFloat = 0
    @State private var bottomPadding: CGFloat = 0
    @State private var containerSize: CGSize = .zero

    var body: some View {
        content(topPadding, bottomPadding)
            // scaleEffect is applied here — outside the content closure — so gestureScale
            // changes drive a pure CALayer transform without re-evaluating the view tree.
            .scaleEffect(x: gestureScale, y: gestureScale, anchor: scaleAnchor)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            topPadding = geo.safeAreaInsets.top
                            bottomPadding = geo.safeAreaInsets.bottom
                            containerSize = geo.size
                        }
                        .onChange(of: geo.safeAreaInsets) { _, insets in
                            topPadding = insets.top
                            bottomPadding = insets.bottom
                        }
                        .onChange(of: geo.size) { _, size in
                            containerSize = size
                        }
                }
            }
            // highPriorityGesture: MagnifyGesture only activates on two fingers, so
            // single-finger scrolls and taps pass through naturally. When two fingers
            // are detected, this wins over child button gestures — preventing accidental
            // taps during a pinch without ever blocking the ScrollView's pan gesture.
            .highPriorityGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !anchorCaptured {
                            if containerSize != .zero {
                                let x = max(0, min(1, value.startLocation.x / containerSize.width))
                                let y = max(0, min(1, value.startLocation.y / containerSize.height))
                                scaleAnchor = UnitPoint(x: x, y: y)
                            }
                            anchorCaptured = true
                        }
                        gestureScale = max(0.4, min(3.0, value.magnification))
                    }
                    .onEnded { value in
                        let newCount = max(1, min(10, Int((CGFloat(gridColumnCount) / value.magnification).rounded())))
                        withAnimation(.easeOut(duration: 0.2)) {
                            gridColumnCount = newCount
                            gestureScale = 1.0
                        }
                        anchorCaptured = false
                    }
            )
    }
}

struct FileGridItemView: View {
    let file: DFFile
    let serverURL: URL
    let thumbnailURL: URL
    var showDetails: Bool = true
    var naturalAspect: Bool = false

    init(file: DFFile, serverURL: URL, showDetails: Bool = true, naturalAspect: Bool = false) {
        self.file = file
        self.serverURL = serverURL
        self.showDetails = showDetails
        self.naturalAspect = naturalAspect
        var components = URLComponents(
            url: serverURL.appendingPathComponent("/raw/\(file.name)"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        self.thumbnailURL = components?.url ?? serverURL
    }

    private var isMedia: Bool {
        file.mime.hasPrefix("image/") || file.mime.hasPrefix("video/")
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
        if naturalAspect && isMedia {
            naturalMediaCell
        } else {
            squareCell
        }
    }

    private var squareCell: some View {
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

                    if !isMedia && showDetails {
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
            .overlay(alignment: .bottomTrailing) { statusBadge }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var naturalMediaCell: some View {
        CachedAsyncImage(url: thumbnailURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Color(.systemGray5)
                .aspectRatio(4/3, contentMode: .fit)
        }
        .overlay(alignment: .bottomTrailing) { statusBadge }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if showDetails && (file.private || file.password != "" || file.expr != "") {
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
}

enum FileSortField: String, CaseIterable {
    case dateUploaded = "created"
    case name = "name"
    case size = "size"
    case dateCaptured = "exif_date"

    var label: String {
        switch self {
        case .dateUploaded: "Upload Date"
        case .name:         "Name"
        case .size:         "Size"
        case .dateCaptured: "Taken"
        }
    }

    var icon: String {
        switch self {
        case .dateUploaded: "calendar.badge.clock"
        case .name:         "character.cursor.ibeam"
        case .size:         "internaldrive"
        case .dateCaptured: "camera"
        }
    }
}

enum MimeTypeFilter: String, CaseIterable {
    case all        = "all"
    case image      = "image"
    case video      = "video"
    case audio      = "audio"
    case text       = "text"
    case document   = "document"
    case archive    = "archive"
    case executable = "executable"

    var label: String {
        switch self {
        case .all:        "All"
        case .image:      "Images"
        case .video:      "Videos"
        case .audio:      "Audio"
        case .text:       "Text / Code"
        case .document:   "Documents"
        case .archive:    "Archives"
        case .executable: "Executables"
        }
    }

    var icon: String {
        switch self {
        case .all:        "doc.on.doc"
        case .image:      "photo"
        case .video:      "play.rectangle"
        case .audio:      "waveform"
        case .text:       "doc.plaintext"
        case .document:   "doc.richtext"
        case .archive:    "archivebox"
        case .executable: "cpu"
        }
    }

}

