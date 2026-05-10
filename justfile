set shell := ["bash", "-uc", "-o", "pipefail"]

default:
    @just --list

# Typecheck the mirror scraper (offline)
mirror-check:
    cd mirror && pnpm typecheck

# Manually trigger the mirror workflow on GitHub
update-mirror:
    gh workflow run mirror.yml --repo MaroMushii/Khorshid

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

# Deploy the Cloudflare cron dispatcher
deploy-dispatcher:
    cd cf-dispatcher && pnpm exec wrangler deploy

# Set the GitHub PAT secret on the Cloudflare Worker
set-dispatcher-token:
    cd cf-dispatcher && pnpm exec wrangler secret put GITHUB_TOKEN
