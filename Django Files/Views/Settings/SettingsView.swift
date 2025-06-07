import SwiftUI

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showLoginSheet: Bool
    @State private var needsRefresh = true
    
    var body: some View {
        NavigationStack {
            List {
                if let server = sessionManager.selectedSession, !server.auth {
                    Text("Please sign into the selected server from the server list to use the application.")
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
