//
//  DFPendingUploadJob.swift
//
//  Add this file to both the UploadAndCopy and "Django Files" targets.
//

import Foundation

struct DFPendingUploadJob: Codable {
    let id: String
    let sessionURL: String
    let sessionToken: String
    /// File names relative to upload-files/<id>/ in the shared app group container.
    /// Empty when isShorten is true.
    let fileNames: [String]
    let albumIDs: [Int]
    /// URL of the first selected album — used as the clipboard link for multi-file uploads.
    let firstAlbumURL: String?
    /// Album name for display in the Live Activity.
    let albumName: String?
    let privateUpload: Bool
    let stripExif: Bool
    let stripGps: Bool
    let isShorten: Bool
    let shortenSourceURL: String?
    let shortText: String
}
