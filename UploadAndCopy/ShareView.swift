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
        .toastNotification(
            message: viewModel.alertMessage,
            isPresented: $viewModel.showAlert,
            duration: 2.5
        )
        .onChange(of: viewModel.showAlert) { oldValue, newValue in
            if newValue && viewModel.shouldAutoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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

// Toast Notification View Modifier
struct ToastNotificationModifier: ViewModifier {
    let message: String
    @Binding var isPresented: Bool
    let duration: Double
    
    @State private var showToast: Bool = false
    @State private var dismissTask: DispatchWorkItem?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    VStack {
                        Text(message)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .opacity(showToast ? 1 : 0)
                            .offset(y: showToast ? 0 : -50)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
                    .onAppear {
                        showToast = true
                        
                        // Cancel any existing dismiss task
                        dismissTask?.cancel()
                        
                        // Auto-dismiss after duration
                        let task = DispatchWorkItem {
                            withAnimation {
                                showToast = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isPresented = false
                            }
                        }
                        dismissTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
                    }
                    .onChange(of: isPresented) { oldValue, newValue in
                        if !newValue {
                            dismissTask?.cancel()
                            showToast = false
                        } else if newValue && !oldValue {
                            // Reset when shown again
                            showToast = true
                            let task = DispatchWorkItem {
                                withAnimation {
                                    showToast = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isPresented = false
                                }
                            }
                            dismissTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
                        }
                    }
                }
            }
    }
}

extension View {
    func toastNotification(
        message: String,
        isPresented: Binding<Bool>,
        duration: Double = 2.5
    ) -> some View {
        modifier(ToastNotificationModifier(
            message: message,
            isPresented: isPresented,
            duration: duration
        ))
    }
}

