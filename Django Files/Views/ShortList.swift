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
    
    @State private var showingShortCreator: Bool = false
    
    private let shortsPerPage = 50
    
    var body: some View {
        ZStack{
            if server.wrappedValue != nil {
                NavigationStack {
                    List {
                        if shorts.isEmpty && !isLoading {
                            HStack {
                                Spacer()
                                VStack {
                                    Spacer()
                                    Image(systemName: "personalhotspot.slash")
                                        .font(.system(size: 50))
                                        .padding(.bottom)
                                        .shadow(color: .purple, radius: 50)
                                    Text("No shorts found")
                                        .font(.headline)
                                        .shadow(color: .purple, radius: 50)
                                    Text("Create a short URL to get started.")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }
                        ForEach(shorts) { short in
                            ShortRow(short: short)
                                .onTapGesture {
                                    UIPasteboard.general.string = "\(server.wrappedValue?.url ?? "")/s/\(short.short)"
                                    ToastManager.shared.showToast(message: "Short URL copied to clipboard")
                                }
                        }
                        if isLoading {
                            HStack {
                                Spacer()
                                LoadingView()
                                    .frame(width: 100, height: 100)
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable{
                        await refreshShorts()
                    }
                    .overlay {
                        if let error = error {
                            errorView(message: error)
                        }
                    }
                    .navigationTitle(server.wrappedValue != nil ? "Short URLS (\(URL(string: server.wrappedValue!.url)?.host ?? "unknown"))" : "Albums")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingShortCreator = true
                            } label: {
                                Label("Create Short", systemImage: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showingShortCreator) {
                        if let serverInstance = server.wrappedValue {
                            ShortCreatorView(server: serverInstance)
                                .onDisappear {
                                    showingShortCreator = false
                                }
                        }
                    }

                }
            } else {
                Label("No server selected.", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if shorts.isEmpty {
                loadInitialShorts()
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
        if shorts.count == 0 && !isLoading {
            error = nil
            shorts = []
            
            Task {
                await fetchShorts()
            }
        }
    }
    
    private func refreshShorts() async {
        await MainActor.run {
            error = nil
            shorts = []
        }
        Task {
            await fetchShorts()
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
        guard let url = URL(string: server.wrappedValue!.url) else {
            await MainActor.run {
                error = "Invalid session URL"
                isLoading = false
            }
            return
        }
        
        let api = DFAPI(url: url, token: server.wrappedValue!.token)
        let lastShortId = shorts.last?.id
        
        if let response = await api.getShorts(amount: shortsPerPage, start: lastShortId, selectedServer: server.wrappedValue) {
            await MainActor.run {
                shorts.append(contentsOf: response.shorts)
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
