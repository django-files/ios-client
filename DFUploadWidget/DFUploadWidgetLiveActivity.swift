//
//  DFUploadWidgetLiveActivity.swift
//  DFUploadWidget
//

import ActivityKit
import DFUploadShared
import SwiftUI
import WidgetKit

struct DFUploadWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DFUploadActivityAttributes.self) { context in
            DFUploadLockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DFExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DFExpandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DFExpandedBottom(context: context)
                }
            } compactLeading: {
                DFCompactLeading(context: context)
            } compactTrailing: {
                DFCompactTrailing(context: context)
            } minimal: {
                DFMinimal(context: context)
            }
        }
    }
}

// MARK: - Lock Screen

struct DFUploadLockScreenView: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(context.state.isComplete
                          ? Color.green.opacity(0.15)
                          : Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                if context.state.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                    DFProgressRing(progress: context.state.progress, lineWidth: 3, size: 46)
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if context.state.isComplete {
                    Text("Upload complete")
                        .font(.subheadline.weight(.semibold))
                    if context.state.copiedURL != nil {
                        Text(context.attributes.albumName.map { "Album link for \($0) copied" }
                             ?? "Link copied to clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(uploadingTitle(context))
                        .font(.subheadline.weight(.semibold))
                    Text(context.attributes.serverHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: context.state.progress)
                        .tint(Color.accentColor)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if !context.state.isComplete {
                Text("\(context.state.uploadedCount)/\(context.state.totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uploadingTitle(_ ctx: ActivityViewContext<DFUploadActivityAttributes>) -> String {
        let n = ctx.state.totalCount
        if n == 1 { return "Uploading…" }
        if let album = ctx.attributes.albumName { return "Uploading \(n) files to \(album)…" }
        return "Uploading \(n) files…"
    }
}

// MARK: - Dynamic Island Expanded

struct DFExpandedLeading: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if context.state.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.title3)
                    DFProgressRing(progress: context.state.progress, lineWidth: 2.5, size: 32)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Django Files")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(context.attributes.serverHost)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }
}

struct DFExpandedTrailing: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        if context.state.isComplete {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .padding(.trailing, 4)
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(context.state.uploadedCount)/\(context.state.totalCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.trailing, 4)
        }
    }
}

struct DFExpandedBottom: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        if context.state.isComplete {
            if context.state.copiedURL != nil {
                Label("Link copied to clipboard", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 4)
            }
        } else {
            ProgressView(value: context.state.progress)
                .tint(.white)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Dynamic Island Compact & Minimal

struct DFCompactLeading: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        ZStack {
            if context.state.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
            } else {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 13))
                DFProgressRing(progress: context.state.progress, lineWidth: 2, size: 22)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 22, height: 22)
        .padding(.leading, 4)
    }
}

struct DFCompactTrailing: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        if !context.state.isComplete {
            Text("\(Int(context.state.progress * 100))%")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white)
                .padding(.trailing, 4)
        }
    }
}

struct DFMinimal: View {
    let context: ActivityViewContext<DFUploadActivityAttributes>
    var body: some View {
        ZStack {
            if context.state.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else {
                DFProgressRing(progress: context.state.progress, lineWidth: 2, size: 20)
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "arrow.up")
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Progress Ring

struct DFProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews

extension DFUploadActivityAttributes {
    static var preview: DFUploadActivityAttributes {
        DFUploadActivityAttributes(serverHost: "files.example.com", albumName: "Vacation 2026")
    }
}

extension DFUploadActivityAttributes.ContentState {
    static var midway: Self {
        .init(progress: 0.42, uploadedCount: 2, totalCount: 5, isComplete: false, copiedURL: nil)
    }
    static var almostDone: Self {
        .init(progress: 0.9, uploadedCount: 4, totalCount: 5, isComplete: false, copiedURL: nil)
    }
    static var done: Self {
        .init(progress: 1.0, uploadedCount: 5, totalCount: 5, isComplete: true,
              copiedURL: "https://files.example.com/a/vacation-2026")
    }
    static var singleStart: Self {
        .init(progress: 0.05, uploadedCount: 0, totalCount: 1, isComplete: false, copiedURL: nil)
    }
}

#Preview("Lock screen — uploading", as: .content, using: DFUploadActivityAttributes.preview) {
    DFUploadWidgetLiveActivity()
} contentStates: {
    DFUploadActivityAttributes.ContentState.singleStart
    DFUploadActivityAttributes.ContentState.midway
    DFUploadActivityAttributes.ContentState.almostDone
    DFUploadActivityAttributes.ContentState.done
}

#Preview("Dynamic Island — expanded", as: .dynamicIsland(.expanded), using: DFUploadActivityAttributes.preview) {
    DFUploadWidgetLiveActivity()
} contentStates: {
    DFUploadActivityAttributes.ContentState.midway
    DFUploadActivityAttributes.ContentState.done
}

#Preview("Dynamic Island — compact", as: .dynamicIsland(.compact), using: DFUploadActivityAttributes.preview) {
    DFUploadWidgetLiveActivity()
} contentStates: {
    DFUploadActivityAttributes.ContentState.midway
    DFUploadActivityAttributes.ContentState.almostDone
    DFUploadActivityAttributes.ContentState.done
}

#Preview("Dynamic Island — minimal", as: .dynamicIsland(.minimal), using: DFUploadActivityAttributes.preview) {
    DFUploadWidgetLiveActivity()
} contentStates: {
    DFUploadActivityAttributes.ContentState.midway
    DFUploadActivityAttributes.ContentState.done
}
