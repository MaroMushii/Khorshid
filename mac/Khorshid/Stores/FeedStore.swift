import Foundation
import Observation

@Observable
@MainActor
final class FeedStore {

    private(set) var posts: [FeedPost] = []
    private(set) var generatedAt: Date?
    private(set) var feedDate: String?
    private(set) var showingYesterday = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client = FeedClient()
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let now = Date()
            if let today = try await client.fetchFeed(for: now), !today.posts.isEmpty {
                apply(today, showingYesterday: false)
                return
            }
            let yesterday = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: now)!
            if let snap = try await client.fetchFeed(for: yesterday) {
                apply(snap, showingYesterday: true)
            } else {
                posts = []
                generatedAt = nil
                feedDate = nil
                showingYesterday = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ snap: FeedSnapshot, showingYesterday: Bool) {
        // Server already sorts by hot_score desc; sort defensively.
        posts = snap.posts.sorted { $0.hotScore > $1.hotScore }
        generatedAt = snap.generatedAt
        feedDate = snap.date
        self.showingYesterday = showingYesterday
    }
}
