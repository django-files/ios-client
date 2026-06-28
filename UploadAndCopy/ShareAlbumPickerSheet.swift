//
//  ShareAlbumPickerSheet.swift
//  UploadAndCopy
//

import SwiftUI

struct ShareAlbumPickerSheet: View {
    let server: DjangoFilesSession?
    @Binding var selectedAlbums: [DFAlbum]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var albums: [DFAlbum] = []
    @State private var searchResults: [DFAlbum] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isCreating = false

    private var displayedAlbums: [DFAlbum] {
        searchText.isEmpty ? albums : searchResults
    }

    private var hasExactNameMatch: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return displayedAlbums.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    private func isSelected(_ album: DFAlbum) -> Bool {
        selectedAlbums.contains { $0.id == album.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section("Selected") {
                        if selectedAlbums.isEmpty && !isLoading {
                            Label("No album selected", systemImage: "photo.stack")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedAlbums) { album in
                                albumRow(album, isSelected: true)
                            }
                        }
                    }

                    let unselected = displayedAlbums.filter { !isSelected($0) }
                    if !unselected.isEmpty {
                        Section("Recent Albums") {
                            ForEach(unselected) { album in
                                albumRow(album, isSelected: false)
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
                                albumRow(album, isSelected: isSelected(album))
                            }
                            if displayedAlbums.isEmpty {
                                Text("No albums found")
                                    .foregroundStyle(.secondary)
                            }
                            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
                            if !hasExactNameMatch && !trimmed.isEmpty {
                                Button {
                                    createAndSelect(name: trimmed)
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
    private func albumRow(_ album: DFAlbum, isSelected: Bool) -> some View {
        Button {
            withAnimation {
                if isSelected {
                    selectedAlbums.removeAll { $0.id == album.id }
                } else {
                    selectedAlbums.append(album)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .animation(.default, value: isSelected)
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

    private func loadRecentAlbums() {
        guard let serverInstance = server, let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            if let response = try? await api.getAlbums(ordering: "-created", selectedServer: serverInstance) {
                await MainActor.run {
                    albums = response.albums
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func createAndSelect(name: String) {
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
            if let response = try? await api.getAlbums(search: name, selectedServer: serverInstance),
               let newAlbum = response.albums.first(where: { $0.name == name }) {
                await MainActor.run {
                    if !albums.contains(where: { $0.id == newAlbum.id }) {
                        albums.insert(newAlbum, at: 0)
                    }
                    selectedAlbums.append(newAlbum)
                    searchText = ""
                    isCreating = false
                }
            } else {
                await MainActor.run { isCreating = false }
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
                    if searchText.trimmingCharacters(in: .whitespaces) == trimmed {
                        isSearching = false
                    }
                }
            }
        }
    }
}
