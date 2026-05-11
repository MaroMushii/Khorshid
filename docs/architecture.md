# Architecture

## Transport: GitHub only

Khorshid runs entirely over GitHub infrastructure. No Firestore, no relay nodes, no P2P
gossip layer. GitHub is fully accessible from Iran (REST API, raw CDN, git protocol —
see `network.md`), battle-tested, and requires no server to operate.

Two repos carry the entire system:

```
MaroMushii/Khorshid          — mirror code + GH Actions workflows + export branch
MaroMushii/khorshid-social   — social layer (GitHub Issues for comments, votes, flags)
MaroMushii/khorshid-room-*   — one private repo per private room (created by room owner)
```

---

## Content model

Three distinct content types, each with a different read/write model:

```
Channels   — read-only Telegram news feeds, mirrored by GH Actions every ~5 min.
             Users vote and comment. Cannot post original content.

Rooms      — curated community discussion spaces (core team defines the list).
             Users post original content, reply to each other, vote.

Private    — invite-only encrypted spaces. One private GitHub repo per room.
             Creator holds the PAT; members join via invite bundle.
```

**Today** is not a separate content type — it is an aggregated editorial view that pulls
from both channels and rooms, ranked by the hot score formula.

---

## Data flow

### News (read path)

```
Telegram channels
  ↓  mirror scraper runs in GH Actions every ~5 min
export branch (MaroMushii/Khorshid)
  ↓  raw.githubusercontent.com CDN — no auth, no rate limit
Client app reads channel snapshots:
  channels/<slug>/snapshot.json   — posts for this channel
  feed/<YYYY-MM-DD>.json          — Today's ranked feed (written by aggregator)
```

### Social (write path)

```
User action (comment, vote, flag)
  → AES-256-GCM encrypt (comments only; votes and flags are plaintext)
  → pick random PAT from pool
  → POST /repos/MaroMushii/khorshid-social/issues/:id/comments
  → optimistic UI: action appears immediately, confirmed on next poll
```

### Social (read path)

```
On context open (channel or room):
  GET /repos/MaroMushii/khorshid-social/issues?labels=<slug>&state=open
  → find today's issue by title, cache issue number locally

Poll loop (adaptive interval: 10s active, 60s backgrounded):
  GET /repos/.../issues/:id/comments?since=<last_seen_timestamp>
  → for each new comment:
      if plaintext (type field present): parse vote or flag
      if encrypted blob ({v,n,c}): AES-GCM decrypt → render
```

GitHub Issues API is immediately consistent — a comment posted via REST is visible in
the next GET within milliseconds. This gives near-real-time behavior without WebSockets
or a dedicated server.

---

## khorshid-social: GitHub Issues as the social layer

One GitHub Issue per context per day. Issues are created automatically by the aggregator
GH Action if they don't exist yet.

**Issue naming convention:**
```
channel-<slug>-<YYYY-MM-DD>     e.g.  channel-bbcpersian-2026-05-11
room-<slug>-<YYYY-MM-DD>        e.g.  room-street-reports-2026-05-11
```

Each Issue comment is one of three payload types:

### Encrypted payloads (comments and room posts)

Wrapper — always this shape:
```json
{ "v": 1, "n": "<12-byte nonce b64>", "c": "<AES-256-GCM ciphertext b64>" }
```

Decrypted content is polymorphic by `type`:
```json
{ "type": "post",    "body": "...", "sent_at": 1746900000000 }
{ "type": "comment", "post_id": "bbcpersian/1234", "reply_to": "<sha256>", "body": "...", "sent_at": 1746900000000 }
```

`post_id` is the Telegram post identifier from the mirror snapshot (`<channel>/<num>`).
`reply_to` is the sha256 of the parent comment's ciphertext blob — used for threaded display.

### Plaintext payloads (votes and flags)

Votes and flags are NOT encrypted. The aggregator GH Action reads them without any
decryption, which lets it rank content without holding any room keys.

```json
{ "type": "vote", "target_id": "<sha256 of target comment's ciphertext>", "signal": "up|important", "vote_id": "<sha256(privkey || target_id) b64>", "sent_at": 1746900000000 }
{ "type": "flag", "target_id": "<sha256 of target comment's ciphertext>",                            "vote_id": "<sha256(privkey || target_id) b64>", "sent_at": 1746900000000 }
```

**`vote_id` is a commitment hash, not a public key.**
- Same user + same target → same `vote_id` (enables deduplication)
- Same user + different target → different `vote_id` (cannot correlate votes across posts)
- Cannot be reversed to reveal the voter's identity

---

## Today aggregator (GH Actions, every minute)

Produces `feed/<YYYY-MM-DD>.json` on the export branch — the ranked Today view.

```
1. Fetch all channel posts for today from export branch
2. Fetch all room posts from khorshid-social (decrypt via public room key — Actions secret)
3. Fetch all plaintext votes and flags from khorshid-social
4. LLM deduplication:
     POST today's channel post headlines + timestamps to Claude Haiku
     Response: cluster_id per post (same story across channels → same cluster)
5. Per post/room-post: tally importance votes, deduplicate by vote_id
6. Hot score:
     hot_score = wilson_lower_bound(importance_votes, total_votes) × e^(−λ × age_hours)
     Posts and room posts: λ = 0.3
     Comments:            λ = 0.5  (go stale faster)
7. Community Report detection:
     Comments whose hot_score exceeds COMMUNITY_REPORT_THRESHOLD
     → included in feed JSON alongside news posts, tagged community_report: true
8. Flag filtering:
     Content with ≥ N unique flag vote_ids → excluded from feed
9. Write feed/<YYYY-MM-DD>.json to export branch
```

