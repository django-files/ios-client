//
//  Django_FilesTests.swift
//  Django FilesTests
//

import Foundation
import Testing
@testable import Django_Files

struct Django_FilesTests {

    // MARK: - Helpers

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func sampleFileJSON(
        id: Int = 1,
        name: String = "test.jpg",
        mime: String = "image/jpeg",
        size: Int = 1024,
        isPrivate: Bool = false,
        albums: [Int] = []
    ) -> Data {
        let albumList = albums.map { String($0) }.joined(separator: ",")
        return """
        {
          "id": \(id), "user": 1, "size": \(size), "mime": "\(mime)",
          "name": "\(name)", "user_name": "Test User", "user_username": "testuser",
          "info": "", "expr": "", "view": 0, "maxv": 0, "password": "",
          "private": \(isPrivate), "avatar": false,
          "url": "http://localhost/i/x/", "thumb": "http://localhost/t/x/",
          "raw": "http://localhost/r/x/\(name)",
          "date": "2025-06-01T12:00:00.000Z",
          "albums": [\(albumList)], "exif": null, "meta": null
        }
        """.data(using: .utf8)!
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - DFFile decoding

    @Test func testDFFileDecoding() throws {
        let data = sampleFileJSON(id: 42, name: "photo.png", mime: "image/png", size: 4096, albums: [3, 5])
        let file = try makeDecoder().decode(DFFile.self, from: data)
        #expect(file.id == 42)
        #expect(file.name == "photo.png")
        #expect(file.mime == "image/png")
        #expect(file.size == 4096)
        #expect(file.userName == "Test User")
        #expect(file.userUsername == "testuser")
        #expect(file.private == false)
        #expect(file.albums == [3, 5])
    }

    @Test func testPrivateFileDecoding() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(isPrivate: true))
        #expect(file.private == true)
    }

    // MARK: - DFFilesResponse decoding

    @Test func testDFFilesResponseDecoding() throws {
        let f1 = String(data: sampleFileJSON(id: 1, name: "a.txt", mime: "text/plain", size: 100), encoding: .utf8)!
        let f2 = String(data: sampleFileJSON(id: 2, name: "b.jpg", mime: "image/jpeg", size: 200), encoding: .utf8)!
        let json = """
        {"files": [\(f1), \(f2)], "next": 2, "count": 10}
        """.data(using: .utf8)!

        let response = try makeDecoder().decode(DFFilesResponse.self, from: json)
        #expect(response.files.count == 2)
        #expect(response.files[0].name == "a.txt")
        #expect(response.files[1].name == "b.jpg")
        #expect(response.next == 2)
        #expect(response.count == 10)
    }

    @Test func testDFFilesResponseEmptyPage() throws {
        let json = #"{"files":[],"next":null,"count":0}"#.data(using: .utf8)!
        let response = try makeDecoder().decode(DFFilesResponse.self, from: json)
        #expect(response.files.isEmpty)
        #expect(response.next == nil)
        #expect(response.count == 0)
    }

    // MARK: - formatSize

    @Test func testFormatSizeBytes() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 512))
        #expect(file.formatSize() == "512 B")
    }

    @Test func testFormatSizeZeroBytes() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 0))
        #expect(file.formatSize() == "0 B")
    }

    @Test func testFormatSizeKilobytes() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 1536))
        #expect(file.formatSize() == "1.5 KB")
    }

    @Test func testFormatSizeMegabytes() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 2 * 1024 * 1024))
        #expect(file.formatSize() == "2.0 MB")
    }

    @Test func testFormatSizeGigabytes() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 2 * 1024 * 1024 * 1024))
        #expect(file.formatSize() == "2.0 GB")
    }

    // MARK: - formattedDate

    @Test func testFormattedDateParsesISO8601() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON())
        #expect(file.dateObject != nil)
        // Successfully parsed — returns a locale string, not the raw ISO string
        #expect(file.formattedDate() != file.date)
    }

    // MARK: - DFUploadResponse decoding

    @Test func testDFUploadResponseDecoding() throws {
        let json = """
        {
          "files": ["http://localhost/i/abc/", "http://localhost/i/def/"],
          "url": "http://localhost/i/abc/",
          "raw": "http://localhost/r/abc/photo.jpg",
          "r": "abc",
          "name": "photo.jpg",
          "size": 4096
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(DFUploadResponse.self, from: json)
        #expect(response.files.count == 2)
        #expect(response.files[0] == "http://localhost/i/abc/")
        #expect(response.files[1] == "http://localhost/i/def/")
        #expect(response.name == "photo.jpg")
        #expect(response.size == 4096)
    }

    @Test func testDFUploadResponseEmptyFiles() throws {
        let json = #"{"files":[],"url":"http://localhost/i/x/","raw":"http://localhost/r/x/f.jpg","r":"x","name":"f.jpg","size":1}"#.data(using: .utf8)!
        let response = try makeDecoder().decode(DFUploadResponse.self, from: json)
        #expect(response.files.isEmpty)
    }

    // MARK: - DFAlbum decoding

    @Test func testDFAlbumDecoding() throws {
        let json = """
        {
          "id": 7, "user": 1, "name": "Vacation 2025",
          "password": null, "private": true,
          "info": "Summer trip", "view": 5, "maxv": 100,
          "expr": "", "date": "2025-06-01T12:00:00.000Z",
          "url": "http://localhost/a/abc/"
        }
        """.data(using: .utf8)!
        let album = try makeDecoder().decode(DFAlbum.self, from: json)
        #expect(album.id == 7)
        #expect(album.name == "Vacation 2025")
        #expect(album.private == true)
        #expect(album.info == "Summer trip")
        #expect(album.maxv == 100)
    }

    @Test func testAlbumsResponseDecoding() throws {
        let json = """
        {
          "albums": [
            {"id":1,"user":1,"name":"A","password":null,"private":false,
             "info":null,"view":0,"maxv":null,"expr":null,
             "date":"2025-01-01T00:00:00.000Z","url":"http://localhost/a/a/"},
            {"id":2,"user":1,"name":"B","password":null,"private":false,
             "info":null,"view":0,"maxv":null,"expr":null,
             "date":"2025-01-02T00:00:00.000Z","url":"http://localhost/a/b/"}
          ],
          "next": null, "count": 2
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(AlbumsResponse.self, from: json)
        #expect(response.albums.count == 2)
        #expect(response.albums[0].name == "A")
        #expect(response.albums[1].name == "B")
        #expect(response.next == nil)
        #expect(response.count == 2)
    }

    // MARK: - CreateAlbumResponse.albumId

    @Test func testCreateAlbumResponseAlbumId() throws {
        let json = #"{"url":"http://localhost/upload/?album=42"}"#.data(using: .utf8)!
        let response = try makeDecoder().decode(CreateAlbumResponse.self, from: json)
        #expect(response.albumId == 42)
    }

    @Test func testCreateAlbumResponseAlbumIdMissing() throws {
        let json = #"{"url":"http://localhost/upload/"}"#.data(using: .utf8)!
        let response = try makeDecoder().decode(CreateAlbumResponse.self, from: json)
        #expect(response.albumId == nil)
    }

    // MARK: - DFShort decoding

    @Test func testDFShortDecoding() throws {
        let json = """
        {"id":3,"short":"abc","url":"https://example.com","max":10,"views":2,"user":1,"fullUrl":"http://localhost/s/abc/"}
        """.data(using: .utf8)!
        let short = try makeDecoder().decode(DFShort.self, from: json)
        #expect(short.id == 3)
        #expect(short.short == "abc")
        #expect(short.url == "https://example.com")
        #expect(short.max == 10)
        #expect(short.views == 2)
        #expect(short.fullUrl == "http://localhost/s/abc/")
    }

    @Test func testShortsResponseDecoding() throws {
        let json = """
        {"shorts":[
          {"id":1,"short":"x","url":"https://a.com","max":0,"views":1,"user":1,"fullUrl":"http://localhost/s/x/"},
          {"id":2,"short":"y","url":"https://b.com","max":5,"views":0,"user":1,"fullUrl":"http://localhost/s/y/"}
        ], "next": null, "count": 2}
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(ShortsResponse.self, from: json)
        #expect(response.shorts.count == 2)
        #expect(response.shorts[0].short == "x")
        #expect(response.shorts[1].short == "y")
    }

    // MARK: - GPS coordinate

    @Test func testGPSCoordinateNorthEast() throws {
        let json = """
        {
          "id": 1, "user": 1, "size": 1024, "mime": "image/jpeg",
          "name": "geo.jpg", "user_name": "Test User", "user_username": "testuser",
          "info": "", "expr": "", "view": 0, "maxv": 0, "password": "",
          "private": false, "avatar": false,
          "url": "http://localhost/i/x/", "thumb": "http://localhost/t/x/",
          "raw": "http://localhost/r/x/geo.jpg",
          "date": "2025-06-01T12:00:00.000Z",
          "albums": [], "meta": null,
          "exif": {
            "GPSInfo": {
              "1": "N", "2": [40, 44, 55.8],
              "3": "E", "4": [73, 59, 11.0]
            }
          }
        }
        """.data(using: .utf8)!
        let file = try makeDecoder().decode(DFFile.self, from: json)
        let coord = file.gpsCoordinate
        #expect(coord != nil)
        #expect(abs(coord!.latitude - 40.748833) < 0.001)
        #expect(abs(coord!.longitude - 73.986389) < 0.001)
    }

    @Test func testGPSCoordinateSouthHemisphere() throws {
        let json = """
        {
          "id": 1, "user": 1, "size": 1024, "mime": "image/jpeg",
          "name": "geo.jpg", "user_name": "Test User", "user_username": "testuser",
          "info": "", "expr": "", "view": 0, "maxv": 0, "password": "",
          "private": false, "avatar": false,
          "url": "http://localhost/i/x/", "thumb": "http://localhost/t/x/",
          "raw": "http://localhost/r/x/geo.jpg",
          "date": "2025-06-01T12:00:00.000Z",
          "albums": [], "meta": null,
          "exif": {
            "GPSInfo": {
              "1": "S", "2": [33, 52, 0.0],
              "3": "E", "4": [151, 12, 0.0]
            }
          }
        }
        """.data(using: .utf8)!
        let file = try makeDecoder().decode(DFFile.self, from: json)
        let coord = file.gpsCoordinate
        #expect(coord != nil)
        #expect(coord!.latitude < 0)
        #expect(abs(coord!.latitude - (-33.866667)) < 0.001)
        #expect(abs(coord!.longitude - 151.2) < 0.001)
    }

    @Test func testGPSCoordinateNilWhenNoExif() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON())
        #expect(file.gpsCoordinate == nil)
    }

    // MARK: - DFShortRequest encoding

    @Test func testDFShortRequestEncodesHyphenatedKey() throws {
        let request = DFShortRequest(url: "https://example.com", vanity: "abc", maxViews: 5)
        let data = try JSONEncoder().encode(request)
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(dict["url"] as? String == "https://example.com")
        #expect(dict["vanity"] as? String == "abc")
        #expect(dict["max-views"] as? Int == 5)
        #expect(dict["maxViews"] == nil)
    }

    // MARK: - formatSize boundary

    @Test func testFormatSizeJustUnderKilo() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 1023))
        #expect(file.formatSize() == "1023 B")
    }

    @Test func testFormatSizeExactKiloBoundary() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON(size: 1024))
        #expect(file.formatSize() == "1.0 KB")
    }

    // MARK: - DFStatsResponse decoding

    @Test func testDFStatsResponseDecoding() throws {
        let json = """
        [
          {
            "model": "files.stat", "pk": 1,
            "fields": {
              "user": 1,
              "stats": {
                "types": {
                  "image/jpeg": {"size": 2048, "count": 1},
                  "text/plain": {"size": 512, "count": 1}
                },
                "size": 2560, "count": 2, "shorts": 0, "human_size": "2.5 KB"
              },
              "created_at": null, "updated_at": null
            }
          }
        ]
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(DFStatsResponse.self, from: json)
        #expect(response.stats.count == 1)
        let stat = response.stats[0]
        #expect(stat.model == "files.stat")
        #expect(stat.pk == 1)
        #expect(stat.fields.user == 1)
        #expect(stat.fields.stats.count == 2)
        #expect(stat.fields.stats.size == 2560)
        #expect(stat.fields.stats.humanSize == "2.5 KB")
        #expect(stat.fields.stats.types.count == 2)
        let mimes = Set(stat.fields.stats.types.map { $0.name })
        #expect(mimes.contains("image/jpeg"))
        #expect(mimes.contains("text/plain"))
    }

    // MARK: - GPS altitude and area

    private func sampleFileJSONWithExif(exif: String, meta: String = "null") -> Data {
        return """
        {
          "id": 1, "user": 1, "size": 1024, "mime": "image/jpeg",
          "name": "geo.jpg", "user_name": "Test User", "user_username": "testuser",
          "info": "", "expr": "", "view": 0, "maxv": 0, "password": "",
          "private": false, "avatar": false,
          "url": "http://localhost/i/x/", "thumb": "http://localhost/t/x/",
          "raw": "http://localhost/r/x/geo.jpg",
          "date": "2025-06-01T12:00:00.000Z",
          "albums": [], "exif": \(exif), "meta": \(meta)
        }
        """.data(using: .utf8)!
    }

    @Test func testGPSAltitude() throws {
        let exif = #"{"GPSInfo":{"6":85.5}}"#
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSONWithExif(exif: exif))
        #expect(file.gpsAltitude != nil)
        #expect(abs(file.gpsAltitude! - 85.5) < 0.001)
    }

    @Test func testGPSAltitudeNilWhenMissing() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSONWithExif(exif: #"{"GPSInfo":{}}"#))
        #expect(file.gpsAltitude == nil)
    }

    @Test func testGPSArea() throws {
        let meta = #"{"GPSArea":"New York"}"#
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSONWithExif(exif: "null", meta: meta))
        #expect(file.gpsArea == "New York")
    }

    @Test func testGPSAreaNilWhenMissing() throws {
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSON())
        #expect(file.gpsArea == nil)
    }

    @Test func testGPSCoordinateNilForZeroZero() throws {
        let exif = #"{"GPSInfo":{"1":"N","2":[0,0,0.0],"3":"E","4":[0,0,0.0]}}"#
        let file = try makeDecoder().decode(DFFile.self, from: sampleFileJSONWithExif(exif: exif))
        #expect(file.gpsCoordinate == nil)
    }

    // MARK: - API layer (mock network)

    @Test func testGetAuthMethodsWithMock() async {
        let api = DFAPI(url: URL(string: "http://localhost")!, token: "", session: mockSession())
        let result = await api.getAuthMethods()
        #expect(result != nil)
        #expect(result?.siteName == "Test Server")
        #expect(result?.authMethods.count == 1)
        #expect(result?.authMethods.first?.name == "local")
    }

    @Test func testGetFilesPage1WithMock() async {
        let api = DFAPI(url: URL(string: "http://localhost")!, token: "test", session: mockSession())
        let result = await api.getFiles(page: 1)
        #expect(result != nil)
        #expect(result?.files.count == 2)
        #expect(result?.files[0].name == "photo.jpg")
        #expect(result?.files[0].mime == "image/jpeg")
        #expect(result?.files[1].name == "notes.txt")
        #expect(result?.files[1].private == true)
        #expect(result?.next == nil)
        #expect(result?.count == 2)
    }

    @Test func testGetFilesPage2WithMockReturnsEmpty() async {
        let api = DFAPI(url: URL(string: "http://localhost")!, token: "test", session: mockSession())
        let result = await api.getFiles(page: 2)
        #expect(result != nil)
        #expect(result?.files.isEmpty == true)
        #expect(result?.next == nil)
    }
}
