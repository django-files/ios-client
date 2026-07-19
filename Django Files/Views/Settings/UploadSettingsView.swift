//
//  UploadSettingsView.swift
//  Django Files
//

import SwiftUI

struct UploadSettingsView: View {
    @AppStorage(TusUploadSettings.enabledDefaultsKey, store: TusUploadSettings.store)
    private var tusUploadsEnabled: Bool = true
    @AppStorage(TusUploadSettings.chunkSizeMBDefaultsKey, store: TusUploadSettings.store)
    private var tusChunkSizeMB: Int = TusUploadSettings.defaultChunkSizeMB

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $tusUploadsEnabled) {
                    VStack(alignment: .leading) {
                        Text("Resumable Uploads")
                        Text("Upload large files in resumable chunks when the server supports it. Falls back to a standard upload automatically otherwise.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if tusUploadsEnabled {
                    Picker("Chunk Size", selection: $tusChunkSizeMB) {
                        ForEach(TusUploadSettings.availableChunkSizesMB, id: \.self) { mb in
                            Text("\(mb) MB").tag(mb)
                        }
                    }
                }
            } header: {
                Text("Uploads")
            } footer: {
                Text("Smaller chunks resume more granularly on a flaky connection but take more requests. 40 MB matches the server's default and stays well under most reverse proxies' upload limits.")
            }
        }
        .navigationTitle("Uploads")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        UploadSettingsView()
    }
}
