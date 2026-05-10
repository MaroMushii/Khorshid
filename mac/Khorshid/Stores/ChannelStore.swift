import Foundation
import Observation

@Observable
@MainActor
final class ChannelStore {

    private(set) var channels: [Channel] = []
    private(set) var postsByChannel: [String: [Post]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client = MirrorClient()
    private var pollTask: Task<Void, Never>?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await client.fetchIndex()
            channels = fetched

            let client = self.client
            var result: [String: [Post]] = [:]

            try await withThrowingTaskGroup(of: (String, [Post]).self) { group in
                for channel in fetched {
                    let path = channel.snapshotPath
                    let id = channel.id
                    group.addTask {
                        let posts = try await client.fetchPosts(snapshotPath: path)
                        return (id, posts)
                    }
                }
                for try await (id, posts) in group {
                    result[id] = posts
                }
            }

            postsByChannel = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
