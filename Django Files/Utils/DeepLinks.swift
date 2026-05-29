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
    
    @MainActor func handleDeepLink(_ url: URL, context: ModelContext, sessionManager: SessionManager, previewStateManager: PreviewStateManager, streamStateManager: StreamStateManager, albumStateManager: AlbumStateManager, selectedTab: Binding<TabViewWindow.Tab>, hasExistingSessions: Binding<Bool>, showingServerConfirmation: Binding<Bool>, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>) {
        print("Deep link received: \(url)")
        guard url.scheme == "djangofiles" else { return }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("Invalid deep link URL")
            return
        }

        let kind: DFAnalytics.DeepLinkKind = {
            switch components.host {
            case "authorize": return .auth
            case "serverlist": return .serverList
            case "filelist": return .fileList
            case "preview": return .preview
            case "stream": return .stream
            case "album": return .album
            default: return .unknown
            }
        }()
        DFAnalytics.logDeepLinkOpened(kind: kind)

        switch components.host {
        case "authorize":
            deepLinkAuth(components, context: context, sessionManager: sessionManager, hasExistingSessions: hasExistingSessions, showingServerConfirmation: showingServerConfirmation, pendingAuthURL: pendingAuthURL, pendingAuthSignature: pendingAuthSignature)
        case "serverlist":
            selectedTab.wrappedValue = .settings
        case "filelist":
            handleFileListDeepLink(components, context: context, sessionManager: sessionManager, selectedTab: selectedTab)
        case "preview":
            handlePreviewLink(components, context: context, sessionManager: sessionManager, previewStateManager: previewStateManager, selectedTab: selectedTab)
        case "stream":
            handleStreamLink(components, context: context, sessionManager: sessionManager, streamStateManager: streamStateManager, selectedTab: selectedTab)
        case "album":
            handleAlbumLink(components, context: context, sessionManager: sessionManager, albumStateManager: albumStateManager, selectedTab: selectedTab)
        default:
            ToastManager.shared.showToast(message: "Unsupported deep link \(url)")
            print("Unsupported deep link type: \(components.host ?? "unknown")")
        }
    }
    
    @MainActor private func handlePreviewLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, previewStateManager: PreviewStateManager, selectedTab: Binding<TabViewWindow.Tab>) {
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

        Task { @MainActor in
            do {
                let existingSessions = try context.fetch(descriptor)
                if let session = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    print("✅ Preview link for known server: \(serverURL.absoluteString)")

                    if !session.auth {
                        print("❌ Session is not authenticated")
                        ToastManager.shared.showToast(message: "Please log in to view this file")
                        selectedTab.wrappedValue = .settings
                        return
                    }

                    let api = DFAPI(url: serverURL, token: session.token)

                    if let fileDetails = await api.getFileDetails(fileID: fileID, password: filePassword) {
                        if fileDetails.user != session.userID {
                            print("❌ File does not belong to current user")
                            selectedTab.wrappedValue = .files
                            previewStateManager.deepLinkFile = fileDetails
                            previewStateManager.showingDeepLinkPreview = true
                            previewStateManager.deepLinkFilePassword = filePassword
                            return
                        }

                        sessionManager.selectedSession = session
                        selectedTab.wrappedValue = .files
                        previewStateManager.deepLinkTargetFileID = fileID
                        previewStateManager.deepLinkFilePassword = filePassword
                    } else {
                        print("❌ Failed to fetch file details")
                        ToastManager.shared.showToast(message: "Unable to access file. It may be private or no longer available.")
                    }
                } else {
                    print("🔑 Preview link for unknown server: \(serverURL.absoluteString)")

                    let api = DFAPI(url: serverURL, token: "")
                    print("🌐 Created API instance for server: \(serverURL)")

                    print("📥 Attempting to fetch file details for ID: \(fileID)")
                    if let fileDetails = await api.getFileDetails(fileID: fileID, password: filePassword) {
                        print("✅ Successfully fetched file details: \(fileDetails.name)")
                        print("🎯 Setting up preview view")
                        selectedTab.wrappedValue = .files
                        previewStateManager.deepLinkFile = fileDetails
                        previewStateManager.showingDeepLinkPreview = true
                        previewStateManager.deepLinkFilePassword = filePassword
                        print("🎯 Preview view setup complete")
                    } else {
                        print("❌ Failed to fetch file details")
                        ToastManager.shared.showToast(message: "Unable to access file. It may be private or no longer available.")
                    }
                }
            } catch {
                print("❌ Error checking for existing sessions: \(error)")
                ToastManager.shared.showToast(message: "Error accessing file: \(error.localizedDescription)")
            }
        }
    }
    
    /// Deep link: `djangofiles://stream/?url=<server_url>&name=<stream_name>&password=<optional>`
    @MainActor private func handleStreamLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, streamStateManager: StreamStateManager, selectedTab: Binding<TabViewWindow.Tab>) {
        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString),
              let streamName = components.queryItems?.first(where: { $0.name == "name" })?.value?.removingPercentEncoding else {
            print("Invalid stream deep link parameters")
            ToastManager.shared.showToast(message: "Invalid stream link")
            return
        }
        let password = components.queryItems?.first(where: { $0.name == "password" })?.value?.removingPercentEncoding
        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task { @MainActor in
            do {
                let existingSessions = try context.fetch(descriptor)
                let matchingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString && $0.auth })
                let token = matchingSession?.token ?? ""
                streamStateManager.deepLinkServerURL = serverURL
                streamStateManager.deepLinkStreamName = streamName
                streamStateManager.deepLinkToken = token
                streamStateManager.deepLinkPassword = password
                streamStateManager.showingDeepLinkStream = true
            } catch {
                print("Error resolving stream deep link: \(error)")
                ToastManager.shared.showToast(message: "Could not open stream")
            }
        }
    }

    @MainActor private func handleFileListDeepLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, selectedTab: Binding<TabViewWindow.Tab>) {
        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString) else {
            print("Invalid server URL in filelist deep link")
            return
        }

        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task { @MainActor in
            do {
                let existingSessions = try context.fetch(descriptor)
                if let matchingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString }) {
                    sessionManager.selectedSession = matchingSession
                    selectedTab.wrappedValue = .files
                } else {
                    print("No session found for URL: \(serverURL.absoluteString)")
                }
            } catch {
                print("Error fetching sessions: \(error)")
            }
        }
    }
    
    @MainActor private func deepLinkAuth(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, hasExistingSessions: Binding<Bool>, showingServerConfirmation: Binding<Bool>, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>) {
        // URLComponents.queryItems already percent-decodes values, so call
        // removingPercentEncoding only as a safety fallback for double-encoded inputs.
        guard let rawSignature = components.queryItems?.first(where: { $0.name == "signature" })?.value,
              let signature = rawSignature.removingPercentEncoding ?? rawSignature as String?,
              !signature.isEmpty,
              let rawURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let urlString = rawURLString.removingPercentEncoding ?? rawURLString as String?,
              let serverURL = URL(string: urlString) else {
            print("Unable to parse auth deep link.")
            ToastManager.shared.showToast(message: "Invalid authorization link")
            return
        }

        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task { @MainActor in
            do {
                let existingSessions = try context.fetch(descriptor)
                // Only skip the auth flow if we already have a valid, authenticated session.
                // If the session exists but is not authenticated, fall through so the user
                // can complete sign-in with the new signature.
                if let existingSession = existingSessions.first(where: {
                    $0.url == serverURL.absoluteString && $0.auth
                }) {
                    sessionManager.selectedSession = existingSession
                    hasExistingSessions.wrappedValue = true
                    ToastManager.shared.showToast(message: "Already signed into \(existingSession.url)")
                    return
                }

                pendingAuthURL.wrappedValue = serverURL
                pendingAuthSignature.wrappedValue = signature
                showingServerConfirmation.wrappedValue = true
            } catch {
                print("Error checking for existing sessions: \(error)")
                ToastManager.shared.showToast(message: "Error opening authorization link")
            }
        }
    }

    /// Deep link: `djangofiles://album/?url=<server_url>&album_id=<id>&album_name=<optional_name>`
    /// Authenticated users are taken directly into the albums tab. Unauthenticated users see the guest cover sheet.
    @MainActor private func handleAlbumLink(_ components: URLComponents, context: ModelContext, sessionManager: SessionManager, albumStateManager: AlbumStateManager, selectedTab: Binding<TabViewWindow.Tab>) {
        guard let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding,
              let serverURL = URL(string: urlString),
              let albumIDString = components.queryItems?.first(where: { $0.name == "album_id" })?.value,
              let albumID = Int(albumIDString) else {
            print("Invalid album deep link parameters")
            ToastManager.shared.showToast(message: "Invalid album link")
            return
        }
        let albumName = components.queryItems?.first(where: { $0.name == "album_name" })?.value?.removingPercentEncoding
        let descriptor = FetchDescriptor<DjangoFilesSession>()

        Task { @MainActor in
            do {
                let existingSessions = try context.fetch(descriptor)
                let matchingSession = existingSessions.first(where: { $0.url == serverURL.absoluteString && $0.auth })

                if let matchingSession = matchingSession {
                    // Authenticated: navigate inside the normal albums tab
                    sessionManager.selectedSession = matchingSession
                    selectedTab.wrappedValue = .albums
                    albumStateManager.deepLinkNavigationAlbumID = albumID
                    albumStateManager.deepLinkNavigationAlbumName = albumName
                } else {
                    // Guest: show the full-screen cover sheet
                    albumStateManager.deepLinkSession = DjangoFilesSession(url: serverURL.absoluteString, token: "")
                    albumStateManager.deepLinkAlbumID = albumID
                    albumStateManager.deepLinkAlbumName = albumName
                    albumStateManager.showingDeepLinkAlbum = true
                }
            } catch {
                print("Error resolving album deep link: \(error)")
                ToastManager.shared.showToast(message: "Could not open album")
            }
        }
    }

    @MainActor func handleServerConfirmation(confirmed: Bool, setAsDefault: Bool, pendingAuthURL: Binding<URL?>, pendingAuthSignature: Binding<String?>, context: ModelContext, sessionManager: SessionManager, hasExistingSessions: Binding<Bool>, selectedTab: Binding<TabViewWindow.Tab>) async {
        guard let serverURL = pendingAuthURL.wrappedValue,
              let signature = pendingAuthSignature.wrappedValue else {
            return
        }

        // Clear pending values immediately so a rapid second tap cannot double-trigger.
        pendingAuthURL.wrappedValue = nil
        pendingAuthSignature.wrappedValue = nil

        guard confirmed else { return }

        DFAnalytics.logLoginMethodSelected(.application)

        do {
            let descriptor = FetchDescriptor<DjangoFilesSession>()
            let existingSessions = try context.fetch(descriptor)
            let wasFirstServer = existingSessions.isEmpty

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
                DFAnalytics.logServerAdded(
                    authMethod: .application,
                    scheme: serverURL.scheme,
                    isFirstServer: wasFirstServer,
                    setAsDefault: setAsDefault
                )
                ToastManager.shared.showToast(message: "Successfully logged into \(newSession.url)")
            } else {
                DFAnalytics.logServerAddFailed(reason: .authFailed, scheme: serverURL.scheme)
                ToastManager.shared.showToast(message: "Failed to sign in. The link may have expired.")
            }
        } catch {
            DFAnalytics.logServerAddFailed(reason: .authFailed, scheme: serverURL.scheme)
            ToastManager.shared.showToast(message: "Problem signing into server \(error)")
            print("Error creating new session: \(error)")
        }
    }
}

