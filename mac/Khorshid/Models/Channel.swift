import Foundation

struct Channel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let lastFetchedAt: Date
    let postCount: Int
    let snapshotPath: String
    let photoPath: String?
}
