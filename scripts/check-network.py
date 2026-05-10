#!/usr/bin/env python3
"""
Network reachability probe for censored environments.
Tests all services relevant to the relay architecture.
No external dependencies — Python 3 stdlib only.

Usage:
  python3 check-network.py
  python3 check-network.py --json     # machine-readable output
"""

import urllib.request
import urllib.error
import ssl
import socket
import time
import sys
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

TARGETS = [
    # label                  url                                          notes
    ("GitHub API",           "https://api.github.com",                   "core write/read path"),
    ("GitHub web",           "https://github.com",                       "main site"),
    ("GitHub raw CDN",       "https://raw.githubusercontent.com",        "read-only file serving"),
    ("GitHub git objects",   "https://objects.githubusercontent.com",    "git pack transfers"),
    ("GitLab",               "https://gitlab.com",                       "fallback transport 1"),
    ("Codeberg",             "https://codeberg.org",                     "fallback transport 2"),
    ("SourceForge",          "https://sourceforge.net",                  "fallback transport 3"),
    ("Google",               "https://www.google.com",                   "baseline google check"),
    ("Google APIs",          "https://www.googleapis.com",               "firebase/sheets/etc live here"),
    ("Firebase RT DB",       "https://firebaseio.com",                   "realtime database"),
    ("Firestore",            "https://firestore.googleapis.com",         "document database"),
    ("Google Sheets",        "https://sheets.googleapis.com",            "sheets as transport fallback"),
    ("Figma",                "https://www.figma.com",                    "confirmed accessible"),
    ("npm registry",         "https://registry.npmjs.org",               "dev-adjacent, might be open"),
    ("PyPI",                 "https://pypi.org",                         "dev-adjacent, might be open"),
    ("Archive.org",          "https://archive.org",                      "cultural institution"),
    ("Cloudflare (1.1.1.1)", "https://one.one.one.one",                  "cloudflare infra check"),
    ("Fastly CDN",           "https://www.fastly.com",                   "github pages CDN"),
    ("jsDelivr CDN",         "https://cdn.jsdelivr.net",                 "open source CDN"),
]

GIT_PROBES = [
    ("GitHub git protocol",  "https://github.com/git/git.git"),
    ("GitLab git protocol",  "https://gitlab.com/gitlab-org/gitlab.git"),
]

PORT_PROBES = [
    ("GitHub SSH (port 22)", "ssh.github.com", 22),
    ("GitHub HTTPS (443)",   "github.com",     443),
    ("GitLab HTTPS (443)",   "gitlab.com",     443),
]

TIMEOUT = 6
CTX = ssl.create_default_context()


def check_https(label, url, notes):
    start = time.time()
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 (compatible; network-probe/1.0)"}
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=CTX) as resp:
            latency = int((time.time() - start) * 1000)
            return {
                "label": label,
                "url": url,
                "notes": notes,
                "reachable": True,
                "status": str(resp.status),
                "latency_ms": latency,
            }
    except urllib.error.HTTPError as e:
        latency = int((time.time() - start) * 1000)
        # HTTP errors mean the server responded — it's reachable
        return {
            "label": label,
            "url": url,
            "notes": notes,
            "reachable": True,
            "status": f"HTTP {e.code}",
            "latency_ms": latency,
        }
    except Exception as e:
        return {
            "label": label,
            "url": url,
            "notes": notes,
            "reachable": False,
            "status": type(e).__name__,
            "latency_ms": None,
        }


def check_git_protocol(label, repo_url):
    probe_url = f"{repo_url}/info/refs?service=git-upload-pack"
    start = time.time()
    try:
        req = urllib.request.Request(
            probe_url,
            headers={
                "User-Agent": "git/2.40.0",
                "Git-Protocol": "version=2",
            }
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=CTX) as resp:
            latency = int((time.time() - start) * 1000)
            content_type = resp.headers.get("Content-Type", "")
            is_git = "git-upload-pack" in content_type
            return {
                "label": label,
                "url": repo_url,
                "notes": "git smart-HTTP protocol",
                "reachable": True,
                "status": "git OK" if is_git else f"HTTP {resp.status} (not git?)",
                "latency_ms": latency,
            }
    except Exception as e:
        return {
            "label": label,
            "url": repo_url,
            "notes": "git smart-HTTP protocol",
            "reachable": False,
            "status": type(e).__name__,
            "latency_ms": None,
        }


