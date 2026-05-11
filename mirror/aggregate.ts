// Usage: pnpm exec tsx aggregate.ts <out-dir> [YYYY-MM-DD]
// Reads today's posts from the export branch checkout at <out-dir>,
// fetches vote/flag signals from khorshid-social, clusters headlines
// via GitHub Models (GPT-4o mini), scores posts, and writes feed/<date>.json.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { IndexDoc, Snapshot } from "./schema.js";
import type { Feed, FeedPost, CommunityReport } from "./feed-schema.js";

const SOCIAL_REPO = "MaroMushii/khorshid-social";
const GH_API = "https://api.github.com";
const GH_MODELS_URL = "https://models.inference.ai.azure.com/chat/completions";
const FLAG_THRESHOLD = 5;
const COMMUNITY_REPORT_TOP_N = 3;

// --- GitHub API types ---

interface GHIssue {
  number: number;
  title: string;
}

interface GHComment {
  id: number;
  body: string;
  created_at: string;
}

interface GHSearchResult {
  items: GHIssue[];
}

// --- Social payload types (subset of social/schema.ts) ---

interface VotePayload {
  type: "vote";
  target_id: string;
  signal: "up" | "important";
  vote_id: string;
}

interface FlagPayload {
  type: "flag";
  target_id: string;
  vote_id: string;
}

// --- GitHub API helpers ---

