//
//  UploadMenuButton.swift
//  Django Files
//

import SwiftUI

struct UploadMenuButton: View {
    let server: Binding<DjangoFilesSession?>
    var onUploadComplete: (() async -> Void)? = nil
    var showPurpleShadow: Bool = false

    @EnvironmentObject private var uploadProgressManager: UploadProgressManager
    @State private var uploadSource: UploadSource?
    @State private var showingShortCreator = false
    @State private var showingAlbumCreator = false
    @State private var showingNewStream = false

    private var useAccessoryProgress: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    var body: some View {
        Menu {
            Menu {
                ForEach(UploadSource.allCases) { source in
                    Button {
                        uploadSource = source
                    } label: {
                        Label(source.title, systemImage: source.systemImage)
                    }
                }
            } label: {
                Label("Upload", systemImage: "arrow.up.doc")
            }
            Button {
                Task { await uploadClipboard() }
            } label: {
                Label("Upload Clipboard", systemImage: "clipboard")
            }
            Button {
                showingShortCreator = true
            } label: {
                Label("Create Short", systemImage: "link.badge.plus")
            }
            Button {
                showingAlbumCreator = true
            } label: {
                Label("Create Album", systemImage: "photo.badge.plus")
            }
            Button {
                showingNewStream = true
            } label: {
                Label("Start Stream", systemImage: "video.badge.waveform.fill")
            }
        } label: {
            Image(systemName: "plus")
        }
        .shadow(color: .purple, radius: showPurpleShadow ? 3 : 0)
        .sheet(item: $uploadSource) { source in
            if let serverInstance = server.wrappedValue {
                FileUploadView(source: source, server: serverInstance, onUploadComplete: onUploadComplete)
            }
        }
        .sheet(isPresented: $showingShortCreator) {
            if let serverInstance = server.wrappedValue {
                ShortCreatorView(server: serverInstance)
            }
        }
        .sheet(isPresented: $showingAlbumCreator) {
            if let serverInstance = server.wrappedValue {
                CreateAlbumView(server: serverInstance)
            }
        }
        .sheet(isPresented: $showingNewStream) {
            if let serverInstance = server.wrappedValue {
                NewStreamView(server: serverInstance)
            }
        }
    }

    @MainActor
    private func uploadClipboard() async {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else {
            ToastManager.shared.showToast(message: "Invalid server configuration")
            return
        }

        let pasteboard = UIPasteboard.general

        if let text = pasteboard.string {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("ios-clip.txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                ToastManager.shared.showToast(message: "Error uploading text: \(error.localizedDescription)")
                return
            }
            await dispatchClipboardUpload(serverURL: url, token: serverInstance.token, tempURL: tempURL, displayName: "ios-clip.txt", successMessage: "Text uploaded successfully", failureMessage: "Failed to upload text")
            return
        }

        if let image = pasteboard.image {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("image.jpg")
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                ToastManager.shared.showToast(message: "No content found in clipboard")
                return
            }
            do {
                try imageData.write(to: tempURL)
            } catch {
                ToastManager.shared.showToast(message: "Error uploading image: \(error.localizedDescription)")
                return
            }
            await dispatchClipboardUpload(serverURL: url, token: serverInstance.token, tempURL: tempURL, displayName: "image.jpg", thumbnail: image, successMessage: "Image uploaded successfully", failureMessage: "Failed to upload image")
            return
        }

        if let videoData = pasteboard.data(forPasteboardType: "public.mpeg-4"),
           let tempURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("video.mp4") {
            do {
                try videoData.write(to: tempURL)
            } catch {
                ToastManager.shared.showToast(message: "Error uploading video: \(error.localizedDescription)")
                return
            }
            await dispatchClipboardUpload(serverURL: url, token: serverInstance.token, tempURL: tempURL, displayName: "video.mp4", successMessage: "Video uploaded successfully", failureMessage: "Failed to upload video")
            return
        }

        ToastManager.shared.showToast(message: "No content found in clipboard")
    }

    @MainActor
    private func dispatchClipboardUpload(serverURL: URL, token: String, tempURL: URL, displayName: String, thumbnail: UIImage? = nil, successMessage: String, failureMessage: String) async {
        if useAccessoryProgress {
            let manager = uploadProgressManager
            let completion = onUploadComplete
            let id = manager.start(filename: displayName, thumbnail: thumbnail)
            let task = Task.detached {
                let api = DFAPI(url: serverURL, token: token)
                let delegate = UploadProgressDelegate { progress in
                    Task { @MainActor in manager.update(id: id, progress: progress) }
                }
                let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    manager.finish(id: id)
                    if !Task.isCancelled {
                        ToastManager.shared.showToast(message: response != nil ? successMessage : failureMessage)
                    }
                }
                if Task.isCancelled { return }
                if response != nil, let completion { await completion() }
            }
            manager.register(task: task)
        } else {
            let api = DFAPI(url: serverURL, token: token)
            let delegate = UploadProgressDelegate { _ in }
            let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
            try? FileManager.default.removeItem(at: tempURL)
            if response != nil {
                if let refresh = onUploadComplete { await refresh() }
                ToastManager.shared.showToast(message: successMessage)
            } else {
                ToastManager.shared.showToast(message: failureMessage)
            }
        }
    }
}
