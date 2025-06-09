//
//  FileRow.swift
//  Django Files
//
//  Created by Ralph Luaces on 6/8/25.
//

import SwiftUI

struct CustomLabel: LabelStyle {
    var spacing: Double = 0.0
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

struct FileRowView: View {
    @Binding var file: DFFile
    var isPrivate: Bool { file.private }
    var hasPassword: Bool { file.password != "" }
    var hasExpiration: Bool { file.expr != "" }
    let serverURL: URL
    
    private func getIcon() -> String {
        if file.mime.hasPrefix("image/") {
            return "photo.artframe"
        } else if file.mime.hasPrefix("video/") {
            return "video.fill"
        } else {
            return "doc.fill"
        }
    }
    
    private var thumbnailURL: URL {
        var components = URLComponents(url: serverURL.appendingPathComponent("/raw/\(file.name)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return components?.url ?? serverURL
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(spacing: 0) {
                if file.mime.hasPrefix("image/") {
                    CachedAsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 64, height: 64)
                    .clipped()
                    .cornerRadius(8)
                } else {
                    Image(systemName: getIcon())
                        .font(.system(size: 50))
                        .frame(width: 64, height: 64)
                        .foregroundColor(Color.primary)
                        .clipped()
                }
            }
            .listRowSeparator(.visible)

            
            VStack(alignment: .leading, spacing: 5) {
                
                HStack(spacing: 5) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.blue)
                }
                
                
                HStack(spacing: 6) {
                    Text(file.mime)
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .lineLimit(1)
                    
                    Label("", systemImage: "lock")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(isPrivate ? 1 : 0)
                    
                    Label("", systemImage: "key")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(hasPassword ? 1 : 0)
                    
                    Label("", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .opacity(hasExpiration ? 1 : 0)
                }
                
                HStack(spacing: 5) {

                    
                    Label(file.userUsername, systemImage: "person")
                        .font(.caption)
                        .labelStyle(CustomLabel(spacing: 3))
                        .lineLimit(1)
                    
                    
                    Text(file.formattedDate())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                }

            }
        }
    }
}
