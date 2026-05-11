# Khorshid-x2x — Create khorshid-social repo and daily Issue provisioning

## Fact-check summary

- CONFIRMED: `MaroMushii/khorshid-social` does NOT exist — `gh repo view` returned 404.
- CONFIRMED: 9 active channels in `mirror/channels.json`: bbcpersian, dwpersian, farsi_iranwire, farsivoa, hranews, iranintltv, mamlekate, radiofarda, sahamnewsorg.
- CONFIRMED: No rooms defined yet — Khorshid-2ay is future work. Workflow will have a placeholder comment for room provisioning.
- CONFIRMED: Existing workflow pattern in `.github/workflows/mirror.yml`: `actions/checkout@v6`, git-based commit (add → diff --staged → commit if changed, skip otherwise).
- CONFIRMED: `social/schema.ts` (Khorshid-nku, just landed) defines `IssueContext` as `` `channel-${string}-${string}` `` — provisioned titles must match exactly.
- INFORMATIONAL: Bead mentions `KHORSHID_SOCIAL_PAT`. The provisioning workflow uses `GITHUB_TOKEN` (auto-provisioned with `issues: write` + `contents: write` in its own repo). External PAT for client writes is Khorshid-il6's scope, not needed here.

## Approach

1. Create `MaroMushii/khorshid-social` as a public repo via `gh repo create --add-readme` (this creates the `main` branch with an initial commit, required for the manifest checkout-and-commit pattern).
2. Push `.github/workflows/provision.yml` via `gh api PUT /repos/.../contents/...` (no local clone needed).
3. The workflow: runs every minute, fetches `channels.json` from `raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/main/mirror/channels.json`, ensures today's Issues exist for all 9 channels, writes `manifest.json` mapping `channel-<slug>-<date>` → issue number (today + yesterday), commits if changed.
4. Add `provision-social` recipe to the main repo's `justfile` for manual trigger (mirrors `update-mirror`).
5. Commit the justfile change to `feat/khorshid-social-repo`.

## Files to touch

| File | Change |
|------|--------|
| External: `khorshid-social/.github/workflows/provision.yml` | Create — core provisioning workflow |
| External: `khorshid-social/README.md` | Auto-created; overwrite with project description |
| Main repo: `justfile` | Add `provision-social` recipe |
| Main repo: `.beads/issues.jsonl` | Claim + close tracking (auto-managed by `bd`) |

## Workflow design (`provision.yml`)

```yaml
name: provision-daily-issues

on:
  schedule:
    - cron: "* * * * *"
  workflow_dispatch: {}

permissions:
  issues: write
  contents: write

concurrency:
  group: provision
  cancel-in-progress: false

jobs:
  provision:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Provision issues + write manifest
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
        run: |
          set -euo pipefail

          TODAY="$(date -u +%Y-%m-%d)"
          YESTERDAY="$(date -u -d yesterday +%Y-%m-%d)"

          CHANNELS=$(curl -sf \
            https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/main/mirror/channels.json \
            | jq -r '.channels[]')

          # Ensure type labels exist (idempotent)
          gh label create channel --color "e4e669" \
            --description "Channel discussion thread" --force 2>/dev/null || true
          gh label create room --color "d93f0b" \
            --description "Room post+comment thread" --force 2>/dev/null || true

          # Fetch all existing channel issues for manifest lookup
          EXISTING=$(gh issue list \
            --repo "$REPO" --label channel \
            --state all --json number,title --limit 200)

          MANIFEST=$(jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{"v":1,"updated_at":$ts,"issues":{}}')

          for slug in $CHANNELS; do
            gh label create "channel-${slug}" --color "0075ca" --force 2>/dev/null || true

            for day in "$TODAY" "$YESTERDAY"; do
              title="channel-${slug}-${day}"

              number=$(echo "$EXISTING" \
                | jq -r --arg t "$title" '.[] | select(.title == $t) | .number')

              if [ -z "$number" ] && [ "$day" = "$TODAY" ]; then
                number=$(gh issue create \
                  --repo "$REPO" \
                  --title "$title" \
                  --body "" \
                  --label "channel" --label "channel-${slug}" \
                  --json number --jq .number)
                echo "Created #${number}: ${title}"
              fi

              if [ -n "$number" ]; then
                MANIFEST=$(echo "$MANIFEST" \
                  | jq --arg t "$title" --argjson n "$number" '.issues[$t] = $n')
              fi
            done
          done

          # Rooms: provisioned here when Khorshid-2ay lands

          echo "$MANIFEST" | jq . > manifest.json

      - name: Commit manifest if changed
        run: |
          git config user.email "282584007+MaroMushii@users.noreply.github.com"
          git config user.name "khorshid-social[bot]"
          git add manifest.json
          if git diff --quiet --staged; then
            echo "manifest unchanged — skipping commit"
            exit 0
          fi
          git commit -m "provision: update manifest $(date -u +%Y-%m-%dT%H:%MZ)"
          git push
```

