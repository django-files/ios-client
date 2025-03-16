import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    let selectedServer: DjangoFilesSession  // Regular property, not @Bindable
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var authMethods: [DFAuthMethod] = []
    @State private var siteName: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    @State private var oauthSheetURL: OAuthURL? = nil
    @State private var isLoggingIn: Bool = false
    

    let dfapi: DFAPI
    var onLoginSuccess: () -> Void
    
    init(dfapi: DFAPI, selectedServer: DjangoFilesSession, onLoginSuccess: @escaping () -> Void) {
        self.dfapi = dfapi
        self.selectedServer = selectedServer
        self.onLoginSuccess = onLoginSuccess
    }
    
    private func fetchAuthMethods() async {
        isLoading = true
        if let response = await dfapi.getAuthMethods() {
            authMethods = response.authMethods
            siteName = response.siteName
        } else {
            error = "Failed to fetch authentication methods, is this a Django Files server?"
        }
        isLoading = false
    }
    
    private func handleLocalLogin() async {
        guard authMethods.contains(where: { $0.name == "local" }) else { return }
        
        isLoggingIn = true
        if await dfapi.localLogin(username: username, password: password, selectedServer: selectedServer) {
            await MainActor.run {
                selectedServer.auth = true
                try? modelContext.save()
            }
            onLoginSuccess()
        } else {
            error = "Login request failed"
        }
        isLoggingIn = false
    }
    
    private func handleOAuthLogin(url: String) {
        print("handleOAuthLogin received URL string: '\(url)'")
        if URL(string: url) != nil {
            print("Valid OAuth URL, showing web view")
            oauthSheetURL = OAuthURL(url: url)
        } else {
            print("Failed to create OAuth URL from: '\(url)'")
            error = "Invalid OAuth URL"
        }
    }
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading authentication methods...")
            } else if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                Button("Retry") {
                    Task {
                        await fetchAuthMethods()
                    }
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack() {
                            // Local login form
                            Text(siteName).font(.title)
                            Text("Login to Django Files at \(dfapi.url)")
                            if authMethods.contains(where: { $0.name == "local" }) {
                                VStack(spacing: 15) {
                                    TextField("Username", text: $username)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .autocapitalization(.none)
                                        .disabled(isLoggingIn)
                                    
                                    SecureField("Password", text: $password)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .disabled(isLoggingIn)
                                    
                                    Button() {
                                        Task {
                                            await handleLocalLogin()
                                        }
                                    } label: {
                                        HStack {
                                            Text(isLoggingIn ? "Logging in..." : "Login")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.accentColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                                }
                                .padding()
                                Divider()
                            }

                            // OAuth methods
                            ForEach(authMethods.filter { $0.name != "local" }, id: \.name) { method in
                                Button {
                                    handleOAuthLogin(url: method.url)
                                } label: {
                                    HStack {
                                        Text("Continue with \(method.name.capitalized)")
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .padding()
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height
                        )
                    }
                }
            }
        }
        .onAppear {
            Task {
                await fetchAuthMethods()
            }
        }
        .sheet(item: $oauthSheetURL) { oauthURL in
            OAuthWebView(url: oauthURL.url, onComplete: { token, sessionKey in
                Task {
                    if let token = token, let sessionKey = sessionKey {
                        let status = await dfapi.oauthTokenLogin(token: token, sessionKey: sessionKey, selectedServer: selectedServer)
                        print("\(sessionKey) : \(token)")
                        print(selectedServer.cookies)
                        if status {
                            selectedServer.auth = true
                            print("oauth login cookie success")
                        } else {
                            print("oauth login cookie failure")
                        }
                        onLoginSuccess()
                    } else {
                        error = "Failed to get OAuth token or session key"
                        oauthSheetURL = nil
                    }
                }
            })
        }
    }
}

struct OAuthURL: Identifiable {
    let id = UUID()
    let url: String
}

#Preview {
    LoginView(dfapi: DFAPI(url: URL(string: "http://localhost")!, token: ""), selectedServer: DjangoFilesSession(), onLoginSuccess: {
        print("Login success")
    })
} 
