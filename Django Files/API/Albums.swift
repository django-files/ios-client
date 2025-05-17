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
    let user: Int
    let name: String
    let password: String
    let `private`: Bool
    let info: String
    let view: Int
    let maxv: Int
    let expr: String
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

extension DFAPI {
    // Fetch albums with pagination
    func getAlbums(page: Int = 1) async -> AlbumsResponse? {
        guard var components = URLComponents(string: "\(url)/api/albums/") else {
            return nil
        }
        
        components.queryItems = [URLQueryItem(name: "page", value: "\(page)")]
        
        guard let requestURL = components.url else {
            return nil
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.addValue("Token \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, 
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let albumsResponse = try decoder.decode(AlbumsResponse.self, from: data)
            return albumsResponse
            
        } catch {
            print("Error fetching albums: \(error)")
            return nil
        }
    }
}