## Manifest format

```json
{
  "v": 1,
  "updated_at": "2026-05-11T00:01:23Z",
  "issues": {
    "channel-bbcpersian-2026-05-11": 1,
    "channel-dwpersian-2026-05-11": 2,
    "channel-bbcpersian-2026-05-10": 9
  }
}
```

Clients fetch `raw.githubusercontent.com/MaroMushii/khorshid-social/refs/heads/main/manifest.json` to resolve `channel-<slug>-<today>` → issue number without an API call.

## justfile addition

```makefile
# Manually trigger the daily Issue provisioner on khorshid-social
provision-social:
    gh workflow run provision.yml --repo MaroMushii/khorshid-social
```

## Order of work

1. `gh repo create MaroMushii/khorshid-social --public --description "Khorshid social layer — GitHub Issues for posts, comments, votes, and flags" --add-readme`
2. Write README content via `gh api PUT repos/MaroMushii/khorshid-social/contents/README.md`
3. Write `provision.yml` via `gh api PUT repos/MaroMushii/khorshid-social/contents/.github/workflows/provision.yml`
4. Add `provision-social` to `justfile`
5. Verify: `gh workflow list --repo MaroMushii/khorshid-social`
6. Manual trigger: `gh workflow run provision.yml --repo MaroMushii/khorshid-social`
7. Wait ~60s, verify: `gh issue list --repo MaroMushii/khorshid-social`
8. Verify manifest: `gh api repos/MaroMushii/khorshid-social/contents/manifest.json | jq -r .content | base64 -d | jq .`
9. Commit justfile change via `but commit`

## Risks

- GH Actions free-tier throttles `* * * * *` cron to ≥5 min intervals. Acceptable — daily Issues don't need sub-minute creation.
- Label creation race if two concurrent runs start simultaneously. Mitigated by `--force` + `|| true`.
- `gh issue list --label channel` returns `[]` on empty repo (first run). Falls through correctly to issue creation.
- `gh api PUT` for creating files requires the SHA of existing file for updates. On first push (file doesn't exist), SHA is omitted — correct. README update requires fetching its current SHA.

## What we'll test

```bash
gh workflow run provision.yml --repo MaroMushii/khorshid-social
# wait ~90 seconds
gh issue list --repo MaroMushii/khorshid-social --json title,number | jq .
gh api repos/MaroMushii/khorshid-social/contents/manifest.json | jq -r .content | base64 -d | jq .
just provision-social
```

Expected: 9 issues created (`channel-<slug>-<today>`), manifest.json with 9 entries.

## Open questions

None blocking.

## Size

medium

## Side effects on approval

- Branch: `feat/khorshid-social-repo`
- `bd update Khorshid-x2x --claim`
- Scratch: `.beads/scratch/Khorshid-x2x.md` (this file)
- Note: "Started. Branch: feat/khorshid-social-repo. Plan: .beads/scratch/Khorshid-x2x.md"
- External: public repo `MaroMushii/khorshid-social` created on GitHub
