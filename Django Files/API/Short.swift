//
//  Stats.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation

struct DFShortRequest: Encodable{
    let url: String
    let vanity: String
    let maxViews: Int
    
    enum CodingKeys: String, CodingKey {
        case url = "url"
        case vanity = "vanity"
        case maxViews = "max-views"
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(vanity, forKey: .vanity)
        try container.encode(maxViews, forKey: .maxViews)
    }
}


struct DFShortResponse: Codable{
    let url: String
    
    enum CodingKeys: String, CodingKey {
        case url = "url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
    }
}

struct DFShort: Identifiable, Codable, Hashable {
    let id: Int
    let short: String
    let url: String
    let max: Int
    let views: Int
    let user: Int
    let fullUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id, short, url, max, views, user, fullUrl
    }
}

// Response structure for shorts API call
struct ShortsResponse: Codable {
    let shorts: [DFShort]
    
    init(shorts: [DFShort]) {
        self.shorts = shorts
    }
    
    enum CodingKeys: String, CodingKey {
        case shorts
    }
}
