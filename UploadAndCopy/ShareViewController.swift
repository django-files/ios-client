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

    var tempFileURLs: Set<URL> = []
    var doShorten = false
    var session: DjangoFilesSession = DjangoFilesSession()
    var shareURLs: [URL] = []
    private var pendingLoads = 0
    private var lastResponseURL: String?

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

        var allProviders: [NSItemProvider] = []
        for extensionItem in extensionItems {
            if let attachments = extensionItem.attachments {
                allProviders.append(contentsOf: attachments)
            }
        }

        guard !allProviders.isEmpty else {
            showMessageAndDismiss(message: "Nothing to share.")
            return
        }

        // Special case: single web URL for shortening
        if allProviders.count == 1 {
            let itemProvider = allProviders[0]
            if itemProvider.hasItemConformingToTypeIdentifier("public.url") &&
               !itemProvider.hasItemConformingToTypeIdentifier("public.image") &&
               !itemProvider.hasItemConformingToTypeIdentifier("public.file-url") {
                itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { (item, error) in
                    DispatchQueue.main.async {
                        guard let url = item as? URL else {
                            self.showMessageAndDismiss(message: "Invalid URL.")
                            return
                        }
                        self.viewModel.showShortText = true
                        self.viewModel.shortTextPlaceholder = self.randomString(length: 5)
                        self.shareURLs = [url]
                        self.viewModel.shareLabel = "Shorten Link"
                        self.viewModel.previewText = url.absoluteString
                        self.viewModel.isTextEditable = false
                        if url.absoluteString.hasPrefix("http://") || url.absoluteString.hasPrefix("https://") {
                            self.doShorten = true
                        }
                        self.viewModel.isLoading = false
                        self.viewModel.isShareEnabled = true
                    }
                }
                return
            }
        }

        // Load all items (images, videos, files, text)
        pendingLoads = allProviders.count
        for provider in allProviders {
            loadProvider(provider)
        }
    }

    private func loadProvider(_ itemProvider: NSItemProvider) {
        if itemProvider.hasItemConformingToTypeIdentifier("public.png") || itemProvider.hasItemConformingToTypeIdentifier("public.image") {
            let typeIdentifier = itemProvider.hasItemConformingToTypeIdentifier("public.png") ? "public.png" : "public.image"
            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                DispatchQueue.main.async {
                    self.handleImageItem(item: item, error: error)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier("public.file-url") {
            itemProvider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                DispatchQueue.main.async {
                    self.viewModel.showShortText = false
                    self.viewModel.shareLabel = "Upload File"
                    if let url = item as? URL {
                        self.shareURLs.append(url)
                    }
                    self.itemLoaded()
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier("public.text") || itemProvider.hasItemConformingToTypeIdentifier("public.plain-text") {
            itemProvider.loadItem(forTypeIdentifier: itemProvider.registeredTypeIdentifiers[0], options: nil) { (item, error) in
                DispatchQueue.main.async {
                    self.viewModel.showShortText = false
                    if let text = item as? String {
                        self.viewModel.previewText = text
                        self.viewModel.isTextEditable = true
                        let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
                        let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).txt")
                        do {
                            try text.write(to: targetURL, atomically: true, encoding: .utf8)
                            self.tempFileURLs.insert(targetURL)
                            self.shareURLs.append(targetURL)
                        } catch {
                            // fall through without this item
                        }
                    }
                    self.itemLoaded()
                }
            }
        } else {
            itemProvider.loadItem(forTypeIdentifier: "public.data", options: nil) { (item, error) in
                DispatchQueue.main.async {
                    self.viewModel.shareLabel = "Upload File"
                    if let url = item as? URL {
                        self.shareURLs.append(url)
                    }
                    self.itemLoaded()
                }
            }
        }
    }

    private func itemLoaded() {
        pendingLoads -= 1
        guard pendingLoads <= 0 else { return }

        let count = shareURLs.count
        guard count > 0 else {
            showMessageAndDismiss(message: "Nothing to share.")
            return
        }
        if count > 1 {
            viewModel.shareLabel = "Upload \(count) Files"
        }
        viewModel.isLoading = false
        viewModel.isShareEnabled = true
    }

    func handleImageItem(item: NSSecureCoding?, error: Error?) {
        viewModel.showShortText = false
        viewModel.isImageUpload = true

        if let error = error {
            // skip this item but keep going
            itemLoaded()
            print("Error loading image: \(error.localizedDescription)")
            return
        }

        guard let item = item else {
            itemLoaded()
            return
        }

        if let url = item as? URL {
            shareURLs.append(url)
            if viewModel.previewImage == nil {
                let previewSize = CGSize(width: 300, height: 300)
                viewModel.previewImage = downsample(imageAt: url, to: previewSize)
            }
        } else if let image = item as? UIImage {
            if viewModel.previewImage == nil {
                viewModel.previewImage = image
            }
            let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
            let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).png")
            do {
                if let pngData = image.pngData() {
                    try pngData.write(to: targetURL)
                    tempFileURLs.insert(targetURL)
                    shareURLs.append(targetURL)
                }
            } catch {
                print("Could not save image: \(error.localizedDescription)")
            }
        } else if let data = item as? Data {
            let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
            let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).png")
            do {
                try data.write(to: targetURL)
                tempFileURLs.insert(targetURL)
                shareURLs.append(targetURL)
                if viewModel.previewImage == nil {
                    let previewSize = CGSize(width: 300, height: 300)
                    viewModel.previewImage = downsample(imageAt: targetURL, to: previewSize)
                }
            } catch {
                print("Could not save image data: \(error.localizedDescription)")
            }
        }

        itemLoaded()
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

            let defaultSession = sessions.first(where: { $0.defaultSession }) ?? sessions.first!

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
        cleanupTempFiles()
        self.dismiss(animated: false, completion: {
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
        })
    }

    private func cleanupTempFiles() {
        for url in tempFileURLs {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        tempFileURLs.removeAll()
    }

    func shareFile(viewModel: ShareViewModel) async {
        viewModel.showProgress = true
        viewModel.uploadProgress = 0

        // If sharing editable text, write the edited content back to the temp file
        if !viewModel.previewText.isEmpty && viewModel.isTextEditable, let firstURL = shareURLs.first {
            do {
                try viewModel.previewText.write(to: firstURL, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.showMessageAndDismiss(message: "Could not update text content.")
                }
                return
            }
        }

        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let total = shareURLs.count

        let albums = viewModel.selectedAlbumIDs.map(String.init).joined(separator: ",")

        for (index, url) in shareURLs.enumerated() {
            let task = await api.uploadFileStreamed(url: url, albums: albums, privateUpload: viewModel.privateUpload, stripExif: viewModel.stripExif, stripGps: viewModel.stripGps, taskDelegate: self)
            let response = await task?.waitForComplete()

            if let responseURL = response?.url {
                lastResponseURL = responseURL
            } else {
                DispatchQueue.main.async {
                    viewModel.showProgress = false
                    viewModel.uploadProgress = 0
                    viewModel.isShareEnabled = true
                    self.showMessageAndDismiss(message: "Bad server response: \(task?.error ?? "Unknown error")")
                }
                return
            }

            DispatchQueue.main.async {
                viewModel.uploadProgress = Float(index + 1) / Float(total)
            }
        }

        DispatchQueue.main.async {
            viewModel.isLoading = false
            UIPasteboard.general.string = self.lastResponseURL
            NotificationCenter.default.addObserver(self, selector: #selector(self.clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
            self.notifyClipboard()
        }
    }

    func shareLink(viewModel: ShareViewModel) async {
        guard let shareURL = shareURLs.first else { return }
        let shortLink: String = viewModel.shortText.isEmpty ? randomString(length: 5) : viewModel.shortText
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let response = await api.createShort(url: shareURL, short: shortLink, selectedServer: session)

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
                    self.extensionContext!.completeRequest(returningItems: [])
                } else {
                    self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
                }
            }
        } )
        self.dismiss(animated: false)
    }

    func notifyClipboard() {
        cleanupTempFiles()

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        DispatchQueue.main.async {
            self.viewModel.alertMessage = "Link copied to clipboard"
            self.viewModel.shouldAutoDismiss = true
            self.viewModel.showAlert = true
        }
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

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}
