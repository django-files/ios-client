import SwiftUI
import SwiftData

struct ServerConfirmationView: View {
    @Binding var serverURL: URL?
    @Binding var signature: String?
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void
    let context: ModelContext
    
    @Environment(\.dismiss) private var dismiss
    @State private var siteName: String = "..."
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var setAsDefault = false
    @Query private var existingSessions: [DjangoFilesSession]
    
    var body: some View {
        NavigationView {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading server info...")
                            Spacer()
                        }
                    }
                } else if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                } else {
                    Text(siteName)
                        .font(.headline)
                    Label(serverURL?.absoluteString ?? "", systemImage: "server.rack")
                    Text("Please confirm that you wish to sign into \(serverURL?.absoluteString ?? "unknown") instance of Django Files.")
                    if existingSessions.count > 0 {
                        Section {
                            Toggle("Set as default server", isOn: $setAsDefault)
                        }
                    }
                }
            }
            .navigationTitle("Sign into \(siteName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign In") {
                        onConfirm(setAsDefault)
                        dismiss()
                    }
                    .disabled(isLoading || error != nil)
                }
            }
            .onAppear {
                Task {
                    await loadServerInfo()
                }
            }
        }
    }
    
    private func loadServerInfo() async {
        guard let url = serverURL else {
            await MainActor.run {
                error = "QR Code or Link has invalid or unreachable server."
                isLoading = false
            }
            return
        }
        
        let api = DFAPI(url: url, token: "")
        if let authMethods = await api.getAuthMethods() {
            await MainActor.run {
                siteName = authMethods.siteName
                isLoading = false
            }
        } else {
            await MainActor.run {
                error = "Could not connect to server"
                isLoading = false
            }
        }
    }
}

#Preview("Loading State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DjangoFilesSession.self, configurations: config)
    
    return ServerConfirmationView(
        serverURL: .constant(URL(string: "http://localhost")!),
        signature: .constant("test"),
        onConfirm: { _ in },
        onCancel: {},
        context: container.mainContext
    )
}

#Preview("Error State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DjangoFilesSession.self, configurations: config)
    
    return ServerConfirmationView(
        serverURL: .constant(nil),
        signature: .constant("test"),
        onConfirm: { _ in },
        onCancel: {},
        context: container.mainContext
    )
}

#Preview("Success State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DjangoFilesSession.self, configurations: config)
    
    return ServerConfirmationView(
        serverURL: .constant(URL(string: "http://localhost")!),
        signature: .constant("test"),
        onConfirm: { _ in },
        onCancel: {},
        context: container.mainContext
    )
}

