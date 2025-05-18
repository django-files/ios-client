//
//  FileUploadView.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/18/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct FileUploadView: View {
    let server: DjangoFilesSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedFiles: [URL] = []
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var showingFilePicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
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
        }
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
                
                _ = await api.uploadFile(url: tempURL, taskDelegate: delegate)
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
            
            _ = await api.uploadFile(url: url, taskDelegate: delegate)
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
