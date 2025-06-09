import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showLoginSheet: Bool
    @State private var needsRefresh = true
    
    var body: some View {
        NavigationStack {
            List {
                if let server = sessionManager.selectedSession {
                    if server.auth {
                        Section {
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
                                
                                VStack(alignment: .leading) {
                                    if let firstName = server.firstName, let username = server.username {
                                        Text(firstName)
                                            .font(.headline)
                                        Text(username)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    } else if let username = server.username {
                                        Text(username)
                                            .font(.headline)
                                    }
                                    HStack{
                                        Text(server.url)
                                            .font(.subheadline)
                                    }
                                }

                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            print("Avatar URL: \(String(describing: server.avatarUrl))")

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
                                customURL: server.url + "/settings/user/",
                                needsRefresh: $needsRefresh
                            )
                        } label: {
                            Label("User Settings", systemImage: "person")
                        }
                        
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
