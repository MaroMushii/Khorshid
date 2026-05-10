# CLAUDE.md

Project-level guidance for Claude when working in this repo. Read first.

## What this project is

**Khorshid** (Persian: "Sun") is a censorship-resistant news and discussion
platform for people living under internet blackouts. Named after the Persian
word for Sun.

The repo is four cooperating pieces:

```
mirror/          — khorshid-mirror, a Node scraper run by GitHub Actions
                   every ~5 min. Fetches Iranian news Telegram channels via
                   t.me, writes per-channel snapshots + media into the
                   `export` branch. Ported from Pigeon's mirror scraper.

cf-dispatcher/   — Cloudflare Worker that fires every 5 min on a CF cron
                   trigger and POSTs to GitHub's workflow_dispatch to kick
                   mirror.yml. Same pattern as Pigeon's dispatcher.

mac/             — SwiftUI macOS 26 client (Swift 6, strict concurrency).
                   Not yet built.

android/         — Flutter Android app.
                   Not yet built.
```

### Data flow

```
Telegram channels
    ↓  (mirror scraper, GH Actions ~5 min)
GitHub export branch  →  raw.githubusercontent.com  (news read path)

Users vote / comment
    ↓
Firestore  (primary real-time: comments + votes)
    ↓  (aggregator GH Action, every minute — not yet built)
GitHub feed/{day}.json  (sorted by votes — fallback read path)
```

### Why GitHub + Firestore

GitHub's `raw.githubusercontent.com` CDN and Google's `googleapis.com`
(Firestore) both survive Iranian internet whitelisting. Telegram's `t.me`
does not — the mirror bridges that gap by scraping from a GitHub Actions
runner (outside Iran) and pushing results to the export branch.

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
```

### Social layer (not yet built)

Comments and votes go to Firestore. Write path:
```
User action → sign with Ed25519 keypair → AES-GCM encrypt → pick random
PAT from pool → write to Firestore (real-time) + GitHub (persistent)
```

## Build & dev

```sh
just                    # list recipes
just mirror-check       # typecheck the scraper (offline)
just mirror-run         # run scraper locally (needs t.me reachable)
just dry-run <channel>  # parse a single live channel
just update-mirror      # manually trigger GH Actions mirror run
just deploy-dispatcher  # deploy CF Worker
just set-dispatcher-token  # set GITHUB_TOKEN secret on CF Worker
```

Install deps:
```sh
cd mirror && pnpm install
cd cf-dispatcher && pnpm install
```

## Conventions

### TypeScript (`mirror/`, `cf-dispatcher/`)

- `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax: false`.
- ES modules; `.js` extension on internal imports (TS resolves them).
- Snake_case for JSON wire fields. Schema lives in `mirror/schema.ts`.

### Swift (`mac/`) — not yet built

- Swift 6, strict concurrency complete. macOS 26 deployment target.
- `@Observable` + `@State` over `ObservableObject` + `@StateObject`.
- `@MainActor` on stores. Bundle ID prefix: `dev.MaroMushii`.
- Liquid Glass UI: window background glass, cards glass. Message bubbles solid.

### Flutter (`android/`) — not yet built

- Dart 3+, null safety enforced.
- Riverpod for state management.

### Git

- Branch naming: `type/description` (e.g. `feat/mirror-votes`, `fix/parser`).
- Conventional commits, scoped: `feat(mirror):`, `feat(mac):`,
  `feat(android):`, `fix(mirror):`, `chore(ci):`.
- Co-author trailer: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.
- Never push to `main` without explicit user confirmation.

### Tooling

- `pnpm`, never npm/yarn.
- Fish shell — Fish-compatible syntax in shell snippets.
- `trash` for deletes, never `rm`.
- `gh` CLI for GitHub API operations, not WebFetch.
- `just` as the task runner.

## Pigeon / Khorshid connection

Khorshid shares conventions and some infrastructure with
[Pigeon](https://github.com/MaroMushii/Pigeon) (the mirror pattern, the
GT-proxy technique, the export branch layout) and
[Khorshid](https://github.com/MaroMushii/Khorshid) (AES-GCM over GitHub, keypair
identity, invite bundles). Both are sister projects by the same developer.

Do not share code via Swift packages or symlinks. Copy-paste with
attribution when needed. The threat models and scope are different enough
that coupling would be a mistake.

## What's not yet built

In priority order:

1. **macOS app skeleton** — news feed reading from the export branch.
2. **Android Flutter app skeleton** — same news feed.
3. **Firestore social layer** — comments + upvotes per post.
4. **Aggregator GitHub Action** — sorts posts by vote count, writes
   `feed/{day}.json` to export branch.
5. **PAT pool** — volunteered tokens for anonymous writes.
6. **Private rooms** — invite-only encrypted discussion (post-MVP).


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
