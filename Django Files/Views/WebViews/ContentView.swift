//
//  ContentView.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import SwiftData
import SwiftUI

public struct AuthViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode:
        Binding<PresentationMode>

    @State private var isAuthViewLoading: Bool = true
    @State private var showingSoftLoginSheet: Bool = false
    @State private var softLoginSucceeded: Bool = false

    @State var selectedServer: DjangoFilesSession

    var customURL: String? = nil

    var needsRefresh: Binding<Bool>

    @State private var authController: AuthController = AuthController()

    public var body: some View {
        if selectedServer.url != "" {
            AuthView(
                authController: authController,
                httpsUrl: customURL ?? selectedServer.url,
                doReset: authController.url?.absoluteString ?? ""
                    != selectedServer.url || !selectedServer.auth,
                session: selectedServer
            )
            .onStartedLoading {
                isAuthViewLoading = true
            }
            .onCancelled {
                isAuthViewLoading = false
                dismiss()
            }
            .onAppear {
                if needsRefresh.wrappedValue {
                    authController.reset()
                    needsRefresh.wrappedValue = false
                }

                authController.onStartedLoadingAction = {
                }

                authController.onLoadedAction = {
                    isAuthViewLoading = false

                }
                authController.onCancelledAction = {
                    isAuthViewLoading = false
                    dismiss()
                }

                authController.onSchemeRedirectAction = {
                    isAuthViewLoading = false
                    guard let resolve = authController.schemeURL else {
                        return
                    }
                    switch resolve {
                    case "serverlist":
                        if UIDevice.current.userInterfaceIdiom == .phone
                        {
                            self.presentationMode.wrappedValue.dismiss()
                        }
                        break
                    case "logout":
                        // The server sends djangofiles://logout when the session cookie
                        // expires. Check the Bearer token first before doing anything destructive.
                        Task { @MainActor in
                            guard let serverURL = URL(string: selectedServer.url) else {
                                selectedServer.auth = false
                                try? modelContext.save()
                                self.presentationMode.wrappedValue.dismiss()
                                return
                            }
                            let api = DFAPI(url: serverURL, token: selectedServer.token)
                            guard await api.getCurrentUser() != nil else {
                                // Token is genuinely invalid — full de-auth.
                                selectedServer.auth = false
                                modelContext.insert(selectedServer)
                                try? modelContext.save()
                                self.presentationMode.wrappedValue.dismiss()
                                return
                            }
                            // Token is valid — cookie just expired. Try to refresh the session.
                            if await api.refreshWebSession(selectedServer: selectedServer) {
                                // Got fresh cookies — re-inject and reload the WebView.
                                authController.applyCookies(from: selectedServer)
                                authController.reset()
                            } else {
                                // Refresh endpoint unavailable (older backend).
                                // Show login sheet over the WebView. On success the WebView
                                // reloads with fresh cookies; on dismiss the WebView closes.
                                showingSoftLoginSheet = true
                            }
                        }
                        break
                    default:
                        return
                    }
                }
            }
            .overlay {
                if isAuthViewLoading {
                    LoadingView().frame(width: 100, height: 100)
                }
            }
            .sheet(isPresented: $showingSoftLoginSheet, onDismiss: {
                if softLoginSucceeded {
                    // Clear stale domain cookies, inject fresh ones, then reload.
                    authController.refreshCookiesAndReload(from: selectedServer)
                } else {
                    // Dismissed without logging in — close the WebView.
                    self.presentationMode.wrappedValue.dismiss()
                }
                softLoginSucceeded = false
            }) {
                LoginView(selectedServer: selectedServer, onLoginSuccess: {
                    softLoginSucceeded = true
                    showingSoftLoginSheet = false
                })
            }
        } else {
            Text("Loading...")
        }
    }
}
