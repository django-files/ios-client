//
//  StreamView.swift
//  Django Files
//
//  Supports:
//  - Authenticated own-server stream viewing
//  - Unauthenticated / cross-server stream viewing (token = "")
//  - Live HLS playback via AVKit
//  - Live chat with WebSocket
//  - Slash commands (/set-name, /title, /ban, etc.)
//

import SwiftUI
import AVKit

// MARK: - Slash Command Definitions

struct SlashCommand: Identifiable, Codable {
    let command: String
    let args: String
    let description: String
    let category: String

    var id: String { command }
    var hasArgs: Bool { !args.isEmpty }

    // Always-available local commands (don't require server permission)
    static let localFallback: [SlashCommand] = [
        SlashCommand(command: "/join",  args: "", description: "Join the stream chat",  category: "chat"),
        SlashCommand(command: "/leave", args: "", description: "Leave the stream chat", category: "chat"),
    ]
}

private struct StreamCommandsResponse: Decodable {
    let commands: [SlashCommand]
    let liveChat: Bool
    let anonymousChat: Bool
    let title: String?
    let description: String?
    let isLive: Bool?
    let isPublic: Bool?
    enum CodingKeys: String, CodingKey {
        case commands, title, description
        case liveChat = "live_chat"
        case anonymousChat = "anonymous_chat"
        case isLive = "is_live"
        case isPublic = "is_public"
    }
}

// MARK: - StreamView

struct StreamView: View {
    let serverURL: URL
    let streamName: String
    let token: String
    let initialStream: DFStream?
    let password: String?

    // HLS player
    @State private var player: AVPlayer?
    @State private var playerObservation: NSKeyValueObservation?
    @State private var isVideoLoading = true

    // Stream info
    @State private var isLive: Bool = false
    @State private var isPublic: Bool = true
    @State private var viewerCount: Int = 0
    @State private var viewerRefreshTimer: Timer?

    // Chat
    @StateObject private var chatManager: StreamChatManager
    @State private var inputText: String = ""
    @State private var showAutocomplete = false
    @State private var autocompleteItems: [SlashCommand] = []
    @State private var selectedAutocompleteIndex = -1
    @FocusState private var inputFocused: Bool
    @State private var showViewersList = false

    // Fullscreen / layout
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isFullscreen = false
    @State private var showFullscreenControls = true
    @State private var controlsFadeTimer: Timer?
    @State private var showChatDrawer = false
    @State private var chatDrawerOffset: CGFloat = 0

    private var effectiveFullscreen: Bool { isFullscreen || verticalSizeClass == .compact }

    // Slash commands (server-driven)
    @State private var availableCommands: [SlashCommand] = SlashCommand.localFallback

    // Auth check
    private var isAuthenticated: Bool { !token.isEmpty }

    init(serverURL: URL, streamName: String, token: String,
         initialStream: DFStream? = nil, password: String? = nil) {
        self.serverURL = serverURL
        self.streamName = streamName
        self.token = token
        self.initialStream = initialStream
        self.password = password
        _chatManager = StateObject(wrappedValue: StreamChatManager(
            serverURL: serverURL, token: token,
            streamName: streamName, isOwner: initialStream?.isOwner ?? false,
            title: initialStream?.title ?? "",
            description: initialStream?.description ?? ""
        ))
    }

