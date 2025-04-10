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
    @State private var showSidebarButton: Bool = false
    @State private var showingEditor = false
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    @State private var selectedServer: DjangoFilesSession?
    @State private var selectedSession: DjangoFilesSession? // Track session for settings
    @State private var showingSelector = false // Show SessionSelector
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
                .onDelete(perform: deleteItems)
            }
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
            .toolbar(removing: !showSidebarButton ? .sidebarToggle : nil)
        } detail: {
            if let server = selectedServer {
                if server.auth {
                    AuthViewContainer(
                        viewingSettings: $viewingSettings,
                        selectedServer: server,
                        columnVisibility: $columnVisibility,
                        showingEditor: $showingEditor,
                        needsRefresh: $needsRefresh,
                        showSidebarButton: $showSidebarButton
                    )
                    .id(server.url)
                    .onAppear {
                        showSidebarButton = false
                        columnVisibility = .detailOnly
                    }
                } else {
                    LoginView(
                        selectedServer: server,
                        onLoginSuccess: {
                            needsRefresh = true
                            showSidebarButton = false
                        }
                    )
                    .id(server.url)
                    .onAppear {
                        showSidebarButton = true
                        columnVisibility = .detailOnly
                    }
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
            selectedServer = items.first(where: { $0.defaultSession }) ?? items.first
            if items.count == 0{
                self.showingEditor.toggle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
        .alert("Delete Server", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete, let index = items.firstIndex(of: item) {
                    deleteItems(offsets: [index])
                }
            }
        } message: {
            Text("Are you sure you want to delete this server? This action cannot be undone.")
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

public struct AuthViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode: Binding<PresentationMode>
    @Query private var items: [DjangoFilesSession]
    
    var viewingSettings: Binding<Bool>
    let selectedServer: DjangoFilesSession
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    var showingEditor: Binding<Bool>
    var needsRefresh: Binding<Bool>
    var showSidebarButton: Binding<Bool>
    
    @State private var authController: AuthController = AuthController()
    
    var backButton : some View { Button(action: {
        self.presentationMode.wrappedValue.dismiss()
        }) {
            HStack {
                if !UIDevice.current.localizedModel.contains("iPad") {
                    Text("Server List")
                }
            }
        }
    }
    public var body: some View {
            if viewingSettings.wrappedValue{
                SessionSelector(session: selectedServer, viewingSelect: viewingSettings)
                    .onAppear(){
                        columnVisibility.wrappedValue = .automatic
                    }
            }
            else if selectedServer.url != "" {
                ZStack{
                    Color.djangoFilesBackground.ignoresSafeArea()
                    LoadingView().frame(width: 100, height: 100)
                    AuthView(
                        authController: authController,
                        httpsUrl: selectedServer.url,
                        doReset: authController.url?.absoluteString ?? "" != selectedServer.url || !selectedServer.auth,
                        session: selectedServer
                        )
                        .onStartedLoading {
                        }
                        .onCancelled {
                            dismiss()
                        }
                        .onAppear(){
                            showSidebarButton.wrappedValue = false
                            columnVisibility.wrappedValue = .detailOnly
                            if needsRefresh.wrappedValue {
                                authController.reset()
                                needsRefresh.wrappedValue = false
                            }
                            
                            authController.onStartedLoadingAction = {
                            }
                            
                            authController.onCancelledAction = {
                                dismiss()
                            }
                            
                            authController.onSchemeRedirectAction = {
                                guard let resolve = authController.schemeURL else{
                                    return
                                }
                                switch resolve{
                                case "serverlist":
                                    if UIDevice.current.userInterfaceIdiom == .phone{
                                        self.presentationMode.wrappedValue.dismiss()
                                    }
                                    showSidebarButton.wrappedValue = true
                                    columnVisibility.wrappedValue = .all
                                    break
                                case "serversettings":
                                    viewingSettings.wrappedValue = true
                                    break
                                case "logout":
                                    selectedServer.auth = false
                                    showSidebarButton.wrappedValue = true
                                    columnVisibility.wrappedValue = .automatic
                                    self.presentationMode.wrappedValue.dismiss()
                                    break
                                default:
                                    return
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .navigationTitle(Text(""))
                .navigationBarHidden(true)
            }
            else {
                Text("Loading...")
                    .onAppear(){
                        columnVisibility.wrappedValue = .all
                    }
            }
    }
}

struct LoadingView: View {
    @State private var isLoading = false
    @State private var firstAppear = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.8)
            .stroke(Color.launchScreenBackground, lineWidth: 5)
            .rotationEffect(Angle(degrees: isLoading ? 360 : 0))
            .opacity(firstAppear ? 1 : 0)
            .onAppear(){
                DispatchQueue.main.async {
                    if isLoading == false{
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)){
                            isLoading.toggle()
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.25)){
                        firstAppear = true
                    }
                }
            }
            .onDisappear(){
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)){
                        firstAppear = true
                    }
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DjangoFilesSession.self, inMemory: true)
}
