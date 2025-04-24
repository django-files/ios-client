//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation


struct FileListView: View {
    let server: Binding<DjangoFilesSession?>
    
    @State private var files: [DFFile] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            if isLoading && files.isEmpty {
                LoadingView()
                    .frame(width: 100, height: 100)
            } else if let error = errorMessage {
                VStack {
                    Text("Error loading files")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadFiles()
                    }
                    .padding(.top)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 5)
            } else if files.isEmpty {
                VStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 50))
                        .padding(.bottom)
                    Text("No files found")
                        .font(.headline)
                    Text("Upload some files to get started")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                NavigationStack {
                    List {
                        ForEach(files, id: \.id) { file in
                            NavigationLink {
                                ContentPreview(mimeType: file.mime, fileURL: URL(string: file.raw))
                                    .toolbar {
                                        ToolbarItem(placement: .navigationBarTrailing) {
                                            Menu {
                                                FileContextMenuButtons(
                                                    onPreview: {

                                                    },
                                                    onCopyShareLink: {
                                                        // Open Maps and center it on this item.
                                                    },
                                                    onCopyRawLink: {
                                                        // Open Maps and center it on this item.
                                                    },
                                                    onSetPrivate: {
                                                        // Add this item to a list of favorites.
                                                    },
                                                    onShowInMaps: {
                                                        // Open Maps and center it on this item.
                                                    }
                                                )
                                            } label: {
                                                Image(systemName: "ellipsis.circle")
                                            }
                                        }
                                    }

                            } label: {
                                FileRowView(file: file)
                            }
                            .id(file.id)
                            
                            // If this is the last item and we have more pages, load more when it appears
                            if hasNextPage && file.id == files.last?.id {
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

                    .listStyle(.plain)
                    .refreshable {
                        await refreshFiles()
                    }
                    .navigationTitle(server.wrappedValue != nil ? "Files (\(URL(string: server.wrappedValue!.url)?.host ?? "unknown"))" : "Files")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(action: {
                                    // Upload action
                                }) {
                                    Label("Upload File", systemImage: "arrow.up.doc")
                                }

                                Button(action: {
                                    refreshFiles()
                                }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }

            }
        }
        .onAppear {
            loadFiles()
        }
    }
    
    private func loadFiles() {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        Task {
            await fetchFiles(page: currentPage)
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
    
    private func refreshFiles() {
        Task {
            await refreshFiles()
        }
    }
    
    @MainActor
    private func refreshFiles() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        await fetchFiles(page: currentPage)
    }
    
    @MainActor
    private func fetchFiles(page: Int, append: Bool = false) async {
        guard let serverInstance = server.wrappedValue, 
              let url = URL(string: serverInstance.url) else {
            errorMessage = "Invalid server URL"
            isLoading = false
            return
        }
        
        let api = DFAPI(url: url, token: serverInstance.token)
        
        if let filesResponse = await api.getFiles(page: page) {
            if append {
                files.append(contentsOf: filesResponse.files)
            } else {
                files = filesResponse.files
            }
            
            hasNextPage = filesResponse.next != nil
            currentPage = page
            isLoading = false
        } else {
            if !append {
                files = []
            }
            errorMessage = "Failed to load files from server"
            isLoading = false
        }
    }
}

struct CustomLabel: LabelStyle {
    var spacing: Double = 0.0
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

struct FileRowView: View {
    let file: DFFile
    
    @State private var showPreview: Bool = false
    
    private func getIcon() -> String {
        switch file.mime {
        case "image/jpeg":
            return "photo.artframe"
        default:
            return "doc.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.blue)
            
            HStack(spacing: 5) {
                Label(file.mime, systemImage: getIcon())
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
                
                Label(file.userUsername, systemImage: "person")
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
                
                Spacer()
                
                Text(file.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contextMenu {
            FileContextMenuButtons(
                onPreview: {
                    showPreview = true
                },
                onCopyShareLink: {
                    // Open Maps and center it on this item.
                },
                onCopyRawLink: {
                    // Open Maps and center it on this item.
                },
                onSetPrivate: {
                    // Add this item to a list of favorites.
                },
                onShowInMaps: {
                    // Open Maps and center it on this item.
                }
            )
        }
        .sheet(isPresented: $showPreview) {
            ContentPreview(mimeType: file.mime, fileURL: URL(string: file.raw))
        }
    }
}
