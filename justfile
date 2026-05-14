set shell := ["bash", "-uc", "-o", "pipefail"]

# Pretty-print xcodebuild output if xcbeautify is on PATH; otherwise pass through unchanged.
xcb := `command -v xcbeautify >/dev/null && echo xcbeautify || echo cat`

# Show the recipe list
default:
    @just --list

# ── Mac app ──────────────────────────────────────────────────────────────────

# Regenerate Xcode project + build Debug
build: xcbuild

# Build Debug and launch a fresh copy (kills any running instance after a successful build)
run: xcbuild kill
    open "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Khorshid-*/Build/Products/Debug/Khorshid.app | head -1)"

[private]
kill:
    pkill -x Khorshid 2>/dev/null || true
    for i in {1..50}; do pgrep -x Khorshid >/dev/null 2>&1 || break; sleep 0.1; done

# Run the test bundle
test:
    cd mac && NSUnbufferedIO=YES xcodebuild -project Khorshid.xcodeproj -scheme Khorshid -configuration Debug test 2>&1 | {{xcb}}

# Open the freshest Debug build (does not rebuild)
app:
    open "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Khorshid-*/Build/Products/Debug/Khorshid.app | head -1)"

[private]
xcbuild:
    cd mac && xcodegen generate
    cd mac && NSUnbufferedIO=YES xcodebuild -project Khorshid.xcodeproj -scheme Khorshid -configuration Debug build 2>&1 | {{xcb}}

# Reveal the freshest Debug build in Finder
reveal:
    open -R "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Khorshid-*/Build/Products/Debug/Khorshid.app | head -1)"

# Trash all DerivedData copies
clean: kill
    -trash ~/Library/Developer/Xcode/DerivedData/Khorshid-*

log_subsystem := "dev.MaroMushii.Khorshid"

# Tail Khorshid logs live. Categories: all (default), feed, net, mirror, identity, social.
logs category="all":
    #!/usr/bin/env bash
    set -euo pipefail
    cat=$(echo "{{category}}" | tr '[:upper:]' '[:lower:]')
    if [[ "$cat" == "all" ]]; then
      pred='subsystem == "{{log_subsystem}}"'
    else
      capped="$(tr '[:lower:]' '[:upper:]' <<< ${cat:0:1})${cat:1}"
      pred='subsystem == "{{log_subsystem}}" AND category == "'"$capped"'"'
    fi
    echo "==> tailing $cat — Ctrl-C to stop"
    exec log stream --style compact --level info --predicate "$pred"

# Dump last <duration> of Khorshid logs and exit. Examples: just logs-since feed 30s
logs-since category="all" duration="5m":
    #!/usr/bin/env bash
    set -euo pipefail
    cat=$(echo "{{category}}" | tr '[:upper:]' '[:lower:]')
    if [[ "$cat" == "all" ]]; then
      pred='subsystem == "{{log_subsystem}}"'
    else
      capped="$(tr '[:lower:]' '[:upper:]' <<< ${cat:0:1})${cat:1}"
      pred='subsystem == "{{log_subsystem}}" AND category == "'"$capped"'"'
    fi
    echo "==> dumping $cat (last {{duration}})"
    log show --style compact --info --debug --last {{duration}} --predicate "$pred"

# Record a SwiftUI Instruments trace → ~/Desktop/khorshid-<ts>.trace. App must be running.
trace seconds="15":
    #!/usr/bin/env bash
    set -euo pipefail
    ts=$(date +%Y%m%d-%H%M%S)
    out="$HOME/Desktop/khorshid-$ts.trace"
    echo "==> recording SwiftUI trace for {{seconds}}s → $out"
    xcrun xctrace record \
      --template "SwiftUI" \
      --attach Khorshid \
      --time-limit {{seconds}}s \
      --output "$out"
    echo "==> done. Open in Instruments:  open '$out'"

# ── Mirror / scraper ─────────────────────────────────────────────────────────

# Typecheck the mirror scraper (offline)
mirror-check:
    cd mirror && pnpm typecheck

# Typecheck the social schema (offline)
social-check:
    cd social && pnpm typecheck

# Manually trigger the mirror workflow on GitHub
update-mirror:
    gh workflow run mirror.yml --repo MaroMushii/Khorshid

# Manually trigger the daily Issue provisioner on khorshid-social
provision-social:
    gh workflow run provision.yml --repo MaroMushii/khorshid-social

# Run the scraper locally against a temp tree
# Requires t.me to be reachable (won't work from Iran-side machines)
mirror-run:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"
    echo "==> scraping into $tmp"
    cd mirror && pnpm exec tsx scrape.ts "$tmp" channels.json
    echo "==> done. tree at $tmp"

# Dry-run the parser against a live channel (needs t.me reachable)
dry-run username="bbcpersian":
    cd mirror && pnpm exec tsx dry-run.ts --live {{username}}

# Run the aggregator locally against a fresh export branch checkout
aggregate-run date="":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"
    echo "==> checking out export branch into $tmp"
    git clone --quiet --branch export --depth 1 "https://x-access-token:$(gh auth token)@github.com/MaroMushii/Khorshid.git" "$tmp"
    echo "==> running aggregator"
    cd mirror && pnpm exec tsx aggregate.ts "$tmp" {{date}}
    echo "==> feed output:"
    ls -lh "$tmp/feed/" 2>/dev/null || echo "(no feed dir written)"

# Manually trigger the aggregator workflow on GitHub
update-aggregator:
    gh workflow run aggregator.yml --repo MaroMushii/Khorshid

# Deploy the Cloudflare cron dispatcher
deploy-dispatcher:
    cd cf-dispatcher && pnpm exec wrangler deploy

# Set the GitHub PAT secret on the Cloudflare Worker
set-dispatcher-token:
    cd cf-dispatcher && pnpm exec wrangler secret put GITHUB_TOKEN
