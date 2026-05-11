set shell := ["bash", "-uc", "-o", "pipefail"]

default:
    @just --list

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
