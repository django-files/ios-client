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
            if let selectedServer{
                if viewingSettings{
                    let temp = selectedServer
                    SessionSelector(session: selectedServer)
                        .onAppear(){
                            columnVisibility = .automatic
                        }
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
                        .onAppear(){
                            columnVisibility = .automatic
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
                        .onAppear(){
                            columnVisibility = .automatic
                        }
                }
            }
            else{
                Text("Select an item")
                    .onAppear(){
                        columnVisibility = .automatic
                    }
            }
        }
        .sheet(isPresented: $showingEditor){
            SessionEditor(session: nil)
        }
        .onAppear() {
            selectedServer = items.first(where: {
                $0.defaultSession == true
            })
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

#Preview {
    ContentView()
        .modelContainer(for: DjangoFilesSession.self, inMemory: true)
}
