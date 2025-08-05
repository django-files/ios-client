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
    @Query private var items: [DjangoFilesSession]

    @State private var isAuthViewLoading: Bool = true

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
                        selectedServer.auth = false
                        modelContext.insert(selectedServer)
                        do {
                            try modelContext.save()
                        } catch {
                            print("Error saving session: \(error)")
                        }
                        self.presentationMode.wrappedValue.dismiss()
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
        } else {
            Text("Loading...")
        }
    }
}


