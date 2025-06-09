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
    @Binding var selectedTab: Tab
    
    @State private var showingServerSelector = false
    @Query private var sessions: [DjangoFilesSession]
    @State private var needsRefresh = false
    @State private var serverChangeRefreshTrigger = UUID()
    @State private var serverNeedsAuth: DjangoFilesSession?
    
    @State private var showLoginSheet = false
    @State private var filesNavigationPath = NavigationPath()
    @State private var albumsNavigationPath = NavigationPath()
    
    init(sessionManager: SessionManager, selectedTab: Binding<Tab>) {
        self.sessionManager = sessionManager
        _selectedTab = selectedTab
    }
    
    enum Tab {
        case files, albums, shorts, settings, mobileWeb
    }
    
    var body: some View {
        Group {
            if let server = sessionManager.selectedSession {
                TabView(selection: $selectedTab) {
                    if server.auth {
                        NavigationStack(path: $filesNavigationPath) {
                            FileListView(server: .constant(server), albumID: nil, navigationPath: $filesNavigationPath, albumName: nil)
                                .id(serverChangeRefreshTrigger)
                        }
                        .tabItem {
                            Label("Files", systemImage: "document.fill")
                        }
                        .tag(Tab.files)
                        
                        NavigationStack(path: $albumsNavigationPath) {
                            AlbumListView(navigationPath: $albumsNavigationPath, server: $sessionManager.selectedSession)
                                .id(serverChangeRefreshTrigger)
                        }
                        .tabItem {
                            Label("Albums", systemImage: "square.stack")
                        }
                        .tag(Tab.albums)
                        
                        ShortListView(server: $sessionManager.selectedSession)
                            .id(serverChangeRefreshTrigger)
                            .tabItem {
                                Label("Shorts", systemImage: "link")
                            }
                            .tag(Tab.shorts)
                    }
                    
                    SettingsView(sessionManager: sessionManager, showLoginSheet: $showLoginSheet)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(Tab.settings)
                }
                .onChange(of: sessionManager.selectedSession) { oldValue, newValue in
                    if let session = newValue {
                        sessionManager.saveSelectedSession()
                        connectToWebSocket(session: session)
                        serverChangeRefreshTrigger = UUID()
                        if !session.auth {
                            selectedTab = .settings
                            showLoginSheet = true
                        }
                    }
                }
                .onChange(of: sessionManager.selectedSession?.auth) { oldValue, newValue in
                    if let isAuth = newValue, !isAuth {
                        selectedTab = .settings
                        showLoginSheet = true
                    }
                }
            } else {
                SettingsView(sessionManager: sessionManager, showLoginSheet: $showLoginSheet)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(Tab.settings)
            }
        }
        .onAppear {
            sessionManager.loadLastSelectedSession(from: sessions)
            
            // Update user data and connect to WebSocket if a session is selected
            if let selectedSession = sessionManager.selectedSession {
                // Create the DFAPI instance
                let api = DFAPI(url: URL(string: selectedSession.url)!, token: selectedSession.token)
                
                // Update user data if authenticated
                if selectedSession.auth {
                    Task {
                        await api.updateSessionWithUserData(selectedSession)
                    }
                }
                
                connectToWebSocket(session: selectedSession)
            }
        }
    }
    
    // Helper function to connect to WebSocket
    private func connectToWebSocket(session: DjangoFilesSession) {
        // Create the DFAPI instance
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        
        // Connect to WebSocket
        print("TabViewWindow: Connecting to WebSocket for session \(session.url)")
        _ = api.connectToWebSocket()
    }
}

struct ServerSelector: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedSession: DjangoFilesSession?
    @State private var itemToDelete: DjangoFilesSession?
    @State private var showingDeleteAlert = false
    @State private var showAddServerSheet = false
    @State private var editSession: DjangoFilesSession?
    @State private var authSession: DjangoFilesSession?
    
    @State private var navigationPath = NavigationPath()
    
    @Query private var items: [DjangoFilesSession]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(selection: $selectedSession) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 0) {
                        Label("", systemImage: item.defaultSession ? "star.fill" : "")
                        Label("", systemImage: item.auth ? "person.fill" : "person")
                        Text(item.url)
                            .swipeActions {
                                Button {
                                    itemToDelete = item
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                .tint(.red)
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
            .sheet(isPresented: $showAddServerSheet) {
                SessionEditor(onBoarding: false, session: nil)
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
                        self.showAddServerSheet.toggle()
                    }) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Server List")
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
