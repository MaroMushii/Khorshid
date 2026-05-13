# Khorshid-0h1 — Today's Highlights (client surface)

## Fact-check vs bead description

The bead's body describes the full Today's Highlights stack: aggregator + client.
Khorshid-pen (Today aggregator) closed on 2026-05-11 — the GH Action ships
`feed/<date>.json` to the export branch every minute, with hot scoring, embedding
dedup, LLM tie-breaks, media-fingerprint confirmations, and flag-threshold hiding.

So Khorshid-0h1's remaining scope = **client-side display** of that feed in the
macOS app. The mac app today only shows per-channel snapshots; there is no Today
view, no `feed/<date>.json` consumption.

**Drift:**
- INFORMATIONAL: bead says "Claude Haiku" for dedup, actual impl uses OpenRouter
  `gpt-oss-120b:free` (commits cd25f45, 8b66e96). Client-side display doesn't care.
- INFORMATIONAL: aggregator side already shipped. Khorshid-pen closed.
- INFORMATIONAL: bead's λ=0.3 / λ=0.5 formula matches `mirror/aggregate.ts`
  `hotScore()` exactly (`Math.exp(-0.3 * ageHours)`).

**Out of scope for this bead (already separate beads):**
- Khorshid-aqh — Ed25519 identity
- Khorshid-il6 — PAT pool
- Khorshid-pye — Comment system
- Khorshid-s7m — Voting system
- Khorshid-qor — Community flagging UI
- Khorshid-2xd — Community Report (encrypted room comments) elevation

So vote counts, confirmations, and (eventually) community reports are *rendered*
read-only — voting itself comes later.

## Wire format (confirmed from `mirror/feed-schema.ts` + live sample 05-12, 75 posts)

```ts
Feed { date, generated_at, posts: FeedPost[], community_reports: CommunityReport[] }
FeedPost {
  post_id,              // "<channel_username>/<telegram_post_id>"
  channel_username, channel_title,
  plain_text, body_html,
  media: MediaDTO[],    // {kind, asset_path, thumbnail_path, aspect_ratio, ...}
  posted_at, hot_score, vote_count, cluster_id,
  confirmations: [{ channel_username, channel_title, permalink }]
}
```

URL: `https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export/feed/<YYYY-MM-DD>.json`

## Plan

### New files (mac)

- `mac/Khorshid/Models/FeedPost.swift` — domain models `FeedPost`, `Confirmation`
  (Sendable structs). Skip `CommunityReport` model — not used until Khorshid-2xd.
- `mac/Khorshid/Services/FeedClient.swift` — `actor FeedClient { fetchFeed(for: Date) }`.
  Decodes feed JSON; reuses `MediaDTO`-style decoding from `MirrorClient`.
- `mac/Khorshid/Stores/FeedStore.swift` — `@Observable @MainActor` store with
  `posts`, `generatedAt`, `isLoading`, `errorMessage`. `start()` polls every 60s
  with a today→yesterday fallback (today often empty before first aggregator run).
- `mac/Khorshid/Views/Today/TodayFeedView.swift` — list view, posts sorted by
  `hot_score` desc (already sorted server-side but defensive).
- `mac/Khorshid/Views/Today/FeedPostRow.swift` — wraps existing `PostBodyView` +
  `PostMediaView`; adds channel header line, posted-at, and confirmations footer.
- `mac/Khorshid/Views/Today/ConfirmationsBadge.swift` — "Confirmed by N other
  channels" with disclosure listing channel titles.

### Files edited

- `mac/Khorshid/App/KhorshidApp.swift` — instantiate `FeedStore`, inject into env,
  call `feedStore.start()` on appear (in addition to ChannelStore).
- `mac/Khorshid/Views/RootView.swift` — sidebar gains a static "Today" row pinned
  at the top above the channel list. Selection model becomes an enum
  `Selection { case today, case channel(String) }`. Detail switches on it.
- `mac/Khorshid/Views/Feed/PostMediaView.swift` — leave unchanged; already
  consumes `[PostMedia]` and works for the feed posts too.
- `mac/Khorshid/project.yml` — only if `xcodegen` needs the new file list; the
  project pattern looks file-glob-based, so probably nothing to do.

### Selection model

Replace `selectedChannelID: Channel.ID?` (String?) with:

```swift
enum SidebarSelection: Hashable { case today; case channel(String) }
@State private var selection: SidebarSelection? = .today
```

Sidebar `List(selection:)` items emit those cases. Detail switches:
- `.today` → `TodayFeedView(store: feedStore)`
- `.channel(let id)` → existing channel detail content

### Fetch & polling

`FeedClient.fetchFeed(for: Date)` builds the YYYY-MM-DD path and `GET`s.
404 → return `nil` (treated as "no feed yet today, fall back to yesterday").
`FeedStore.refresh()`:
1. Try today. If non-nil and `posts.count > 0`, use it.
2. Else try yesterday. Show with a "Showing yesterday — today not aggregated yet"
   banner.
3. Update `posts`, `generatedAt`, errors.

Poll every 60s while window is visible (matches aggregator cadence).

### Row UI

Card layout, top-down:
- Channel header: small avatar (`photoPath` from `ChannelStore.channels` lookup
  by username) + channel title + "· posted_at relative".
- Body: `PostBodyView` (HTML).
- Media: `PostMediaView` (existing).
- Footer: vote_count badge ("⭐ 12") if > 0; confirmations badge if non-empty.

Channel avatar lookup may miss if the channel isn't in `ChannelStore.channels`
yet — render a generic icon then. No new fetch path.

### Risks

- ChannelStore and FeedStore both poll the export branch independently. Fine for
  now (small payloads, raw.githubusercontent.com is cheap). Could share a client
  later — explicitly not doing it now to avoid premature abstraction.
- Today's feed often empty at start-of-day (only past few hours of posts get
  collected and the aggregator runs every minute but needs the mirror to run
  first). The yesterday fallback prevents an empty view during this window.
- `MediaDTO` JSON shape: I haven't re-verified the feed's `media[]` includes
  `asset_path`/`thumbnail_path` vs the older `asset_url` naming — need to confirm
  on first run. Mitigation: defensive decoding with optional fields.

### Tests / verification

No XCTest harness in mac yet. Verification = run app, see Today feed populate
with yesterday's 75 posts, confirm post ordering matches hot_score desc, confirm
channel switch still works.

```
just mac-build  # or xcodebuild from CLI
open Khorshid.app
```

### Tasks (in order)

1. Add `FeedPost`, `Confirmation` models.
2. Add `FeedClient` with `fetchFeed(for:)`.
3. Add `FeedStore` (observable, polling).
4. Add `TodayFeedView`, `FeedPostRow`, `ConfirmationsBadge`.
5. Wire `FeedStore` into `KhorshidApp` env.
6. Refactor `RootView` selection to `SidebarSelection`, add Today row.
7. Local build + manual smoke test against export branch.
8. Commit (conventional, `feat(mac): today highlights feed`).

## Commit message draft

```
feat(mac): Today's Highlights feed view

Reads feed/<date>.json from the export branch (written by the aggregator
GH Action) and renders posts in hot-score order with cross-channel
confirmations. Sidebar gains a Today entry pinned above the channel list.
Falls back to yesterday's feed when today's hasn't been aggregated yet.

Refs: Khorshid-0h1.
```
