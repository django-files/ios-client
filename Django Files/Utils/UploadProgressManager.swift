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
    }

    @Published private(set) var uploads: [Upload] = []
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0

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

    func finish(id: UUID) {
        guard uploads.contains(where: { $0.id == id }) else { return }
        uploads.removeAll { $0.id == id }
        completedCount += 1
    }
}

struct UploadProgressAccessoryView: View {
    @EnvironmentObject private var manager: UploadProgressManager

    var body: some View {
        HStack(spacing: 12) {
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
