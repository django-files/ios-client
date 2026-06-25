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

class ShareViewController: UIViewController {
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

    override func viewDidLoad() {
        super.viewDidLoad()

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

        getAvailableServers()

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("Nothing to share.")
            return
        }

        var allProviders: [NSItemProvider] = []
        for extensionItem in extensionItems {
            if let attachments = extensionItem.attachments {
                allProviders.append(contentsOf: attachments)
            }
        }

        guard !allProviders.isEmpty else {
            showError("Nothing to share.")
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
                            self.showError("Invalid URL.")
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
            showError("Nothing to share.")
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
            showError(error.localizedDescription)
            viewModel.availableSessions = []
        }
    }

    func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789-_"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    func handleShare(from viewModel: ShareViewModel) {
        if let selectedSession = viewModel.selectedSession {
            session = selectedSession
        }

        if doShorten && !isShortLinkValid(shortText: viewModel.shortText) {
            let alert = UIAlertController(
                title: nil,
                message: "Short URL can only contain lowercase letters, numbers, hyphens, and underscores.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        viewModel.isShareEnabled = false

        // Write edited text content back to the source file before copying
        if !viewModel.previewText.isEmpty && viewModel.isTextEditable, let firstURL = shareURLs.first {
            try? viewModel.previewText.write(to: firstURL, atomically: true, encoding: .utf8)
        }

        guard let jobID = prepareJob(viewModel: viewModel) else {
            showError("Could not prepare upload.")
            viewModel.isShareEnabled = true
            return
        }

        cleanupTempFiles()

        let deepLink = URL(string: "djangofiles://upload-job/?id=\(jobID)")!
        NSLog("[ShareUpload] opening deep link: %@", deepLink.absoluteString)

        extensionContext?.open(deepLink) { [weak self] success in
            NSLog("[ShareUpload] extensionContext.open success=%d", success ? 1 : 0)
            if !success {
                let fallback = self?.openURLViaResponderChain(deepLink) ?? false
                NSLog("[ShareUpload] responder chain fallback success=%d", fallback ? 1 : 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.extensionContext?.completeRequest(returningItems: [])
            }
        }
    }

    @discardableResult
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) && r !== self {
                _ = r.perform(selector, with: url)
                return true
            }
            responder = r.next
        }
        return false
    }

    private func prepareJob(viewModel: ShareViewModel) -> String? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.djangofiles.app"
        ) else { return nil }

        let jobID = UUID().uuidString

        var copiedFileNames: [String] = []

        if !doShorten {
            let jobFilesDir = container
                .appendingPathComponent("upload-files")
                .appendingPathComponent(jobID)
            guard (try? FileManager.default.createDirectory(
                at: jobFilesDir, withIntermediateDirectories: true)) != nil
            else { return nil }

            for (i, url) in shareURLs.enumerated() {
                let ext = url.pathExtension
                let filename = ext.isEmpty ? "\(i)" : "\(i).\(ext)"
                let dest = jobFilesDir.appendingPathComponent(filename)
                guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else {
                    return nil
                }
                copiedFileNames.append(filename)
            }
        }

        let job = DFPendingUploadJob(
            id: jobID,
            sessionURL: session.url,
            sessionToken: session.token,
            fileNames: copiedFileNames,
            albumIDs: viewModel.selectedAlbums.map { $0.id },
            firstAlbumURL: viewModel.selectedAlbums.first?.url,
            albumName: viewModel.selectedAlbums.first?.name,
            privateUpload: viewModel.privateUpload,
            stripExif: viewModel.stripExif,
            stripGps: viewModel.stripGps,
            isShorten: doShorten,
            shortenSourceURL: shareURLs.first?.absoluteString,
            shortText: viewModel.shortText
        )

        let jobsDir = container.appendingPathComponent("upload-jobs")
        try? FileManager.default.createDirectory(at: jobsDir, withIntermediateDirectories: true)
        let jobFile = jobsDir.appendingPathComponent("\(jobID).json")
        guard let data = try? JSONEncoder().encode(job),
              (try? data.write(to: jobFile)) != nil else { return nil }

        return jobID
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

    func isShortLinkValid(shortText: String) -> Bool {
        let validUrl = /[a-z0-9\-_]+/
        return shortText.wholeMatch(of: validUrl) != nil
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "", code: 0))
            })
            self.present(alert, animated: true)
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

