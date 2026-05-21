//
//  NewStreamView.swift
//  Django Files
//

import SwiftUI

private struct BroadcastConfig: Identifiable {
    let id = UUID()
    let streamKey: String
    let title: String
    let description: String
}

struct NewStreamView: View {
    let server: DjangoFilesSession
    @Environment(\.dismiss) private var dismiss

    @State private var streamKey: String = ""
    @State private var streamTitle: String = ""
    @State private var streamDescription: String = ""
    @State private var broadcastConfig: BroadcastConfig?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("my-stream", text: $streamKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Stream Name")
                } footer: {
                    Text("The URL slug for your stream — viewers watch at \(server.url)/live/<name>/")
                }

                Section("Info (optional)") {
                    TextField("Title", text: $streamTitle)
                    TextField("Description", text: $streamDescription, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                }
            }
            .navigationTitle("New Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        broadcastConfig = BroadcastConfig(
                            streamKey: streamKey.trimmingCharacters(in: .whitespaces),
                            title: streamTitle,
                            description: streamDescription
                        )
                    }
                    .disabled(streamKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .fullScreenCover(item: $broadcastConfig) { config in
            if let serverURL = URL(string: server.url) {
                StreamBroadcastView(
                    serverURL: serverURL,
                    streamName: config.streamKey,
                    token: server.token,
                    streamTitle: config.title,
                    streamDescription: config.description,
                    ownerUsername: server.username ?? ""
                )
                .onDisappear { dismiss() }
            }
        }
    }

}
