//
//  FileMapView.swift
//  Django Files
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Internal data models

private struct GeoFile: Identifiable {
    let file: DFFile
    let coordinate: CLLocationCoordinate2D
    var id: Int { file.id }
}

private struct MapCluster: Identifiable {
    let id: String                      // stable grid-cell key — no UUID churn
    let coordinate: CLLocationCoordinate2D
    let files: [GeoFile]
    var isCluster: Bool { files.count > 1 }

    /// First image file in the cluster, or the first file of any type.
    var representative: GeoFile? {
        files.first(where: { $0.file.mime.hasPrefix("image/") }) ?? files.first
    }
}

// MARK: - FileMapView

struct FileMapView: View {
    let server: Binding<DjangoFilesSession?>

    @Environment(\.dismiss) private var dismiss

    @State private var geoFiles:  [DFFile]     = []
    @State private var clusters:  [MapCluster] = []
    @State private var mapSpan    = MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading      = false
    @State private var showingPreview = false
    @State private var showFileInfo   = false
    @State private var previewIndex   = 0

    // MARK: Helpers

    private var serverURL: URL? {
        server.wrappedValue.flatMap { URL(string: $0.url) }
    }

    private func thumbURL(for file: DFFile) -> URL? {
        guard let base = serverURL else { return nil }
        var c = URLComponents(
            url: base.appendingPathComponent("/raw/\(file.name)"),
            resolvingAgainstBaseURL: true
        )
        c?.queryItems = [URLQueryItem(name: "thumb", value: "true")]
        return c?.url
    }

    // MARK: Clustering

    /// Rebuilds `clusters` from the current `geoFiles` and `mapSpan`.
    /// Uses stable string IDs so SwiftUI diffs existing annotation views
    /// rather than destroying and recreating them on every render.
    private func updateClusters() {
        let cellSize = max(mapSpan.latitudeDelta / 8.0,
                          mapSpan.longitudeDelta / 8.0,
                          0.0005)

        var cells: [String: [GeoFile]] = [:]
        for file in geoFiles {
            guard let coord = file.gpsCoordinate else { continue }
            let geo = GeoFile(file: file, coordinate: coord)
            let key = "\(Int(floor(coord.latitude  / cellSize)))_" +
                      "\(Int(floor(coord.longitude / cellSize)))"
            cells[key, default: []].append(geo)
        }

        clusters = cells.map { key, group in
            let lat = group.reduce(0.0) { $0 + $1.coordinate.latitude  } / Double(group.count)
            let lon = group.reduce(0.0) { $0 + $1.coordinate.longitude } / Double(group.count)
            return MapCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                files: group
            )
        }
    }

    private func zoomToCluster(_ cluster: MapCluster) {
        let lats = cluster.files.map { $0.coordinate.latitude }
        let lons = cluster.files.map { $0.coordinate.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let span = MKCoordinateSpan(
            latitudeDelta:  max((maxLat - minLat) * 2.5, 0.002),
            longitudeDelta: max((maxLon - minLon) * 2.5, 0.002)
        )
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // MARK: Map annotation content (separate @ViewBuilder avoids type-checker overload)

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

    // Extracted so Map{} body stays trivially simple for the Swift type-checker
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
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition, content: mapContent)
                    .mapStyle(.standard(elevation: .realistic))
                    .onMapCameraChange { ctx in
                        mapSpan = ctx.region.span
                        updateClusters()
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .fullScreenCover(isPresented: $showingPreview, content: previewContent)

                if isLoading && geoFiles.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading GPS files…").font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                if !isLoading && geoFiles.isEmpty {
                    ContentUnavailableView(
                        "No GPS Files",
                        systemImage: "location.slash.fill",
                        description: Text("Upload photos with location data to see them here.")
                    )
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !geoFiles.isEmpty {
                        Text("\(geoFiles.count) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: loadGPSFiles)
        .onChange(of: server.wrappedValue?.url) { _, _ in
            geoFiles = []
            clusters = []
            loadGPSFiles()
        }
    }

    // MARK: Preview content

    @ViewBuilder
    private func previewContent() -> some View {
        if !geoFiles.isEmpty, previewIndex < geoFiles.count {
            FilePreviewView(
                file: Binding(
                    get: { geoFiles[previewIndex] },
                    set: { geoFiles[previewIndex] = $0 }
                ),
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

    // MARK: Data loading

    private func loadGPSFiles() {
        guard let serverInstance = server.wrappedValue,
              let url = URL(string: serverInstance.url) else { return }
        isLoading = true
        geoFiles  = []
        clusters  = []

        Task {
            let api = DFAPI(url: url, token: serverInstance.token)
            _ = await api.getFilesWithGPS(selectedServer: serverInstance) { pageGeo in
                Task { @MainActor in
                    geoFiles.append(contentsOf: pageGeo)
                    updateClusters()
                    if geoFiles.count == pageGeo.count {
                        // First page — auto-fit camera to show these pins
                        cameraPosition = .automatic
                    }
                }
            }
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Cluster pin (thumbnail + count badge)

struct MapClusterPin: View {
    let representativeThumbURL: URL?
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail of the representative file
                Group {
                    if let url = representativeThumbURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color(.systemGray5)
                                .overlay {
                                    Image(systemName: "photo.stack.fill")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    } else {
                        Color(.systemGray5)
                            .overlay {
                                Image(systemName: "photo.stack.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white, lineWidth: 2)
                )

                // Count badge
                Text(count < 100 ? "\(count)" : "99+")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: 8, y: -8)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Individual pin (with embedded popover callout)

struct FileMapPin: View {
    let file: DFFile
    let thumbnailURL: URL?
    let onViewFile: () -> Void

    @State private var showingCallout = false

    private var showThumb: Bool { file.mime.hasPrefix("image/") && thumbnailURL != nil }

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
                            Image(systemName: icon())
                                .font(.system(size: 18))
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

// MARK: - Callout popover

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
                        Color(.systemGray5)
                            .overlay {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let area = file.gpsArea {
                        Label(area, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let alt = file.gpsAltitude {
                        Label(String(format: "%.0f m", alt), systemImage: "mountain.2.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(file.formattedDate())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
