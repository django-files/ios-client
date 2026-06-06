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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWebSocketToast),
            name: Notification.Name("DFWebSocketToastNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionRequest),
            name: DFWebSocket.connectionRequestNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleWebSocketToast(notification: Notification) {
        let info = notification.userInfo ?? [:]
        if let groupKey = info["groupKey"] as? String,
           let singular = info["singleMessage"] as? String,
           let pluralFormat = info["pluralFormat"] as? String {
            ToastManager.shared.showToast(
                groupKey: groupKey,
                systemImage: info["systemImage"] as? String,
                singular: singular,
                pluralFormat: pluralFormat
            )
        } else if let message = info["message"] as? String {
            ToastManager.shared.showToast(message: message)
        }
    }
    
    @objc private func handleConnectionRequest(notification: Notification) {
        guard let ws = notification.userInfo?["webSocket"] as? DFWebSocket else { return }
        attach(to: ws)
    }

    /// Adopt an existing `DFWebSocket` as the observer's delegate. The caller
    /// retains ownership of the socket's lifecycle — we only listen.
    func attach(to webSocket: DFWebSocket) {
        print("WebSocketToastObserver: Attaching to WebSocket")
        self.webSocket = webSocket
        webSocket.delegate = self
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
