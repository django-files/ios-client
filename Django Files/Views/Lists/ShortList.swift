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
    @State private var currentPage = 1
    @State private var hasNextPage = false
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var filterUserID: Int? = nil
    @State private var users: [DFUser] = []

    private var isFilteringUsers: Bool { filterUserID != server.wrappedValue?.userID }
    
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
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom)
                                    Text("No shorts found")
                                        .font(.headline)
                                    Text("Create a short URL to get started")
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await deleteShort(short) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                            if hasNextPage && short.id == shorts.last?.id {
                                Color.clear
                                    .frame(height: 20)
                                    .onAppear {
                                        loadNextPage()
                                    }
                            }
                        }
                        if isLoading && hasNextPage {
                            ProgressView()
                                .frame(width: 50, height: 50)
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
                    .navigationTitle("Short URLs")
                    .toolbar {
                        if server.wrappedValue?.superUser ?? false {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Menu {
                                    Section("Filters") {
                                        Menu {
                                            Picker("", selection: Binding(
                                                get: { filterUserID },
                                                set: { newValue in
                                                    filterUserID = newValue
                                                    Task { await refreshShorts() }
                                                }
                                            )) {
                                                Label("All Users", systemImage: "person.2")
                                                    .tag(Optional<Int>(0))
                                                ForEach(users, id: \.id) { user in
                                                    Label(user.username, systemImage: "person.circle")
                                                        .tag(Optional(user.id))
                                                }
                                            }
                                            .pickerStyle(.inline)
                                        } label: {
                                            Label("Users", systemImage: "person.2")
                                                .symbolVariant(isFilteringUsers ? .fill : .none)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal.decrease")
                                        .foregroundStyle(isFilteringUsers ? Color.accentColor : Color.primary)
                                }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            UploadMenuButton(server: server)
                        }
                    }

                }
            } else {
                Label("No server selected.", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if filterUserID == nil { filterUserID = server.wrappedValue?.userID }
            if shorts.isEmpty { loadInitialShorts() }
            if server.wrappedValue?.superUser == true {
                Task {
                    if let serverInstance = server.wrappedValue, let url = URL(string: serverInstance.url) {
                        let api = DFAPI(url: url, token: serverInstance.token)
                        users = await api.getAllUsers(selectedServer: serverInstance)
                    }
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
        guard shorts.isEmpty && !isLoading else { return }
        isLoading = true
        error = nil
        currentPage = 1
        Task {
            await fetchShorts(page: 1)
        }
    }

    private func loadNextPage() {
        guard hasNextPage && !isLoading else { return }
        isLoading = true
        Task {
            await fetchShorts(page: currentPage + 1, append: true)
        }
    }

    private func refreshShorts() async {
        error = nil
        currentPage = 1
        await fetchShorts(page: 1)
    }

    @MainActor
    private func deleteShort(_ short: DFShort) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }
        let api = DFAPI(url: url, token: serverInstance.token)
        let success = await api.deleteShort(shortID: short.id, selectedServer: serverInstance)
        if success {
            withAnimation {
                shorts.removeAll { $0.id == short.id }
            }
        }
    }

    @MainActor
    private func fetchShorts(page: Int, append: Bool = false) async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            error = "Invalid session URL"
            isLoading = false
            return
        }

        let api = DFAPI(url: url, token: serverInstance.token)

        if let response = await api.getShorts(page: page, filterUserID: filterUserID, selectedServer: serverInstance) {
            if append {
                shorts.append(contentsOf: response.shorts)
            } else {
                shorts = response.shorts
            }
            hasNextPage = response.next != nil
            currentPage = page
            error = nil
        } else {
            if !append { shorts = [] }
            error = "Failed to load shorts. Please try again."
        }

        isLoading = false
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
