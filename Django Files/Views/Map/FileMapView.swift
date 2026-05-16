//
//  FileMapView.swift
//  Django Files
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Private models

private struct PinSummary: Sendable {
    let id: Int
    let lat: Double
    let lon: Double
}

private struct GeoFile: Identifiable, @unchecked Sendable {
    let file: DFFile
    let coordinate: CLLocationCoordinate2D
    var id: Int { file.id }
}

private struct MapCluster: Identifiable, @unchecked Sendable {
    let id: String                  // stable grid-cell key — no UUID churn
    let coordinate: CLLocationCoordinate2D
    let files: [GeoFile]
    var isCluster: Bool { files.count > 1 }
    var representative: GeoFile? {
        files.first(where: { $0.file.mime.hasPrefix("image/") }) ?? files.first
    }
}

// MARK: - FileMapView

struct FileMapView: View {
    let server: Binding<DjangoFilesSession?>

    @Environment(\.dismiss) private var dismiss

    // geoFiles drives the preview sheet; coordCache is the fast-lookup for clustering.
    @State private var geoFiles:       [DFFile]          = []
    @State private var coordCache:     [Int: PinSummary] = [:]
    @State private var clusters:       [MapCluster]       = []
    @State private var mapSpan         = MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
    @State private var cameraPosition: MapCameraPosition  = .automatic
    @State private var isLoading                          = false
    @State private var showingPreview                     = false
    @State private var showFileInfo                       = false
    @State private var previewIndex                       = 0
    @State private var loadTask:    Task<Void, Never>?    = nil
    @State private var clusterTask: Task<Void, Never>?    = nil


    // MARK: Helpers

    private var serverKey: String? {
        server.wrappedValue.flatMap { URL(string: $0.url) }?.absoluteString
    }

    private var serverURL: URL? {
        server.wrappedValue.flatMap { URL(string: $0.url) }
    }

    private func thumbURL(for file: DFFile) -> URL? {
        guard let base = serverURL else { return nil }
        var c = URLComponents(url: base.appendingPathComponent("/raw/\(file.name)"),
                              resolvingAgainstBaseURL: true)
        c?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return c?.url
    }

    // MARK: Clustering

    private func updateClusters() {
        let pins    = Array(coordCache.values)
        let ids     = geoFiles.map { $0.id }
        let files   = geoFiles
        let spanLat = mapSpan.latitudeDelta
        let spanLon = mapSpan.longitudeDelta

        clusterTask?.cancel()
        clusterTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }

            var pinByID:  [Int: PinSummary] = [:]
            var idToFile: [Int: DFFile]     = [:]
            for p in pins  { pinByID[p.id]  = p }
            for f in files { idToFile[f.id] = f }

            let maxAnnotations = 50
            var cellSize = max(spanLat / 8.0, spanLon / 8.0, 0.001)
            var cells: [String: [Int]] = [:]
            repeat {
                cells.removeAll(keepingCapacity: true)
                for id in ids {
                    guard let p = pinByID[id] else { continue }
                    let key = "\(Int(floor(p.lat / cellSize)))_\(Int(floor(p.lon / cellSize)))"
                    cells[key, default: []].append(id)
                }
                if cells.count <= maxAnnotations { break }
                cellSize *= 2.0
            } while cellSize < 360.0
            guard !Task.isCancelled else { return }

