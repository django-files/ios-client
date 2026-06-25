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
    var inlineMode: Bool = false
    var albumID: Int? = nil
    var selectedMimeTypes: Set<MimeTypeFilter> = []
    var filterUserID: Int? = nil
    var externalFileCount: Binding<Int>? = nil
    var externalIsLoading: Binding<Bool>? = nil

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
    @State private var showingClusterPreview              = false
    @State private var clusterPreviewFiles: [DFFile]      = []
    @State private var clusterPreviewIndex                = 0
    @State private var loadTask:    Task<Void, Never>?    = nil
    @State private var clusterTask: Task<Void, Never>?    = nil
    @State private var didAutoZoom                        = false


    // MARK: Helpers

    private var serverKey: String? {
        guard let base = server.wrappedValue.flatMap({ URL(string: $0.url) })?.absoluteString else {
            return nil
        }
        var key = base
        if let albumID { key += "#album=\(albumID)" }
        // Distinct caches per user-filter selection: superusers can switch
        // between their own files and other users' files, and entries must
        // not bleed between those selections.
        key += "#user=\(filterUserID.map(String.init) ?? "all")"
        return key
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

    private var filteredGeoFiles: [DFFile] {
        guard !selectedMimeTypes.isEmpty else { return geoFiles }
        return geoFiles.filter { file in
            selectedMimeTypes.contains { file.mime.hasPrefix($0.rawValue) }
        }
    }

    // MARK: Clustering

    private func updateClusters() {
        let displayed = filteredGeoFiles
        let displayedIDs = Set(displayed.map { $0.id })
        let pins    = coordCache.values.filter { displayedIDs.contains($0.id) }
        let ids     = displayed.map { $0.id }
        let files   = displayed
        let spanLat = mapSpan.latitudeDelta
        let spanLon = mapSpan.longitudeDelta

        clusterTask?.cancel()
        clusterTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }

            var pinByID:  [Int: PinSummary] = [:]
            var idToFile: [Int: DFFile]     = [:]
            for p in pins  { pinByID[p.id]  = p }
            for f in files { idToFile[f.id] = f }

            // At close zoom levels show more pins so clusters resolve into
            // individual annotations when drilling in.
            let maxAnnotations = (spanLat < 0.1 && spanLon < 0.1) ? 500 : 50
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

    private func autoZoomToGeoFiles() {
        guard !didAutoZoom else { return }
        let pins = Array(coordCache.values)
        guard !pins.isEmpty else { return }

        let lats = pins.map { $0.lat }
        let lons = pins.map { $0.lon }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        didAutoZoom = true
        let span = MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01))
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude:  (minLat + maxLat) / 2,
                                              longitude: (minLon + maxLon) / 2),
                span: span))
        }
    }

    private func zoomToCluster(_ cluster: MapCluster) {
        let lats = cluster.files.map { $0.coordinate.latitude }
        let lons = cluster.files.map { $0.coordinate.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        // All files at essentially the same coordinate — can't
        // resolve via zoom; open a cluster-scoped preview instead.
        if (maxLat - minLat) < 0.001 && (maxLon - minLon) < 0.001 {
            clusterPreviewFiles = cluster.files.map { $0.file }
            clusterPreviewIndex = 0
            showingClusterPreview = true
            return
        }

        let span = MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 1.5, 0.002),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.002))
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude:  (minLat + maxLat) / 2,
                                              longitude: (minLon + maxLon) / 2),
                span: span))
        }
    }

    // MARK: Map content

    private func isSameLocationCluster(_ cluster: MapCluster) -> Bool {
        let lats = cluster.files.map { $0.coordinate.latitude }
        let lons = cluster.files.map { $0.coordinate.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return true }
        return (maxLat - minLat) < 0.001 && (maxLon - minLon) < 0.001
    }

    @ViewBuilder
    private func pinView(for cluster: MapCluster) -> some View {
        if cluster.isCluster {
            let sameLocation = isSameLocationCluster(cluster)
            // Build media pairs keeping thumbnailURLs and mediaFiles index-aligned.
            let mediaPairs = cluster.files
                .filter { $0.file.mime.hasPrefix("image/") || $0.file.mime.hasPrefix("video/") }
                .compactMap { gf -> (DFFile, URL)? in
                    guard let url = thumbURL(for: gf.file) else { return nil }
                    return (gf.file, url)
                }
            let thumbURLs   = mediaPairs.map { $0.1 }
            let mediaFiles  = mediaPairs.map { $0.0 }
            MapClusterPin(
                thumbnailURLs: thumbURLs,
                mediaFiles: mediaFiles,
                files: cluster.files.map { $0.file },
                count: cluster.files.count,
                isSameLocation: sameLocation,
                onZoom: { zoomToCluster(cluster) },
                onViewFiles: {
                    clusterPreviewFiles = cluster.files.map { $0.file }
                    clusterPreviewIndex = 0
                    showingClusterPreview = true
                }
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

    @ViewBuilder
    private var emptyStateOverlay: some View {
        let displayedCount = filteredGeoFiles.count
        if isLoading && displayedCount == 0 {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        } else if !isLoading && displayedCount == 0 {
            if !selectedMimeTypes.isEmpty && !geoFiles.isEmpty {
                ContentUnavailableView(
                    "No Matching Files",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No GPS files match the current filter.")
                )
            } else {
                ContentUnavailableView(
                    "No GPS Files",
                    systemImage: "location.slash.fill",
                    description: Text("Upload photos with location data to see them here.")
                )
            }
        }
    }

    private var mapCoreView: some View {
        Map(position: $cameraPosition, content: mapContent)
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .onEnd) { ctx in
                // Convert .automatic → .region on first camera change so that
                // subsequent self.clusters updates don't trigger camera adjustments
                // (which would fire onMapCameraChange → updateClusters → … ad infinitum).
                if case .automatic = cameraPosition {
                    cameraPosition = .region(ctx.region)
                }
                mapSpan = ctx.region.span
                updateClusters()
            }
            .overlay { emptyStateOverlay }
            .fullScreenCover(isPresented: $showingPreview, content: fullPreview)
            .fullScreenCover(isPresented: $showingClusterPreview, content: clusterPreviewContent)
            .onAppear(perform: loadGPSFiles)
            .onDisappear {
                loadTask?.cancel()
                clusterTask?.cancel()
            }
            .onChange(of: server.wrappedValue?.url) { _, _ in
                loadGPSFiles()
            }
            .onChange(of: filterUserID) { _, _ in
                loadGPSFiles()
            }
            .onChange(of: filteredGeoFiles.count) { _, new in
                externalFileCount?.wrappedValue = new
            }
            .onChange(of: selectedMimeTypes) { _, _ in
                updateClusters()
            }
            .onChange(of: isLoading) { _, new in
                externalIsLoading?.wrappedValue = new
            }
    }

    @ToolbarContentBuilder
    private var statusToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let displayedCount = filteredGeoFiles.count
            if isLoading || displayedCount > 0 {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("\(displayedCount) \(displayedCount == 1 ? "file" : "files")")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.default, value: isLoading)
                .animation(.default, value: displayedCount)
            }
        }
    }

    var body: some View {
        if inlineMode {
            mapCoreView
        } else {
            NavigationStack {
                mapCoreView
                    .ignoresSafeArea(.all, edges: .top)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                            }
                        }
                        statusToolbar
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private func fullPreview() -> some View {
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
              let url = URL(string: serverInstance.url),
              let key = serverKey else { return }
        let token = serverInstance.token
        let album = albumID
        let userFilter = filterUserID

        loadTask?.cancel()
        clusterTask?.cancel()
        didAutoZoom = false
        // Drop entries from any prior server/user selection — applyEntries only
        // upserts, so without this purge, files from the previous cache key
        // would linger after a server switch or user-filter change.
        geoFiles.removeAll()
        coordCache.removeAll()
        clusters.removeAll()

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
                guard let response = try? await api.getFiles(page: page,
                                                             album: album,
                                                             selectedServer: serverInstance,
                                                             filterUserID: userFilter,
                                                             filterMime: nil) else { break }
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
                    updateClusters()
                }

                if fullyKnown { break }
                guard response.next != nil else { break }
                page += 1
            }

            guard !Task.isCancelled else { return }
            store.markFullySynced(key)
            updateClusters()
            autoZoomToGeoFiles()
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

    @ViewBuilder
    private func clusterPreviewContent() -> some View {
        if !clusterPreviewFiles.isEmpty, clusterPreviewIndex < clusterPreviewFiles.count {
            FilePreviewView(
                file: Binding(get: { clusterPreviewFiles[clusterPreviewIndex] },
                              set: { clusterPreviewFiles[clusterPreviewIndex] = $0 }),
                server: server,
                showingPreview: $showingClusterPreview,
                showFileInfo: $showFileInfo,
                fileListDelegate: nil,
                allFiles: $clusterPreviewFiles,
                currentIndex: clusterPreviewIndex,
                onNavigate: { idx in
                    if idx >= 0, idx < clusterPreviewFiles.count { clusterPreviewIndex = idx }
                }
            )
        }
    }
}

