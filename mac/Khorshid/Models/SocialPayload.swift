import Foundation

// MARK: - Encrypted envelope (top-level issue comment body)

struct SocialPayloadWrapper: Codable {
    let v: Int
    let n: String    // base64 12-byte AES-GCM nonce
    let c: String    // base64 ciphertext + 16-byte GCM tag
    let pub: String? // pubkey hex — v:2+
    let sig: String? // base64 Ed25519 sig over nonceBytes||combinedBytes — v:2+
}

// MARK: - Decrypted payload (inside the encrypted envelope)

enum DecryptedPayload {
    case post(body: String, sentAt: Int)
    case comment(postId: String, replyTo: String?, body: String, sentAt: Int)
}

extension DecryptedPayload {
    struct DTO: Decodable {
        let type: String
        let body: String?
        let post_id: String?
        let reply_to: String?
        let sent_at: Int
    }

    init?(dto: DTO) {
        switch dto.type {
        case "post":
            guard let body = dto.body else { return nil }
            self = .post(body: body, sentAt: dto.sent_at)
        case "comment":
            guard let postId = dto.post_id, let body = dto.body else { return nil }
            self = .comment(postId: postId, replyTo: dto.reply_to, body: body, sentAt: dto.sent_at)
        default:
            return nil
        }
    }

    func encoded() throws -> Data {
        struct Encoded: Encodable {
            let type: String
            let body: String?
            let post_id: String?
            let reply_to: String?
            let sent_at: Int
        }
        let enc: Encoded
        switch self {
        case .post(let body, let sentAt):
            enc = Encoded(type: "post", body: body, post_id: nil, reply_to: nil, sent_at: sentAt)
        case .comment(let postId, let replyTo, let body, let sentAt):
            enc = Encoded(type: "comment", body: body, post_id: postId, reply_to: replyTo, sent_at: sentAt)
        }
        return try JSONEncoder().encode(enc)
    }
}

// MARK: - Plaintext payloads (votes + flags — parsed but acted on by future beads)

struct VotePayload: Codable {
    let type: String
    let target_id: String
    let signal: String   // "up" | "important"
    let vote_id: String
    let sent_at: Int
}

struct FlagPayload: Codable {
    let type: String
    let target_id: String
    let vote_id: String
    let sent_at: Int
}
