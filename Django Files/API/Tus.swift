//
//  Tus.swift
//  Django Files
//
//  tus resumable upload client (https://tus.io/protocols/resumable-upload).
//
//  django-files fronts a tusd sidecar at `/tus/` when TUS_ENABLED, always proxied by nginx
//  regardless of that flag — so an unreachable/disabled server surfaces as a non-201 response
//  to the creation POST rather than a connection failure. Older servers without the tus branch
//  don't have the `/tus/` route at all and 404 the same way. Either case is treated as
//  "tus unusable right now" and the caller transparently falls back to the legacy multipart
//  `/api/upload/` endpoint, so this is safe to attempt against any server.
//
//  Import on the server is async (Celery), so a finished PATCH doesn't carry the file's URL —
//  we poll `/api/files/` for a same-name/same-size match for a few seconds and, failing that,
//  still report success since the upload itself completed; the file will simply appear once
//  server-side processing catches up.

import Foundation

enum TusUploadError: Error {
    /// This server can't take a tus upload right now (no route, disabled, or an
    /// unrecognized response) — caller should fall back to the legacy endpoint.
    case notSupported
    /// The server understood the tus request and explicitly rejected it (bad auth, over
    /// quota, oversized). Falling back to legacy upload would very likely hit the same
    /// rejection, but we still let the caller decide.
    case rejected(status: Int, message: String)
    /// Chunk transfer could not proceed (read/seek failure, malformed tus response, or
    /// retries exhausted).
    case interrupted
}

/// User-facing tus preferences, editable from the Uploads settings screen. Backed by the
/// app-group `UserDefaults` suite (rather than `.standard`) so the share extension — which
/// runs as its own process — reads the same values the main app writes.
enum TusUploadSettings {
    private static let appGroupID = "group.djangofiles.app"

    static let enabledDefaultsKey = "tusUploadsEnabled"
    static let chunkSizeMBDefaultsKey = "tusChunkSizeMB"
    static let defaultChunkSizeMB = 40
    static let availableChunkSizesMB = [10, 20, 40, 60, 90]

    static var store: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        store.object(forKey: enabledDefaultsKey) == nil ? true : store.bool(forKey: enabledDefaultsKey)
    }

    static var chunkSizeBytes: Int {
        let mb = store.object(forKey: chunkSizeMBDefaultsKey) as? Int ?? defaultChunkSizeMB
        return mb * 1024 * 1024
    }
}

/// Servers that have already told us they can't do tus this run, so repeated uploads to the
/// same server don't all pay for a doomed creation request first. Not persisted — a fresh app
/// launch (or a server later enabling tus) gets a clean retry.
private actor TusSupportCache {
    static let shared = TusSupportCache()
    private var unsupportedServers: Set<String> = []

    func isKnownUnsupported(_ server: String) -> Bool {
        unsupportedServers.contains(server)
    }

    func markUnsupported(_ server: String) {
        unsupportedServers.insert(server)
    }
}

extension DFAPI {
    private static let tusResumableVersion = "1.0.0"
    private static let tusMaxRetries = 5
    private static let tusCompletionPollAttempts = 10
    private static let tusCompletionPollInterval: Duration = .seconds(1.5)

