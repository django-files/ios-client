//
//  AlbumPickerSheet.swift
//  Django Files
//

import SwiftUI

struct AlbumPickerSheet: View {
    let file: DFFile
    let server: DjangoFilesSession?
    let onAlbumsChanged: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var currentAlbumIDs: [Int]
    @State private var albums: [DFAlbum] = []
    @State private var searchResults: [DFAlbum] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isCreating = false
    private var searchTask: Task<Void, Never>? = nil

    init(file: DFFile, server: DjangoFilesSession?, onAlbumsChanged: @escaping ([Int]) -> Void) {
        self.file = file
        self.server = server
        self.onAlbumsChanged = onAlbumsChanged
        _currentAlbumIDs = State(initialValue: file.albums)
    }

    private var displayedAlbums: [DFAlbum] {
        searchText.isEmpty ? albums : searchResults
    }

    private var hasExactNameMatch: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return displayedAlbums.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section("In Albums") {
                        if displayedAlbums.filter({ currentAlbumIDs.contains($0.id) }).isEmpty && !isLoading {
                            Label("Not in any album", systemImage: "photo.stack")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(displayedAlbums.filter { currentAlbumIDs.contains($0.id) }) { album in
                                albumRow(album, isAssigned: true)
                            }
                        }
                    }

                    let unassigned = displayedAlbums.filter { !currentAlbumIDs.contains($0.id) }
                    if !unassigned.isEmpty {
                        Section("Recent Albums") {
                            ForEach(unassigned) { album in
                                albumRow(album, isAssigned: false)
                            }
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        if isSearching {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(displayedAlbums) { album in
                                albumRow(album, isAssigned: currentAlbumIDs.contains(album.id))
                            }
                            if displayedAlbums.isEmpty {
                                Text("No albums found")
                                    .foregroundStyle(.secondary)
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
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadRecentAlbums() }
            .onChange(of: searchText) { _, newValue in
                handleSearchChange(newValue)
            }
        }
    }

    @ViewBuilder
    private func albumRow(_ album: DFAlbum, isAssigned: Bool) -> some View {
        Button {
            toggleAlbum(album)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isAssigned ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .animation(.default, value: isAssigned)
                Text(album.name)
                    .foregroundStyle(Color.primary)
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

    private func toggleAlbum(_ album: DFAlbum) {
        withAnimation {
            if currentAlbumIDs.contains(album.id) {
                currentAlbumIDs.removeAll { $0 == album.id }
            } else {
                currentAlbumIDs.append(album.id)
            }
        }
        let ids = currentAlbumIDs
        onAlbumsChanged(ids)
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            _ = await api.editFiles(fileIDs: [file.id], changes: ["albums": ids], selectedServer: serverInstance)
        }
    }

    private func createAndAdd(name: String) {
        guard !isCreating,
              let serverInstance = server,
              let url = URL(string: serverInstance.url) else { return }
        isCreating = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            guard let _ = await api.createAlbum(name: name, selectedServer: serverInstance) else {
                await MainActor.run { isCreating = false }
                return
            }
            // Find the newly created album by searching for its exact name
            if let response = try? await api.getAlbums(search: name, selectedServer: serverInstance),
               let newAlbum = response.albums.first(where: { $0.name == name }) {
                await MainActor.run {
                    if !albums.contains(where: { $0.id == newAlbum.id }) {
                        albums.insert(newAlbum, at: 0)
                    }
                    currentAlbumIDs.append(newAlbum.id)
                    searchText = ""
                    isCreating = false
                }
                let ids = currentAlbumIDs
                onAlbumsChanged(ids)
                _ = await api.editFiles(fileIDs: [file.id], changes: ["albums": ids], selectedServer: serverInstance)
            } else {
                await MainActor.run { isCreating = false }
            }
        }
    }

    private func loadRecentAlbums() {
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            if let response = try? await api.getAlbums(ordering: "-created", selectedServer: serverInstance) {
                var loaded = response.albums
                // Fetch any assigned albums missing from the recent list
                let loadedIDs = Set(loaded.map { $0.id })
                for id in file.albums where !loadedIDs.contains(id) {
                    if let album = await api.getAlbum(albumId: id, selectedServer: serverInstance) {
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
        // Immediate local filter for snappy feedback
        searchResults = albums.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        // Server search for broader results
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
                    if searchText.trimmingCharacters(in: .whitespaces) == trimmed {
                        isSearching = false
                    }
                }
            }
        }
    }
}
