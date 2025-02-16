//
//  Auth.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import SwiftUI
import WebKit
import AuthenticationServices

class AuthController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return view.window!
    }
}

struct AuthView: UIViewRepresentable {
    @State var authController: AuthController?
    @State var session: ASWebAuthenticationSession?
    @Environment(\.dismiss) private var dismiss
    var httpsUrl: String
    
    func makeUIView(context: Context) -> WKWebView {
        guard let url = URL(string: httpsUrl) else {
            return WKWebView()
        }
        
        let request = URLRequest(url: url)
        let webView = WKWebView()
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        doAuth()
    }
    
    func doAuth(){
        guard let authURL = URL(string: "\(httpsUrl)/oauth/?next=/test") else {return}
        let session = ASWebAuthenticationSession(url: authURL, callback: ASWebAuthenticationSession.Callback.https(host: httpsUrl, path: "/oauth/*")){ callbackURL, error in
            guard error == nil, let success = callbackURL else { return }

            let code = NSURLComponents(string: (success.absoluteString))?.queryItems?.filter({ $0.name == "code" }).first
            
            print(code?.value ?? "No code")
        }
        authController = AuthController()
        session.presentationContextProvider = authController
        session.start()
    }
}

struct AuthView_Preview: PreviewProvider {
    static var previews: some View {
        AuthView(httpsUrl: "https://d.luac.es")
    }
}
