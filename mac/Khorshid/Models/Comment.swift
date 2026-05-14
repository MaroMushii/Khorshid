import Foundation

struct Comment: Identifiable, Equatable, Sendable {
    let id: String       // SHA256 hex of raw GitHub Issue comment body
    let postId: String?  // nil = top-level room post
    let replyTo: String?
    let body: String
    let sentAt: Date
    let isPending: Bool  // optimistic — true until confirmed by poll
}
