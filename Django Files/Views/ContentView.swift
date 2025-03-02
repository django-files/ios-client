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
    @State private var runningSession = false
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly
    @State private var selectedServer: DjangoFilesSession? = DjangoFilesSession()
    
    @State private var token: String?
    
    @State private var viewingSettings: Bool = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedServer) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        Text(item.url)
                    }
                }
                .onDelete(perform: deleteItems)            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
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
            AuthViewContainer(viewingSettings: $viewingSettings, selectedServer: $selectedServer, columnVisibility: $columnVisibility, showingEditor: $showingEditor)
        }
        .sheet(isPresented: $showingEditor){
            SessionEditor(session: nil)
        }
        .onAppear() {
            setDefaultServer()
            if items.count > 0{
                selectedServer = items.first(where: {
                    $0.defaultSession == true
                })
                if selectedServer == nil{
                    selectedServer = items.first
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }

    private func setDefaultServer(){
        if items.count > 0{
            var server = items.first(where: {
                $0.defaultSession == true
            })
            if server == nil {
                server = items.first(where: {
                    $0.auth
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
    
    var viewingSettings: Binding<Bool>
    var selectedServer: Binding<DjangoFilesSession?>
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    var showingEditor: Binding<Bool>
    @State private var toolbarHidden: Bool = false
    
    @State private var authController: AuthController = AuthController()

    var backButton : some View { Button(action: {
        self.presentationMode.wrappedValue.dismiss()
        }) {
            HStack {
                if !UIDevice.current.localizedModel.contains("iPad") {
                    Image("backImage")
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                    Text("Server List")
                }
            }
        }
    }
    public var body: some View {
        if selectedServer.wrappedValue != nil{
            if viewingSettings.wrappedValue{
                SessionSelector(session: selectedServer.wrappedValue!, viewingSelect: viewingSettings)
                    .onAppear(){
                        columnVisibility.wrappedValue = .automatic
                    }
            }
            else if selectedServer.wrappedValue!.url != "" {
                ZStack{
                    Color.djangoFilesBackground.ignoresSafeArea()
                    LoadingView().frame(width: 100, height: 100)
                    AuthView(authController: authController, httpsUrl: selectedServer.wrappedValue!.url, doReset: authController.url?.absoluteString ?? "" != selectedServer.wrappedValue!.url || !selectedServer.wrappedValue!.auth)
                        .onAuth {
                            toolbarHidden = true
                            guard let temp = authController.getToken() else {
                                return
                            }
                            selectedServer.wrappedValue!.token = temp
                            do{
                                try modelContext.save()
                            }
                            catch{}
                        }
                        .onStartedLoading {
                            toolbarHidden = false
                        }
                        .onCancelled {
                            dismiss()
                            toolbarHidden = false
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
                            default:
                                return
                            }
                        }
                        .onAppear(){
                            columnVisibility.wrappedValue = .automatic
                        }
                        .toolbar(toolbarHidden ? .hidden : .visible)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Server Info"){
                                    viewingSettings.wrappedValue = true
                                }
                            }
                        }
                        .navigationTitle(Text(""))
                        .navigationBarBackButtonHidden(true)
                        .navigationBarItems(leading: backButton)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            }
            else{
                Text("Loading...")
                    .onAppear(){
                        columnVisibility.wrappedValue = .automatic
                    }
            }
        }
        else{
            Text("Select an item")
                .onAppear(){
                    columnVisibility.wrappedValue = .automatic
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
