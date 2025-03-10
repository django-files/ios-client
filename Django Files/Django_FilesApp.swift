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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.djangofiles.app"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Handle reset arguments
        if CommandLine.arguments.contains("--DeleteAllData") {
            // Clear UserDefaults
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            // Clear SwiftData store
            do {
                let context = sharedModelContainer.mainContext
                // Delete all DjangoFilesSession objects
                try context.delete(model: DjangoFilesSession.self)
                try context.save()
            } catch {
                print("Error clearing SwiftData store: \(error)")
            }
            // Clear any files in the app's documents directory
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                do {
                    let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, 
                                                                             includingPropertiesForKeys: nil)
                    for fileURL in fileURLs {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                } catch {
                    print("Error clearing documents directory: \(error)")
                }
            }
        }
    }

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
