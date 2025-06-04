//
//  Albums.swift
//  Django Files
//
//  Created by Ralph Luaces on 4/29/25.
//

import Foundation

// Album model that matches the JSON payload
struct DFAlbum: Identifiable, Decodable, Hashable {
    let id: Int
    let user: Int?
    let name: String
    let password: String?
    let `private`: Bool
    let info: String?
    let view: Int
    let maxv: Int?
    let expr: String?
    let date: String
    let url: String
    
    // Format date for display
    func formattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        if let date = dateFormatter.date(from: date) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return date
    }
}

// Response structure for album API call
struct AlbumsResponse: Decodable {
    let albums: [DFAlbum]
    let next: Int?
    let count: Int
}

// Request structure for album creation
struct CreateAlbumRequest: Codable {
    let name: String
    let maxv: Int?
    let expr: String?
    let password: String?
    let `private`: Bool?
    let info: String?
}

// Response structure for album creation
struct CreateAlbumResponse: Decodable {
    let url: String
    
    // Extract album ID from the URL
    var albumId: Int? {
        guard let urlComponents = URLComponents(string: url),
              let queryItems = urlComponents.queryItems,
              let albumQuery = queryItems.first(where: { $0.name == "album" }),
              let albumId = Int(albumQuery.value ?? "") else {
            return nil
        }
        return albumId
    }
}

extension DFAPI {
    // Fetch albums with pagination
    func getAlbums(page: Int = 1, selectedServer: DjangoFilesSession? = nil) async -> AlbumsResponse? {
        do {
            let responseBody = try await makeAPIRequest(
                path: getAPIPath(.albums) + "\(page)/",
                parameters: [:],
                method: .get,
                expectedResponse: .ok,
                selectedServer: selectedServer
            )
            let decoder = JSONDecoder()
            return try decoder.decode(AlbumsResponse.self, from: responseBody)
        } catch {
            print("Error fetching albums: \(error)")
            return nil
        }
    }
    
    // Create a new album
    func createAlbum(name: String, maxViews: Int? = nil, expiration: String? = nil, 
                    password: String? = nil, isPrivate: Bool? = nil, description: String? = nil, 
                    selectedServer: DjangoFilesSession? = nil) async -> CreateAlbumResponse? {
        let request = CreateAlbumRequest(
            name: name,
            maxv: maxViews,
            expr: expiration,
            password: password,
            private: isPrivate,
            info: description
        )
        
        do {
            let json = try JSONEncoder().encode(request)
            let responseBody = try await makeAPIRequest(
                body: json,
                path: getAPIPath(.album),
                parameters: [:],
                method: .post,
                expectedResponse: .ok,
                headerFields: [.contentType: "application/json"],
                selectedServer: selectedServer
            )
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(CreateAlbumResponse.self, from: responseBody)
        } catch {
            print("Error creating album: \(error)")
            return nil
        }
    }
    
    // Delete an album by ID
    func deleteAlbum(albumId: Int, selectedServer: DjangoFilesSession? = nil) async -> Bool {
        do {
            let path = "\(getAPIPath(.album))\(albumId)"
            _ = try await makeAPIRequest(
                path: path,
                parameters: [:],
                method: .delete,
                expectedResponse: .noContent,
                selectedServer: selectedServer
            )
            return true
        } catch {
            print("Error deleting album: \(error)")
            return false
        }
    }
}

