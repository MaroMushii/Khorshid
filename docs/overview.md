# Khorshid

A censorship-resistant, encrypted communication platform built for people living under
internet blackouts. Designed around the reality that GitHub and Google are sometimes the
only accessible services.

Named after the Persian word for "Sun."

---

## Why this exists

Iran has experienced 70+ day internet blackouts where the entire internet is in whitelist
mode — only a handful of approved services are reachable. People have no way to communicate,
share news, or coordinate. Khorshid is built to fill that gap using the services that
remain open.

The government will block anything that threatens them, regardless of collateral damage.
No assumption of "they can't block X" is made here. The design adapts to whatever
remains accessible.

---

## What it is

A Reddit-inspired platform with two core concepts:

**Daily rooms.** Each day is self-contained. You open today, you see today's content.
Yesterday doesn't pollute today.

**Importance voting.** Not just upvotes. A specific signal that surfaces what *matters* —
a report of a crackdown goes up because people need to see it, not because it's popular.
Important messages float to "Today's highlights" at the top. Everything else scrolls below.

**Room types:**
- Public rooms — open to anyone with the app. Pre-defined: News, Politics, Tech, Random.
- Private rooms — invite-only, shared via QR code or Bluetooth pairing. Like a group chat.

---

## Core principles

1. **Zero setup for users.** Open the app, pick a name, start reading and writing. No
   GitHub account. No email. No registration.

2. **All rooms encrypted.** GitHub and anyone who accesses the storage sees ciphertext.
   "Public" means anyone with the app can read it — not anyone on the internet.

3. **Identity is a keypair, not an account.** Generated locally on first launch. Your
   private key never leaves your device. Your display name is whatever you typed.

4. **Transport is a plugin.** The message format doesn't care how messages travel.
   When one transport gets blocked, the app silently switches to the next.

5. **Relay operators are anonymous bridges.** Volunteers outside Iran run relay nodes
   that bridge between transports. They see encrypted blobs. Nothing else.

---

## Platforms

Target: Android first (highest reach in Iran), then macOS and Windows.
A cross-platform framework (Flutter or Kotlin Multiplatform) should be evaluated.
