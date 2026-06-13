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
    let isLive: Bool?

    enum CodingKeys: String, CodingKey {
        case event, message, delay, id, name, user, expr, password, objects
        case bsClass = "bsClass"
        case `private`
        case old_name
        case isLive = "is_live"
    }
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
    
    private static let toastNotification = Notification.Name("DFWebSocketToastNotification")
    static let fileDeleteNotification = Notification.Name("DFWebSocketFileDeleteNotification")
    static let fileNewNotification = Notification.Name("DFWebSocketFileNewNotification")
    static let albumNewNotification = Notification.Name("DFWebSocketAlbumNewNotification")
    static let albumDeleteNotification = Notification.Name("DFWebSocketAlbumDeleteNotification")
    static let streamStatusNotification = Notification.Name("DFWebSocketStreamStatusNotification")
    static let albumUpdateNotification = Notification.Name("DFWebSocketAlbumUpdateNotification")
    static let streamDeleteNotification = Notification.Name("DFWebSocketStreamDeleteNotification")
    static let connectionRequestNotification = Notification.Name("DFWebSocketConnectionRequest")

    private static let fileEventDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let albumEventDecoder = JSONDecoder()

    private func postToast(_ message: String) {
        NotificationCenter.default.post(
            name: Self.toastNotification,
            object: nil,
            userInfo: ["message": message]
        )
    }

    /// Post a coalescing toast. Bursts of events sharing `groupKey` (e.g. a
    /// batch delete fan-out from the server) collapse into a single toast whose
    /// text is regenerated from `pluralFormat` with `{count}` substituted in.
    private func postGroupedToast(
        groupKey: String,
        singleMessage: String,
        pluralFormat: String,
        systemImage: String? = nil
    ) {
        var info: [String: Any] = [
            "groupKey": groupKey,
            "singleMessage": singleMessage,
            "pluralFormat": pluralFormat,
        ]
        if let systemImage {
            info["systemImage"] = systemImage
        }
        NotificationCenter.default.post(
            name: Self.toastNotification,
            object: nil,
            userInfo: info
        )
    }

    private func handleMessage(_ messageText: String) {
        print("WebSocket message received: \(messageText)")

        guard let data = messageText.data(using: .utf8) else { return }

        let message: DFWebSocketMessage
        do {
            message = try JSONDecoder().decode(DFWebSocketMessage.self, from: data)
        } catch {
            print("Failed to decode WebSocket message: \(error)")
            return
        }

        switch message.event {
        case "toast", "notification":
            postToast(message.message ?? "New notification")

        case "file-new":
            // Broadcast is scoped to user-{user_id}, so this is always our own account; no toast.
            if let file = try? Self.fileEventDecoder.decode(DFFile.self, from: data) {
                NotificationCenter.default.post(
                    name: Self.fileNewNotification,
                    object: nil,
                    userInfo: ["file": file]
                )
            }

        case "file-delete":
            postGroupedToast(
                groupKey: "ws.file-delete",
                singleMessage: "File \(message.name ?? "Untitled.file") deleted.",
                pluralFormat: "{count} files deleted."
            )
            if let id = message.id {
                NotificationCenter.default.post(
                    name: Self.fileDeleteNotification,
                    object: nil,
                    userInfo: ["id": id]
                )
            }

        case "album-new":
            postGroupedToast(
                groupKey: "ws.album-new",
                singleMessage: "Album \(message.name ?? "Untitled") created.",
                pluralFormat: "{count} albums created."
            )
            if let album = try? Self.albumEventDecoder.decode(DFAlbum.self, from: data) {
                NotificationCenter.default.post(
                    name: Self.albumNewNotification,
                    object: nil,
                    userInfo: ["album": album]
                )
            } else {
                NotificationCenter.default.post(name: Self.albumNewNotification, object: nil)
            }

        case "album-update":
            // The payload lacks `url` so a full DFAlbum decode fails.
            // Use the already-decoded message envelope for a partial field update.
            if let id = message.id {
                var info: [String: Any] = ["id": id]
                if let p = message.private  { info["private"]  = p }
                if let n = message.name     { info["name"]     = n }
                if let pw = message.password { info["password"] = pw }
                if let e = message.expr     { info["expr"]     = e }
                NotificationCenter.default.post(
                    name: Self.albumUpdateNotification,
                    object: nil,
                    userInfo: info
                )
            }

        case "album-delete":
            postGroupedToast(
                groupKey: "ws.album-delete",
                singleMessage: "Album \(message.name ?? "Untitled") deleted.",
                pluralFormat: "{count} albums deleted."
            )
            if let id = message.id {
                NotificationCenter.default.post(
                    name: Self.albumDeleteNotification,
                    object: nil,
                    userInfo: ["id": id]
                )
            }

        case "stream-status":
            let streamName = message.name ?? "Stream"
            postToast(message.isLive == true ? "\(streamName) is now live." : "\(streamName) has ended.")
            if let name = message.name, let isLive = message.isLive {
                NotificationCenter.default.post(
                    name: Self.streamStatusNotification,
                    object: nil,
                    userInfo: ["name": name, "isLive": isLive]
                )
            }

        case "stream-delete":
            if let name = message.name {
                NotificationCenter.default.post(
                    name: Self.streamDeleteNotification,
                    object: nil,
                    userInfo: ["name": name]
                )
            }

        default:
            print("WebSocket: Unhandled event: \(message.event)")
        }

        DispatchQueue.main.async {
            self.delegate?.webSocket(self, didReceiveMessage: message)
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
        
        postToast("WebSocket Connected")

        delegate?.webSocketDidConnect(self)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown reason"
        print("WebSocket Closed with code: \(closeCode), reason: \(reasonString)")

        postToast("WebSocket Disconnected: \(closeCode)")
        
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
        // Close any existing socket from a prior session so we don't leak a
        // connection (and double-deliver events) when the user switches servers.
        DFAPI.sharedWebSocket?.disconnect()

        let webSocket = self.createWebSocket()
        DFAPI.sharedWebSocket = webSocket

        // Hand the live socket to WebSocketToastObserver so it attaches as
        // delegate. Passing `self` (the api) instead would cause the observer
        // to open a second connection and every event would fire twice.
        NotificationCenter.default.post(
            name: DFWebSocket.connectionRequestNotification,
            object: nil,
            userInfo: ["webSocket": webSocket]
        )

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

