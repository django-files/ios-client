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
    
    private func makeAPIRequest<T>(_ bodyType: T.Type, from body: Data, path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok) async throws -> Data where T : Decodable
    {
        var request = HTTPRequest(method: .get, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.authorization] = token
        let (responseBody, response) = try await URLSession.shared.upload(for: request, from: JSONDecoder().decode(bodyType, from: body) as! Data)
        guard response.status == .ok else {
            throw URLError(.badServerResponse)
        }
        return responseBody
    }
    
    private func makeAPIRequest(path: String, parameters: [String:String], method: HTTPRequest.Method = .get, expectedResponse: HTTPResponse.Status = .ok) async throws -> Data {
        var request = HTTPRequest(method: .get, url: encodeParametersIntoURL(path: path, parameters: parameters))
        request.headerFields[.referer] = url.absoluteString
        request.headerFields[.authorization] = self.token
        let (responseBody, response) = try await URLSession.shared.upload(for: request, from: Data())
        guard response.status != .created else {
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
}
