//
//  SessionEditor.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import SwiftUI
import SwiftData

struct SessionEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [DjangoFilesSession]
    
    let session: DjangoFilesSession?
    
    private var editorTitle: String {
        session == nil ? "Add Server" : "Edit Server"
    }
    
    private func save() {
        if let session {
            session.url = url?.absoluteString ?? ""
            session.token = token
            session.auth = false
        } else {
            let session = DjangoFilesSession ()
            session.url = url?.absoluteString ?? ""
            for item in items{
                item.defaultSession = false
            }
            session.defaultSession = true
            session.token = token
            session.auth = false
            modelContext.insert(session)
            do {
                try modelContext.save()
            } catch {
                
            }
        }
    }
    
    @State private var url: URL? = nil
    @State private var token: String = ""
    @State private var badURL = false
    @State private var insecureURL = false
    
    
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent{
                    TextField("https://df.myserver.com", text: Binding(
                        get: {
                            if url?.scheme == nil || url?.scheme == ""{
                                return ""
                            }
                            return url?.absoluteString ?? ""
                        },
                        set: {
                            let temp = URL(string: $0)
                            if temp?.scheme != nil && temp?.scheme != ""{
                                url = temp
                                if (url?.scheme?.lowercased()) == ("http"){
                                    insecureURL = true
                                } else {
                                    insecureURL = false
                                }
                            }
                        }
                    ))
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("URL:")
                }
                if insecureURL {
                    let warningMessage = "⚠️ We strongly recommend using HTTPS."
                    TextField("", text: Binding(
                            get: { warningMessage },
                            set: { _ in } // Prevents user from modifying the text
                        ))
                        .disabled(true) // Prevents user input
                        .foregroundColor(.red)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(editorTitle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action:{
                        if url != nil
                        {
                            withAnimation {
                                save()
                                dismiss()
                            }
                        }
                        else{
                            badURL.toggle()
                        }
                    })
                    {
                        Text("Add Session")
                    }
                    .alert(isPresented: $badURL){
                        Alert(title: Text("Invalid URL"), message: Text("Invalid URL format or scheme (http or https).\nExample: https://df.myserver.com"))
                    }
                }
                if items.count > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let session {
                    // Edit the incoming animal.
                    url = URL(string: session.url)
                }
            }
        }
    }
}