            let newClusters: [MapCluster] = cells.compactMap { key, memberIDs in
                var sumLat = 0.0, sumLon = 0.0
                let geos: [GeoFile] = memberIDs.compactMap { id in
                    guard let file = idToFile[id], let p = pinByID[id] else { return nil }
                    sumLat += p.lat; sumLon += p.lon
                    return GeoFile(file: file,
                                   coordinate: CLLocationCoordinate2D(latitude: p.lat,
                                                                      longitude: p.lon))
                }
                guard !geos.isEmpty else { return nil }
                let n = Double(geos.count)
                return MapCluster(id: key,
                                  coordinate: CLLocationCoordinate2D(latitude:  sumLat / n,
                                                                     longitude: sumLon / n),
                                  files: geos)
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                // Only update when clusters actually differ — prevents an infinite
                // cycle where MapKit sees a new cluster array, adjusts .automatic
                // camera, fires onMapCameraChange, calls updateClusters, ad infinitum.
                guard self.clusters.count != newClusters.count
                        || zip(self.clusters, newClusters).contains(where: { $0.id != $1.id })
                else { return }
                self.clusters = newClusters
            }
        }
    }

    private func zoomToCluster(_ cluster: MapCluster) {
        let lats = cluster.files.map { $0.coordinate.latitude }
        let lons = cluster.files.map { $0.coordinate.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let span = MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 2.5, 0.002),
            longitudeDelta: max((maxLon - minLon) * 2.5, 0.002))
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude:  (minLat + maxLat) / 2,
                                              longitude: (minLon + maxLon) / 2),
                span: span))
        }
    }

    // MARK: Map content

    @ViewBuilder
    private func pinView(for cluster: MapCluster) -> some View {
        if cluster.isCluster {
            MapClusterPin(
                representativeThumbURL: cluster.representative.flatMap { thumbURL(for: $0.file) },
                count: cluster.files.count,
                onTap: { zoomToCluster(cluster) }
            )
        } else if let geo = cluster.files.first {
            FileMapPin(
                file: geo.file,
                thumbnailURL: thumbURL(for: geo.file),
                onViewFile: {
                    if let idx = geoFiles.firstIndex(of: geo.file) {
                        previewIndex = idx
                        showingPreview = true
                    }
                }
            )
        }
    }

    @MapContentBuilder
    private func mapContent() -> some MapContent {
        ForEach(clusters) { cluster in
            Annotation("", coordinate: cluster.coordinate, anchor: .bottom) {
                pinView(for: cluster)
            }
        }
    }

    // MARK: Body

    var body: some View {
        Map(position: $cameraPosition, content: mapContent)
            .mapStyle(.standard)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    if !geoFiles.isEmpty {
                        HStack(spacing: 6) {
                            Text("\(geoFiles.count) files")
                            if isLoading {
                                ProgressView().scaleEffect(0.7)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .overlay {
                if isLoading && geoFiles.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                } else if !isLoading && geoFiles.isEmpty {
                    ContentUnavailableView(
                        "No GPS Files",
                        systemImage: "location.slash.fill",
                        description: Text("Upload photos with location data to see them here.")
                    )
                }
            }
            .fullScreenCover(isPresented: $showingPreview, content: previewContent)
            .onAppear(perform: loadGPSFiles)
            .onDisappear {
                loadTask?.cancel()
                clusterTask?.cancel()
            }
            .onChange(of: server.wrappedValue?.url) { _, _ in
                loadGPSFiles()
            }
    }

    // MARK: Preview

    @ViewBuilder
    private func previewContent() -> some View {
        if !geoFiles.isEmpty, previewIndex < geoFiles.count {
            FilePreviewView(
                file: Binding(get: { geoFiles[previewIndex] },
                              set: { geoFiles[previewIndex] = $0 }),
                server: server,
                showingPreview: $showingPreview,
                showFileInfo: $showFileInfo,
                fileListDelegate: nil,
                allFiles: $geoFiles,
                currentIndex: previewIndex,
                onNavigate: { idx in
                    if idx >= 0, idx < geoFiles.count { previewIndex = idx }
                }
            )
        }
    }

    // MARK: Loading
    //
    // Strategy:
    //  1. Show cached entries immediately (no flash on re-open).
    //  2. Fetch page 1; if ALL file IDs on the page are already in the seen-set,
    //     we're up to date and stop early. Otherwise add new geo files and continue.
    private func loadGPSFiles() {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }
        let key   = url.absoluteString
        let token = serverInstance.token

        loadTask?.cancel()
        clusterTask?.cancel()

        loadTask = Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            let store  = MapGeoCacheStore.shared
            let cached = store.entries(for: key)
            if !cached.isEmpty {
                applyEntries(cached)
                updateClusters()
            }

            let api  = DFAPI(url: url, token: token)
            var page = 1

            while !Task.isCancelled {
                guard let response = await api.getFiles(page: page) else { break }
                guard !Task.isCancelled else { break }

                let pageIDs   = Set(response.files.map { $0.id })
                let fullyKnown = store.isPageFullyKnown(pageIDs, for: key)

                let newEntries: [MapGeoCacheStore.Entry] = response.files.compactMap { file in
                    guard let coord = file.gpsCoordinate else { return nil }
                    return MapGeoCacheStore.Entry(file: file,
                                                  lat: coord.latitude,
                                                  lon: coord.longitude)
                }

                guard !Task.isCancelled else { break }

                store.mark(seen: pageIDs, entries: newEntries, for: key)

                if !newEntries.isEmpty {
                    applyEntries(newEntries)
                }

                if fullyKnown { break }
                guard response.next != nil else { break }
                page += 1
            }

            guard !Task.isCancelled else { return }
            updateClusters()
        }
    }

    /// Merge a batch of cache entries into the live state, avoiding duplicates.
    private func applyEntries(_ entries: [MapGeoCacheStore.Entry]) {
        for e in entries {
            coordCache[e.file.id] = PinSummary(id: e.file.id, lat: e.lat, lon: e.lon)
        }
        let newIDs   = Set(entries.map { $0.file.id })
        let newFiles = entries.map { $0.file }
        geoFiles.removeAll { newIDs.contains($0.id) }
        geoFiles.append(contentsOf: newFiles)
    }
}

