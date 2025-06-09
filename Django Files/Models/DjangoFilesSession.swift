//
//  Item.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import Foundation
import SwiftData

@Model
public final class DjangoFilesSession: Equatable, @unchecked Sendable {
    var url: String
    var defaultSession: Bool = false
    var token: String
    var auth: Bool = false
    var userID: Int?
    var username: String?
    var firstName: String?
    var avatarUrl: URL?
    var superUser: Bool = false
    var defaultColor: String?
    var navColorOne: String?
    var navColorTwo: String?
    var defaultFilePrivate: Bool = false
    var defaultFilePassword: Bool = false
    var defaultFileExpire: String?
    var defaultFileRemoveExif: Bool = false
    var defaultFileUploadNameFormat: String = "name"
    
    
    @Transient var cookies: [HTTPCookie] = []
    
    init() {
        self.url = ""
        self.token = ""
    }
    init(url: String) {
        self.url = url
        self.token = ""
    }
    init(url: String, token: String) {
        self.url = url
        self.token = token
    }
    
    func checkSession() -> Bool {
        return true
    }
    
    public static func == (lhs: DjangoFilesSession, rhs: DjangoFilesSession) -> Bool{
        return lhs.url == rhs.url
    }
}
