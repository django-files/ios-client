//
//  SearchView.swift
//  Django Files
//

import SwiftUI

enum SearchScope: String, CaseIterable {
    case files = "Files"
    case albums = "Albums"
    case shorts = "Shorts"
    case streams = "Streams"
}

struct SearchView: View {
    let server: Binding<DjangoFilesSession?>
    @Binding var searchQuery: String
    @Binding var scope: SearchScope

    @State private var searchTask: Task<Void, Never>? = nil

    @State private var files: [DFFile] = []
    @State private var albums: [DFAlbum] = []
    @State private var shorts: [DFShort] = []
    @State private var streams: [DFStream] = []

    @State private var isLoading = false
    @State private var selectedFile: DFFile? = nil
    @State private var showingPreview = false
    @State private var showFileInfo = false

    private var serverURL: URL {
        server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
    }

    var body: some View {
        List {
            listContent
        }
        .listStyle(.plain)
        .overlay { overlay }
        .navigationTitle("Search")
        .onChange(of: scope) { _, _ in triggerSearch() }
        .onChange(of: searchQuery) { _, _ in triggerSearch() }
        .fullScreenCover(isPresented: $showingPreview) {
            if let file = selectedFile,
               let index = files.firstIndex(where: { $0.id == file.id }) {
                FilePreviewView(
                    file: .constant(file),
                    server: server,
                    showingPreview: $showingPreview,
                    showFileInfo: $showFileInfo,
                    fileListDelegate: nil,
                    allFiles: .constant(files),
                    currentIndex: index,
                    onNavigate: { _ in },
                    onLoadMore: nil
                )
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch scope {
        case .files:
            ForEach(files) { file in
                Button {
                    selectedFile = file
                    showingPreview = true
                } label: {
                    FileRowView(file: .constant(file), serverURL: serverURL)
                }
                .buttonStyle(.plain)
            }
        case .albums:
            ForEach(albums) { album in
                AlbumRowView(album: album, session: server.wrappedValue)
            }
        case .shorts:
            ForEach(shorts) { short in
                ShortRow(short: short)
            }
        case .streams:
            ForEach(streams) { stream in
                StreamRow(stream: stream)
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if searchQuery.isEmpty {
            ContentUnavailableView(
                "Search \(scope.rawValue)",
                systemImage: "magnifyingglass",
                description: Text("Search by name or content")
            )
        } else if !isLoading && currentResults == 0 {
            ContentUnavailableView.search(text: searchQuery)
        }
    }

    private var currentResults: Int {
        switch scope {
        case .files:   return files.count
        case .albums:  return albums.count
        case .shorts:  return shorts.count
        case .streams: return streams.count
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty else {
            files = []; albums = []; shorts = []; streams = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await fetchResults(query: searchQuery, scope: scope)
        }
    }

    @MainActor
    private func fetchResults(query: String, scope: SearchScope) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        let api = DFAPI(url: url, token: serverInstance.token)
        do {
            switch scope {
            case .files:
                let response = try await api.getFiles(page: 1, selectedServer: serverInstance, search: query)
                files = response.files
            case .albums:
                let response = try await api.getAlbums(search: query, selectedServer: serverInstance)
                albums = response.albums
            case .shorts:
                let response = try await api.getShorts(selectedServer: serverInstance)
                let q = query.lowercased()
                shorts = response.shorts.filter {
                    $0.short.lowercased().contains(q) || $0.url.lowercased().contains(q)
                }
            case .streams:
                let response = try await api.getStreams(selectedServer: serverInstance)
                let q = query.lowercased()
                streams = response.streams.filter {
                    $0.name.lowercased().contains(q) || $0.title.lowercased().contains(q)
                }
            }
        } catch {
            files = []; albums = []; shorts = []; streams = []
        }
        isLoading = false
    }
}
