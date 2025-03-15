import SwiftUI
import AuthenticationServices

struct OAuthWebView: View {
    let url: String
    let onComplete: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Color.clear.onAppear {
            startAuthentication()
        }
    }
    
    private func startAuthentication() {
        print("Starting authentication...")
        guard let authURL = URL(string: url) else {
            print("Failed to create URL from string: '\(url)'")
            onComplete(nil)
            dismiss()
            return
        }
        print("Auth URL created: \(authURL)")
    
        // Create the auth session
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "djangofiles",
            completionHandler: { callbackURL, error in          
                if let error = error {
                    print("Authentication failed: \(error.localizedDescription)")
                    onComplete(nil)
                    dismiss()
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                    print("No callback URL or token received")
                    onComplete(nil)
                    dismiss()
                    return
                }
                
                onComplete(token)
                dismiss()
            }
        )

        // Present the authentication session
        session.presentationContextProvider = WindowProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        
        let started = session.start()
        print("Session started: \(started)")  // Debug print
        
        if !started {
            print("Failed to start authentication session")
            onComplete(nil)
            dismiss()
        }
    }
}

// Helper class to provide window for ASWebAuthenticationSession
class WindowProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WindowProvider()
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window found")
        }
        return window
    }
}

#Preview {
    OAuthWebView(url: "https://example.com/oauth") { token in
        print("Received token: \(String(describing: token))")
    }
} 
