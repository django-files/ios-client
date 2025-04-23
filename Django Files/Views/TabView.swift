//
//  TabView.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/19/25.
//

import SwiftUI
import SwiftData

struct TabViewWindow: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var sessionManager: SessionManager
    
    @State private var showingServerSelector = false
    @Query private var sessions: [DjangoFilesSession]
    @State private var needsRefresh = false
    
    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    var body: some View {
        TabView {
            Tab("Files", systemImage: "document.fill") {
                FileListView(server: $sessionManager.selectedSession)
            }
            
            Tab("Gallery", systemImage: "photo.artframe") {
                //                ReceivedView()
            }
            
            Tab("Albums", systemImage: "square.stack") {
                //                ReceivedView()
            }
            
            
            Tab("Shorts", systemImage: "link") {
                //                SentView()
            }
            
            Tab("Web", systemImage: "globe"){
                if let selectedSession = sessionManager.selectedSession {
                    AuthViewContainer(
                        selectedServer: selectedSession,
                        needsRefresh: $needsRefresh
                    )
                    .id(selectedSession.url)
                } else {
                    Text("Please select a server")
                }
            }

            Tab("Server List", systemImage: "server.rack") {
                ServerSelector(selectedSession: $sessionManager.selectedSession)
            }
        }
        .onAppear {
            sessionManager.loadLastSelectedSession(from: sessions)
        }
        .onChange(of: sessionManager.selectedSession) { oldValue, newValue in
            if newValue != nil {
                sessionManager.saveSelectedSession()
            }
        }
        .navigationTitle(Text("Servers"))

    }
}

struct ServerSelector: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedSession: DjangoFilesSession?
    @State private var itemToDelete: DjangoFilesSession?  // Track item to be deleted
    @State private var showingDeleteAlert = false  // Track if delete alert is showing
    @State private var showingEditor = false
    @State private var editSession: DjangoFilesSession?
    @State private var authSession: DjangoFilesSession?
    
    @State private var showLoginSheet: Bool = false
    
    @Query private var items: [DjangoFilesSession]
    
    var body: some View {
            List(selection: $selectedSession) {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Label("", systemImage: item.defaultSession ? "star.fill" : "")
                        Text(item.url)
                        .swipeActions {
                            Button(role: .destructive) {
                                itemToDelete = item
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            Button {
                                editSession = item
                            } label: {
                                Label("Settings", systemImage: "gear")
                            }
                            .tint(.indigo)
                        }
                        .onTapGesture {
                            if !item.auth {
                                authSession = item
                            } else {
                                selectedSession = item
                            }
                        }
                    }
                }
            }
            .sheet(item: $authSession) { session in
                if !session.auth {
                    LoginView(selectedServer: session, onLoginSuccess:{
                        selectedSession = session
                    })
                }
            }
            .sheet(item: $editSession) { session in
                SessionSelector(session: session)
            }
            .sheet(isPresented: $showingEditor) {
                SessionEditor(session: nil)
            }
            .confirmationDialog("Delete Server", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete,
                        let index = items.firstIndex(of: item)
                    {
                        deleteItems(offsets: [index])
                        if selectedSession == item {
                            selectedSession = nil
                        }
                    }
                }
            } message: {
                 Text(
                     "Are you sure you want to delete \(URL(string: itemToDelete?.url ?? "")?.host ?? "this server")? This action cannot be undone."
                 )
             }
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        self.showingEditor.toggle()
                    }) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Servers")


    }
    
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
                print("Deleting items: \(offsets)")
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}
