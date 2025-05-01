//
//  WebSocketObs.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/1/25.
//

import SwiftUI

/// This class observes WebSocket notifications and displays them as toasts
class WebSocketToastObserver: DFWebSocketDelegate {
    static let shared = WebSocketToastObserver()
    private var webSocket: DFWebSocket?
    
    private init() {
        print("WebSocketToastObserver initialized")
        
        // Register for WebSocket toast notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWebSocketToast),
            name: Notification.Name("DFWebSocketToastNotification"),
            object: nil
        )
        
        // Register for WebSocket connection requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionRequest),
            name: Notification.Name("DFWebSocketConnectionRequest"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleWebSocketToast(notification: Notification) {
        print("WebSocketToastObserver: Received notification with info: \(String(describing: notification.userInfo))")
        if let message = notification.userInfo?["message"] as? String {
            // Use the existing ToastManager to display the message
            DispatchQueue.main.async {
                print("WebSocketToastObserver: Showing toast with message: \(message)")
                ToastManager.shared.showToast(message: message)
            }
        }
    }
    
    @objc private func handleConnectionRequest(notification: Notification) {
        print("WebSocketToastObserver: Received connection request")
        if let api = notification.userInfo?["api"] as? DFAPI {
            connectToWebSocket(api: api)
        }
    }
    
    // Connect directly to the WebSocket service
    func connectToWebSocket(api: DFAPI) {
        print("WebSocketToastObserver: Connecting to WebSocket")
        webSocket = api.createWebSocket()
        webSocket?.delegate = self
    }
    
    // MARK: - DFWebSocketDelegate methods
    
    func webSocketDidConnect(_ webSocket: DFWebSocket) {
        print("WebSocketToastObserver: WebSocket connected")
    }
    
    func webSocketDidDisconnect(_ webSocket: DFWebSocket, withError error: Error?) {
        print("WebSocketToastObserver: WebSocket disconnected with error: \(String(describing: error))")
    }
    
    func webSocket(_ webSocket: DFWebSocket, didReceiveMessage data: DFWebSocketMessage) {
        print("WebSocketToastObserver: Received message: \(data.event), message: \(String(describing: data.message))")
        
        // Directly handle toast messages
        if data.event == "toast" || data.event == "notification" {
            DispatchQueue.main.async {
                ToastManager.shared.showToast(message: data.message ?? "New notification")
            }
        }
    }
}

// Extension to set up the observer in the app
extension UIApplication {
    static func setupWebSocketToastObserver() {
        print("Setting up WebSocketToastObserver")
        _ = WebSocketToastObserver.shared
    }
    
    static func connectWebSocketObserver(api: DFAPI) {
        print("Connecting WebSocketToastObserver to API")
        WebSocketToastObserver.shared.connectToWebSocket(api: api)
    }
}