// MARK: - Cluster pin

struct MapClusterPin: View {
    let thumbnailURLs: [URL]
    let mediaFiles: [DFFile]
    let files: [DFFile]
    let count: Int
    let isSameLocation: Bool
    let onZoom: () -> Void
    let onViewFiles: () -> Void

    @State private var showingCallout = false

    var body: some View {
        Button(action: {
            if isSameLocation { showingCallout = true }
            else { onZoom() }
        }) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = thumbnailURLs.first {
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
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                    showingCallout ? Color.accentColor : .white,
                    lineWidth: showingCallout ? 3 : 2
                ))

                Text(count < 100 ? "\(count)" : "99+")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: 8, y: -8)
            }
            .shadow(color: .black.opacity(showingCallout ? 0.5 : 0.3),
                    radius: showingCallout ? 6 : 4, y: 2)
            .scaleEffect(showingCallout ? 1.1 : 1.0)
            .animation(.spring(response: 0.2), value: showingCallout)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingCallout, arrowEdge: .bottom) {
            ClusterMapCallout(thumbnailURLs: thumbnailURLs, mediaFiles: mediaFiles, totalCount: count) {
                showingCallout = false
                onViewFiles()
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Cluster callout

struct ClusterMapCallout: View {
    let thumbnailURLs: [URL]
    let mediaFiles: [DFFile]   // index-aligned with thumbnailURLs
    let totalCount: Int
    let onViewFiles: () -> Void

    @State private var currentIndex: Int = 0

    private var displayURLs: [URL] { Array(thumbnailURLs.prefix(8)) }

    private var location: String? { mediaFiles.compactMap { $0.gpsArea }.first }

    private var dateRange: String {
        let dates = mediaFiles.map { $0.formattedDate() }
        guard let first = dates.first else { return "" }
        guard let last = dates.last, last != first else { return first }
        return "\(first) – \(last)"
    }

    private var avgElevation: Double? {
        let alts = mediaFiles.compactMap { $0.gpsAltitude }
        guard !alts.isEmpty else { return nil }
        return alts.reduce(0, +) / Double(alts.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onViewFiles) {
                ZStack {
                    if displayURLs.isEmpty {
                        Color(.systemGray5).overlay {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 32)).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(displayURLs.enumerated()), id: \.offset) { idx, url in
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color(.systemGray5)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipped()
                            .opacity(currentIndex == idx ? 1 : 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()
            }
            .buttonStyle(.plain)
            .task {
                guard displayURLs.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.6)) {
                        currentIndex = (currentIndex + 1) % displayURLs.count
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if let loc = location {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    Text(dateRange)
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if let alt = avgElevation {
                        Label(String(format: "%.0f m", alt), systemImage: "mountain.2.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(totalCount) \(totalCount == 1 ? "file" : "files")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(width: 280)
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
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: icon()).font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
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
            Button(action: onViewFile) {
                Group {
                    if file.mime.hasPrefix("image/") || file.mime.hasPrefix("video/"),
                       let url = thumbnailURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5)
                        }
                    } else {
                        Color(.systemGray5).overlay {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let area = file.gpsArea {
                    Text(area)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Text(file.formattedDate()).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if let alt = file.gpsAltitude {
                        Label(String(format: "%.0f m", alt), systemImage: "mountain.2.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 280)
    }
}
