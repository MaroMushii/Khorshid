# Scratch Plan: Khorshid-ro9 — Sign writes + verify reads

## Fact-check

- `IdentityStore.sign(_:)` — confirmed at `mac/Khorshid/Services/IdentityStore.swift`. Calls `privateKey.signature(for:)` via `Curve25519.Signing.PrivateKey`. Throws `IdentityError.notReady` if key not loaded.
- `Identity.publicKeyHex` — confirmed in `mac/Khorshid/Models/Identity.swift`. Hex string computed from `publicKey: Data`.
- `SocialPayloadWrapper` — confirmed in `mac/Khorshid/Models/SocialPayload.swift`. Fields: `v: Int`, `n: String`, `c: String`. No `pub`/`sig` yet.
- `SocialCrypto.encrypt()` — returns `SocialPayloadWrapper(v: 1, n:, c:)`. No identity param.
- `SocialCrypto.decrypt()` — guards on `wrapper.v == 1` only. No sig check.
- `SocialStore.send()` — calls `SocialCrypto.encrypt(payload, key: key)` inside a MainActor Task. Has `identityStore: IdentityStore?` available.
- `Khorshid-aqh` blocker: macOS slice merged to main. Bead stays open for Android (Khorshid-o5y). Not a real blocker here.
- No partial work — `Khorshid-ro9` has zero linked commits.

## Architecture

**Signing bytes:** `nonceBytes + combinedBytes` where `combined = ciphertext + tag` — exactly what's stored in `c`. Covers the full payload.

**Wire format:** v:1 (legacy, no sig) stays decodable. v:2 adds `pub` + `sig`.
```
v:1 → { v:1, n, c }                               — decrypt without sig check
v:2 → { v:2, n, c, pub: <hex pubkey>, sig: <b64> } — verify sig before decrypt; drop if invalid
```

**No closure injection into SocialCrypto.** Signing stays on the MainActor call site in `SocialStore.send()`. Two new static helpers on `SocialCrypto` handle the split cleanly:
- `signatureMessage(for:) -> Data?` — reconstructs sign bytes from a wrapper (base64-decode `n` + `c`, concatenate)
- `applySignature(_:publicKeyHex:to:) -> SocialPayloadWrapper` — upgrades v:1 to v:2

`vote()` is untouched — plaintext votes use `vote_id` commitment, no signature.

## Files

### Modify: `mac/Khorshid/Models/SocialPayload.swift`
Add optional fields to `SocialPayloadWrapper`:
```swift
struct SocialPayloadWrapper: Codable {
    let v: Int
    let n: String
    let c: String
    let pub: String?   // pubkey hex — v:2+
    let sig: String?   // base64 Ed25519 sig over nonceBytes||combinedBytes — v:2+
}
```
Codable synthesis handles optional fields — v:1 decodes cleanly with nil for both.

### Modify: `mac/Khorshid/Services/SocialCrypto.swift`
1. Add `.invalidSignature` to `CryptoError`
2. Add private `dataFromHex(_:) -> Data?` helper
3. Add `signatureMessage(for:) -> Data?`
4. Add `applySignature(_:publicKeyHex:to:) -> SocialPayloadWrapper`
5. Update `decrypt()` — v:2 path verifies sig; support v:1 and v:2

### Modify: `mac/Khorshid/Stores/SocialStore.swift`
1. `send()` guard: add `let identity = identityStore`
2. Inside Task, after `encrypt()`, sign and upgrade to v:2

## Risks

- **v:1 legacy content**: Still in the Issues. Handled — v:1 decrypt path unchanged.
- **`identity.identity` nil at send time**: `IdentityStore.start()` runs synchronously on launch; key is loaded before UI is interactive. Guard throws `.notReady` if not ready — surfaces as `self.error`.
- **`Curve25519.Signing.PublicKey` init can throw**: Wrapped in the v:2 guard chain — failure throws `.invalidSignature`, silently dropped by `try?` in poll.
- **Invalid sigs silently dropped**: Intentional per bead spec. The `try?` in `SocialStore.poll()` already handles any decrypt error.

## Task list
1. Modify `SocialPayload.swift` — add `pub?`/`sig?`
2. Modify `SocialCrypto.swift` — helpers + updated `decrypt()`
3. Modify `SocialStore.swift` — sign on write path
4. Build check
