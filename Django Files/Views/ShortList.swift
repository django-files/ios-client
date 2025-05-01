//
//  ShortList.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/29/25.
//

import Foundation
import SwiftUI

struct ShortListView: View {
    let server: Binding<DjangoFilesSession?>
    
    @State private var shorts: [DFShort] = []
    @State private var isLoading = false
    @State private var hasMoreResults = true
    @State private var error: String? = nil
    
    private let shortsPerPage = 50
    
    var body: some View {
        NavigationView {
            List {
                ForEach(shorts) { short in
                    ShortRow(short: short)
                }
                
                if hasMoreResults && !shorts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            loadMoreShorts()
                        }
                }
                
                if isLoading && shorts.isEmpty {
                    loadingView
                }
            }
            .listStyle(.plain)
            .refreshable{
                await refreshShorts()
            }
            .overlay {
                if shorts.isEmpty && !isLoading {
                    emptyView
                }
                
                if let error = error {
                    errorView(message: error)
                }
            }
            .navigationTitle("Short URLs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            // Create album action
                        } label: {
                            Label("Create Short", systemImage: "plus")
                        }

                        Button("Refresh") {
                            loadInitialShorts()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                if shorts.isEmpty {
                    loadInitialShorts()
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading shorts...")
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No short URLs found")
                .font(.headline)
            
            Text("Create your first short URL to get started")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Create Short URL") {
                // TODO: Implement create new short URL action
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadInitialShorts()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private func loadInitialShorts() {
        isLoading = true
        error = nil
        shorts = []
        
        Task {
            await fetchShorts()
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func refreshShorts() async {
        await MainActor.run {
            isLoading = true
            error = nil
            shorts = []
            hasMoreResults = true
        }
        
        await fetchShorts()
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func loadMoreShorts() {
        guard !isLoading, hasMoreResults else { return }
        
        Task {
            await fetchShorts()
        }
    }
    
    private func fetchShorts() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Create API client from session URL and token
        guard let url = URL(string: server.wrappedValue!.url) else {
            await MainActor.run {
                error = "Invalid session URL"
                isLoading = false
            }
            return
        }
        
        let api = DFAPI(url: url, token: server.wrappedValue!.token)
        
        // Get the ID of the last short for pagination
        let lastShortId = shorts.last?.id
        
        if let response = await api.getShorts(amount: shortsPerPage, start: lastShortId) {
            await MainActor.run {
                // Append new shorts to the existing list
                shorts.append(contentsOf: response.shorts)
                
                // Check if there might be more results
                hasMoreResults = response.shorts.count >= shortsPerPage
                error = nil
            }
        } else {
            await MainActor.run {
                error = "Failed to load shorts. Please try again."
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
}

struct ShortRow: View {
    let short: DFShort
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(short.short)
                    .font(.headline)
                    .foregroundColor(.blue)
                Text("\(short.views) uses")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(String(short.user), systemImage: "person")
                    .font(.caption)
                    .labelStyle(CustomLabel(spacing: 3))
            }
            Text(short.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
