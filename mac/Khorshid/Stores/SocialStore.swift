import Foundation
import CryptoKit
import Observation

@Observable @MainActor
final class SocialStore {

    private(set) var comments: [Comment] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    private let client = SocialClient()
    private var patPool: PATPool?
    private var identityStore: IdentityStore?

    private var currentContext: String?
    private var currentKey: SymmetricKey?
    private var issueNumber: Int?
    private var lastSeenAt: Date?
    private var pollTask: Task<Void, Never>?

    func configure(patPool: PATPool, identityStore: IdentityStore) {
        self.patPool = patPool
        self.identityStore = identityStore
    }

    func subscribe(to context: String, key: SymmetricKey) {
        guard context != currentContext else { return }
        unsubscribe()
        currentContext = context
        currentKey = key
        comments = []
        error = nil
        issueNumber = nil
        lastSeenAt = nil
        pollTask = Task { [weak self] in await self?.runPoll() }
    }

    func unsubscribe() {
        pollTask?.cancel()
        pollTask = nil
        currentContext = nil
        currentKey = nil
        issueNumber = nil
        lastSeenAt = nil
        comments = []
    }

    func send(body: String, postId: String? = nil, replyTo: String? = nil) {
        guard let key = currentKey,
              let context = currentContext,
              let pat = patPool?.token() else { return }

        let sentAt = Int(Date().timeIntervalSince1970 * 1000)
        let payload: DecryptedPayload = postId != nil
            ? .comment(postId: postId!, replyTo: replyTo, body: body, sentAt: sentAt)
            : .post(body: body, sentAt: sentAt)

        let optimisticId = UUID().uuidString
        comments.append(Comment(
            id: optimisticId, postId: postId, replyTo: replyTo,
            body: body,
            sentAt: Date(timeIntervalSince1970: Double(sentAt) / 1000),
            isPending: true
        ))

        Task { [weak self] in
            guard let self else { return }
            do {
                let n = try await resolveIssueNumber(context: context)
                let wrapper = try SocialCrypto.encrypt(payload, key: key)
                let json = try JSONEncoder().encode(wrapper)
                let bodyStr = String(data: json, encoding: .utf8)!
                try await client.postComment(issueNumber: n, body: bodyStr, pat: pat)
            } catch let err as SocialClient.SocialError {
                if case .http(let code) = err, [401, 403, 429].contains(code) {
                    patPool?.markExhausted(pat)
                }
                removeOptimistic(optimisticId)
                self.error = err
            } catch {
                removeOptimistic(optimisticId)
                self.error = error
            }
        }
    }

    // MARK: - Private

    private func runPoll() async {
        while !Task.isCancelled {
            await poll()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func poll() async {
        guard let context = currentContext, let key = currentKey else { return }
        do {
            let n = try await resolveIssueNumber(context: context)
            let dtos = try await client.fetchComments(issueNumber: n, since: lastSeenAt)
            guard !dtos.isEmpty else { return }

            var fresh: [Comment] = []
            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoPlain = ISO8601DateFormatter()
            isoPlain.formatOptions = [.withInternetDateTime]

            for dto in dtos {
                guard let bodyData = dto.body.data(using: .utf8) else { continue }
                let rawId = SocialCrypto.sha256hex(of: bodyData)
                let createdAt = isoFull.date(from: dto.created_at)
                    ?? isoPlain.date(from: dto.created_at)
                    ?? Date()

                if let wrapper = try? JSONDecoder().decode(SocialPayloadWrapper.self, from: bodyData),
                   let decoded = try? SocialCrypto.decrypt(wrapper, key: key) {
                    switch decoded {
                    case .post(let b, let ts):
                        fresh.append(Comment(
                            id: rawId, postId: nil, replyTo: nil, body: b,
                            sentAt: Date(timeIntervalSince1970: Double(ts) / 1000),
                            isPending: false
                        ))
                    case .comment(let pid, let rt, let b, let ts):
                        fresh.append(Comment(
                            id: rawId, postId: pid, replyTo: rt, body: b,
                            sentAt: Date(timeIntervalSince1970: Double(ts) / 1000),
                            isPending: false
                        ))
                    }
                }
                // Plaintext votes/flags are silently skipped — handled by future voting bead

                if lastSeenAt == nil || createdAt > lastSeenAt! {
                    lastSeenAt = createdAt
                }
            }

            if !fresh.isEmpty {
                comments.removeAll { $0.isPending }
                let existingIds = Set(comments.map(\.id))
                comments.append(contentsOf: fresh.filter { !existingIds.contains($0.id) })
                comments.sort { $0.sentAt < $1.sentAt }
            }
        } catch {
            self.error = error
        }
    }

    private func resolveIssueNumber(context: String) async throws -> Int {
        if let n = issueNumber { return n }
        let n = try await client.issueNumber(for: context)
        issueNumber = n
        return n
    }

    private func removeOptimistic(_ id: String) {
        comments.removeAll { $0.id == id }
    }
}
