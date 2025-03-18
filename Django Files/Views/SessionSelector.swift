//
//  SessionSelector.swift
//  Django Files
//
//  Created by Michael on 2/15/25.
//

import SwiftUI
import SwiftData
import AuthenticationServices

struct SessionSelector: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [DjangoFilesSession]
    
    let session: DjangoFilesSession
    
    var viewingSelect: Binding<Bool>? = nil
    
    @State private var url = ""
    @State private var token = ""
    @State private var sessionStarted = false
    @State private var defaultSession = false
    
    @State private var showTokenCopiedAlert = false
    @State private var showURLCopiedAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent{
                    Text(url)
                        .contentShape(Rectangle())
                        .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = token
                                }) {
                                    Text("Copy to clipboard")
                                    Image(systemName: "doc.on.doc")
                                }
                             }
                        .onTapGesture {
                            UIPasteboard.general.string = token
                            showURLCopiedAlert = true
                        }
                        .alert(isPresented: $showURLCopiedAlert){
                            Alert(title: Text("URL Copied"), message: Text("Server URL copied to clipboard"))
                        }
                } label: {
                    Text("URL:")
                }
                LabeledContent{
                    SecureField("", text: $token)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .disabled(true)
                        .contentShape(Rectangle())
                        .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = token
                                }) {
                                    Text("Copy to clipboard")
                                    Image(systemName: "doc.on.doc")
                                }
                             }
                        .onTapGesture {
                            UIPasteboard.general.string = token
                            showTokenCopiedAlert = true
                        }
                        .alert(isPresented: $showTokenCopiedAlert){
                            Alert(title: Text("Token Copied"), message: Text("Token copied to clipboard"))
                        }
                } label: {
                    Text("Token:")
                }
                Toggle("Default:", isOn: $defaultSession)
                    .onChange(of: defaultSession) {
                        if !session.auth{
                            defaultSession = false
                            return
                        }
                        if defaultSession{
                            for item in items{
                                item.defaultSession = false
                            }
                            session.defaultSession = true
                        }
                        else{
                            session.defaultSession = false
                            var any: Bool = false
                            for item in items{
                                any = any || item.defaultSession
                            }
                            if !any{
                                session.defaultSession = true
                                defaultSession = true
                            }
                        }
                    }
                LabeledContent{
                    Text(session.auth ? "Success" : "Failure")
                } label: {
                    Text("Auth Status:")
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Server Options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back") {
                        if viewingSelect == nil{
                            dismiss()
                        }
                        else{
                            viewingSelect?.wrappedValue = false
                        }
                    }
                }
            }
            .onAppear {
                url = session.url
                defaultSession = session.defaultSession
                token = session.token
                
            }
        }
    }
}