    var body: some View {
        Group {
            if effectiveFullscreen {
                fullscreenLayout
            } else {
                portraitLayout
            }
        }
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
        .sheet(isPresented: $showViewersList) { viewersSheet }
        .onChange(of: verticalSizeClass) { _, _ in
            // When rotating back to portrait, clear manual fullscreen only if
            // the user hadn't explicitly set it — landscape auto-fullscreen handles itself.
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // Video with fullscreen button overlay
            ZStack(alignment: .bottomTrailing) {
                videoPlayerContent
                    .frame(height: 220)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isFullscreen = true }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(10)
            }

            streamInfoBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

            Divider()

            if chatManager.liveChat {
                chatPanel
            } else {
                chatDisabledView
            }
        }
        .navigationTitle(chatManager.streamTitle.isEmpty ? streamName : chatManager.streamTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Fullscreen Layout

    private var fullscreenLayout: some View {
        GeometryReader { geo in
            let hInset = max(geo.safeAreaInsets.leading, geo.safeAreaInsets.trailing, 16)
            ZStack(alignment: .bottom) {
                // Video fills entire screen
                videoPlayerContent
                    .ignoresSafeArea()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }

                // Chat drawer (slides up from bottom)
                if showChatDrawer {
                    chatDrawer(in: geo, hInset: hInset)
                }

                // Fading top bar — title / badge / viewer count / exit
                fullscreenTopBar(in: geo, hInset: hInset)
                    .opacity(showFullscreenControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: showFullscreenControls)
                    .frame(maxHeight: .infinity, alignment: .top)

                // Always-visible bottom bar — chat toggle only
                fullscreenBottomBar(in: geo, hInset: hInset)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func chatDrawer(in geo: GeometryProxy, hInset: CGFloat) -> some View {
        let drawerHeight = min(geo.size.height * 0.55, 420.0)
        return VStack(spacing: 0) {
            Capsule()
                .fill(Color(white: 0.6, opacity: 0.8))
                .frame(width: 36, height: 4)
                .padding(.vertical, 8)

            if chatManager.liveChat {
                chatPanel
            } else {
                chatDisabledView
            }
        }
        .frame(height: drawerHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, hInset)
        .offset(y: chatDrawerOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    chatDrawerOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation(.easeOut(duration: 0.25)) { showChatDrawer = false }
                    }
                    withAnimation(.spring()) { chatDrawerOffset = 0 }
                }
        )
        .transition(.move(edge: .bottom))
    }

    private func fullscreenTopBar(in geo: GeometryProxy, hInset: CGFloat) -> some View {
        HStack {
            Text(chatManager.streamTitle.isEmpty ? streamName : chatManager.streamTitle)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(radius: 2)
            Spacer()
            liveBadge
            Button {
                showViewersList = true
            } label: {
                Label("\(viewerCount)", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if verticalSizeClass != .compact {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isFullscreen = false }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, max(geo.safeAreaInsets.leading, 16))
        .padding(.trailing, max(geo.safeAreaInsets.trailing, 16))
        .padding(.top, geo.safeAreaInsets.top + 8)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func fullscreenBottomBar(in geo: GeometryProxy, hInset: CGFloat) -> some View {
        HStack {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    showChatDrawer.toggle()
                    chatDrawerOffset = 0
                }
                resetControlsTimer()
            } label: {
                Image(systemName: showChatDrawer ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.leading, max(geo.safeAreaInsets.leading, 16))
        .padding(.trailing, max(geo.safeAreaInsets.trailing, 16))
        .padding(.bottom, max(geo.safeAreaInsets.bottom, 12))
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
            .opacity(showChatDrawer ? 0 : 1)
        )
    }

    // MARK: - Shared Video Content

    private var videoPlayerContent: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if isVideoLoading {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Stream offline")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Controls Auto-Hide

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showFullscreenControls.toggle()
        }
        if showFullscreenControls { resetControlsTimer() }
    }

    private func resetControlsTimer() {
        controlsFadeTimer?.invalidate()
        controlsFadeTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.5)) { showFullscreenControls = false }
        }
    }

    // MARK: - Chat Disabled Placeholder

    private var chatDisabledView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Live chat is disabled")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Stream Info Bar

    private var streamInfoBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chatManager.streamTitle.isEmpty ? streamName : chatManager.streamTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if !chatManager.streamDescription.isEmpty {
                    Text(chatManager.streamDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                liveBadge
                Button {
                    showViewersList = true
                } label: {
                    Label("\(viewerCount)", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var liveBadge: some View {
        Group {
            if isLive {
                Text("LIVE")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text("OFFLINE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(UIColor.tertiarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chatManager.messages) { msg in
                            ChatMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: chatManager.messages.count) { _, _ in
                    if let last = chatManager.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Banned state
            if chatManager.isBanned {
                HStack {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.red)
                    Text("You have been banned from this chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            } else if chatManager.isManuallyDisconnected {
                HStack {
                    Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                    Text("You left the chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Rejoin") { chatManager.rejoinChat() }
                        .font(.caption.bold())
                }
                .padding(10)
            } else if !isAuthenticated && !chatManager.anonymousChat {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                    Text("Sign in to participate in chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                // Autocomplete
                if showAutocomplete && !autocompleteItems.isEmpty {
                    autocompleteView
                }

                // Input bar
                chatInputBar
            }
        }
    }

    // MARK: - Autocomplete

    private var autocompleteView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(autocompleteItems.enumerated()), id: \.element.id) { idx, cmd in
                Button {
                    applyAutocomplete(cmd)
                } label: {
                    HStack(spacing: 6) {
                        Text(cmd.command)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(.primary)
                        if !cmd.args.isEmpty {
                            Text(cmd.args)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(cmd.description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        idx == selectedAutocompleteIndex
                            ? Color(UIColor.tertiarySystemBackground)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Chat Input Bar

    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .focused($inputFocused)
                .onChange(of: inputText) { _, val in updateAutocomplete(val) }
                .onSubmit { submitMessage() }

            Button {
                submitMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Viewers Sheet

    private var viewersSheet: some View {
        NavigationStack {
            List(chatManager.viewers) { viewer in
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: viewer.avatarUrl)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(UIColor.secondarySystemBackground)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewer.displayName).font(.subheadline)
                        if !viewer.username.isEmpty && viewer.username != viewer.displayName {
                            Text("@\(viewer.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Viewers (\(chatManager.viewers.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showViewersList = false }
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func onAppear() {
        if let s = initialStream {
            isLive = s.isLive
            isPublic = s.isPublic
        }

        setupHLSPlayer()
        chatManager.connect()
        startViewerCountPolling()
        resetControlsTimer()
        Task { await fetchCommands() }
    }

    private func onDisappear() {
        player?.pause()
        player = nil
        playerObservation?.invalidate()
        playerObservation = nil
        chatManager.disconnect()
        viewerRefreshTimer?.invalidate()
        viewerRefreshTimer = nil
        controlsFadeTimer?.invalidate()
        controlsFadeTimer = nil
    }

    // MARK: - HLS Setup

    private func setupHLSPlayer() {
        let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var urlString = "\(base)/hls/\(streamName).m3u8"
        if let pw = password, !pw.isEmpty,
           let encoded = pw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "?password=\(encoded)"
        }
        guard let hlsURL = URL(string: urlString) else { return }
        isVideoLoading = true
        let item = AVPlayerItem(url: hlsURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        self.player = newPlayer
        newPlayer.play()

        playerObservation = item.observe(\.status, options: [.new]) { observedItem, _ in
            DispatchQueue.main.async { self.isVideoLoading = observedItem.status == .unknown }
        }
    }

    // MARK: - Viewer Count Polling

    private func startViewerCountPolling() {
        Task { await fetchViewerCount() }
        viewerRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { await fetchViewerCount() }
        }
    }

    private func fetchViewerCount() async {
        let api = DFAPI(url: serverURL, token: token)
        if let count = await api.getStreamViewerCount(name: streamName) {
            await MainActor.run { viewerCount = count }
        }
    }

    // MARK: - Command Fetching

    private func fetchCommands() async {
        let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/stream/commands/\(streamName)/") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(StreamCommandsResponse.self, from: data) else {
            return
        }
        await MainActor.run {
            availableCommands = response.commands
            // Sync chat settings onto the manager (authoritative from server)
            chatManager.liveChat = response.liveChat
            chatManager.anonymousChat = response.anonymousChat
            // Populate stream info when we didn't have initialStream (e.g. deep link)
            if initialStream == nil {
                if let t = response.title, !t.isEmpty { chatManager.streamTitle = t }
                if let d = response.description { chatManager.streamDescription = d }
                if let live = response.isLive { isLive = live }
                if let pub = response.isPublic { isPublic = pub }
            }
        }
    }

    // MARK: - Message Submission

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        hideAutocomplete()

        if text.hasPrefix("/") {
            executeCommand(text)
        } else {
            chatManager.sendMessage(text)
        }
    }

    // MARK: - Slash Commands

    private func executeCommand(_ input: String) {
        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : ""

        // Verify the command is in the server-granted list (guards owner-only commands)
        let granted = availableCommands.map { $0.command }
        // /join and /leave are always allowed locally
        let isLocal = cmd == "/join" || cmd == "/leave"
        guard isLocal || granted.contains(cmd) else {
            chatManager.messages.append(.system("Command not available: \(cmd)"))
            return
        }

        switch cmd {
        case "/set-name":
            guard !arg.isEmpty else {
                chatManager.messages.append(.system("Usage: /set-name <name>"))
                return
            }
            chatManager.setName(arg)

        case "/leave":
            chatManager.leaveChat()

        case "/join":
            chatManager.rejoinChat()

        case "/title":
            guard !arg.isEmpty else {
                chatManager.messages.append(.system("Usage: /title <title>"))
                return
            }
            chatManager.setTitle(arg)

        case "/description":
            guard !arg.isEmpty else {
                chatManager.messages.append(.system("Usage: /description <description>"))
                return
            }
            chatManager.setDescription(arg)

        case "/ban":
            guard !arg.isEmpty else {
                chatManager.messages.append(.system("Usage: /ban <display_name>"))
                return
            }
            chatManager.banUser(arg)

        case "/ban-message-cleanup":
            guard !arg.isEmpty else {
                chatManager.messages.append(.system("Usage: /ban-message-cleanup <display_name>"))
                return
            }
            chatManager.banMessageCleanup(arg)

        default:
            chatManager.messages.append(.system("Unknown command: \(cmd). Type / for available commands."))
        }
    }

    // MARK: - Autocomplete

    private func updateAutocomplete(_ text: String) {
        // Only match when still typing the command word (no space yet means no arg being entered)
        guard text.hasPrefix("/"), !text.contains(" ") else { hideAutocomplete(); return }
        let typed = text.lowercased()
        let matches = availableCommands.filter { $0.command.hasPrefix(typed) }
        if matches.isEmpty {
            hideAutocomplete()
        } else {
            autocompleteItems = matches
            showAutocomplete = true
            selectedAutocompleteIndex = -1
        }
    }

    private func hideAutocomplete() {
        showAutocomplete = false
        autocompleteItems = []
        selectedAutocompleteIndex = -1
    }

    private func applyAutocomplete(_ cmd: SlashCommand) {
        hideAutocomplete()
        if cmd.hasArgs {
            // Fill the command and let the user type the argument
            inputText = cmd.command + " "
            inputFocused = true
        } else {
            // No args — execute immediately without going through the text field
            inputText = ""
            executeCommand(cmd.command)
        }
    }
}

// MARK: - ChatMessageRow

struct ChatMessageRow: View {
    let message: DisplayChatMessage

    var body: some View {
        if message.isSystem {
            Text(message.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 8) {
                if !message.avatarURL.isEmpty, let url = URL(string: message.avatarURL) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(UIColor.tertiarySystemBackground))
                    }
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(nameColor(for: message.username))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text(message.displayName.prefix(1).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }

                (Text(message.displayName).bold()
                    .foregroundStyle(nameColor(for: message.username))
                 + Text("  ") + Text(message.message))
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
        }
    }

    private func nameColor(for username: String) -> Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .cyan, .indigo, .mint]
        var hash = 0
        for c in username.unicodeScalars {
            hash = (hash &* 31) &+ Int(c.value)
        }
        return colors[abs(hash) % colors.count]
    }
}
