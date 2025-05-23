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

struct FileUploadView: View {
    let server: DjangoFilesSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedFiles: [URL] = []
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var showingFilePicker: Bool = false
    @State private var showingCamera: Bool = false
    @State private var capturedImage: UIImage?
    
    @State private var uploadPrivate: Bool = false
    
    // Album selection states
    @State private var albums: [DFAlbum] = []
    @State private var searchText: String = ""
    @State private var selectedAlbum: DFAlbum?
    @State private var isLoadingAlbums: Bool = false
    @FocusState private var isSearchFocused: Bool
    
    // Audio recording states
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording: Bool = false
    @State private var recordingURL: URL?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Toggle("Make Private", isOn: $uploadPrivate)
                
                // Album Selection
                VStack(alignment: .leading) {
                    TextField("Search Albums", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isSearchFocused)
                        .onChange(of: searchText) { _, _ in
                            if searchText.isEmpty {
                                selectedAlbum = nil
                            }
                        }
                    
                    if !searchText.isEmpty && (isSearchFocused || selectedAlbum == nil) {
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(albums.filter { album in
                                    album.name.localizedCaseInsensitiveContains(searchText)
                                }) { album in
                                    Button(action: {
                                        selectedAlbum = album
                                        searchText = album.name
                                        isSearchFocused = false
                                    }) {
                                        Text(album.name)
                                            .foregroundColor(.primary)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    }
                    
                    if let album = selectedAlbum {
                        HStack {
                            Text("Selected Album: \(album.name)")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                selectedAlbum = nil
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Audio Recording Button
                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    Label(isRecording ? "Stop Recording" : "Record Audio", systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRecording ? Color.red : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                // Camera Button
                Button(action: {
                    showingCamera = true
                }) {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                // Photo Picker
                PhotosPicker(
                    selection: $selectedItems,
                    matching: .images,
                    photoLibrary: .shared()) {
                        Label("Select Photos", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                
                // Document Picker Button
                Button(action: {
                    showingFilePicker = true
                }) {
                    Label("Select Files", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                if isUploading {
                    ProgressView(value: uploadProgress) {
                        Text("Uploading...")
                    }
                }
            }
            .padding()
            .navigationTitle("Upload Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    Task {
                        await uploadCapturedImage(image)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    selectedFiles = urls
                    Task {
                        await uploadFiles(urls)
                    }
                case .failure(let error):
                    print("Error selecting files: \(error.localizedDescription)")
                }
            }
            .onChange(of: selectedItems) { _, newValue in
                Task {
                    await uploadPhotos(newValue)
                }
            }
            .task {
                await loadAlbums()
            }
        }
    }
    
    private func uploadCapturedImage(_ image: UIImage) async {
        isUploading = true
        uploadProgress = 0.0
        
        if let imageData = image.jpegData(compressionQuality: 0.8),
           let tempURL = saveTemporaryFile(data: imageData, filename: "ios_photo.jpg") {
            let api = DFAPI(url: URL(string: server.url)!, token: server.token)
            let delegate = UploadProgressDelegate { progress in
                uploadProgress = progress
            }
            
            if let albumId = selectedAlbum?.id {
                _ = await api.uploadFile(url: tempURL, albums: String(albumId), privateUpload: uploadPrivate, taskDelegate: delegate)
            } else {
                _ = await api.uploadFile(url: tempURL, privateUpload: uploadPrivate, taskDelegate: delegate)
            }
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        isUploading = false
        capturedImage = nil
        dismiss()
    }
    
    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        isUploading = true
        uploadProgress = 0.0
        
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let totalItems = Double(items.count)
        
        for (index, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let tempURL = saveTemporaryFile(data: data, filename: "photo_\(index).jpg") {
                let delegate = UploadProgressDelegate { progress in
                    uploadProgress = (Double(index) + progress) / totalItems
                }
                
                if let albumId = selectedAlbum?.id {
                    _ = await api.uploadFile(url: tempURL, albums: String(albumId), privateUpload: uploadPrivate, taskDelegate: delegate)
                } else {
                    _ = await api.uploadFile(url: tempURL, privateUpload: uploadPrivate, taskDelegate: delegate)
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        isUploading = false
        dismiss()
    }
    
    private func uploadFiles(_ urls: [URL]) async {
        isUploading = true
        uploadProgress = 0.0
        
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let totalFiles = Double(urls.count)
        
        for (index, url) in urls.enumerated() {
            let delegate = UploadProgressDelegate { progress in
                uploadProgress = (Double(index) + progress) / totalFiles
            }
            
            if let albumId = selectedAlbum?.id {
                _ = await api.uploadFile(url: url, albums: String(albumId), privateUpload: uploadPrivate, taskDelegate: delegate)
            } else {
                _ = await api.uploadFile(url: url, privateUpload: uploadPrivate, taskDelegate: delegate)
            }
        }
        
        isUploading = false
        dismiss()
    }
    
    private func saveTemporaryFile(data: Data, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error saving temporary file: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let documentsPath = FileManager.default.temporaryDirectory
            let audioFilename = documentsPath.appendingPathComponent("recording.m4a")
            recordingURL = audioFilename
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Recording failed: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        if let url = recordingURL {
            Task {
                await uploadAudioRecording(url)
            }
        }
    }
    
    private func uploadAudioRecording(_ url: URL) async {
        isUploading = true
        uploadProgress = 0.0
        
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        let delegate = UploadProgressDelegate { progress in
            uploadProgress = progress
        }
        
        if let albumId = selectedAlbum?.id {
            _ = await api.uploadFile(url: url, albums: String(albumId), privateUpload: uploadPrivate, taskDelegate: delegate)
        } else {
            _ = await api.uploadFile(url: url, privateUpload: uploadPrivate, taskDelegate: delegate)
        }
        try? FileManager.default.removeItem(at: url)
        
        isUploading = false
        recordingURL = nil
        dismiss()
    }
    
    private func loadAlbums() async {
        isLoadingAlbums = true
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        if let response = await api.getAlbums() {
            albums = response.albums
        }
        isLoadingAlbums = false
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
