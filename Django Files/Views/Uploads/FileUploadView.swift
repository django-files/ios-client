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
    var onUploadComplete: (() async -> Void)? = nil

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

    @State private var isUploading = false
    @State private var uploadProgress: Double = 0

    private var useAccessoryProgress: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

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
            if isUploading && !useAccessoryProgress {
                Section {
                    ProgressView(value: uploadProgress) { Text("Uploading…") }
                }
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
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
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
        if useAccessoryProgress {
            detachCapturedImageUpload(image)
            dismiss()
        } else {
            Task { await uploadCapturedImageInline(image) }
        }
    }

    private func startPhotosUpload(_ items: [PhotosPickerItem]) {
        if useAccessoryProgress {
            detachPhotosUpload(items)
            dismiss()
        } else {
            Task { await uploadPhotosInline(items) }
        }
    }

    private func startFilesUpload(_ urls: [URL]) {
        if useAccessoryProgress {
            detachFilesUpload(urls)
            dismiss()
        } else {
            Task { await uploadFilesInline(urls) }
        }
    }

    // MARK: - Inline upload (iOS < 26 fallback)

    private func uploadCapturedImageInline(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.8),
              let tempURL = saveTemporaryFile(data: data, filename: "ios_photo.jpg") else { return }
        isUploading = true
        uploadProgress = 0
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let delegate = UploadProgressDelegate { uploadProgress = $0 }
        _ = await api.uploadFile(
            url: tempURL,
            albums: albumIdParam,
            privateUpload: uploadPrivate,
            stripExif: stripExif,
            stripGps: stripGps,
            taskDelegate: delegate
        )
        try? FileManager.default.removeItem(at: tempURL)
        isUploading = false
        await onUploadComplete?()
        dismiss()
    }

    private func uploadPhotosInline(_ items: [PhotosPickerItem]) async {
        isUploading = true
        uploadProgress = 0
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let total = Double(items.count)
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let tempURL = saveTemporaryFile(data: data, filename: "photo_\(index).jpg") else { continue }
            let delegate = UploadProgressDelegate { progress in
                uploadProgress = (Double(index) + progress) / total
            }
            _ = await api.uploadFile(
                url: tempURL,
                albums: albumIdParam,
                privateUpload: uploadPrivate,
                stripExif: stripExif,
                stripGps: stripGps,
                taskDelegate: delegate
            )
            try? FileManager.default.removeItem(at: tempURL)
        }
        isUploading = false
        await onUploadComplete?()
        dismiss()
    }

    private func uploadFilesInline(_ urls: [URL]) async {
        isUploading = true
        uploadProgress = 0
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let total = Double(urls.count)
        for (index, url) in urls.enumerated() {
            let delegate = UploadProgressDelegate { progress in
                uploadProgress = (Double(index) + progress) / total
            }
            _ = await api.uploadFile(
                url: url,
                albums: albumIdParam,
                privateUpload: uploadPrivate,
                stripExif: stripExif,
                stripGps: stripGps,
                taskDelegate: delegate
            )
        }
        isUploading = false
        await onUploadComplete?()
        dismiss()
    }

    private func uploadAudioInline(_ url: URL) async {
        isUploading = true
        uploadProgress = 0
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let delegate = UploadProgressDelegate { uploadProgress = $0 }
        _ = await api.uploadFile(
            url: url,
            albums: albumIdParam,
            privateUpload: uploadPrivate,
            stripExif: stripExif,
            stripGps: stripGps,
            taskDelegate: delegate
        )
        try? FileManager.default.removeItem(at: url)
        isUploading = false
        await onUploadComplete?()
        dismiss()
    }

    private var albumIdParam: String {
        selectedAlbum.map { String($0.id) } ?? ""
    }

    private func saveTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            ToastManager.shared.showToast(message: "Could not save file: \(error.localizedDescription)")
            return nil
        }
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
        if useAccessoryProgress {
            detachSingleFileUpload(tempURL: url, displayName: "recording.m4a", deleteAfter: true)
            dismiss()
        } else {
            Task { await uploadAudioInline(url) }
        }
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
        let completion = onUploadComplete

        let id = manager.start(filename: displayName, thumbnail: thumbnail)
        Task.detached {
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
            if let completion { await completion() }
        }
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
        let completion = onUploadComplete

        let ids: [UUID] = (0..<items.count).map { index in
            manager.start(filename: "photo_\(index).jpg")
        }

        Task.detached {
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            for (index, item) in items.enumerated() {
                let id = ids[index]
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    await MainActor.run { manager.finish(id: id) }
                    continue
                }
                if let image = UIImage(data: data) {
                    await MainActor.run { manager.setThumbnail(id: id, image: image) }
                }
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(index).jpg")
                do { try data.write(to: tempURL) } catch {
                    await MainActor.run { manager.finish(id: id) }
                    continue
                }
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
            if let completion { await completion() }
        }
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
        let completion = onUploadComplete

        let ids: [UUID] = urls.map { manager.start(filename: $0.lastPathComponent) }

        Task.detached {
            let api = DFAPI(url: URL(string: serverURL)!, token: token)
            for (index, url) in urls.enumerated() {
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
            if let completion { await completion() }
        }
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
        let completion = onUploadComplete

        let id = manager.start(filename: "ios_photo.jpg", thumbnail: image)

        Task.detached {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                await MainActor.run { manager.finish(id: id) }
                if let completion { await completion() }
                return
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ios_photo.jpg")
            do {
                try data.write(to: tempURL)
            } catch {
                await MainActor.run { manager.finish(id: id) }
                if let completion { await completion() }
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
            if let completion { await completion() }
        }
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
