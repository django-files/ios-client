//
//  BiometricLockManager.swift
//  Django Files
//

import LocalAuthentication
import SwiftUI

@MainActor
class BiometricLockManager: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published private(set) var isEnabled: Bool

    private let enabledKey = "requireBiometrics"
    private let timeoutKey = "biometricLockTimeout"

    /// Seconds the app can be backgrounded before requiring auth. 0 = immediately.
    @Published var lockTimeout: Int {
        didSet { UserDefaults.standard.set(lockTimeout, forKey: timeoutKey) }
    }

    private var backgroundedAt: Date? = nil
    private var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "requireBiometrics")
        isEnabled = enabled
        isLocked = enabled
        lockTimeout = UserDefaults.standard.integer(forKey: "biometricLockTimeout")
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context.biometryType
    }

    func recordBackgrounded() {
        if isEnabled { backgroundedAt = .now }
    }

    func checkAndLockIfNeeded() {
        guard isEnabled, !isLocked else { return }
        guard let backgroundedAt else { return }
        let elapsed = Date.now.timeIntervalSince(backgroundedAt)
        if elapsed >= TimeInterval(lockTimeout) {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Django Files"
            )
            if success { isLocked = false }
        } catch {
            // User cancelled or failed — remain locked
        }
    }

    // Returns false if biometrics/passcode are unavailable or the user cancels verification.
    func enable() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Enable app lock for Django Files"
            )
            guard success else { return false }
        } catch {
            return false
        }
        UserDefaults.standard.set(true, forKey: enabledKey)
        isEnabled = true
        isLocked = false  // just authenticated
        return true
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        isEnabled = false
        isLocked = false
        backgroundedAt = nil
    }
}
