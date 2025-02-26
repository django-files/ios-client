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
    @State private var authController: AuthController = AuthController()
    
    @State private var selectedServer: DjangoFilesSession? = DjangoFilesSession()
    
    @State private var token: String?
    
    @State private var viewingSettings: Bool = false
    
    var body: some View {
        NavigationSplitView {
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
                    }.sheet(isPresented: $showingEditor){
                        SessionEditor(session: nil)
                    }
                }
            }
        } detail: {
            if items.count == 0{
                SessionEditor(session: nil)
                    .onDisappear(){
                        if items.count > 0{
                            selectedServer = items[0]
                        }
                    }
            }
            else if let selectedServer{
                if viewingSettings{
                    let temp = selectedServer
                    SessionSelector(session: selectedServer)
                        .onDisappear(){
                            viewingSettings = false
                            self.selectedServer = temp
                        }
                }
                else if selectedServer.url != "" {
                    AuthView(authController: authController, httpsUrl: selectedServer.url)
                        .onLoaded {
                            guard let temp = authController.getToken() else {
                                return
                            }
                            selectedServer.token = temp
                            do{
                                try modelContext.save()
                            }
                            catch{}
                        }
                        .onCancelled {
                            dismiss()
                        }
                        .toolbar{
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Settings"){
                                    viewingSettings = true
                                }
                            }
                        }
                }
                else{
                    Text("Loading...")
                }
            }
            else{
                Text("Select an item")
            }
        }
        .onAppear() {
            selectedServer = items.first(where: {
                $0.defaultSession == true
            })
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
