import SwiftUI
import WebKit

struct OAuthWebView: UIViewRepresentable {
    let url: String
    let onComplete: (String?) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        print("Creating WebView with raw URL string: '\(url)'") // Print the exact string
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
//        webView.customUserAgent = "Mozilla/5.0 (Linux; Android 8.0; Pixel 2 Build/OPD3.170816.012) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.82 Mobile Safari/537.36"
        
        if let url = URL(string: url) {
            print("Successfully created URL: \(url)")
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("Failed to create URL from string: '\(url)'") // Added quotes to see whitespace
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OAuthWebView
        
        init(_ parent: OAuthWebView) {
            self.parent = parent
        }
        
        // Add navigation error handling
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView failed to load: \(error.localizedDescription)")
            print("Error details: \(error)")  // Add this for more detail
        }
        
        // Add navigation start handling
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("WebView started loading")
        }
        
        // Add navigation completion handling
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                print("Navigating to: \(url)") // Debug print
                
                if url.absoluteString.contains("token=") {
                    print("Found token in URL") // Debug print
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
                    parent.onComplete(token)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
} 
