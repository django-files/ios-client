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
    
    @State private var showLoginSheet: Bool = false
    @State private var newSession: DjangoFilesSession?
    
    let session: DjangoFilesSession?
    var onSessionCreated: ((DjangoFilesSession) -> Void)?
    
    private var editorTitle: String {
        session == nil ? "Add Server" : "Edit Server"
    }
    
    @State private var showDuplicateAlert = false
    
    private func checkURLAuthAndSave() {
        if let session {
            session.url = url?.absoluteString ?? ""
            session.token = token
            session.auth = false
        } else {
            if items.contains(where: { $0.url == url?.absoluteString }) {
                showDuplicateAlert = true
                return
            }
            newSession = DjangoFilesSession()
            newSession!.url = url?.absoluteString ?? ""
            newSession!.token = token
            newSession!.auth = false
            modelContext.insert(newSession!)
            showLoginSheet = true
        }
    }
    
    @State private var url: URL? = nil
    @State private var token: String = ""
    @State private var badURL = false
    @State private var insecureURL = false
    
    @FocusState private var isURLFieldFocused: Bool
    
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Server URL")) {
                    TextField("", text: Binding(
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
                                insecureURL = (url?.scheme?.lowercased()) == ("http")
                            }
                        }
                    ), prompt: Text(verbatim: "https://df.example.com"))
                    .focused($isURLFieldFocused)
                    .onChange(of: isURLFieldFocused) { wasFocused, isFocused in
                        if isFocused && url == nil {
                            url = URL(string: "https://")
                        }
                    }
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("urlTextField")
                    .keyboardType(.URL)
                }
                if insecureURL {
                    let warningMessage = "⚠️ HTTPS strongly recommend."
                    TextField("", text: Binding(
                            get: { warningMessage },
                            set: { _ in } // Prevents user from modifying the text
                        ))
                        .disabled(true) // Prevents user input
                        .foregroundColor(.red)
                }
            }
            .padding(.top, -40)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(editorTitle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action:{
                        if var urlString = url?.absoluteString {
                            if urlString.hasSuffix("/") {
                                urlString.removeLast()
                                url = URL(string: urlString)
                            }
                        }
                        if url != nil {
                            withAnimation {
                                checkURLAuthAndSave()
                            }
                        } else {
                            badURL.toggle()
                        }
                    })
                    {
                        Text("Save")
                    }
                    .accessibilityIdentifier("serverSubmitButton")
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
            .alert(isPresented: $showDuplicateAlert) {
                Alert(
                    title: Text("Duplicate URL"),
                    message: Text("A session with this URL already exists."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showLoginSheet, onDismiss: {
                if let newSession = newSession, newSession.auth {
                    do {
                        try modelContext.save()
                        onSessionCreated?(newSession)
                        dismiss()
                    } catch {
                        print("Error saving session: \(error)")
                    }
                }
            }) {
                if let newSession = newSession {
                    LoginView(selectedServer: newSession, onLoginSuccess: {
                        newSession.auth = true
                    })
                } else if let session = session {
                    LoginView(selectedServer: session, onLoginSuccess: {
                        session.auth = true
                    })
                }
            }
        }
    }
}
