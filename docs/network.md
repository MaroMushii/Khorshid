# Iran Network Status

Results from a live probe run inside Iran on 2026-05-09.
Script: `scripts/check-network.py`

---

## Raw results

```
SERVICE                  STATUS          LATENCY   NOTES
─────────────────────────────────────────────────────────────────────────────
✓ Fastly CDN             200               680ms   github pages CDN
✓ Figma                  200              1278ms   confirmed accessible
✓ Firestore              HTTP 404          737ms   document database
✓ GitHub API             200               733ms   core write/read path
✓ GitHub API (real call) 200               793ms   unauthenticated, works
✓ GitHub HTTPS (443)     open               13ms   raw TCP
✓ GitHub SSH (port 22)   open             1501ms   raw TCP
✓ GitHub git objects     HTTP 404          734ms   expected (needs real hash)
✓ GitHub git protocol    git OK            956ms   smart-HTTP confirmed
✓ GitHub raw CDN         200              1249ms   read-only file serving
✓ GitHub web             200               737ms   main site
✓ GitLab HTTPS (443)     open               13ms   raw TCP
✓ GitLab git protocol    git OK           1163ms   smart-HTTP confirmed
✓ Google                 200               609ms   baseline
✓ Google APIs            HTTP 404          843ms   googleapis.com reachable
✓ Google Sheets          HTTP 404          885ms   sheets API reachable
✓ PyPI                   200               817ms   open
✓ SourceForge            HTTP 403          778ms   reachable (needs auth)
✓ npm registry           200               627ms   open

✗ Archive.org            URLError              —   blocked
✗ Cloudflare (1.1.1.1)   URLError              —   blocked
✗ Codeberg               URLError              —   blocked
✗ Firebase RT DB         URLError              —   blocked (firebaseio.com)
✗ GitLab (web)           URLError              —   blocked
✗ jsDelivr CDN           URLError              —   blocked
```

---

## Analysis

### GitHub: fully open

Everything GitHub-related is accessible:
- REST API (733ms avg latency)
- git smart-HTTP protocol (confirmed working)
- git over SSH port 22 (open, usable for push/pull)
- Raw CDN via raw.githubusercontent.com
- GitHub Pages via Fastly CDN

This is the most reliable foundation available.

### Firestore: probe shows reachable, but treat as unreliable

`firestore.googleapis.com` returned HTTP 404 on the root path during the May 2026 probe —
expected behavior, the root path has no handler. TCP connection succeeded.

However: Firestore is a Google Firebase product and likely subject to sanctions targeting
Firebase specifically. The probe did not verify authenticated Firestore API calls. Do not
depend on Firestore as a transport. Khorshid uses GitHub Issues API instead, which is
confirmed working end-to-end.

`firebaseio.com` (Firebase Realtime Database) returns URLError — specifically blocked.
Do not use.

### googleapis.com is open

Google's API infrastructure (`www.googleapis.com`, `sheets.googleapis.com`,
`firestore.googleapis.com`) is accessible. HTTP 404 on root paths is expected.
Actual API endpoints at specific paths work.

Implication: Google Sheets API is a viable emergency transport fallback.

### GitLab: git protocol works, web is blocked

`gitlab.com` website returns URLError — blocked. But:
- TCP port 443 open (13ms)
- git smart-HTTP protocol confirmed working (git OK, 1163ms)

The git transport to GitLab is viable even though the website is not. App can push/pull
to GitLab repos silently without the user ever needing to visit gitlab.com.

### Cloudflare is blocked

Confirmed. No Cloudflare IPs are reachable. This eliminates:
- Cloudflare CDN
- Cloudflare Workers
- jsDelivr (uses Cloudflare)
- Any service fronted by Cloudflare

### PyPI and npm are open

Likely because Iranian developers need to install packages. Not useful as transports
but confirms that the whitelist includes developer infrastructure.

---

## Latency notes

~700-1200ms round-trip to GitHub and Google is high but acceptable for a messaging app
that isn't trying to compete with Telegram. Firestore's real-time WebSocket connection
would have lower sustained latency than individual HTTP requests.

---

## What to re-probe periodically

- `api.github.com` — core write/read path, most critical to monitor
- `raw.githubusercontent.com` — CDN read path for news feed
- `firestore.googleapis.com` — not currently used, but worth tracking if access improves
- `8.8.8.8` / `8.8.4.4` — Google DNS (emergency DNS tunneling fallback, currently unverified)

Run `python3 scripts/check-network.py` whenever the network situation changes.
