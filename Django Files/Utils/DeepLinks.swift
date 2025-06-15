//
//  DeepLinks.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/15/25.
//

import SwiftUI
import SwiftData

class DeepLinks {
    static let shared = DeepLinks()
    private init() {}
    
    func handleDeepLink(_ url: URL, context: ModelContext, sessionManager: SessionManager, previewStateManager: PreviewStateManager, selectedTab: Binding<TabViewWindow.Tab>, hasExistingSessions: Binding<Bool>, showingServerConfirmation: Binding<Bool>, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>) {
        print("Deep link received: \(url)")
        guard url.scheme == "djangofiles" else { return }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("Invalid deep link URL")
            return
        }

        switch components.host {
        case "authorize":
            deepLinkAuth(components, context: context, sessionManager: sessionManager, hasExistingSessions: hasExistingSessions, showingServerConfirmation: showingServerConfirmation, pendingAuthURL: pendingAuthURL, pendingAuthSignature: pendingAuthSignature)
        case "serverlist":
            selectedTab.wrappedValue = .settings
        case "filelist":
            handleFileListDeepLink(components, context: context, sessionManager: sessionManager, selectedTab: selectedTab)
        case "preview":
            handlePreviewLink(components, context: context, sessionManager: sessionManager, previewStateManager: previewStateManager, selectedTab: selectedTab)
        default:
            ToastManager.shared.showToast(message: "Unsupported deep link \(url)")
            print("Unsupported deep link type: \(components.host ?? "unknown")")
        }
    }
    
    private func handlePreviewLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, previewStateManager: PreviewStateManager, selectedTab: Binding<TabViewWindow.Tab>) {
        print("🔍 Handling preview deep link with components: \(components)")

        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString),
              let fileIDString = components.queryItems?.first(where: { $0.name == "file_id" })?.value,
              let fileID = Int(fileIDString),
              let fileName = components.queryItems?.first(where: { $0.name == "file_name" })?.value?.removingPercentEncoding else {
            print("❌ Invalid preview deep link parameters")
            return
        }

        let filePassword = components.queryItems?.first(where: { $0.name == "file_password" })?.value?.removingPercentEncoding

        print("📡 Parsed deep link - Server: \(serverURL), FileID: \(fileID), FileName: \(fileName), HasPassword: \(filePassword != nil)")

        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task {
            do {
                let existingSessions = try context.fetch(descriptor)
                if let session = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    print("✅ Preview link for known server: \(serverURL.absoluteString)")
                    
                    if !session.auth {
                        print("❌ Session is not authenticated")
                        await MainActor.run {
                            ToastManager.shared.showToast(message: "Please log in to view this file")
                            selectedTab.wrappedValue = .settings
                        }
                        return
                    }
    
                    let api = DFAPI(url: serverURL, token: session.token)
                    
                    if let fileDetails = await api.getFileDetails(fileID: fileID, password: filePassword) {
                        if fileDetails.user != session.userID {
                            print("❌ File does not belong to current user")
                            await MainActor.run {
                                selectedTab.wrappedValue = .files
                                previewStateManager.deepLinkFile = fileDetails
                                previewStateManager.showingDeepLinkPreview = true
                                previewStateManager.deepLinkFilePassword = filePassword
                            }
                            return
                        }
    
                        await MainActor.run {
                            sessionManager.selectedSession = session
                            selectedTab.wrappedValue = .files
                            previewStateManager.deepLinkTargetFileID = fileID
                            previewStateManager.deepLinkFilePassword = filePassword
                        }
                    } else {
                        print("❌ Failed to fetch file details")
                        await MainActor.run {
                            ToastManager.shared.showToast(message: "Unable to access file. It may be private or no longer available.")
                        }
                    }
                } else {
                    print("🔑 Preview link for unknown server: \(serverURL.absoluteString)")

                    let api = DFAPI(url: serverURL, token: "")
                    print("🌐 Created API instance for server: \(serverURL)")

                    print("📥 Attempting to fetch file details for ID: \(fileID)")
                    if let fileDetails = await api.getFileDetails(fileID: fileID, password: filePassword) {
                        print("✅ Successfully fetched file details: \(fileDetails.name)")
                        await MainActor.run {
                            print("🎯 Setting up preview view")
                            selectedTab.wrappedValue = .files
                            previewStateManager.deepLinkFile = fileDetails
                            previewStateManager.showingDeepLinkPreview = true
                            previewStateManager.deepLinkFilePassword = filePassword
                            print("🎯 Preview view setup complete")
                        }
                    } else {
                        print("❌ Failed to fetch file details")
                        await MainActor.run {
                            ToastManager.shared.showToast(message: "Unable to access file. It may be private or no longer available.")
                        }
                    }
                }
            } catch {
                print("❌ Error checking for existing sessions: \(error)")
                await MainActor.run {
                    ToastManager.shared.showToast(message: "Error accessing file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleFileListDeepLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, selectedTab: Binding<TabViewWindow.Tab>) {
        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString) else {
            print("Invalid server URL in filelist deep link")
            return
        }

        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task {
            do {
                let existingSessions = try context.fetch(descriptor)
                if let matchingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    await MainActor.run {
                        sessionManager.selectedSession = matchingSession
                        selectedTab.wrappedValue = .files
                    }
                } else {
                    print("No session found for URL: \(serverURL.absoluteString)")
                }
            } catch {
                print("Error fetching sessions: \(error)")
            }
        }
    }
    
    private func deepLinkAuth(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, hasExistingSessions: Binding<Bool>, showingServerConfirmation: Binding<Bool>, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>) {
        guard let signature = components.queryItems?.first(where: { $0.name == "signature" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding ?? "") else {
            print("Unable to parse auth deep link.")
            return
        }

        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task {
            do {
                let existingSessions = try context.fetch(descriptor)
                if let existingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    await MainActor.run {
                        sessionManager.selectedSession = existingSession
                        hasExistingSessions.wrappedValue = true
                        ToastManager.shared.showToast(message: "Connected to existing server \(existingSession.url)")
                    }
                    return
                }
                
                await MainActor.run {
                    pendingAuthURL.wrappedValue = serverURL
                    pendingAuthSignature.wrappedValue = signature
                    showingServerConfirmation.wrappedValue = true
                }
            } catch {
                print("Error checking for existing sessions: \(error)")
            }
        }
    }

    @MainActor func handleServerConfirmation(confirmed: Bool, setAsDefault: Bool, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>, context: ModelContext, sessionManager: SessionManager, hasExistingSessions: Binding<Bool>, selectedTab: Binding<TabViewWindow.Tab>) async {
        guard let serverURL = pendingAuthURL.wrappedValue,
              let signature = pendingAuthSignature.wrappedValue else {
            return
        }

        if !confirmed {
            pendingAuthURL.wrappedValue = nil
            pendingAuthSignature.wrappedValue = nil
            return
        }

        await MainActor.run {
            do {
                let descriptor = FetchDescriptor<DjangoFilesSession>()
                let existingSessions = try context.fetch(descriptor)
                
                Task {
                    if let newSession = await sessionManager.createAndAuthenticateSession(
                        url: serverURL,
                        signature: signature,
                        context: context
                    ) {
                        if setAsDefault {
                            for session in existingSessions {
                                session.defaultSession = false
                            }
                            newSession.defaultSession = true
                        }
                        sessionManager.selectedSession = newSession
                        hasExistingSessions.wrappedValue = true
                        selectedTab.wrappedValue = .files
                        ToastManager.shared.showToast(message: "Successfully logged into \(newSession.url)")
                    }
                }
            } catch {
                ToastManager.shared.showToast(message: "Problem signing into server \(error)")
                print("Error creating new session: \(error)")
            }

            pendingAuthURL.wrappedValue = nil
            pendingAuthSignature.wrappedValue = nil
        }
    }
}

