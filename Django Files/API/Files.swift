//
//  Files.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/23/25.
//

import Foundation

public struct DFFile: Codable, Hashable, Equatable {
    public var id: Int
    public var user: Int
    public var size: Int
    public var mime: String
    public var name: String
    public var userName: String
    public var userUsername: String
    public var info: String
    public var expr: String
    public var view: Int
    public var maxv: Int
    public var password: String
    public var `private`: Bool
    public var avatar: Bool
    public var url: String
    public var thumb: String
    public var raw: String
    public var date: String
    public var albums: [Int]
    public var exif: [String: AnyCodable]?
    public var meta: [String: AnyCodable]?
    
    // Skip nested JSON structures
    enum CodingKeys: String, CodingKey {
        case id, user, size, mime, name, info, expr, view, maxv, password, `private`, avatar, userName, userUsername, url, thumb, raw, date, albums, exif, meta
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        user = try container.decode(Int.self, forKey: .user)
        size = try container.decode(Int.self, forKey: .size)
        mime = try container.decode(String.self, forKey: .mime)
        name = try container.decode(String.self, forKey: .name)
        userName = try container.decode(String.self, forKey: .userName)
        userUsername = try container.decode(String.self, forKey: .userUsername)
        info = try container.decode(String.self, forKey: .info)
        expr = try container.decode(String.self, forKey: .expr)
        view = try container.decode(Int.self, forKey: .view)
        maxv = try container.decode(Int.self, forKey: .maxv)
        password = try container.decode(String.self, forKey: .password)
        `private` = try container.decode(Bool.self, forKey: .private)
        avatar = try container.decode(Bool.self, forKey: .avatar)
        url = try container.decode(String.self, forKey: .url)
        thumb = try container.decode(String.self, forKey: .thumb)
        raw = try container.decode(String.self, forKey: .raw)
        date = try container.decode(String.self, forKey: .date)
        albums = try container.decode([Int].self, forKey: .albums)
        
        // Decode exif and meta as dynamic JSON objects
        if let exifContainer = try? container.decode([String: AnyCodable].self, forKey: .exif) {
            exif = exifContainer
        } else {
            exif = nil
        }
        
        if let metaContainer = try? container.decode([String: AnyCodable].self, forKey: .meta) {
            meta = metaContainer
        } else {
            meta = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(user, forKey: .user)
        try container.encode(size, forKey: .size)
        try container.encode(mime, forKey: .mime)
        try container.encode(name, forKey: .name)
        try container.encode(userName, forKey: .userName)
        try container.encode(userUsername, forKey: .userUsername)
        try container.encode(info, forKey: .info)
        try container.encode(expr, forKey: .expr)
        try container.encode(view, forKey: .view)
        try container.encode(maxv, forKey: .maxv)
        try container.encode(password, forKey: .password)
        try container.encode(`private`, forKey: .private)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(url, forKey: .url)
        try container.encode(thumb, forKey: .thumb)
        try container.encode(raw, forKey: .raw)
        try container.encode(date, forKey: .date)
        try container.encode(albums, forKey: .albums)
        try container.encode(exif, forKey: .exif)
        try container.encode(meta, forKey: .meta)
    }
    
    // Helper property to get a Date object when needed
    public var dateObject: Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = iso8601Formatter.date(from: date) {
            return date
        }
        
        // Fall back to other formatters if needed
        let backupFormatter = DateFormatter()
        backupFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        backupFormatter.locale = Locale(identifier: "en_US_POSIX")
        backupFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        if let date = backupFormatter.date(from: date) {
            return date
        }
        
        return nil
    }
    
