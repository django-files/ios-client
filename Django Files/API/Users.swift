//
//  Users.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/8/25.
//

import Foundation

public struct DFUser: Codable {
    public let id: Int
    public let username: String
    public let firstName: String
    public let lastName: String
    public let email: String
    public let lastLogin: Date?
    public let dateJoined: Date
    public let isSuperuser: Bool
    public let isStaff: Bool
    public let isActive: Bool
    public let timezone: String
    public let defaultExpire: String
    public let defaultColor: String
    public let navColor1: String
    public let navColor2: String
    public let removeExifGeo: Bool
    public let removeExif: Bool
    public let showExifPreview: Bool
    public let defaultUploadNameFormat: String
    public let defaultFilePrivate: Bool
    public let defaultFilePassword: Bool
    public let storageQuota: Int
    public let storageUsage: Int
    public let avatarUrl: String
    public let userAvatarChoice: String
    public let groups: [String]
    public let userPermissions: [String]
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Configure date decoder
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        firstName = try container.decode(String.self, forKey: .firstName)
        lastName = try container.decode(String.self, forKey: .lastName)
        email = try container.decode(String.self, forKey: .email)
        
        // Decode dates
        if let lastLoginStr = try container.decodeIfPresent(String.self, forKey: .lastLogin),
           let lastLoginDate = dateFormatter.date(from: lastLoginStr) {
            lastLogin = lastLoginDate
        } else {
            lastLogin = nil
        }
        
        if let dateJoinedStr = try container.decode(String.self, forKey: .dateJoined) as String?,
           let dateJoinedDate = dateFormatter.date(from: dateJoinedStr) {
            dateJoined = dateJoinedDate
        } else {
            throw DecodingError.dataCorruptedError(forKey: .dateJoined, in: container, debugDescription: "Date string does not match format")
        }
        
        isSuperuser = try container.decode(Bool.self, forKey: .isSuperuser)
        isStaff = try container.decode(Bool.self, forKey: .isStaff)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        timezone = try container.decode(String.self, forKey: .timezone)
        defaultExpire = try container.decode(String.self, forKey: .defaultExpire)
        defaultColor = try container.decode(String.self, forKey: .defaultColor)
        navColor1 = try container.decode(String.self, forKey: .navColor1)
        navColor2 = try container.decode(String.self, forKey: .navColor2)
        removeExifGeo = try container.decode(Bool.self, forKey: .removeExifGeo)
        removeExif = try container.decode(Bool.self, forKey: .removeExif)
        showExifPreview = try container.decode(Bool.self, forKey: .showExifPreview)
        defaultUploadNameFormat = try container.decode(String.self, forKey: .defaultUploadNameFormat)
        defaultFilePrivate = try container.decode(Bool.self, forKey: .defaultFilePrivate)
        defaultFilePassword = try container.decode(Bool.self, forKey: .defaultFilePassword)
        storageQuota = try container.decode(Int.self, forKey: .storageQuota)
        storageUsage = try container.decode(Int.self, forKey: .storageUsage)
        avatarUrl = try container.decode(String.self, forKey: .avatarUrl)
        userAvatarChoice = try container.decode(String.self, forKey: .userAvatarChoice)
        groups = try container.decode([String].self, forKey: .groups)
        userPermissions = try container.decode([String].self, forKey: .userPermissions)
    }
}


extension DFAPI {
    public func getCurrentUser(selectedServer: DjangoFilesSession? = nil) async -> DFUser? {
        do {
            let responseBody = try await makeAPIRequest(
                body: Data(),
                path: getAPIPath(.user),
                parameters: [:],
                method: .get,
                selectedServer: selectedServer
            )
            let specialDecoder = JSONDecoder()
            specialDecoder.keyDecodingStrategy = .convertFromSnakeCase
            return try specialDecoder.decode(DFUser.self, from: responseBody)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Missing key: \(key.stringValue) in context: \(context.debugDescription)")
        } catch {
            print("Request failed \(error)")
        }
        return nil
    }
    
    public func getUsers(after userId: Int? = nil, selectedServer: DjangoFilesSession? = nil) async -> [DFUser]? {
        var parameters: [String: String] = ["amount": "20"]
        if let userId = userId {
            parameters["after"] = String(userId)
        }
        
        do {
            let responseBody = try await makeAPIRequest(
                body: Data(),
                path: getAPIPath(.users),
                parameters: parameters,
                method: .get,
                selectedServer: selectedServer
            )
            let specialDecoder = JSONDecoder()
            specialDecoder.keyDecodingStrategy = .convertFromSnakeCase
            return try specialDecoder.decode([DFUser].self, from: responseBody)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Missing key: \(key.stringValue) in context: \(context.debugDescription)")
        } catch {
            print("Request failed \(error)")
        }
        return nil
    }
    
    public func getAllUsers(selectedServer: DjangoFilesSession? = nil) async -> [DFUser] {
        var allUsers: [DFUser] = []
        var lastUserId: Int? = nil
        
        while true {
            guard let users = await getUsers(after: lastUserId, selectedServer: selectedServer) else {
                break
            }
            
            // If we got no users back, we're done
            if users.isEmpty {
                break
            }
            
            // Add the users to our collection
            allUsers.append(contentsOf: users)
            
            // Update the lastUserId for the next request
            lastUserId = users.last?.id
        }
        
        return allUsers
    }
    
    @MainActor
    public func updateSessionWithUserData(_ session: DjangoFilesSession) async -> Bool {
        guard let user = await getCurrentUser(selectedServer: session) else {
            return false
        }
        
        // Update session with user data
        session.userID = user.id
        session.username = user.username
        session.firstName = user.firstName
        // Handle avatar URL more robustly
        if let avatarURL = URL(string: user.avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)) {
            session.avatarUrl = avatarURL
        } else {
            print("Warning: Invalid avatar URL received from server: \(user.avatarUrl)")
            session.avatarUrl = nil
        }
        session.superUser = user.isSuperuser
        session.defaultColor = user.defaultColor
        session.navColorOne = user.navColor1
        session.navColorTwo = user.navColor2
        session.defaultFilePrivate = user.defaultFilePrivate
        session.defaultFilePassword = user.defaultFilePassword
        session.defaultFileExpire = user.defaultExpire
        session.defaultFileRemoveExif = user.removeExif
        session.defaultFileUploadNameFormat = user.defaultUploadNameFormat
        session.auth = true
        
        return true
    }
}
