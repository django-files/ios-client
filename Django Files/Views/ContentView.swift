//
//  ContentView.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var items: [DjangoFilesSession]
    @State private var showingEditor = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var selectedServer: DjangoFilesSession?
    @State private var selectedSession: DjangoFilesSession? // Track session for settings
    @State private var needsRefresh = false  // Added to handle refresh after adding server
    @State private var itemToDelete: DjangoFilesSession? // Track item to be deleted
    @State private var showingDeleteAlert = false // Track if delete alert is showing
    
    @State private var token: String?
        
    @State private var viewingSettings: Bool = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedServer) {
                ForEach(items, id: \.self) { item in
                    NavigationLink(value: item) {
                        Text(item.url)
                            .swipeActions() {
                                Button(role: .destructive) {
                                    itemToDelete = item
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    selectedSession = item
                                } label: {
                                    Label("Settings", systemImage: "gear")
                                }
                                .tint(.indigo)
                            }
                    }
                }
            }
            .animation(.linear, value: self.items)
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        self.showingEditor.toggle()
                    })
                    {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let server = selectedServer {
                if server.auth {
                    AuthViewContainer(
                        viewingSettings: $viewingSettings,
                        selectedServer: server,
                        columnVisibility: $columnVisibility,
                        showingEditor: $showingEditor,
                        needsRefresh: $needsRefresh
                    )
                    .id(server.url)
                } else if server.url != "" {
                    LoginView(
                        selectedServer: server,
                        onLoginSuccess: {
                            needsRefresh = true
                        }
                    )
                    .id(server.url)
                    .onAppear {
                        columnVisibility = .detailOnly
                    }
                } else {
                    Text("Loading...")
                }
            }
        }
        .sheet(isPresented: $showingEditor){
            SessionEditor(session: nil)
                .onDisappear {
                    if items.count > 0 {
                        needsRefresh = true
                        selectedServer = items.last
                    }
                }
        }
        .sheet(item: $selectedSession) { session in
            SessionSelector(session: session)
        }
        .onAppear() {
            print("Showing content view.")
            selectedServer = items.first(where: { $0.defaultSession }) ?? items.first
            if items.count == 0{
                self.showingEditor.toggle()
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete, let index = items.firstIndex(of: item) {
                    deleteItems(offsets: [index])
                    if selectedServer == item {
                        needsRefresh = true
                        selectedServer = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \(URL(string: itemToDelete?.url ?? "")?.host ?? "this server")? This action cannot be undone.")
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DjangoFilesSession.self, inMemory: true)
}
