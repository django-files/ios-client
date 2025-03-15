import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    let selectedServer: DjangoFilesSession  // Regular property, not @Bindable
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var authMethods: [DFAuthMethod] = []
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    @State private var showWebView: Bool = false
    @State private var selectedOAuthURL: String? = nil
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
        if let oauthUrl = URL(string: url) {
            selectedOAuthURL = oauthUrl.absoluteString
            showWebView = true
        } else {
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
                ScrollView {
                    VStack(spacing: 20) {
                        // Local login form
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
                                    .background(Color.gray)
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
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await fetchAuthMethods()
            }
        }
        .sheet(isPresented: $showWebView) {
            if let url = selectedOAuthURL {
                AuthView(
                    authController: AuthController(),
                    httpsUrl: url,
                    doReset: true,
                    session: nil,
                    onLoadedAction: nil,
                    onAuthAction: {
                        showWebView = false
                        onLoginSuccess()
                    },
                    onSchemeRedirectAction: nil,
                    onCancelledAction: {
                        showWebView = false
                        error = "Authentication cancelled"
                    },
                    onStartedLoadingAction: nil
                )
            }
        }
    }
}

#Preview {
    LoginView(dfapi: DFAPI(url: URL(string: "https://example.com")!, token: ""), selectedServer: DjangoFilesSession(), onLoginSuccess: {
        print("Login success")
    })
} 
