//
//  StreamBroadcastView.swift
//  Django Files
//
//  Live camera broadcast for stream owners via RTMP.
//
//  Requires two products from HaishinKit.swift added to the Django Files target:
//    • HaishinKit       — MediaMixer, MTHKView, codec settings
//    • RTMPHaishinKit   — RTMPConnection, RTMPStream
//  Package URL: https://github.com/shogo4405/HaishinKit.swift
//
//  RTMP ingest URL:  rtmp://{host}:{port}/live?token={auth_token}
//  Stream key:       {streamName}
//
//  The backend (nginx-rtmp) authenticates via on_publish → /api/stream/auth/
//  which reads the token from the tcurl query parameter.
//

import SwiftUI
import AVFoundation
import VideoToolbox
import ReplayKit
import HaishinKit
import RTMPHaishinKit

// MARK: - Camera Preview (Metal-backed)

private struct CameraPreviewView: UIViewRepresentable {
    let hkView: MTHKView
    let deviceOrientation: UIDeviceOrientation

    func makeUIView(context: Context) -> MTHKView { hkView }

    func updateUIView(_ uiView: MTHKView, context: Context) {
        DispatchQueue.main.async { applyTransform(to: uiView) }
    }

    private func applyTransform(to view: MTHKView) {
        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        let fillScale = max(w, h) / min(w, h)

        let t: CGAffineTransform
        switch deviceOrientation {
        case .landscapeLeft:
            t = CGAffineTransform(rotationAngle: .pi / 2).scaledBy(x: fillScale, y: fillScale)
        case .landscapeRight:
            t = CGAffineTransform(rotationAngle: -.pi / 2).scaledBy(x: fillScale, y: fillScale)
        case .portraitUpsideDown:
            t = CGAffineTransform(rotationAngle: .pi)
        default:
            t = .identity
        }
        UIView.animate(withDuration: 0.15, animations: {
            view.alpha = 0
        }) { _ in
            view.transform = t
            UIView.animate(withDuration: 0.15) { view.alpha = 1 }
        }
    }
}

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case screen = "Screen Share"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .screen: return "rectangle.on.rectangle"
        }
    }
}

// MARK: - Stream Resolution

enum StreamResolution: String, CaseIterable, Identifiable {
    case p480  = "480p"
    case p720  = "720p"
    case p1080 = "1080p"
    case uhd4k = "4K"

    var id: String { rawValue }

    var bitRate: Int {
        switch self {
        case .p480:  return 1_500_000
        case .p720:  return 2_000_000
        case .p1080: return 4_000_000
        case .uhd4k: return 12_000_000
        }
    }

    private var landscapeSize: CGSize {
        switch self {
        case .p480:  return CGSize(width: 854,  height: 480)
        case .p720:  return CGSize(width: 1280, height: 720)
        case .p1080: return CGSize(width: 1920, height: 1080)
        case .uhd4k: return CGSize(width: 3840, height: 2160)
        }
    }

    /// The AVCaptureSession preset required to capture frames at this resolution.
    /// The session preset gates the camera's output size; if it stays at the default
    /// .hd1280x720 the codec can't produce anything above 720p regardless of settings.
    var capturePreset: AVCaptureSession.Preset {
        switch self {
        case .p480:  return .vga640x480
        case .p720:  return .hd1280x720
        case .p1080: return .hd1920x1080
        case .uhd4k: return .hd4K3840x2160
        }
    }

    func videoSize(for orientation: UIDeviceOrientation) -> CGSize {
        let ls = landscapeSize
        switch orientation {
        case .landscapeLeft, .landscapeRight: return ls
        default: return CGSize(width: ls.height, height: ls.width)
        }
    }
}

// MARK: - Broadcaster ViewModel

@MainActor
final class RTMPBroadcaster: ObservableObject {

    enum BroadcastState {
        case idle, connecting, live, error(String)

