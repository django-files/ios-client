//
//  ShareUploadManager.swift
//  Django Files
//

import ActivityKit
import DFUploadShared
import UIKit

@MainActor
final class ShareUploadManager: ObservableObject {
    private static let groupContainerID = "group.djangofiles.app"

    func processJob(id: String) {
        print("[ShareUpload] processJob id=\(id)")
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupContainerID
        ) else {
            print("[ShareUpload] no container")
            return
        }

        let jobFile = container
            .appendingPathComponent("upload-jobs")
            .appendingPathComponent("\(id).json")

        let data: Data
        do {
            data = try Data(contentsOf: jobFile)
        } catch {
            print("[ShareUpload] job file read failed: \(error)")
            return
        }
        let job: DFPendingUploadJob
        do {
            job = try JSONDecoder().decode(DFPendingUploadJob.self, from: data)
        } catch {
            print("[ShareUpload] job decode failed: \(error)")
            return
        }
        print("[ShareUpload] decoded job, files=\(job.fileNames.count) isShorten=\(job.isShorten)")

        let info = ActivityAuthorizationInfo()
        print("[ShareUpload] activities enabled = \(info.areActivitiesEnabled), frequentPushes = \(info.frequentPushesEnabled)")

        let filesDir = container
            .appendingPathComponent("upload-files")
            .appendingPathComponent(id)

        Task { [weak self] in
            await self?.runJob(job: job, filesDir: filesDir, jobFile: jobFile)
        }
    }

    private func runJob(job: DFPendingUploadJob, filesDir: URL, jobFile: URL) async {
        guard let serverURL = URL(string: job.sessionURL) else { return }
        let api = DFAPI(url: serverURL, token: job.sessionToken)
        let serverHost = serverURL.host ?? job.sessionURL

        if job.isShorten {
            guard let sourceString = job.shortenSourceURL,
                  let sourceURL = URL(string: sourceString) else { return }

            let activity = startActivity(serverHost: serverHost, totalCount: 1, albumName: nil)
            let shortLink = job.shortText.isEmpty ? randomString() : job.shortText
            let response = await api.createShort(url: sourceURL, short: shortLink)
            if let link = response?.url {
                await MainActor.run { UIPasteboard.general.string = link }
            }
            await endActivity(activity, copiedURL: response?.url)
            try? FileManager.default.removeItem(at: jobFile)
            return
        }

        let fileURLs = job.fileNames.map { filesDir.appendingPathComponent($0) }
        let total = fileURLs.count
        let activity = startActivity(serverHost: serverHost, totalCount: total, albumName: job.albumName)
        let albumsParam = job.albumIDs.map { String($0) }.joined(separator: ",")
        var lastFileURL: String?

        for (i, fileURL) in fileURLs.enumerated() {
            let fileBase = Double(i) / Double(total)
            let fileSlice = 1.0 / Double(total)

            let progressDelegate = ShareUploadProgressDelegate(threshold: 0.05) { progress in
                let overall = fileBase + progress * fileSlice
                Task {
                    let state = DFUploadActivityAttributes.ContentState(
                        progress: overall,
                        uploadedCount: i,
                        totalCount: total,
                        isComplete: false,
                        copiedURL: nil
                    )
                    await activity?.update(ActivityContent(state: state, staleDate: .now + 3600))
                }
            }

            let task = await api.uploadFileStreamed(
                url: fileURL,
                albums: albumsParam,
                privateUpload: job.privateUpload,
                stripExif: job.stripExif,
                stripGps: job.stripGps,
                taskDelegate: progressDelegate
            )
            if let response = await task?.waitForComplete() {
                lastFileURL = response.url
            }

            let completedState = DFUploadActivityAttributes.ContentState(
                progress: Double(i + 1) / Double(total),
                uploadedCount: i + 1,
                totalCount: total,
                isComplete: false,
                copiedURL: nil
            )
            await activity?.update(ActivityContent(state: completedState, staleDate: .now + 3600))
        }

        let urlToCopy = total > 1 ? job.firstAlbumURL : lastFileURL
        if let link = urlToCopy {
            await MainActor.run { UIPasteboard.general.string = link }
        }

        await endActivity(activity, copiedURL: urlToCopy)

        try? FileManager.default.removeItem(at: filesDir)
        try? FileManager.default.removeItem(at: jobFile)
    }

    // MARK: - Live Activity

    private func startActivity(
        serverHost: String,
        totalCount: Int,
        albumName: String?
    ) -> Activity<DFUploadActivityAttributes>? {
        let attrs = DFUploadActivityAttributes(
            serverHost: serverHost,
            albumName: albumName
        )
        let initial = DFUploadActivityAttributes.ContentState(
            progress: 0,
            uploadedCount: 0,
            totalCount: totalCount,
            isComplete: false,
            copiedURL: nil
        )
        do {
            let a = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: initial, staleDate: .now + 3600)
            )
            print("[ShareUpload] Activity.request OK id=\(a.id)")
            return a
        } catch {
            print("[ShareUpload] Activity.request FAILED: \(error)")
            return nil
        }
    }

    private func endActivity(
        _ activity: Activity<DFUploadActivityAttributes>?,
        copiedURL: String?
    ) async {
        guard let activity else { return }
        let lastState = activity.content.state
        let final = DFUploadActivityAttributes.ContentState(
            progress: 1.0,
            uploadedCount: lastState.totalCount,
            totalCount: lastState.totalCount,
            isComplete: true,
            copiedURL: copiedURL
        )
        await activity.end(
            ActivityContent(state: final, staleDate: nil),
            dismissalPolicy: .after(.now + 30)
        )
    }

    private func randomString() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<5).map { _ in letters.randomElement()! })
    }
}

private class ShareUploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void
    private let threshold: Double
    private var lastReported: Double = -1

    init(threshold: Double, onProgress: @escaping (Double) -> Void) {
        self.threshold = threshold
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let p = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        if p - lastReported >= threshold {
            lastReported = p
            onProgress(p)
        }
    }
}
