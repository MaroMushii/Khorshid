# Scratch Plan: Khorshid-qor — Community flagging

## Fact-check

- `FlagPayload` — confirmed in `mac/Khorshid/Models/SocialPayload.swift` (line 71). Fields: `type: String`, `target_id: String`, `vote_id: String`, `sent_at: Int`. No changes needed.
- `SocialStore` — no flag state exists yet. Poll loop handles `VotePayload` (type="vote"); `FlagPayload` (type="flag") falls through silently.
- `vote()` / `applyVote()` / `undoVote()` / `hasVoted()` — all confirmed in `SocialStore.swift`. Exact template.
- `seenVoteIds: [String: Set<String>]` — confirmed. Same structure for flag dedup.
- `Comment` model — no `isHidden` field. Not adding one — hiding via `SocialStore.isHidden(targetId:)`.
- No partial work. No blockers.

## Architecture

Flags mirror votes exactly — plaintext Issue comments, `vote_id` dedup, optimistic write with undo on failure. One difference: a threshold (N=5) triggers client-local hiding. Everything lives in `SocialStore` only.

## Files

### Modify only: `mac/Khorshid/Stores/SocialStore.swift`

New state, flag()/hasFlagged()/isHidden() methods, applyFlag()/undoFlag() helpers, subscribe/unsubscribe cleanup, poll processing for type="flag".

## Risks

- Double-flag guarded by `seenFlagIds` check in `flag()`.
- Cross-session state rebuilds from first full poll — no persistence needed.
- `flagThreshold = 5` static constant, easy to tune.
- No comment UI yet — `isHidden()` ready for future view beads.

## Task list
1. Add `flagTallies`, `seenFlagIds`, `flagThreshold` state
2. Add `flag()`, `hasFlagged()`, `isHidden()` methods
3. Add `applyFlag()`, `undoFlag()` private helpers
4. Wire cleanup into `subscribe()` / `unsubscribe()`
5. Add poll processing for type="flag"
6. Build check
