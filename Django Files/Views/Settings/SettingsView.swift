import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showLoginSheet: Bool
    @State private var needsRefresh = true
    @Query private var allSessions: [DjangoFilesSession]

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
                        Section(header: Text("Server")) {
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

                            // Server row → server settings (superusers only)
                            if server.superUser {
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
                                            Text(sessionManager.cachedVersion ?? "placeholder")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .opacity(sessionManager.cachedVersion == nil ? 0 : 1)
                                        }
                                    }
                                }
                            } else {
                                HStack(spacing: 12) {
                                    Image(systemName: "server.rack")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(URL(string: server.url)?.host ?? server.url)
                                            .font(.subheadline)
                                        Text(sessionManager.cachedVersion ?? "placeholder")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .opacity(sessionManager.cachedVersion == nil ? 0 : 1)
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
                        Section(header: Text("Server")) {
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

                Section(header: Text("App")) {
                    NavigationLink {
                        TabCustomizationView()
                    } label: {
                        Label("Customize Tabs", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
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
