//
//  Auth.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import SwiftUI
@preconcurrency import WebKit
import AuthenticationServices
import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

class AuthController: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
//    let tempTokenFileName: String = "token.txt"
    
    var url: URL?
    
    var webView: WKWebView

    let customUserAgent = "DjangoFiles iOS \(String(describing: Bundle.main.releaseVersionNumber ?? "Unknown"))(\(String(describing: Bundle.main.buildVersionNumber ?? "-")))"

    public var isLoaded: Bool = false
    private var reloadState: Bool = false
    private var authError: String? = nil
    
    private var safeAreaInsets: EdgeInsets = EdgeInsets()
    
    public func getAuthErrorMessage() -> String? {
        return authError
    }
    
    public var schemeURL: String?
    
    var onAuthAction: (() -> Void)?
    var onLoadedAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?
    var onStartedLoadingAction: (() -> Void)?
    var onSchemeRedirectAction: (() -> Void)?
    
    override init() {
        // Configure WebView to use persistent cookie storage
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // Use persistent storage instead of ephemeral
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        super.init()
        
        // Configure the webView after super.init()
        self.webView.customUserAgent = customUserAgent
        self.webView.navigationDelegate = self
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void){
        webView.isHidden = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        onLoadedAction?()
        decisionHandler(.allow)
        return
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if reloadState{
            Task{
                webView.load(URLRequest(url: url!))
                reloadState = false
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy{
        webView.scrollView.zoomScale = 0
        
        if navigationAction.request.url?.scheme == "djangofiles"{
            var schemeRemove = URLComponents(url: navigationAction.request.url!, resolvingAgainstBaseURL: true)!
            schemeRemove.scheme = nil
            schemeURL = schemeRemove.url!.absoluteString.trimmingCharacters(in: ["/", "\\"])
            onSchemeRedirectAction?()
            loadHomepage()
            return .cancel
        }
        else if navigationAction.request.url?.absoluteString == "about:blank"{
            return .allow
        }
        else if url?.scheme == "https" && navigationAction.request.url?.scheme != "https" {
            onCancelledAction?()
            reset()
            authError = "Blocked attempt to navigate to non-HTTPS URL while using HTTPS."
            return .cancel
        }
        else{
            return .allow
        }
    }
    
    public func setSafeAreaInsets(_ insets: EdgeInsets){
        safeAreaInsets = insets
    }
    
    public func reset(){
        authError = nil
        isLoaded = false
        loadHomepage()
    }
    
    public func applyCookies(from session: DjangoFilesSession) {
        if URL(string: session.url) != nil {} else { return }
        
        // Apply cookies to the WebView's data store
        let dataStore = webView.configuration.websiteDataStore
        for cookie in session.cookies {
            dataStore.httpCookieStore.setCookie(cookie)
        }
    }
    
    private func loadHomepage(){
        reloadState = true
        webView.isHidden = true
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        Task{
            onStartedLoadingAction?()
        }
    }
}

struct AuthView: UIViewRepresentable {
    @Environment(\.dismiss) private var dismiss
    
    let authController: AuthController
    var httpsUrl: String
    let doReset: Bool
    let session: DjangoFilesSession?
    
    var onLoadedAction: (() -> Void)?
    var onSchemeRedirectAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?
    var onStartedLoadingAction: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        guard let url = URL(string: httpsUrl) else {
            return WKWebView()
        }
        
        if doReset {
            authController.reset()
        }
        
        authController.url = url
        
        // Apply cookies from the session if available
        if let session = session {
            authController.applyCookies(from: session)
        }
        
        return authController.webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}


extension AuthView {
    func onLoaded(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onLoadedAction = handler
        return new
    }
    func onSchemeRedirect(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onSchemeRedirectAction = handler
        return new
    }
    func onCancelled(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onCancelledAction = handler
        return new
    }
    func onStartedLoading(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onStartedLoadingAction = handler
        return new
    }
}