    /// Uploads a file via tus when the server supports it, transparently falling back to the
    /// legacy multipart `/api/upload/` endpoint otherwise. Drop-in replacement for `uploadFile`
    /// — same signature, same semantics for callers (nil on failure).
    public func uploadFileResumable(
        url fileURL: URL,
        fileName: String? = nil,
        albums: String = "",
        privateUpload: Bool = false,
        stripExif: Bool = false,
        stripGps: Bool = false,
        taskDelegate: URLSessionTaskDelegate? = nil
    ) async -> DFUploadResponse? {
        let filename = fileName ?? (fileURL.absoluteString as NSString).lastPathComponent

        if TusUploadSettings.isEnabled, await !TusSupportCache.shared.isKnownUnsupported(url.absoluteString) {
            do {
                return try await uploadFileTus(
                    url: fileURL,
                    fileName: filename,
                    albums: albums,
                    privateUpload: privateUpload,
                    stripExif: stripExif,
                    stripGps: stripGps,
                    taskDelegate: taskDelegate
                )
            } catch TusUploadError.notSupported {
                await TusSupportCache.shared.markUnsupported(url.absoluteString)
            } catch {
                print("DFAPI: tus upload failed (\(error)); falling back to legacy upload")
            }
        }

        // Stream rather than buffer the whole file for the fallback: the share extension
        // that drove the tus requirement in the first place runs under a tight OS memory
        // cap, so a large file that outgrew tus mid-transfer must not be re-read into memory.
        guard let streamedTask = await uploadFileStreamed(
            url: fileURL,
            fileName: filename,
            albums: albums,
            privateUpload: privateUpload,
            stripExif: stripExif,
            stripGps: stripGps,
            taskDelegate: taskDelegate ?? NoopTaskDelegate()
        ) else { return nil }
        return await streamedTask.waitForComplete()
    }

    private func tusEndpointURL() -> URL {
        url.appendingPathComponent("tus/")
    }

    private func tusMetadataValue(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func tusMetadata(fileName: String, albums: String, privateUpload: Bool, stripExif: Bool, stripGps: Bool) -> String {
        // Mirrors the option channels of the legacy endpoint (see parse_headers server-side) so
        // behavior is identical across both upload paths. `authorization` is read by the
        // server's pre-create hook to resolve the user and is stripped before metadata persists.
        var pairs = [
            "filename \(tusMetadataValue(fileName))",
            "name \(tusMetadataValue(fileName))",
            "authorization \(tusMetadataValue(token))",
        ]
        if !albums.isEmpty { pairs.append("albums \(tusMetadataValue(albums))") }
        if privateUpload { pairs.append("private \(tusMetadataValue("true"))") }
        if stripExif { pairs.append("strip-exif \(tusMetadataValue("true"))") }
        if stripGps { pairs.append("strip-gps \(tusMetadataValue("true"))") }
        return pairs.joined(separator: ",")
    }

    private func uploadFileTus(
        url fileURL: URL,
        fileName: String,
        albums: String,
        privateUpload: Bool,
        stripExif: Bool,
        stripGps: Bool,
        taskDelegate: URLSessionTaskDelegate?
    ) async throws -> DFUploadResponse {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let metadata = tusMetadata(fileName: fileName, albums: albums, privateUpload: privateUpload, stripExif: stripExif, stripGps: stripGps)

        let uploadURL = try await tusCreateUpload(size: size, metadata: metadata)

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        try await tusPatchChunks(uploadURL: uploadURL, fileHandle: fileHandle, size: size, taskDelegate: taskDelegate)

        if let response = await tusAwaitProcessedFile(name: fileName, size: size) {
            return response
        }
        // Bytes are fully committed server-side; import just hasn't surfaced in a file list
        // query yet. Report success rather than erroring out a completed upload — the file
        // will appear once processing catches up, same as any other slow post-processing.
        return DFUploadResponse(url: "", raw: "", r: "", name: fileName, size: Int(size))
    }

    private func tusCreateUpload(size: Int64, metadata: String) async throws -> URL {
        var request = URLRequest(url: tusEndpointURL())
        request.httpMethod = "POST"
        request.setValue(DFAPI.tusResumableVersion, forHTTPHeaderField: "Tus-Resumable")
        request.setValue("\(size)", forHTTPHeaderField: "Upload-Length")
        request.setValue(metadata, forHTTPHeaderField: "Upload-Metadata")
        request.setValue(DFAPI.customUserAgent, forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TusUploadError.notSupported
        }
        guard let http = response as? HTTPURLResponse else { throw TusUploadError.notSupported }

        if http.statusCode == 201,
           let location = http.value(forHTTPHeaderField: "Location"),
           let created = URL(string: location, relativeTo: tusEndpointURL())?.absoluteURL {
            return created
        }

        // A real server-side rejection (bad auth, over quota/size) carries our JSON error
        // shape; anything else (404 route missing on a pre-tus server, 500 from a
        // disabled-tus hook failure) means tus isn't usable right now.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["message"] as? String, !message.isEmpty {
            throw TusUploadError.rejected(status: http.statusCode, message: message)
        }
        throw TusUploadError.notSupported
    }

