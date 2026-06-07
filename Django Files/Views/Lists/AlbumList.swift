//
//  AlbumList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/29/25.
//

import SwiftUI
import SwiftData
import Foundation

struct AlbumListView: View {
    let navigationPath: Binding<NavigationPath>
    let server: Binding<DjangoFilesSession?>

    @EnvironmentObject private var albumStateManager: AlbumStateManager
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var albums: [DFAlbum] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    @State private var selectedAlbum: DFAlbum? = nil
    @State private var showDeleteConfirmation = false
    @State private var albumToDelete: DFAlbum? = nil
    @State private var filterUserID: Int? = nil
    @State private var users: [DFUser] = []
    @AppStorage("albumListSortOption") private var sortOption: String = "-created"

    private var isFilteringUsers: Bool { filterUserID != server.wrappedValue?.userID }
    private var hasActiveOptions: Bool { isFilteringUsers || (sessionManager.supportsOrdering && sortOption != "-created") }

    @ViewBuilder
    private var statusOverlay: some View {
        if let errorMessage {
            ListStatusView.error(message: errorMessage) { loadAlbums() }
        } else if albums.isEmpty && !isLoading {
            ListStatusView(
                icon: "photo.stack.fill",
                title: "No albums found",
                message: "Create an album to get started"
            )
        } else if isLoading && albums.isEmpty {
            LoadingView()
                .frame(width: 100, height: 100)
        }
    }

    var body: some View {
        List {
            ForEach(albums, id: \.id) { album in
                NavigationLink(value: album) {
                    AlbumRowView(album: album, session: server.wrappedValue)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = album.url
                            }) {
                                Label("Copy Link", systemImage: "link")
                            }

                            Button(role: .destructive, action: {
                                albumToDelete = album
                                showDeleteConfirmation = true
                            }) {
                                Label("Delete Album", systemImage: "trash")
                            }
                        }
                }
                .id(album.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button() {
                        albumToDelete = album
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }

                if hasNextPage && album.id == albums.last?.id {
                    Color.clear
                        .frame(height: 20)
                        .onAppear {
                            loadNextPage()
                        }
                }
            }

