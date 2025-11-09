//
//  ShareView.swift
//  UploadAndCopy
//
//  Created by Auto on 2/16/25.
//

import SwiftUI
import UIKit

struct ShareView: View {
    @ObservedObject var viewModel: ShareViewModel
    @FocusState private var isShortTextFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(viewModel.shareLabel)
                    .font(.headline)
                    .padding(.top, 8)
                
                if let image = viewModel.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                } else if !viewModel.previewText.isEmpty {
                    VStack(spacing: 0) {
                        TextEditor(text: $viewModel.previewText)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .disabled(!viewModel.isTextEditable)
                } else {
                    // No preview available (e.g., file upload)
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("File ready to upload")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                
                if viewModel.showShortText {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Short URL Vanity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                        
                        TextField(viewModel.shortTextPlaceholder, text: $viewModel.shortText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isShortTextFocused)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
            
            ProgressView(value: viewModel.uploadProgress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .opacity(viewModel.showProgress ? 1 : 0)
            
            // Destination selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                Menu {
                    ForEach(viewModel.availableSessions, id: \.url) { session in
                        Button(session.url) {
                            viewModel.selectSession(session)
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.selectedSession?.url ?? "No servers available")
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .disabled(viewModel.availableSessions.isEmpty)
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            
            HStack(spacing: 12) {
                Button {
                    viewModel.cancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.share()
                } label: {
                    Text("Share")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isShareEnabled || viewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
        .alert("Django Files", isPresented: $viewModel.showAlert) {
        } message: {
            Text(viewModel.alertMessage)
        }
        .onChange(of: viewModel.showAlert) { oldValue, newValue in
            if newValue && viewModel.shouldAutoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if viewModel.showAlert && viewModel.shouldAutoDismiss {
                        viewModel.dismissAlert()
                    }
                }
            }
        }
    }
}

// Observable object to manage the share view state
class ShareViewModel: ObservableObject {
    @Published var availableSessions: [DjangoFilesSession] = []
    @Published var selectedSession: DjangoFilesSession?
    @Published var shareLabel: String = "Upload"
    @Published var previewImage: UIImage?
    @Published var previewText: String = ""
    @Published var isTextEditable: Bool = false
    @Published var showShortText: Bool = false
    @Published var shortText: String = ""
    @Published var shortTextPlaceholder: String = ""
    @Published var showProgress: Bool = false
    @Published var uploadProgress: Float = 0.0
    @Published var isShareEnabled: Bool = false
    @Published var isLoading: Bool = true
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var shouldAutoDismiss: Bool = false
    
    weak var shareViewController: ShareViewController?
    
    func selectSession(_ session: DjangoFilesSession) {
        selectedSession = session
    }
    
    func share() {
        shareViewController?.handleShare(from: self)
    }
    
    func cancel() {
        shareViewController?.handleCancel()
    }
    
    func dismissAlert() {
        if showAlert {
            let wasAutoDismiss = shouldAutoDismiss
            showAlert = false
            shouldAutoDismiss = false
            // Always call dismissAfterAlert, but it will handle completion differently
            shareViewController?.dismissAfterAlert(shouldComplete: wasAutoDismiss)
        }
    }
}

//#Preview {
//    let viewModel = ShareViewModel()
//    viewModel.availableSessions = [
//        DjangoFilesSession(url: "https://example.com", token: "token1"),
//        DjangoFilesSession(url: "https://test.com", token: "token2")
//    ]
//    viewModel.selectedSession = viewModel.availableSessions.first
//    viewModel.shareLabel = "Share Image"
//    viewModel.previewImage = UIImage(systemName: "photo")
//    viewModel.showShortText = true
//    viewModel.shortTextPlaceholder = "Enter short URL"
//    viewModel.isShareEnabled = true
//    viewModel.isLoading = false
//    
//    return ShareView(viewModel: viewModel)
//}
//
//#Preview("Text Preview") {
//    let viewModel = ShareViewModel()
//    viewModel.availableSessions = [
//        DjangoFilesSession(url: "https://example.com", token: "token1")
//    ]
//    viewModel.selectedSession = viewModel.availableSessions.first
//    viewModel.shareLabel = "Share Text"
//    viewModel.previewText = "This is a sample text that can be shared."
//    viewModel.isTextEditable = true
//    viewModel.isShareEnabled = true
//    viewModel.isLoading = false
//    
//    return ShareView(viewModel: viewModel)
//}
//
//#Preview("File Upload") {
//    let viewModel = ShareViewModel()
//    viewModel.availableSessions = [
//        DjangoFilesSession(url: "https://example.com", token: "token1")
//    ]
//    viewModel.selectedSession = viewModel.availableSessions.first
//    viewModel.shareLabel = "Upload File"
//    viewModel.isShareEnabled = true
//    viewModel.isLoading = false
//    
//    return ShareView(viewModel: viewModel)
//}
//
//#Preview("Loading State") {
//    let viewModel = ShareViewModel()
//    viewModel.availableSessions = [
//        DjangoFilesSession(url: "https://example.com", token: "token1")
//    ]
//    viewModel.selectedSession = viewModel.availableSessions.first
//    viewModel.shareLabel = "Uploading..."
//    viewModel.showProgress = true
//    viewModel.uploadProgress = 0.5
//    viewModel.isLoading = true
//    viewModel.isShareEnabled = false
//    
//    return ShareView(viewModel: viewModel)
//}

