//
//  FileList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData
import Foundation

// Make sure we have the proper imports
@_implementationOnly import Django_Files

struct FileListView: View {
    let server: DjangoFilesSession
    
    @State private var files: [DFFile] = []
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            Color.djangoFilesBackground.ignoresSafeArea()
            
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
                List {
                    ForEach(files, id: \.id) { file in
                        FileRowView(file: file)
                    }
                    
                    if hasNextPage {
                        HStack {
                            Spacer()
                            Button("Load More") {
                                loadNextPage()
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await refreshFiles()
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
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
        guard let url = URL(string: server.url) else {
            errorMessage = "Invalid server URL"
            isLoading = false
            return
        }
        
        let api = DFAPI(url: url, token: server.token)
        
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

struct FileRowView: View {
    let file: DFFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
                .font(.headline)
            
            HStack(spacing: 12) {
                Label(file.mime, systemImage: "doc.fill")
                    .font(.caption)
                
                Label("User: \(file.user)", systemImage: "person")
                    .font(.caption)
                
                Spacer()
                
                Text(file.formattedDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
