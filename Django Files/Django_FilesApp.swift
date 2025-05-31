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

    @StateObject private var sessionManager = SessionManager()
    @State private var hasExistingSessions = false
    @State private var isLoading = true

    init() {
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
                    SessionEditor(onBoarding: true, session: nil, onSessionCreated: { newSession in
                        sessionManager.selectedSession = newSession
                        hasExistingSessions = true
                    })
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .commands {
            SidebarCommands()
        }
#endif
    }
    
    private func handleDeepLink(_ url: URL) {
        // print("Deep link received: \(url)")
        guard url.scheme == "djangofiles" else { return }
        
        // Extract the signature from the URL parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("Invalid deep link URL")
            return
        }
        switch components.host {
        case "authorize":
            deepLinkAuth(components)
        default:
            print("Unsupported deep link type: \(components.host ?? "unknown")")
        }
    }
    
    private func deepLinkAuth(_ components: URLComponents) {
        guard let signature = components.queryItems?.first(where: { $0.name == "signature" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding ?? "") else {
            print("Unable to parse auth deep link.")
            return
        }

        // Check if a session with this URL already exists
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DjangoFilesSession>()
        
        Task {
            do {
                let existingSessions = try context.fetch(descriptor)
                if let existingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    // If session exists, update it on the main thread
                    await MainActor.run {
                        sessionManager.selectedSession = existingSession
                        hasExistingSessions = true
                    }
                    return
                }
                
                // If no existing session, create and authenticate a new one
                if let newSession = await sessionManager.createAndAuthenticateSession(
                    url: serverURL,
                    signature: signature,
                    context: context
                ) {
                    // Update the UI on the main thread
                    await MainActor.run {
                        sessionManager.selectedSession = newSession
                        hasExistingSessions = true
                        ToastManager.shared.showToast(message: "Successfully logged into \(newSession.url)")
                    }
                }
            } catch {
                print("Error checking for existing sessions: \(error)")
            }
        }
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
