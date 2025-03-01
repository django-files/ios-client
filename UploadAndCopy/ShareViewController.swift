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

class ShareViewController: UIViewController, UITextFieldDelegate, URLSessionTaskDelegate {
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
    
    var isTempFile = false
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
            self.showMessageAndDismiss(message: "Nothing to share.")
            return
        }
        guard let server = getDefaultServer() else {
            self.showMessageAndDismiss(message: "No servers configured.")
            return
        }
        session = server
        
        if URL(string: server.url) == nil{
            self.showMessageAndDismiss(message: "Server '\(server.url)' is invalid.")
            return
        }
        if URL(string: server.url)?.scheme == nil{
            self.showMessageAndDismiss(message: "Server '\(server.url)' scheme (http or https) is invalid.")
            return
        }
        
        self.progressBar.isHidden = true
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
                            self.imageView.image = item as? UIImage
                            if self.shareURL == nil && self.imageView.image != nil{
                                let tempDirectoryURL = NSURL.fileURL(withPath: NSTemporaryDirectory(), isDirectory: true)
                                let targetURL = tempDirectoryURL.appendingPathComponent("\(UUID.init().uuidString).png")
                                do{
                                    try self.imageView.image!.pngData()?.write(to: targetURL)
                                    self.isTempFile = true
                                    self.shareURL = targetURL
                                }
                                catch {
                                    self.showMessageAndDismiss(message: "Invalid image.")
                                }
                            }
                            else if self.imageView.image == nil && self.shareURL != nil{
                                do{
                                    self.imageView.image = UIImage(data: try Data(contentsOf: self.shareURL!))
                                }
                                catch {
                                    self.showMessageAndDismiss(message: "Invalid image.")
                                }
                            }
                            else{
                                self.showMessageAndDismiss(message: "Invalid image.")
                            }
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
        self.progressBar.isHidden = false
        self.progressBar.progress = 0
        
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        Task{
            let response = await api.uploadFile(url: shareURL!, taskDelegate: self)
            self.activityIndicator.stopAnimating()
            
            if response == nil{
                DispatchQueue.main.async {
                    self.showMessageAndDismiss(message: "Bad server response.")
                }
            }
            else{
                DispatchQueue.main.async {
                    UIPasteboard.general.string = response?.url
                    NotificationCenter.default.addObserver(self, selector: #selector(self.clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
                    self.notifyClipboard()
                }
            }
        }
    }
    
    func shareLink() async {
        let shortLink: String = (self.shortText.text == nil || self.shortText.text == "") ? randomString(length: 5) : self.shortText.text!
        let api = DFAPI(url: URL(string: session.url)!, token: session.token)
        Task{
            let response = await api.createShort(url: shareURL!, short: shortLink)
            self.activityIndicator.stopAnimating()
            
            if response == nil{
                DispatchQueue.main.async {
                    self.showMessageAndDismiss(message: "Bad server response.")
                }
            }
            else{
                DispatchQueue.main.async {
                    UIPasteboard.general.string = response?.url
                    NotificationCenter.default.addObserver(self, selector: #selector(self.clipboardChanged), name: UIPasteboard.changedNotification, object: nil)
                    self.notifyClipboard()
                }
            }
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
        if self.isTempFile {
            do{
                if FileManager.default.fileExists(atPath: self.shareURL!.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: self.shareURL!)
                }
            }
            catch { }
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
        }, completion: { finished in
            if finished{
                self.dismiss(animated: true, completion: {
                    self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
                })
            }
        })
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
        let alert = UIAlertController(title: "Django Files", message: "Link copied to clipboard", preferredStyle: .alert)
        self.present(alert, animated: true, completion: nil)
        UIView.animate(withDuration: 0.2, animations: {
            self.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
        }, completion: { finished in
            if finished{
                self.view.isHidden = true
            }
        })
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { _ in
            alert.dismiss(animated: true, completion: nil)
            self.extensionContext!.completeRequest(returningItems: [])
        } )
    }
    
    func showMessageAndDismiss(message: String){
        let alert = UIAlertController(title: "Django Files", message: message, preferredStyle: .alert)
        self.present(alert, animated: true, completion: nil)
        UIView.animate(withDuration: 0.2, animations: {
            self.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
        }, completion: { finished in
            if finished{
                self.view.isHidden = true
            }
        })
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { _ in
            alert.dismiss(animated: true, completion: nil)
            self.extensionContext!.cancelRequest(withError: NSError(domain: "", code: 0))
        } )
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
    {
        let uploadProgress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        self.progressBar.progress = uploadProgress
    }
}
