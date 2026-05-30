//
//  Error.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation

struct DFErrorResponse: Codable{
    var error: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case error = "error"
        case message = "message"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(String.self, forKey: .error)
        do{
            message = try container.decode(String.self, forKey: .message)
        }
        catch { message = "" }
    }
}

/// Typed error surfaced from `makeAPIRequest`. Provides a user-readable description
/// suitable for display in list error states.
enum DFAPIError: LocalizedError {
    /// Server returned a non-2xx with a parseable `{error, message}` body.
    case server(status: Int, error: String, message: String)
    /// Server returned a non-2xx without a parseable body.
    case httpStatus(Int)
    /// URLSession / transport failure.
    case transport(URLError)
    /// Could not decode the success response.
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case let .server(status, error, message):
            let body = message.isEmpty ? error : message
            return body.isEmpty ? "Server returned \(status)." : "\(body) (\(status))"
        case let .httpStatus(status):
            return "Server returned \(status)."
        case let .transport(err):
            return err.localizedDescription
        case .decoding:
            return "The server response could not be read."
        }
    }
}
