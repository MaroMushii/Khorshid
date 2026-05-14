import Foundation
import CryptoKit
import Observation

@Observable @MainActor
final class SocialStore {

    private(set) var comments: [Comment] = []
    private(set) var voteTallies: [String: VoteTally] = [:]
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
    private var sendTasks: [String: Task<Void, Never>] = [:]
    private var issueNumberTask: Task<Int, Error>?
    private var seenVoteIds: [String: Set<String>] = [:]

    private let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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
        voteTallies = [:]
        seenVoteIds = [:]
        error = nil
        issueNumber = nil
        lastSeenAt = nil
        pollTask = Task { [weak self] in await self?.runPoll() }
    }

    func unsubscribe() {
        pollTask?.cancel()
        pollTask = nil
        for task in sendTasks.values { task.cancel() }
        sendTasks = [:]
        issueNumberTask?.cancel()
        issueNumberTask = nil
        currentContext = nil
        currentKey = nil
        issueNumber = nil
        lastSeenAt = nil
        comments = []
        voteTallies = [:]
        seenVoteIds = [:]
    }

    func send(body: String, postId: String? = nil, replyTo: String? = nil) {
        guard let key = currentKey,
              let context = currentContext,
              let pat = patPool?.token(),
              let identity = identityStore else { return }

        let sentAt = Int(Date().timeIntervalSince1970 * 1000)
        let payload: DecryptedPayload
        if let postId {
            payload = .comment(postId: postId, replyTo: replyTo, body: body, sentAt: sentAt)
        } else {
            payload = .post(body: body, sentAt: sentAt)
        }

        let optimisticId = UUID().uuidString
        comments.append(Comment(
            id: optimisticId, postId: postId, replyTo: replyTo,
            body: body,
            sentAt: Date(timeIntervalSince1970: Double(sentAt) / 1000),
            isPending: true
        ))

        let task = Task { [weak self] in
            defer { self?.sendTasks.removeValue(forKey: optimisticId) }
            guard let self else { return }
            do {
                let n = try await resolveIssueNumber(context: context)
                guard let pubHex = identity.identity?.publicKeyHex else {
                    throw IdentityError.notReady
                }
                // Non-escaping closure; executes on MainActor because this Task inherits SocialStore's isolation.
                let wrapper = try SocialCrypto.encrypt(payload, key: key, publicKeyHex: pubHex) { [identity] in
                    try identity.sign($0)
                }
                let json = try JSONEncoder().encode(wrapper)
                guard let bodyStr = String(data: json, encoding: .utf8) else { return }
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
        sendTasks[optimisticId] = task
    }

    func vote(targetId: String, signal: String) {
        guard let pat = patPool?.token(),
              let identity = identityStore,
              let context = currentContext else { return }

        let voteId = identity.voteId(for: targetId)
        guard !(seenVoteIds[targetId]?.contains(voteId) ?? false) else { return }

        let sentAt = Int(Date().timeIntervalSince1970 * 1000)
        applyVote(targetId: targetId, voteId: voteId, signal: signal)

        let taskId = UUID().uuidString
        let task = Task { [weak self] in
            defer { self?.sendTasks.removeValue(forKey: taskId) }
            guard let self else { return }
            do {
                let n = try await resolveIssueNumber(context: context)
                let payload = VotePayload(
                    type: "vote", target_id: targetId,
                    signal: signal, vote_id: voteId, sent_at: sentAt
                )
                let json = try JSONEncoder().encode(payload)
                guard let bodyStr = String(data: json, encoding: .utf8) else { return }
                try await client.postComment(issueNumber: n, body: bodyStr, pat: pat)
            } catch let err as SocialClient.SocialError {
                if case .http(let code) = err, [401, 403, 429].contains(code) {
                    patPool?.markExhausted(pat)
                }
                undoVote(targetId: targetId, voteId: voteId, signal: signal)
                self.error = err
            } catch {
                undoVote(targetId: targetId, voteId: voteId, signal: signal)
                self.error = error
            }
        }
        sendTasks[taskId] = task
    }

    func hasVoted(targetId: String, signal: String) -> Bool {
        guard let voteId = identityStore?.voteId(for: targetId) else { return false }
        return seenVoteIds[targetId]?.contains(voteId) ?? false
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
            guard !Task.isCancelled else { return }
            let dtos = try await client.fetchComments(issueNumber: n, since: lastSeenAt)
            guard !Task.isCancelled else { return }
            guard !dtos.isEmpty else { return }

            var fresh: [Comment] = []

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
                } else if let vote = try? JSONDecoder().decode(VotePayload.self, from: bodyData),
                          vote.type == "vote" {
                    applyVote(targetId: vote.target_id, voteId: vote.vote_id, signal: vote.signal)
                }

                if let last = lastSeenAt {
                    if createdAt > last { lastSeenAt = createdAt }
                } else {
                    lastSeenAt = createdAt
                }
            }

            if !fresh.isEmpty {
                comments.removeAll { $0.isPending }
                let existingIds = Set(comments.map(\.id))
                comments.append(contentsOf: fresh.filter { !existingIds.contains($0.id) })
                comments.sort { $0.sentAt < $1.sentAt }
            }
        } catch is CancellationError {
            // Task was cancelled — not an error worth surfacing
        } catch {
            self.error = error
        }
    }

    private func resolveIssueNumber(context: String) async throws -> Int {
        if let n = issueNumber { return n }
        if let t = issueNumberTask { return try await t.value }
        let t = Task { [client] in try await client.issueNumber(for: context) }
        issueNumberTask = t
        do {
            let n = try await t.value
            issueNumber = n
            issueNumberTask = nil
            return n
        } catch {
            issueNumberTask = nil
            throw error
        }
    }

    private func removeOptimistic(_ id: String) {
        comments.removeAll { $0.id == id }
    }

    private func applyVote(targetId: String, voteId: String, signal: String) {
        seenVoteIds[targetId, default: []].insert(voteId)
        switch signal {
        case "up":        voteTallies[targetId, default: VoteTally()].upCount += 1
        case "important": voteTallies[targetId, default: VoteTally()].importantCount += 1
        default: break
        }
    }

    private func undoVote(targetId: String, voteId: String, signal: String) {
        seenVoteIds[targetId]?.remove(voteId)
        switch signal {
        case "up":        voteTallies[targetId]?.upCount = max(0, (voteTallies[targetId]?.upCount ?? 0) - 1)
        case "important": voteTallies[targetId]?.importantCount = max(0, (voteTallies[targetId]?.importantCount ?? 0) - 1)
        default: break
        }
    }
}