def check_tcp_port(label, host, port):
    start = time.time()
    try:
        with socket.create_connection((host, port), timeout=TIMEOUT):
            latency = int((time.time() - start) * 1000)
            return {
                "label": label,
                "url": f"{host}:{port}",
                "notes": "raw TCP",
                "reachable": True,
                "status": "open",
                "latency_ms": latency,
            }
    except Exception as e:
        return {
            "label": label,
            "url": f"{host}:{port}",
            "notes": "raw TCP",
            "reachable": False,
            "status": type(e).__name__,
            "latency_ms": None,
        }


def check_github_api_call():
    """Actually calls the GitHub API — confirms auth-less access works."""
    start = time.time()
    try:
        req = urllib.request.Request(
            "https://api.github.com/zen",
            headers={
                "User-Agent": "network-probe/1.0",
                "Accept": "application/vnd.github+json",
            }
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=CTX) as resp:
            latency = int((time.time() - start) * 1000)
            body = resp.read().decode().strip()
            return {
                "label": "GitHub API (real call)",
                "url": "https://api.github.com/zen",
                "notes": "unauthenticated API call",
                "reachable": True,
                "status": f'200 — "{body[:40]}"',
                "latency_ms": latency,
            }
    except Exception as e:
        return {
            "label": "GitHub API (real call)",
            "url": "https://api.github.com/zen",
            "notes": "unauthenticated API call",
            "reachable": False,
            "status": type(e).__name__,
            "latency_ms": None,
        }


def render_table(results):
    GREEN  = "\033[92m"
    RED    = "\033[91m"
    YELLOW = "\033[93m"
    RESET  = "\033[0m"
    BOLD   = "\033[1m"

    col_label   = max(len(r["label"]) for r in results) + 2
    col_status  = max(len(r["status"]) for r in results) + 2
    col_latency = 12
    col_notes   = 40

    header = (
        f"{'SERVICE':<{col_label}}"
        f"{'STATUS':<{col_status}}"
        f"{'LATENCY':>{col_latency}}"
        f"  {'NOTES'}"
    )
    print(f"\n{BOLD}{header}{RESET}")
    print("─" * (col_label + col_status + col_latency + col_notes))

    for r in results:
        if r["reachable"]:
            color  = GREEN
            symbol = "✓"
            lat    = f"{r['latency_ms']}ms" if r["latency_ms"] else "—"
        else:
            color  = RED
            symbol = "✗"
            lat    = "—"

        label   = f"{symbol} {r['label']}"
        status  = r["status"]
        notes   = r.get("notes", "")

        print(
            f"{color}{label:<{col_label}}{RESET}"
            f"{status:<{col_status}}"
            f"{lat:>{col_latency}}"
            f"  {YELLOW}{notes}{RESET}"
        )


def main():
    as_json = "--json" in sys.argv

    all_jobs = []

    with ThreadPoolExecutor(max_workers=16) as pool:
        futures = {}

        for label, url, notes in TARGETS:
            f = pool.submit(check_https, label, url, notes)
            futures[f] = label

        for label, repo_url in GIT_PROBES:
            f = pool.submit(check_git_protocol, label, repo_url)
            futures[f] = label

        for label, host, port in PORT_PROBES:
            f = pool.submit(check_tcp_port, label, host, port)
            futures[f] = label

        f = pool.submit(check_github_api_call)
        futures[f] = "GitHub API (real call)"

        results = []
        for future in as_completed(futures):
            results.append(future.result())

    # sort: reachable first, then by label
    results.sort(key=lambda r: (not r["reachable"], r["label"]))

    if as_json:
        print(json.dumps(results, indent=2))
        return

    render_table(results)

    reachable = [r for r in results if r["reachable"]]
    blocked   = [r for r in results if not r["reachable"]]

    print(f"\nReachable: {len(reachable)}  |  Blocked/unreachable: {len(blocked)}\n")

    if any("GitHub API" in r["label"] and r["reachable"] for r in results):
        print("→ GitHub API is UP. Primary transport viable.")
    if any("GitLab" in r["label"] and r["reachable"] for r in results):
        print("→ GitLab is UP. Fallback transport 1 viable.")
    if any("Firebase" in r["label"] and r["reachable"] for r in results):
        print("→ Firebase is UP. Consider as high-speed transport.")
    if any("Google Sheets" in r["label"] and r["reachable"] for r in results):
        print("→ Google Sheets API is UP. Emergency fallback viable.")


if __name__ == "__main__":
    main()
