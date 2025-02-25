//
//  Django_FilesApp.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import SwiftUI
import SwiftData

@main
struct Django_FilesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DjangoFilesSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.blastsoftstudios.djangofiles"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            SidebarCommands()
        }
#endif
    }
}
