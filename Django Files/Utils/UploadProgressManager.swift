//
//  UploadProgressManager.swift
//  Django Files
//

import ActivityKit
import DFUploadShared
import SwiftUI
import UIKit

@MainActor
final class UploadProgressManager: ObservableObject {
    struct Upload: Identifiable {
        let id: UUID
        var filename: String
        var thumbnail: UIImage?
        var progress: Double
    }

    @Published private(set) var uploads: [Upload] = []
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0

    private var activeTasks: [Task<Void, Never>] = []
    private var activity: Activity<DFUploadActivityAttributes>?
    private var activityServerHost: String = ""
    private var lastActivityProgress: Double = -1

    var isUploading: Bool { !uploads.isEmpty }

    var currentUpload: Upload? { uploads.first }

    var currentIndex: Int { min(completedCount + 1, totalCount) }

    /// Cumulative session progress: completed files plus the in-progress fraction of the current file,
    /// divided by total files in this session.
    var cumulativeProgress: Double {
        guard totalCount > 0 else { return 0 }
        let currentFraction = currentUpload?.progress ?? 0
        return (Double(completedCount) + currentFraction) / Double(totalCount)
    }

    func start(filename: String, thumbnail: UIImage? = nil, serverHost: String = "") -> UUID {
        let isNewSession = uploads.isEmpty
        if isNewSession {
            completedCount = 0
            totalCount = 0
            activityServerHost = serverHost
        }
        totalCount += 1
        let upload = Upload(id: UUID(), filename: filename, thumbnail: thumbnail, progress: 0)
        uploads.append(upload)
        updateActivity()
        return upload.id
    }

    /// Call on the `.inactive` scene-phase transition. The app is still considered foreground at
    /// this point (per Apple's rules), so `Activity.request` will succeed; calling it on
    /// `.background` is too late and silently fails.
    func appWillResignActive() {
        guard !uploads.isEmpty, activity == nil else { return }
        startActivity()
    }

    /// Call when the app returns to the foreground. The in-app accessory bar takes over,
    /// so the Live Activity is no longer needed.
    func appDidBecomeActive() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        lastActivityProgress = -1
    }

    func setThumbnail(id: UUID, image: UIImage) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].thumbnail = image
    }

    func update(id: UUID, progress: Double) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].progress = max(0, min(1, progress))
        updateActivity()
    }

    func finish(id: UUID) {
        guard uploads.contains(where: { $0.id == id }) else { return }
        uploads.removeAll { $0.id == id }
        completedCount += 1
        if uploads.isEmpty {
            activeTasks.removeAll()
            endActivity(copiedURL: nil)
        } else {
            updateActivity()
        }
    }

    func register(task: Task<Void, Never>) {
        activeTasks.append(task)
    }

    func cancelAll() {
        for task in activeTasks { task.cancel() }
        activeTasks.removeAll()
        uploads.removeAll()
        completedCount = 0
        totalCount = 0
        if let activity {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            self.activity = nil
        }
        lastActivityProgress = -1
    }

    // MARK: - Live Activity

    private func startActivity() {
        guard activity == nil else { return }
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else { return }
        let attrs = DFUploadActivityAttributes(serverHost: activityServerHost, albumName: nil)
        let state = currentContentState(isComplete: false, copiedURL: nil)
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: .now + 3600)
            )
            lastActivityProgress = state.progress
        } catch {
            NSLog("[UploadProgress] Activity.request failed: %@", String(describing: error))
        }
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = currentContentState(isComplete: false, copiedURL: nil)
        if abs(state.progress - lastActivityProgress) < 0.02
            && state.uploadedCount == activity.content.state.uploadedCount
            && state.totalCount == activity.content.state.totalCount {
            return
        }
        lastActivityProgress = state.progress
        Task {
            await activity.update(ActivityContent(state: state, staleDate: .now + 3600))
        }
    }

    private func endActivity(copiedURL: String?) {
        guard let activity else { return }
        let final = DFUploadActivityAttributes.ContentState(
            progress: 1.0,
            uploadedCount: totalCount,
            totalCount: totalCount,
            isComplete: true,
            copiedURL: copiedURL
        )
        let dismissalDate = Date().addingTimeInterval(15)
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .after(dismissalDate)
            )
        }
        self.activity = nil
        lastActivityProgress = -1
    }

    private func currentContentState(isComplete: Bool, copiedURL: String?) -> DFUploadActivityAttributes.ContentState {
        DFUploadActivityAttributes.ContentState(
            progress: cumulativeProgress,
            uploadedCount: completedCount,
            totalCount: totalCount,
            isComplete: isComplete,
            copiedURL: copiedURL
        )
    }
}

struct UploadProgressAccessoryView: View {
    @EnvironmentObject private var manager: UploadProgressManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                manager.cancelAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel upload")

            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.currentUpload?.filename ?? "Uploading…")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if manager.totalCount > 1 {
                        Text("\(manager.currentIndex) of \(manager.totalCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                    ProgressView(value: manager.cumulativeProgress)
                        .progressViewStyle(.linear)
                }
            }

            Text("\(Int(manager.cumulativeProgress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var iconView: some View {
        if let thumbnail = manager.currentUpload?.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.tint.opacity(0.15))
                .overlay {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
        }
    }
}
