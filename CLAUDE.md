# CLAUDE.md

Project-level guidance for Claude when working in this repo. Read first.

## What this project is

**Khorshid** (Persian: "Sun") is a censorship-resistant news and discussion
platform for people living under internet blackouts. Named after the Persian
word for Sun.

The repo is three cooperating pieces:

```
mirror/          — khorshid-mirror, a Node scraper run by GitHub Actions
                   every ~5 min. Fetches Iranian news Telegram channels via
                   t.me, writes per-channel snapshots + media into the
                   `export` branch. Ported from Pigeon's mirror scraper.

mac/             — SwiftUI macOS 26 client (Swift 6, strict concurrency).
                   Skeleton built. Reads news feed from export branch.

android/         — Flutter Android app. Not yet built.
```

There is also a companion repo (not in this directory):

```
MaroMushii/khorshid-social  — GitHub Issues used as the social layer.
                               One Issue per context (channel/room) per day.
                               Issue comments = encrypted posts, plaintext votes/flags.
```

### Data flow

```
Telegram channels
    ↓  (mirror scraper, GH Actions ~5 min)
export branch  →  raw.githubusercontent.com  (news read path)
    ↓  (Today aggregator, GH Action every minute — not yet built)
export branch/feed/{day}.json  (ranked by importance votes)

Users vote / comment
    ↓  (PAT pool → GitHub Issues API — near real-time)
MaroMushii/khorshid-social Issues  (social read/write path)
```

### Why GitHub only

GitHub's REST API and `raw.githubusercontent.com` CDN are reliably accessible
from Iran. Telegram's `t.me` is not — the mirror bridges that gap. Firestore
(googleapis.com) appeared reachable in a May 2026 probe but is likely sanctioned
as a Firebase product; Khorshid does not depend on it. See `docs/network.md`.

GitHub Issues API is immediately consistent (POST a comment, GET it back within
milliseconds), which gives near-real-time social behavior via adaptive polling —
the same pattern used in a private sister project.

## Hard rules — do not violate

- **Never request `t.me` directly from client apps.** Iran's DPI
  fingerprints the SNI. Always read from the mirror (export branch) or
  the GT-host-rewrite proxy inherited from Pigeon.
- **The mirror is write-only from GH Actions.** Client apps (mac, android)
  must never write to the GitHub export branch. Only the Actions workflow
  does, using the auto-provisioned `GITHUB_TOKEN`.
- **Mirror snapshots store canonical (un-rewritten) URLs.** Apps apply
  their own URL rewriting after decode.
- **All user content is AES-GCM encrypted.** Public rooms use a hardcoded
  key shipped in the app binary. "Public" means anyone with the app can
  decrypt — not anyone on the internet.
- **Identity is a keypair, not an account.** Generated on first launch,
  never leaves the device. No GitHub account, no email, no signup.

## Architecture cheat sheet

### Export branch read path (news)

```
raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export/
  index.json                          — channel discovery
  channels/<u>/snapshot.json          — posts for channel <u>
  channels/<u>/media/<hash>.<ext>     — mirrored media
  health.json                         — last sweep status
  feed/<YYYY-MM-DD>.json              — Today ranked feed (written by aggregator)
```

### Social layer (khorshid-social, not yet built)

All social content lives in `MaroMushii/khorshid-social` GitHub Issues.

Issue naming: `channel-<slug>-<YYYY-MM-DD>` / `room-<slug>-<YYYY-MM-DD>`

Issue comment types:
```
Encrypted blob  →  { v: 1, n: "<nonce b64>", c: "<AES-256-GCM ciphertext b64>" }
                   Decrypts to: { type: "post"|"comment", body, post_id?, reply_to?, sent_at }

Plaintext vote  →  { type: "vote", target_id, signal: "up"|"important",
                     vote_id: sha256(privkey || target_id), sent_at }

Plaintext flag  →  { type: "flag", target_id,
                     vote_id: sha256(privkey || target_id), sent_at }
```

Write path (public rooms):
```
User action → AES-GCM encrypt (comments only) → pick random PAT from pool
→ POST /repos/MaroMushii/khorshid-social/issues/:id/comments
```

Read path:
```
GET /repos/.../issues/:id/comments?since=<last_seen>  (poll every 10–60s)
```

## Build & dev

```sh
just                    # list recipes
just mirror-check       # typecheck the scraper (offline)
just mirror-run         # run scraper locally (needs t.me reachable)
just dry-run <channel>  # parse a single live channel
just update-mirror      # manually trigger GH Actions mirror run
```

Install deps:
```sh
cd mirror && pnpm install
```

## Conventions

### TypeScript (`mirror/`, `cf-dispatcher/`)

- `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax: false`.
- ES modules; `.js` extension on internal imports (TS resolves them).
- Snake_case for JSON wire fields. Schema lives in `mirror/schema.ts`.

### Swift (`mac/`)

- Swift 6, strict concurrency complete. macOS 26 deployment target.
- `@Observable` + `@State` over `ObservableObject` + `@StateObject`.
- `@MainActor` on stores. Bundle ID prefix: `dev.MaroMushii`.
- Liquid Glass UI: window background glass, cards glass. Message bubbles solid.

### Flutter (`android/`) — not yet built

- Dart 3+, null safety enforced.
- Riverpod for state management.

### Git

- Branch naming: `type/description` (e.g. `feat/mirror-votes`, `fix/parser`).
- Conventional commits, scoped: `feat(mirror):`, `feat(mac):`, `feat(social):`,
  `feat(android):`, `fix(mirror):`, `chore(ci):`, `docs(design):`.
- Co-author trailer: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.
- Never push to `main` without explicit user confirmation.

### Tooling

- `pnpm`, never npm/yarn.
- Fish shell — Fish-compatible syntax in shell snippets.
- `trash` for deletes, never `rm`.
- `gh` CLI for GitHub API operations, not WebFetch.
- `just` as the task runner.

## Pigeon connection

Khorshid shares conventions and some infrastructure with
[Pigeon](https://github.com/MaroMushii/Pigeon) (the mirror pattern, the
GT-proxy technique, the export branch layout). Sister project by the same developer.

Do not share code via Swift packages or symlinks. Copy-paste with
attribution when needed. The threat models and scope are different enough
that coupling would be a mistake.

## What's not yet built

In priority order (see `bd ready` for the full tracked backlog):

1. **GitHub Issues social schema** (`Khorshid-nku`) — wire format spec as code.
2. **khorshid-social repo + daily Issue provisioning** (`Khorshid-x2x`) — create
   the companion repo and the GH Action that ensures today's Issues exist.
3. **Today aggregator GH Action** (`Khorshid-pen`) — LLM dedup, hot scoring,
   writes `feed/{day}.json` to export branch.
4. **Ed25519 identity** (`Khorshid-aqh`) — keypair gen + Keychain storage in mac app.
5. **PAT pool** (`Khorshid-il6`) — project-owner PATs for anonymous public writes.
6. **Comment system** (`Khorshid-pye`) — read/write via Issues API with adaptive polling.
7. **Voting system** (`Khorshid-s7m`) — plaintext votes with commitment hash.
8. **Community flagging** (`Khorshid-qor`) — threshold-based local content hiding.
9. **Community Report** (`Khorshid-2xd`) — hot comments elevated into Today feed.
10. **Private rooms** (`Khorshid-2ay`) — invite bundle model, one private repo per room.
11. **Android app** (`Khorshid-o5y`) — Flutter, after macOS is working end-to-end.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
