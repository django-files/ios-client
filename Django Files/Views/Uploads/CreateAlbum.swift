//
//  CreateAlbum.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/20/25.
//

import SwiftUI

struct CreateAlbumView: View {
    let server: DjangoFilesSession
    @Environment(\.dismiss) private var dismiss
    
    @State private var albumName = ""
    @State private var isPrivate = false
    @State private var password = ""
    @State private var maxViews = ""
    @State private var expiration = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Album Details")) {
                    TextField("Album Name", text: $albumName)
                    Toggle("Private", isOn: $isPrivate)
                }
                
                Section(header: Text("Security (Optional)")) {
                    TextField("Password", text: $password)
                    TextField("Max Views", text: $maxViews)
                        .keyboardType(.numberPad)
                    TextField("Expiration (e.g., 1h, 5days, 2y)", text: $expiration)
                }
                
                Section(header: Text("Additional Info")) {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await createAlbum()
                        }
                    }
                    .disabled(albumName.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createAlbum() async {
        isCreating = true
        errorMessage = nil
        
        guard let url = URL(string: server.url) else {
            errorMessage = "Invalid server URL"
            isCreating = false
            return
        }
        
        let api = DFAPI(url: url, token: server.token)
        
        let maxViewsInt = Int(maxViews)
        
        if let _ = await api.createAlbum(
            name: albumName,
            maxViews: maxViewsInt,
            expiration: expiration.isEmpty ? nil : expiration,
            password: password.isEmpty ? nil : password,
            isPrivate: isPrivate,
            description: description.isEmpty ? nil : description,
            selectedServer: server
        ) {
            // Album created successfully
            await MainActor.run {
                isCreating = false
                dismiss()
            }
        } else {
            await MainActor.run {
                errorMessage = "Failed to create album"
                isCreating = false
            }
        }
    }
}

