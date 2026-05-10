import Foundation

struct SnapshotData: Sendable {
    let channelPhotoPath: String?
    let posts: [Post]
}

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
        let channel: ChannelInfoDTO
        let posts: [PostDTO]
    }

    private struct ChannelInfoDTO: Decodable {
        let photo_path: String?
    }

    private struct PostDTO: Decodable {
        let id: String
        let body_html: String
        let plain_text: String
        let views_label: String?
        let posted_at: String?
        let reactions: [ReactionDTO]
        let media: [MediaDTO]
        let permalink: String
    }

    private struct ReactionDTO: Decodable {
        let emoji: String
        let count: String
    }

    private struct MediaDTO: Decodable {
        let kind: String
        let asset_path: String?
        let thumbnail_path: String?
        let aspect_ratio: Double?
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
                snapshotPath: entry.snapshot_path,
                photoPath: nil
            )
        }
    }

    func fetchSnapshot(snapshotPath: String) async throws -> SnapshotData {
        let url = URL(string: "\(Self.baseURL)/\(snapshotPath)")!
        let data = try await fetch(url)
        let doc = try JSONDecoder().decode(SnapshotDoc.self, from: data)
        let posts = doc.posts.map { dto in
            Post(
                id: dto.id,
                bodyHtml: dto.body_html,
                plainText: dto.plain_text,
                postedAt: parseDate(dto.posted_at),
                viewsLabel: dto.views_label,
                reactions: dto.reactions.map { Reaction(emoji: $0.emoji, count: $0.count) },
                media: dto.media.map {
                    PostMedia(
                        kind: PostMedia.Kind(rawValue: $0.kind) ?? .unknown,
                        assetPath: $0.asset_path,
                        thumbnailPath: $0.thumbnail_path,
                        aspectRatio: $0.aspect_ratio
                    )
                },
                permalink: dto.permalink
            )
        }
        return SnapshotData(channelPhotoPath: doc.channel.photo_path, posts: posts)
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
