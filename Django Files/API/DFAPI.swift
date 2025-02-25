//
//  DFAPI.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation
import HTTPTypes
import HTTPTypesFoundation

struct DFAPI {
    private static let API_PATH = "/api/"
    
    enum DjangoFilesAPIs: String {
        case stats = "stats/"
        case upload = "upload"
        case short = "shorten/"
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
    
    private func makeAPIRequest(body: Data, path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok, headerFields: [HTTPField.Name:String] = [:]) async throws -> Data
    {
        var request = HTTPRequest(method: method, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.authorization] = token
        request.headerFields[.referer] = url.absoluteString
        for kvp in headerFields {
            request.headerFields[kvp.key] = kvp.value
        }
        let (responseBody, response) = try await URLSession.shared.upload(for: request, from: body)
        guard response.status == .ok else {
            handleError(response.status, data: responseBody)
            throw URLError(.badServerResponse)
        }
        return responseBody
    }
    
    private func makeAPIRequest(path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok, headerFields: [HTTPField.Name:String] = [:]) async throws -> Data {
        var request = HTTPRequest(method: method, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.referer] = url.absoluteString
        request.headerFields[.authorization] = self.token
        for kvp in headerFields {
            request.headerFields[kvp.key] = kvp.value
        }
        let (responseBody, response) = try await URLSession.shared.upload(for: request, from: Data())
        guard response.status != .created else {
            handleError(response.status, data: responseBody)
            throw URLError(.badServerResponse)
        }
        return responseBody
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
    
    public func uploadFile(url: URL, fileName: String? = nil) async -> DFUploadResponse?{
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
            let responseBody = try await makeAPIRequest(body: data, path: getAPIPath(.upload), parameters: [:], method: .post, expectedResponse: .ok, headerFields: [.contentType: "multipart/form-data; boundary=\(boundary)"])
            return try decoder.decode(DFUploadResponse.self, from: responseBody)
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
    
    public func createShort(url: URL, short: String, maxViews: Int? = nil) async -> DFShortResponse?{
        let request = DFShortRequest(url: url.absoluteString, vanity: short, maxViews: maxViews ?? 0)
        do{
            let json = try JSONEncoder().encode(request)
            let responseBody = try await makeAPIRequest<DFShortRequest>(body: json, path: getAPIPath(.short), parameters: [:], method: .post, expectedResponse: .ok, headerFields: [:])
            return try decoder.decode(DFShortResponse.self, from: responseBody)
        }catch {
            print("Request failed \(error)")
            return nil;
        }
    }
}
