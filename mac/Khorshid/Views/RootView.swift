import SwiftUI

struct RootView: View {

    @Environment(ChannelStore.self) private var store
    @State private var selectedChannelID: Channel.ID?

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationTitle("Khorshid")
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailContent
                .navigationTitle(detailTitle)
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.isLoading)
                        .keyboardShortcut("r", modifiers: .command)
                    }
                }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        List(store.channels, selection: $selectedChannelID) { channel in
            ChannelRow(channel: channel)
        }
        .overlay {
            if store.channels.isEmpty && !store.isLoading && store.errorMessage == nil {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "newspaper",
                    description: Text("The mirror hasn't run yet.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    // MARK: - Detail

    private var detailTitle: String {
        if let id = selectedChannelID,
           let channel = store.channels.first(where: { $0.id == id }) {
            return channel.title
        }
        return "Khorshid"
    }

    @ViewBuilder
    private var detailContent: some View {
        if let id = selectedChannelID, let posts = store.postsByChannel[id] {
            if posts.isEmpty {
                ContentUnavailableView("No Posts", systemImage: "tray")
            } else {
                List(posts) { post in
                    PostRow(post: post)
                }
            }
        } else if let error = store.errorMessage {
            ContentUnavailableView(
                "Could Not Load",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            ContentUnavailableView("Select a Channel", systemImage: "newspaper")
        }
    }
}
