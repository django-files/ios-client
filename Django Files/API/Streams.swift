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
    var isLive: Bool
    let startedAt: Date?
    let endedAt: Date?
    let uniqueViews: Int
    var isPublic: Bool
    let password: String?
    let viewerLimit: Int
    let liveChat: Bool
    let anonymousChat: Bool
    let userName: String
    let userUsername: String
    let url: String
    let isOwner: Bool
    let subscriberCount: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, title, description, password, url
        case isLive, startedAt, endedAt, uniqueViews
        case isPublic = "public"   // JSON key is "public", not "is_public"
        case viewerLimit, liveChat, anonymousChat
        case userName, userUsername, isOwner, subscriberCount
    }
}

struct DFStreamIngestInfo: Codable {
    let rtmpHost: String
    let rtmpPort: Int
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
    private var reconnectAttempts = 0

    private let maxReconnectAttempts = 10
    private let maxMessages = 500

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
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true) else { return }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/home/"
        guard let wsURL = components.url else { return }

        urlSession?.invalidateAndCancel()
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
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
    }

    private func reconnect() {
        guard !isReconnecting, !isManuallyDisconnected else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            appendMessage(.system("Connection lost. Refresh to reconnect."))
            return
        }
        isReconnecting = true
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)) * 2.0, 32.0)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate(); pingTimer = nil
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
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
        await DFAPI(url: serverURL, token: token).pingStream(name: streamName)
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
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamChatEvent.self, from: data),
              event.name == streamName else { return }

        switch event.event {
        case "chat-history":
            if let vid = event.viewerId { myViewerId = vid }
            messages = (event.messages ?? []).suffix(maxMessages).map { msg in
                DisplayChatMessage(from: StreamChatMessage(
                    userId: msg.userId,
                    username: msg.username,
                    displayName: msg.displayName,
                    avatarUrl: resolveAvatarURL(msg.avatarUrl),
                    message: msg.message,
                    timestamp: msg.timestamp
                ))
            }
            if let vs = event.viewers { viewers = vs.map(resolveViewer) }

        case "chat-message":
            if let msg = buildMessage(from: event) { appendMessage(msg) }

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
                appendMessage(.system("Your name has been set to: \(name)"))
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
                appendMessage(.system(live ? "Stream is now live." : "Stream has ended."))
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
        sendSocketAny(data)
    }

    private func sendSocketAny(_ data: [String: Any]) {
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
        appendMessage(.system("You left the chat. Type /join to rejoin."))
    }

    private func appendMessage(_ msg: DisplayChatMessage) {
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
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

    func setLiveChat(_ enabled: Bool) {
        sendSocketAny(["method": "set-stream-live-chat", "name": streamName, "enabled": enabled])
    }

    func setAnonymousChat(_ enabled: Bool) {
        sendSocketAny(["method": "set-stream-anonymous-chat", "name": streamName, "enabled": enabled])
    }
}

// MARK: - URLSessionWebSocketDelegate

extension StreamChatManager: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.reconnectAttempts = 0
            self.isConnected = true
            if !self.token.isEmpty {
                self.sendSocket(["method": "authorize", "authorization": self.token])
            }
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
    public func getStreams(page: Int = 1, filterUserID: Int? = nil, selectedServer: DjangoFilesSession? = nil) async throws -> DFStreamsResponse {
        var parameters: [String: String] = [:]
        if let filterUserID {
            parameters["user"] = String(filterUserID)
        }
        let responseBody = try await makeAPIRequest(
            path: "/api/streams/\(page)/",
            parameters: parameters,
            method: .get,
            selectedServer: selectedServer
        )
        do {
            return try decoder.decode(DFStreamsResponse.self, from: responseBody)
        } catch {
            throw DFAPIError.decoding(error)
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
            return try decoder.decode(DFStreamIngestInfo.self, from: responseBody)
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
            return try decoder.decode(DFStreamViewersResponse.self, from: responseBody).count
        } catch {
            print("getStreamViewerCount failed: \(error)")
            return nil
        }
    }

    public func toggleStreamPublic(name: String, newValue: Bool, selectedServer: DjangoFilesSession? = nil) async -> Bool? {
        do {
            let body: [String: Bool] = ["public": newValue]
            let json = try JSONEncoder().encode(body)
            let path = "/api/stream/\(name)/"
            let responseBody = try await makeAPIRequest(
                body: json,
                path: path,
                parameters: [:],
                method: .patch,
                expectedResponse: .ok,
                headerFields: [.contentType: "application/json"],
                selectedServer: selectedServer
            )
            let stream = try decoder.decode(DFStream.self, from: responseBody)
            return stream.isPublic
        } catch {
            print("Error toggling stream public: \(error)")
            return nil
        }
    }

    public func deleteStream(name: String, selectedServer: DjangoFilesSession? = nil) async -> Bool {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["names": [name]])
            _ = try await makeAPIRequest(
                body: body,
                path: getAPIPath(.delete_stream),
                parameters: [:],
                method: .delete,
                selectedServer: selectedServer
            )
            return true
        } catch {
            print("Stream delete failed: \(error)")
            return false
        }
    }

    public func getStreamCommands(name: String, selectedServer: DjangoFilesSession? = nil) async -> StreamCommandsResponse? {
        do {
            let responseBody = try await makeAPIRequest(
                path: "/api/stream/commands/\(name)/",
                parameters: [:],
                method: .get,
                headerFields: [.accept: "application/json"],
                selectedServer: selectedServer
            )
            return try decoder.decode(StreamCommandsResponse.self, from: responseBody)
        } catch {
            print("getStreamCommands failed: \(error)")
            return nil
        }
    }
}

// MARK: - Slash Commands

struct SlashCommand: Identifiable, Codable {
    let command: String
    let args: String
    let description: String
    let category: String

    var id: String { command }
    var hasArgs: Bool { !args.isEmpty }

    static let localFallback: [SlashCommand] = [
        SlashCommand(command: "/join",  args: "", description: "Join the stream chat",  category: "chat"),
        SlashCommand(command: "/leave", args: "", description: "Leave the stream chat", category: "chat"),
    ]
}

// MARK: - Stream Commands Response

struct StreamCommandsResponse: Decodable {
    let commands: [SlashCommand]
    let liveChat: Bool
    let anonymousChat: Bool
    let title: String?
    let description: String?
    let isLive: Bool?
    let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case commands, title, description
        case liveChat, anonymousChat, isLive, isPublic
    }
}
