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
    let server: Binding<DjangoFilesSession?>
    
    @State private var albums: [DFAlbum] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    @State private var selectedAlbum: DFAlbum? = nil
    @State private var navigationPath = NavigationPath()
        
    var body: some View {
        ZStack {
            if isLoading && albums.isEmpty {
                LoadingView()
                    .frame(width: 100, height: 100)
            } else if let error = errorMessage {
                VStack {
                    Text("Error loading albums")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadAlbums()
                    }
                    .padding(.top)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 5)
            } else if albums.isEmpty {
                VStack {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 50))
                        .padding(.bottom)
                    Text("No albums found")
                        .font(.headline)
                    Text("Create an album to get started")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                NavigationStack(path: $navigationPath) {
                    List {
                        ForEach(albums, id: \.id) { album in
                            NavigationLink(value: album) {
                                AlbumRowView(album: album)
                                    .contextMenu {
                                        Button(action: {
                                            UIPasteboard.general.string = album.url
                                        }) {
                                            Label("Copy Link", systemImage: "link")
                                        }
                                        
                                        Button(action: {
                                            // Toggle private action
                                        }) {
                                            Label(album.private ? "Make Public" : "Make Private", 
                                                  systemImage: album.private ? "lock.open" : "lock")
                                        }
                                    }
                            }
                            .id(album.id)
                            
                            // If this is the last item and we have more pages, load more when it appears
                            if hasNextPage && album.id == albums.last?.id {
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
                    .navigationDestination(for: DFAlbum.self) { album in
                        Text("Album: \(album.name)")
                    }
                    .listStyle(.plain)
                    .refreshable {
                        refreshAlbums()
                    }
                    .listStyle(.plain)
                    .navigationTitle(server.wrappedValue != nil ? "Albums (\(URL(string: server.wrappedValue!.url)?.host ?? "unknown"))" : "Albums")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(action: {
                                    // Create album action
                                }) {
                                    Label("Create Album", systemImage: "plus")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .onChange(of: selectedAlbum) { oldValue, newValue in
                    if let album = newValue {
                        navigationPath.append(album)
                        selectedAlbum = nil // Reset after navigation
                    }
                }
            }
        }
        .onAppear {
            loadAlbums()
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
    
    private func refreshAlbums() {
        Task {
            await refreshAlbumsAsync()
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
        
        if let albumsResponse = await api.getAlbums(page: page) {
            if append {
                albums.append(contentsOf: albumsResponse.albums)
            } else {
                albums = albumsResponse.albums
            }
            
            hasNextPage = albumsResponse.next != nil
            currentPage = page
            isLoading = false
        } else {
            if !append {
                albums = []
            }
            errorMessage = "Failed to load albums from server"
            isLoading = false
        }
    }
}

struct AlbumRowView: View {
    let album: DFAlbum
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.blue)
            HStack(spacing: 5) {
                Label("\(album.view) views", systemImage: "eye")
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
                
                if album.private {
                    Label("Private", systemImage: "lock")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                }
                Text(album.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
