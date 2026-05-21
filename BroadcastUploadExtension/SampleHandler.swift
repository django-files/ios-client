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

    private static let appGroupID  = "group.djangofiles.app"
    private static let configKey   = "stream.broadcast.config"
    private static let statusKey   = "stream.broadcast.status"
    private static let requestKey  = "stream.broadcast.request"
    private static let micMutedKey    = "stream.broadcast.micMuted"
    private static let orientationKey = "stream.broadcast.orientation"

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

    // Rotation — ReplayKit always delivers portrait-dimensioned pixel buffers
    // and uses RPVideoSampleOrientationKey to signal the display rotation.
    // We rotate the buffer to match the display orientation so the codec
    // receives correctly-oriented pixels and the viewer sees the right picture.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var rotatedBufferPool: CVPixelBufferPool?
    private var rotatedBufferPoolConfig = CGSize.zero

    private var isMicMuted: Bool {
        UserDefaults(suiteName: Self.appGroupID)?.bool(forKey: Self.micMutedKey) ?? false
    }

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

        // Reset mic mute on each new broadcast so stale host-app state
        // doesn't carry over into a fresh session.
        UserDefaults(suiteName: Self.appGroupID)?.removeObject(forKey: Self.micMutedKey)

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
            let orientation = bufferOrientation(sampleBuffer)
            // Rotate portrait-dimensioned buffer to match the display orientation
            // so the encoder receives correctly-oriented pixels.
            let buf = orientation.needsRotation
                ? (rotate(sampleBuffer, for: orientation) ?? sampleBuffer)
                : sampleBuffer
            reconfigureCodecIfNeeded(for: buf)
            Task { [mixer] in await mixer.append(buf, track: 0) }
        case .audioApp:
            let buf = sampleBuffer
            Task { [mixer] in await mixer.append(buf, track: 0) }
        case .audioMic:
            // Drop mic buffers when the host app has muted the mic.
            guard !isMicMuted else { break }
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

    // MARK: - Buffer rotation

    /// Rotates a CMSampleBuffer to the correct display orientation using CIImage.
    /// The output buffer has swapped W/H for landscape orientations.
    /// Returns nil on failure — caller falls back to the original buffer.
    private func rotate(_ sampleBuffer: CMSampleBuffer,
                        for orientation: CGImagePropertyOrientation) -> CMSampleBuffer? {
        guard let src = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // CIImage.oriented() applies the correct rotation/flip for the given
        // CGImagePropertyOrientation so the resulting image is display-upright.
        let image = CIImage(cvPixelBuffer: src).oriented(orientation)
        let dstW = Int(image.extent.width)
        let dstH = Int(image.extent.height)

        // Recreate the pool only when the output dimensions change (orientation switch).
        if rotatedBufferPoolConfig != CGSize(width: dstW, height: dstH) {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(src),
                kCVPixelBufferWidthKey: dstW,
                kCVPixelBufferHeightKey: dstH,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            rotatedBufferPool = pool
            rotatedBufferPoolConfig = CGSize(width: dstW, height: dstH)
        }

        var dst: CVPixelBuffer?
        guard let pool = rotatedBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dst) == kCVReturnSuccess,
              let dst else { return nil }

        // CIImage.oriented() may leave a non-zero extent origin — translate to (0,0).
        let translated = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y
        ))
        ciContext.render(translated, to: dst)

        // Re-wrap in a CMSampleBuffer preserving the original timing.
        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
        var fmtDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: dst,
            formatDescriptionOut: &fmtDesc
        )
        guard let fmtDesc else { return nil }
        var out: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: dst,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmtDesc,
            sampleTiming: &timing,
            sampleBufferOut: &out
        )
        return out
    }

    // MARK: - Codec sizing

    /// Reconfigures the codec output size when the buffer geometry changes.
    /// Rotation is applied before this call, so buffer dimensions directly
    /// reflect the displayed orientation — no orientation-based swapping needed.
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
        // Bootstrap before the first real frame arrives.
        // Both UIScreen.main (iOS 26) and UIScreen.screens (iOS 16) are
        // deprecated, and UIApplication.shared is unavailable in extensions,
        // so use a representative modern display resolution.
        let native = CGSize(width: 1179, height: 2556)
        let target = videoSizePreservingAspect(source: native, longEdge: longEdgePixels)
        return VideoCodecSettings(
            videoSize: target,
            bitRate: bitRate,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            scalingMode: .normal,
            allowFrameReordering: false
        )
    }

    /// Reads the display orientation for the sample buffer.
    /// Priority 1: orientation relayed from the host app via App Group (UIDevice.orientation
    ///   is unambiguous; the host app writes it on every change and before broadcast starts).
    /// Priority 2: RPVideoSampleOrientationKey — used only when no App Group value is set
    ///   (e.g., broadcast launched without the host app running in the foreground).
    private func bufferOrientation(_ buffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        if defaults?.object(forKey: Self.orientationKey) != nil {
            return hostAppOrientation()
        }
        if let raw = CMGetAttachment(
            buffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
            return orientation
        }
        return .up
    }

    private func hostAppOrientation() -> CGImagePropertyOrientation {
        let v = UserDefaults(suiteName: Self.appGroupID)?
            .integer(forKey: Self.orientationKey) ?? 0
        switch v {
        case 1: return .right  // landscapeLeft  (home button right, device rotated CW → right column → top → rotate buffer 90° CCW)
        case 2: return .left   // landscapeRight (home button left, device rotated CCW → left column → top → rotate buffer 90° CW)
        case 3: return .down   // portraitUpsideDown
        default: return .up    // portrait, no rotation
        }
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

private extension CGImagePropertyOrientation {
    // `.up` and `.upMirrored` are already display-correct — no rotation needed.
    var needsRotation: Bool {
        self != .up && self != .upMirrored
    }
}
