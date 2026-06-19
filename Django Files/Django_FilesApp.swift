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

class PreviewStateManager: ObservableObject {
    @Published var deepLinkFile: DFFile?
    @Published var showingDeepLinkPreview = false
    @Published var deepLinkTargetFileID: Int? = nil
    @Published var deepLinkFilePassword: String? = nil
}

class StreamStateManager: ObservableObject {
    @Published var showingDeepLinkStream = false
    @Published var deepLinkServerURL: URL? = nil
    @Published var deepLinkStreamName: String? = nil
    @Published var deepLinkToken: String = ""
    @Published var deepLinkPassword: String? = nil
}

class AlbumStateManager: ObservableObject {
    @Published var showingDeepLinkAlbum = false
    @Published var deepLinkSession: DjangoFilesSession? = nil
    @Published var deepLinkAlbumID: Int? = nil
    @Published var deepLinkAlbumName: String? = nil
    // Set when an authenticated user follows an album deep link — triggers in-app navigation
    @Published var deepLinkNavigationAlbumID: Int? = nil
    @Published var deepLinkNavigationAlbumName: String? = nil
}

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set to a non-nil mask to temporarily lock orientation (e.g. portrait-only for broadcast).
    static var orientationLock: UIInterfaceOrientationMask? = nil

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock ?? .all
    }

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    let shouldDisableFirebase = ProcessInfo.processInfo.arguments.contains("--DisableFirebase")
    if !shouldDisableFirebase {
        FirebaseApp.configure()

        // Initialize Firebase Analytics based on user preference.
        // `DFAnalytics.setCollectionEnabled` forces off on simulator
        // regardless of UserDefaults, keeping dev/QA traffic out of prod.
        let analyticsEnabled = UserDefaults.standard.bool(forKey: "firebaseAnalyticsEnabled")
        DFAnalytics.setCollectionEnabled(analyticsEnabled)

        // Initialize Crashlytics based on user preference
        let crashlyticsEnabled = UserDefaults.standard.bool(forKey: "crashlyticsEnabled")
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashlyticsEnabled)
    }

    if ProcessInfo.processInfo.arguments.contains("--MockNetwork") {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        DFAPIConfiguration.sessionOverride = URLSession(configuration: config)
    }

    return true
  }
}