// MARK: - Cluster pin

struct MapClusterPin: View {
    let representativeThumbURL: URL?
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = representativeThumbURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5).overlay {
                                Image(systemName: "photo.stack.fill").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Color(.systemGray5).overlay {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 20)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 2))

                Text(count < 100 ? "\(count)" : "99+")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: 8, y: -8)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual pin

struct FileMapPin: View {
    let file: DFFile
    let thumbnailURL: URL?
    let onViewFile: () -> Void

    @State private var showingCallout = false

    private var showThumb: Bool {
        (file.mime.hasPrefix("image/") || file.mime.hasPrefix("video/")) && thumbnailURL != nil
    }

    private func icon() -> String {
        if file.mime.hasPrefix("video/") { return "video.fill" }
        if file.mime.hasPrefix("audio/") { return "waveform" }
        return "doc.fill"
    }

    var body: some View {
        Button { showingCallout = true } label: {
            ZStack {
                if showThumb, let url = thumbnailURL {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.systemGray5)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: icon()).font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(showingCallout ? Color.accentColor : .white,
                                  lineWidth: showingCallout ? 3 : 2)
            )
            .shadow(color: .black.opacity(showingCallout ? 0.5 : 0.25),
                    radius: showingCallout ? 6 : 3, y: 2)
            .scaleEffect(showingCallout ? 1.1 : 1.0)
            .animation(.spring(response: 0.2), value: showingCallout)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingCallout, arrowEdge: .bottom) {
            FileMapCallout(file: file, thumbnailURL: thumbnailURL) {
                showingCallout = false
                onViewFile()
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Callout

struct FileMapCallout: View {
    let file: DFFile
    let thumbnailURL: URL?
    let onViewFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if file.mime.hasPrefix("image/"), let url = thumbnailURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5)
                        }
                    } else {
                        Color(.systemGray5).overlay {
                            Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let area = file.gpsArea {
                        Label(area, systemImage: "location.fill")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let alt = file.gpsAltitude {
                        Label(String(format: "%.0f m", alt), systemImage: "mountain.2.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(file.formattedDate()).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(14)

            Divider()

            Button(action: onViewFile) {
                Label("View File", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(10)
        }
        .frame(width: 280)
    }
}
