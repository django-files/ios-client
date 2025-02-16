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
    @Query private var items: [DjangoFilesSession]
    @State private var showingEditor = false
    @State private var runningSession = false

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        SessionSelector(session: item)
                    }label: {
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
            Text("Select an item")
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
