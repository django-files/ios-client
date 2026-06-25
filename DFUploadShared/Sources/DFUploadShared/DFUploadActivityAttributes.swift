import ActivityKit
import Foundation

public struct DFUploadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var progress: Double
        public var uploadedCount: Int
        public var totalCount: Int
        public var isComplete: Bool
        public var copiedURL: String?

        public init(
            progress: Double,
            uploadedCount: Int,
            totalCount: Int,
            isComplete: Bool,
            copiedURL: String?
        ) {
            self.progress = progress
            self.uploadedCount = uploadedCount
            self.totalCount = totalCount
            self.isComplete = isComplete
            self.copiedURL = copiedURL
        }
    }

    public var serverHost: String
    public var albumName: String?

    public init(serverHost: String, albumName: String?) {
        self.serverHost = serverHost
        self.albumName = albumName
    }
}
