//
//  Stats.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation

struct DFUploadResponse: Codable{
    var files: [String] = []
    let url: String
    let raw: String
    let r: String
    let name: String
    let size: Int
    
    enum CodingKeys: String, CodingKey {
        case files = "files"
        case url = "url"
        case raw = "raw"
        case r = "r"
        case name = "name"
        case size = "size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var fileContainer = try container.nestedUnkeyedContainer(forKey: .files)
        while (!fileContainer.isAtEnd){
            files.append(try fileContainer.decode(String.self))
        }
        url = try container.decode(String.self, forKey: .url)
        raw = try container.decode(String.self, forKey: .raw)
        r = try container.decode(String.self, forKey: .r)
        name = try container.decode(String.self, forKey: .name)
        size = try container.decode(Int.self, forKey: .size)
    }
}
