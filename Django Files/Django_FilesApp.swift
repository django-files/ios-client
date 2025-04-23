//
//  Django_FilesApp.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import SwiftUI
import SwiftData

class SessionManager: ObservableObject {
    @Published var selectedSession: DjangoFilesSession?
    private let userDefaultsKey = "lastSelectedSessionURL"
    
    func saveSelectedSession() {
        if let session = selectedSession {
            UserDefaults.standard.set(session.url, forKey: userDefaultsKey)
        }
    }
    
    func loadLastSelectedSession(from sessions: [DjangoFilesSession]) {
        // Return if we already have a session loaded
        if selectedSession != nil { return }
        
        if let lastSessionURL = UserDefaults.standard.string(forKey: userDefaultsKey) {
            selectedSession = sessions.first(where: { $0.url == lastSessionURL })
        } else if let defaultSession = sessions.first(where: { $0.defaultSession }) {
            // Fall back to any session marked as default
            selectedSession = defaultSession
        } else if let firstSession = sessions.first {
            // Fall back to the first available session
            selectedSession = firstSession
        }
    }
}

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

    @StateObject private var sessionManager = SessionManager()

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
//            ContentView()
            TabViewWindow(sessionManager: sessionManager)
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            SidebarCommands()
        }
#endif
    }
}
