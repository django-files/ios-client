//
//  BiometricLockView.swift
//  Django Files
//

import LocalAuthentication
import SwiftUI

struct BiometricLockView: View {
    @EnvironmentObject private var lockManager: BiometricLockManager

    private var lockIcon: String {
        switch lockManager.biometryType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        case .opticID:  return "opticid"
        default:        return "lock.fill"
        }
    }

    private var unlockLabel: String {
        switch lockManager.biometryType {
        case .faceID:   return "Unlock with Face ID"
        case .touchID:  return "Unlock with Touch ID"
        case .opticID:  return "Unlock with Optic ID"
        default:        return "Unlock"
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: lockIcon)
                    .font(.system(size: 64))
                    .foregroundStyle(.primary)

                Text("Django Files is locked")
                    .font(.title2)
                    .fontWeight(.semibold)

                Button(unlockLabel) {
                    Task { await lockManager.authenticate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .task {
            await lockManager.authenticate()
        }
    }
}