async function ghGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`${GH_API}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!res.ok) throw new Error(`GitHub API ${path} → ${res.status} ${await res.text()}`);
  return res.json() as Promise<T>;
}

// --- Scoring ---

function hotScore(voteCount: number, postedAt: string | null): number {
  const now = Date.now();
  // No timestamp on encrypted room comments — treat as posted 6h ago (mid-day proxy)
  const posted = postedAt ? new Date(postedAt).getTime() : now - 6 * 3_600_000;
  const ageHours = Math.max(0, (now - posted) / 3_600_000);
  return voteCount * Math.exp(-0.3 * ageHours);
}

function sha256(str: string): string {
  return createHash("sha256").update(str).digest("hex");
}

// --- Vote/flag tallying ---

function mergeInto(target: Map<string, Set<string>>, source: Map<string, Set<string>>): void {
  for (const [id, ids] of source) {
    const existing = target.get(id) ?? new Set<string>();
    for (const v of ids) existing.add(v);
    target.set(id, existing);
  }
}

function tallySignal(
  comments: GHComment[],
  type: "vote" | "flag",
  signal?: "important" | "up"
): Map<string, Set<string>> {
  const tally = new Map<string, Set<string>>();
  for (const c of comments) {
    let p: Record<string, unknown>;
    try {
      p = JSON.parse(c.body) as Record<string, unknown>;
    } catch {
      continue;
    }
    if (p["type"] !== type) continue;
    if (type === "vote" && p["signal"] !== signal) continue;

    const targetId = p["target_id"];
    const voteId = p["vote_id"];
    if (typeof targetId !== "string" || typeof voteId !== "string") continue;

    const set = tally.get(targetId) ?? new Set<string>();
    set.add(voteId);
    tally.set(targetId, set);
  }
  return tally;
}

// --- GitHub Models clustering ---

interface ClusterAssignment {
  id: string;
  cluster_id: string;
}

async function clusterHeadlines(
  token: string,
  posts: Array<{ id: string; headline: string }>
): Promise<Map<string, string>> {
  if (posts.length === 0) return new Map();

  const res = await fetch(GH_MODELS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "You are a news deduplication assistant. Group posts covering the same story. Return ONLY valid JSON.",
        },
        {
          role: "user",
          content: `Assign a short snake_case cluster_id to each post. Same story = same cluster_id. Different stories = different cluster_ids.\n\nReturn: {"assignments": [{"id": "<post_id>", "cluster_id": "<snake_case>"}, ...]}\n\nPosts:\n${JSON.stringify(posts)}`,
        },
      ],
    }),
  });

  if (!res.ok) throw new Error(`GitHub Models → ${res.status}: ${await res.text()}`);

  const data = (await res.json()) as {
    choices: Array<{ message: { content: string } }>;
  };

  const content = data.choices[0]?.message.content ?? "{}";
  const parsed = JSON.parse(content) as { assignments?: ClusterAssignment[] };

  const map = new Map<string, string>();
  for (const a of parsed.assignments ?? []) {
    map.set(a.id, a.cluster_id);
  }
  return map;
}

// --- Main ---

async function main(): Promise<void> {
  const outDir = process.argv[2];
  if (!outDir) throw new Error("Usage: tsx aggregate.ts <out-dir> [YYYY-MM-DD]");

  const today = process.argv[3] ?? new Date().toISOString().slice(0, 10);
  const ghToken = process.env["GITHUB_TOKEN"];
  if (!ghToken) throw new Error("GITHUB_TOKEN not set");

  // 1. Read index.json from export branch checkout
  const indexPath = join(outDir, "index.json");
  if (!existsSync(indexPath)) {
    console.log("No index.json in export branch — nothing to aggregate.");
    return;
  }
  const index = JSON.parse(readFileSync(indexPath, "utf8")) as IndexDoc;

  // 2. Collect today's posts from all channel snapshots
  type PostEntry = { channelUsername: string; channelTitle: string; post: Snapshot["posts"][number] };
  const allPosts: PostEntry[] = [];

  for (const entry of index.channels) {
    const snapshotPath = join(outDir, entry.snapshot_path);
    if (!existsSync(snapshotPath)) continue;
    const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8")) as Snapshot;
    for (const post of snapshot.posts) {
      if (post.posted_at?.startsWith(today)) {
        allPosts.push({ channelUsername: entry.username, channelTitle: entry.title, post });
      }
    }
  }

  console.log(`Found ${allPosts.length} posts for ${today}`);

  // 3. Fetch today's Issues from khorshid-social (public repo)
  const searchResult = await ghGet<GHSearchResult>(
    `/search/issues?q=repo:${SOCIAL_REPO}+${today}+in:title&per_page=100`,
    ghToken
  );

  const channelIssues = searchResult.items.filter((i) => i.title.startsWith("channel-"));
  const roomIssues = searchResult.items.filter((i) => i.title.startsWith("room-"));

  // 4. Fetch vote/flag signals from channel Issues
  const importantVotes = new Map<string, Set<string>>();
  const allFlags = new Map<string, Set<string>>();

  for (const issue of channelIssues) {
    const comments = await ghGet<GHComment[]>(
      `/repos/${SOCIAL_REPO}/issues/${issue.number}/comments?per_page=100`,
      ghToken
    );
    mergeInto(importantVotes, tallySignal(comments, "vote", "important"));
    mergeInto(allFlags, tallySignal(comments, "flag"));
  }

  // 5. Cluster headlines via GitHub Models (GPT-4o mini)
  const clusterInputs = allPosts.map(({ channelUsername, post }) => ({
    id: `${channelUsername}/${post.id}`,
    headline: post.plain_text.slice(0, 200),
  }));

  const clusterMap = await clusterHeadlines(ghToken, clusterInputs);

  // 6. Score posts and apply flag hiding
  const scoredPosts: FeedPost[] = [];

  for (const { channelUsername, channelTitle, post } of allPosts) {
    const postId = `${channelUsername}/${post.id}`;
    if ((allFlags.get(postId)?.size ?? 0) >= FLAG_THRESHOLD) continue;

    const voteCount = importantVotes.get(postId)?.size ?? 0;
    scoredPosts.push({
      post_id: postId,
      channel_username: channelUsername,
      channel_title: channelTitle,
      plain_text: post.plain_text,
      body_html: post.body_html,
      media: post.media,
      posted_at: post.posted_at,
      hot_score: hotScore(voteCount, post.posted_at),
      vote_count: voteCount,
      cluster_id: clusterMap.get(postId) ?? postId,
    });
  }

  scoredPosts.sort((a, b) => b.hot_score - a.hot_score);

  // 7. Community Reports: top N encrypted room comments by importance votes
  type ScoredComment = Omit<CommunityReport, never>;
  const roomCommentScores: ScoredComment[] = [];

  for (const issue of roomIssues) {
    // "room-<slug>-<YYYY-MM-DD>" → extract slug
    const roomSlug = issue.title.slice("room-".length, -(today.length + 1));
    const comments = await ghGet<GHComment[]>(
      `/repos/${SOCIAL_REPO}/issues/${issue.number}/comments?per_page=100`,
      ghToken
    );

    const roomVotes = tallySignal(comments, "vote", "important");
    const roomFlags = tallySignal(comments, "flag");

    for (const comment of comments) {
      // Only score encrypted blobs (SocialPayloadWrapper), skip plaintext signals
      let p: Record<string, unknown>;
      try {
        p = JSON.parse(comment.body) as Record<string, unknown>;
      } catch {
        continue;
      }
      if (p["type"] === "vote" || p["type"] === "flag") continue;
      if (!("v" in p && "n" in p && "c" in p)) continue;

      const commentId = sha256(comment.body);
      if ((roomFlags.get(commentId)?.size ?? 0) >= FLAG_THRESHOLD) continue;

      const voteCount = roomVotes.get(commentId)?.size ?? 0;
      roomCommentScores.push({
        comment_id: commentId,
        issue_number: issue.number,
        room_slug: roomSlug,
        hot_score: hotScore(voteCount, comment.created_at),
        vote_count: voteCount,
      });
    }
  }

  roomCommentScores.sort((a, b) => b.hot_score - a.hot_score);
  const communityReports = roomCommentScores.slice(0, COMMUNITY_REPORT_TOP_N);

  // 8. Write feed/<date>.json to export branch checkout
  const feed: Feed = {
    date: today,
    generated_at: new Date().toISOString(),
    posts: scoredPosts,
    community_reports: communityReports,
  };

  const feedDir = join(outDir, "feed");
  mkdirSync(feedDir, { recursive: true });
  writeFileSync(join(feedDir, `${today}.json`), JSON.stringify(feed, null, 2) + "\n");

  console.log(
    `Wrote feed/${today}.json — ${scoredPosts.length} posts, ${communityReports.length} community reports`
  );
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