        var isLive: Bool {
            if case .live = self { return true }
            return false
        }
        var isConnecting: Bool {
            if case .connecting = self { return true }
            return false
        }
        var errorMessage: String? {
            if case .error(let msg) = self { return msg }
            return nil
        }
    }

    @Published var broadcastState: BroadcastState = .idle
    @Published var isMuted = false
    @Published var resolution: StreamResolution = .p720
    // Set at init time so the view renders correctly before async setup runs.
    @Published private(set) var captureMode: CaptureMode
    @Published private(set) var isSwitchingMode = false

    private var isScreenCapturing = false

    // Camera mode uses the default .single session (AVCaptureSession for camera/mic).
    // Screen mode uses .manual (no AVCaptureSession — HaishinKit's ReplayKit mode):
    // frames are fed directly via mixer.append() from RPScreenRecorder.
    private var mixer: MediaMixer
    private let connection = RTMPConnection()
    private(set) var stream: RTMPStream

    // Metal preview view — camera mode only; irrelevant in screen mode.
    let previewView: MTHKView = {
        let v = MTHKView(frame: .zero)
        v.videoGravity = .resizeAspectFill
        return v
    }()

    init(captureMode: CaptureMode = .camera) {
        self.captureMode = captureMode
        self.mixer = captureMode == .camera
            ? MediaMixer()
            : MediaMixer(captureSessionMode: .manual)
        stream = RTMPStream(connection: connection)
    }

    // MARK: - Setup

    func setup(useFrontCamera: Bool, deviceOrientation: UIDeviceOrientation) async {
        configureAudioSession()
        try? await stream.setVideoSettings(videoCodecSettings(for: resolution, orientation: deviceOrientation))
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
        await mixer.addOutput(stream)

        switch captureMode {
        case .camera:
            // Set the capture session preset BEFORE starting so the camera
            // actually provides frames at the target resolution.
            await mixer.setSessionPreset(resolution.capturePreset)
            await mixer.addOutput(previewView)
            await mixer.startRunning()
            await attachCamera(useFrontCamera: useFrontCamera)
            await attachAudioDevice()
            await mixer.setVideoOrientation(avOrientation(from: deviceOrientation))

        case .screen:
            // .manual mode: no AVCaptureSession. RPScreenRecorder feeds both
            // video and mic audio into the mixer via append().
            await mixer.startRunning()
            startScreenCapture()
        }
    }

    // MARK: - Device Attachment

    private func attachCamera(useFrontCamera: Bool) async {
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        do {
            try await mixer.attachVideo(device, track: 0)
        } catch {
            print("StreamBroadcast attachVideo error: \(error)")
        }
    }

    private func attachAudioDevice() async {
        let device = AVCaptureDevice.default(for: .audio)
        do {
            try await mixer.attachAudio(device, track: 0)
        } catch {
            print("StreamBroadcast attachAudio error: \(error)")
        }
    }

    // MARK: - Camera flip / mute

    func flipCamera(useFrontCamera: Bool) {
        Task { await attachCamera(useFrontCamera: useFrontCamera) }
    }

    func toggleMute() {
        isMuted.toggle()
        Task {
            // isMuted on AudioMixerSettings silences the output without detaching
            // the audio device, keeping the RTMP audio track alive and the
            // stream intact. attachAudio(nil) would drop the track mid-stream.
            var settings = await mixer.audioMixerSettings
            settings.isMuted = isMuted
            await mixer.setAudioMixerSettings(settings)
        }
    }

    // MARK: - Go Live / Stop

    func startStream(rtmpURL: String, streamName: String) {
        guard case .idle = broadcastState else { return }
        broadcastState = .connecting
        Task {
            do {
                _ = try await connection.connect(rtmpURL)
                _ = try await stream.publish(streamName)
                broadcastState = .live
            } catch {
                broadcastState = .error(error.localizedDescription)
            }
        }
    }

    /// Ends the RTMP stream; keeps preview/capture running so the user can go live again.
    func stopStream() {
        Task {
            _ = try? await stream.close()
            try? await connection.close()
            broadcastState = .idle
        }
    }

