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
    @State private var showingLogin = false
    @State private var runningSession = false
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    @State private var selectedServer: DjangoFilesSession?
    @State private var selectedSession: DjangoFilesSession? // Track session for settings
    @State private var showingSelector = false // Show SessionSelector
    @State private var needsRefresh = false  // Added to handle refresh after adding server
    
    @State private var token: String?
        
    @State private var viewingSettings: Bool = false
    
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedServer) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        Text(item.url)
                            .swipeActions() {
                                Button(role: .destructive) {
                                    deleteItems(offsets: [items.firstIndex(of: item)!])
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
        } detail: {
            if let server = selectedServer {
                if server.auth {
                    AuthViewContainer(viewingSettings: $viewingSettings, selectedServer: server, columnVisibility: $columnVisibility, showingEditor: $showingEditor, needsRefresh: $needsRefresh)
                } else {
                    LoginView(
                        selectedServer: server,
                        onLoginSuccess: {
                            print("Login success")
                            needsRefresh = true
                        }
                    )
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
            setDefaultServer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }

    private func setDefaultServer(){
        if items.count > 0{
            var server = items.first(where: {
                return $0.defaultSession == true
            })
            if server == nil {
                server = items.first(where: {
                    return $0.auth
                })
                if server != nil{
                    server?.defaultSession = true
                }
            }
        }
        if items.count == 0{
            self.showingEditor.toggle()
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        setDefaultServer()
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
    
    @State private var toolbarHidden: Bool = false
    @State private var authError: Bool = false
    @State private var authController: AuthController = AuthController()
    
    var backButton : some View { Button(action: {
        self.presentationMode.wrappedValue.dismiss()
        }) {
            HStack {
                if !UIDevice.current.localizedModel.contains("iPad") {
//                    Image("backImage")
//                        .aspectRatio(contentMode: .fit)
//                        .foregroundColor(.white)
                    Text("Server List")
                }
            }
        }
    }
    public var body: some View {
        GeometryReader { geometry in
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
                            toolbarHidden = false
                        }
                        .onCancelled {
                            dismiss()
                            toolbarHidden = false
                            authError = true
                        }
                        .onSchemeRedirect {
                            guard let resolve = authController.schemeURL else{
                                return
                            }
                            switch resolve{
                            case "serverlist":
                                self.presentationMode.wrappedValue.dismiss()
                                break
                            case "serversettings":
                                viewingSettings.wrappedValue = true
                                break
                            case "logout":
                                selectedServer.auth = false
                                print("logout event")
                                toolbarHidden = false
                                authError = true
                                dismiss()
                                break
                            default:
                                return
                            }
                        }
                        .onAppear(){
                            toolbarHidden = true
                            authController.setSafeAreaInsets(geometry.safeAreaInsets)
                            columnVisibility.wrappedValue = .automatic
                            if needsRefresh.wrappedValue {
                                authController.reset()
                                needsRefresh.wrappedValue = false
                            }
                            
                            authController.onStartedLoadingAction = {
                                toolbarHidden = true
                            }
                            
                            authController.onCancelledAction = {
                                dismiss()
                                toolbarHidden = false
                                authError = true
                            }
                            
                            authController.onSchemeRedirectAction = {
                                guard let resolve = authController.schemeURL else{
                                    return
                                }
                                switch resolve{
                                case "serverlist":
                                    self.presentationMode.wrappedValue.dismiss()
                                    break
                                case "serversettings":
                                    viewingSettings.wrappedValue = true
                                    break
                                case "logout":
                                    selectedServer.auth = false
                                    print("logout event")
                                    toolbarHidden = false
                                    authError = true
                                    dismiss()
                                    break
                                default:
                                    return
                                }
                            }
                        }
                        .onChange(of: geometry.safeAreaInsets){
                            authController.setSafeAreaInsets(geometry.safeAreaInsets)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .toolbar(toolbarHidden && UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .visible)
                .navigationTitle(Text(""))
                .navigationBarBackButtonHidden(true)
                .navigationBarItems(leading: backButton)
                .alert(isPresented: $authError){
                    Alert(title: Text("Error"), message: Text(authController.getAuthErrorMessage() ?? "Unknown Error"))
                }
            }
            else {
                Text("Loading...")
                    .onAppear(){
                        columnVisibility.wrappedValue = .automatic
                    }
            }
        }
    }
    
    private func setDefaultServer(){
        if items.count > 0{
            var server = items.first(where: {
                return $0.defaultSession == true
            })
            if server == nil {
                server = items.first(where: {
                    return $0.auth
                })
                if server != nil{
                    server?.defaultSession = true
                }
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
