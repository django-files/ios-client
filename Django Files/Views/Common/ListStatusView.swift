//
//  ListStatusView.swift
//  Django Files
//

import SwiftUI

/// Centered placeholder shown when a list has no rows to render — either because
/// the fetch failed or the result was empty. Includes an SF Symbol, a title,
/// a secondary message, and an optional retry button.
///
/// Designed to live as an `.overlay` on top of the parent `List` so the
/// pull-to-refresh gesture remains available even in the error state.
struct ListStatusView: View {
    let icon: String
    var iconColor: Color = .secondary
    var iconSize: CGFloat = 50
    let title: String
    let message: String?
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ListStatusView {
    /// Convenience for the standard error presentation.
    static func error(message: String?, retry: @escaping () -> Void) -> ListStatusView {
        ListStatusView(
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            iconSize: 60,
            title: "Something went wrong",
            message: message ?? "Please try again.",
            onRetry: retry
        )
    }
}

#Preview("Empty") {
    List {}
        .overlay {
            ListStatusView(
                icon: "video.slash",
                title: "No streams found",
                message: "Start a stream via OBS or another RTMP client"
            )
        }
}

#Preview("Error") {
    List {}
        .overlay {
            ListStatusView.error(
                message: "Authentication failed. Please sign in again.",
                retry: {}
            )
        }
}
