//
//  RecentUploadTracker.swift
//  Django Files
//

import Foundation

/// Tracks server-assigned names of files we just uploaded so the matching
/// `file-new` websocket toast can be suppressed. Entries expire after `ttl`
/// to avoid swallowing an unrelated toast if names ever collide.
final class RecentUploadTracker {
    static let shared = RecentUploadTracker()

    private let queue = DispatchQueue(label: "RecentUploadTracker")
    private var entries: [String: Date] = [:]
    private let ttl: TimeInterval = 60

    func record(name: String) {
        queue.sync {
            prune()
            entries[name] = Date()
        }
    }

    /// Removes and returns true if `name` was recorded within the TTL window.
    func consume(name: String) -> Bool {
        queue.sync {
            prune()
            guard entries.removeValue(forKey: name) != nil else { return false }
            return true
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-ttl)
        entries = entries.filter { $0.value > cutoff }
    }
}
