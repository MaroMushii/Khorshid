# Architecture

## The three-layer model

The network is designed in three independent layers. Each layer works without the ones
above it. Higher layers are faster, not required.

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3 — External internet (Firestore, GitHub, GitLab, ...)   │
│  When: global internet is partially accessible                   │
│  Speed: near real-time (Firestore) to minutes (GitHub polling)  │
│  Reach: anyone with the app, anywhere                           │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2 — Inside-Iran nodes                                    │
│  When: NIN is up, even if global internet is fully cut          │
│  Speed: real-time (WebSocket, same country)                     │
│  Reach: all NIN users                                           │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1 — Local P2P gossip (WiFi Direct, mDNS, Bluetooth)      │
│  When: always. No server, no internet, no NIN required          │
│  Speed: seconds when in range, hours via store-carry-forward    │
│  Reach: nearby devices, propagates as people move               │
└─────────────────────────────────────────────────────────────────┘
```

Layer 1 is the foundation. Layers 2 and 3 are amplifiers. If everything above Layer 1
gets shut down, the network keeps working — just slower.

---

## Layer 1: Local P2P gossip

Every device is a node. Every device stores every message it has received.
When two devices come within range, they sync.

```
Device A: "newest message I have is ID abc123, timestamp 14:32"
Device B: "I have 12 messages newer than that"
Device A: "send them"
← both devices now have the complete set →
```

No server involved. No internet required. Messages propagate as people move through
the city — a university WiFi island syncs to a mobile user, who walks across town and
syncs to a market WiFi island. City-wide propagation without any infrastructure.

**Transports for Layer 1:**

| Transport       | Range    | Platforms              | Notes                              |
|-----------------|----------|------------------------|------------------------------------|
| WiFi (mDNS)     | LAN      | All                    | Needs a router. Auto-discovery.    |
| WiFi Direct     | ~200m    | Android, Windows       | No router. Two devices connect directly. |
| Multipeer (MCF) | ~70m     | iOS + macOS only       | Apple proprietary. Works well within Apple ecosystem. |
| Bluetooth       | ~10m     | All                    | Slow (~2 Mbps) but universal fallback. |

**Gossip protocol requirements:**
- Each device has a local append-only message store (SQLite, encrypted at rest)
- On connection: exchange newest-seen message ID per room, transfer delta
- Messages are deduplicated by content-addressed ID (sha256)
- No trust required: all messages are verified by signature before storing

---

## Layer 2: Inside-Iran nodes

Nodes run inside Iran on the NIN. Accessible to every Iranian without touching the
external whitelist. No dedicated server purchase required.

### Two kinds of nodes — very different risk profiles

**Phone relay nodes (preferred)**
The Khorshid app itself runs in relay mode on a phone. No server bought, no hosting
provider involved, no paper trail.

```
Consumer mode (always):    reads and writes messages, syncs outward
Relay mode (opt-in):       also accepts inbound connections from local network,
                           stores messages on behalf of nearby devices,
                           gossips with other known nodes
```

Relay mode activates only when on WiFi + charging. A foreground notification tells the
user it is active. Battery and data are not consumed unexpectedly.

**Volunteer machine nodes (higher risk, higher value)**
A personal computer, Raspberry Pi, or old laptop running the node binary on a home or
office network. Not a purchased VPS — hardware the person already owns.

```
khorshid-node (single binary, ~10MB, Go):
  ├── serves a real-looking cover website on port 443
  ├── accepts encrypted blobs via token-gated endpoints
  ├── maintains WebSocket connections for real-time push
  ├── stores messages: memory + append-only file (no database server)
  ├── gossips with other known nodes on message arrival
  └── logs nothing to disk by default
```

The cover service design:

```
GET  /                  →  real-looking cover website (shop, blog, portfolio)
GET  /about             →  more cover content
POST /api/<token>/sync  →  Khorshid relay endpoint (token-gated)
WS   /live/<token>      →  WebSocket for real-time push (token-gated)
```

Without the token, every request returns the cover site. A scanner sees a small Iranian
website. WebSocket on port 443 is completely normal — every Iranian e-commerce site uses
it for live notifications. Payload is AES-GCM ciphertext wrapped in JSON — identical to
any other HTTPS API traffic.

### The NAT reality

A phone on cellular sits behind Carrier-Grade NAT. Other NIN devices cannot connect to
it directly — it can only make outbound connections.

```
✓ Works:   Cellular phone → connects out → WiFi relay node (routable NIN IP)
✗ Broken:  Cellular phone → tries to connect in → another cellular phone
```

This means phone relay nodes are effective within a WiFi island (mDNS discovery,
no NAT) and via WiFi Direct (no router, ~200m range). They cannot serve as real-time
relays for other cellular devices across the NIN. For that, a machine with a stable
NIN-accessible IP is required.

### Store-carry-forward: phones as message carriers

The NAT limitation stops mattering once you think about physical mobility.

```
Home WiFi:    phone syncs with home relay node, picks up overnight messages
Commute:      phone carries messages on cellular
University:   phone joins campus WiFi, syncs with campus relay node,
              delivers what it was carrying, picks up campus messages
