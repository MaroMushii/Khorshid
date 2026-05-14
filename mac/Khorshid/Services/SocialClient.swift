import Foundation

actor SocialClient {

    enum SocialError: Error {
        case issueNotFound(String)
        case http(Int)
    }

    private static let apiBase = "https://api.github.com/repos/MaroMushii/Khorshid-Social"
    private static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/MaroMushii/Khorshid-Social/refs/heads/main/manifest.json"
    )!
    private static let manifestTTL: TimeInterval = 300

    private var manifest: ManifestDoc?
    private var manifestFetchedAt: Date?

    // ISO8601DateFormatter is not Sendable — nonisolated(unsafe) matches MirrorClient/FeedClient pattern.
    nonisolated(unsafe) private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private struct ManifestDoc: Decodable {
        let issues: [String: Int]
    }

    struct IssueCommentDTO: Decodable, Sendable {
        let id: Int
        let body: String
        let created_at: String
    }

    func issueNumber(for context: String) async throws -> Int {
        let m = try await refreshedManifest()
        guard let n = m.issues[context] else { throw SocialError.issueNotFound(context) }
        return n
    }

    func fetchComments(issueNumber: Int, since: Date? = nil) async throws -> [IssueCommentDTO] {
        var urlStr = "\(Self.apiBase)/issues/\(issueNumber)/comments?per_page=100"
        if let since {
            urlStr += "&since=\(Self.isoFull.string(from: since))"
        }
        let data = try await get(URL(string: urlStr)!)
        return try JSONDecoder().decode([IssueCommentDTO].self, from: data)
    }

    func postComment(issueNumber: Int, body: String, pat: String) async throws {
        let url = URL(string: "\(Self.apiBase)/issues/\(issueNumber)/comments")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 201 else { throw SocialError.http(code) }
    }

    func invalidateManifest() {
        manifestFetchedAt = nil
    }

    // MARK: - Private

    private func refreshedManifest() async throws -> ManifestDoc {
        if let m = manifest, let fetchedAt = manifestFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.manifestTTL {
            return m
        }
        let data = try await get(Self.manifestURL)
        let m = try JSONDecoder().decode(ManifestDoc.self, from: data)
        manifest = m
        manifestFetchedAt = Date()
        return m
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw SocialError.http(code) }
        return data
    }
}