    // Format the date string for display
    public func formattedDate() -> String {
        guard let date = dateObject else {
            return date // Return the raw string if we can't parse it
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Format file size to human readable string
    public func formatSize() -> String {
        let bytes = Double(size)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var index = 0
        var value = bytes
        
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        
        // Format with appropriate decimal places
        if index == 0 {
            return "\(Int(value)) \(units[index])"
        } else {
            return String(format: "%.1f %@", value, units[index])
        }
    }
    
    // Add hash implementation for Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Add equality implementation for Equatable conformance
    public static func == (lhs: DFFile, rhs: DFFile) -> Bool {
        return lhs.id == rhs.id
    }
}

// Helper type to handle dynamic JSON values
public struct AnyCodable: Codable {
    private let storage: Any
    
    public init(_ value: Any) {
        self.storage = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.storage = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.storage = bool
        } else if let int = try? container.decode(Int.self) {
            self.storage = int
        } else if let double = try? container.decode(Double.self) {
            self.storage = double
        } else if let string = try? container.decode(String.self) {
            self.storage = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.storage = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.storage = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch storage {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(storage, context)
        }
    }
    
    public var value: Any {
        switch storage {
        case let array as [AnyCodable]:
            return array.map { $0.value }
        case let dict as [String: AnyCodable]:
            return dict.mapValues { $0.value }
        default:
            return storage
        }
    }
}

public struct DFFilesResponse: Codable {
    public let files: [DFFile]
    public let next: Int?
    public let count: Int
}

extension DFAPI {
    public func getFiles(page: Int = 1, album: Int? = nil, selectedServer: DjangoFilesSession? = nil, filterUserID: Int? = nil) async -> DFFilesResponse? {
        do {
            var parameters: [String: String] = [:]
            if let album = album {
                parameters["album"] = String(album)
            }
            if filterUserID != nil {
                parameters["user"] = String(filterUserID!)
            }
            
            let responseBody = try await makeAPIRequest(
                body: Data(),
                path: getAPIPath(.files) + "\(page)/",
                parameters: parameters,
                method: .get,
                selectedServer: selectedServer
            )
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
    
    public func getFileDetails(fileID: Int, password: String? = nil, selectedServer: DjangoFilesSession? = nil) async -> DFFile? {
        do {
            var parameters: [String: String] = [:]
            if let password = password {
                parameters["password"] = password
            }
            
            let responseBody = try await makeAPIRequest(
                body: Data(),
                path: getAPIPath(.file) + "\(fileID)",
                parameters: parameters,
                method: .get,
                selectedServer: selectedServer
            )
            let specialDecoder = JSONDecoder()
            specialDecoder.keyDecodingStrategy = .convertFromSnakeCase
            return try specialDecoder.decode(DFFile.self, from: responseBody)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Missing key: \(key.stringValue) in context: \(context.debugDescription)")
        } catch {
            print("Request failed \(error)")
        }
        return nil
    }
    
    public func deleteFiles(fileIDs: [Int], selectedServer: DjangoFilesSession? = nil) async -> Bool {
        do {
            let fileIDsData = try JSONSerialization.data(withJSONObject: ["ids": fileIDs])
            let _ = try await makeAPIRequest(
                body: fileIDsData,
                path: getAPIPath(.delete_file),
                parameters: [:],
                method: .delete,
                selectedServer: selectedServer
            )
            return true
        } catch {
            print("File Delete Failed \(error)")
            return false
        }
    }
    
    public func editFiles(fileIDs: [Int], changes: [String: Any], selectedServer: DjangoFilesSession? = nil) async -> Bool {
        do {
            var requestData: [String: Any] = ["ids": fileIDs]
            for (key, value) in changes {
                requestData[key] = value
            }
            let jsonData = try JSONSerialization.data(withJSONObject: requestData)
            let _ = try await makeAPIRequest(
                body: jsonData,
                path: getAPIPath(.edit_file),
                parameters: [:],
                method: .post,
                selectedServer: selectedServer
            )
            return true
        } catch {
            print("File Edit Failed \(error)")
            return false
        }
    }
    
    public func renameFile(fileID: Int, name: String, selectedServer: DjangoFilesSession? = nil) async -> Bool {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: ["name": name])
            let _ = try await makeAPIRequest(
                body: jsonData,
                path: getAPIPath(.file) + "\(fileID)",
                parameters: [:],
                method: .post,
                selectedServer: selectedServer
            )
            return true
        } catch {
            print("File Edit Failed \(error)")
            return false
        }
    }
}
