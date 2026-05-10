import Foundation

struct Post: Identifiable, Sendable {
    let id: String
    let plainText: String
    let postedAt: Date?
    let viewsLabel: String?
    let reactions: [Reaction]
    let permalink: String
}

struct Reaction: Sendable {
    let emoji: String
    let count: String
}
