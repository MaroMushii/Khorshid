import Foundation

actor FeedClient {

    enum FetchError: Error, LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code): "Feed returned HTTP \(code)."
            }
        }
    }

    private static let baseURL = "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export"

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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - DTOs

    private struct FeedDoc: Decodable {
        let date: String
        let generated_at: String?
        let posts: [FeedPostDTO]
    }

    private struct FeedPostDTO: Decodable {
        let post_id: String
        let channel_username: String
        let channel_title: String
        let plain_text: String
        let body_html: String
        let media: [MediaDTO]
        let posted_at: String?
        let hot_score: Double
        let vote_count: Int
        let cluster_id: String
        let confirmations: [ConfirmationDTO]
    }

    private struct ConfirmationDTO: Decodable {
        let channel_username: String
        let channel_title: String
        let permalink: String
    }

    private struct MediaDTO: Decodable {
        let kind: String
        let asset_path: String?
        let thumbnail_path: String?
        let aspect_ratio: Double?
    }

    // MARK: - Public API

    /// Returns `nil` for HTTP 404 (no feed file yet for that date). Throws on other errors.
    func fetchFeed(for date: Date) async throws -> FeedSnapshot? {
        let day = Self.dayFormatter.string(from: date)
        let url = URL(string: "\(Self.baseURL)/feed/\(day).json")!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.http(0)
        }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw FetchError.http(http.statusCode) }

        let doc = try JSONDecoder().decode(FeedDoc.self, from: data)
        let posts = doc.posts.map { dto in
            FeedPost(
                id: dto.post_id,
                channelUsername: dto.channel_username,
                channelTitle: dto.channel_title,
                plainText: dto.plain_text,
                bodyHtml: dto.body_html,
                media: dto.media.map {
                    PostMedia(
                        kind: PostMedia.Kind(rawValue: $0.kind) ?? .unknown,
                        assetPath: $0.asset_path,
                        thumbnailPath: $0.thumbnail_path,
                        aspectRatio: $0.aspect_ratio
                    )
                },
                postedAt: parseDate(dto.posted_at),
                hotScore: dto.hot_score,
                voteCount: dto.vote_count,
                clusterId: dto.cluster_id,
                confirmations: dto.confirmations.map {
                    Confirmation(
                        channelUsername: $0.channel_username,
                        channelTitle: $0.channel_title,
                        permalink: $0.permalink
                    )
                }
            )
        }
        return FeedSnapshot(
            date: doc.date,
            generatedAt: parseDate(doc.generated_at),
            posts: posts
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return Self.isoFractional.date(from: string) ?? Self.isoPlain.date(from: string)
    }
}
