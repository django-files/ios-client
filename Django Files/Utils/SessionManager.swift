//
//  SessionManager.swift
//  Django Files
//
//  Created by Ralph Luaces on 5/29/25.
//

import SwiftUI
import SwiftData

class SessionManager: ObservableObject {
    @Published var selectedSession: DjangoFilesSession?
    private let userDefaultsKey = "lastSelectedSessionURL"
    
    func saveSelectedSession() {
        if let session = selectedSession {
            UserDefaults.standard.set(session.url, forKey: userDefaultsKey)
        }
    }
    
    func createAndAuthenticateSession(url: URL, signature: String, context: ModelContext) async -> DjangoFilesSession? {
        let serverURL = "\(url.scheme ?? "https")://\(url.host ?? "")"
        let newSession = DjangoFilesSession(url: serverURL)
        
        let api = DFAPI(url: URL(string: serverURL)!, token: "")
        
        // Get token using the signature
        if let token = await api.applicationAuth(signature: signature, selectedServer: newSession) {
            newSession.token = token
            newSession.auth = true
            
            // Save the session
            context.insert(newSession)
            try? context.save()
            
            return newSession
        }
        
        return nil
    }
    
    func loadLastSelectedSession(from sessions: [DjangoFilesSession]) {
        if selectedSession != nil { return }
        
        if let lastSessionURL = UserDefaults.standard.string(forKey: userDefaultsKey) {
            selectedSession = sessions.first(where: { $0.url == lastSessionURL })
        } else if let defaultSession = sessions.first(where: { $0.defaultSession }) {
            selectedSession = defaultSession
        } else if let firstSession = sessions.first {
            selectedSession = firstSession
        }
    }
    
}
