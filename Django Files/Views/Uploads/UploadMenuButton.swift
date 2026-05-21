//
//  UploadMenuButton.swift
//  Django Files
//

import SwiftUI

struct UploadMenuButton: View {
    let server: Binding<DjangoFilesSession?>
    var onUploadComplete: (() async -> Void)? = nil
    var showPurpleShadow: Bool = false

    @State private var showingUploadSheet = false
    @State private var showingShortCreator = false
    @State private var showingAlbumCreator = false
    @State private var showingNewStream = false

    var body: some View {
        Menu {
            Button {
                showingUploadSheet = true
            } label: {
                Label("Upload File", systemImage: "arrow.up.doc")
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
        .sheet(isPresented: $showingUploadSheet, onDismiss: {
            guard let refresh = onUploadComplete else { return }
            Task { await refresh() }
        }) {
            if let serverInstance = server.wrappedValue {
                FileUploadView(server: serverInstance)
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

        let api = DFAPI(url: url, token: serverInstance.token)
        let pasteboard = UIPasteboard.general

        if let text = pasteboard.string {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("ios-clip.txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
                let delegate = UploadProgressDelegate { _ in }
                let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                if response != nil {
                    if let refresh = onUploadComplete { await refresh() }
                    ToastManager.shared.showToast(message: "Text uploaded successfully")
                } else {
                    ToastManager.shared.showToast(message: "Failed to upload text")
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                ToastManager.shared.showToast(message: "Error uploading text: \(error.localizedDescription)")
            }
            return
        }

        if let image = pasteboard.image {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("image.jpg")
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do {
                    try imageData.write(to: tempURL)
                    let delegate = UploadProgressDelegate { _ in }
                    let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                    try? FileManager.default.removeItem(at: tempURL)
                    if response != nil {
                        if let refresh = onUploadComplete { await refresh() }
                        ToastManager.shared.showToast(message: "Image uploaded successfully")
                    } else {
                        ToastManager.shared.showToast(message: "Failed to upload image")
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    ToastManager.shared.showToast(message: "Error uploading image: \(error.localizedDescription)")
                }
            }
            return
        }

        if let videoData = pasteboard.data(forPasteboardType: "public.mpeg-4"),
           let tempURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("video.mp4") {
            do {
                try videoData.write(to: tempURL)
                let delegate = UploadProgressDelegate { _ in }
                let response = await api.uploadFile(url: tempURL, taskDelegate: delegate)
                try? FileManager.default.removeItem(at: tempURL)
                if response != nil {
                    if let refresh = onUploadComplete { await refresh() }
                    ToastManager.shared.showToast(message: "Video uploaded successfully")
                } else {
                    ToastManager.shared.showToast(message: "Failed to upload video")
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                ToastManager.shared.showToast(message: "Error uploading video: \(error.localizedDescription)")
            }
            return
        }

        ToastManager.shared.showToast(message: "No content found in clipboard")
    }
}
