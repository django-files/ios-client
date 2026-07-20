//
//  UploadPauseGate.swift
//  Django Files
//
//  Per-upload suspend/resume gate consulted by the tus chunk-upload loop. An actor (not
//  MainActor) since that loop runs on a detached Task — UI-facing paused/pausable state lives
//  on `UploadProgressManager` instead and is updated via callbacks from the upload loop.
//
//  Chunks default to tens of MB, so a PATCH already in flight when the user taps pause can take
//  a long time to finish on its own — waiting for it to complete would make pause feel broken.
//  Instead this gate tracks the in-flight chunk's URLSessionTask and cancels it immediately on
//  pause; the chunk loop treats that specific cancellation as "paused, not failed" and retries
//  the same chunk (after resyncing the offset via HEAD) once resumed, rather than counting it
//  against the upload's retry budget.

import Foundation

actor UploadPauseGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private weak var activeTask: URLSessionTask?

    var isPaused: Bool { paused }

    /// Called by the chunk loop as soon as a PATCH's URLSessionTask exists, so a pause requested
    /// mid-flight (or just before, in the narrow race between creating the task and registering
    /// it here) can be enforced right away instead of waiting for the chunk to finish.
    func setActiveTask(_ task: URLSessionTask?) {
        activeTask = task
        if paused { activeTask?.cancel() }
    }

    func pause() {
        paused = true
        activeTask?.cancel()
    }

    func resume() {
        paused = false
        activeTask = nil
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
