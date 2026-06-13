//
//  StreamList.swift
//  Django Files
//

import SwiftUI
import Combine

struct StreamListView: View {
    let server: Binding<DjangoFilesSession?>

    @State private var streams: [DFStream] = []
    @State private var isLoading = false
    @State private var hasMoreResults = true
    @State private var error: String?
    @State private var filterUserID: Int? = nil
    @State private var users: [DFUser] = []
    @State private var liveFilter: LiveFilter = .all
    @State private var streamPendingDelete: DFStream? = nil

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
                                    .contextMenu {
                                        if stream.isOwner || session.superUser {
                                            Button(action: {
                                                Task { await toggleStreamPrivacy(stream) }
                                            }) {
                                                Label(
                                                    stream.isPublic ? "Make Private" : "Make Public",
                                                    systemImage: stream.isPublic ? "lock" : "lock.open"
                                                )
                                            }

                                            Divider()

                                            Button(role: .destructive, action: {
                                                streamPendingDelete = stream
                                            }) {
                                                Label("Delete Stream", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                            .onAppear {
                                if stream.id == streams.last?.id && hasMoreResults {
                                    loadMoreStreams()
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if stream.isOwner || session.superUser {
                                    Button(role: .destructive) {
                                        streamPendingDelete = stream
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
                        if let error {
                            ListStatusView.error(message: error) { loadInitialStreams() }
                        } else if streams.isEmpty && !isLoading {
                            ListStatusView(
                                icon: "video.slash",
                                title: "No streams found",
                                message: "Start a stream via OBS or another RTMP client"
                            )
                        }
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
                                Image(systemName: "line.3.horizontal.decrease")
                                    .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.primary)
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
        .onReceive(NotificationCenter.default.publisher(for: DFWebSocket.streamStatusNotification)) { notification in
            guard let name = notification.userInfo?["name"] as? String,
                  let isLive = notification.userInfo?["isLive"] as? Bool else { return }
            if let idx = streams.firstIndex(where: { $0.name == name }) {
                withAnimation { streams[idx].isLive = isLive }
            } else if isLive {
                // New stream went live but isn't in the list yet — fetch it
                Task { await refreshStreams() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DFWebSocket.streamDeleteNotification)) { notification in
            guard let name = notification.userInfo?["name"] as? String else { return }
            withAnimation { streams.removeAll { $0.name == name } }
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
        .alert("Delete Stream", isPresented: Binding(
            get: { streamPendingDelete != nil },
            set: { if !$0 { streamPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let stream = streamPendingDelete,
                      let session = server.wrappedValue,
                      let url = URL(string: session.url) else { return }
                streamPendingDelete = nil
                Task { await deleteStream(stream, session: session, serverURL: url) }
            }
            Button("Cancel", role: .cancel) { streamPendingDelete = nil }
        } message: {
            if let stream = streamPendingDelete {
                Text("Are you sure you want to delete \"\(stream.title.isEmpty ? stream.name : stream.title)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Toggle Privacy

    @MainActor
    private func toggleStreamPrivacy(_ stream: DFStream) async {
        guard let session = server.wrappedValue,
              let url = URL(string: session.url) else { return }
        let api = DFAPI(url: url, token: session.token)
        if let newValue = await api.toggleStreamPublic(name: stream.name, newValue: !stream.isPublic, selectedServer: session) {
            withAnimation {
                if let index = streams.firstIndex(where: { $0.name == stream.name }) {
                    streams[index].isPublic = newValue
                }
            }
        } else {
            ToastManager.shared.showToast(message: "Failed to update stream privacy")
        }
    }

    // MARK: - Delete

    @MainActor
    private func deleteStream(_ stream: DFStream, session: DjangoFilesSession, serverURL: URL) async {
        let api = DFAPI(url: serverURL, token: session.token)
        let success = await api.deleteStream(name: stream.name, selectedServer: session)
        if success {
            withAnimation {
                streams.removeAll { $0.name == stream.name }
            }
        }
    }

    // MARK: - Data Loading

    private func loadInitialStreams() {
        guard !isLoading else { return }
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
            await MainActor.run { error = "Invalid session URL" }
            return
        }
        await MainActor.run { isLoading = true }

        let api = DFAPI(url: url, token: session.token)
        let page = (streams.count / streamsPerPage) + 1

        do {
            let response = try await api.getStreams(page: page, filterUserID: filterUserID, selectedServer: session)
            await MainActor.run {
                streams.append(contentsOf: response.streams)
                hasMoreResults = response.next != nil
                error = nil
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
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
                    Label("\(stream.uniqueViews)", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !stream.isPublic {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let pw = stream.password, !pw.isEmpty {
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