Street:       WiFi Direct sync with a passing phone — bidirectional in ~10s
Coffee shop:  entire table syncs via mDNS when all join the same WiFi
```

Messages travel at the speed of people moving through the city. For a crisis news board,
30–60 minutes of city-wide propagation is acceptable. For real-time chat, it is not.

### The human risk

Running a node — even on personal hardware — carries real risk in Iran. People have been
arrested for running VPN infrastructure. This is not theoretical.

Risk by node type:
- **Phone relay:** lowest risk. It is an app, not a server. Dynamic cellular IP. Genuine
  deniability. Cannot be identified as "running a server" without device inspection.
- **Home machine:** medium risk. ISP sees unusual inbound traffic volume. Cover website
  provides deniability but traffic pattern may not match "small website."
- **VPS from Iranian hosting provider:** highest risk. Provider has name, national ID,
  payment info. One government request and it is over. Avoid.

The network is designed so that nodes are optional amplifiers — it works without them.
No one should run a node unless they understand the risk and choose to accept it.

### Node discovery

Node IPs are never published in a public registry. They propagate through the gossip
network itself — nodes announce their presence as signed messages, other nodes and
clients add them to their known list. The app ships with a small number of hardcoded
seed node IPs maintained by the core team.

---

## Layer 3: External internet transports

Ordered by preference. The app probes silently and uses the first working one.

| Priority | Transport        | Why                                              | Status (2026-05-09)     |
|----------|------------------|--------------------------------------------------|-------------------------|
| 1        | Firestore        | Real-time push, no polling, proper database      | Accessible (googleapis) |
| 2        | GitHub API + git | Persistent, reliable, full git protocol works    | Fully accessible        |
| 3        | GitLab git       | Same git protocol, different domain              | git protocol accessible |
| 4        | Google Sheets    | Emergency fallback, googleapis accessible        | Accessible              |
| 5        | DNS tunneling    | Nuclear fallback. ~1–3 KB/s. Needs 8.8.8.8 open | Unknown                 |

Firebase Realtime DB (firebaseio.com) is specifically blocked. Use Firestore instead.

---

## Message format

Every message is a self-contained blob. Transport-independent.

```json
{
  "id":        "<sha256 of payload>",
  "sender":    "<ed25519 public key, base64>",
  "signature": "<ed25519 signature of payload, base64>",
  "payload":   "<AES-256-GCM ciphertext, base64>",
  "nonce":     "<12-byte GCM nonce, base64>",
  "chunks":    { "index": 0, "total": 1 },
  "sent_at":   "<unix timestamp ms>"
}
```

Plaintext inside payload (after decryption), polymorphic by type:

```json
{ "type": "text",     "body": "...", "room": "news", "day": "2026-05-09", "reply_to": null }
{ "type": "vote_up",  "target_id": "<message id>" }
{ "type": "vote_down","target_id": "<message id>" }
{ "type": "important","target_id": "<message id>" }
```

The `chunks` field exists from day one for DNS tunneling compatibility (max 63 bytes per
DNS label). Even when not chunking, index=0, total=1.

---

## Identity

- Generated on first launch: Ed25519 keypair stored in device secure storage / keychain.
- Public key = user identity. Display name is stored locally alongside it.
- No server-side registration. No GitHub account. No email.
- Backup: export keypair as QR code to restore on new device.

---

## Encryption

All rooms use AES-256-GCM. There are no unencrypted rooms.

**Public rooms:** Key is hardcoded per room in the app binary.
- "Public" = anyone with the app can decrypt.
- GitHub and anyone who accesses storage sees ciphertext.
- Keys are rotated via app update if compromised.

**Private rooms:** Key generated fresh at room creation, shared via invite bundle.
- Bundle: `{ repo, pat, key, name }` → base64 → QR code
- Shared via QR scan, Bluetooth (one-time pairing), or paste
- After joining, all communication through GitHub/Firestore. Bluetooth not used again.

```swift
enum RoomAccess {
    case publicRoom(key: SymmetricKey)           // key ships in binary
    case privateRoom(key: SymmetricKey, pat: String) // key from invite bundle
}
```

---

## Write path (how messages reach the network)

Users do not need GitHub accounts.

The app ships with a **PAT pool** — a set of GitHub tokens donated by volunteers, stored
in the binary or fetched from a well-known location in the main repo.

```
User writes message
  → sign with local private key
  → encrypt with room key
  → app picks a random PAT from pool
  → write to Firestore (real-time) AND GitHub (persistent)
