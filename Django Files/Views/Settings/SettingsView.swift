import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showLoginSheet: Bool
    @State private var needsRefresh = true
    @State private var serverVersion: String? = nil

    private func hostWithVersion(_ server: DjangoFilesSession) -> String {
        let host = URL(string: server.url)?.host ?? server.url
        if let version = serverVersion {
            return "\(host) (\(version))"
        }
        return host
    }

    var body: some View {
        NavigationStack {
            List {
                if let server = sessionManager.selectedSession {
                    if server.auth {
                        Section {
                            NavigationLink {
                                AuthViewContainer(
                                    selectedServer: server,
                                    customURL: server.url + "/settings/user/",
                                    needsRefresh: $needsRefresh
                                )
                            } label: {
                                HStack {
                                    if let avatarUrl = server.avatarUrl {
                                        CachedAsyncImage(url: avatarUrl) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 50, height: 50)
                                                .clipShape(Circle())
                                        } placeholder: {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 50, height: 50)
                                                .foregroundColor(.gray)
                                        }
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                            .foregroundColor(.gray)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        if let username = server.username {
                                            Text(username)
                                                .font(.headline)
                                        }
                                        if let firstName = server.firstName, !firstName.isEmpty {
                                            Text(firstName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(hostWithVersion(server))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .onAppear {
                            Task {
                                if let url = URL(string: server.url) {
                                    serverVersion = await DFAPI(url: url, token: server.token).getVersion()
                                }
                            }
                        }
                    } else {
                        Text("Please sign into the selected server from the server list to use the application.")
                    }
                }

                Section {
                    NavigationLink {
                        ServerSelector(selectedSession: $sessionManager.selectedSession)
                            .navigationTitle("Servers")
                    } label: {
                        Label("Server List", systemImage: "server.rack")
                    }
                } header: {
                    Text("Select Active Server")
                }

                if let server = sessionManager.selectedSession, server.auth {
                    Section {
                        NavigationLink {
                            AuthViewContainer(
                                selectedServer: server,
                                customURL: server.url + "/settings/site/",
                                needsRefresh: $needsRefresh
                            )
                        } label: {
                            Label("Server Settings", systemImage: "person.2.badge.gearshape")
                        }
                    } header: {
                        Text("Selected Server Settings")
                    }
                }

                Section {
                    NavigationLink {
                        AppSettings()
                    } label: {
                        Label("App Settings", systemImage: "gear")
                    }
                } header: {
                    Text("Application")
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
