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

    private func albumLabel(_ ids: [Int]) -> String {
        switch ids.count {
        case 0: return "None"
        case 1: return "1 Album"
        default: return "\(ids.count) Albums"
        }
    }

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

            // Album picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Album")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                Button {
                    viewModel.showAlbumPicker = true
                } label: {
                    HStack {
                        Text(albumLabel(viewModel.selectedAlbumIDs))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .disabled(viewModel.selectedSession == nil)
            }
            .padding(.top, 8)
            .sheet(isPresented: $viewModel.showAlbumPicker) {
                ShareAlbumPickerSheet(
                    server: viewModel.selectedSession,
                    selectedAlbumIDs: $viewModel.selectedAlbumIDs
                )
            }

            VStack(spacing: 2) {
                Toggle("Private", isOn: $viewModel.privateUpload)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                if viewModel.isImageUpload {
                    Divider()
                        .padding(.horizontal, 16)
                    Toggle("Strip EXIF", isOn: $viewModel.stripExif)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    Divider()
                        .padding(.horizontal, 16)
                    Toggle("Strip GPS", isOn: $viewModel.stripGps)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
            .padding(.top, 4)

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
            duration: 1.25
        )
        .onChange(of: viewModel.showAlert) { oldValue, newValue in
            if newValue && viewModel.shouldAutoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
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
    @Published var privateUpload: Bool = false
    @Published var stripExif: Bool = false
    @Published var stripGps: Bool = false
    @Published var isImageUpload: Bool = false
    @Published var selectedAlbumIDs: [Int] = []
    @Published var showAlbumPicker: Bool = false

    weak var shareViewController: ShareViewController?
    
    func selectSession(_ session: DjangoFilesSession) {
        selectedSession = session
    }
    
    func share() {
        guard let vc = shareViewController else {
            print("ShareViewModel: shareViewController is nil, cannot share")
            return
        }
        vc.handleShare(from: self)
    }

    func cancel() {
        guard let vc = shareViewController else {
            print("ShareViewModel: shareViewController is nil, cannot cancel")
            return
        }
        vc.handleCancel()
    }

    func dismissAlert() {
        if showAlert {
            let wasAutoDismiss = shouldAutoDismiss
            showAlert = false
            shouldAutoDismiss = false
            guard let vc = shareViewController else {
                print("ShareViewModel: shareViewController is nil, cannot dismiss alert")
                return
            }
            vc.dismissAfterAlert(shouldComplete: wasAutoDismiss)
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
            .overlay(alignment: .center) {
                if isPresented {
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                        }
                        .padding(.horizontal, 24)
                        .opacity(showToast ? 1 : 0)
                        .scaleEffect(showToast ? 1 : 0.9)
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

