//
//  UploadPauseGate.swift
//  Django Files
//
//  Per-upload suspend/resume gate consulted between tus chunks. An actor (not MainActor) since
//  the chunk-upload loop runs on a detached Task — UI-facing paused/pausable state lives on
//  `UploadProgressManager` instead and is updated via callbacks from the upload loop.

import Foundation

actor UploadPauseGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    /// Suspends while paused. Throws `CancellationError` immediately if the surrounding Task
    /// is already cancelled, or as soon as it's cancelled while suspended here — cancelling a
    /// paused upload must not leave it stuck waiting for a resume that will never come.
    func waitWhilePaused() async throws {
        try Task.checkCancellation()
        while paused {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if paused {
                        waiters.append(continuation)
                    } else {
                        continuation.resume()
                    }
                }
            } onCancel: {
                Task { await self.resume() }
            }
            try Task.checkCancellation()
        }
    }
}
