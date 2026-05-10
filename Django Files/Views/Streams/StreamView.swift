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
import UIKit

// MARK: - Audio Route Picker (AirPlay / speaker / headphones / Bluetooth)
//
// AVRoutePickerView must be in the live UIKit view hierarchy to present its
// system sheet. Embedding it inside a SwiftUI ToolbarItem doesn't work.
// Solution: on button tap, attach a 1×1 proxy view to the key window,
// trigger the picker's internal button, then remove it via the delegate.

private struct RoutePickerButton: View {
    enum BackgroundShape { case circle, roundedRect }

    var tint: Color = .primary
    var size: CGFloat = 16
    var padding: CGFloat = 10
    var backgroundShape: BackgroundShape = .circle

    var body: some View {
        Button(action: showRoutePicker) {
            Image(systemName: "airplayaudio")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .padding(padding)
                .background {
                    switch backgroundShape {
                    case .circle:
                        Circle().fill(.black.opacity(0.45))
                    case .roundedRect:
                        RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func showRoutePicker() {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else { return }
        RoutePickerWindow.present(in: windowScene)
    }
}

/// Hosts AVRoutePickerView in its own UIWindow at alert level so the system
/// sheet has a proper presentation context. Tears itself down via the delegate.
private final class RoutePickerWindow: UIWindow, AVRoutePickerViewDelegate {
    private static var retained: [RoutePickerWindow] = []

    private let routePicker = AVRoutePickerView()
    private var fallbackTimer: Timer?

    static func present(in scene: UIWindowScene) {
        let win = RoutePickerWindow(windowScene: scene)
        win.frame = scene.coordinateSpace.bounds
        win.backgroundColor = .clear
        win.windowLevel = .alert + 1

        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        win.rootViewController = vc
        win.isHidden = false

        let size: CGFloat = 44
        let bounds = scene.coordinateSpace.bounds
        win.routePicker.frame = CGRect(
            x: bounds.midX - size / 2,
            y: bounds.maxY - 120,
            width: size, height: size
        )
        win.routePicker.alpha = 0.011
        win.routePicker.delegate = win
        vc.view.addSubview(win.routePicker)

        win.triggerPicker()
        retained.append(win)
    }

    private func triggerPicker() {
        func firstButton(in view: UIView) -> UIButton? {
            if let b = view as? UIButton { return b }
            for sub in view.subviews { if let b = firstButton(in: sub) { return b } }
            return nil
        }
        firstButton(in: routePicker)?.sendActions(for: .touchUpInside)

        // If no sheet appears within 0.5 s (no available routes, or simulator),
        // tear the window down so it doesn't block touches.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.tearDown()
        }
    }

    private func tearDown() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        isHidden = true
        RoutePickerWindow.retained.removeAll { $0 === self }
    }

    override init(windowScene: UIWindowScene) {
        super.init(frame: .zero)
        self.windowScene = windowScene
    }

    required init?(coder: NSCoder) { fatalError() }

    // Cancel the fallback timer — a sheet is actually appearing.
    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        tearDown()
    }
}

// MARK: - AVPlayer wrapper without transport controls

private struct AVPlayerLayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

// MARK: - StreamView

struct StreamView: View {
    let serverURL: URL
    let streamName: String
    let token: String
    let initialStream: DFStream?
    var password: String? = nil

    // HLS player
    @State private var player: AVPlayer?
    @State private var playerObservation: NSKeyValueObservation?
    @State private var stalledObserver: NSObjectProtocol?
    @State private var isVideoLoading = true
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false

    // Stream info
    @State private var isLive: Bool = false
    @State private var isPublic: Bool = true
    @State private var viewerCount: Int = 0
    @State private var viewerRefreshTimer: Timer?
    @State private var streamStartedAt: Date?
    @State private var streamEndedAt: Date?

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
    @State private var isPlaying = true

    private var effectiveFullscreen: Bool { isFullscreen || verticalSizeClass == .compact }

    // Slash commands (server-driven)
    @State private var availableCommands: [SlashCommand] = SlashCommand.localFallback

