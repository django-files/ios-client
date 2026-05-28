//
//  ScreenshotDisplay.swift
//  Django Files
//
//  When launched with --ObfuscateForScreenshots, this swaps real server
//  hostnames and usernames for realistic placeholders so credentials/PII
//  don't leak into automated App Store screenshots. No-op otherwise.
//

import Foundation

enum ScreenshotDisplay {
    static let isActive: Bool =
        ProcessInfo.processInfo.arguments.contains("--ObfuscateForScreenshots")

    static let dummyHost = "files.example.com"
    static let dummyUsername = "demo"
    static let dummyFirstName = "Demo User"

    static func host(_ original: String) -> String {
        isActive ? dummyHost : original
    }

    static func username(_ original: String) -> String {
        isActive ? dummyUsername : original
    }

    static func firstName(_ original: String) -> String {
        isActive ? dummyFirstName : original
    }
}
