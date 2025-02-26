//
//  SessionEditor.swift
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
    
    @State private var url = ""
    @State private var token = ""
    @State private var sessionStarted = false
    @State private var defaultSession = false
    
    private func tryAuth() async -> Bool{
        guard let dfUrl = URL(string: url) else {
            return false
        }
        let stats = await DFAPI(url: dfUrl, token: token).getStats(amount: nil)
        if stats == nil {
            session.auth = false
            return false
        }
        else{
            session.auth = true
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent{
                    Text(url)
                } label: {
                    Text("URL:")
                }
                LabeledContent{
                    SecureField("", text: $token)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: token){
                            session.token = token
                        }
                } label: {
                    Text("Token:")
                }
                Toggle("Default:", isOn: $defaultSession)
                    .onChange(of: defaultSession) {
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
                Button("Try Auth"){
                    Task{
                        _ = await tryAuth()
                        do {
                            try modelContext.save()
                        } catch {
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Select Session")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                url = session.url
                defaultSession = session.defaultSession
                token = session.token
                
                if token != ""{
                    Task{
                        
                        _ = await tryAuth()
                    }
                }
            }
        }
    }
}
