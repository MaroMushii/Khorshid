import Foundation

struct Post: Identifiable, Sendable {
    let id: String
    let bodyHtml: String
    let plainText: String
    let postedAt: Date?
    let viewsLabel: String?
    let reactions: [Reaction]
    let media: [PostMedia]
    let permalink: String
}

struct Reaction: Sendable {
    let emoji: String
    let count: String
}

struct PostMedia: Sendable {
    enum Kind: String, Sendable { case photo, video, unknown }
    let kind: Kind
    let assetPath: String?
    let thumbnailPath: String?
    let aspectRatio: Double?
}
