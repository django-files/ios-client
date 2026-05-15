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
import AVKit
import VideoToolbox
import ReplayKit
import HaishinKit
import RTMPHaishinKit

// MARK: - Camera Preview (Metal-backed)

private struct CameraPreviewView: UIViewRepresentable {
    let hkView: MTHKView
    let pipPreviewView: PiPHKView
    let pipCoordinator: CameraPiPCoordinator
    let deviceOrientation: UIDeviceOrientation
    /// Only install PiP if the capture session can actually keep delivering
    /// frames while the app is backgrounded — otherwise PiP just floats a
    /// frozen frame, which is worse UX than letting iOS pause the stream.
    let supportsBackgroundCamera: Bool

    // SwiftUI gets a fresh container UIView on every mount, but the broadcaster
    // owns the actual MTHKView so the mixer can keep delivering frames across
    // mode swaps. Returning the singleton MTHKView directly made SwiftUI's
    // hosting machinery fail to reattach it on the second camera-mode entry
    // (the view stayed orphaned in the old hosting hierarchy), which is what
    // made repeated swapping appear broken.

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        hkView.removeFromSuperview()
        hkView.frame = container.bounds
        hkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(hkView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Re-host the MTHKView if it somehow lost its superview (e.g. SwiftUI
        // re-issued makeUIView elsewhere first).
        if hkView.superview !== uiView {
            hkView.removeFromSuperview()
            hkView.frame = uiView.bounds
            hkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(hkView)
        }
        DispatchQueue.main.async {
            applyTransformIfNeeded(to: hkView, coordinator: context.coordinator)
            // AVPictureInPictureController must be initialized AFTER the source
            // view is in a window. updateUIView runs after layout, so by the
            // first call here the window association is established.
            if supportsBackgroundCamera,
               hkView.window != nil,
               !context.coordinator.didInstallPiP {
                context.coordinator.didInstallPiP = true
                pipCoordinator.install(sourceView: hkView, pipPreviewView: pipPreviewView)
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: PreviewCoordinator) {
        // Don't tear down PiP here — StreamBroadcastView owns the lifecycle and
        // calls coordinator.uninstall() in onDisappear. SwiftUI may call
        // dismantleUIView on transient re-renders that we shouldn't react to.
    }

    func makeCoordinator() -> PreviewCoordinator { PreviewCoordinator() }
    final class PreviewCoordinator {
        var didInstallPiP = false
        var lastOrientation: UIDeviceOrientation = .unknown
    }

    private func applyTransformIfNeeded(to view: MTHKView, coordinator: PreviewCoordinator) {
        // updateUIView fires on every state change (mode switch, isSwitchingMode
        // flicker, etc.). Re-running the alpha-fade animation each time stacks
        // animations on top of each other and can leave the view stuck at
        // alpha 0. Only animate when the orientation has actually changed.
        guard coordinator.lastOrientation != deviceOrientation else { return }
        coordinator.lastOrientation = deviceOrientation

        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        // mixer.setVideoOrientation() already tells HaishinKit which way to rotate
        // the encoded frames, so the MTHKView content arrives correctly oriented —
        // we do NOT apply a matching rotation here. The only exception is
        // portraitUpsideDown, which AVCaptureVideoOrientation doesn't model and
        // HaishinKit therefore can't correct through setVideoOrientation.
        // Previously landscapeLeft/Right also applied fillScale (≈2.16×), which
        // caused the "too zoomed in" appearance while the actual stream was fine.
        let t: CGAffineTransform
        switch deviceOrientation {
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

// MARK: - Broadcast Extension Availability

/// Whether our Broadcast Upload Extension is actually embedded in the app
/// bundle. Without this check, tapping "Go Live" in screen mode while the
/// extension is missing — Simulator, or a build that pre-dates the Xcode
/// target wiring — falls through to iOS's own screen-recorder, which saves
/// to Photos instead of streaming.
enum BroadcastExtensionAvailability {
    /// Bundle identifier of the broadcast upload extension (must mirror
    /// RTMPBroadcaster.broadcastExtensionBundleID).
    static let bundleID = "com.djangofiles.app.BroadcastUploadExtension"

    static let isAvailable: Bool = {
        #if targetEnvironment(simulator)
        // Broadcast Upload Extensions don't load in the iOS Simulator. Even
        // if the .appex is embedded, RPSystemBroadcastPickerView falls back
        // to the system screen-recorder.
        return false
        #else
        guard let pluginsURL = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
              )
        else { return false }
        return contents.contains { url in
            guard let info = Bundle(url: url)?.infoDictionary,
                  let id = info["CFBundleIdentifier"] as? String
            else { return false }
            return id == bundleID
        }
        #endif
    }()

    static var unavailableReason: String {
        #if targetEnvironment(simulator)
        return "Screen sharing requires a physical device — the iOS Simulator can't run broadcast upload extensions."
        #else
        return "The screen-sharing extension isn't installed in this build. Add the Broadcast Upload Extension target in Xcode and rebuild — see BroadcastUploadExtension/SETUP.md."
        #endif
    }
}

// MARK: - System Broadcast Picker (screen-share, background-capable)
//
// RPSystemBroadcastPickerView is a system UIView that brings up the
// "Start Broadcast" sheet for the user to pick our Broadcast Upload Extension.
// We host an invisible instance and "tap" its internal button programmatically
// when the user hits our record button, so the look-and-feel matches the rest
// of the broadcast UI instead of Apple's default purple AirPlay-style picker.

private struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String
    @Binding var trigger: Int

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = preferredExtension
        // Mic comes from RPSampleBufferType.audioMic inside the extension; the
        // separate mic toggle on the system picker is redundant for us.
        picker.showsMicrophoneButton = false
        // Seed the coordinator with the current trigger value so we don't fire
        // a spurious picker tap when re-entering screen mode (the view is
        // recreated each entry, but `trigger` is parent state that persists).
        context.coordinator.lastTrigger = trigger
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        if context.coordinator.lastTrigger != trigger {
            context.coordinator.lastTrigger = trigger
            // updateUIView may run inside a layout pass — defer the tap so the
            // sheet doesn't fight with the current view-tree update cycle.
            DispatchQueue.main.async { tapInnerButton(in: uiView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastTrigger = 0 }

    private func tapInnerButton(in view: UIView) {
        if let button = view as? UIButton {
            button.sendActions(for: .touchUpInside)
            return
        }
        for sub in view.subviews { tapInnerButton(in: sub) }
    }
}

// MARK: - Camera Picture-in-Picture
//
// AVPictureInPictureController in "video call" mode (iOS 15+) lets us keep the
// AVCaptureSession alive when the app is backgrounded — the OS treats PiP as
// foreground for capture purposes. Without PiP, the session would be suspended
// the moment the user switches apps, killing the RTMP video track.
//
// Two MTHKViews are required: one stays inline in the app, the other lives
// inside the floating PiP window. The MediaMixer fans the same camera frames
// to both, so this doesn't double the encode cost.

@MainActor
final class CameraPiPCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {

    private var pipController: AVPictureInPictureController?
    private let videoCallVC: AVPictureInPictureVideoCallViewController = {
        let vc = AVPictureInPictureVideoCallViewController()
        // Default to portrait 9:16; AVKit honors aspect, not exact size.
        vc.preferredContentSize = CGSize(width: 270, height: 480)
        vc.view.backgroundColor = .black
        return vc
    }()

    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var isPossible = false

    /// `sourceView` is the inline preview (must already be in a window).
    /// `pipPreviewView` is mounted into the PiP floating window.
    func install(sourceView: UIView, pipPreviewView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard pipController == nil else { return }

        // Attach the second preview to the video-call VC. fillSuperview-style
        // constraints so the camera fills the floating window regardless of size.
        pipPreviewView.removeFromSuperview()
        pipPreviewView.translatesAutoresizingMaskIntoConstraints = false
        videoCallVC.view.addSubview(pipPreviewView)
        NSLayoutConstraint.activate([
            pipPreviewView.leadingAnchor.constraint(equalTo: videoCallVC.view.leadingAnchor),
            pipPreviewView.trailingAnchor.constraint(equalTo: videoCallVC.view.trailingAnchor),
            pipPreviewView.topAnchor.constraint(equalTo: videoCallVC.view.topAnchor),
            pipPreviewView.bottomAnchor.constraint(equalTo: videoCallVC.view.bottomAnchor),
        ])

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: videoCallVC
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Auto-start PiP when the app moves to the background. Without this,
        // the AVCaptureSession would be suspended on background and the
        // streamer would freeze.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller
        self.isPossible = controller.isPictureInPicturePossible
    }

    func uninstall() {
        if let controller = pipController, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
        pipController = nil
        isPictureInPictureActive = false
        isPossible = false
    }

    func stop() {
        pipController?.stopPictureInPicture()
    }

    // MARK: AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = false }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: any Error) {
        print("CameraPiPCoordinator: failed to start PiP: \(error)")
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

    /// Long-edge pixel target. Camera frames are 16:9 so the short edge is derived
    /// from that; screen frames keep the device's native aspect, scaled to this.
    var longEdgePixels: CGFloat {
        switch self {
        case .p480:  return 854
        case .p720:  return 1280
        case .p1080: return 1920
        case .uhd4k: return 3840
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

    /// Output size for screen capture: matches the device's native screen aspect
    /// ratio rather than a fixed 16:9, otherwise VideoToolbox stretches the buffer
    /// (scalingMode is .normal — fill, not preserve-aspect) and the receiver sees
    /// a squashed picture. Long edge is capped at the resolution target.
    /// `frameSize` is the actual buffer pixel size if known (per-frame in the
    /// broadcast extension); pass `.zero` to fall back to UIScreen.nativeBounds.
    func screenVideoSize(orientation: UIDeviceOrientation, frameSize: CGSize = .zero) -> CGSize {
        let sourceSize: CGSize
        if frameSize.width > 0, frameSize.height > 0 {
            sourceSize = frameSize
        } else {
            // nativeBounds is always reported in portrait pixels (w < h).
            let native = UIScreen.main.nativeBounds.size
            if orientation.isLandscape {
                sourceSize = CGSize(width: native.height, height: native.width)
            } else {
                sourceSize = native
            }
        }

        let long  = max(sourceSize.width, sourceSize.height)
        let short = min(sourceSize.width, sourceSize.height)
        guard long > 0, short > 0 else { return videoSize(for: orientation) }

        let aspect = short / long
        let targetLong  = longEdgePixels
        let targetShort = (targetLong * aspect).rounded()
        // H.264 prefers even dimensions — round down to the nearest even number.
        let evenShort = max(2, CGFloat(Int(targetShort) & ~1))
        let evenLong  = max(2, CGFloat(Int(targetLong)  & ~1))

        if sourceSize.width >= sourceSize.height {
            return CGSize(width: evenLong, height: evenShort)
        } else {
            return CGSize(width: evenShort, height: evenLong)
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
    /// True when the AVCaptureSession can keep delivering frames while the app
    /// is in PiP / multitasking. iPad-with-Apple-silicon only; always false on
    /// iPhone. Used by the SwiftUI layer to decide whether installing PiP would
    /// just produce a frozen-frame floating window.
    @Published private(set) var supportsBackgroundCamera = false

    // Camera-mode plumbing. Screen mode delegates capture+RTMP to the
    // Broadcast Upload Extension (separate process) so it survives
    // backgrounding — these objects are dormant while in screen mode.
    //
    // The mixer is created once and reused across mode switches: recreating it
    // means the previous AVCaptureSession lingers in memory long enough that the
    // new session can fail to acquire the camera, which was the original
    // "switch more than once" bug. We just stop/start it instead.
    //
    // connection and stream ARE recreated per camera entry — reusing them after
    // close() leaves residual handshake/chunk state that breaks the next publish.
    private let mixer: MediaMixer
    private var connection = RTMPConnection()
    private(set) var stream: RTMPStream

    // Metal preview view — camera mode only; irrelevant in screen mode.
    let previewView: MTHKView = {
        let v = MTHKView(frame: .zero)
        v.videoGravity = .resizeAspectFill
        return v
    }()

    // Second preview attached to the PiP video-call view controller. Must be a
    // separate UIView from `previewView` because AVKit mounts it into the PiP
    // window's hierarchy — a single view can't live in two windows at once.
    //
    // Uses PiPHKView (AVSampleBufferDisplayLayer-backed) instead of MTHKView.
    // AVKit's PiP overlay window renders AVSampleBufferDisplayLayer correctly,
    // but a CAMetalLayer-backed view (MTHKView) stops updating once moved
    // into the floating window — that's the "frozen frame in PiP" symptom.
    let pipPreviewView: PiPHKView = {
        let v = PiPHKView(frame: .zero)
        v.videoGravity = .resizeAspect
        return v
    }()

    // Screen-mode extension config (mirrors BroadcastUploadExtension/SampleHandler.swift).
    static let appGroupID = "group.djangofiles.app"
    static let broadcastExtensionBundleID = "com.djangofiles.app.BroadcastUploadExtension"
    private static let configKey  = "stream.broadcast.config"
    private static let statusKey  = "stream.broadcast.status"
    private static let requestKey = "stream.broadcast.request"

    private var statusTimer: Timer?
    private var pendingRTMPURL: String?
    private var pendingStreamName: String?

    init(captureMode: CaptureMode = .camera) {
        self.captureMode = captureMode
        // Single mixer for the broadcaster's lifetime. Screen mode doesn't feed
        // the mixer (the extension owns capture+encode), so it stays idle
        // there — startRunning is only called from the camera-mode setup path.
        self.mixer = MediaMixer()
        stream = RTMPStream(connection: connection)
    }

    // MARK: - Setup

    func setup(useFrontCamera: Bool, deviceOrientation: UIDeviceOrientation) async {
        configureAudioSession()

        switch captureMode {
        case .camera:
            try? await stream.setVideoSettings(videoCodecSettings(for: resolution, orientation: deviceOrientation))
            try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
            await mixer.addOutput(stream)
            // Set the capture session preset BEFORE starting so the camera
            // actually provides frames at the target resolution.
            await mixer.setSessionPreset(resolution.capturePreset)
            // Lets the AVCaptureSession keep delivering frames while the app is
            // in Picture-in-Picture / multitasking. Without this flag iOS would
            // suspend the camera the moment we go background, and HaishinKit
            // explicitly checks `session.isMultitaskingCameraAccessEnabled`
            // before deciding whether to pause video on background.
            if #available(iOS 16.0, *) {
                var supported = false
                await mixer.configuration { session in
                    if session.isMultitaskingCameraAccessSupported {
                        session.isMultitaskingCameraAccessEnabled = true
                        supported = true
                    }
                }
                supportsBackgroundCamera = supported
            }
            await mixer.addOutput(previewView)
            // Second tap for the PiP floating-window preview. The mixer fans
            // frames out to every attached view, so we don't double-encode.
            await mixer.addOutput(pipPreviewView)
            await mixer.startRunning()
            await attachCamera(useFrontCamera: useFrontCamera)
            await attachAudioDevice()
            await mixer.setVideoOrientation(avOrientation(from: deviceOrientation))

        case .screen:
            // No in-process capture: the Broadcast Upload Extension handles
            // everything. We just observe the status it writes to App Group.
            clearExtensionStatus()
            startObservingExtensionStatus()
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
        switch captureMode {
        case .camera:
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
        case .screen:
            // For screen mode, "start" persists credentials so the system
            // broadcast extension can pick them up; the user actually starts
            // the broadcast via RPSystemBroadcastPickerView (system UI).
            pendingRTMPURL = rtmpURL
            pendingStreamName = streamName
            writeBroadcastConfig(rtmpURL: rtmpURL, streamName: streamName)
        }
    }

    /// Re-writes the App Group config that the broadcast extension reads on launch.
    /// Call before showing RPSystemBroadcastPickerView so the extension has fresh
    /// credentials even if the user changed resolution / opened a different stream.
    func writeBroadcastConfig(rtmpURL: String, streamName: String) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set([
            "rtmpURL": rtmpURL,
            "streamKey": streamName,
            "bitRate": resolution.bitRate,
            "longEdgePixels": Double(resolution.longEdgePixels),
        ], forKey: Self.configKey)
    }

    /// Ends the RTMP stream; keeps preview/capture running so the user can go live again.
    func stopStream() {
        switch captureMode {
        case .camera:
            Task {
                _ = try? await stream.close()
                try? await connection.close()
                broadcastState = .idle
            }
        case .screen:
            // Ask the extension to finish gracefully via App Group flag.
            // The extension polls this on its per-frame path (~1Hz) and calls
            // finishBroadcastWithError to end. We optimistically reset our
            // state; the observer will overwrite if the extension still reports
            // a different state.
            if let defaults = UserDefaults(suiteName: Self.appGroupID) {
                defaults.set("stop", forKey: Self.requestKey)
            }
            broadcastState = .idle
        }
    }

    /// Full teardown — releases all hardware. Call on view dismiss.
    func teardown() async {
        stopObservingExtensionStatus()
        _ = try? await stream.close()
        try? await connection.close()
        if captureMode == .camera {
            try? await mixer.attachVideo(nil as AVCaptureDevice?, track: 0)
            try? await mixer.attachAudio(nil as AVCaptureDevice?, track: 0)
            await mixer.stopRunning()
        }
        broadcastState = .idle
    }

    /// Surface a one-shot error from the SwiftUI layer (e.g. when the screen
    /// share record button is tapped but our broadcast extension isn't
    /// embedded in this build). Drops into the existing error alert path.
    func reportExtensionUnavailable(_ message: String) {
        broadcastState = .error(message)
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
            // mode: .default is intentional — HaishinKit's own example notes that
            // setting a specific mode (e.g. .videoRecording) disables stereo capture
            // and suppresses output routing, producing silence on device and no audio
            // in the RTMP stream. .default leaves capture/routing intact.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            try session.setActive(true)
            // Required for stereo mic capture on iOS 18+.
            try? session.setPreferredInputNumberOfChannels(2)
        } catch {
            print("RTMPBroadcaster: audio session error: \(error)")
        }
    }

    // MARK: - Broadcast Extension Status (screen mode only)

    /// Polls the status the Broadcast Upload Extension writes to App Group
    /// UserDefaults so we can show Connecting / Live / Error in our UI.
    /// Darwin notifications would be cleaner but UserDefaults polling at 1Hz
    /// is plenty for status state and avoids the extra plumbing.
    private func startObservingExtensionStatus() {
        stopObservingExtensionStatus()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollExtensionStatus() }
        }
        statusTimer = timer
    }

    private func stopObservingExtensionStatus() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func pollExtensionStatus() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let dict = defaults.dictionary(forKey: Self.statusKey),
              let state = dict["state"] as? String
        else { return }

        switch state {
        case "connecting":
            if !broadcastState.isConnecting { broadcastState = .connecting }
        case "live":
            if !broadcastState.isLive { broadcastState = .live }
        case "paused":
            if !broadcastState.isLive { broadcastState = .live }
        case "ended":
            if broadcastState.isLive || broadcastState.isConnecting {
                broadcastState = .idle
            }
        case "error":
            let message = (dict["message"] as? String) ?? "Broadcast extension failed."
            if broadcastState.errorMessage != message {
                broadcastState = .error(message)
            }
        default:
            break
        }
    }

    private func clearExtensionStatus() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.removeObject(forKey: Self.statusKey)
        // Stale "stop" requests would immediately kill a freshly launched
        // broadcast — wipe them on every setup/mode-switch.
        defaults.removeObject(forKey: Self.requestKey)
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
        if captureMode == .camera {
            // Closing the RTMP stream/connection on every mode swap so we don't
            // try to fan a screen-extension publish through the in-process stream
            // (the extension publishes independently).
            _ = try? await stream.close()
            try? await connection.close()
            try? await mixer.attachVideo(nil as AVCaptureDevice?, track: 0)
            try? await mixer.attachAudio(nil as AVCaptureDevice?, track: 0)
            // Drop the soon-to-be-replaced RTMPStream so the mixer doesn't
            // retain it. previewView / pipPreviewView stay attached — they're
            // singletons that are reused across switches and re-adding them
            // each time would just churn HaishinKit's outputs array.
            await mixer.removeOutput(stream)
            await mixer.stopRunning()
        } else {
            stopObservingExtensionStatus()
        }

        broadcastState = .idle
        captureMode = newMode

        switch newMode {
        case .camera:
            // Reuse the single mixer; reset only the RTMP plumbing. Reusing
            // RTMPConnection/RTMPStream after close() leaves residual state
            // that breaks the next publish — recreating them is cheap.
            connection = RTMPConnection()
            stream = RTMPStream(connection: connection)
            try? await stream.setVideoSettings(videoCodecSettings(for: resolution, orientation: deviceOrientation))
            try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
            await mixer.addOutput(stream)
            await mixer.setSessionPreset(resolution.capturePreset)
            // Re-run the multitasking-camera enable in case the user started
            // the view in screen mode (where setup() skips this) and only now
            // arrived at the camera path. Idempotent — safe to run again.
            if #available(iOS 16.0, *) {
                var supported = false
                await mixer.configuration { session in
                    if session.isMultitaskingCameraAccessSupported {
                        session.isMultitaskingCameraAccessEnabled = true
                        supported = true
                    }
                }
                supportsBackgroundCamera = supported
            }
            // addOutput is idempotent (HaishinKit dedupes by identity), so
            // re-adding the preview views on every camera entry is harmless
            // and guards against a hypothetical out-of-band removal.
            await mixer.addOutput(previewView)
            await mixer.addOutput(pipPreviewView)
            await mixer.startRunning()
            await attachCamera(useFrontCamera: useFrontCamera)
            await attachAudioDevice()
            await mixer.setVideoOrientation(avOrientation(from: deviceOrientation))
        case .screen:
            clearExtensionStatus()
            startObservingExtensionStatus()
        }
    }

    func setResolution(_ newResolution: StreamResolution, orientation: UIDeviceOrientation) {
        resolution = newResolution
        Task {
            switch captureMode {
            case .camera:
                // Update the capture session preset so the camera targets the new
                // resolution. The camera transitions asynchronously, so initial frames
                // arriving in the new VTCompressionSession may still be at the old
                // size — scalingMode: .normal in videoCodecSettings handles this by
                // upscaling them rather than cropping, keeping the encoded output
                // valid throughout the transition.
                await mixer.setSessionPreset(newResolution.capturePreset)
                try? await stream.setVideoSettings(videoCodecSettings(for: newResolution, orientation: orientation))
            case .screen:
                // Re-write App Group config so the next broadcast picks up the
                // new bitrate / long-edge. Doesn't affect an already-running
                // broadcast — that would require the user to stop and restart.
                if let rtmp = pendingRTMPURL, let key = pendingStreamName {
                    writeBroadcastConfig(rtmpURL: rtmp, streamName: key)
                }
            }
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
        // Screen capture frames carry the device's native aspect (~9:19.5); the
        // 16:9 default used for camera would force a stretch under scalingMode .normal.
        let size = captureMode == .screen
            ? res.screenVideoSize(orientation: orientation)
            : res.videoSize(for: orientation)
        return VideoCodecSettings(
            videoSize: size,
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
    @StateObject private var pipCoordinator = CameraPiPCoordinator()
    @State private var useFrontCamera = false
    @State private var showEndConfirmation = false
    @State private var permissionDenied = false
    @State private var didSetup = false
    @State private var ingestInfo: DFStreamIngestInfo?
    @State private var showIngestInfo = false
    @State private var showResolutionPicker = false
    @State private var showChatDrawer = false
    @State private var chatDrawerOffset: CGFloat = 0
    @State private var broadcastPickerTrigger = 0
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
                    CameraPreviewView(
                        hkView: broadcaster.previewView,
                        pipPreviewView: broadcaster.pipPreviewView,
                        pipCoordinator: pipCoordinator,
                        deviceOrientation: deviceOrientation,
                        supportsBackgroundCamera: broadcaster.supportsBackgroundCamera
                    )
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

            // Invisible host for the system broadcast picker. We tap its inner
            // button programmatically from the record button in screen mode so
            // the visible UI stays consistent with the rest of the broadcast view.
            if broadcaster.captureMode == .screen {
                BroadcastPickerView(
                    preferredExtension: RTMPBroadcaster.broadcastExtensionBundleID,
                    trigger: $broadcastPickerTrigger
                )
                .frame(width: 0, height: 0)
                .opacity(0.001)
                .allowsHitTesting(false)
            }

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
            pipCoordinator.uninstall()
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
                        .lineLimit(1)
                        // fixedSize stops SwiftUI from horizontally compressing
                        // this capsule when the row gets crowded (4 buttons in
                        // camera mode + the centre title badge competing for
                        // space). Without it, "1080p" gets squashed to "10…".
                        .fixedSize(horizontal: true, vertical: false)
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
                            // Refuse to enter screen mode when our broadcast
                            // extension isn't embedded — otherwise the user
                            // would land in a UI whose only "Go Live" path
                            // leads to Apple's built-in screen recorder.
                            if mode == .screen, !BroadcastExtensionAvailability.isAvailable {
                                broadcaster.reportExtensionUnavailable(BroadcastExtensionAvailability.unavailableReason)
                                return
                            }
                            Task {
                                await broadcaster.switchCaptureMode(
                                    to: mode,
                                    useFrontCamera: useFrontCamera,
                                    deviceOrientation: deviceOrientation
                                )
                            }
                        } label: {
                            // Hint the user when screen share won't work in
                            // this build (extension missing / simulator).
                            let label = (mode == .screen && !BroadcastExtensionAvailability.isAvailable)
                                ? "\(mode.rawValue) (unavailable)"
                                : mode.rawValue
                            Label(label, systemImage: mode.icon)
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
            // Right-cluster wins the layout when the centre title is long —
            // otherwise the title eats horizontal space and the resolution
            // capsule (rightmost text element) gets clipped first.
            .layoutPriority(1)
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

            // Mute — camera mode only. In screen mode the Broadcast Upload
            // Extension owns the mic, and the user toggles it from the system
            // "Start Broadcast" sheet rather than from our UI.
            if broadcaster.captureMode == .camera {
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
            } else {
                // Keep the layout balanced when the mute button is absent.
                Color.clear.frame(width: 52, height: 52)
            }
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
                    Image(systemName: broadcaster.broadcastState.isLive
                          ? "dot.radiowaves.left.and.right"
                          : "rectangle.on.rectangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(broadcaster.broadcastState.isLive
                         ? "Screen is being shared"
                         : "Screen Share")
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Text(broadcaster.broadcastState.isLive
                         ? "iOS will keep recording even when you switch to another app. Tap the stop button to end."
                         : "Tap the record button below — iOS will ask you to confirm before broadcasting your screen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
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
        // Screen-share mode owns no in-process capture: the Broadcast Upload
        // Extension is the one capturing audio/video, and iOS prompts the user
        // for screen + mic permission inside the system "Start Broadcast" sheet.
        // Returning true skips redundant prompts in the host app.
        guard initialCaptureMode == .camera else { return true }

        let micGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:   micGranted = true
        case .notDetermined: micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:            micGranted = false
        }

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
        // In screen mode, refuse to trigger the system picker if our extension
        // isn't actually installed in the app bundle — RPSystemBroadcastPickerView
        // would otherwise fall back to Apple's built-in screen recorder, which
        // saves a clip to Photos rather than streaming. Surface a clear error
        // instead so the user knows they need a real device + the Xcode target.
        if broadcaster.captureMode == .screen, !BroadcastExtensionAvailability.isAvailable {
            broadcaster.reportExtensionUnavailable(BroadcastExtensionAvailability.unavailableReason)
            return
        }
        // Both paths share startStream; in screen mode that just persists the
        // creds to App Group. The actual broadcast is launched by the system
        // when we tap the hidden RPSystemBroadcastPickerView's inner button.
        broadcaster.startStream(rtmpURL: currentRTMPURL, streamName: streamName)
        if broadcaster.captureMode == .screen {
            broadcastPickerTrigger &+= 1
        }
    }

    private var currentRTMPURL: String {
        let host = ingestInfo?.rtmpHost ?? serverURL.host ?? serverURL.absoluteString
        let port = ingestInfo?.rtmpPort ?? 1935
        return "rtmp://\(host):\(port)/live?token=\(token)"
    }
}