```

PATs only allow writing to public repos. If extracted from binary, an attacker can:
- Write unsigned garbage (filtered by aggregator)
- Not impersonate anyone (signature check fails)
- Not read private rooms (no AES key)

PATs are rotated by app update or by a self-updating credential file in the repo.

---

## Read path

**Firestore (primary):** Real-time listener. New messages arrive in milliseconds.
No polling. App subscribes to room's Firestore collection.

**GitHub (fallback):** Clients fetch from `raw.githubusercontent.com` — CDN-backed,
no auth required, high rate limits. A GitHub Actions job runs every minute, reads all
user commits, scores by votes, writes sorted `feed/{day}.json` to repo.

```
raw.githubusercontent.com/{org}/{repo}/main/feed/2026-05-09.json
```

One HTTP GET = all messages for the day, sorted by importance. No API rate limit applies.

---

## Relay architecture

Relay operators are volunteers (diaspora, people with VPN, anyone outside Iran) who
bridge messages between transports when one gets blocked.

**What a relay does:**
```
every 60 seconds:
  for each transport it can reach:
    fetch messages since last run
  for each new message:
    push to all other reachable transports
```

Messages are content-addressed (sha256 ID). Publishing the same message twice is a
no-op — clients deduplicate automatically.

**How to become a relay (anonymous):**
1. Create a throwaway GitHub account (throwaway email, no real identity)
2. Fork the relay repo
3. Add transport credentials as GitHub repo secrets
4. Enable GitHub Actions (default on forks)
5. Done. Relay runs on GitHub's machines. Operator IP never involved.

**How the app discovers relays:**
- Layer 1: hardcoded seed relays in binary (5-10, maintained by core team)
- Layer 2: registry file in relay repo — community PRs to add new relays
- Layer 3: relays announce themselves as signed messages; other relays pick them up

**Trust model:** Relays are untrusted. Messages are signed. A malicious relay can:
- Copy messages faithfully (good)
- Not copy messages (useless)
- Inject unsigned garbage (filtered by clients)
It cannot forge identities or read private room content.

---

## Room structure

Each room is a Firestore collection + a GitHub repo (or branch).

**Public rooms (pre-defined):**
- `khorshid-news` — Today's News
- `khorshid-politics` — Politics
- `khorshid-tech` — Tech
- `khorshid-random` — Random

**Private rooms:** each is a separate private GitHub repo. Room creator holds the PAT.

**Daily structure:** messages have a `day` field. The UI groups by day. Each day has:
- "Highlights" section: top-N messages by importance votes
- "All messages" section: chronological scroll below

---

## Open questions

**Platform:**
- [ ] Cross-platform framework: Flutter vs Kotlin Multiplatform vs Tauri
- [ ] Android-first confirmed. What's the second platform?

**Layer 3 (external):**
- [ ] Firestore anonymous auth — what does the app need to ship? (securetoken.googleapis.com reachable?)
- [ ] DNS tunneling: spec out the chunking format and nameserver setup
- [ ] GitHub Actions relay: 1-minute minimum interval — acceptable for GitHub fallback path?
- [ ] Private room resilience: if creator's GitHub account deleted, room dies. Fix?

**Layer 2 (inside-Iran nodes):**
- [ ] Phone relay: Android foreground service lifecycle — how to survive aggressive battery
      optimization on Iranian ROM variants (Xiaomi, Samsung OneUI)?
- [ ] Cover website content — generic enough to not raise suspicion across all nodes?
- [ ] Node binary language confirmed as Go (single static binary, fast, minimal runtime).
- [ ] Minimum viable node: benchmark RAM/CPU for ~200 concurrent WebSocket connections.
- [ ] How do nodes authenticate to each other? (prevent fake nodes joining the mesh)
- [ ] What is the threshold for relay mode? WiFi + charging confirmed. Anything else?

**Layer 1 (local P2P):**
- [ ] Gossip protocol: build on SSB's existing protocol or design a simpler custom one?
- [ ] iOS ↔ Android sync: only path is same-WiFi mDNS. Is this acceptable?
- [ ] Store-carry-forward: how long does a device hold messages it hasn't delivered?
- [ ] What's the maximum local message store size before pruning old days?

**Moderation:**
- [ ] Who removes spam/disinformation from public rooms? No good answer yet.
- [ ] Can moderation be decentralized? (community flagging → threshold hides message locally)

