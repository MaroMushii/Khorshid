# Khorshid-50o: macOS App Skeleton — Scratch Plan

## Bead

Bootstrap the SwiftUI macOS 26 app under `mac/`. Read-only news feed from
the export branch. No social layer. No GT proxy.

## Fact-check

### BLOCKING
None.

### INFORMATIONAL
- Export branch (`MaroMushii/Khorshid#export`) exists but is currently empty.
  Mirror hasn't been triggered since the initial repo scaffold. MirrorClient
  will receive 404 on `index.json` until the mirror runs; surfaced as a clean
  error / empty state in ChannelStore.
- Repo is private. `raw.githubusercontent.com` only works credential-free for
  public repos. The repo must be made public before production use. Not a
  blocker for the skeleton.
- GT proxy (PinnedHTTPSClient, PinnedURLProtocol) excluded. CLAUDE.md
  confirms `raw.githubusercontent.com` survives Iranian whitelisting; user
  confirmed exclusion.

## Files to create

```
mac/
  project.yml
  Khorshid/
    App/
      KhorshidApp.swift
    Models/
      Channel.swift
      Post.swift
    Services/
      MirrorClient.swift
    Stores/
      ChannelStore.swift
    Views/
      RootView.swift
      Sidebar/
        ChannelRow.swift
      Feed/
        PostRow.swift
    Resources/
      Assets.xcassets/
        AppIcon.appiconset/Contents.json
        Contents.json
      Info.plist
      Khorshid.entitlements
```

## Key references

- Schema: `mirror/schema.ts` — IndexDoc, IndexEntry, Snapshot, PostDTO,
  ReactionDTO, MediaDTO
- ISO 8601 dual-formatter pattern:
  `/Users/mehdi/Work/Pigeon/mac/Pigeon/Services/MirrorHealth.swift` lines 61-72
- project.yml template:
  `/Users/mehdi/Work/Pigeon/mac/project.yml`
- Export base URL:
  `https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export`

## Design decisions

### project.yml
- bundleIdPrefix: `dev.MaroMushii`
- deploymentTarget macOS: `26.0`
- SWIFT_VERSION: `6.0`, SWIFT_STRICT_CONCURRENCY: `complete`
- No external packages (no SwiftSoup, Nuke, Sparkle)
- Entitlements: app-sandbox + network.client

### Domain models
Channel (from IndexEntry):
  - id: String (username)
  - title: String
  - lastFetchedAt: Date
  - postCount: Int

Post (from PostDTO):
  - id: String
  - plainText: String
  - postedAt: Date?
  - viewsLabel: String?
  - reactions: [Reaction]
  - permalink: String

Reaction (from ReactionDTO):
  - emoji: String
  - count: String

### MirrorClient
- `actor MirrorClient` — Swift 6 actor isolation
- `URLSession.shared` — plain HTTPS, no custom protocol registration needed
- `fetchIndex() async throws -> [Channel]` — GET /index.json
- `fetchPosts(snapshotPath:) async throws -> [Post]` — GET /<snapshotPath>
- JSON: manual `Decodable` with snake_case CodingKeys
- ISO 8601 parsing: fractional seconds → plain fallback (same as Pigeon)

### ChannelStore
- `@MainActor @Observable final class ChannelStore`
- `channels: [Channel]`, `postsByChannel: [String: [Post]]`
- `isLoading: Bool`, `errorMessage: String?`
- `start()` — kicks off Task loop, polls every 5 min
- `refresh() async` — fetches index, then all snapshots concurrently via
  `withThrowingTaskGroup`
- `selectedChannelUsername: String?` — drives detail pane

### KhorshidApp
- `@main struct KhorshidApp: App`
- `@State private var store = ChannelStore()`
- Passes store via `.environment(store)`
- Calls `store.start()` in `.onAppear` on `WindowGroup` content
  (safe: SwiftUI onAppear is main-thread → @MainActor compatible)

### Views
- `RootView`: `NavigationSplitView` — sidebar channel list, detail post feed
- `ChannelRow`: title + post count badge
- `PostRow`: plain text (3-line limit), formatted timestamp, views label,
  reactions as emoji+count pairs

## Risks

1. Empty export branch → empty state "No channels yet" until mirror runs
2. Private repo → 404 on raw.githubusercontent.com fetches until made public
3. Strict concurrency — all async boundaries must be actor-safe; no `@Sendable`
   closure warnings

## Verification

1. `cd mac && xcodegen generate` — no errors
2. Project builds in Xcode with 0 errors, 0 strict-concurrency warnings
3. App launches and shows empty-state view
4. Once mirror runs (trigger via `just update-mirror`), next poll shows channels

## Branch

`feat/mac-app-skeleton`

## Status

`in_progress` — claimed 2026-05-10