`feed/<YYYY-MM-DD>.json` shape:
```json
{
  "date": "2026-05-11",
  "generated_at": 1746900000000,
  "posts": [
    {
      "cluster_id": "abc123",
      "sources": ["bbcpersian/1234", "iranintl/9981"],
      "hot_score": 4.2,
      "importance_votes": 38,
      "channel_slug": "bbcpersian",
      "post_id": "bbcpersian/1234"
    }
  ],
  "community_reports": [
    {
      "comment_encrypted": { "v": 1, "n": "...", "c": "..." },
      "hot_score": 3.1,
      "importance_votes": 22,
      "source_issue": "channel-bbcpersian-2026-05-11",
      "community_report": true
    }
  ]
}
```

Community Report blobs are included verbatim in the feed JSON so clients decrypt and
display them without a separate API call. The aggregator never reads comment content —
only the plaintext vote counts.

---

## Identity

- Ed25519 keypair generated on first launch, stored in device Keychain.
- Public key is the user's identity. Display name stored locally alongside it.
- No server-side registration. No GitHub account. No email.
- Backup: export keypair as QR code for device migration.

---

## Encryption

All content is AES-256-GCM. There is no unencrypted content.

**Public channels and rooms:** key is hardcoded per context in the app binary.
- "Public" = anyone with the app can decrypt.
- `khorshid-social` is a public repo — GitHub sees ciphertext.
- Keys are rotated via app update if compromised.

**Private rooms:** key generated at room creation, distributed via invite bundle.

```swift
enum RoomAccess {
    case publicContext(key: SymmetricKey)                        // key ships in binary
    case privateRoom(key: SymmetricKey, pat: String, repo: Repo) // key from invite bundle
}
```

---

## PAT pool

Users do not need GitHub accounts to participate in public channels or rooms.

The app ships a set of fine-grained PATs created by the project owner (MaroMushii),
scoped to `issues:write` on `MaroMushii/khorshid-social`. GitHub allows many PATs per
account — each has its own 5,000 req/hour rate limit bucket, so pooling 5–10 gives
ample capacity. These are:
- Hardcoded in the app binary (fallback)
- Also fetched from `raw.githubusercontent.com/.../main/pats.json` on launch (for rotation
  without a full app update)

Per write: app picks a random PAT. On HTTP 429 or 401/403, it tries the next one.

Extracted PATs are low-risk: they can write garbage (filtered by clients checking
payload structure) but cannot impersonate anyone (no private key) and cannot read
private rooms (no AES key).

---

## Private rooms

Each private room is its own private GitHub repo. Only the creator and invited members
have access. No PAT pool — the PAT is in the invite bundle.

**Room creation (creator needs a GitHub account):**
1. Create private repo `khorshid-room-<random-id>` under your account
2. Mint a fine-grained PAT with `issues:write` scoped to that repo
3. Generate AES-256 room key
4. Encode invite bundle: `{ owner, repo, pat, key, name }` → base64

**Joining (no GitHub account needed):**
1. Paste or scan invite bundle
2. App calls `GET /repos/<owner>/<repo>` to verify PAT access
3. On success: store bundle in Keychain, enter room

Same GitHub Issues API pattern as public rooms: one Issue per day, Issue comments are
encrypted blobs. All members write via the shared PAT — GitHub sees one anonymous bot
doing all the writes.

---

## Navigation structure

```
Today     — default view. Aggregated feed: top channel posts + hot room posts
            + Community Report comments. Updated every minute via feed JSON.

Channels  — browse individual mirrored Telegram channels. Read-only news feed.
            Vote and comment per post.

Rooms     — curated community spaces (core team maintains the list).
            Original posting, discussion, voting.

Private   — invite-only rooms. Encrypted. No visibility to anyone outside.
```

---

## Moderation

**Public channels and rooms:**
Community flagging is the primary mechanism. Flag payloads are plaintext and aggregator-
readable. Content reaching ≥ N unique flag `vote_id`s is excluded from the Today feed
and hidden locally by the client.

Core team can delete Issue comments directly via GitHub web UI or API. Deleted comments
stop appearing in subsequent `GET /comments` responses — all clients drop them on next
poll.

**Private rooms:**
No moderation. Room creator controls membership by controlling who has the invite bundle.
Kicking a member requires rotating the room key and re-issuing bundles to remaining members
(forward secrecy caveat: old messages with old key become unreadable after rotation).

---

## Open questions

- [ ] Flag threshold N — start with 5, needs tuning once real traffic exists
- [ ] Community Report threshold — what hot_score floor surfaces a comment to Today?
- [ ] Private room key rotation UX — how does the app communicate "you need to re-join"?
- [ ] Aggregator Claude API cost at scale — re-evaluate if cluster API gets expensive
- [ ] Re-probe Firestore accessibility periodically (see network.md) — if it becomes
      reliably accessible, it's a viable real-time enhancement but not a dependency
