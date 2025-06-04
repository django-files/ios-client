//
//  Django_FilesApp.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // Skip Firebase initialization if disabled via launch arguments
    let shouldDisableFirebase = ProcessInfo.processInfo.arguments.contains("--DisableFirebase")
    if !shouldDisableFirebase {
        FirebaseApp.configure()
        
        // Initialize Firebase Analytics based on user preference
        let analyticsEnabled = UserDefaults.standard.bool(forKey: "firebaseAnalyticsEnabled")
        Analytics.setAnalyticsCollectionEnabled(analyticsEnabled)
        
        // Initialize Crashlytics based on user preference
        let crashlyticsEnabled = UserDefaults.standard.bool(forKey: "crashlyticsEnabled")
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashlyticsEnabled)
    }

    return true
  }
}


@main
struct Django_FilesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
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
    @State private var selectedTab: TabViewWindow.Tab = .files
    @State private var showingServerConfirmation = false
    @State private var pendingAuthURL: URL? = nil
    @State private var pendingAuthSignature: String? = nil

    init() {
        // print("📱 Setting up WebSocketToastObserver")
        let _ = WebSocketToastObserver.shared
        
        // Handle reset arguments
        if CommandLine.arguments.contains("--DeleteAllData") {
            // Clear UserDefaults
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                do {
                    let context = sharedModelContainer.mainContext
                    // Delete all DjangoFilesSession objects
                    try context.delete(model: DjangoFilesSession.self)
                    try context.save()
                } catch {
                    print("Error clearing SwiftData store: \(error)")
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
                            return
                        }
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    ProgressView()
                        .onAppear {
                            checkForExistingSessions()
                        }
                } else if !hasExistingSessions {
                    SessionEditor(onBoarding: true, session: nil, onSessionCreated: { newSession in
                        sessionManager.selectedSession = newSession
                        hasExistingSessions = true
                    })
                } else if sessionManager.selectedSession == nil {
                    NavigationStack {
                        ServerSelector(selectedSession: $sessionManager.selectedSession)
                            .navigationTitle("Select Server")
                    }
                } else {
                    TabViewWindow(sessionManager: sessionManager, selectedTab: $selectedTab)
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .sheet(isPresented: $showingServerConfirmation) {
                ServerConfirmationView(
                    serverURL: $pendingAuthURL,
                    signature: $pendingAuthSignature,
                    onConfirm: { setAsDefault in
                        Task {
                            await handleServerConfirmation(confirmed: true, setAsDefault: setAsDefault)
                        }
                    },
                    onCancel: {
                        Task {
                            await handleServerConfirmation(confirmed: false, setAsDefault: false)
                        }
                    },
                    context: sharedModelContainer.mainContext
                )
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
        print("Deep link received: \(url)")
        guard url.scheme == "djangofiles" else { return }
        
        // Extract the signature from the URL parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("Invalid deep link URL")
            return
        }
        print("Deep link host: \(components.host ?? "unknown")")
        switch components.host {
        case "authorize":
            deepLinkAuth(components)
        case "serverlist":
            selectedTab = .settings
        case "filelist":
            handleFileListDeepLink(components)
        default:
            ToastManager.shared.showToast(message: "Unsupported deep link \(url)")
            print("Unsupported deep link type: \(components.host ?? "unknown")")
        }
    }
    
    private func handleFileListDeepLink(_ components: URLComponents) {
        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString) else {
            print("Invalid server URL in filelist deep link")
            return
        }
        
        // Find the session with matching URL and select it
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DjangoFilesSession>()
        
        Task {
            do {
                let existingSessions = try context.fetch(descriptor)
                if let matchingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    await MainActor.run {
                        sessionManager.selectedSession = matchingSession
                        selectedTab = .files
                    }
                } else {
                    print("No session found for URL: \(serverURL.absoluteString)")
                }
            } catch {
                print("Error fetching sessions: \(error)")
            }
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
                    // If session exists, just select it and update UI
                    await MainActor.run {
                        sessionManager.selectedSession = existingSession
                        hasExistingSessions = true
                        ToastManager.shared.showToast(message: "Connected to existing server \(existingSession.url)")
                    }
                    return
                }
                
                // No existing session, show confirmation dialog
                await MainActor.run {
                    pendingAuthURL = serverURL
                    pendingAuthSignature = signature
                    showingServerConfirmation = true
                }
            } catch {
                print("Error checking for existing sessions: \(error)")
            }
        }
    }
    
    private func handleServerConfirmation(confirmed: Bool, setAsDefault: Bool) async {
        guard let serverURL = pendingAuthURL,
              let signature = pendingAuthSignature else {
            return
        }

        // If user cancelled, just clear the pending data and return
        if !confirmed {
            pendingAuthURL = nil
            pendingAuthSignature = nil
            return
        }

        await MainActor.run {
            // Create and authenticate the new session
            let context = sharedModelContainer.mainContext
            
            do {
                let descriptor = FetchDescriptor<DjangoFilesSession>()
                let existingSessions = try context.fetch(descriptor)
                
                // Create and authenticate the new session
                Task {
                    if let newSession = await sessionManager.createAndAuthenticateSession(
                        url: serverURL,
                        signature: signature,
                        context: context
                    ) {
                        if setAsDefault {
                            // Reset all other sessions to not be default
                            for session in existingSessions {
                                session.defaultSession = false
                            }
                            newSession.defaultSession = true
                        }
                        sessionManager.selectedSession = newSession
                        hasExistingSessions = true
                        selectedTab = .files
                        ToastManager.shared.showToast(message: "Successfully logged into \(newSession.url)")
                    }
                }
            } catch {
                ToastManager.shared.showToast(message: "Problem signing into server \(error)")
                print("Error creating new session: \(error)")
            }
            
            // Clear pending auth data
            pendingAuthURL = nil
            pendingAuthSignature = nil
        }
    }
    
    private func checkDefaultServer() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DjangoFilesSession>()
        
        Task {
            do {
                let sessions = try context.fetch(descriptor)
                await MainActor.run {
                    if sessionManager.selectedSession == nil {
                        if let defaultSession = sessions.first(where: { $0.defaultSession }) {
                            sessionManager.selectedSession = defaultSession
                            selectedTab = .files
                        } else {
                            selectedTab = .settings
                        }
                    }
                }
            } catch {
                print("Error checking for default server: \(error)")
            }
        }
    }
    
    private func checkForExistingSessions() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DjangoFilesSession>()
        
        do {
            let sessionsCount = try context.fetchCount(descriptor)
            hasExistingSessions = sessionsCount > 0
            if hasExistingSessions {
                checkDefaultServer()
            }
            isLoading = false  // Set loading to false after check completes
        } catch {
            print("Error checking for existing sessions: \(error)")
            isLoading = false  // Ensure we exit loading state even on error
        }
    }
}
