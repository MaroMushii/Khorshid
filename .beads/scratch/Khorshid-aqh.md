# Khorshid-aqh — Ed25519 identity (macOS slice)

## Context

Zero-signup identity is the keystone for everything social: voting,
commenting, flagging, private-room membership. Without it, no other
write-path bead (s7m, pye, qor, 2ay) can proceed.

The bead spans macOS (Swift/CryptoKit) and Android (Dart/pointycastle).
Android is not built yet (separate bead `Khorshid-o5y` ships the skeleton).
This slice does **macOS only**. We leave the bead open and re-enter it
for the Android half once the Flutter app exists, OR split off an
`-android` bead at that time.

## Fact-check

- INFORMATIONAL drift: bead description names Keychain service
  `dev.kumamaki.Khorshid`. Actual bundle ID per `mac/project.yml` is
  `dev.MaroMushii.Khorshid`. Use the actual bundle ID.
- INFORMATIONAL drift: bead description doesn't mention `vote_id` derivation
  scheme, but `CLAUDE.md` documents `vote_id = sha256(privkey || target_id)`.
  Identity store must expose the private-key bytes to sibling code, OR
  expose a `voteId(for: targetId)` helper. Pick the helper — keeps the
  raw key bytes inside the store.
- UNVERIFIABLE: bead says "QR export for device migration" — defer to a
  follow-up bead (cleaner UX work, not blocking writes).
- No existing CryptoKit / Keychain code in `mac/Khorshid` — greenfield.
- Sandbox entitlements: app is sandboxed (`com.apple.security.app-sandbox: true`).
  Sandbox + Keychain works for *generic password* items as long as the bundle
  has a code-signing identity. Local dev signs ad-hoc (`CODE_SIGN_IDENTITY: "-"`),
  which means Keychain access works on the local machine; for distribution we
  need a Keychain Access Group entitlement. Not blocking — flag in plan.

## Files

**New** (mac/Khorshid/):
- `Models/Identity.swift` — `struct Identity: Sendable { let publicKey: Data;
  var displayName: String }`. Computed `publicKeyHex`.
- `Services/Keychain.swift` — Thin wrapper over `SecItemAdd/Copy/Delete`
  for a single generic-password item: `service` + `account` constants,
  `read/write/delete(Data) throws`. Errors via `enum KeychainError`.
- `Services/IdentityStore.swift` — `@Observable @MainActor final class
  IdentityStore`. On `start()` loads from Keychain or generates a fresh
  `Curve25519.Signing.PrivateKey`, stores 32-byte raw repr, publishes
  the `Identity`. Exposes:
  - `var identity: Identity?` (nil until `start()` finishes)
  - `func sign(_ data: Data) throws -> Data`
  - `func voteId(for targetId: String) -> String` — `sha256(rawPriv || targetId).hex`
  - `func setDisplayName(_ name: String)` — persists to `UserDefaults` under
    `identity.displayName`, mutates `identity.displayName`.
  - `func resetForTesting()` — deletes Keychain item + UserDefaults, regenerates.
    Wrapped in `#if DEBUG`.

**Edited**:
- `App/KhorshidApp.swift` — instantiate `IdentityStore`, `.environment(...)`,
  call `identityStore.start()` in `.onAppear` alongside the other two.

## Behavior

- First launch: no Keychain entry → generate `Curve25519.Signing.PrivateKey`,
  serialize as `.rawRepresentation` (32 bytes), write to Keychain. Read back
  immediately to confirm.
- Subsequent launches: read Keychain → instantiate `PrivateKey(rawRepresentation:)`.
- Display name: default `"Anonymous"`, stored in `UserDefaults`. Mutable.
- Public key surface: `Data` (32 bytes) and `publicKeyHex: String`.
- `voteId(for:)` uses `CryptoKit.SHA256` over `rawPriv || targetId.utf8`.
- Errors during keygen/load surface via a `loadError: Error?` observable
  field; UI not in scope for this bead beyond making the store available.

## Risks

- Keychain access in app-sandbox + ad-hoc signing: usually OK on dev box,
  but if a teammate later signs with a real Team ID, the Keychain item
  becomes inaccessible unless we add a Keychain Access Group entitlement.
  Note in plan; not solving here.
- Strict-concurrency: `CryptoKit` types are `Sendable` (per Apple docs).
  `SecItem*` C APIs are thread-safe; we'll call them from the main actor
  via the store, no detached threading needed at this scale (one read
  on launch, occasional writes).

## Tests / verification

No XCTest harness in the mac app. Manual smoke:
1. `cd mac && xcodegen && xcodebuild -scheme Khorshid build` — clean build,
   no strict-concurrency warnings.
2. Launch app, confirm via temporary `print()` in `IdentityStore.start()`
   that the public-key hex is non-empty and *stable across relaunches*.
3. Use `security find-generic-password -s dev.MaroMushii.Khorshid -a
   identity.ed25519` to confirm a Keychain entry exists after first run.
4. Delete that entry, relaunch — new public key appears, store recovers.

## Out of scope (follow-up beads to consider)

- QR-export of keypair for device migration → new bead.
- Settings UI for display name → new bead (or piggyback on `Khorshid-pye`).
- Android Dart implementation → re-enter `Khorshid-aqh` once `Khorshid-o5y`
  ships, or split into `Khorshid-aqh-android`.

## Task list

1. Add `Models/Identity.swift`.
2. Add `Services/Keychain.swift`.
3. Add `Services/IdentityStore.swift`.
4. Wire into `App/KhorshidApp.swift`.
5. `xcodegen`, build, manual smoke.
6. Commit, leave bead open (Android half remains).