    /// Full teardown — releases all hardware. Call on view dismiss.
    func teardown() async {
        stopScreenCapture()
        _ = try? await stream.close()
        try? await connection.close()
        if captureMode == .camera {
            try? await mixer.attachVideo(nil as AVCaptureDevice?, track: 0)
            try? await mixer.attachAudio(nil as AVCaptureDevice?, track: 0)
        }
        await mixer.stopRunning()
        broadcastState = .idle
    }

    func clearError() {
        broadcastState = .idle
    }

    // MARK: - Audio Session

    // Configures AVAudioSession for streaming and background audio continuation.
    // UIBackgroundModes:audio in Info.plist keeps the process alive when minimised.
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("RTMPBroadcaster: audio session error: \(error)")
        }
    }

    // MARK: - Screen Capture

    private func startScreenCapture() {
        let recorder = RPScreenRecorder.shared()

        // isAvailable is false on the iOS Simulator — must test on a real device.
        guard recorder.isAvailable else {
            broadcastState = .error("Screen recording unavailable. This feature requires a physical device.")
            return
        }

        guard !recorder.isRecording else {
            isScreenCapturing = true
            return
        }

        // Mic audio is provided by RPScreenRecorder in .manual mode (no AVCaptureSession).
        recorder.isMicrophoneEnabled = true

        // Capture mixer reference on @MainActor before entering the non-isolated handler.
        // Per-frame we hop back to the MediaMixer actor via Task { await }.
        let mixerRef = mixer
        recorder.startCapture(handler: { buffer, type, error in
            guard error == nil else { return }
            switch type {
            case .video, .audioMic:
                Task { await mixerRef.append(buffer, track: 0) }
            default:
                break
            }
        }, completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.broadcastState = .error("Screen capture failed: \(error.localizedDescription)")
                } else {
                    self?.isScreenCapturing = true
                }
            }
        })
    }

    private func stopScreenCapture() {
        guard isScreenCapturing else { return }
        RPScreenRecorder.shared().stopCapture { _ in }
        isScreenCapturing = false
    }

    func updateOrientation(deviceOrientation: UIDeviceOrientation) {
        guard captureMode == .camera else { return }
        Task {
            await mixer.setVideoOrientation(avOrientation(from: deviceOrientation))
            try? await stream.setVideoSettings(videoCodecSettings(for: resolution, orientation: deviceOrientation))
        }
    }

    func switchCaptureMode(to newMode: CaptureMode, useFrontCamera: Bool, deviceOrientation: UIDeviceOrientation) async {
        guard newMode != captureMode, !isSwitchingMode else { return }
        isSwitchingMode = true
        defer { isSwitchingMode = false }

        // Tear down the current source cleanly.
        stopScreenCapture()
        if captureMode == .camera {
            try? await mixer.attachVideo(nil as AVCaptureDevice?, track: 0)
            try? await mixer.attachAudio(nil as AVCaptureDevice?, track: 0)
            await mixer.removeOutput(previewView)
        }
        // Detach stream from old mixer so it doesn't receive stale frames.
        await mixer.removeOutput(stream)
        await mixer.stopRunning()

        // Swap mixer — the RTMPStream and RTMPConnection are reused so any
        // in-progress RTMP publish continues without a reconnect (viewers see
        // a brief freeze during the source transition, then new frames arrive).
        captureMode = newMode
        mixer = newMode == .camera
            ? MediaMixer()
            : MediaMixer(captureSessionMode: .manual)

        await mixer.addOutput(stream)

        switch newMode {
        case .camera:
            await mixer.setSessionPreset(resolution.capturePreset)
            await mixer.addOutput(previewView)
            await mixer.startRunning()
            await attachCamera(useFrontCamera: useFrontCamera)
            await attachAudioDevice()
            await mixer.setVideoOrientation(avOrientation(from: deviceOrientation))
        case .screen:
            await mixer.startRunning()
            startScreenCapture()
        }
    }

    func setResolution(_ newResolution: StreamResolution, orientation: UIDeviceOrientation) {
        resolution = newResolution
        Task {
            if captureMode == .camera {
                // Update the capture session preset so the camera targets the new
                // resolution. The camera transitions asynchronously, so initial frames
                // arriving in the new VTCompressionSession may still be at the old
                // size — scalingMode: .normal in videoCodecSettings handles this by
                // upscaling them rather than cropping, keeping the encoded output
                // valid throughout the transition.
                await mixer.setSessionPreset(newResolution.capturePreset)
            }
            try? await stream.setVideoSettings(videoCodecSettings(for: newResolution, orientation: orientation))
        }
    }

    // High AutoLevel lets VideoToolbox pick the correct H.264 level for the
    // resolution (Baseline 3.1 caps out at 720p and breaks higher resolutions).
    // allowFrameReordering must be false — B-frames are incompatible with RTMP.
    // scalingMode .normal is required: the default .trim only CROPS (no actual
    // resize), so a 720p camera frame arriving in a 1080p VT session — which
    // happens briefly during the camera format transition — produces a malformed
    // bitstream. .normal tells VT to properly scale any size-mismatched buffer
    // to the output dimensions, keeping the stream valid during the transition.
    private func videoCodecSettings(for res: StreamResolution, orientation: UIDeviceOrientation) -> VideoCodecSettings {
        VideoCodecSettings(
            videoSize: res.videoSize(for: orientation),
            bitRate: res.bitRate,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            scalingMode: .normal,
            allowFrameReordering: false
        )
    }

    // AVCaptureVideoOrientation is deprecated in iOS 17 in favour of
    // AVCaptureDeviceRotationCoordinator, but HaishinKit's setVideoOrientation
    // still requires it. Isolate the deprecated usage here until HaishinKit
    // exposes a replacement API.
    @available(iOS, deprecated: 17.0)
    private func avOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft:      return .landscapeRight
        case .landscapeRight:     return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default:                  return .portrait
        }
    }
}

