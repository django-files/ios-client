//
//  Streams.swift
//  Django Files
//

import Foundation

// MARK: - REST Models

struct DFStream: Codable, Identifiable {
    let name: String
    let title: String
    let description: String
    let isLive: Bool
    let startedAt: Date?
    let endedAt: Date?
    let uniqueViews: Int
    let isPublic: Bool
    let password: String
    let viewerLimit: Int
    let liveChat: Bool
    let anonymousChat: Bool
    let userName: String
    let userUsername: String
    let url: String
    let isOwner: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, title, description, password, url
        case isLive = "is_live"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case uniqueViews = "unique_views"
        case isPublic = "public"
        case viewerLimit = "viewer_limit"
        case liveChat = "live_chat"
        case anonymousChat = "anonymous_chat"
        case userName = "user_name"
        case userUsername = "user_username"
        case isOwner = "is_owner"
    }
}

struct DFStreamIngestInfo: Codable {
    let rtmpHost: String
    let rtmpPort: Int

    enum CodingKeys: String, CodingKey {
        case rtmpHost = "rtmp_host"
        case rtmpPort = "rtmp_port"
    }
}

struct DFStreamsResponse: Codable {
    let streams: [DFStream]
    let next: Int?
    let count: Int
}

struct DFStreamViewersResponse: Codable {
    let count: Int
}

// MARK: - Chat Models

struct ChatViewer: Codable, Identifiable, Equatable {
    let viewerId: String
    let userId: Int?
    let username: String
    let displayName: String
    let avatarUrl: String

    var id: String { viewerId }

    enum CodingKeys: String, CodingKey {
        case viewerId = "viewer_id"
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct StreamChatMessage: Codable {
    let userId: Int?
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let message: String?
    let timestamp: Double?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case message, timestamp
    }
}

/// Unified envelope covering all stream chat WebSocket events
struct StreamChatEvent: Codable {
    let event: String
    let name: String?
    let userId: Int?
    let username: String?
    let displayName: String?
    let avatarUrl: String?
    let message: String?
    let timestamp: Double?
    let viewerId: String?
    let liveChat: Bool?
    let anonymousChat: Bool?
    let viewer: ChatViewer?
    let viewers: [ChatViewer]?
    let messages: [StreamChatMessage]?
    let title: String?
    let description: String?
    let isLive: Bool?

    enum CodingKeys: String, CodingKey {
        case event, name, message, timestamp, username, viewer, viewers, messages
        case title, description
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case viewerId = "viewer_id"
        case liveChat = "live_chat"
        case anonymousChat = "anonymous_chat"
        case isLive = "is_live"
    }
}

/// Display-ready chat message (includes system messages)
struct DisplayChatMessage: Identifiable {
    let id: UUID
    let displayName: String
    let avatarURL: String
    let message: String
    let timestamp: String
    let isSystem: Bool
    let userId: Int?
    let username: String

    init(from msg: StreamChatMessage) {
        id = UUID()
        displayName = msg.displayName ?? msg.username ?? "Anonymous"
        avatarURL = msg.avatarUrl ?? ""
        message = msg.message ?? ""
        if let ts = msg.timestamp {
            let date = Date(timeIntervalSince1970: ts)
            timestamp = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        } else {
            timestamp = ""
        }
        isSystem = false
        userId = msg.userId
        username = msg.username ?? ""
    }

    static func system(_ text: String) -> DisplayChatMessage {
        DisplayChatMessage(
            id: UUID(), displayName: "", avatarURL: "",
            message: text, timestamp: "", isSystem: true, userId: nil, username: ""
        )
    }

    private init(id: UUID, displayName: String, avatarURL: String, message: String,
                 timestamp: String, isSystem: Bool, userId: Int?, username: String) {
        self.id = id; self.displayName = displayName; self.avatarURL = avatarURL
        self.message = message; self.timestamp = timestamp; self.isSystem = isSystem
        self.userId = userId; self.username = username
    }
}

// MARK: - StreamChatManager

@MainActor
class StreamChatManager: NSObject, ObservableObject {
    @Published var messages: [DisplayChatMessage] = []
    @Published var viewers: [ChatViewer] = []
    @Published var liveChat: Bool = true
    @Published var anonymousChat: Bool = false
    @Published var isBanned: Bool = false
    @Published var isConnected: Bool = false
    @Published var isManuallyDisconnected: Bool = false
    @Published var streamTitle: String
    @Published var streamDescription: String
    @Published var streamIsLive: Bool? = nil

    let serverURL: URL
    let token: String
    let streamName: String
    let isOwner: Bool
    let ownerUsername: String

    private(set) var myViewerId: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?
    private var httpPingTimer: Timer?
    private var reconnectTimer: Timer?
    private var isReconnecting = false

