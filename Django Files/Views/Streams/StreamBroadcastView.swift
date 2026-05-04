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
//  RTMP ingest URL:  rtmp://{host}:1935/live?token={auth_token}
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
        // Configure codec settings on the stream (RTMPStream is an actor → await)
        try? await stream.setVideoSettings(VideoCodecSettings(
            videoSize: CGSize(width: 1280, height: 720),
            bitRate: 2_000_000
        ))
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))

        // Wire preview view and stream as outputs of the mixer
        await mixer.addOutput(previewView)
        await mixer.addOutput(stream)

        // Start the capture pipeline
        await mixer.startRunning()

        // Attach camera and microphone devices
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

    func stopStream() {
        Task {
            _ = try? await stream.close()
            try? await connection.close()
            broadcastState = .idle
        }
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

    @StateObject private var broadcaster = RTMPBroadcaster()
    @State private var useFrontCamera = true
    @State private var showEndConfirmation = false
    @State private var permissionDenied = false
    @State private var didSetup = false

    @Environment(\.dismiss) private var dismiss

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
        .onDisappear { onDisappear() }
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
            }
            .buttonStyle(.plain)

            Spacer()
            statusBadge
            Spacer()

            Button { flipCamera() } label: {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
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
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { broadcaster.toggleMute() } label: {
                    Image(systemName: broadcaster.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(broadcaster.isMuted ? .red : .white)
                        .padding(14)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            if broadcaster.broadcastState.isLive {
                Button { showEndConfirmation = true } label: {
                    Label("End Stream", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
            } else if broadcaster.broadcastState.isConnecting {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Connecting to stream…")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            } else {
                Button { goLive() } label: {
                    Label("Go Live", systemImage: "video.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .disabled(permissionDenied)
            }
        }
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

        guard await checkAndRequestPermissions() else {
            permissionDenied = true
            return
        }
        await broadcaster.setup(useFrontCamera: useFrontCamera)
    }

    private func onDisappear() {
        if broadcaster.broadcastState.isLive || broadcaster.broadcastState.isConnecting {
            broadcaster.stopStream()
        }
    }

    /// Returns true when both camera and microphone are authorized (requesting if needed).
    private func checkAndRequestPermissions() async -> Bool {
        let cameraGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }

        let micGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
        case .notDetermined:
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            micGranted = false
        }

        return cameraGranted && micGranted
    }

    // MARK: - Actions

    private func flipCamera() {
        useFrontCamera.toggle()
        broadcaster.flipCamera(useFrontCamera: useFrontCamera)
    }

    private func goLive() {
        broadcaster.startStream(rtmpURL: buildRTMPURL(), streamName: streamName)
    }

    /// Constructs the RTMP ingest URL.
    /// Format: rtmp://{host}:1935/live?token={token}
    /// nginx-rtmp passes this as tcurl to /api/stream/auth/ for validation.
    private func buildRTMPURL() -> String {
        let host = serverURL.host ?? serverURL.absoluteString
        return "rtmp://\(host):1935/live?token=\(token)"
    }
}