// MARK: - StreamBroadcastView

struct StreamBroadcastView: View {
    let serverURL: URL
    let streamName: String
    let token: String
    let streamTitle: String
    let ownerUsername: String
    let initialCaptureMode: CaptureMode

    @StateObject private var broadcaster: RTMPBroadcaster
    @StateObject private var chatManager: StreamChatManager
    @State private var useFrontCamera = false
    @State private var showEndConfirmation = false
    @State private var permissionDenied = false
    @State private var didSetup = false
    @State private var ingestInfo: DFStreamIngestInfo?
    @State private var showIngestInfo = false
    @State private var showResolutionPicker = false
    @State private var showChatDrawer = false
    @State private var chatDrawerOffset: CGFloat = 0
    @State private var deviceOrientation: UIDeviceOrientation = {
        let o = UIDevice.current.orientation
        return o.isValidInterfaceOrientation ? o : .portrait
    }()

    @Environment(\.dismiss) private var dismiss

    init(serverURL: URL, streamName: String, token: String, streamTitle: String,
         ownerUsername: String = "", initialCaptureMode: CaptureMode = .camera) {
        self.serverURL = serverURL
        self.streamName = streamName
        self.token = token
        self.streamTitle = streamTitle
        self.ownerUsername = ownerUsername
        self.initialCaptureMode = initialCaptureMode
        // Initialize broadcaster with the selected mode so captureMode is correct
        // from the first render — before async setup() runs.
        _broadcaster = StateObject(wrappedValue: RTMPBroadcaster(captureMode: initialCaptureMode))
        _chatManager = StateObject(wrappedValue: StreamChatManager(
            serverURL: serverURL,
            token: token,
            streamName: streamName,
            isOwner: true,
            ownerUsername: ownerUsername,
            title: streamTitle
        ))
    }

    // MARK: - Rotation helpers

