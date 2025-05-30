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
    
    @State private var albums: [DFAlbum] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    @State private var selectedAlbum: DFAlbum? = nil
    @State private var showDeleteConfirmation = false
    @State private var albumToDelete: DFAlbum? = nil
    @State private var showingAlbumCreator: Bool = false
        
    var body: some View {
        List {
            if isLoading && albums.isEmpty {
                HStack {
                    Spacer()
                    LoadingView()
                        .frame(width: 100, height: 100)
                    Spacer()
                }
            } else if let error = errorMessage {
                HStack {
                    Spacer()
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
                    Spacer()
                }
            } else if albums.isEmpty {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 50))
                            .padding(.bottom)
                            .shadow(color: .purple, radius: 50)
                        Text("No albums found")
                            .font(.headline)
                            .shadow(color: .purple, radius: 50)
                        Text("Create an album to get started")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(albums, id: \.id) { album in
                    NavigationLink(value: album) {
                        AlbumRowView(album: album)
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
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            Task {
                await refreshAlbumsAsync()
            }
        }
        .navigationTitle(server.wrappedValue != nil ? "Albums (\(URL(string: server.wrappedValue!.url)?.host ?? "unknown"))" : "Albums")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAlbumCreator = true
                }) {
                    Label("Create Album", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: DFAlbum.self) { album in
            FileListView(server: server, albumID: album.id, navigationPath: navigationPath, albumName: album.name)
        }
        .sheet(isPresented: $showingAlbumCreator) {
            if let serverInstance = server.wrappedValue {
                CreateAlbumView(server: serverInstance)
                    .onDisappear {
                        showingAlbumCreator = false
                    }
            }
        }
        .onChange(of: selectedAlbum) { oldValue, newValue in
            if let album = newValue {
                navigationPath.wrappedValue.append(album)
                selectedAlbum = nil // Reset after navigation
            }
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
                    Label("", systemImage: "lock")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                }
                if album.password != "" {
                    Label("", systemImage: "key")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                }
                Text(album.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(1)
            }
        }
    }
}
