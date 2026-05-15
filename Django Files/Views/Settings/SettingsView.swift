import SwiftUI
import SwiftData
import FirebaseAnalytics
import FirebaseCrashlytics

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showLoginSheet: Bool
    @State private var needsRefresh = true
    @State private var serverVersion: String? = nil
    @Query private var allSessions: [DjangoFilesSession]

    @AppStorage("firebaseAnalyticsEnabled") private var firebaseAnalyticsEnabled = true
    @AppStorage("crashlyticsEnabled") private var crashlyticsEnabled = true
    @State private var showAnalyticsAlert = false
    @State private var showCrashlyticsAlert = false
    @State private var pendingAnalyticsValue = true
    @State private var pendingCrashlyticsValue = true

    private var versionInfo: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        if version == "0.0" { return "dev (source)" }
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                if let server = sessionManager.selectedSession {
                    if server.auth {
                        Section {
                            // Profile row → user settings
                            NavigationLink {
                                AuthViewContainer(
                                    selectedServer: server,
                                    customURL: server.url + "/settings/user/",
                                    needsRefresh: $needsRefresh
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    if let avatarUrl = server.avatarUrl {
                                        CachedAsyncImage(url: avatarUrl) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 44, height: 44)
                                                .clipShape(Circle())
                                        } placeholder: {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 44, height: 44)
                                                .foregroundColor(.gray)
                                        }
                                        .id(avatarUrl)
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .frame(width: 44, height: 44)
                                            .foregroundColor(.gray)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let username = server.username {
                                            Text(username).font(.headline)
                                        }
                                        if let firstName = server.firstName, !firstName.isEmpty {
                                            Text(firstName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            // Server row → server settings
                            NavigationLink {
                                AuthViewContainer(
                                    selectedServer: server,
                                    customURL: server.url + "/settings/site/",
                                    needsRefresh: $needsRefresh
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(systemName: "server.rack")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 7))
                                            .foregroundStyle(.secondary)
                                            .offset(x: 3, y: 3)
                                    }
                                    .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(URL(string: server.url)?.host ?? server.url)
                                            .font(.subheadline)
                                        if let version = serverVersion {
                                            Text(version)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            // Server list row
                            NavigationLink {
                                ServerSelector(selectedSession: $sessionManager.selectedSession)
                                    .navigationTitle("Servers")
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "server.rack")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44)
                                    Text("Select Active Server")
                                        .font(.subheadline)
                                }
                            }
                            .contextMenu {
                                ForEach(allSessions, id: \.url) { session in
                                    Button {
                                        sessionManager.selectedSession = session
                                        sessionManager.saveSelectedSession()
                                    } label: {
                                        Label(
                                            URL(string: session.url)?.host ?? session.url,
                                            systemImage: session.url == server.url ? "checkmark" : "server.rack"
                                        )
                                    }
                                }
                                Section {
                                    Button {
                                        for s in allSessions { s.defaultSession = false }
                                        server.defaultSession = true
                                    } label: {
                                        Label("Set \(URL(string: server.url)?.host ?? server.url) as Default", systemImage: "star.fill")
                                    }
                                    .disabled(server.defaultSession)
                                }
                            }
                        }
                    } else {
                        Section {
                            NavigationLink {
                                ServerSelector(selectedSession: $sessionManager.selectedSession)
                                    .navigationTitle("Servers")
                            } label: {
                                Label("Server List", systemImage: "server.rack")
                            }
                            Text("Please sign into the selected server from the server list to use the application.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }

                Section(header: Text("Privacy")) {
                    Toggle(isOn: Binding(
                        get: { firebaseAnalyticsEnabled },
                        set: { newValue in
                            if !newValue {
                                pendingAnalyticsValue = newValue
                                showAnalyticsAlert = true
                            } else {
                                firebaseAnalyticsEnabled = newValue
                                Analytics.setAnalyticsCollectionEnabled(newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text("Analytics")
                            Text("Help improve the app by sending anonymous usage data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .alert("Disable Analytics?", isPresented: $showAnalyticsAlert) {
                        Button("Keep Enabled", role: .cancel) { firebaseAnalyticsEnabled = true }
                        Button("Disable", role: .destructive) {
                            firebaseAnalyticsEnabled = pendingAnalyticsValue
                            Analytics.setAnalyticsCollectionEnabled(pendingAnalyticsValue)
                        }
                    } message: {
                        Text("Please consider leaving analytics enabled to help improve Django Files. We do not collect ANY personal information with analytics.")
                    }

                    Toggle(isOn: Binding(
                        get: { crashlyticsEnabled },
                        set: { newValue in
                            if !newValue {
                                pendingCrashlyticsValue = newValue
                                showCrashlyticsAlert = true
                            } else {
                                crashlyticsEnabled = newValue
                                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text("Crash Reporting")
                            Text("Send crash reports to help identify and fix issues")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .alert("Disable Crash Reporting?", isPresented: $showCrashlyticsAlert) {
                        Button("Keep Enabled", role: .cancel) { crashlyticsEnabled = true }
                        Button("Disable", role: .destructive) {
                            crashlyticsEnabled = pendingCrashlyticsValue
                            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(pendingCrashlyticsValue)
                        }
                    } message: {
                        Text("Please consider leaving crash analytics enabled. We collect no personal information, only information pertaining to application errors.")
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionInfo)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .task(id: sessionManager.selectedSession?.url) {
                serverVersion = nil
                guard let server = sessionManager.selectedSession,
                      let url = URL(string: server.url) else { return }
                serverVersion = await DFAPI(url: url, token: server.token).getVersion()
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showLoginSheet) {
                if let session = sessionManager.selectedSession {
                    LoginView(selectedServer: session, onLoginSuccess: {
                        showLoginSheet = false
                    })
                }
            }
        }
    }
}

#Preview {
    SettingsView(
        sessionManager: SessionManager(),
        showLoginSheet: .constant(false)
    )
}
