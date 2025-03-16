import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedServer: DjangoFilesSession
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var authMethods: [DFAuthMethod] = []
    @State private var siteName: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    @State private var oauthSheetURL: OAuthURL? = nil
    @State private var isLoggingIn: Bool = false
    @State private var showErrorBanner: Bool = false
    

    let dfapi: DFAPI
    var onLoginSuccess: () -> Void
    
    init(selectedServer: DjangoFilesSession, onLoginSuccess: @escaping () -> Void) {
        print("LoginView init")
        self.dfapi = DFAPI(
            url: URL(string: selectedServer.url) ?? URL(string: "http://notarealhost")!,
            token: selectedServer.token
        )
        self.selectedServer = selectedServer
        self.onLoginSuccess = onLoginSuccess
    }
    
    private func fetchAuthMethods(selectedServer: DjangoFilesSession) async {
        print("Fetching auth methods \(selectedServer.url)")
        isLoading = true
        if let response = await dfapi.getAuthMethods() {
            print("methods fetched")
            authMethods = response.authMethods
            siteName = response.siteName
        } else {
            error = "Failed to fetch authentication methods, is this a Django Files server?"
        }
        print("done")
        isLoading = false
    }
    
    private func handleLocalLogin() async {
        isLoggingIn = true
        guard authMethods.contains(where: { $0.name == "local" }) else { return }
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
        ZStack {
            VStack {
                if isLoading {
                    ProgressView("Loading authentication methods...")
                } else if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                    Button("Retry") {
                        Task {
                            await fetchAuthMethods(selectedServer: selectedServer)
                        }
                    }
                } else {
                    GeometryReader { geometry in
                        VStack() {
                            // Local login form
                            Text(siteName).font(.title)
                            Text("Login for \(dfapi.url)")
                                .padding([.top, .bottom], 5)
                            if authMethods.contains(where: { $0.name == "local" }) {
                                VStack(spacing: 15) {
                                    TextField("Username", text: $username)
                                        .font(.title2)
                                        .padding()
                                        .frame(width: 270, height: 50).border(Color.gray)
                                        .cornerRadius(3)
                                        .autocapitalization(.none)
                                        .disabled(isLoggingIn)
                                        .padding([.leading, .trailing])
                                    SecureField("Password", text: $password)
                                        .font(.title3)
                                        .padding()
                                        .frame(width: 270, height: 50).border(Color.gray)
                                        .cornerRadius(3)
                                        .disabled(isLoggingIn)
                                        .padding([.leading, .trailing])
                                    
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
                                    .padding([.top], 15)
                                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                                }
                                .padding([.leading, .trailing], 50)
                                .padding([.bottom], 15)
                                Divider()
                                .padding([.bottom], 15)
                            }

                            // OAuth methods
                            ForEach(authMethods.filter { $0.name != "local" }, id: \.name) { method in
                                Button {
                                    handleOAuthLogin(url: method.url)
                                } label: {
                                    HStack {
                                        Text("\(method.name.capitalized) Login")
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .padding([.leading, .trailing], 50)
                                .padding([.bottom])
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height
                        )
                    }
                }
            }
            .onAppear {
                Task {
                    await fetchAuthMethods(selectedServer: selectedServer)
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
                            showErrorBanner = true
                            oauthSheetURL = nil
                            // Automatically hide the banner after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showErrorBanner = false
                                }
                            }
                        }
                    }
                })
            }
            
            // Error banner overlay
            if showErrorBanner {
                VStack {
                    Spacer()
                    Text("Authentication failed. Please try again.")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: showErrorBanner)
            }
        }
    }
}

struct OAuthURL: Identifiable {
    let id = UUID()
    let url: String
}

#Preview {
    LoginView(selectedServer: DjangoFilesSession(url: "http://localhost"), onLoginSuccess: {
        print("Login success")
    })
} 
