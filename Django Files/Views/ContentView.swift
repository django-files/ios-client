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
                .onDelete(perform: deleteItems)
            }
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
            AuthViewContainer(viewingSettings: $viewingSettings, selectedServer: $selectedServer, columnVisibility: $columnVisibility)
        }
        .sheet(isPresented: $showingEditor){
            SessionEditor(session: nil)
        }
        .onAppear() {
            selectedServer = items.first(where: {
                $0.defaultSession == true
            }) ?? DjangoFilesSession()
            if items.count == 0{
                self.showingEditor.toggle()
            }
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
    
    var viewingSettings: Binding<Bool>
    var selectedServer: Binding<DjangoFilesSession?>
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    @State private var toolbarHidden: Bool = false
    @State private var loadingAngle: Angle = Angle(degrees: 360)
    
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
                let temp = selectedServer.wrappedValue
                SessionSelector(session: selectedServer.wrappedValue!)
                    .onAppear(){
                        columnVisibility.wrappedValue = .automatic
                    }
                    .onDisappear(){
                        viewingSettings.wrappedValue = false
                        self.selectedServer.wrappedValue = temp
                    }
            }
            else if selectedServer.wrappedValue!.url != "" {
                ZStack{
                    LoadingView().frame(width: 100, height: 100)
                    AuthView(authController: authController, httpsUrl: selectedServer.wrappedValue!.url, doReset: authController.url?.absoluteString ?? "" != selectedServer.wrappedValue!.url)
                        .onAuth {
                            guard let temp = authController.getToken() else {
                                return
                            }
                            selectedServer.wrappedValue!.token = temp
                            do{
                                try modelContext.save()
                            }
                            catch{}
                        }
                        .onCancelled {
                            dismiss()
                        }
                        .onScrolledToTop{
                            withAnimation(.smooth(duration: 0.2)) {
                                toolbarHidden = false
                            }
                        }
                        .onScrolled{
                            withAnimation(.smooth(duration: 0.2)) {
                                toolbarHidden = true
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
                        .navigationBarBackButtonHidden(true)
                        .navigationBarItems(leading: backButton)                }
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
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoading)
            .opacity(firstAppear ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: firstAppear)
            .onAppear(){
                if isLoading == false{
                    isLoading.toggle()
                }
                firstAppear = true
            }
            .onDisappear(){
                firstAppear = false
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DjangoFilesSession.self, inMemory: true)
}
