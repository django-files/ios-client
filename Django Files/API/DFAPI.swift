//
//  DFAPI.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation
import UIKit

// Custom imports
import SwiftUI  // Needed for ToastManager

// Add an import for the models file
// This line should be modified if the module structure is different
// Or the models should be declared here if needed

struct DFAPI {
    private static let API_PATH = "/api/"
    
    // Add a shared WebSocket instance
    private static var sharedWebSocket: DFWebSocket?
    
    enum DjangoFilesAPIs: String {
        case stats = "stats/"
        case upload = "upload/"
        case short = "shorten/"
        case auth_methods = "auth/methods/"
        case login = "auth/token/"
        case files = "files/"
        case shorts = "shorts/"
        case delete_file = "files/delete/"
        case edit_file = "files/edit/"
        case file = "file/"
        case raw = "raw/"
    }
    
    let url: URL
    let token: String
    var decoder: JSONDecoder
    
    
    init(url: URL, token: String){
        self.url = url
        self.token = token
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    private func encodeParametersIntoURL(path: String, parameters: [String: String]) -> URL {
        var components = URLComponents(url: url.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    
    private func getAPIPath(_ api: DjangoFilesAPIs) -> String {
        return DFAPI.API_PATH + api.rawValue
    }
    
    private func handleError(_ status: HTTPResponse.Status, data: Data?){
        print("Server response status code: \(status)")
        do{
            let e = try decoder.decode(DFErrorResponse.self, from: data!)
            print("\(e.error): \(e.message)")
        }catch {
            print("Invalid error response.")
        }
    }
    
    private func makeAPIRequest(body: Data, path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok, headerFields: [HTTPField.Name:String] = [:], taskDelegate: URLSessionTaskDelegate? = nil) async throws -> Data
    {
        var request = HTTPRequest(method: method, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.authorization] = token
        request.headerFields[.referer] = url.absoluteString
        for kvp in headerFields {
            request.headerFields[kvp.key] = kvp.value
        }
        let session = URLSession(configuration: .ephemeral, delegate: taskDelegate, delegateQueue: .main)
        let (responseBody, response) = try await session.upload(for: request, from: body)
        guard response.status == .ok else {
            handleError(response.status, data: responseBody)
            throw URLError(.badServerResponse)
        }
        return responseBody
    }
    
    private func makeAPIRequest(path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok, headerFields: [HTTPField.Name:String] = [:], taskDelegate: URLSessionTaskDelegate? = nil) async throws -> Data {
        var request = HTTPRequest(method: method, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.referer] = url.absoluteString
        request.headerFields[.authorization] = self.token
        for kvp in headerFields {
            request.headerFields[kvp.key] = kvp.value
        }
        
        let session = URLSession(configuration: .ephemeral, delegate: taskDelegate ?? nil, delegateQueue: .main)
        let (responseBody, response) = try await session.upload(for: request, from: Data())
        guard response.status != .created else {
            handleError(response.status, data: responseBody)
            throw URLError(.badServerResponse)
        }
        return responseBody
    }
    private func makeAPIRequestStreamed(path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok, headerFields: [HTTPField.Name:String] = [:], taskDelegate: URLSessionStreamDelegate) throws -> URLSessionUploadTask{
        var request = HTTPRequest(method: method, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.referer] = url.absoluteString
        request.headerFields[.authorization] = self.token
        for kvp in headerFields {
            request.headerFields[kvp.key] = kvp.value
        }
        
        let session = URLSession(configuration: .ephemeral, delegate: taskDelegate, delegateQueue: .main)
        return session.uploadTask(withStreamedRequest: URLRequest(httpRequest: request)!)
    }
    
    public func getStats(amount: Int? = nil) async -> DFStatsResponse?{
        do{
            let responseBody = try await makeAPIRequest(path: getAPIPath(.stats), parameters: amount == nil ? [:] : ["amount" : amount?.description ?? ""])
            return try decoder.decode(DFStatsResponse.self, from: responseBody)
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
    
    public func deleteFiles(fileIDs: [Int]) async {
        do {
            // Convert array to JSON string
            let fileIDsData = try JSONSerialization.data(withJSONObject: ["ids": fileIDs])

            let _ = try await makeAPIRequest(
                body: fileIDsData,
                path: getAPIPath(.delete_file),
                parameters: [:],
                method: .delete
            )
        } catch {
            print("File Delete Failed \(error)")
        }
    }
    
    public func editFiles(fileIDs: [Int], changes: [String: Any]) async -> Bool {
        do {
            // Combine the file IDs and changes into a single dictionary
            var requestData: [String: Any] = ["ids": fileIDs]
            for (key, value) in changes {
                requestData[key] = value
            }
                        
            // Convert combined dictionary to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: requestData)
            
            let _ = try await makeAPIRequest(
                body: jsonData,
                path: getAPIPath(.edit_file),
                parameters: [:],
                method: .post
            )
            return true
        } catch {
            print("File Edit Failed \(error)")
            return false
        }
    }
    
    public func renameFile(fileID: Int, name: String) async -> Bool {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: ["name": name])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            let _ = try await makeAPIRequest(
                body: jsonData,
                path: getAPIPath(.file) + "\(fileID)",
                parameters: [:],
                method: .post
            )
            return true
        } catch {
            print("File Edit Failed \(error)")
            return false
        }
    }
    
    public func uploadFile(url: URL, fileName: String? = nil, taskDelegate: URLSessionTaskDelegate? = nil) async -> DFUploadResponse?{
        let boundary = UUID().uuidString
        let filename = fileName ?? (url.absoluteString as NSString).lastPathComponent
        
        var data = Data()
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        do{
            try data.append(Data(contentsOf: url))
        }
        catch{
            print("Error reading file \(error)")
            return nil
        }
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        do{
            let responseBody = try await makeAPIRequest(body: data, path: getAPIPath(.upload), parameters: [:], method: .post, expectedResponse: .ok, headerFields: [.contentType: "multipart/form-data; boundary=\(boundary)"], taskDelegate: taskDelegate)
            return try decoder.decode(DFUploadResponse.self, from: responseBody)
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
    
    public func uploadFileStreamed(url: URL, fileName: String? = nil, taskDelegate: URLSessionTaskDelegate) async -> DjangoFilesUploadDelegate?{
        let boundary = UUID().uuidString
        
        do{
            let delegate = DjangoFilesUploadDelegate(fileURL: url, boundary: boundary, originalDelegate: taskDelegate)
            let task = try makeAPIRequestStreamed(path: getAPIPath(.upload), parameters: [:], method: .post, expectedResponse: .ok, headerFields: [.contentType: "multipart/form-data; boundary=\(boundary)"], taskDelegate: delegate)
            task.resume()
            return delegate
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
    
    public func createShort(url: URL, short: String, maxViews: Int? = nil) async -> DFShortResponse?{
        let request = DFShortRequest(url: url.absoluteString, vanity: short, maxViews: maxViews ?? 0)
        do{
            let json = try JSONEncoder().encode(request)
            let responseBody = try await makeAPIRequest(body: json, path: getAPIPath(.short), parameters: [:], method: .post, expectedResponse: .ok, headerFields: [:], taskDelegate: nil)
            return try decoder.decode(DFShortResponse.self, from: responseBody)
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
    
    public func getShorts(amount: Int = 50, start: Int? = nil) async -> ShortsResponse? {
        var parameters: [String: String] = ["amount": "\(amount)"]
        if let start = start {
            parameters["start"] = "\(start)"
        }
        
        do {
            let responseBody = try await makeAPIRequest(
                path: getAPIPath(.shorts),
                parameters: parameters,
                method: .get
            )
            
            let shorts = try decoder.decode([DFShort].self, from: responseBody)
            return ShortsResponse(shorts: shorts)
            
        } catch {
            print("Error fetching shorts: \(error)")
            return nil
        }
    }
    
    public func getAuthMethods() async -> DFAuthMethodsResponse? {
        do {
            let responseBody = try await makeAPIRequest(
                path: getAPIPath(.auth_methods),
                parameters: [:],
                method: .get
            )
            //log response body content
            return try decoder.decode(DFAuthMethodsResponse.self, from: responseBody)
        } catch {
            print("Request failed \(error)")
            return nil
        }
    }

    struct DFLocalLoginRequest: Codable {
        let username: String
        let password: String
    }
    
    struct UserToken: Codable {
        let token: String
    }

    public func localLogin(username: String, password: String, selectedServer: DjangoFilesSession) async -> Bool {
        let request = DFLocalLoginRequest(username: username, password: password)
        do {
            let json = try JSONEncoder().encode(request)
            
            // Create URL request manually to access response headers
            var urlRequest = URLRequest(url: encodeParametersIntoURL(path: getAPIPath(.login), parameters: [:]))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = json
            
            // Use default session configuration which persists cookies
            let configuration = URLSessionConfiguration.default
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            // Extract cookies from response
            if let headerFields = httpResponse.allHeaderFields as? [String: String] {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: urlRequest.url!)
                // Store cookies in the shared cookie storage
                cookies.forEach { cookie in
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                await MainActor.run {
                    selectedServer.cookies = cookies
                }
            }
            
            let userToken = try JSONDecoder().decode(UserToken.self, from: data)
            
            // Update the token in the server object
            await MainActor.run {
                selectedServer.token = userToken.token
            }
            return true
        } catch {
            print("Local login request failed \(error)")
            return false
        }
    }
    
    struct DFOAuthLoginRequest: Codable {
        let token: String
        let sessionKey: String
    }
    
    public func oauthTokenLogin(token: String, sessionKey: String, selectedServer: DjangoFilesSession) async -> Bool {
        let request = DFOAuthLoginRequest(token: token, sessionKey: sessionKey)
        do {
            let json = try JSONEncoder().encode(request)
            
            // Create URL request manually to access response headers
            var urlRequest = URLRequest(url: encodeParametersIntoURL(path: getAPIPath(.login), parameters: [:]))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = json
            
            if let url = urlRequest.url {
                // Set the cookie directly in the request header
                urlRequest.setValue("sessionid=\(sessionKey)", forHTTPHeaderField: "Cookie")
                print("Using session key cookie: \(sessionKey) on \(url)")
                
                // Also set it in the cookie storage
                let cookieProperties: [HTTPCookiePropertyKey: Any] = [
                    .name: "sessionid",
                    .value: sessionKey,
                    .domain: url.host ?? "",
                    .path: "/",
                    .secure: false,
                    .expires: Date().addingTimeInterval(31536000)  // 1 year from now
                ]
                
                if let cookie = HTTPCookie(properties: cookieProperties) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                    print("Set cookie: \(cookie)")
                }
            }
            
            // Use default session configuration which persists cookies
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = .shared
            configuration.httpCookieAcceptPolicy = .always
            
            // Print all cookies before making the request
            print("Cookies before request:")
            HTTPCookieStorage.shared.cookies?.forEach { cookie in
                print(" - \(cookie.name): \(cookie.value)")
            }
            
            let session = URLSession(configuration: configuration)
            let (_, response) = try await session.data(for: urlRequest)
            
            print("response: \(response)")
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw URLError(.badServerResponse)
            }
            
            // Print request headers for debugging
            print("Request headers:")
            urlRequest.allHTTPHeaderFields?.forEach { key, value in
                print(" - \(key): \(value)")
            }
            
            // Print response headers for debugging
            print("Response headers:")
            (response as? HTTPURLResponse)?.allHeaderFields.forEach { key, value in
                print(" - \(key): \(value)")
            }
            
            // Extract cookies from response
            if let headerFields = httpResponse.allHeaderFields as? [String: String] {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: urlRequest.url!)
                // Store cookies in the shared cookie storage
                cookies.forEach { cookie in
                    HTTPCookieStorage.shared.setCookie(cookie)
                    print("Received cookie from response: \(cookie)")
                }
                await MainActor.run {
                    selectedServer.cookies = cookies
                }
            }
            
            // Update the token in the server object
            await MainActor.run {
                selectedServer.token = token
            }
            
            return true
        } catch {
            print("OAuth login request failed \(error)")
            return false
        }
    }

    public func getFiles(page: Int = 1) async -> DFFilesResponse? {
        do {
            let responseBody = try await makeAPIRequest(
                path: getAPIPath(.files) + "\(page)/",
                parameters: [:],
                method: .get
            )
            
            // Use the default decoder since dates are now handled as strings
            let specialDecoder = JSONDecoder()
            specialDecoder.keyDecodingStrategy = .convertFromSnakeCase
            return try specialDecoder.decode(DFFilesResponse.self, from: responseBody)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Missing key: \(key.stringValue) in context: \(context.debugDescription)")
        } catch {
            print("Request failed \(error)")
        }
        return nil
    }

    public func checkRedirect(url: String) async -> String? {
        do {
            guard let targetURL = URL(string: url) else { return nil }
            
            var request = HTTPRequest(method: .get, url: targetURL)
            request.headerFields[.authorization] = self.token
            request.headerFields[.referer] = self.url.absoluteString
            
            let configuration = URLSessionConfiguration.ephemeral
            let delegate = RedirectDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            
            let (_, response) = try await session.data(for: request)
            
            if response.status.code == 302 {
                if let newURL = URL(string: response.headerFields[.location]!) {
                    if newURL.host() == nil {
                        return "\(targetURL.scheme ?? "https")://\(targetURL.host() ?? "")\(response.headerFields[.location] ?? "")"
                    } else {
                        return response.headerFields[.location]
                    }
                }
            }

            return nil
        } catch {
            print("Redirect check failed: \(error)")
            return nil
        }
    }

    // Create and connect to a WebSocket, also setting up WebSocketToastObserver
    public func connectToWebSocket() -> DFWebSocket {
        let webSocket = self.createWebSocket()
        
        // Instead of directly accessing WebSocketToastObserver, post a notification
        // that the observer will pick up
        NotificationCenter.default.post(
            name: Notification.Name("DFWebSocketConnectionRequest"),
            object: nil,
            userInfo: ["api": self]
        )
        
        // Store as the shared instance
        DFAPI.sharedWebSocket = webSocket
        
        return webSocket
    }
    
    // Get the shared WebSocket or create a new one if none exists
    public static func getSharedWebSocket() -> DFWebSocket? {
        return sharedWebSocket
    }
}

class DjangoFilesUploadDelegate: NSObject, StreamDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate, URLSessionStreamDelegate{
    enum States {
        case invalid    //Invalid/uninitialized state
        case started    //Upload started
        case intro      //Uploading intro to multipart data
        case file       //Uploading file
        case outro      //Uploading outro to multipart data
        case complete   //Upload complete
        case error      //Error state
    }
    
    //Upload buffer size
    final let BUFFER_SIZE: Int = 1000000
    
    //File read chunk size
    final let CHUNK_SIZE: Int = 4096
    
    public let originalDelegate: URLSessionTaskDelegate
    public let boundary: String
    
    public let fileName: String
    public let fileURL: URL
    var canWrite: Bool = false
    var error: String? = nil
    var timer: Timer?
    var state: States = .invalid
    
    var intro: Data
    var fileStream: FileHandle
    var dataProgress: Int64
    var size: Int64
    var outro: Data
    
    var multipartProgress: Int = 0
    
    var task: URLSessionTask? = nil
    var session: URLSession? = nil
    
    var response: DFUploadResponse?
    
    struct UploadStreams {
        let input: InputStream
        let output: OutputStream
        var bytesAvailable: Int64 = 0
    }
    lazy var boundStreams: UploadStreams = {
        var inputOrNil: InputStream? = nil
        var outputOrNil: OutputStream? = nil
        Stream.getBoundStreams(withBufferSize: BUFFER_SIZE,
                               inputStream: &inputOrNil,
                               outputStream: &outputOrNil)
        guard let input = inputOrNil, let output = outputOrNil else {
            fatalError("On return of `getBoundStreams`, both `inputStream` and `outputStream` will contain non-nil streams.")
        }
        DispatchQueue.main.async {
            // configure and open output stream
            output.delegate = self
            output.schedule(in: .current, forMode: .default)
            output.open()
        }
        
        self.session = session
        self.task = task
        state = .started
        
        return UploadStreams(input: input, output: output)
    }()
    
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        completionHandler(boundStreams.input)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStreamFrom offset: Int64, completionHandler: @escaping @Sendable (InputStream?) -> Void){
        completionHandler(boundStreams.input)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?){
        self.error = error?.localizedDescription
        if error != nil{
            state = .error
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?){
        self.error = error?.localizedDescription
        if error != nil{
            state = .error
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
    {
        //Tell the original delegate how much data was sent
        originalDelegate.urlSession?(session, task: task, didSendBodyData: bytesSent, totalBytesSent: self.dataProgress, totalBytesExpectedToSend: self.size)
    }
    
    func waitForComplete() async -> DFUploadResponse?{
        while task?.state != .completed{
            do{
                try await Task.sleep(for: .milliseconds(100))
            }
            catch{
            }
        }
        return response
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: Data){
        if dataTask.httpResponse != nil{
            if dataTask.httpResponse!.status == 200 { }
            else if dataTask.httpResponse!.status == 499{
                error = "Upload timeout. (499)"
                state = .error
                return
            }
            else{
                error = "Response error. (\(dataTask.httpResponse!.status))"
                state = .error
                return
            }
        }
        
        do{
            response = try JSONDecoder().decode(DFUploadResponse.self, from: didReceive)
        }
        catch{
            response = nil
            state = .error
        }
    }
    
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask){
        self.task = task
    }
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream == boundStreams.output else {
            return
        }
        if eventCode.contains(.openCompleted){
            print("DFAPI: Stream opened.")
        }
        if eventCode.contains(.hasSpaceAvailable) {
            canWrite = true
        }
        if eventCode.contains(.endEncountered){
            print("DFAPI: Stream closed.")
        }
        if eventCode.contains(.errorOccurred) {
            error = "Stream error"
            state = .complete
        }
    }
    
    func isComplete() -> Bool{
        return state == .complete || state == .error
    }
    
    init(fileURL: URL, boundary: String, originalDelegate: URLSessionTaskDelegate, fileName: String? = nil) {
        self.boundary = boundary
        self.originalDelegate = originalDelegate
        self.fileURL = fileURL
        
        self.fileName = fileName ?? (fileURL.absoluteString as NSString).lastPathComponent
        
        self.intro = Data()
        self.outro = Data()
        
        self.dataProgress = 0
        
        do{
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
            self.size = attributes[FileAttributeKey.size] as! Int64
            self.fileStream = try FileHandle(forReadingFrom: fileURL)
        }
        catch{
            state = .complete
            self.error = "Could not read file: \(error)"
            self.fileStream = FileHandle()
            self.size = 0
            super.init()
            return
        }
        
        super.init()
        
        //Create the multipart form data
        self.intro.append("\r\n--\(self.boundary)\r\n".data(using: .utf8)!)
        self.intro.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(self.fileName)\"\r\n".data(using: .utf8)!)
        self.intro.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        
        self.outro.append("\r\n--\(self.boundary)--\r\n".data(using: .utf8)!)
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.0, repeats: true) {
                [weak self] timer in
                guard let self = self else { return }
                
                if self.canWrite {
                    let message: Data
                    switch state{
                    case .intro:
                        //Send as much of the multipart form data as possible
                        message = intro.subdata(in: multipartProgress..<intro.count)
                        break
                    case .outro:
                        //Send as much of the multipart form data as possible
                        message = outro.subdata(in: multipartProgress..<outro.count)
                    case .file:
                        do{
                            //Send as much of the file as possible
                            message = try fileStream.read(upToCount: CHUNK_SIZE)!
                        }
                        catch{
                            self.state = .error
                            return
                        }
                    case .invalid:
                        return
                    case .started:
                        print ("DFAPI: Timer started.")
                        multipartProgress = 0
                        state = .intro
                        return
                    case .error:
                        print ("DFAPI: File upload state error.")
                        self.boundStreams.output.close()
                        timer.invalidate()
                        return
                    case .complete:
                        print ("DFAPI: File upload complete.")
                        self.boundStreams.output.close()
                        timer.invalidate()
                        return
                    }
                    let messageData = message
                    let messageCount = messageData.count
                    do{
                        let bytesWritten: Int = messageData.withUnsafeBytes {
                            self.boundStreams.output.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: messageData.count)
                        }
                        if self.state == .file {
                            //If uploading file, save the amount of data written to stream
                            dataProgress += Int64(bytesWritten)
                        }
                        if bytesWritten < messageCount {
                            if self.state == .file {
                                do{
                                    //Not all data was written, seek back to where we left off
                                    try fileStream.seek(toOffset: fileStream.offset() - UInt64(messageCount - bytesWritten))
                                }
                                catch{
                                    state = .error
                                    self.error = "Stream overflowed and could not seek back."
                                    timer.invalidate()
                                }
                            }
                        }
                        if self.state != .file{
                            //Not all data was written, store how much was
                            self.multipartProgress += bytesWritten
                        }
                    }
                    canWrite = false
                    
                    switch state{
                    case .intro:
                        if multipartProgress == intro.count{
                            print ("DFAPI: Intro sent.")
                            state = .file
                            multipartProgress = 0
                        }
                        break
                    case .outro:
                        if multipartProgress == outro.count{
                            print ("DFAPI: Outro sent.")
                            state = .complete
                            multipartProgress = 0
                        }
                    case .file:
                        do{
                            if try fileStream.offset() == self.size {
                                print ("DFAPI: File sent.")
                                state = .outro
                                multipartProgress = 0
                            }
                        }
                        catch{
                            print ("DFAPI: File upload read error.")
                            self.error = "Read error"
                            state = .error
                        }
                    case .invalid:
                        return
                    case .started:
                        return
                    case .error:
                        print ("DFAPI: File upload state error.")
                        self.boundStreams.output.close()
                        timer.invalidate()
                        return
                    case .complete:
                        print ("DFAPI: File upload complete.")
                        self.boundStreams.output.close()
                        timer.invalidate()
                        return
                    }
                }
            }
        }
    }
}

struct DFAuthMethod: Codable {
    let name: String
    let url: String
}

struct DFAuthMethodsResponse: Codable {
    let authMethods: [DFAuthMethod]
    let siteName: String
}

class RedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Don't follow the redirect by passing nil
        completionHandler(nil)
    }
}
