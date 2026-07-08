//
//  SearchView.swift
//  Django Files
//

import SwiftUI

struct SearchView: View {
    let server: Binding<DjangoFilesSession?>
    @Binding var searchQuery: String

    @State private var files: [DFFile] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedFile: DFFile? = nil
    @State private var showingPreview = false
    @State private var showFileInfo = false

    private var serverURL: URL {
        server.wrappedValue.flatMap { URL(string: $0.url) } ?? URL(string: "https://localhost")!
    }

    var body: some View {
        List {
            ForEach(files) { file in
                Button {
                    selectedFile = file
                    showingPreview = true
                } label: {
                    FileRowView(file: .constant(file), serverURL: serverURL)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay { overlay }
        .navigationTitle("Search")
        .onChange(of: searchQuery) { _, newQuery in
            searchTask?.cancel()
            guard !newQuery.isEmpty else { files = []; return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await fetchFiles(query: newQuery)
            }
        }
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
    private var overlay: some View {
        if searchQuery.isEmpty {
            ContentUnavailableView(
                "Search Files",
                systemImage: "magnifyingglass",
                description: Text("Search by filename, type, or content")
            )
        } else if files.isEmpty && !isLoading {
            ContentUnavailableView.search(text: searchQuery)
        }
    }

    @MainActor
    private func fetchFiles(query: String) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        let api = DFAPI(url: url, token: serverInstance.token)
        do {
            let response = try await api.getFiles(page: 1, selectedServer: serverInstance, search: query)
            files = response.files
        } catch {
            files = []
        }
        isLoading = false
    }
}