@main
struct Django_FilesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var previewStateManager = PreviewStateManager()
    @StateObject private var streamStateManager = StreamStateManager()
    @StateObject private var albumStateManager = AlbumStateManager()
    @StateObject private var uploadProgressManager = UploadProgressManager()
    @StateObject private var biometricLockManager = BiometricLockManager()
    @State private var showFileInfo = false
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

        if CommandLine.arguments.contains("--InjectTestSession") {
            let context = sharedModelContainer.mainContext
            let testSession = DjangoFilesSession(url: "http://localhost", token: "test-token")
            testSession.auth = true
            testSession.defaultSession = true
            testSession.username = "testuser"
            testSession.firstName = "Test"
            testSession.userID = 1
            context.insert(testSession)
            try? context.save()
        }

        if CommandLine.arguments.contains("--FileListGridView") {
            UserDefaults.standard.set(true, forKey: "fileListIsGridView")
        }

        if let columnsArg = CommandLine.arguments.first(where: { $0.hasPrefix("--FileListGridColumns=") }),
           let count = Int(columnsArg.dropFirst("--FileListGridColumns=".count)),
           (1...3).contains(count) {
            UserDefaults.standard.set(true, forKey: "fileListIsGridView")
            UserDefaults.standard.set(count, forKey: "fileListGridColumns")
        }

        if CommandLine.arguments.contains("--FileListMapView") {
            UserDefaults.standard.set(true, forKey: "fileListShowingMap")
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
            .environmentObject(previewStateManager)
            .environmentObject(streamStateManager)
            .environmentObject(albumStateManager)
            .environmentObject(uploadProgressManager)
            .environmentObject(sessionManager)
            .environmentObject(biometricLockManager)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    DFAnalytics.logAppOpen()
                    biometricLockManager.checkAndLockIfNeeded()
                    if biometricLockManager.isLocked {
                        Task { await biometricLockManager.authenticate() }
                    }
                } else if newPhase == .background {
                    biometricLockManager.recordBackgrounded()
                }
            }
            .overlay {
                if biometricLockManager.isLocked {
                    BiometricLockView()
                        .environmentObject(biometricLockManager)
                }
            }
            .onOpenURL { url in
                DeepLinks.shared.handleDeepLink(
                    url,
                    context: sharedModelContainer.mainContext,
                    sessionManager: sessionManager,
                    previewStateManager: previewStateManager,
                    streamStateManager: streamStateManager,
                    albumStateManager: albumStateManager,
                    selectedTab: $selectedTab,
                    hasExistingSessions: $hasExistingSessions,
                    showingServerConfirmation: $showingServerConfirmation,
                    pendingAuthURL: $pendingAuthURL,
                    pendingAuthSignature: $pendingAuthSignature
                )
            }
            .sheet(isPresented: $showingServerConfirmation) {
                ServerConfirmationView(
                    serverURL: $pendingAuthURL,
                    signature: $pendingAuthSignature,
                    onConfirm: { setAsDefault in
                        Task {
                            await DeepLinks.shared.handleServerConfirmation(
                                confirmed: true,
                                setAsDefault: setAsDefault,
                                pendingAuthURL: $pendingAuthURL,
                                pendingAuthSignature: $pendingAuthSignature,
                                context: sharedModelContainer.mainContext,
                                sessionManager: sessionManager,
                                hasExistingSessions: $hasExistingSessions,
                                selectedTab: $selectedTab
                            )
                        }
                    },
                    onCancel: {
                        Task {
                            await DeepLinks.shared.handleServerConfirmation(
                                confirmed: false,
                                setAsDefault: false,
                                pendingAuthURL: $pendingAuthURL,
                                pendingAuthSignature: $pendingAuthSignature,
                                context: sharedModelContainer.mainContext,
                                sessionManager: sessionManager,
                                hasExistingSessions: $hasExistingSessions,
                                selectedTab: $selectedTab
                            )
                        }
                    },
                    context: sharedModelContainer.mainContext
                )
            }
            .fullScreenCover(isPresented: $previewStateManager.showingDeepLinkPreview) {
                if let file = previewStateManager.deepLinkFile {
                    FilePreviewView(
                        file: .constant(file),
                        server: .constant(nil),
                        showingPreview: $previewStateManager.showingDeepLinkPreview,
                        showFileInfo: $showFileInfo,
                        fileListDelegate: nil,
                        allFiles: .constant([file]),
                        currentIndex: 0,
                        onNavigate: { _ in }
                    )
                    .onDisappear {
                        previewStateManager.deepLinkFile = nil
                    }
                }
            }
            .fullScreenCover(isPresented: $streamStateManager.showingDeepLinkStream) {
                if let serverURL = streamStateManager.deepLinkServerURL,
                   let streamName = streamStateManager.deepLinkStreamName {
                    NavigationStack {
                        StreamView(
                            serverURL: serverURL,
                            streamName: streamName,
                            token: streamStateManager.deepLinkToken,
                            password: streamStateManager.deepLinkPassword
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    streamStateManager.showingDeepLinkStream = false
                                }
                            }
                        }
                    }
                    .onDisappear {
                        streamStateManager.deepLinkServerURL = nil
                        streamStateManager.deepLinkStreamName = nil
                    }
                }
            }
            .fullScreenCover(isPresented: $albumStateManager.showingDeepLinkAlbum) {
                if let albumID = albumStateManager.deepLinkAlbumID {
                    NavigationStack {
                        FileListView(
                            server: Binding(
                                get: { albumStateManager.deepLinkSession },
                                set: { _ in }
                            ),
                            albumID: albumID,
                            navigationPath: .constant(NavigationPath()),
                            albumName: albumStateManager.deepLinkAlbumName
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    albumStateManager.showingDeepLinkAlbum = false
                                }
                            }
                        }
                    }
                    .environmentObject(previewStateManager)
                    .onDisappear {
                        albumStateManager.deepLinkSession = nil
                        albumStateManager.deepLinkAlbumID = nil
                        albumStateManager.deepLinkAlbumName = nil
                    }
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
            isLoading = false
        } catch {
            print("Error checking for existing sessions: \(error)")
            isLoading = false
        }
    }
}
