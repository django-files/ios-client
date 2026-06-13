//
//  BulkAlbumPickerSheet.swift
//  Django Files
//

import SwiftUI

private enum AlbumMembership {
    case all
    case partial(Int)
    case none
}

struct BulkAlbumPickerSheet: View {
    let fileCount: Int
    let server: DjangoFilesSession?
    // fileID → current album IDs; mutated as the user toggles
    let onAlbumsChanged: ([Int: [Int]]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fileAlbums: [Int: Set<Int>]
    @State private var searchText = ""
    @State private var albums: [DFAlbum] = []
    @State private var searchResults: [DFAlbum] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isCreating = false

    init(
        files: [DFFile],
        server: DjangoFilesSession?,
        onAlbumsChanged: @escaping ([Int: [Int]]) -> Void
    ) {
        self.fileCount = files.count
        self.server = server
        self.onAlbumsChanged = onAlbumsChanged
        _fileAlbums = State(initialValue: Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, Set($0.albums)) }
        ))
    }

    // MARK: - Derived state

    private var allAssignedAlbumIDs: Set<Int> {
        fileAlbums.values.reduce(into: Set<Int>()) { $0.formUnion($1) }
    }

    private func membership(of albumID: Int) -> AlbumMembership {
        let count = fileAlbums.values.filter { $0.contains(albumID) }.count
        if count == 0 { return .none }
        if count == fileAlbums.count { return .all }
        return .partial(count)
    }

    private var displayedAlbums: [DFAlbum] {
        searchText.isEmpty ? albums : searchResults
    }

    private var hasExactNameMatch: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return displayedAlbums.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    // Albums split by membership for the non-search list
    private var inAll: [DFAlbum] {
        displayedAlbums.filter {
            if case .all = membership(of: $0.id) { return true }
            return false
        }
    }
    private var inSome: [DFAlbum] {
        displayedAlbums.filter {
            if case .partial = membership(of: $0.id) { return true }
            return false
        }
    }
    private var inNone: [DFAlbum] {
        displayedAlbums.filter {
            if case .none = membership(of: $0.id) { return true }
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    if !inAll.isEmpty {
                        Section("In All Files") {
                            ForEach(inAll) { album in
                                albumRow(album, membership: .all)
                            }
                        }
                    }

                    if !inSome.isEmpty {
                        Section("In Some Files") {
                            ForEach(inSome) { album in
                                albumRow(album, membership: membership(of: album.id))
                            }
                        }
                    }

                    if !inNone.isEmpty {
                        Section(inAll.isEmpty && inSome.isEmpty ? "Recent Albums" : "Add to All") {
                            ForEach(inNone) { album in
                                albumRow(album, membership: .none)
                            }
                        }
                    }

                    if inAll.isEmpty && inSome.isEmpty && inNone.isEmpty && !isLoading {
                        Label("No albums yet", systemImage: "photo.stack")
                            .foregroundStyle(.secondary)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        if isSearching {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            ForEach(displayedAlbums) { album in
                                albumRow(album, membership: membership(of: album.id))
                            }
                            if displayedAlbums.isEmpty {
                                Text("No albums found").foregroundStyle(.secondary)
                            }
                            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                            if !hasExactNameMatch && !trimmed.isEmpty {
                                Button {
                                    createAndAdd(name: trimmed)
                                } label: {
                                    Label("Create \"\(trimmed)\"", systemImage: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .disabled(isCreating)
                            }
                        }
                    } header: {
                        Text(isSearching ? "Searching…" : "Results")
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search or create album"
            )
            .navigationTitle("Albums — \(fileCount) Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadRecentAlbums() }
            .onChange(of: searchText) { _, newValue in handleSearchChange(newValue) }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func albumRow(_ album: DFAlbum, membership: AlbumMembership) -> some View {
        Button { toggleAlbum(album) } label: {
            HStack(spacing: 12) {
                membershipIcon(membership)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name).foregroundStyle(Color.primary)
                    if case .partial(let count) = membership {
                        Text("\(count) of \(fileCount) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if album.private {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func membershipIcon(_ membership: AlbumMembership) -> some View {
        switch membership {
        case .all:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
        case .partial:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(Color.orange)
                .font(.title3)
        case .none:
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary)
                .font(.title3)
        }
    }

    // MARK: - Toggle

    private func toggleAlbum(_ album: DFAlbum) {
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        let api = DFAPI(url: url, token: serverInstance.token)

        withAnimation {
            switch membership(of: album.id) {
            case .all:
                // Remove from all files
                for fileID in fileAlbums.keys {
                    fileAlbums[fileID]?.remove(album.id)
                }
            case .partial, .none:
                // Add to all files that don't have it
                for fileID in fileAlbums.keys {
                    fileAlbums[fileID]?.insert(album.id)
                }
            }
        }

        let snapshot = fileAlbums
        onAlbumsChanged(snapshot.mapValues { Array($0) })

        Task {
            await withTaskGroup(of: Void.self) { group in
                for (fileID, albumIDs) in snapshot {
                    let ids = Array(albumIDs)
                    group.addTask {
                        _ = await api.editFiles(
                            fileIDs: [fileID],
                            changes: ["albums": ids],
                            selectedServer: serverInstance
                        )
                    }
                }
            }
        }
    }

    // MARK: - Load / Search / Create

    private func loadRecentAlbums() {
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            if let response = try? await api.getAlbums(ordering: "-created", selectedServer: serverInstance) {
                var loaded = response.albums
                // Ensure all currently-assigned albums appear even if not in the recent list
                let loadedIDs = Set(loaded.map(\.id))
                for albumID in allAssignedAlbumIDs where !loadedIDs.contains(albumID) {
                    if let album = await api.getAlbum(albumId: albumID, selectedServer: serverInstance) {
                        loaded.insert(album, at: 0)
                    }
                }
                await MainActor.run {
                    albums = loaded
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func handleSearchChange(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchResults = albums.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        isSearching = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            if let response = try? await api.getAlbums(search: trimmed, selectedServer: serverInstance) {
                await MainActor.run {
                    guard searchText.trimmingCharacters(in: .whitespaces) == trimmed else { return }
                    var merged = response.albums
                    for album in albums where !merged.contains(where: { $0.id == album.id }) {
                        merged.append(album)
                    }
                    searchResults = merged.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
                    isSearching = false
                }
            } else {
                await MainActor.run {
                    if searchText.trimmingCharacters(in: .whitespaces) == trimmed { isSearching = false }
                }
            }
        }
    }

    private func createAndAdd(name: String) {
        guard !isCreating, let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        isCreating = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            guard let _ = await api.createAlbum(name: name, selectedServer: serverInstance) else {
                await MainActor.run { isCreating = false }
                return
            }
            if let response = try? await api.getAlbums(search: name, selectedServer: serverInstance),
               let newAlbum = response.albums.first(where: { $0.name == name }) {
                await MainActor.run {
                    if !albums.contains(where: { $0.id == newAlbum.id }) {
                        albums.insert(newAlbum, at: 0)
                    }
                    searchText = ""
                    isCreating = false
                }
                // Add to all files
                for fileID in fileAlbums.keys {
                    fileAlbums[fileID]?.insert(newAlbum.id)
                }
                let snapshot = fileAlbums
                onAlbumsChanged(snapshot.mapValues { Array($0) })
                await withTaskGroup(of: Void.self) { group in
                    for (fileID, albumIDs) in snapshot {
                        let ids = Array(albumIDs)
                        group.addTask {
                            _ = await api.editFiles(
                                fileIDs: [fileID],
                                changes: ["albums": ids],
                                selectedServer: serverInstance
                            )
                        }
                    }
                }
            } else {
                await MainActor.run { isCreating = false }
            }
        }
    }
}