            if isLoading && hasNextPage {
                ProgressView()
                    .frame(width: 50, height: 50)
            }
        }
        .listStyle(.plain)
        .refreshable {
            Task {
                await refreshAlbumsAsync()
            }
        }
        .overlay { statusOverlay }
        .navigationTitle("Albums")
        .toolbar {
            if sessionManager.supportsOrdering || (server.wrappedValue?.superUser ?? false) {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        if sessionManager.supportsOrdering {
                            Menu {
                                Picker("", selection: $sortOption) {
                                    ForEach(AlbumSortOption.allCases, id: \.rawValue) { option in
                                        Label(option.label, systemImage: option.icon).tag(option.rawValue)
                                    }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                                    .symbolVariant(sortOption != "-created" ? .fill : .none)
                            }
                        }
                        if server.wrappedValue?.superUser ?? false {
                            Menu {
                                Picker("", selection: Binding(
                                    get: { filterUserID },
                                    set: { newValue in
                                        filterUserID = newValue
                                        Task { await refreshAlbumsAsync() }
                                    }
                                )) {
                                    Label("All Users", systemImage: "person.2")
                                        .tag(Optional<Int>(0))
                                    ForEach(users, id: \.id) { user in
                                        Label(user.username, systemImage: "person.circle")
                                            .tag(Optional(user.id))
                                    }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                Label("Users", systemImage: "person.2")
                                    .symbolVariant(isFilteringUsers ? .fill : .none)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(hasActiveOptions ? Color.accentColor : Color.primary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                UploadMenuButton(server: server)
            }
        }
        .navigationDestination(for: DFAlbum.self) { album in
            FileListView(server: server, albumID: album.id, navigationPath: navigationPath, albumName: album.name)
        }
        .onChange(of: selectedAlbum) { oldValue, newValue in
            if let album = newValue {
                navigationPath.wrappedValue.append(album)
                selectedAlbum = nil // Reset after navigation
            }
        }
        .onChange(of: albumStateManager.deepLinkNavigationAlbumID) { _, _ in
            navigateToPendingDeepLink()
        }
        .onChange(of: sortOption) { _, _ in
            Task { await refreshAlbumsAsync() }
        }
        .confirmationDialog("Are you sure?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let album = albumToDelete {
                    Task {
                        await deleteAlbum(album)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                // Optional: No action needed for cancel
            }
        } message: {
            Text("Are you sure you want to delete \"\(String(describing: albumToDelete?.name ?? "Unknown Album"))\"?")
        }
        .onAppear {
            if filterUserID == nil { filterUserID = server.wrappedValue?.userID }
            loadAlbums()
            navigateToPendingDeepLink()
            if server.wrappedValue?.superUser == true {
                Task {
                    if let serverInstance = server.wrappedValue, let url = URL(string: serverInstance.url) {
                        let api = DFAPI(url: url, token: serverInstance.token)
                        users = await api.getAllUsers(selectedServer: serverInstance)
                    }
                }
            }
        }
    }

    private func navigateToPendingDeepLink() {
        guard let albumID = albumStateManager.deepLinkNavigationAlbumID else { return }
        albumStateManager.deepLinkNavigationAlbumID = nil
        albumStateManager.deepLinkNavigationAlbumName = nil

        // Use the already-loaded album when available (real name, no extra request)
        if let existing = albums.first(where: { $0.id == albumID }) {
            navigationPath.wrappedValue.append(existing)
            return
        }

        // Fetch from the API so the title is correct
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }

        Task { @MainActor in
            let api = DFAPI(url: url, token: serverInstance.token)
            if let album = await api.getAlbum(albumId: albumID, selectedServer: serverInstance) {
                navigationPath.wrappedValue.append(album)
            }
        }
    }
    
    private func loadAlbums() {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        Task {
            await fetchAlbums(page: currentPage)
        }
    }
    
    private func loadNextPage() {
        guard hasNextPage else { return }
        guard !isLoading else { return }  // Prevent multiple simultaneous loading requests
        isLoading = true
        
        Task {
            await fetchAlbums(page: currentPage + 1, append: true)
        }
    }
    
    @MainActor
    private func refreshAlbumsAsync() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        await fetchAlbums(page: currentPage)
    }
    
    @MainActor
    private func fetchAlbums(page: Int, append: Bool = false) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            errorMessage = "Invalid server URL"
            isLoading = false
            return
        }

        let api = DFAPI(url: url, token: serverInstance.token)

        do {
            let albumsResponse = try await api.getAlbums(page: page, filterUserID: filterUserID, ordering: sessionManager.supportsOrdering ? sortOption : nil, selectedServer: serverInstance)
            if append {
                albums.append(contentsOf: albumsResponse.albums)
            } else {
                albums = albumsResponse.albums
            }
            hasNextPage = albumsResponse.next != nil
            currentPage = page
            errorMessage = nil
        } catch {
            if !append { albums = [] }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    @MainActor
    private func deleteAlbum(_ album: DFAlbum) async {
        guard let serverInstance = server.wrappedValue else { return }
        
        let api = DFAPI(url: URL(string: serverInstance.url)!, token: serverInstance.token)
        
        if await api.deleteAlbum(albumId: album.id) {
            withAnimation{
                if let index = albums.firstIndex(where: { $0.id == album.id }) {
                    albums.remove(at: index)
                }
            }
        } else {
            ToastManager.shared.showToast(message: "Failed to delete album")
        }
        
        albumToDelete = nil
    }
}

enum AlbumSortOption: String, CaseIterable {
    case newestFirst = "-created"
    case oldestFirst = "created"
    case nameAZ = "name"
    case nameZA = "-name"
    case mostFiles = "-files"
    case fewestFiles = "files"

    var label: String {
        switch self {
        case .newestFirst:  "Newest First"
        case .oldestFirst:  "Oldest First"
        case .nameAZ:       "Name A–Z"
        case .nameZA:       "Name Z–A"
        case .mostFiles:    "Most Files"
        case .fewestFiles:  "Fewest Files"
        }
    }

    var icon: String {
        switch self {
        case .newestFirst:  "arrow.down.calendar"
        case .oldestFirst:  "arrow.up.calendar"
        case .nameAZ:       "textformat.abc"
        case .nameZA:       "textformat.abc"
        case .mostFiles:    "photo.stack"
        case .fewestFiles:  "photo"
        }
    }
}

struct AlbumRowView: View {
    let album: DFAlbum
    let session: DjangoFilesSession?

    var body: some View {
        HStack(alignment: .center) {
            AlbumThumbnailGrid(albumID: album.id, session: session)
                .frame(width: 64, height: 64)
                .cornerRadius(8)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(album.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.blue)

                HStack(spacing: 6) {
                    Label("\(album.view)", systemImage: "eye")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                    Label("", systemImage: "lock")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(album.private ? 1 : 0)
                    Label("", systemImage: "key")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity((album.password ?? "").isEmpty ? 0 : 1)
                }

                Text(album.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct AlbumThumbnailGrid: View {
    let albumID: Int
    let session: DjangoFilesSession?

    @State private var thumbURLs: [URL] = []

    var body: some View {
        Group {
            if thumbURLs.isEmpty {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 28))
                    .frame(width: 64, height: 64)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundStyle(.secondary)
            } else {
                let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        if i < thumbURLs.count {
                            CachedAsyncImage(url: thumbURLs[i]) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.12)
                            }
                            .frame(width: 31, height: 31)
                            .clipped()
                        } else {
                            Color.secondary.opacity(0.07)
                                .frame(width: 31, height: 31)
                        }
                    }
                }
                .frame(width: 64, height: 64)
            }
        }
        .task(id: albumID) {
            await loadThumbnails()
        }
    }

    private func loadThumbnails() async {
        guard let session, let url = URL(string: session.url) else { return }
        let api = DFAPI(url: url, token: session.token)
        guard let response = try? await api.getFiles(page: 1, album: albumID, selectedServer: session) else { return }
        let urls = response.files
            .filter { $0.mime.hasPrefix("image/") }
            .prefix(4)
            .compactMap { URL(string: $0.thumb) }
        await MainActor.run { thumbURLs = Array(urls) }
    }
}
