//
//  ShareViewController.swift
//  UploadAndCopy
//
//  Created by Michael on 2/16/25.
//

import UIKit
import Social
import SwiftData

class ShareViewController: UIViewController, UITextFieldDelegate {
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
    
    @IBOutlet weak var viewOverlay: UIView!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var progressBar: UIProgressView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var serverLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var shortTextLabel: UILabel!
    @IBOutlet weak var shortText: UITextField!
    @IBOutlet weak var shareLabel: UILabel!
    
    var doShorten = false
    var session: DjangoFilesSession = DjangoFilesSession()
    var shareURL: URL?
    
    override func viewDidLoad() {
        viewOverlay.layer.cornerRadius = 15
        activityIndicator.startAnimating()
        self.activityIndicator.hidesWhenStopped = true
        
        shortText.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0, userInfo: nil))
            return
        }
        guard let server = getDefaultServer() else {
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0, userInfo: nil))
            return
        }
        session = server
        
        var loaded: Bool = false
        for extensionItem in extensionItems {
            for ele in extensionItem.attachments! {
                let itemProvider = ele

                if itemProvider.hasItemConformingToTypeIdentifier("public.image"){
                    itemProvider.loadItem(forTypeIdentifier: "public.image", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.shortText.isHidden = true
                            self.shareLabel.text = "Upload Image"
                            self.shareURL = item as? URL
                            self.imageView.image = self.downsample(imageAt: item as! URL, to: self.imageView.frame.size)
                            self.imageView.setNeedsDisplay()
                            self.activityIndicator.stopAnimating()
                            self.shareButton.isEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
                else if itemProvider.hasItemConformingToTypeIdentifier("public.url"){
                    itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.shortText.isHidden = false
                            self.shortTextLabel.isHidden = false
                            self.shortText.placeholder = self.randomString(length: 5)
                            self.shareURL = item as? URL
                            self.shareLabel.text = "Shorten Link"
                            if self.shareURL!.absoluteString.hasPrefix("http://") || self.shareURL!.absoluteString.hasPrefix("https://"){
                                self.doShorten = true
                            }
                            self.activityIndicator.stopAnimating()
                            self.shareButton.isEnabled = true
                        }
                    })
                    loaded = true
                    break
                }
                else {
                    itemProvider.loadItem(forTypeIdentifier: "public.data", options: nil, completionHandler: { (item, error) in
                        DispatchQueue.main.async {
                            self.shareURL = item as? URL
                            self.shareLabel.text = "Upload File"
                            self.activityIndicator.stopAnimating()
                            self.shareButton.isEnabled = true
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
        
        serverLabel.text = session.url
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
    }
 
    func getDefaultServer() -> DjangoFilesSession? {
        var selectedServer: DjangoFilesSession?
        do{
            let servers = try sharedModelContainer.mainContext.fetch(FetchDescriptor<DjangoFilesSession>())
            if servers.count == 0{
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
            print(error)
        }
        return selectedServer
    }
    
    func randomString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyz0123456789-_"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    func shareFile() async {
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let response = await api.uploadFile(url: shareURL!)
        self.activityIndicator.stopAnimating()
        
        if response == nil{
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0, userInfo: nil))
        }
        else{
            self.extensionContext!.completeRequest(returningItems: [])
            UIPasteboard.general.string = response?.url
            NotificationCenter.default.addObserver(self, selector: #selector(clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
        }
    }
    
    func shareLink() async {
        let shortLink: String = (self.shortText.text == nil || self.shortText.text == "") ? randomString(length: 5) : self.shortText.text!
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        let response = await api.createShort(url: shareURL!, short: shortLink)
        self.activityIndicator.stopAnimating()
        
        if response == nil{
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0, userInfo: nil))
        }
        else{
            self.extensionContext!.completeRequest(returningItems: [])
            UIPasteboard.general.string = response?.url
            NotificationCenter.default.addObserver(self, selector: #selector(clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
        }
    }
    
    func isShortLinkValid() -> Bool{
        let validUrl = /[a-z0-9\-_]+/
        if (shortText.text?.wholeMatch(of: validUrl)) != nil {
            return true
        }
        else{
            return false
        }
    }
    
    @IBAction func onShare(_ sender: Any) {
        if doShorten && !isShortLinkValid(){
            shortText.becomeFirstResponder()
            return
        }
        
        shareButton.isEnabled = false
        self.activityIndicator.startAnimating()
        
        Task {
            if !doShorten{
                await shareFile()
            }
            else{
                await shareLink()
            }
        }
    }
    
    @objc func clipboardChanged() { }

    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            if self.view.frame.origin.y == 0 {
                self.view.frame.origin.y -= keyboardSize.height
            }
        }
    }

    @objc func keyboardWillHide(notification: NSNotification) {
        if self.view.frame.origin.y != 0 {
            self.view.frame.origin.y = 0
        }
    }
    
    @IBAction func onCancel(_ sender: Any) {
        self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0, userInfo: nil))
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
