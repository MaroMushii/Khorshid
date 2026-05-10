import Foundation

actor MirrorClient {

    enum FetchError: Error, LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code): "Mirror returned HTTP \(code)."
            }
        }
    }

    private static let baseURL = "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export"

    // ISO8601DateFormatter is a non-Sendable reference type; nonisolated(unsafe)
    // is required to use these static formatters across concurrency boundaries.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - DTOs

    private struct IndexDoc: Decodable {
        let channels: [IndexEntry]
    }

    private struct IndexEntry: Decodable {
        let username: String
        let title: String
        let last_fetched_at: String
        let post_count: Int
        let snapshot_path: String
    }

    private struct SnapshotDoc: Decodable {
        let posts: [PostDTO]
    }

    private struct PostDTO: Decodable {
        let id: String
        let plain_text: String
        let views_label: String?
        let posted_at: String?
        let reactions: [ReactionDTO]
        let permalink: String
    }

    private struct ReactionDTO: Decodable {
        let emoji: String
        let count: String
    }

    // MARK: - Public API

    func fetchIndex() async throws -> [Channel] {
        let url = URL(string: "\(Self.baseURL)/index.json")!
        let data = try await fetch(url)
        let doc = try JSONDecoder().decode(IndexDoc.self, from: data)
        return doc.channels.map { entry in
            Channel(
                id: entry.username,
                title: entry.title,
                lastFetchedAt: parseDate(entry.last_fetched_at) ?? .distantPast,
                postCount: entry.post_count,
                snapshotPath: entry.snapshot_path
            )
        }
    }

    func fetchPosts(snapshotPath: String) async throws -> [Post] {
        let url = URL(string: "\(Self.baseURL)/\(snapshotPath)")!
        let data = try await fetch(url)
        let doc = try JSONDecoder().decode(SnapshotDoc.self, from: data)
        return doc.posts.map { dto in
            Post(
                id: dto.id,
                plainText: dto.plain_text,
                postedAt: parseDate(dto.posted_at),
                viewsLabel: dto.views_label,
                reactions: dto.reactions.map { Reaction(emoji: $0.emoji, count: $0.count) },
                permalink: dto.permalink
            )
        }
    }

    // MARK: - Helpers

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return Self.isoFractional.date(from: string) ?? Self.isoPlain.date(from: string)
    }
}