    /// Each control counter-rotates to stay upright while the layout stays fixed.
    private var controlRotation: Angle {
        switch deviceOrientation {
        case .landscapeLeft:      return .degrees(90)
        case .landscapeRight:     return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default:                  return .degrees(0)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !permissionDenied {
                if broadcaster.captureMode == .camera {
                    CameraPreviewView(hkView: broadcaster.previewView, deviceOrientation: deviceOrientation)
                        .ignoresSafeArea()
                } else {
                    screenShareBackground
                        .ignoresSafeArea()
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .ignoresSafeArea(edges: .bottom)

            if permissionDenied {
                permissionDeniedOverlay
            }

            // Chat drawer — slides up from the bottom
            if showChatDrawer {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 0) {
                            Capsule()
                                .fill(Color(white: 0.6, opacity: 0.8))
                                .frame(width: 36, height: 4)
                                .padding(.vertical, 8)

                            if chatManager.liveChat {
                                chatPanel
                            } else {
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
                        }
                        // Cap height so the rotated panel (visual width = layout height)
                        // doesn't overflow the screen when the device is in landscape.
                        .frame(height: min(geo.size.height * 0.55, geo.size.width * 0.9, 420))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .rotationEffect(controlRotation)
                        .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                        .padding(.horizontal, 16)
                        // geo.safeAreaInsets.bottom is 0 normally (container inset is ignored
                        // via .ignoresSafeArea(.container) below) and equals keyboard height
                        // when the software keyboard is shown — so this naturally avoids the
                        // keyboard without firing for hardware keyboards or the simulator.
                        .padding(.bottom, max(geo.safeAreaInsets.bottom + 8, 44))
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
                    }
                }
                // .container ignores home-indicator/status-bar insets so the drawer
                // fills edge-to-edge, but keeps the .keyboard inset active so
                // geo.safeAreaInsets.bottom reflects the real software keyboard height.
                .ignoresSafeArea(.container)
                .transition(.move(edge: .bottom))
            }

            // Resolution picker — custom overlay so it counter-rotates with the
            // other controls. A system Menu popup is always portrait-oriented and
            // appears at the wrong position/angle when the device is in landscape.
            if showResolutionPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { showResolutionPicker = false }
                    }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(StreamResolution.allCases) { res in
                        resolutionPickerRow(res)
                    }
                }
                .frame(width: 130)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 8)
                .rotationEffect(controlRotation)
                .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 64)
                .padding(.trailing, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }

            // Ingest info — custom card overlay so it counter-rotates correctly.
            // A system .sheet() is always presented in the interface orientation
            // (portrait-locked) and cannot be rotated, making it appear sideways
            // in landscape. Pre-rotation the card is portrait-shaped (340×380);
            // after the 90° counter-rotation it looks landscape-shaped (380×340).
            if showIngestInfo {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showIngestInfo = false } }

                ingestInfoSheet
                    .frame(width: 340, height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .rotationEffect(controlRotation)
                    .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await onAppear() }
        .onDisappear {
            // Restore orientation support before leaving
            AppDelegate.orientationLock = nil
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .requestGeometryUpdate(.iOS(interfaceOrientations: .all))
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            Task { await broadcaster.teardown() }
            chatManager.disconnect()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        ) { _ in
            let o = UIDevice.current.orientation
            if o.isValidInterfaceOrientation {
                deviceOrientation = o
                broadcaster.updateOrientation(deviceOrientation: o)
            }
        }
        .confirmationDialog(
            "End Stream?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Stream", role: .destructive) {
                broadcaster.stopStream()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect all viewers.")
        }
        .alert(
            "Stream Error",
            isPresented: Binding(
                get: { broadcaster.broadcastState.errorMessage != nil },
                set: { if !$0 { broadcaster.clearError() } }
            )
        ) {
            Button("OK") { broadcaster.clearError() }
        } message: {
            Text(broadcaster.broadcastState.errorMessage ?? "")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                if broadcaster.broadcastState.isLive {
                    showEndConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
                    .rotationEffect(controlRotation)
                    .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
            }
            .buttonStyle(.plain)

            Spacer()
            statusBadge
            Spacer()

            HStack(spacing: 10) {
                Button { showIngestInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                        .rotationEffect(controlRotation)
                        .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showResolutionPicker = true }
                } label: {
                    Text(broadcaster.resolution.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .rotationEffect(controlRotation)
                        .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                }

                // Source switcher — tap to change between camera and screen share.
                Menu {
                    ForEach(CaptureMode.allCases) { mode in
                        Button {
                            Task {
                                await broadcaster.switchCaptureMode(
                                    to: mode,
                                    useFrontCamera: useFrontCamera,
                                    deviceOrientation: deviceOrientation
                                )
                            }
                        } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                        .disabled(mode == broadcaster.captureMode)
                    }
                } label: {
                    Image(systemName: broadcaster.isSwitchingMode
                          ? "arrow.triangle.2.circlepath"
                          : broadcaster.captureMode.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                        .rotationEffect(controlRotation)
                        .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                }
                .buttonStyle(.plain)
                .disabled(broadcaster.isSwitchingMode)

                if broadcaster.captureMode == .camera {
                    Button { flipCamera() } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.45), in: Circle())
                            .rotationEffect(controlRotation)
                            .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var statusBadge: some View {
        Group {
            if broadcaster.broadcastState.isLive {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red, in: Capsule())
            } else if broadcaster.broadcastState.isConnecting {
                Label("Connecting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange, in: Capsule())
            } else {
                Text(streamTitle.isEmpty ? streamName : streamTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .rotationEffect(controlRotation)
        .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(alignment: .center) {
            // Chat toggle
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    showChatDrawer.toggle()
                    chatDrawerOffset = 0
                }
            } label: {
                Image(systemName: showChatDrawer ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.45), in: Circle())
                    .rotationEffect(controlRotation)
                    .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
            }
            .buttonStyle(.plain)

            Spacer()

            recordButton

            Spacer()

            // Mute — always in the same spot
            Button { broadcaster.toggleMute() } label: {
                Image(systemName: broadcaster.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(broadcaster.isMuted ? .red : .white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.45), in: Circle())
                    .rotationEffect(controlRotation)
                    .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Standard record button: fixed white ring with a state-driven inner shape.
    /// The ring stays in place; only the inner icon counter-rotates to stay upright.
    private var recordButton: some View {
        Button {
            switch broadcaster.broadcastState {
            case .idle, .error: goLive()
            case .live:         showEndConfirmation = true
            case .connecting:   break
            }
        } label: {
            ZStack {
                // Outer ring — never rotates
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 72, height: 72)

                // Inner indicator — rotates to stay upright
                Group {
                    switch broadcaster.broadcastState {
                    case .idle, .error:
                        Circle()
                            .fill(.red)
                            .frame(width: 56, height: 56)
                    case .live:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    case .connecting:
                        ProgressView().tint(.white)
                    }
                }
                .rotationEffect(controlRotation)
                .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
            }
            .animation(.easeInOut(duration: 0.2), value: broadcaster.broadcastState.isLive)
        }
        .buttonStyle(.plain)
        .disabled(broadcaster.broadcastState.isConnecting || permissionDenied)
    }

    // MARK: - Chat Panel

    @State private var chatInputText: String = ""
    @FocusState private var chatInputFocused: Bool

    private var chatPanel: some View {
        VStack(spacing: 0) {
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

            HStack(spacing: 8) {
                TextField("Message…", text: $chatInputText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .focused($chatInputFocused)
                    .onSubmit { sendChatMessage() }

                Button { sendChatMessage() } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(chatInputText.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? Color.secondary : Color.accentColor)
                }
                .disabled(chatInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func sendChatMessage() {
        let text = chatInputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        chatInputText = ""
        chatManager.sendMessage(text)
    }

    // MARK: - Resolution Picker Row

    @ViewBuilder
    private func resolutionPickerRow(_ res: StreamResolution) -> some View {
        let isSelected = res == broadcaster.resolution
        let isLast = res == StreamResolution.allCases.last
        Button {
            broadcaster.setResolution(res, orientation: deviceOrientation)
            withAnimation(.easeOut(duration: 0.15)) { showResolutionPicker = false }
        } label: {
            HStack {
                Text(res.rawValue)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        if !isLast {
            Divider().padding(.leading, 16)
        }
    }

    // MARK: - Screen Share Background

    private var screenShareBackground: some View {
        Color.black
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.on.rectangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Screen Sharing")
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Your screen is broadcast to viewers.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .rotationEffect(controlRotation)
                .animation(.easeInOut(duration: 0.25), value: deviceOrientation)
            }
    }

    // MARK: - Ingest Info Sheet

    private var ingestInfoSheet: some View {
        NavigationStack {
            List {
                Section("RTMP Ingest URL") {
                    HStack {
                        Text(currentRTMPURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = currentRTMPURL
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("Stream Key") {
                    HStack {
                        Text(streamName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = streamName
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Text("Use these credentials with any RTMP-compatible encoder such as OBS Studio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stream Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { withAnimation { showIngestInfo = false } }
                }
            }
        }
    }

    // MARK: - Permission Denied Overlay

    private var permissionDeniedOverlay: some View {
        let isScreenMode = initialCaptureMode == .screen
        return VStack(spacing: 16) {
            Image(systemName: isScreenMode ? "mic.slash.fill" : "video.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(isScreenMode ? "Microphone Access Required" : "Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
            Text(isScreenMode
                 ? "Please allow microphone access in Settings to stream audio while sharing your screen."
                 : "Please allow camera and microphone access in Settings to go live.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Lifecycle

    private func onAppear() async {
        guard !didSetup else { return }
        didSetup = true

        // Capture physical orientation before forcing portrait — requestGeometryUpdate
        // causes UIDevice.current.orientation to settle on portrait, so reading it
        // afterwards gives the wrong value when the device is already in landscape.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let physicalOrientation = UIDevice.current.orientation

        // Lock interface to portrait so the layout never rotates;
        // individual controls rotate themselves to stay upright.
        AppDelegate.orientationLock = .portrait
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))

        if physicalOrientation.isValidInterfaceOrientation {
            deviceOrientation = physicalOrientation
        }

        async let ingestFetch = fetchIngestInfo()
        async let permissionsOK = checkAndRequestPermissions()

        ingestInfo = await ingestFetch

        guard await permissionsOK else {
            permissionDenied = true
            return
        }
        // Connect chat in parallel with broadcaster setup — they're independent
        async let broadcasterSetup: Void = broadcaster.setup(
            useFrontCamera: useFrontCamera,
            deviceOrientation: deviceOrientation
        )
        chatManager.connect()
        await broadcasterSetup
    }

    private func fetchIngestInfo() async -> DFStreamIngestInfo? {
        let api = DFAPI(url: serverURL, token: token)
        return await api.getStreamIngestInfo()
    }

    private func checkAndRequestPermissions() async -> Bool {
        let micGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:   micGranted = true
        case .notDetermined: micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:            micGranted = false
        }

        // Screen share mode only needs the microphone; RPScreenRecorder handles
        // its own screen-capture permission prompt inside startCapture().
        guard initialCaptureMode == .camera else { return micGranted }

        let cameraGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:   cameraGranted = true
        case .notDetermined: cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:            cameraGranted = false
        }

        return cameraGranted && micGranted
    }

    // MARK: - Actions

    private func flipCamera() {
        useFrontCamera.toggle()
        broadcaster.flipCamera(useFrontCamera: useFrontCamera)
    }

    private func goLive() {
        broadcaster.startStream(rtmpURL: currentRTMPURL, streamName: streamName)
    }

    private var currentRTMPURL: String {
        let host = ingestInfo?.rtmpHost ?? serverURL.host ?? serverURL.absoluteString
        let port = ingestInfo?.rtmpPort ?? 1935
        return "rtmp://\(host):\(port)/live?token=\(token)"
    }
}
