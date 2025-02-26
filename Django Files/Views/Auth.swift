//
//  Auth.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import SwiftUI
import WebKit
import AuthenticationServices
import Foundation

class AuthController: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let tempTokenFileName: String = "token.txt"
    
    var webView: WKWebView!
    var url: URL!

    var authComplete: Bool = false
    var gettingToken: Bool = false
    var isLoaded: Bool = false
    
    var onLoadedAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void){
        if authComplete{
            decisionHandler(.allow)
            return
        }
        
        if navigationResponse.response.url?.absoluteString == url.appendingPathComponent("/").absoluteString {
            let code = (navigationResponse.response as! HTTPURLResponse).statusCode
            switch code{
            case 200:
                decisionHandler(.cancel)
                Task{
                    webView.load(URLRequest(url: url.appending(path: "/api/token")))
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
        else if navigationResponse.response.url?.absoluteString == url.appendingPathComponent("/api/token/").absoluteString{
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
        onLoadedAction?()
        
        Task{
            webView.load(URLRequest(url: url))
        }
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
    }
}

struct AuthView: UIViewRepresentable {
    var authController: AuthController
    @State var httpsUrl: String
    @Environment(\.dismiss) private var dismiss
    
    @State var isLoadedHandled: Bool = false
    
    var onLoadedAction: (() -> Void)?
    var onCancelledAction: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        guard let url = URL(string: httpsUrl) else {
            return WKWebView()
        }
        
        let request = URLRequest(url: url)
        let webView = WKWebView()
        
        authController.reset()
        authController.url = url
        authController.webView = webView
        authController.onLoadedAction = onLoadedAction
        authController.onCancelledAction = onCancelledAction
        
        webView.navigationDelegate = authController
        webView.load(request)
        
        return webView
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
    func onCancelled(_ handler: @escaping () -> Void) -> AuthView {
        var new = self
        new.onCancelledAction = handler
        return new
    }
}