    private func tusCommittedOffset(uploadURL: URL) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        request.setValue(DFAPI.tusResumableVersion, forHTTPHeaderField: "Tus-Resumable")
        let session = URLSession(configuration: .ephemeral)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let offsetHeader = http.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = Int64(offsetHeader) else {
            throw TusUploadError.interrupted
        }
        return offset
    }

    private func tusPatchChunks(uploadURL: URL, fileHandle: FileHandle, size: Int64, taskDelegate: URLSessionTaskDelegate?) async throws {
        var offset: Int64 = 0
        var attempt = 0
        let session = URLSession(configuration: .ephemeral)

        while offset < size {
            try fileHandle.seek(toOffset: UInt64(offset))
            let chunkSize = Int(min(Int64(TusUploadSettings.chunkSizeBytes), size - offset))
            guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                throw TusUploadError.interrupted
            }

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PATCH"
            request.setValue(DFAPI.tusResumableVersion, forHTTPHeaderField: "Tus-Resumable")
            request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")

            do {
                // Reports progress against the whole file (not just this chunk) by translating
                // each chunk's own byte counts through the offset already committed.
                let forwarder = TusChunkProgressForwarder(originalDelegate: taskDelegate, completedBytes: offset, totalSize: size)
                let (_, response) = try await session.upload(for: request, from: chunk, delegate: forwarder)
                guard let http = response as? HTTPURLResponse, http.statusCode == 204,
                      let offsetHeader = http.value(forHTTPHeaderField: "Upload-Offset"),
                      let newOffset = Int64(offsetHeader) else {
                    throw TusUploadError.interrupted
                }
                offset = newOffset
                attempt = 0
            } catch {
                attempt += 1
                guard attempt <= DFAPI.tusMaxRetries else { throw TusUploadError.interrupted }
                // The failed PATCH may have partially landed server-side — resync to the
                // actually-committed offset instead of assuming the whole chunk was lost.
                offset = (try? await tusCommittedOffset(uploadURL: uploadURL)) ?? offset
                try? await Task.sleep(for: .seconds(Double(attempt) * 1.5))
            }
        }
    }

    private func tusAwaitProcessedFile(name: String, size: Int64) async -> DFUploadResponse? {
        for _ in 0..<DFAPI.tusCompletionPollAttempts {
            try? await Task.sleep(for: DFAPI.tusCompletionPollInterval)
            if let filesResponse = try? await getFiles(page: 1, search: name),
               let match = filesResponse.files.first(where: { $0.name == name && $0.size == Int(size) }) {
                return DFUploadResponse(url: match.url, raw: match.raw, r: match.url, name: match.name, size: match.size)
            }
        }
        return nil
    }
}

/// `uploadFileStreamed` requires a delegate; this stands in when `uploadFileResumable` was
/// called without one (progress reporting is simply skipped in that case).
private final class NoopTaskDelegate: NSObject, URLSessionTaskDelegate {}

/// Forwards a chunk PATCH's own `didSendBodyData` callback to the caller-supplied delegate
/// with byte counts translated into whole-file terms, so progress bars driven by `UploadProgressDelegate`
/// (designed for a single request) see one smooth 0...1 sweep across every chunk instead of
/// restarting at each PATCH.
private class TusChunkProgressForwarder: NSObject, URLSessionTaskDelegate {
    let originalDelegate: URLSessionTaskDelegate?
    let completedBytes: Int64
    let totalSize: Int64

    init(originalDelegate: URLSessionTaskDelegate?, completedBytes: Int64, totalSize: Int64) {
        self.originalDelegate = originalDelegate
        self.completedBytes = completedBytes
        self.totalSize = totalSize
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        originalDelegate?.urlSession?(
            session,
            task: task,
            didSendBodyData: bytesSent,
            totalBytesSent: completedBytes + totalBytesSent,
            totalBytesExpectedToSend: totalSize
        )
    }
}
