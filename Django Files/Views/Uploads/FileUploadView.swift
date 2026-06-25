//
//  FileUploadView.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/18/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

enum UploadSource: String, CaseIterable, Identifiable {
    case camera, photoLibrary, files, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Take Photo"
        case .photoLibrary: "Photo Library"
        case .files: "Files"
        case .audio: "Record Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera"
        case .photoLibrary: "photo.on.rectangle"
        case .files: "folder"
        case .audio: "mic"
        }
    }

    /// EXIF/GPS stripping only applies to image sources.
    var supportsImageOptions: Bool {
        switch self {
        case .camera, .photoLibrary: true
        case .files, .audio: false
        }
    }
}

struct FileUploadView: View {
    let source: UploadSource
    let server: DjangoFilesSession

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadProgressManager: UploadProgressManager

    @State private var uploadPrivate = false
    @State private var stripExif = false
    @State private var stripGps = false

    @State private var albums: [DFAlbum] = []
    @State private var selectedAlbum: DFAlbum?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingFilePicker = false
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?

    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingURL: URL?
    @State private var recordingStartedAt: Date?

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(source.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) {
                    primaryActionButton.padding()
                }
                .sheet(isPresented: $showingCamera) {
                    ImagePicker(image: $capturedImage)
                        .ignoresSafeArea()
                }
                .fileImporter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true,
                    onCompletion: handleFileImporter
                )
                .onChange(of: capturedImage) { _, image in
                    guard let image else { return }
                    capturedImage = nil
                    startCapturedImageUpload(image)
                }
                .onChange(of: selectedItems) { _, items in
                    guard !items.isEmpty else { return }
                    startPhotosUpload(items)
                }
                .task { await loadAlbums() }
        }
    }

    @ViewBuilder
    private var form: some View {
        Form {
            optionsSection
            albumSection
            if isRecording, let startedAt = recordingStartedAt {
                Section { RecordingIndicator(startedAt: startedAt) }
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section("Options") {
            Toggle("Make Private", isOn: $uploadPrivate)
            if source.supportsImageOptions {
                Toggle("Strip EXIF", isOn: $stripExif)
                Toggle("Strip GPS", isOn: $stripGps)
            }
        }
    }

    private var albumSection: some View {
        Section("Album") {
            NavigationLink {
                AlbumPickerView(albums: albums, selected: $selectedAlbum)
            } label: {
                LabeledContent("Album", value: selectedAlbum?.name ?? "None")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if isRecording { cancelRecording() }
                dismiss()
            }
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            startFilesUpload(urls)
        case .failure(let error):
            ToastManager.shared.showToast(message: "Could not open files: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch source {
        case .camera:
            actionButton(title: "Take Photo", systemImage: "camera") {
                showingCamera = true
            }
        case .photoLibrary:
            PhotosPicker(
                selection: $selectedItems,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label("Choose Photos & Videos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .files:
            actionButton(title: "Choose Files", systemImage: "folder") {
                showingFilePicker = true
            }
        case .audio:
            actionButton(
                title: isRecording ? "Stop Recording" : "Start Recording",
                systemImage: isRecording ? "stop.circle.fill" : "record.circle",
                tint: isRecording ? .red : nil
            ) {
                if isRecording { stopRecording() } else { startRecording() }
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint ?? .accentColor)
    }

    // MARK: - Upload dispatch

    private func startCapturedImageUpload(_ image: UIImage) {
        detachCapturedImageUpload(image)
        dismiss()
    }

    private func startPhotosUpload(_ items: [PhotosPickerItem]) {
        detachPhotosUpload(items)
        dismiss()
    }

    private func startFilesUpload(_ urls: [URL]) {
        detachFilesUpload(urls)
        dismiss()
    }

    private var albumIdParam: String {
        selectedAlbum.map { String($0.id) } ?? ""
    }

    // MARK: - Recording

    private func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordingStartedAt = .now
            isRecording = true
        } catch {
            ToastManager.shared.showToast(message: "Could not start recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        recordingStartedAt = nil
        guard let url = recordingURL else { return }
        recordingURL = nil
        detachSingleFileUpload(tempURL: url, displayName: "recording.m4a", deleteAfter: true)
        dismiss()
    }

    private func cancelRecording() {
        audioRecorder?.stop()
        isRecording = false
        recordingStartedAt = nil
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
    }

    // MARK: - Detached upload (iOS 26+)

    @MainActor
    private func detachSingleFileUpload(tempURL: URL, displayName: String, thumbnail: UIImage? = nil, deleteAfter: Bool) {
        let serverURL = server.url
        let token = server.token
        let albums = albumIdParam
        let priv = uploadPrivate
        let exif = stripExif
        let gps = stripGps
        let manager = uploadProgressManager

        let host = URL(string: serverURL)?.host ?? serverURL
        let id = manager.start(filename: displayName, thumbnail: thumbnail, serverHost: host)
        let task = Task.detached {
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            let delegate = UploadProgressDelegate { progress in
                Task { @MainActor in manager.update(id: id, progress: progress) }
            }
            _ = await api.uploadFile(
                url: tempURL,
                albums: albums,
                privateUpload: priv,
                stripExif: exif,
                stripGps: gps,
                taskDelegate: delegate
            )
            if deleteAfter { try? FileManager.default.removeItem(at: tempURL) }
            await MainActor.run { manager.finish(id: id) }
        }
        manager.register(task: task)
    }

    @MainActor
    private func detachPhotosUpload(_ items: [PhotosPickerItem]) {
        let serverURL = server.url
        let token = server.token
        let albums = albumIdParam
        let priv = uploadPrivate
        let exif = stripExif
        let gps = stripGps
        let manager = uploadProgressManager
        let host = URL(string: serverURL)?.host ?? serverURL

        let ids: [UUID] = items.enumerated().map { (index, item) in
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .audiovisualContent) }
            return manager.start(filename: isVideo ? "video_\(index)" : "photo_\(index).jpg", serverHost: host)
        }

        let task = Task.detached {
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                let id = ids[index]
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .audiovisualContent) }

                let uploadURL: URL?
                if isVideo {
                    uploadURL = try? await item.loadTransferable(type: VideoTransferable.self).map { $0.url }
                } else {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        await MainActor.run { manager.finish(id: id) }
                        continue
                    }
                    if let image = UIImage(data: data) {
                        await MainActor.run { manager.setThumbnail(id: id, image: image) }
                    }
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(index).jpg")
                    do { try data.write(to: fileURL) } catch {
                        await MainActor.run { manager.finish(id: id) }
                        continue
                    }
                    uploadURL = fileURL
                }

                guard let url = uploadURL else {
                    await MainActor.run { manager.finish(id: id) }
                    continue
                }
                let delegate = UploadProgressDelegate { progress in
                    Task { @MainActor in manager.update(id: id, progress: progress) }
                }
                _ = await api.uploadFile(
                    url: url,
                    albums: albums,
                    privateUpload: priv,
                    stripExif: exif,
                    stripGps: gps,
                    taskDelegate: delegate
                )
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { manager.finish(id: id) }
            }
        }
        manager.register(task: task)
    }

    @MainActor
    private func detachFilesUpload(_ urls: [URL]) {
        let serverURL = server.url
        let token = server.token
        let albums = albumIdParam
        let priv = uploadPrivate
        let exif = stripExif
        let gps = stripGps
        let manager = uploadProgressManager

        let host = URL(string: serverURL)?.host ?? serverURL
        let ids: [UUID] = urls.map { manager.start(filename: $0.lastPathComponent, serverHost: host) }

        let task = Task.detached {
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }
                let id = ids[index]
                if let thumb = Self.thumbnailForFileURL(url) {
                    await MainActor.run { manager.setThumbnail(id: id, image: thumb) }
                }
                let delegate = UploadProgressDelegate { progress in
                    Task { @MainActor in manager.update(id: id, progress: progress) }
                }
                _ = await api.uploadFile(
                    url: url,
                    albums: albums,
                    privateUpload: priv,
                    stripExif: exif,
                    stripGps: gps,
                    taskDelegate: delegate
                )
                await MainActor.run { manager.finish(id: id) }
            }
        }
        manager.register(task: task)
    }

    @MainActor
    private func detachCapturedImageUpload(_ image: UIImage) {
        let serverURL = server.url
        let token = server.token
        let albums = albumIdParam
        let priv = uploadPrivate
        let exif = stripExif
        let gps = stripGps
        let manager = uploadProgressManager

        let host = URL(string: serverURL)?.host ?? serverURL
        let id = manager.start(filename: "ios_photo.jpg", thumbnail: image, serverHost: host)

        let task = Task.detached {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                await MainActor.run { manager.finish(id: id) }
                return
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ios_photo.jpg")
            do {
                try data.write(to: tempURL)
            } catch {
                await MainActor.run { manager.finish(id: id) }
                return
            }
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            let delegate = UploadProgressDelegate { progress in
                Task { @MainActor in manager.update(id: id, progress: progress) }
            }
            _ = await api.uploadFile(
                url: tempURL,
                albums: albums,
                privateUpload: priv,
                stripExif: exif,
                stripGps: gps,
                taskDelegate: delegate
            )
            try? FileManager.default.removeItem(at: tempURL)
            await MainActor.run { manager.finish(id: id) }
        }
        manager.register(task: task)
    }

    nonisolated private static func thumbnailForFileURL(_ url: URL) -> UIImage? {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp"]
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func loadAlbums() async {
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        if let response = try? await api.getAlbums() {
            albums = response.albums
        }
    }
}

private struct RecordingIndicator: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Recording")
                Spacer()
                Text(elapsed(since: startedAt, until: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func elapsed(since start: Date, until end: Date) -> String {
        let s = Int(max(0, end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct AlbumPickerView: View {
    let albums: [DFAlbum]
    @Binding var selected: DFAlbum?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredAlbums: [DFAlbum] {
        guard !searchText.isEmpty else { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Button {
                selected = nil
                dismiss()
            } label: {
                row(title: "None", isSelected: selected == nil)
            }
            ForEach(filteredAlbums) { album in
                Button {
                    selected = album
                    dismiss()
                } label: {
                    row(title: album.name, isSelected: selected?.id == album.id)
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    var onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.onProgress(progress)
        }
    }
}
