//
//  Stats.swift
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
        var container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(String.self, forKey: .error)
        do{
            message = try container.decode(String.self, forKey: .message)
        }
        catch { message = "" }
    }
}
