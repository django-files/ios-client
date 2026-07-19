//
//  UploadProgressManager.swift
//  Django Files
//

import SwiftUI
import UIKit

@MainActor
final class UploadProgressManager: ObservableObject {
    struct Upload: Identifiable {
        let id: UUID
        var filename: String
        var thumbnail: UIImage?
        var progress: Double
        /// True once this upload is confirmed to be running over tus — only tus uploads can
        /// actually be paused/resumed, so the pause control stays hidden until then (and hides
        /// again if a mid-transfer failure falls back to the legacy, non-pausable path).
        var isPausable: Bool = false
        var isPaused: Bool = false
    }

    @Published private(set) var uploads: [Upload] = []
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0

    private var activeTasks: [Task<Void, Never>] = []
    private var pauseGates: [UUID: UploadPauseGate] = [:]

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

    func start(filename: String, thumbnail: UIImage? = nil) -> UUID {
        if uploads.isEmpty {
            completedCount = 0
            totalCount = 0
        }
        totalCount += 1
        let upload = Upload(id: UUID(), filename: filename, thumbnail: thumbnail, progress: 0)
        uploads.append(upload)
        return upload.id
    }

    func setThumbnail(id: UUID, image: UIImage) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].thumbnail = image
    }

    func update(id: UUID, progress: Double) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].progress = max(0, min(1, progress))
    }

    func setPausable(id: UUID, pausable: Bool) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].isPausable = pausable
        if !pausable {
            uploads[index].isPaused = false
        }
    }

    func registerPauseGate(id: UUID, gate: UploadPauseGate) {
        pauseGates[id] = gate
    }

    func togglePause(id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), uploads[index].isPausable,
              let gate = pauseGates[id] else { return }
        let nowPaused = !uploads[index].isPaused
        uploads[index].isPaused = nowPaused
        Task {
            if nowPaused {
                await gate.pause()
            } else {
                await gate.resume()
            }
        }
    }

    func finish(id: UUID) {
        guard uploads.contains(where: { $0.id == id }) else { return }
        uploads.removeAll { $0.id == id }
        pauseGates.removeValue(forKey: id)
        completedCount += 1
        if uploads.isEmpty {
            activeTasks.removeAll()
        }
    }

    func register(task: Task<Void, Never>) {
        activeTasks.append(task)
    }

    func cancelAll() {
        for task in activeTasks { task.cancel() }
        activeTasks.removeAll()
        pauseGates.removeAll()
        uploads.removeAll()
        completedCount = 0
        totalCount = 0
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

            if let current = manager.currentUpload, current.isPausable {
                Button {
                    manager.togglePause(id: current.id)
                } label: {
                    Image(systemName: current.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(current.isPaused ? "Resume upload" : "Pause upload")
            }

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
