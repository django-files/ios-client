//
//  Files.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/23/25.
//

import Foundation

public struct DFFile: Codable, Hashable, Equatable {
    public let id: Int
    public let user: Int
    public let size: Int
    public let mime: String
    public let name: String
    public let userName: String
    public let userUsername: String
    public let info: String
    public let expr: String
    public let view: Int
    public let maxv: Int
    public let password: String
    public let `private`: Bool
    public let avatar: Bool
    public let url: String
    public let thumb: String
    public let raw: String
    public let date: String
    public let albums: [Int]
    
    // Skip nested JSON structures
    enum CodingKeys: String, CodingKey {
        case id, user, size, mime, name, info, expr, view, maxv, password, `private`, avatar, userName, userUsername, url, thumb, raw, date, albums
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
    
    // Add hash implementation for Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Add equality implementation for Equatable conformance
    public static func == (lhs: DFFile, rhs: DFFile) -> Bool {
        return lhs.id == rhs.id
    }
}

public struct DFFilesResponse: Codable {
    public let files: [DFFile]
    public let next: Int?
    public let count: Int
}
