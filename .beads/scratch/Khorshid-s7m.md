# Scratch Plan: Khorshid-s7m — Voting system via GitHub Issues API

## Fact-check

- `IdentityStore.voteId(for:)` — confirmed at `mac/Khorshid/Services/IdentityStore.swift`. SHA256(rawRepresentation || utf8(targetId)), returns hex string. Works exactly as spec requires.
- `SocialClient.postComment(issueNumber:body:pat:)` — confirmed. Accepts any string body. Plaintext JSON vote works without changes.
- `SocialStore.poll()` — confirmed. Line `// Plaintext votes/flags are silently skipped — handled by future voting bead` is the exact hook point.
- `VotePayload` struct — confirmed in `SocialPayload.swift`, is `Codable`. Fields: `type`, `target_id`, `signal` ("up"|"important"), `vote_id`, `sent_at`.
- `PATPool.token()` / `markExhausted(_:)` — confirmed in `PATPool.swift`.
- No blocking drift. All infra built by Khorshid-pye is available.

## Architecture

Votes are plaintext GitHub Issue comments — the same channel/room Issue as encrypted posts/comments. The poll loop fetches them alongside comments; we parse `type="vote"` DTOs and tally by `target_id`.

### Client-side tally model

```swift
// VoteTally.swift
struct VoteTally: Equatable, Sendable {
    var upCount: Int = 0
    var importantCount: Int = 0
}
```

No separate `Vote` model needed — the UI only needs counts and "did I vote?" status.

### SocialStore changes

**New state:**
```swift
private(set) var voteTallies: [String: VoteTally] = [:]
private var seenVoteIds: [String: Set<String>] = [:]  // targetId → Set<voteId>, dedup guard
```

**New method:**
```swift
func vote(targetId: String, signal: String) {
    guard let pat = patPool?.token(),
          let identity = identityStore,
          let context = currentContext else { return }

    let voteId = identity.voteId(for: targetId)
    guard !(seenVoteIds[targetId]?.contains(voteId) ?? false) else { return }  // already voted

    let sentAt = Int(Date().timeIntervalSince1970 * 1000)
    applyVote(targetId: targetId, voteId: voteId, signal: signal)  // optimistic

    Task { [weak self] in
        guard let self else { return }
        do {
            let n = try await resolveIssueNumber(context: context)
            let payload = VotePayload(
                type: "vote", target_id: targetId,
                signal: signal, vote_id: voteId, sent_at: sentAt
            )
            let json = try JSONEncoder().encode(payload)
            let bodyStr = String(data: json, encoding: .utf8)!
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
}
```

**applyVote / undoVote helpers:**
```swift
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
```

**"Did I vote?" helper:**
```swift
func hasVoted(targetId: String, signal: String) -> Bool {
    guard let voteId = identityStore?.voteId(for: targetId) else { return false }
    return seenVoteIds[targetId]?.contains(voteId) ?? false
}
```
Note: `hasVoted` is computed from `seenVoteIds` (which is populated by both optimistic writes and confirmed poll reads), so it's consistent without extra state.

**Poll processing — replace the skip comment:**
```swift
// inside the for dto in dtos loop, after the encrypted comment attempt:
if let voteData = dto.body.data(using: .utf8),
   let vote = try? JSONDecoder().decode(VotePayload.self, from: voteData),
   vote.type == "vote" {
    applyVote(targetId: vote.target_id, voteId: vote.vote_id, signal: vote.signal)
}
```

**unsubscribe() cleanup — add:**
```swift
voteTallies = [:]
seenVoteIds = [:]
```

### "Did I vote?" across sessions

`seenVoteIds` is populated from poll reads on each subscribe, so if the user already voted in a prior session, the first full poll rebuilds their vote state from the Issue comment thread. No local persistence needed.

## Files

### Create
- `mac/Khorshid/Models/VoteTally.swift` — `VoteTally` struct

### Modify
- `mac/Khorshid/Stores/SocialStore.swift`
  - Add `voteTallies`, `seenVoteIds` state
  - Add `vote(targetId:signal:)`, `hasVoted(targetId:signal:)`, `applyVote`, `undoVote`
  - In `poll()`: tally VotePayload DTOs
  - In `unsubscribe()`: clear vote state

### Local-only (gitignored)
- `mac/Khorshid.xcodeproj/project.pbxproj` — register VoteTally.swift

## Risks

- **Double-vote from same session**: Guard in `vote()` checks `seenVoteIds` before posting — prevents accidental double-tap.
- **FlagPayload still ignored**: `type="flag"` is not yet handled (Khorshid-qor). The poll loop would try VotePayload decode, fail, and silently skip — correct behavior.
- **Tally drift on failed POST + immediate re-poll**: If optimistic vote is applied, POST fails, undoVote fires, but a concurrent poll already counted the same vote_id — `seenVoteIds` dedup prevents double-count. The undo will decrement correctly.

## Task list
1. Create `VoteTally.swift`
2. Modify `SocialStore.swift` — state + methods
3. Modify `SocialStore.swift` — poll processing
4. Register in pbxproj (local)
5. Build check