    init(serverURL: URL, token: String, streamName: String, isOwner: Bool,
         ownerUsername: String = "", title: String = "", description: String = "") {
        self.serverURL = serverURL
        self.token = token
        self.streamName = streamName
        self.isOwner = isOwner
        self.ownerUsername = ownerUsername
        self.streamTitle = title
        self.streamDescription = description
        super.init()
    }

    deinit {
        pingTimer?.invalidate()
        httpPingTimer?.invalidate()
        reconnectTimer?.invalidate()
    }

    // MARK: - Connection

    func connect() {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/home/"
        guard let wsURL = components.url else { return }

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: wsURL)
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
        setupPing()
    }

    func disconnect() {
        isManuallyDisconnected = true
        sendSocket(["method": "leave-stream-chat", "name": streamName])
        pingTimer?.invalidate(); pingTimer = nil
        httpPingTimer?.invalidate(); httpPingTimer = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func reconnect() {
        guard !isReconnecting, !isManuallyDisconnected else { return }
        isReconnecting = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate(); pingTimer = nil
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.isReconnecting = false
                self.connect()
            }
        }
    }

    // MARK: - Ping

    private func setupPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.webSocketTask?.sendPing { error in
                    if let error {
                        print("StreamChat ping error: \(error)")
                    }
                }
            }
        }
        // HTTP viewer presence ping every 58s
        httpPingTimer = Timer.scheduledTimer(withTimeInterval: 58, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.httpPing()
            }
        }
    }

    private func httpPing() async {
        let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let pingURL = URL(string: "\(base)/api/stream/ping/\(streamName)/") else { return }
        var request = URLRequest(url: pingURL)
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let msg):
                    if case .string(let text) = msg { self.handleText(text) }
                    else if case .data(let data) = msg,
                            let text = String(data: data, encoding: .utf8) { self.handleText(text) }
                    self.receiveMessage()
                case .failure(let error):
                    print("StreamChat receive error: \(error)")
                    self.isConnected = false
                    self.reconnect()
                }
            }
        }
    }

    private func handleText(_ text: String) {
        print("StreamChat raw message: \(text)")
        guard let data = text.data(using: .utf8) else {
            print("StreamChat: failed to encode text as UTF-8")
            return
        }
        guard let event = try? JSONDecoder().decode(StreamChatEvent.self, from: data) else {
            print("StreamChat: JSON decode failed for: \(text)")
            return
        }
        print("StreamChat decoded event=\(event.event) name=\(event.name ?? "nil") expecting=\(streamName)")
        guard event.name == streamName else { return }

        switch event.event {
        case "chat-history":
            if let vid = event.viewerId { myViewerId = vid }
            messages = []
            event.messages?.forEach { msg in
                let resolved = StreamChatMessage(
                    userId: msg.userId,
                    username: msg.username,
                    displayName: msg.displayName,
                    avatarUrl: resolveAvatarURL(msg.avatarUrl),
                    message: msg.message,
                    timestamp: msg.timestamp
                )
                messages.append(DisplayChatMessage(from: resolved))
            }
            if let vs = event.viewers { viewers = vs.map(resolveViewer) }

        case "chat-message":
            if let msg = buildMessage(from: event) { messages.append(msg) }

        case "chat-viewers":
            if let vs = event.viewers { viewers = vs.map(resolveViewer) }

        case "chat-viewer-joined":
            if let v = event.viewer, !viewers.contains(where: { $0.id == v.id }) {
                viewers.append(resolveViewer(v))
            }

        case "chat-viewer-left":
            if let vid = event.viewerId { viewers.removeAll { $0.viewerId == vid } }

        case "set-stream-title":
            if let t = event.title { streamTitle = t }

        case "set-stream-description":
            if let d = event.description { streamDescription = d }

        case "chat-settings":
            if let lc = event.liveChat { liveChat = lc }
            if let ac = event.anonymousChat { anonymousChat = ac }

        case "chat-name-set":
            if let name = event.displayName {
                messages.append(.system("Your name has been set to: \(name)"))
            }

        case "chat-banned":
            if event.viewerId == nil || event.viewerId == myViewerId { isBanned = true }

        case "chat-message-cleanup":
            if let uname = event.username {
                messages.removeAll {
                    !$0.isSystem && ($0.username == uname ||
                    (event.userId != nil && $0.userId == event.userId))
                }
            }

        case "stream-status":
            if let live = event.isLive {
                streamIsLive = live
                messages.append(.system(live ? "Stream is now live." : "Stream has ended."))
            }

        case "chat-retry":
            if !isManuallyDisconnected {
                Task { try? await Task.sleep(nanoseconds: 1_500_000_000); joinChat() }
            }

        default:
            break
        }
    }

    /// Turns a server-relative path like `/static/images/default_avatar.png`
    /// into a fully-qualified URL. Absolute URLs and nil pass through unchanged.
    private func resolveAvatarURL(_ path: String?) -> String? {
        guard let path, !path.isEmpty, path.hasPrefix("/") else { return path }
        let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)\(path)"
    }

    private func resolveViewer(_ viewer: ChatViewer) -> ChatViewer {
        guard viewer.avatarUrl.hasPrefix("/") else { return viewer }
        return ChatViewer(
            viewerId: viewer.viewerId,
            userId: viewer.userId,
            username: viewer.username,
            displayName: viewer.displayName,
            avatarUrl: resolveAvatarURL(viewer.avatarUrl) ?? viewer.avatarUrl
        )
    }

    private func buildMessage(from event: StreamChatEvent) -> DisplayChatMessage? {
        guard let msg = event.message else { return nil }
        let sm = StreamChatMessage(
            userId: event.userId,
            username: event.username,
            displayName: event.displayName ?? event.username ?? "Anonymous",
            avatarUrl: resolveAvatarURL(event.avatarUrl),
            message: msg,
            timestamp: event.timestamp
        )
        return DisplayChatMessage(from: sm)
    }

    // MARK: - Send

    private func sendSocket(_ data: [String: String]) {
        guard let json = try? JSONSerialization.data(withJSONObject: data),
              let text = String(data: json, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error { print("StreamChat send error: \(error)") }
        }
    }

    func joinChat() {
        guard !isManuallyDisconnected else { return }
        sendSocket(["method": "join-stream-chat", "name": streamName])
    }

    func leaveChat() {
        isManuallyDisconnected = true
        sendSocket(["method": "leave-stream-chat", "name": streamName])
        messages.append(.system("You left the chat. Type /join to rejoin."))
    }

    func rejoinChat() {
        isManuallyDisconnected = false
        sendSocket(["method": "join-stream-chat", "name": streamName])
    }

    func sendMessage(_ text: String) {
        sendSocket(["method": "send-chat-message", "name": streamName, "message": text])
    }

    func setName(_ name: String) {
        sendSocket(["method": "set-chat-name", "name": streamName, "custom_name": name])
    }

    // Owner-only commands
    func setTitle(_ title: String) {
        sendSocket(["method": "set-stream-title", "name": streamName, "title": title])
    }

    func setDescription(_ desc: String) {
        sendSocket(["method": "set-stream-description", "name": streamName, "description": desc])
    }

    func banUser(_ target: String) {
        sendSocket(["method": "ban-chat-user", "name": streamName, "target": target])
    }

    func banMessageCleanup(_ target: String) {
        sendSocket(["method": "ban-message-cleanup", "name": streamName, "target": target])
    }
}

