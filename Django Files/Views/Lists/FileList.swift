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
    
    /// Apply `change` to the given files locally, reassigning the array once so a
    /// single view update covers every mutation.
    private func mutate(fileIDs: [Int], _ change: (inout DFFile) -> Void) {
        withAnimation {
            var updated = files
            for id in fileIDs {
                if let index = updated.firstIndex(where: { $0.id == id }) {
                    change(&updated[index])
                }
            }
            files = updated
        }
    }

    /// Shared server-edit path: POST the change, and mirror it locally on success.
    private func applyEdit(fileIDs: [Int], changes: [String: Any], _ change: @escaping (inout DFFile) -> Void) async -> Bool {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            return false
        }
        let api = DFAPI(url: url, token: serverInstance.token)
        let status = await api.editFiles(fileIDs: fileIDs, changes: changes, selectedServer: serverInstance)
        if status {
            mutate(fileIDs: fileIDs, change)
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
            mutate(fileIDs: [fileID]) { file in
                file.name = newName
                // The raw/thumb/share URLs embed the filename — rewrite their last components
                let urlKeyPaths: [WritableKeyPath<DFFile, String>] = [\.raw, \.thumb, \.url]
                for keyPath in urlKeyPaths {
                    if let old = URL(string: file[keyPath: keyPath]) {
                        file[keyPath: keyPath] = old.deletingLastPathComponent()
                            .appendingPathComponent(newName).absoluteString
                    }
                }
            }
            onSuccess?()
        }
        return status
    }

    func setFilePassword(fileID: Int, password: String, onSuccess: (() -> Void)?) async -> Bool {
        let status = await applyEdit(fileIDs: [fileID], changes: ["password": password]) { $0.password = password }
        if status { onSuccess?() }
        return status
    }

    func setFilePrivate(fileID: Int, isPrivate: Bool, onSuccess: (() -> Void)?) async -> Bool {
        let status = await applyEdit(fileIDs: [fileID], changes: ["private": isPrivate]) { $0.private = isPrivate }
        if status { onSuccess?() }
        return status
    }

    func updateFileAlbums(fileID: Int, albumIDs: [Int]) {
        mutate(fileIDs: [fileID]) { $0.albums = albumIDs }
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
        await applyEdit(fileIDs: fileIDs, changes: ["private": isPrivate]) { $0.private = isPrivate }
    }

    func setFileExpiration(fileID: Int, expr: String, onSuccess: (() -> Void)?) async -> Bool {
        let status = await applyEdit(fileIDs: [fileID], changes: ["expr": expr]) { $0.expr = expr }
        if status { onSuccess?() }
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
    @State private var showingSettings = false
    @State private var settingsShowLogin = false

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
    @State private var gridScrollAnchor = GridScrollAnchor()

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

    /// The user can act on (delete/edit) files they own; superusers own everything.
    private func isOwned(_ file: DFFile) -> Bool {
        (server.wrappedValue?.userID != nil && file.user == server.wrappedValue?.userID)
            || server.wrappedValue?.superUser == true
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
        if files.count > 0 { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        Task {
            await fetchFiles(page: currentPage)
            checkForDeepLinkTarget()
        }
    }
    
    // Photos-style density scaling: tighter gutters and squarer corners as cells shrink.
    private var gridSpacing: CGFloat {
        gridColumnCount >= 6 ? 1 : 2
    }

    private var gridCornerRadius: CGFloat {
        max(0, 12 - CGFloat(gridColumnCount) * 1.5)
    }

    // Zoomed-out grids show hundreds of cells per screen; scale the fetch size with
    // density so pagination keeps up (server caps are generous, cap ours at 500).
    private var pageSize: Int {
        guard isGridView else { return 25 }
        return min(500, max(25, gridColumnCount * gridColumnCount * 3))
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: gridColumnCount)
    }

    private var gridContent: some View {
        let showDetails = gridColumnCount <= 5
        let showContextMenus = gridColumnCount <= 8
        let serverURL = resolvedServerURL
        let prefetchThreshold = max(5, gridColumnCount * 3)
        // Reference-box binding: scroll tracking writes go to the box (no view
        // invalidation per row scrolled); the value is only read back when the column
        // count swaps, letting the system keep the anchor item in place (Photos-style).
        let anchorBinding = Binding<Int?>(
            get: { gridScrollAnchor.fileID },
            set: { gridScrollAnchor.fileID = $0 }
        )
        return PinchableGridContainer(gridColumnCount: $gridColumnCount) { topPad, bottomPad, width in
            let cellSize: CGFloat? = width > 0
                ? (width - gridSpacing * CGFloat(gridColumnCount - 1)) / CGFloat(gridColumnCount)
                : nil
            // Membership set built once per body evaluation — the previous per-cell
            // `files.suffix(n).contains` scan cost O(n) on every single cell appear.
            let prefetchIDs = Set(files.suffix(prefetchThreshold).map(\.id))
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                    ForEach(files) { file in
                        let isSelected = selectedFileIDs.contains(file.id)
                        let item = FileGridItemView(
                            file: file,
                            serverURL: serverURL,
                            showDetails: showDetails,
                            naturalAspect: naturalAspect,
                            cornerRadius: gridCornerRadius,
                            targetSize: cellSize
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        let base = Group {
                            if isSelectMode {
                                item
                                    .overlay(alignment: .topLeading) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(isSelected ? Color.accentColor : .white)
                                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                                            .padding(6)
                                    }
                                    .opacity(isSelected ? 1.0 : 0.6)
                            } else {
                                item
                            }
                        }
                        // Tap gesture instead of Button: press-tracking and accessibility
                        // wrappers add up across hundreds of visible cells.
                        let cell = base
                            .onTapGesture {
                                if isSelectMode {
                                    toggleSelection(file: file)
                                } else {
                                    selectedFile = file
                                    showingPreview = true
                                }
                            }
                            .onAppear {
                                if hasNextPage && prefetchIDs.contains(file.id) {
                                    loadNextPage()
                                }
                            }

                        // The modifier itself installs a UIKit interaction per cell, so
                        // it must not be attached at all when zoomed far out (hundreds
                        // of visible cells) — an empty menu closure isn't enough.
                        if showContextMenus && !isSelectMode {
                            cell.contextMenu {
                                fileContextMenu(for: file, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                            }
                        } else {
                            cell
                        }
                    }
                }
                .scrollTargetLayout()
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
            .scrollPosition(id: anchorBinding, anchor: .center)
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
            ForEach(files) { file in
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
                                    serverURL: resolvedServerURL
                                )
                                .contextMenu {
                                    fileContextMenu(for: file, isPrivate: file.private, expirationText: $expirationText, passwordText: $passwordText, fileNameText: $fileNameText)
                                } preview: {
                                    CachedAsyncImage(url: file.thumbnailURL(on: resolvedServerURL)) { image in
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
                                    serverURL: resolvedServerURL
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
                        if isOwned(file) {
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
                            Label("Select", systemImage: "checklist")
                        }
                        .disabled(files.isEmpty)
                    }

                    Divider()

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(sessionManager: sessionManager, showLoginSheet: $settingsShowLogin)
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
        guard isOwned(file) else { return }
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
        } else {
            selectedFileIDs.insert(file.id)
        }
    }

    private var ownedSelectedIDs: [Int] {
        files
            .filter { selectedFileIDs.contains($0.id) && isOwned($0) }
            .map(\.id)
    }

    private var selectedFiles: [DFFile] {
        files.filter { selectedFileIDs.contains($0.id) }
    }

    @ViewBuilder
    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                let allOwned = files.filter { isOwned($0) }
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
                            ? (files.first(where: { $0.id == ids[0] })?.name ?? "")
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
        let isOwner = isOwned(file)
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
        // Derive the page from what we already have so changing pageSize (pinch zoom)
        // never skips server offsets — integer division only ever re-fetches overlap,
        // which the append path deduplicates.
        let nextPage = (files.count / pageSize) + 1
        Task {
            await fetchFiles(page: nextPage, append: true)
        }
    }
    
    @MainActor
    private func refreshFiles() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        // Don't clear here: page 1 replaces the array atomically on success (and the
        // error path clears it), so the current content stays up during the refresh
        // instead of tearing down and rebuilding the whole grid.
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
            let filesResponse = try await api.getFiles(page: page, pageSize: pageSize, album: albumID, selectedServer: serverInstance, filterUserID: effectiveFilterUserID, filterType: filterTypeParam, ordering: sessionManager.supportsOrdering ? sortOption : nil, search: nil)
            if append {
                // Only append new files that aren't already in the list
                let existingIDs = Set(files.map(\.id))
                let newFiles = filesResponse.files.filter { !existingIDs.contains($0.id) }
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

// Plain reference type on purpose: scrollPosition(id:) writes on every row scrolled,
// and holding the value outside @State keeps those writes from re-evaluating the
// (large) file grid body.
private final class GridScrollAnchor {
    var fileID: Int?
}

private struct PinchableGridContainer<Content: View>: View {
    static var maxColumns: Int { 25 }

    @Binding var gridColumnCount: Int
    @ViewBuilder let content: (_ topPad: CGFloat, _ bottomPad: CGFloat, _ width: CGFloat) -> Content
    @State private var topPadding: CGFloat = 0
    @State private var bottomPadding: CGFloat = 0
    @State private var containerSize: CGSize = .zero

    var body: some View {
        PinchZoomLayer(gridColumnCount: $gridColumnCount, containerSize: containerSize) {
            content(topPadding, bottomPadding, containerSize.width)
        }
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
    }
}

// Owns all per-frame gesture state, and holds `content` as a pre-built value rather
// than a closure: pinch frames re-run only this body, the stored grid subtree diffs
// as unchanged, and the scale change stays a pure CALayer transform. When the state
// lived beside the content closure, every gesture frame re-evaluated the entire
// LazyVGrid ForEach.
private struct PinchZoomLayer<Content: View>: View {
    @Binding var gridColumnCount: Int
    let containerSize: CGSize
    let content: Content

    @State private var gestureScale: CGFloat = 1.0
    @State private var scaleAnchor: UnitPoint = .center
    @State private var anchorCaptured: Bool = false

    init(gridColumnCount: Binding<Int>, containerSize: CGSize, @ViewBuilder content: () -> Content) {
        self._gridColumnCount = gridColumnCount
        self.containerSize = containerSize
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(x: gestureScale, y: gestureScale, anchor: scaleAnchor)
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
                        gestureScale = max(0.2, min(3.0, value.magnification))
                    }
                    .onEnded { value in
                        // Photos-style seamless reflow: swap the column count with NO
                        // layout animation (animating it relayouts every visible cell
                        // per frame — the zoom lag), but pick the residual scale that
                        // makes the new layout's cell size exactly match what's on
                        // screen, then settle that small correction back to 1.
                        let startCount = gridColumnCount
                        let finalScale = max(0.2, min(3.0, value.magnification))
                        let newCount = max(1, min(PinchableGridContainer<Content>.maxColumns, Int((CGFloat(startCount) / finalScale).rounded())))
                        gridColumnCount = newCount
                        gestureScale = finalScale * CGFloat(newCount) / CGFloat(startCount)
                        withAnimation(.easeOut(duration: 0.18)) {
                            gestureScale = 1.0
                        }
                        anchorCaptured = false
                    }
            )
    }
}

