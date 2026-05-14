//
//  SampleHandler.swift
//  BroadcastUploadExtension
//
//  Broadcast Upload Extension that streams the device's screen to RTMP.
//  Lives in a separate process so it can keep running when the host app
//  is backgrounded — the only iOS-supported path for system-wide screen
//  capture beyond foreground.
//
//  Communication with the host app happens via App Group UserDefaults:
//    Input  (host → ext):   "stream.broadcast.config"
//    Output (ext → host):   "stream.broadcast.status"
//    Stop   (host → ext):   "stream.broadcast.request" = "stop"
//
//  Required products (must be linked to this target via SPM):
//    • HaishinKit       — MediaMixer, codec settings
//    • RTMPHaishinKit   — RTMPConnection, RTMPStream
//

import ReplayKit
import HaishinKit
import RTMPHaishinKit
import VideoToolbox
import AVFoundation
import UIKit

final class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Constants (must mirror the host app)

    private static let appGroupID = "group.djangofiles.app"
    private static let configKey  = "stream.broadcast.config"
    private static let statusKey  = "stream.broadcast.status"
    private static let requestKey = "stream.broadcast.request"

    // MARK: - RTMP plumbing

    private let connection = RTMPConnection()
    private lazy var stream: RTMPStream = RTMPStream(connection: connection)
    // .manual mode: no AVCaptureSession; frames are fed directly via append().
    private let mixer = MediaMixer(captureSessionMode: .manual)

    // MARK: - Configuration

    private var rtmpURL: String = ""
    private var streamKey: String = ""
    private var bitRate: Int = 2_000_000
    private var longEdgePixels: CGFloat = 1280

    // MARK: - Per-frame state

    private var lastBufferSize: CGSize = .zero
    private var didConfigureSettings = false
    private var lastStopCheck: Date = .distantPast

    // MARK: - RPBroadcastSampleHandler

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let config = defaults.dictionary(forKey: Self.configKey),
              let url = config["rtmpURL"] as? String, !url.isEmpty,
              let key = config["streamKey"] as? String, !key.isEmpty
        else {
            updateStatus(state: "error", message: "Missing stream credentials in App Group")
            let err = NSError(
                domain: "DjangoFilesBroadcast",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Stream credentials not available. Open the Django Files app and start the stream from there before tapping Start Broadcast."]
            )
            finishBroadcastWithError(err)
            return
        }

        rtmpURL = url
        streamKey = key
        if let br = config["bitRate"] as? Int { bitRate = br }
        if let le = config["longEdgePixels"] as? Double { longEdgePixels = CGFloat(le) }

        updateStatus(state: "connecting")

        Task { [weak self] in
            await self?.setupAndConnect()
        }
    }

    override func broadcastPaused() {
        Task { [weak self] in
            guard let self else { return }
            await self.mixer.stopRunning()
            self.updateStatus(state: "paused")
        }
    }

    override func broadcastResumed() {
        Task { [weak self] in
            guard let self else { return }
            await self.mixer.startRunning()
            self.updateStatus(state: "live")
        }
    }

    override func broadcastFinished() {
        // Synchronous teardown — the extension is about to be terminated.
        // Wait briefly so the RTMP FCUnpublish/close packets get a chance
        // to flush; otherwise the server may keep the stream "live" for a
        // few seconds until it times out.
        let semaphore = DispatchSemaphore(value: 0)
        Task { [weak self] in
            guard let self else { semaphore.signal(); return }
            _ = try? await self.stream.close()
            try? await self.connection.close()
            await self.mixer.stopRunning()
            self.updateStatus(state: "ended")
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            checkStopRequestIfNeeded()
            reconfigureCodecIfNeeded(for: sampleBuffer)
            let buf = sampleBuffer
            Task { [mixer] in await mixer.append(buf, track: 0) }
        case .audioApp, .audioMic:
            let buf = sampleBuffer
            Task { [mixer] in await mixer.append(buf, track: 0) }
        @unknown default:
            break
        }
    }

    /// Lets the host app trigger a graceful stop without the user having to
    /// hunt for the iOS status-bar pill. Rate-limited to ~1Hz so we don't
    /// hammer UserDefaults on the per-frame path.
    private func checkStopRequestIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastStopCheck) >= 1.0 else { return }
        lastStopCheck = now
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              defaults.string(forKey: Self.requestKey) == "stop"
        else { return }
        defaults.removeObject(forKey: Self.requestKey)
        let err = NSError(
            domain: "DjangoFilesBroadcast",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Stream ended."]
        )
        finishBroadcastWithError(err)
    }

    // MARK: - Setup

    private func setupAndConnect() async {
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
        // Configure with a sensible initial size based on the device's screen,
        // then refine per-frame once real buffer dimensions arrive.
        try? await stream.setVideoSettings(initialVideoSettings())
        await mixer.addOutput(stream)
        await mixer.startRunning()

        do {
            _ = try await connection.connect(rtmpURL)
            _ = try await stream.publish(streamKey)
            updateStatus(state: "live")
        } catch {
            updateStatus(state: "error", message: error.localizedDescription)
            finishBroadcastWithError(error)
        }
    }

    // MARK: - Codec sizing

    /// Set the video codec's output size to match the actual sample buffer's
    /// aspect ratio. scalingMode is .normal (fill, not preserve-aspect), so an
    /// incorrect output size stretches the picture on the receiver — exactly
    /// the bug that triggered this rewrite.
    private func reconfigureCodecIfNeeded(for buffer: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(buffer) else { return }
        let w = CGFloat(CVPixelBufferGetWidth(pb))
        let h = CGFloat(CVPixelBufferGetHeight(pb))
        let size = CGSize(width: w, height: h)
        if didConfigureSettings && size == lastBufferSize { return }
        lastBufferSize = size
        didConfigureSettings = true

        let target = videoSizePreservingAspect(source: size, longEdge: longEdgePixels)
        let settings = VideoCodecSettings(
            videoSize: target,
            bitRate: bitRate,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            scalingMode: .normal,
            allowFrameReordering: false
        )
        Task { [stream] in try? await stream.setVideoSettings(settings) }
    }

    private func initialVideoSettings() -> VideoCodecSettings {
        // UIScreen.nativeBounds is always portrait pixels; close enough as a
        // bootstrap value before the first real frame arrives.
        let native = UIScreen.main.nativeBounds.size
        let target = videoSizePreservingAspect(source: native, longEdge: longEdgePixels)
        return VideoCodecSettings(
            videoSize: target,
            bitRate: bitRate,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            scalingMode: .normal,
            allowFrameReordering: false
        )
    }

    private func videoSizePreservingAspect(source: CGSize, longEdge: CGFloat) -> CGSize {
        let long  = max(source.width, source.height)
        let short = min(source.width, source.height)
        guard long > 0, short > 0 else { return CGSize(width: 1280, height: 720) }
        let aspect = short / long
        let scaledShort = (longEdge * aspect).rounded()
        // H.264 requires even dimensions.
        let evenShort = max(2, CGFloat(Int(scaledShort) & ~1))
        let evenLong  = max(2, CGFloat(Int(longEdge)    & ~1))
        if source.width >= source.height {
            return CGSize(width: evenLong, height: evenShort)
        } else {
            return CGSize(width: evenShort, height: evenLong)
        }
    }

    // MARK: - Status reporting

    private func updateStatus(state: String, message: String? = nil) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        var dict: [String: Any] = [
            "state": state,
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let msg = message { dict["message"] = msg }
        defaults.set(dict, forKey: Self.statusKey)
    }
}
