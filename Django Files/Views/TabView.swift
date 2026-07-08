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
    @EnvironmentObject private var previewStateManager: PreviewStateManager
    @EnvironmentObject private var uploadProgressManager: UploadProgressManager
    @ObservedObject var sessionManager: SessionManager
    @Binding var selectedTab: Tab
    
    @State private var showingServerSelector = false
    @Query private var sessions: [DjangoFilesSession]
    @State private var serverChangeRefreshTrigger = UUID()

    @State private var showLoginSheet = false
    @State private var filesNavigationPath = NavigationPath()
    @State private var albumsNavigationPath = NavigationPath()
    @State private var showFileInfo = false
    @State private var searchQuery = ""
    @State private var searchScope: SearchScope = .files

    @AppStorage("tabOrder")   private var tabOrderString   = "files,albums,shorts,streams"
    @AppStorage("hiddenTabs") private var hiddenTabsString = ""

    private var orderedVisibleTabs: [PrimaryTab] {
        let hidden = Set(hiddenTabsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })
        let order  = tabOrderString.split(separator: ",").map(String.init)
        return order.compactMap { id -> PrimaryTab? in
            guard !hidden.contains(id), let tab = PrimaryTab(rawValue: id) else { return nil }
            return tab
        }
    }

    init(sessionManager: SessionManager, selectedTab: Binding<Tab>) {
        self.sessionManager = sessionManager
        _selectedTab = selectedTab
    }
    
    enum Tab: Hashable {
        case files, albums, shorts, streams, settings, search
    }

    private enum PrimaryTab: String, Hashable {
        case files, albums, shorts, streams

        var appTab: Tab {
            switch self {
            case .files: return .files
            case .albums: return .albums
            case .shorts: return .shorts
            case .streams: return .streams
            }
        }

        var title: String {
            switch self {
            case .files: return "Files"
            case .albums: return "Albums"
            case .shorts: return "Shorts"
            case .streams: return "Streams"
            }
        }

        var icon: String {
            switch self {
            case .files: return "document.fill"
            case .albums: return "square.stack"
            case .shorts: return "link"
            case .streams: return "video.fill"
            }
        }
    }
    
    var body: some View {
        Group {
            if let server = sessionManager.selectedSession {
                Group {
                    if #available(iOS 26.0, *) {
                        modernTabView(server: server)
                    } else {
                        legacyTabView(server: server)
                    }
                }
                .onChange(of: uploadProgressManager.isUploading) { _, isUploading in
                    ToastManager.shared.bottomInset = isUploading ? 72 : 0
                }
                .onChange(of: sessionManager.selectedSession) { _, newValue in
                    if let session = newValue {
                        filesNavigationPath = NavigationPath()
                        albumsNavigationPath = NavigationPath()
                        serverChangeRefreshTrigger = UUID()
                        sessionManager.saveSelectedSession()
                        Task { await refreshUserData(session: session) }
                        Task { await sessionManager.fetchVersion() }
                    }
                }
                .onChange(of: sessionManager.selectedSession?.auth) { _, newValue in
                    if let isAuth = newValue, !isAuth {
                        if #unavailable(iOS 26.0) {
                            selectedTab = .settings
                        }
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
        .environmentObject(previewStateManager)
        .onAppear {
            sessionManager.loadLastSelectedSession(from: sessions)
            if let selectedSession = sessionManager.selectedSession {
                connectToWebSocket(session: selectedSession)
                Task { await refreshUserData(session: selectedSession) }
                Task { await sessionManager.fetchVersion() }
            }
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func modernTabView(server: DjangoFilesSession) -> some View {
        TabView(selection: $selectedTab) {
            if server.auth, let tab = orderedVisibleTab(at: 0) {
                SwiftUI.Tab(tab.title, systemImage: tab.icon, value: tab.appTab) {
                    tabContentView(for: tab.appTab, server: server)
                }
            }
            if server.auth, let tab = orderedVisibleTab(at: 1) {
                SwiftUI.Tab(tab.title, systemImage: tab.icon, value: tab.appTab) {
                    tabContentView(for: tab.appTab, server: server)
                }
            }
            if server.auth, let tab = orderedVisibleTab(at: 2) {
                SwiftUI.Tab(tab.title, systemImage: tab.icon, value: tab.appTab) {
                    tabContentView(for: tab.appTab, server: server)
                }
            }
            if server.auth, let tab = orderedVisibleTab(at: 3) {
                SwiftUI.Tab(tab.title, systemImage: tab.icon, value: tab.appTab) {
                    tabContentView(for: tab.appTab, server: server)
                }
            }
            if server.auth {
                SwiftUI.Tab(value: Tab.search, role: .search) {
                    NavigationStack {
                        SearchView(server: $sessionManager.selectedSession, searchQuery: $searchQuery, scope: $searchScope)
                    }
                    .searchable(text: $searchQuery, prompt: "Search…")
                    .searchScopes($searchScope) {
                        ForEach(SearchScope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .uploadProgressAccessoryIfAvailable(isShowing: uploadProgressManager.isUploading)
    }

    private func orderedVisibleTab(at index: Int) -> PrimaryTab? {
        guard orderedVisibleTabs.indices.contains(index) else { return nil }
        return orderedVisibleTabs[index]
    }

    @ViewBuilder
    private func legacyTabView(server: DjangoFilesSession) -> some View {
        TabView(selection: $selectedTab) {
            if server.auth {
                ForEach(orderedVisibleTabs, id: \.self) { tab in
                    tabContent(for: tab.appTab, server: server)
                }
            }
            SettingsView(sessionManager: sessionManager, showLoginSheet: $showLoginSheet)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tabBarMinimizeIfAvailable()
        .uploadProgressAccessoryIfAvailable(isShowing: uploadProgressManager.isUploading)
    }

    @ViewBuilder
    private func tabContentView(for tab: Tab, server: DjangoFilesSession) -> some View {
        switch tab {
        case .files:
            NavigationStack(path: $filesNavigationPath) {
                FileListView(server: .constant(server), albumID: nil, navigationPath: $filesNavigationPath, albumName: nil)
                    .id(serverChangeRefreshTrigger)
            }
        case .albums:
            NavigationStack(path: $albumsNavigationPath) {
                AlbumListView(navigationPath: $albumsNavigationPath, server: $sessionManager.selectedSession)
                    .id(serverChangeRefreshTrigger)
            }
        case .shorts:
            ShortListView(server: $sessionManager.selectedSession)
                .id(serverChangeRefreshTrigger)
        case .streams:
            StreamListView(server: $sessionManager.selectedSession)
                .id(serverChangeRefreshTrigger)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func tabContent(for tab: Tab, server: DjangoFilesSession) -> some View {
        switch tab {
        case .files:
            NavigationStack(path: $filesNavigationPath) {
                FileListView(server: .constant(server), albumID: nil, navigationPath: $filesNavigationPath, albumName: nil)
                    .id(serverChangeRefreshTrigger)
            }
            .tabItem { Label("Files", systemImage: "document.fill") }
            .tag(Tab.files)
        case .albums:
            NavigationStack(path: $albumsNavigationPath) {
                AlbumListView(navigationPath: $albumsNavigationPath, server: $sessionManager.selectedSession)
                    .id(serverChangeRefreshTrigger)
            }
            .tabItem { Label("Albums", systemImage: "square.stack") }
            .tag(Tab.albums)
        case .shorts:
            ShortListView(server: $sessionManager.selectedSession)
                .id(serverChangeRefreshTrigger)
                .tabItem { Label("Shorts", systemImage: "link") }
                .tag(Tab.shorts)
        case .streams:
            StreamListView(server: $sessionManager.selectedSession)
                .id(serverChangeRefreshTrigger)
                .tabItem { Label("Streams", systemImage: "video.fill") }
                .tag(Tab.streams)
        default:
            EmptyView()
        }
    }

    private func refreshUserData(session: DjangoFilesSession) async {
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        _ = await api.updateSessionWithUserData(session)
    }
    
    // Helper function to connect to WebSocket
    private func connectToWebSocket(session: DjangoFilesSession) {
        // Create the DFAPI instance
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        
        // Connect to WebSocket
        _ = api.connectToWebSocket()
    }
}


private extension View {
    @ViewBuilder
    func tabBarMinimizeIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    @ViewBuilder
    func uploadProgressAccessoryIfAvailable(isShowing: Bool) -> some View {
        if #available(iOS 26.0, *), isShowing {
            self.tabViewBottomAccessory {
                UploadProgressAccessoryView()
            }
        } else {
            self
        }
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
    
    @Query private var items: [DjangoFilesSession]

    var body: some View {
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
                                    dismiss()
                                }
                            }
                    }
                }
            }
            .sheet(item: $authSession) { session in
                if !session.auth {
                    LoginView(selectedServer: session, onLoginSuccess:{
                        selectedSession = session
                        dismiss()
                    })
                }
            }
            .onChange(of: authSession?.auth) { oldValue, newValue in
                if newValue == true {
                    authSession = nil
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
    
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}
