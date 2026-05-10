# Khorshid-6p0 — Deploy Cloudflare dispatcher for reliable cron

## Fact-check

- `cf-dispatcher/src/worker.ts` — correct. REPO=MaroMushii/Khorshid, WORKFLOW=mirror.yml, REF=main.
- `cf-dispatcher/wrangler.toml` — correct. name=khorshid-mirror-dispatcher, cron=*/5.
- `mirror.yml` — has `workflow_dispatch: {}`. Workflow ID 274089170 confirmed active on GitHub.
- **BLOCKING drift found:** wrangler auth is expired (403 on `whoami`). Must re-login before deploy.
  Pigeon's wrangler session is also expired — same CF account token. Re-login fixes both.
- No code changes needed. This is a pure ops task.
- No uncommitted changes. On branch: main.

## Plan

### Step 1 — Re-authenticate wrangler (interactive, browser)
User runs in terminal:
```fish
cd /Users/mehdi/Work/Khorshid/cf-dispatcher
pnpm exec wrangler login
```
Browser opens → log in to the Cloudflare account that will own the Worker.
Verify: `pnpm exec wrangler whoami` returns an account name.

### Step 2 — Deploy the Worker
```fish
just deploy-dispatcher
```
Which runs: `cd cf-dispatcher && pnpm exec wrangler deploy`
Expected output: "Deployed khorshid-mirror-dispatcher (version X) triggers: cron(*/5 * * * *)"

### Step 3 — Create a fine-grained GitHub PAT for the Worker
At github.com/settings/personal-access-tokens (logged in as MaroMushii):
- Resource owner: MaroMushii
- Repository access: Only MaroMushii/Khorshid
- Permissions: Actions → Read and write
- No other permissions needed

Copy the token.

### Step 4 — Set the secret on the Worker
```fish
just set-dispatcher-token
```
Which runs: `cd cf-dispatcher && pnpm exec wrangler secret put GITHUB_TOKEN`
Paste the PAT when prompted. It's stored encrypted in CF — never in the repo.

### Step 5 — Verify
In CF dashboard: Workers & Pages → khorshid-mirror-dispatcher → Settings → Triggers
Should show: `*/5 * * * *`

Optional live verification:
```fish
cd cf-dispatcher && pnpm exec wrangler tail khorshid-mirror-dispatcher
```
Wait up to 5 min for the first dispatch log to appear:
`dispatched mirror.yml on <MaroMushii/Khorshid@main> at <timestamp>`

Then check GH Actions: gh run list --workflow mirror.yml --repo MaroMushii/Khorshid

## Risks

- CF free plan: 100k requests/day. At 288 dispatches/day (*/5), well under limit.
- PAT expiry: fine-grained PATs default to 1 year. Set a calendar reminder to rotate.
- If the Pigeon wrangler auth was shared, re-login will refresh it for Pigeon too.

## Files changed
None. Pure deployment.
