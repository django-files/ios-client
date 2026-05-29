//
//  ShareViewController.swift
//  UploadAndCopy
//
//  Created by Michael on 2/16/25.
//

import UIKit
import Social
import SwiftData
import CoreHaptics
import SwiftUI

class ShareViewController: UIViewController, URLSessionTaskDelegate {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DjangoFilesSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.djangofiles.app"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    private var hostingController: UIHostingController<ShareView>?
    private var viewModel = ShareViewModel()
    
    var isTempFile = false
    var doShorten = false
    var session: DjangoFilesSession = DjangoFilesSession()
    var shareURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup SwiftUI view
        viewModel.shareViewController = self
        let shareView = ShareView(viewModel: viewModel)
        hostingController = UIHostingController(rootView: shareView)
        
        guard let hostingController = hostingController else { return }
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        
        // Load available servers
        getAvailableServers()
        
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.showMessageAndDismiss(message: "Nothing to share.")
            return
        }
        
        var loaded: Bool = false
        for extensionItem in extensionItems {
            for ele in extensionItem.attachments! {
                let itemProvider = ele
                print(ele)

                if itemProvider.hasItemConformingToTypeIdentifier("public.png") || itemProvider.hasItemConformingToTypeIdentifier("public.image") {
                    let typeIdentifier = itemProvider.hasItemConformingToTypeIdentifier("public.png") ? "public.png" : "public.image"
                    itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.handleImageItem(item: item, error: error)
                        }
                    })
                    loaded = true
                    break
                }
                else if itemProvider.hasItemConformingToTypeIdentifier("public.file-url") {
                    itemProvider.loadItem(forTypeIdentifier: "public.file-url", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.viewModel.showShortText = false
                            self.viewModel.shareLabel = "Upload File"
                            self.shareURL = item as? URL
                            self.viewModel.isLoading = false
                            self.viewModel.isShareEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
                else if itemProvider.hasItemConformingToTypeIdentifier("public.url"){
                    itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.viewModel.showShortText = true
                            self.viewModel.shortTextPlaceholder = self.randomString(length: 5)
                            self.shareURL = item as? URL
                            self.viewModel.shareLabel = "Shorten Link"
                            self.viewModel.previewText = self.shareURL!.absoluteString
                            self.viewModel.isTextEditable = false
                            if self.shareURL!.absoluteString.hasPrefix("http://") || self.shareURL!.absoluteString.hasPrefix("https://"){
                                self.doShorten = true
                            }
                            self.viewModel.isLoading = false
                            self.viewModel.isShareEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
                else if itemProvider.hasItemConformingToTypeIdentifier("public.text") || itemProvider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    itemProvider.loadItem(forTypeIdentifier: itemProvider.registeredTypeIdentifiers[0], options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.viewModel.showShortText = false
                            
                            if let text = item as? String {
                                // Show the text preview
                                self.viewModel.previewText = text
                                self.viewModel.isTextEditable = true
                                
                                // Create a temporary file to store the text
                                let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
                                let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID.init().uuidString).txt")
                                do {
                                    try text.write(to: targetURL, atomically: true, encoding: .utf8)
                                    self.isTempFile = true
                                    self.shareURL = targetURL
                                    self.viewModel.shareLabel = "Upload Text"
                                } catch {
                                    self.showMessageAndDismiss(message: "Could not share text.")
                                }
                            }
                            self.viewModel.isLoading = false
                            self.viewModel.isShareEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
                else {
                    itemProvider.loadItem(forTypeIdentifier: "public.data", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.shareURL = item as? URL
                            self.viewModel.shareLabel = "Upload File"
                            self.viewModel.isLoading = false
                            self.viewModel.isShareEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
            }
            if loaded {
                break
            }
        }
    }
    
    func handleImageItem(item: NSSecureCoding?, error: Error?) {
        self.viewModel.showShortText = false
        self.viewModel.shareLabel = "Upload Image"
        self.viewModel.isImageUpload = true
        
        if let error = error {
            self.showMessageAndDismiss(message: "Error loading image: \(error.localizedDescription)")
            return
        }
        
        guard let item = item else {
            self.showMessageAndDismiss(message: "Invalid image.")
            return
        }
        
        // Handle different item types
        if let url = item as? URL {
            // Item is a URL
            self.shareURL = url
            let previewSize = CGSize(width: 300, height: 300)
            self.viewModel.previewImage = self.downsample(imageAt: url, to: previewSize)
        } else if let image = item as? UIImage {
            // Item is a UIImage - need to save it to a temp file
            self.viewModel.previewImage = image
            let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
            let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID.init().uuidString).png")
            do {
                if let pngData = image.pngData() {
                    try pngData.write(to: targetURL)
                    self.isTempFile = true
                    self.shareURL = targetURL
                } else {
                    self.showMessageAndDismiss(message: "Invalid image.")
                    return
                }
            } catch {
                self.showMessageAndDismiss(message: "Could not save image: \(error.localizedDescription)")
                return
            }
        } else if let data = item as? Data {
            // Item is Data - save it to a temp file and create UIImage
            let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
            let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID.init().uuidString).png")
            do {
                try data.write(to: targetURL)
                self.isTempFile = true
                self.shareURL = targetURL
                let previewSize = CGSize(width: 300, height: 300)
                self.viewModel.previewImage = self.downsample(imageAt: targetURL, to: previewSize)
            } catch {
                self.showMessageAndDismiss(message: "Could not save image: \(error.localizedDescription)")
                return
            }
        } else {
            self.showMessageAndDismiss(message: "Invalid image type.")
            return
        }
        
        self.viewModel.isLoading = false
        self.viewModel.isShareEnabled = true
    }
    
    func getAvailableServers() {
        let context = sharedModelContainer.mainContext

        do {
            let descriptor = FetchDescriptor<DjangoFilesSession>(
                predicate: #Predicate { $0.auth == true },
                sortBy: [SortDescriptor(\.url)]
            )
            let sessions = try context.fetch(descriptor)

            guard !sessions.isEmpty else {
                viewModel.availableSessions = []
                return
            }

            // Pick the default session, or fallback to the first one
            let defaultSession = sessions.first(where: { $0.defaultSession }) ?? sessions.first!

            // Update view model
            viewModel.availableSessions = sessions
            viewModel.selectedSession = defaultSession
            session = defaultSession

        } catch {
            self.showMessageAndDismiss(message: error.localizedDescription)
            viewModel.availableSessions = []
        }
    }
    
    func getDefaultServer() -> DjangoFilesSession? {
        var selectedServer: DjangoFilesSession?
        do{
            let servers = try sharedModelContainer.mainContext.fetch(FetchDescriptor<DjangoFilesSession>())
            if servers.count == 0 {
                return nil
            }
            selectedServer = servers.first(where: {
                return $0.defaultSession
            })
            if selectedServer == nil{
                selectedServer = servers[0]
            }
        }
        catch {
            self.showMessageAndDismiss(message: error.localizedDescription)
        }
        return selectedServer
    }
    
    func randomString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyz0123456789-_"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    func handleShare(from viewModel: ShareViewModel) {
        // Update session if changed
        if let selectedSession = viewModel.selectedSession {
            session = selectedSession
        }
        
        if doShorten && !isShortLinkValid(shortText: viewModel.shortText) {
            DispatchQueue.main.async {
                viewModel.alertMessage = "Short URL can only contain lowercase letters, numbers, hyphens, and underscores."
                viewModel.shouldAutoDismiss = false
                viewModel.showAlert = true
            }
            return
        }
        
        viewModel.isShareEnabled = false

        Task {
            if !doShorten {
                await shareFile(viewModel: viewModel)
            } else {
                await shareLink(viewModel: viewModel)
            }
        }
    }
    
    func handleCancel() {
        if self.isTempFile {
            do{
                if let shareURL = self.shareURL, FileManager.default.fileExists(atPath: shareURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: shareURL)
                }
            }
            catch { }
        }
        self.dismiss(animated: false, completion: {
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
        })
    }
    
    func shareFile(viewModel: ShareViewModel) async {
        viewModel.showProgress = true
        viewModel.uploadProgress = 0
        
        // If we're sharing text and it's been edited, update the file content
        if !viewModel.previewText.isEmpty && viewModel.isTextEditable {
            do {
                try viewModel.previewText.write(to: shareURL!, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.showMessageAndDismiss(message: "Could not update text content.")
                }
                return
            }
        }
        
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let task = await api.uploadFileStreamed(url: shareURL!, privateUpload: viewModel.privateUpload, stripExif: viewModel.stripExif, stripGps: viewModel.stripGps, taskDelegate: self)
        let response = await task?.waitForComplete()
        
        DispatchQueue.main.async {
            viewModel.isLoading = false
            
            if response == nil{
                viewModel.showProgress = false
                viewModel.uploadProgress = 0
                viewModel.isShareEnabled = true
                self.showMessageAndDismiss(message: "Bad server response: \(task?.error ?? "Unknown error")")
            }
            else{
                UIPasteboard.general.string = response?.url
                NotificationCenter.default.addObserver(self, selector: #selector(self.clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
                self.notifyClipboard()
            }
        }
    }

    func shareLink(viewModel: ShareViewModel) async {
        let shortLink: String = viewModel.shortText.isEmpty ? randomString(length: 5) : viewModel.shortText
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let response = await api.createShort(url: shareURL!, short: shortLink, selectedServer: session)
        
        DispatchQueue.main.async {
            viewModel.isLoading = false
            
            if response == nil{
                viewModel.isShareEnabled = true
                self.showMessageAndDismiss(message: "Bad server response.")
            }
            else{
                UIPasteboard.general.string = response?.url
                NotificationCenter.default.addObserver(self, selector: #selector(self.clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
                self.notifyClipboard()
            }
        }
    }
    
    func isShortLinkValid(shortText: String) -> Bool{
        let validUrl = /[a-z0-9\-_]+/
        if shortText.wholeMatch(of: validUrl) != nil {
            return true
        }
        else{
            return false
        }
    }
    
    @objc func clipboardChanged() { }
    
    func dismissAfterAlert(shouldComplete: Bool = false) {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false, block: { _ in
            DispatchQueue.main.async {
                if shouldComplete {
                    // For success messages, complete the request
                    self.extensionContext!.completeRequest(returningItems: [])
                } else {
                    // For error messages, cancel the request
                    self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
                }
            }
        } )
        self.dismiss(animated: false)
    }
    
    func notifyClipboard() {
        if self.isTempFile {
            do{
                if FileManager.default.fileExists(atPath: self.shareURL!.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: self.shareURL!)
                }
            }
            catch { }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.async {
            self.viewModel.alertMessage = "Link copied to clipboard"
            self.viewModel.shouldAutoDismiss = true
            self.viewModel.showAlert = true
        }
        
        // The alert will auto-dismiss and complete the request via dismissAfterAlert
    }
    
    func showMessageAndDismiss(message: String){
        DispatchQueue.main.async {
            self.viewModel.alertMessage = message
            self.viewModel.shouldAutoDismiss = false
            self.viewModel.showAlert = true
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
    {
        let uploadProgress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.viewModel.uploadProgress = uploadProgress
        }
    }
    
    func downsample(imageAt imageURL: URL,
                    to pointSize: CGSize,
                    scale: CGFloat = UIScreen.main.scale) -> UIImage? {

        // Create an CGImageSource that represent an image
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else {
            return nil
        }
        
        // Calculate the desired dimension
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        
        // Perform downsampling
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        // Return the downsampled image as UIImage
        return UIImage(cgImage: downsampledImage)
    }
}
