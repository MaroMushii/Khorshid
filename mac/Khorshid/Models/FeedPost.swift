import Foundation

struct FeedPost: Identifiable, Sendable {
    let id: String              // matches post_id, "<channel_username>/<telegram_post_id>"
    let channelUsername: String
    let channelTitle: String
    let plainText: String
    let bodyHtml: String
    let media: [PostMedia]
    let postedAt: Date?
    let hotScore: Double
    let voteCount: Int
    let clusterId: String
    let confirmations: [Confirmation]
}

struct Confirmation: Sendable, Hashable {
    let channelUsername: String
    let channelTitle: String
    let permalink: String
}

struct FeedSnapshot: Sendable {
    let date: String            // YYYY-MM-DD
    let generatedAt: Date?
    let posts: [FeedPost]
}