struct FileGridItemView: View, Equatable {
    let file: DFFile
    let serverURL: URL
    var showDetails: Bool = true
    var naturalAspect: Bool = false
    var cornerRadius: CGFloat = 8
    var targetSize: CGFloat? = nil

    // Compared via .equatable() at the call site so list-wide invalidations
    // (page appends, selection changes) skip the body of every unchanged cell.
    // Only fields that affect rendering participate.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.file.id == rhs.file.id
            && lhs.file.name == rhs.file.name
            && lhs.file.mime == rhs.file.mime
            && lhs.file.private == rhs.file.private
            && lhs.file.password == rhs.file.password
            && lhs.file.expr == rhs.file.expr
            && lhs.serverURL == rhs.serverURL
            && lhs.showDetails == rhs.showDetails
            && lhs.naturalAspect == rhs.naturalAspect
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.targetSize == rhs.targetSize
    }

    // Computed in body (pruned by Equatable) instead of init: URL parsing ran for
    // every visible cell on every list-wide re-evaluation.
    private var thumbnailURL: URL {
        file.thumbnailURL(on: serverURL)
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

    private var hasBadge: Bool {
        showDetails && (file.private || file.password != "" || file.expr != "")
    }

    var body: some View {
        let core = Group {
            if naturalAspect && isMedia {
                naturalMediaCell
            } else {
                squareCell
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Badge overlay attached only when there's something to draw — a constant
        // empty overlay still costs a node on every one of hundreds of cells.
        if hasBadge {
            core.overlay(alignment: .bottomTrailing) { statusBadge }
        } else {
            core
        }
    }

    private var squareCell: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottom) {
                    if isMedia {
                        CachedAsyncImage(url: thumbnailURL, targetSize: targetSize) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5)
                        }
                    } else {
                        Color(.systemGray5)
                            .overlay {
                                Image(systemName: getIcon())
                                    // Scale to the cell — a fixed 30pt symbol overflows
                                    // (and wastes raster work on) tiny zoomed-out cells.
                                    .font(.system(size: min(30, (targetSize ?? 75) * 0.4)))
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
            }
    }

    private var naturalMediaCell: some View {
        CachedAsyncImage(url: thumbnailURL, targetSize: targetSize) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Color(.systemGray5)
                .aspectRatio(4/3, contentMode: .fit)
        }
    }

    private var statusBadge: some View {
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
