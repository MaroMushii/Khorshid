# Khorshid

A censorship-resistant, encrypted news and discussion platform built for people living
under internet blackouts. Designed around the reality that GitHub is reliably accessible
from Iran even during severe censorship.

Named after the Persian word for "Sun."

---

## Why this exists

Iran has experienced 70+ day internet blackouts where the entire internet is in whitelist
mode — only a handful of approved services are reachable. People have no way to get news,
communicate, or coordinate. Khorshid is built to fill that gap using the infrastructure
that remains open.

The government will block anything that threatens them, regardless of collateral damage.
No assumption of "they can't block X" is made here. The design works within whatever
remains accessible.

---

## What it is

A news and community platform built on two rails:

**Channels.** Mirrored Telegram news channels (BBC Persian, Iran International, Radio
Farda, and others). Read-only. Updated every ~5 minutes by a GitHub Actions scraper.
You read, vote, and comment. No Telegram account required.

**Rooms.** Community discussion spaces curated by the core team. You post original
content — eyewitness reports, links, discussions. Rooms are the bottom-up rail: a post
or comment from a room can climb into Today's feed alongside official news if enough
people mark it as important.

**Today.** The editorial surface. Pulls from both channels and rooms. Deduplicates same
stories from multiple channels. Ranks everything by importance votes and time decay. A
hot community comment gets a "Community Report" card in Today — the same visual weight
as a BBC Persian article.

**Private.** Invite-only encrypted rooms. One private GitHub repo per room. Join via QR
code or pasted invite bundle. Room key never leaves the device.

---

## Core principles

1. **Zero setup for users.** Open the app, pick a name, start reading and writing. No
   GitHub account. No email. No registration.

2. **All content encrypted.** GitHub sees ciphertext. "Public" means anyone with the app
   can read it — not anyone on the internet.

3. **Identity is a keypair, not an account.** Generated locally on first launch. Your
   private key never leaves your device. Your display name is whatever you typed.

4. **Community sets the agenda.** Importance votes — not recency, not follower count —
   determine what surfaces in Today. A ground-level eyewitness report competes on equal
   terms with an official news post.

5. **GitHub is the only infrastructure.** No dedicated servers. No Cloudflare. No
   Firebase. The REST API and raw CDN are the entire backend.

---

## Platforms

macOS first (SwiftUI, macOS 26), then Android (Flutter).
