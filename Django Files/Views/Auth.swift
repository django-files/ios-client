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

class AuthController: NSObject, WKNavigationDelegate, WKDownloadDelegate, UIScrollViewDelegate {
    let tempTokenFileName: String = "token.txt"
    var serverButtonJavascript: String = ""
    
    var url: URL?
    
    let webView: WKWebView = FullScreenWebView()
    
    private var authComplete: Bool = false
    private var gettingToken: Bool = false
    public var isLoaded: Bool = false
    private var reloadState: Bool = false
    
    public var schemeURL: String?
    
    var onAuthAction: (() -> Void)?
    var onLoadedAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?
    var onStartedLoadingAction: (() -> Void)?
    var onSchemeRedirectAction: (() -> Void)?
    
    override init(){
        super.init()
        do{
            serverButtonJavascript = String(data: try Data(contentsOf: URL(fileURLWithPath: Bundle.main.resourcePath! + "/DFMenu.js")), encoding: .utf8)!
        }
        catch{
            serverButtonJavascript = ""
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void){
        webView.isHidden = false
        onLoadedAction?()
        
        if authComplete{
            decisionHandler(.allow)
            return
        }
        
        if navigationResponse.response.url?.absoluteString == url!.appendingPathComponent("/").absoluteString {
            let code = (navigationResponse.response as! HTTPURLResponse).statusCode
            switch code{
            case 200:
                decisionHandler(.cancel)
                Task{
                    webView.load(URLRequest(url: url!.appending(path: "/api/token")))
                }
                break
            case 302:
                decisionHandler(.allow)
                break
            default:
                decisionHandler(.cancel)
                onCancelledAction?()
                return
            }
            return
        }
        else if navigationResponse.response.url?.absoluteString == url!.appendingPathComponent("/api/token/").absoluteString{
            let response = navigationResponse.response as! HTTPURLResponse
            if response.statusCode == 200{
                gettingToken = true
                decisionHandler(.download)
            }
            else{
                onCancelledAction?()
            }
        }
        else{
            decisionHandler(.allow)
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if reloadState{
            Task{
                webView.load(URLRequest(url: url!))
                reloadState = false
            }
        }
        else if webView.url?.host() == url?.host(){
            webView.evaluateJavaScript(serverButtonJavascript, completionHandler: { (jsonRaw: Any?, error: Error?) in
            })
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy{
        if navigationAction.request.url?.scheme == "djangofiles"{
            var schemeRemove = URLComponents(url: navigationAction.request.url!, resolvingAgainstBaseURL: true)!
            schemeRemove.scheme = nil
            schemeURL = schemeRemove.url!.absoluteString.trimmingCharacters(in: ["/", "\\"])
            onSchemeRedirectAction?()
            return .cancel
        }
        else{
            return .allow
        }
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
        let targetURL = tempDirectoryURL.appendingPathComponent(tempTokenFileName)
        completionHandler(targetURL)
        authComplete = true
        
        if download.progress.fractionCompleted == 1{
            downloadDidFinish(download)
        }
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        isLoaded = true
        onAuthAction?()
        
        Task{
            webView.load(URLRequest(url: url!))
        }
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.pinchGestureRecognizer?.isEnabled = false
    }
    
    public func getToken() -> String?{
        if !isLoaded{
            return nil
        }
        let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
        let targetURL = tempDirectoryURL.appendingPathComponent(tempTokenFileName)
        do{
            let data = try Data(contentsOf: targetURL)
            isLoaded = true
            clearToken()
            return String(data: data, encoding: .utf8)!
        }
        catch{
            return nil
        }
    }
    
    public func clearToken(){
        let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
        let targetURL = tempDirectoryURL.appendingPathComponent(tempTokenFileName)
        do{
            if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: targetURL)
            }
        }
        catch{}
    }
    
    public func reset(){
        clearToken()
        authComplete = false
        isLoaded = false
        gettingToken = false
        loadHomepage()
    }
    
    private func loadHomepage(){
        reloadState = true
        webView.isHidden = true
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        onStartedLoadingAction?()
    }
}

struct AuthView: UIViewRepresentable {
    @Environment(\.dismiss) private var dismiss
    
    let authController: AuthController
    var httpsUrl: String
    let doReset: Bool
    
    var onLoadedAction: (() -> Void)?
    var onAuthAction: (() -> Void)?
    var onSchemeRedirectAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?
    var onStartedLoadingAction: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        guard let url = URL(string: httpsUrl) else {
            return FullScreenWebView()
        }
        
        if doReset{
            authController.url = url
            
            authController.onLoadedAction = onLoadedAction
            authController.onCancelledAction = onCancelledAction
            
            authController.onAuthAction = onAuthAction
            authController.onStartedLoadingAction = onStartedLoadingAction
            authController.onSchemeRedirectAction = onSchemeRedirectAction
            
            authController.webView.navigationDelegate = authController
            authController.webView.scrollView.delegate = authController
            authController.webView.scrollView.maximumZoomScale = 1
            authController.webView.scrollView.minimumZoomScale = 1
            authController.webView.scrollView.zoomScale = 1
            authController.webView.isOpaque = false
            
            authController.reset()
        }
        
        return authController.webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
}

class FullScreenWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}


extension AuthView {
    func onAuth(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onAuthAction = handler
        return new
    }
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
