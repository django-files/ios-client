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
import HaishinKit
import RTMPHaishinKit

// MARK: - Camera Preview (Metal-backed)

private struct CameraPreviewView: UIViewRepresentable {
    let hkView: MTHKView
    func makeUIView(context: Context) -> MTHKView { hkView }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
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

    // HaishinKit objects — both are actors
    private let mixer = MediaMixer()
    private let connection = RTMPConnection()
    private(set) var stream: RTMPStream

    // Metal preview view — one instance, reused across layout rebuilds
    let previewView: MTHKView = {
        let v = MTHKView(frame: .zero)
        v.videoGravity = .resizeAspectFill
        return v
    }()

    init() {
        stream = RTMPStream(connection: connection)
    }

    // MARK: - Setup

    /// Call once after camera/mic permissions are confirmed.
    func setup(useFrontCamera: Bool) async {
        try? await stream.setVideoSettings(VideoCodecSettings(
            videoSize: CGSize(width: 1280, height: 720),
            bitRate: 2_000_000
        ))
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

        await mixer.addOutput(previewView)
        await mixer.addOutput(stream)
        await mixer.startRunning()

        await attachCamera(useFrontCamera: useFrontCamera)
        await attachAudioDevice()
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
            if isMuted {
                try? await mixer.attachAudio(nil, track: 0)
            } else {
                await attachAudioDevice()
            }
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

    /// Ends the RTMP stream but keeps the camera preview running.
    func stopStream() {
        Task {
            _ = try? await stream.close()
            try? await connection.close()
            broadcastState = .idle
        }
    }

    /// Full teardown — stops mixer and releases camera/mic. Call on view dismiss.
    func teardown() async {
        _ = try? await stream.close()
        try? await connection.close()
        try? await mixer.attachVideo(nil as AVCaptureDevice?, track: 0)
        try? await mixer.attachAudio(nil as AVCaptureDevice?, track: 0)
        await mixer.stopRunning()
        broadcastState = .idle
    }

    func clearError() {
        broadcastState = .idle
    }
}

// MARK: - StreamBroadcastView

struct StreamBroadcastView: View {
    let serverURL: URL
    let streamName: String
    let token: String
    let streamTitle: String
    let rtmpPort: Int

    @StateObject private var broadcaster = RTMPBroadcaster()
    @State private var useFrontCamera = true
    @State private var showEndConfirmation = false
    @State private var permissionDenied = false
    @State private var didSetup = false
    @State private var ingestInfo: DFStreamIngestInfo?
    @State private var showIngestInfo = false
    @State private var deviceOrientation: UIDeviceOrientation = {
        let o = UIDevice.current.orientation
        return o.isValidInterfaceOrientation ? o : .portrait
    }()

    @Environment(\.dismiss) private var dismiss

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
                CameraPreviewView(hkView: broadcaster.previewView)
                    .ignoresSafeArea()
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
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await onAppear() }
        .onDisappear {
            // Restore orientation support before leaving
            AppDelegate.orientationLock = nil
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            Task { await broadcaster.teardown() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        ) { _ in
            let o = UIDevice.current.orientation
            if o.isValidInterfaceOrientation {
                deviceOrientation = o
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
        .sheet(isPresented: $showIngestInfo) {
            ingestInfoSheet
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
            // Left placeholder mirrors mute button to keep record button centered
            Color.clear.frame(width: 52, height: 52)

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
                    Button("Done") { showIngestInfo = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Permission Denied Overlay

    private var permissionDeniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Please allow camera and microphone access in Settings to go live.")
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

        // Lock interface to portrait so the layout never rotates;
        // individual controls rotate themselves to stay upright.
        AppDelegate.orientationLock = .portrait
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        async let ingestFetch = fetchIngestInfo()
        async let permissionsOK = checkAndRequestPermissions()

        ingestInfo = await ingestFetch

        guard await permissionsOK else {
            permissionDenied = true
            return
        }
        await broadcaster.setup(useFrontCamera: useFrontCamera)
    }

    private func fetchIngestInfo() async -> DFStreamIngestInfo? {
        let api = DFAPI(url: serverURL, token: token)
        return await api.getStreamIngestInfo()
    }

    private func checkAndRequestPermissions() async -> Bool {
        let cameraGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:   cameraGranted = true
        case .notDetermined: cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:            cameraGranted = false
        }

        let micGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:   micGranted = true
        case .notDetermined: micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:            micGranted = false
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
        let port = ingestInfo?.rtmpPort ?? rtmpPort
        return "rtmp://\(host):\(port)/live?token=\(token)"
    }
}
