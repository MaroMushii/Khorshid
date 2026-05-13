import SwiftUI

struct TodayFeedView: View {

    @Environment(FeedStore.self) private var feedStore
    @Environment(ChannelStore.self) private var channelStore

    var body: some View {
        Group {
            if feedStore.posts.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
        .refreshable { await feedStore.refresh() }
        .toolbar {
            ToolbarItem {
                if feedStore.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = feedStore.errorMessage {
            ContentUnavailableView(
                "Could Not Load Feed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if feedStore.isLoading {
            ContentUnavailableView("Loading…", systemImage: "newspaper")
        } else {
            ContentUnavailableView(
                "No Posts Yet",
                systemImage: "newspaper",
                description: Text("Today's feed hasn't been aggregated yet.")
            )
        }
    }

    @ViewBuilder
    private var feedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if feedStore.showingYesterday, let date = feedStore.feedDate {
                    yesterdayBanner(date: date)
                }
                ForEach(feedStore.posts) { post in
                    FeedPostRow(
                        post: post,
                        channelPhotoPath: channelStore.channels
                            .first(where: { $0.id == post.channelUsername })?.photoPath
                    )
                }
            }
            .padding(16)
        }
    }

    private func yesterdayBanner(date: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Showing \(date) — today's feed not aggregated yet")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.tertiary, in: .rect(cornerRadius: 8))
    }
}