    // Auth check
    private var isAuthenticated: Bool { !token.isEmpty }

    // Broadcast
    @State private var showBroadcast = false

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
            ownerUsername: initialStream?.userUsername ?? "",
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
        .onChange(of: chatManager.streamIsLive) { _, live in
            if let live { isLive = live }
        }
        .sheet(isPresented: $showViewersList) { viewersSheet }
        .fullScreenCover(isPresented: $showBroadcast) {
            StreamBroadcastView(
                serverURL: serverURL,
                streamName: streamName,
                token: token,
                streamTitle: chatManager.streamTitle,
                ownerUsername: initialStream?.userUsername ?? ""
            )
        }
        .onChange(of: verticalSizeClass) { _, _ in
            // When rotating back to portrait, clear manual fullscreen only if
            // the user hadn't explicitly set it — landscape auto-fullscreen handles itself.
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // Video with controls overlay
            ZStack {
                videoPlayerContent

                if player != nil {
                    // Play/pause — bottom leading
                    Button { togglePlayPause() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)

                }

                // Mute + Route + Fullscreen — bottom trailing
                HStack(spacing: 6) {
                    if player != nil {
                        Button { toggleMute() } label: {
                            Image(systemName: muteIcon())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)

                        RoutePickerButton(tint: .white, size: 14, padding: 8, backgroundShape: .circle)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isFullscreen = true }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)

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
        .toolbar {
            if initialStream?.isOwner == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showBroadcast = true
                    } label: {
                        Label("Go Live", systemImage: "video.badge.waveform.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(isLive ? .red : .accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Fullscreen Layout

    private var fullscreenLayout: some View {
        ZStack {
            // Black background fills behind safe areas
            Color.black.ignoresSafeArea()

            // Video fills entire screen (behind safe areas)
            videoPlayerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            // Controls overlay — constrained to safe area so no manual inset math needed
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Chat drawer
                    if showChatDrawer {
                        chatDrawer(height: min(geo.size.height * 0.55, 420))
                    }

                    VStack(spacing: 0) {
                        // Fading top bar
                        fullscreenTopBar
                            .opacity(showFullscreenControls ? 1 : 0)
                            .animation(.easeInOut(duration: 0.25), value: showFullscreenControls)

                        Spacer()

                        // Centered play/pause
                        if player != nil {
                            Button { togglePlayPause() } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(16)
                                    .background(.black.opacity(0.4), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(showFullscreenControls ? 1 : 0)
                            .animation(.easeInOut(duration: 0.25), value: showFullscreenControls)
                        }

                        Spacer()

                        // Always-visible bottom bar
                        fullscreenBottomBar
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func chatDrawer(height: CGFloat) -> some View {
        VStack(spacing: 0) {
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
        .frame(height: height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .offset(y: chatDrawerOffset)
        .gesture(
            DragGesture()
                .onChanged { value in chatDrawerOffset = max(0, value.translation.height) }
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation(.easeOut(duration: 0.25)) { showChatDrawer = false }
                    }
                    withAnimation(.spring()) { chatDrawerOffset = 0 }
                }
        )
        .transition(.move(edge: .bottom))
    }

    private var fullscreenTopBar: some View {
        HStack {
            Text(chatManager.streamTitle.isEmpty ? streamName : chatManager.streamTitle)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(radius: 2)
            Spacer()
            liveBadge
            Label("\(initialStream?.subscriberCount ?? 0)", systemImage: "bell")
                .font(.caption)
                .foregroundStyle(.white)
            Button { showViewersList = true } label: {
                Label("\(viewerCount)", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var fullscreenBottomBar: some View {
        HStack {
            // Chat toggle — always visible
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

            // Mute toggle
            Button { toggleMute() } label: {
                Image(systemName: muteIcon())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)

            RoutePickerButton(tint: .white, size: 15, padding: 10, backgroundShape: .circle)

            // Exit fullscreen — portrait only (landscape users rotate to exit)
            if verticalSizeClass != .compact {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isFullscreen = false }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                AVPlayerLayerView(player: player)
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

    private func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying { player?.play() } else { player?.pause() }
        // Show controls briefly so the user sees the state change
        if effectiveFullscreen {
            withAnimation(.easeInOut(duration: 0.2)) { showFullscreenControls = true }
            resetControlsTimer()
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        // If they unmute while slider is at 0, restore to full volume
        if !isMuted && volume < 0.01 { volume = 1.0; player?.volume = 1.0 }
    }

    private func muteIcon() -> String {
        if isMuted || volume < 0.01 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.fill" }
        if volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
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
            VStack(alignment: .center, spacing: 4) {
                liveBadge
                HStack(spacing: 8) {
                    Label("\(initialStream?.subscriberCount ?? 0)", systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            ChatMessageRow(message: msg, ownerUsername: chatManager.ownerUsername)
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
            List {
                // Stream timing
                if streamStartedAt != nil || streamEndedAt != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if let started = streamStartedAt {
                            if isLive {
                                Label {
                                    Text("Live for ") + Text(started, style: .relative)
                                } icon: {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else {
                                Label(
                                    "Started \(DateFormatter.localizedString(from: started, dateStyle: .none, timeStyle: .short))",
                                    systemImage: "play.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        if let ended = streamEndedAt {
                            Label(
                                "Ended \(DateFormatter.localizedString(from: ended, dateStyle: .none, timeStyle: .short))",
                                systemImage: "stop.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color(UIColor.secondarySystemBackground))
                }

                ForEach(chatManager.viewers) { viewer in
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
            streamStartedAt = s.startedAt
            streamEndedAt = s.endedAt
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
        if let obs = stalledObserver { NotificationCenter.default.removeObserver(obs) }
        stalledObserver = nil
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
        // Keep the default (true): AVPlayer buffers before playing and auto-recovers
        // brief network stalls by buffering more. Setting false causes a tight
        // play→pause→recover loop when the buffer is momentarily empty.
        newPlayer.volume = volume
        newPlayer.isMuted = isMuted
        self.player = newPlayer
        isPlaying = true
        newPlayer.play()

        // Drive the loading indicator via timeControlStatus.
        // With automaticallyWaitsToMinimizeStalling = true, brief network stalls
        // show up as .waitingToPlayAtSpecifiedRate (handled internally), not .paused.
        // .paused only fires when the stream truly ends or the player gives up.
        playerObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) { player, _ in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self.isVideoLoading = true
                case .playing:
                    self.isVideoLoading = false
                case .paused:
                    self.isVideoLoading = false
                @unknown default:
                    break
                }
            }
        }

        // Recover from explicit stall notifications (deeper than timeControlStatus).
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { _ in
            guard self.isPlaying else { return }
            self.recoverFromStall()
        }
    }

    /// Seeks to the live edge then resumes. Only called on explicit stall events,
    /// not on every .paused transition, to avoid a busy-loop during initial load.
    private func recoverFromStall() {
        guard let player, let item = player.currentItem,
              item.status != .failed else { return }
        if let range = item.seekableTimeRanges.last {
            let end = CMTimeRangeGetEnd(range.timeRangeValue)
            player.seek(to: end) { _ in player.play() }
        } else {
            player.play()
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
        let api = DFAPI(url: serverURL, token: token)
        guard let response = await api.getStreamCommands(name: streamName) else { return }
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
        let matches = availableCommands.filter { cmd in
            guard cmd.command.hasPrefix(typed) else { return false }
            // iOS has a dedicated Rejoin button — /join adds no value in autocomplete
            if cmd.command == "/join" { return false }
            // /leave only makes sense while joined
            if cmd.command == "/leave" && chatManager.isManuallyDisconnected { return false }
            return true
        }
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
    var ownerUsername: String = ""

    private var isStreamOwner: Bool {
        !ownerUsername.isEmpty && message.username == ownerUsername
    }

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

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if isStreamOwner {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.yellow)
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
