//
//  Stats.swift
//  Django Files
//
//  Created by Michael on 2/16/25.
//

import Foundation

struct DFStatsResponse: Codable{
    var stats: [DFStat] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while (!container.isAtEnd){
            stats.append(try container.decode(DFStat.self))
        }
    }
}

struct DFStat: Codable{
    let model: String
    let pk: Int
    let fields: DFStatField
    
    enum CodingKeys: String, CodingKey {
        case model = "model"
        case pk = "pk"
        case fields = "fields"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        pk = try container.decode(Int.self, forKey: .pk)
        fields = try container.decode(DFStatField.self, forKey: .fields)
    }
}

struct DFStatField: Codable{
    let user: Int
    let stats: DFStatContainer
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case user = "user"
        case stats = "stats"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(Int.self, forKey: .user)
        stats = try container.decode(DFStatContainer.self, forKey: .stats)
        createdAt = try? container.decode(Date.self, forKey: .createdAt)
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
    }
}

struct DFStatContainer: Codable{
    var types: [DFStatType] = []
    let size: Int64
    let count: Int
    let shorts: Int
    let humanSize: String

    enum CodingKeys: String, CodingKey {
        case types = "types"
        case size = "size"
        case count = "count"
        case shorts = "shorts"
        case humanSize = "human_size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typesContainer = try container.decode([String : DFStatType].self, forKey: .types)

        for item in typesContainer{
            types.append(DFStatType(name: item.key, source: item.value))
        }

        size = try container.decode(Int64.self, forKey: .size)
        count = try container.decode(Int.self, forKey: .count)
        shorts = try container.decode(Int.self, forKey: .shorts)
        humanSize = (try? container.decode(String.self, forKey: .humanSize)) ?? ""
    }
}

struct DFStatType: Codable{
    let name: String
    let size: Int64
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case size = "size"
        case count = "count"
    }
    
    init(name: String, source: DFStatType) {
        self.name = name
        self.size = source.size
        self.count = source.count
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = ""
        size = try container.decode(Int64.self, forKey: .size)
        count = try container.decode(Int.self, forKey: .count)
    }
}

extension DFAPI {
    public func getStats(amount: Int? = nil, selectedServer: DjangoFilesSession? = nil) async -> DFStatsResponse? {
        do {
            var parameters: [String: String] = [:]
            if let amount { parameters["amount"] = String(amount) }
            let responseBody = try await makeAPIRequest(
                path: getAPIPath(.stats),
                parameters: parameters,
                selectedServer: selectedServer
            )
            return try decoder.decode(DFStatsResponse.self, from: responseBody)
        } catch {
            print("Request failed \(error)")
            return nil
        }
    }
}
