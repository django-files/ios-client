//
//  Dialogs.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/5/25.
//

import SwiftUI

struct FileDialogs: View {
    @Binding var showingDeleteConfirmation: Bool
    @Binding var fileIDsToDelete: [Int]
    @Binding var fileNameToDelete: String
    
    @Binding var showingExpirationDialog: Bool
    @Binding var expirationText: String
    @Binding var fileToExpire: DFFile?
    
    @Binding var showingPasswordDialog: Bool
    @Binding var passwordText: String
    @Binding var fileToPassword: DFFile?
    
    @Binding var showingRenameDialog: Bool
    @Binding var fileNameText: String
    @Binding var fileToRename: DFFile?
    
    let onDelete: ([Int]) async -> Bool
    let onSetExpiration: (DFFile, String) async -> Void
    let onSetPassword: (DFFile, String) async -> Void
    let onRename: (DFFile, String) async -> Void
    
    var body: some View {
        EmptyView()
            .confirmationDialog("Are you sure?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        let _ = await onDelete(fileIDsToDelete)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete \"\(fileNameToDelete)\"?")
            }
            .alert("Set File Expiration", isPresented: $showingExpirationDialog) {
                TextField("Enter expiration", text: $expirationText)
                Button("Cancel", role: .cancel) {
                    fileToExpire = nil
                }
                Button("Set") {
                    if let file = fileToExpire {
                        let expirationValue = expirationText
                        Task {
                            await onSetExpiration(file, expirationValue)
                            await MainActor.run {
                                expirationText = ""
                                fileToExpire = nil
                            }
                        }
                    }
                }
            } message: {
                Text("Enter time until file expiration. Examples: 1h, 5days, 2y")
            }
            .alert("Set File Password", isPresented: $showingPasswordDialog) {
                TextField("Enter password", text: $passwordText)
                Button("Cancel", role: .cancel) {
                    fileToPassword = nil
                }
                Button("Set") {
                    if let file = fileToPassword {
                        let passwordValue = passwordText
                        Task {
                            await onSetPassword(file, passwordValue)
                            await MainActor.run {
                                passwordText = ""
                                fileToPassword = nil
                            }
                        }
                    }
                }
            } message: {
                Text("Enter a password for the file.")
            }
            .alert("Rename File", isPresented: $showingRenameDialog) {
                TextField("New File Name", text: $fileNameText)
                Button("Cancel", role: .cancel) {
                    fileToRename = nil
                }
                Button("Set") {
                    if let file = fileToRename {
                        let fileNameValue = fileNameText
                        Task {
                            await onRename(file, fileNameValue)
                            await MainActor.run {
                                fileNameText = ""
                                fileToRename = nil
                            }
                        }
                    }
                }
            } message: {
                Text("Enter a new name for this file.")
            }
    }
}

