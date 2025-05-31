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
    @State private var tempSession: DjangoFilesSession?
    
    let onBoarding: Bool
    let session: DjangoFilesSession?
    var onSessionCreated: ((DjangoFilesSession) -> Void)?

    private var editorTitle: String {
        session == nil ? "Add Server" : "Edit Server"
    }
    
    @State private var showDuplicateAlert = false
    
    @State private var url: URL? = nil
    @State private var token: String = ""
    @State private var badURL: Bool = false
    @State private var insecureURL: Bool = false
    @State private var isCheckingServer: Bool = false
    @State private var serverError: String? = nil
    
    @FocusState private var isURLFieldFocused: Bool
    
    private func checkURLAuthAndSave() {
        Task {
            isCheckingServer = true
            serverError = nil
            
            // Create a temporary DFAPI instance to check auth methods
            let api = DFAPI(url: url!, token: "")
            if let _ = await api.getAuthMethods() {
                isCheckingServer = false
                
                // Server is valid, proceed with login
                if let session {
                    // For editing, update the URL and clear auth
                    session.url = url?.absoluteString ?? ""
                    session.token = token
                    session.auth = false
                    showLoginSheet = true
                } else {
                    if items.contains(where: { $0.url == url?.absoluteString }) {
                        showDuplicateAlert = true
                        return
                    }
                    // Create temporary session but don't save it yet
                    tempSession = DjangoFilesSession()
                    tempSession!.url = url?.absoluteString ?? ""
                    tempSession!.token = token
                    tempSession!.auth = false
                    showLoginSheet = true
                }
            } else {
                isCheckingServer = false
                serverError = "Could not connect to server or server is not a Django Files instance"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if onBoarding {
                    HStack {
                        Spacer()
                        Label("", systemImage: "hand.wave.fill")
                            .font(.system(size: 50))
                            .padding(.bottom)
                            .shadow(color: .purple, radius: 20)
                            .listRowSeparator(.hidden)
                        Spacer()
                    }
                    Text("Welcome to Django Files!")
                        .font(.system(size: 25))
                        .padding(.bottom)
                        .shadow(color: .purple, radius: 20)
                        .listRowSeparator(.hidden)
                    Text("Thanks for using our iOS app! If you don’t have a server set up yet, check out our GitHub README to get started.")
                        .listRowSeparator(.hidden)
                    Text("https://github.com/django-files/django-files")
                        .listRowSeparator(.hidden)
                }
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
                                serverError = nil
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
                            set: { _ in }
                        ))
                        .disabled(true)
                        .foregroundColor(.red)
                }
                if let error = serverError {
                    Text("❌ " + error)
                        .disabled(true)
                        .foregroundColor(.red)
                }
                if isCheckingServer {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Checking server...")
                    }
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
                    .disabled(isCheckingServer)
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
                if let session = session {
                    if session.auth {
                        try? modelContext.save()
                        dismiss()
                    }
                } else if let tempSession = tempSession, tempSession.auth {
                    modelContext.insert(tempSession)
                    try? modelContext.save()
                    onSessionCreated?(tempSession)
                    dismiss()
                }
            }) {
                if let session = session {
                    LoginView(selectedServer: session, onLoginSuccess: {
                        session.auth = true
                    })
                } else if let tempSession = tempSession {
                    LoginView(selectedServer: tempSession, onLoginSuccess: {
                        tempSession.auth = true
                    })
                }
            }
        }
        .scrollDisabled(true)
    }
}
