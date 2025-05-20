//
//  CreateShort.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/20/25.
//

import SwiftUI

struct ShortCreatorView: View {
    let server: DjangoFilesSession
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = ""
    @State private var vanityPath: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("URL to shorten", text: $url)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    TextField("Vanity path (optional)", text: $vanityPath)
                        .autocapitalization(.none)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Short")
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
                            await submitShort()
                        }
                    }
                    .disabled(url.isEmpty || isSubmitting)
                }
            }
        }
    }
    
    private func submitShort() async {
        isSubmitting = true
        errorMessage = nil
        
        guard let urlObj = URL(string: url) else {
            errorMessage = "Invalid URL format"
            isSubmitting = false
            return
        }
        
        let api = DFAPI(url: URL(string: server.url)!, token: server.token)
        if let response = await api.createShort(url: urlObj, short: vanityPath) {
            // Success - close the sheet
            dismiss()
        } else {
            errorMessage = "Failed to create short URL"
        }
        
        isSubmitting = false
    }
}
