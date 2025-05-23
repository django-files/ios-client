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
    @State private var hasExistingSessions = false
    @State private var isLoading = true

    init() {
        // Initialize WebSocket debugging
        // print("📱 App initializing - WebSocket toast system will use direct approach")
        
        // Initialize WebSocket toast observer - make sure this runs at startup
        // print("📱 Setting up WebSocketToastObserver")
        let _ = WebSocketToastObserver.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    ProgressView()
                        .onAppear {
                            checkForExistingSessions()
                        }
                } else if hasExistingSessions {
                    TabViewWindow(sessionManager: sessionManager)
                } else {
                    SessionEditor(session: nil, onSessionCreated: { newSession in
                        sessionManager.selectedSession = newSession
                        hasExistingSessions = true
                    })
                }
            }
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            SidebarCommands()
        }
#endif
    }
    
    private func checkForExistingSessions() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DjangoFilesSession>()
        
        do {
            let sessionsCount = try context.fetchCount(descriptor)
            hasExistingSessions = sessionsCount > 0
            isLoading = false  // Set loading to false after check completes
        } catch {
            print("Error checking for existing sessions: \(error)")
            isLoading = false  // Ensure we exit loading state even on error
        }
    }
}
