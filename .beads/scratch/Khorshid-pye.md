# Scratch Plan: Khorshid-pye — Comment system via GitHub Issues API

## Fact-check results

- `PATPool` ✓ `mac/Khorshid/Services/PATPool.swift` — `token()` / `markExhausted()` ready
- `IdentityStore` ✓ `mac/Khorshid/Services/IdentityStore.swift` — `sign()` ready
- `MaroMushii/Khorshid-Social` ✓ live; manifest.json has 18 channel issues (no room issues yet — rooms get provisioned by a future bead)
- `social/schema.ts` ✓ authoritative wire format — all Swift models must mirror it exactly
- `KhorshidApp.swift` ✓ already injects `patPool` and `identityStore` via `.environment()`
- No SocialClient, SocialStore, or social models exist — clean slate
- Patterns to follow: `actor` for network I/O clients, `@Observable @MainActor class` for UI stores
- `Khorshid-x2x` ✓ closed — Khorshid-Social is live and manifest-ready
- `Khorshid-il6` ✓ closed — PAT pool is live

## Architecture

Five new files + one modified:

| File | Type | Role |
|---|---|---|
| `Models/SocialPayload.swift` | Structs/enum | Wire-format types mirroring social/schema.ts |
| `Models/Comment.swift` | Struct | Client-side comment model |
| `Services/SocialCrypto.swift` | enum (static helpers) | AES-256-GCM encrypt/decrypt; SHA256 ID helper |
| `Services/SocialClient.swift` | actor | GitHub Issues API (fetch + post); manifest caching |
| `Stores/SocialStore.swift` | @Observable @MainActor | Polling loop, comment state, orchestrates writes |
| `App/KhorshidApp.swift` | (modify) | Wire SocialStore into app |

`SocialClient` is unaware of `PATPool` — the store (on MainActor) picks the token before calling into the actor. Keeps the client pure and testable.

Manifest is cached 5 min in the client (`raw.githubusercontent.com`). Issue number cached per subscription in the store.

`SocialStore.configure(patPool:identityStore:)` is called from `.onAppear` to avoid circular init order with `@State` properties. Not ideal but correct; a future session can refactor if needed.

Room key: `subscribe(to:key:)` takes a `SymmetricKey` — caller decides. This bead doesn't hardcode any room keys (rooms don't exist in Khorshid-Social yet). The infrastructure is key-agnostic.

## Files — detailed content

### `mac/Khorshid/Models/SocialPayload.swift`

```swift
import Foundation

struct SocialPayloadWrapper: Codable {
    let v: Int
    let n: String   // base64 12-byte AES-GCM nonce
    let c: String   // base64 ciphertext + 16-byte tag
}

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

struct VotePayload: Codable {
    let type: String
    let target_id: String
    let signal: String
    let vote_id: String
    let sent_at: Int
}

struct FlagPayload: Codable {
    let type: String
    let target_id: String
    let vote_id: String
    let sent_at: Int
}
```

### `mac/Khorshid/Models/Comment.swift`

```swift
import Foundation

struct Comment: Identifiable, Equatable, Sendable {
    let id: String       // SHA256 hex of raw GitHub Issue comment body
    let postId: String?  // nil = top-level room post
    let replyTo: String?
    let body: String
    let sentAt: Date
    let isPending: Bool  // optimistic — true until confirmed by poll
}
```

### `mac/Khorshid/Services/SocialCrypto.swift`

```swift
import Foundation
import CryptoKit

enum SocialCrypto {

    enum CryptoError: Error {
        case malformedWrapper
        case unknownPayloadType
    }

    static func encrypt(_ payload: DecryptedPayload, key: SymmetricKey) throws -> SocialPayloadWrapper {
        let plaintext = try payload.encoded()
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        var combined = Data(box.ciphertext)
        combined.append(contentsOf: box.tag)
        return SocialPayloadWrapper(
            v: 1,
            n: Data(nonce).base64EncodedString(),
            c: combined.base64EncodedString()
        )
    }

    static func decrypt(_ wrapper: SocialPayloadWrapper, key: SymmetricKey) throws -> DecryptedPayload {
        guard wrapper.v == 1,
              let nonceData = Data(base64Encoded: wrapper.n),
              let combined = Data(base64Encoded: wrapper.c),
              combined.count >= 16 else {
            throw CryptoError.malformedWrapper
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: key)
        let dto = try JSONDecoder().decode(DecryptedPayload.DTO.self, from: plaintext)
        guard let result = DecryptedPayload(dto: dto) else {
            throw CryptoError.unknownPayloadType
        }
        return result
    }

    static func sha256hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

### `mac/Khorshid/Services/SocialClient.swift`

```swift
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

    // ISO8601DateFormatter is not Sendable — nonisolated(unsafe) matches MirrorClient pattern.
    nonisolated(unsafe) private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
```

### `mac/Khorshid/Stores/SocialStore.swift`

```swift
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
```

### Modify: `mac/Khorshid/App/KhorshidApp.swift`

- Add `@State private var socialStore = SocialStore()`
- Add `.environment(socialStore)`
- In `.onAppear`: `socialStore.configure(patPool: patPool, identityStore: identityStore)`

### `mac/Khorshid.xcodeproj/project.pbxproj`

Five new files need registration (PBXFileReference + PBXBuildFile + group + sources entries). Based on the previous bead, the Xcode linter/formatter will auto-register these after the build attempt — write the Swift files first, then build.

## Task list

1. Create `mac/Khorshid/Models/SocialPayload.swift`
2. Create `mac/Khorshid/Models/Comment.swift`
3. Create `mac/Khorshid/Services/SocialCrypto.swift`
4. Create `mac/Khorshid/Services/SocialClient.swift`
5. Create `mac/Khorshid/Stores/SocialStore.swift`
6. Modify `mac/Khorshid/App/KhorshidApp.swift`
7. Build — linter registers pbxproj entries; fix any Swift 6 errors

## Risks

- **Rooms don't exist in manifest**: `issueNumber(for:)` will throw `.issueNotFound` for any room context. The store catches this silently and retries on the next poll. Correct behavior — channels will work, rooms will start working when provisioned.
- **`SocialStore` init order**: `configure(patPool:identityStore:)` must be called from `.onAppear` before any `subscribe()` call. If subscribe fires before configure, `patPool?.token()` returns nil and the send is dropped silently. Acceptable — the user can't subscribe before the view appears.
- **Optimistic comment IDs**: Pending comments use UUID as ID; on confirmation they get the SHA256 of the raw body. The merge logic replaces all pending items on successful poll. If poll races with post, there's a brief duplicate. The dedup by ID prevents persisting duplicates.
- **ISO8601DateFormatter in `poll()`**: Creating two formatters in each poll call is technically wasteful. Fine for now — a future pass can lift them to static.
- **pbxproj**: Five files need manual/linter registration. Same as PATPool bead — build, wait for linter, build again.

## Verification

- Build succeeds under Swift 6 strict concurrency
- `SocialCrypto.encrypt()` → `decrypt()` round-trip produces identical payload (unit-testable in Xcode playground)
- `SocialClient.fetchComments(issueNumber:since:)` returns real data from a live channel issue
- `SocialStore` sets `isLoading = false` and populates `error` on poll failure
- `token()` returns nil on empty pool → `send()` drops silently (no crash)
