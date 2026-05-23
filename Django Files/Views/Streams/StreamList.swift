//
//  StreamList.swift
//  Django Files
//

import SwiftUI

struct StreamListView: View {
    let server: Binding<DjangoFilesSession?>

    @State private var streams: [DFStream] = []
    @State private var isLoading = false
    @State private var hasMoreResults = true
    @State private var error: String?
    @State private var filterUserID: Int? = nil
    @State private var users: [DFUser] = []
    @State private var liveFilter: LiveFilter = .all

    private var isFilteringUsers: Bool { filterUserID != server.wrappedValue?.userID }
    private var hasActiveFilters: Bool { isFilteringUsers || liveFilter != .all }

    private var filteredStreams: [DFStream] {
        switch liveFilter {
        case .all:     return streams
        case .live:    return streams.filter { $0.isLive }
        case .offline: return streams.filter { !$0.isLive }
        }
    }

    private let streamsPerPage = 50

    var body: some View {
        ZStack {
            if let session = server.wrappedValue, let serverURL = URL(string: session.url) {
                NavigationStack {
                    List {
                        if streams.isEmpty && !isLoading {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    Image(systemName: "video.slash")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.secondary)
                                        .shadow(color: .blue, radius: 20)
                                    Text("No streams found")
                                        .font(.headline)
                                    Text("Start a stream via OBS or another RTMP client.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }

                        ForEach(filteredStreams) { stream in
                            NavigationLink {
                                StreamView(
                                    serverURL: serverURL,
                                    streamName: stream.name,
                                    token: session.token,
                                    initialStream: stream
                                )
                            } label: {
                                StreamRow(stream: stream)
                            }
                            .onAppear {
                                if stream.id == streams.last?.id && hasMoreResults {
                                    loadMoreStreams()
                                }
                            }
                        }

                        if isLoading {
                            HStack {
                                Spacer()
                                LoadingView().frame(width: 80, height: 80)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await refreshStreams() }
                    .overlay {
                        if let error { errorView(message: error) }
                    }
                    .navigationTitle("Streams")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Menu {
                                Picker("Status", selection: $liveFilter) {
                                    Image(systemName: "video").tag(LiveFilter.all)
                                    Image(systemName: "video.fill").tag(LiveFilter.live)
                                    Image(systemName: "video.slash").tag(LiveFilter.offline)
                                }
                                .pickerStyle(.segmented)

                                if server.wrappedValue?.superUser ?? false {
                                    Divider()
                                    Section("Filters") {
                                        Menu {
                                            Picker("", selection: Binding(
                                                get: { filterUserID },
                                                set: { newValue in
                                                    filterUserID = newValue
                                                    Task { await refreshStreams() }
                                                }
                                            )) {
                                                Label("All Users", systemImage: "person.2")
                                                    .tag(Optional<Int>(0))
                                                ForEach(users, id: \.id) { user in
                                                    Label(user.username, systemImage: "person.circle")
                                                        .tag(Optional(user.id))
                                                }
                                            }
                                            .pickerStyle(.inline)
                                        } label: {
                                            Label("Users", systemImage: "person.2")
                                                .symbolVariant(isFilteringUsers ? .fill : .none)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            UploadMenuButton(server: server)
                        }
                    }
                }
            } else {
                Label("No server selected.", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if filterUserID == nil { filterUserID = server.wrappedValue?.userID }
            if streams.isEmpty { loadInitialStreams() }
            if server.wrappedValue?.superUser == true {
                Task {
                    if let session = server.wrappedValue, let url = URL(string: session.url) {
                        let api = DFAPI(url: url, token: session.token)
                        users = await api.getAllUsers(selectedServer: session)
                    }
                }
            }
        }
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Error").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") { loadInitialStreams() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Data Loading

    private func loadInitialStreams() {
        guard streams.isEmpty, !isLoading else { return }
        error = nil
        Task { await fetchStreams() }
    }

    private func refreshStreams() async {
        await MainActor.run { error = nil; streams = []; hasMoreResults = true }
        await fetchStreams()
    }

    private func loadMoreStreams() {
        guard !isLoading, hasMoreResults else { return }
        Task { await fetchStreams() }
    }

    private func fetchStreams() async {
        guard let session = server.wrappedValue,
              let url = URL(string: session.url) else {
            error = "Invalid session URL"; return
        }
        await MainActor.run { isLoading = true }

        let api = DFAPI(url: url, token: session.token)
        let page = (streams.count / streamsPerPage) + 1

        if let response = await api.getStreams(page: page, filterUserID: filterUserID, selectedServer: session) {
            await MainActor.run {
                streams.append(contentsOf: response.streams)
                hasMoreResults = response.next != nil
                error = nil
                isLoading = false
            }
        } else {
            await MainActor.run {
                error = "Failed to load streams. Please try again."
                isLoading = false
            }
        }
    }
}

// MARK: - LiveFilter

enum LiveFilter {
    case all, live, offline
}

// MARK: - StreamRow

struct StreamRow: View {
    let stream: DFStream

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 56, height: 56)
                Image(systemName: stream.isLive ? "video.fill" : "video")
                    .font(.title2)
                    .foregroundStyle(stream.isLive ? .red : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stream.title.isEmpty ? stream.name : stream.title)
                        .font(.headline)
                        .lineLimit(1)
                    if stream.isLive {
                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(stream.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !stream.isPublic {
                        Label("Private", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let pw = stream.password, !pw.isEmpty {
                        Label("Password", systemImage: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Label("\(stream.uniqueViews)", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
