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

            let client = self.client
            var snapshots: [String: SnapshotData] = [:]

            try await withThrowingTaskGroup(of: (String, SnapshotData).self) { group in
                for channel in fetched {
                    let path = channel.snapshotPath
                    let id = channel.id
                    group.addTask {
                        let data = try await client.fetchSnapshot(snapshotPath: path)
                        return (id, data)
                    }
                }
                for try await (id, data) in group {
                    snapshots[id] = data
                }
            }

            postsByChannel = snapshots.mapValues { $0.posts }
            channels = fetched.map { ch in
                Channel(
                    id: ch.id,
                    title: ch.title,
                    lastFetchedAt: ch.lastFetchedAt,
                    postCount: ch.postCount,
                    snapshotPath: ch.snapshotPath,
                    photoPath: snapshots[ch.id]?.channelPhotoPath
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
