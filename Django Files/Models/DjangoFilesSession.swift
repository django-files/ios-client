//
//  Item.swift
//  Django Files
//
//  Created by Michael on 2/14/25.
//

import Foundation
import SwiftData

@Model
final class DjangoFilesSession {
    var url: String
    var defaultSession: Bool = false
    var token: String
    var auth: Bool = false
    
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
}
