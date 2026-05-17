//
//  MapGeoCache.swift
//  Django Files
//

import Foundation

/// Persists GPS-tagged file data between map opens.
/// @MainActor so callers inside SwiftUI Tasks (which inherit the main actor) can
/// read/write synchronously — no actor hops needed.
@MainActor
final class MapGeoCacheStore {
    static let shared = MapGeoCacheStore()
    private init() {}

    struct Entry: @unchecked Sendable {
        let file: DFFile
        let lat: Double
        let lon: Double
    }

    // Keyed by server base URL string → file ID → Entry
    private var entriesByServer: [String: [Int: Entry]] = [:]
    // All file IDs seen from the API (geo or not) — used to detect "fully caught up" pages
    private var seenIDsByServer: [String: Set<Int>] = [:]
    // Servers whose last load finished all pages; only then is the
    // "fullyKnown" shortcut safe to use.
    private var fullySyncedServers: Set<String> = []

    func entries(for server: String) -> [Entry] {
        Array((entriesByServer[server] ?? [:]).values)
    }

    /// Returns true if every ID in `ids` was already recorded for this server
    /// AND the server completed a full prior sync.
    func isPageFullyKnown(_ ids: Set<Int>, for server: String) -> Bool {
        guard fullySyncedServers.contains(server),
              let seen = seenIDsByServer[server], !seen.isEmpty else { return false }
        return ids.isSubset(of: seen)
    }

    func mark(seen ids: Set<Int>, entries newEntries: [Entry], for server: String) {
        seenIDsByServer[server, default: []].formUnion(ids)
        for e in newEntries {
            entriesByServer[server, default: [:]][e.file.id] = e
        }
    }

    func markFullySynced(_ server: String) {
        fullySyncedServers.insert(server)
    }

    func invalidate(for server: String) {
        entriesByServer.removeValue(forKey: server)
        seenIDsByServer.removeValue(forKey: server)
    }
}
