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
        } else {
            let session = DjangoFilesSession ()
            session.url = url?.absoluteString ?? ""
            for item in items{
                item.defaultSession = false
            }
            session.defaultSession = true
            session.token = token
            modelContext.insert(session)
        }
    }
    
    @State private var url: URL? = nil
    @State private var token: String = ""
    @State private var badURL = false

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent{
                    TextField("https://df.myserver.com", text: Binding(
                        get: { url?.absoluteString ?? "" },
                        set: { url = URL(string: $0) }
                    ))
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("URL:")
                }
                LabeledContent{
                    TextField("", text: Binding(
                        get: { token.count == 32 ? token : "" },
                        set: { token = $0 }
                    ))
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("Token:")
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
                        Alert(title: Text("Invalid URL"))
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
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

struct SessionEditor_Preview: PreviewProvider {
    static var previews: some View {
        SessionEditor(session: DjangoFilesSession(url: "https://d.luac.es"))
    }
}