// MARK: - URLSessionWebSocketDelegate

extension StreamChatManager: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.isConnected = true
            self.joinChat()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.isConnected = false
            if closeCode != .normalClosure && closeCode != .goingAway {
                self.reconnect()
            }
        }
    }
}

// MARK: - DFAPI Extension

extension DFAPI {
    public func getStreams(page: Int = 1, selectedServer: DjangoFilesSession? = nil) async -> DFStreamsResponse? {
        do {
            let responseBody = try await makeAPIRequest(
                path: "/api/streams/\(page)/",
                parameters: [:],
                method: .get,
                selectedServer: selectedServer
            )
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode(DFStreamsResponse.self, from: responseBody)
        } catch {
            print("getStreams failed: \(error)")
            return nil
        }
    }

    public func pingStream(name: String, selectedServer: DjangoFilesSession? = nil) async {
        _ = try? await makeAPIRequest(
            path: "/api/stream/ping/\(name)/",
            parameters: [:],
            method: .get,
            selectedServer: selectedServer
        )
    }

    public func getStreamIngestInfo(selectedServer: DjangoFilesSession? = nil) async -> DFStreamIngestInfo? {
        do {
            let responseBody = try await makeAPIRequest(
                path: "/api/stream/ingest/",
                parameters: [:],
                method: .get,
                headerFields: [.accept: "application/json"],
                selectedServer: selectedServer
            )
            return try JSONDecoder().decode(DFStreamIngestInfo.self, from: responseBody)
        } catch {
            print("getStreamIngestInfo failed: \(error)")
            return nil
        }
    }

    public func getStreamViewerCount(name: String, selectedServer: DjangoFilesSession? = nil) async -> Int? {
        do {
            let responseBody = try await makeAPIRequest(
                path: "/api/stream/viewers/\(name)/",
                parameters: [:],
                method: .get,
                headerFields: [.accept: "application/json"],
                selectedServer: selectedServer
            )
            return try JSONDecoder().decode(DFStreamViewersResponse.self, from: responseBody).count
        } catch {
            print("getStreamViewerCount failed: \(error)")
            return nil
        }
    }
}
