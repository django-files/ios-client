//
//  Websocket.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/1/25.
//

import Foundation
import Combine

protocol DFWebSocketDelegate: AnyObject {
    func webSocketDidConnect(_ webSocket: DFWebSocket)
    func webSocketDidDisconnect(_ webSocket: DFWebSocket, withError error: Error?)
    func webSocket(_ webSocket: DFWebSocket, didReceiveMessage data: DFWebSocketMessage)
}

// Message types that can be received from the server
struct DFWebSocketMessage: Codable {
    let event: String
    let message: String?
    let bsClass: String?
    let delay: String?
    let id: Int?
    let name: String?
    let user: Int?
    let expr: String?
    let `private`: Bool?
    let password: String?
    let old_name: String?
    let objects: [DFWebSocketObject]?
}

struct DFWebSocketObject: Codable {
    let id: Int
    let name: String
    let expr: String?
    let `private`: Bool?
}

class DFWebSocket: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var session: URLSession!
    
    private var isConnected = false
    private var isReconnecting = false
    
    // URL components for the WebSocket connection
    private let server: URL
    private let token: String
    
    weak var delegate: DFWebSocketDelegate?
    
    init(server: URL, token: String) {
        self.server = server
        self.token = token
        super.init()
        
        // Create a URLSession with the delegate set to self
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: .main)
        
        // Connect to the WebSocket server
        connect()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection Management
    
    func connect() {
        // Create the WebSocket URL
        var components = URLComponents(url: server, resolvingAgainstBaseURL: true)!
        
        // Determine if we need wss or ws
        let isSecure = components.scheme == "https"
        components.scheme = isSecure ? "wss" : "ws"
        
        // Set the path for the WebSocket
        components.path = "/ws/home/"
        
        guard let url = components.url else {
            print("Invalid WebSocket URL")
            return
        }
        
        print("WebSocket: Connecting to \(url.absoluteString)...")
        
        // Create the WebSocket task
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Set up message receiving
        receiveMessage()
        
        // Setup ping timer to keep connection alive
        setupPingTimer()
        
        // Post a notification that we're attempting connection
//        NotificationCenter.default.post(
//            name: Notification.Name("DFWebSocketToastNotification"),
//            object: nil,
//            userInfo: ["message": "Connecting to WebSocket..."]
//        )
        
        print("WebSocket: Connection attempt started")
    }
    
    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        isConnected = false
    }
    
    private func reconnect() {
        guard !isReconnecting else { return }
        
        isReconnecting = true
        print("WebSocket Disconnected! Reconnecting...")
        
        // Clean up existing connection
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        
        // Schedule reconnection
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isReconnecting = false
            self.connect()
        }
    }
    
    private func setupPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.ping()
        }
    }
    
    private func ping() {
        webSocketTask?.sendPing { [weak self] error in
//            print("websocket ping")
            if let error = error {
                print("WebSocket ping error: \(error)")
                self?.reconnect()
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue listening for more messages
                self.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.delegate?.webSocketDidDisconnect(self, withError: error)
                self.reconnect()
            }
        }
    }
    
    private func handleMessage(_ messageText: String) {
        print("WebSocket message received: \(messageText)")
        
        guard let data = messageText.data(using: .utf8) else { return }
        
        do {
            let message = try JSONDecoder().decode(DFWebSocketMessage.self, from: data)
            
            // Post a notification for toast messages if the event is appropriate
            if message.event == "toast" || message.event == "notification" {
                let userInfo: [String: Any] = ["message": message.message ?? "New notification"]
                NotificationCenter.default.post(
                    name: Notification.Name("DFWebSocketToastNotification"),
                    object: nil,
                    userInfo: userInfo
                )
            } else if message.event == "file-new" {
                NotificationCenter.default.post(
                    name: Notification.Name("DFWebSocketToastNotification"),
                    object: nil,
                    userInfo: ["message": "New file (\(message.name ?? "Untitled.file"))"]
                )
            } else if message.event == "file-delete" {
                NotificationCenter.default.post(
                    name: Notification.Name("DFWebSocketToastNotification"),
                    object: nil,
                    userInfo: ["message": "File (\(message.name ?? "Untitled.file")) deleted."]
                )
            } else {
                // For debugging - post a notification for all message types
                print("WebSocket: Received message with event: \(message.event)")
                let displayText = "WebSocket: \(message.event) - \(message.message ?? "No message")"
                
                // Post notification for all WebSocket events during debugging
                NotificationCenter.default.post(
                    name: Notification.Name("DFWebSocketToastNotification"),
                    object: nil,
                    userInfo: ["message": displayText]
                )
            }
            
            // Process the message
            DispatchQueue.main.async {
                self.delegate?.webSocket(self, didReceiveMessage: message)
            }
        } catch {
            print("Failed to decode WebSocket message: \(error)")
            
            // Try to show the raw message as a toast for debugging
            NotificationCenter.default.post(
                name: Notification.Name("DFWebSocketToastNotification"),
                object: nil,
                userInfo: ["message": "Raw WebSocket message: \(messageText)"]
            )
        }
    }
    
    // MARK: - Sending Messages
    
    func send(message: String) {
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    func send<T: Encodable>(object: T) {
        do {
            let data = try JSONEncoder().encode(object)
            if let json = String(data: data, encoding: .utf8) {
                send(message: json)
            }
        } catch {
            print("Failed to encode WebSocket message: \(error)")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension DFWebSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket Connected.")
        isConnected = true
        
        // Post a notification that connection was successful
        NotificationCenter.default.post(
            name: Notification.Name("DFWebSocketToastNotification"),
            object: nil,
            userInfo: ["message": "WebSocket Connected"]
        )
        
        delegate?.webSocketDidConnect(self)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown reason"
        print("WebSocket Closed with code: \(closeCode), reason: \(reasonString)")
        
        // Post a notification about the disconnection
        NotificationCenter.default.post(
            name: Notification.Name("DFWebSocketToastNotification"),
            object: nil,
            userInfo: ["message": "WebSocket Disconnected: \(closeCode)"]
        )
        
        // Only trigger reconnect for abnormal closures
        if closeCode != .normalClosure && closeCode != .goingAway {
            delegate?.webSocketDidDisconnect(self, withError: nil)
            reconnect()
        }
    }
}

// MARK: - Extension to DFAPI

extension DFAPI {
    // Create and connect to a WebSocket, also setting up WebSocketToastObserver
    public func connectToWebSocket() -> DFWebSocket {
        let webSocket = self.createWebSocket()
        
        // Instead of directly accessing WebSocketToastObserver, post a notification
        // that the observer will pick up
        NotificationCenter.default.post(
            name: Notification.Name("DFWebSocketConnectionRequest"),
            object: nil,
            userInfo: ["api": self]
        )
        
        // Store as the shared instance
        DFAPI.sharedWebSocket = webSocket
        
        return webSocket
    }
    
    // Get the shared WebSocket or create a new one if none exists
    public static func getSharedWebSocket() -> DFWebSocket? {
        return sharedWebSocket
    }
    
    func createWebSocket() -> DFWebSocket {
        return DFWebSocket(server: self.url, token: self.token)
    }
}

