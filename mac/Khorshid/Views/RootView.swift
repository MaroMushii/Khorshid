import SwiftUI

enum SidebarSelection: Hashable {
    case today
    case channel(String)
}

struct RootView: View {

    @Environment(ChannelStore.self) private var channelStore
    @Environment(FeedStore.self) private var feedStore
    @State private var selection: SidebarSelection? = .today

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle("Khorshid")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailContent
                .navigationTitle(detailTitle)
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task {
                                async let a: Void = channelStore.refresh()
                                async let b: Void = feedStore.refresh()
                                _ = await (a, b)
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(channelStore.isLoading || feedStore.isLoading)
                        .keyboardShortcut("r", modifiers: .command)
                    }
                }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: SidebarSelection.today) {
                    Label {
                        Text("Today's Highlights")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Channels") {
                ForEach(channelStore.channels) { channel in
                    NavigationLink(value: SidebarSelection.channel(channel.id)) {
                        ChannelRow(channel: channel)
                    }
                }
            }
        }
        .overlay {
            if channelStore.channels.isEmpty && !channelStore.isLoading && channelStore.errorMessage == nil {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "newspaper",
                    description: Text("The mirror hasn't run yet.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                if channelStore.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: - Detail

    private var detailTitle: String {
        switch selection {
        case .today, .none:
            return "Today"
        case .channel(let id):
            return channelStore.channels.first(where: { $0.id == id })?.title ?? "Khorshid"
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .today, .none:
            TodayFeedView()
        case .channel(let id):
            channelDetail(id: id)
        }
    }

    @ViewBuilder
    private func channelDetail(id: String) -> some View {
        if let posts = channelStore.postsByChannel[id] {
            if posts.isEmpty {
                ContentUnavailableView("No Posts", systemImage: "tray")
            } else {
                List(posts) { post in
                    PostRow(post: post)
                }
            }
        } else if let error = channelStore.errorMessage {
            ContentUnavailableView(
                "Could Not Load",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            ContentUnavailableView("Loading…", systemImage: "newspaper")
        }
    }
}
