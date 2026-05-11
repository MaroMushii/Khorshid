// Usage: pnpm exec tsx aggregate.ts <out-dir> [YYYY-MM-DD]
// Reads today's posts from the export branch checkout at <out-dir>,
// fetches vote/flag signals from khorshid-social, deduplicates posts via
// media fingerprint + embedding similarity + LLM, scores, and writes
// feed/<date>.json (client-facing) and feed/<date>.cache.json (aggregator state).

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { IndexDoc, Snapshot } from "./schema.js";
import type { Feed, FeedPost, FeedCache, CommunityReport } from "./feed-schema.js";

const SOCIAL_REPO = "MaroMushii/khorshid-social";
const GH_API = "https://api.github.com";
const GH_COMPLETIONS_URL = "https://models.inference.ai.azure.com/chat/completions";
const GH_EMBEDDINGS_URL = "https://models.inference.ai.azure.com/embeddings";

const FLAG_THRESHOLD = 5;
const COMMUNITY_REPORT_TOP_N = 3;

// Cosine similarity thresholds for dedup
const DEDUP_DEFINITE_MATCH = 0.92; // above → duplicate, no LLM call
const DEDUP_DEFINITE_NEW = 0.30;   // below → new story, no LLM call
const DEDUP_CANDIDATES = 3;        // top N candidates sent to LLM for ambiguous range

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

// --- GitHub API helper ---

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
  const posted = postedAt ? new Date(postedAt).getTime() : now - 6 * 3_600_000;
  const ageHours = Math.max(0, (now - posted) / 3_600_000);
  return voteCount * Math.exp(-0.3 * ageHours);
}

function sha256(str: string): string {
  return createHash("sha256").update(str).digest("hex");
}

function textExcerpt(plainText: string): string {
  return (plainText.split("\n")[0] ?? plainText).trim().slice(0, 150);
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

// --- Rate-limit retry ---

async function withRetry<T>(label: string, fn: () => Promise<T>, maxRetries = 4): Promise<T> {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === maxRetries - 1) throw err;
      const match = String(err).match(/Please wait (\d+) seconds/);
      const waitSecs = match ? parseInt(match[1]!, 10) + 2 : 62;
      console.log(`[${label}] rate limited — waiting ${waitSecs}s (attempt ${attempt + 1}/${maxRetries})`);
      await new Promise((resolve) => setTimeout(resolve, waitSecs * 1000));
    }
  }
  throw new Error(`${label}: max retries exceeded`);
}

// --- Embeddings ---

async function embedBatch(token: string, texts: string[]): Promise<number[][]> {
  if (texts.length === 0) return [];

  const res = await fetch(GH_EMBEDDINGS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: "text-embedding-3-small", input: texts }),
  });
  if (!res.ok) throw new Error(`Embeddings API → ${res.status}: ${await res.text()}`);

  const data = (await res.json()) as { data: Array<{ embedding: number[]; index: number }> };
  // API may return results out of order — sort by index to align with input array
  return [...data.data].sort((a, b) => a.index - b.index).map((d) => d.embedding);
}

function cosineSim(a: number[], b: number[]): number {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    const ai = a[i] ?? 0;
    const bi = b[i] ?? 0;
    dot += ai * bi;
    normA += ai * ai;
    normB += bi * bi;
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

// --- LLM dedup decision (only called for ambiguous cosine range) ---

const DEDUP_SYSTEM_PROMPT = [
  "You are a Persian/Farsi news deduplication assistant.",
  "Each post is an excerpt from a Telegram channel post — not a traditional headline.",
  "Determine if the new post covers the same story as any candidate already in the feed.",
  "Same story = same event, even if worded differently. Named entities are the strongest signal.",
  'Return ONLY valid JSON: {"is_duplicate": true|false, "matching_post_id": "<post_id or null>"}',
].join(" ");

async function llmDedupDecision(
  token: string,
  newExcerpt: string,
  candidates: Array<{ id: string; excerpt: string }>
): Promise<{ is_duplicate: boolean; matching_post_id: string | null }> {
  const res = await fetch(GH_COMPLETIONS_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: DEDUP_SYSTEM_PROMPT },
        { role: "user", content: JSON.stringify({ new_post: newExcerpt, candidates }) },
      ],
    }),
  });
  if (!res.ok) throw new Error(`LLM dedup → ${res.status}: ${await res.text()}`);

  const data = (await res.json()) as { choices: Array<{ message: { content: string } }> };
  const content = data.choices[0]?.message.content ?? "{}";
  const parsed = JSON.parse(content) as { is_duplicate?: boolean; matching_post_id?: string | null };

  return {
    is_duplicate: parsed.is_duplicate ?? false,
    matching_post_id: parsed.matching_post_id ?? null,
  };
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

  // 3. Load existing feed and cache (incremental — runs accumulate throughout the day)
  const feedDir = join(outDir, "feed");
  const feedPath = join(feedDir, `${today}.json`);
  const cachePath = join(feedDir, `${today}.cache.json`);

  const existingFeed: Feed = existsSync(feedPath)
    ? (JSON.parse(readFileSync(feedPath, "utf8")) as Feed)
    : { date: today, generated_at: "", posts: [], community_reports: [] };

  const cache: FeedCache = existsSync(cachePath)
    ? (JSON.parse(readFileSync(cachePath, "utf8")) as FeedCache)
    : { embeddings: {}, media_urls: [] };

  const existingPostIds = new Set(existingFeed.posts.map((p) => p.post_id));
  const feedMediaUrls = new Set(cache.media_urls);

  // 4. Fetch today's Issues from khorshid-social
  const searchResult = await ghGet<GHSearchResult>(
    `/search/issues?q=repo:${SOCIAL_REPO}+${today}+in:title&per_page=100`,
    ghToken
  );

  const channelIssues = searchResult.items.filter((i) => i.title.startsWith("channel-"));
  const roomIssues = searchResult.items.filter((i) => i.title.startsWith("room-"));

  // 5. Fetch vote/flag signals from channel Issues
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

  // 6. Refresh hot_scores for posts already in the feed (votes accumulate throughout the day)
  for (const post of existingFeed.posts) {
    const voteCount = importantVotes.get(post.post_id)?.size ?? 0;
    post.vote_count = voteCount;
    post.hot_score = hotScore(voteCount, post.posted_at);
  }

  // 7. Dedup and add new posts
  const newPosts = allPosts.filter(
    ({ channelUsername, post }) => !existingPostIds.has(`${channelUsername}/${post.id}`)
  );

  console.log(`${newPosts.length} new posts to process`);

  // Phase 1: apply cheap filters (flags, media fingerprint), collect survivors
  type Candidate = {
    channelUsername: string;
    channelTitle: string;
    post: Snapshot["posts"][number];
    postId: string;
    postMediaUrls: string[];
    excerpt: string;
  };

  const toProcess: Candidate[] = [];

  for (const { channelUsername, channelTitle, post } of newPosts) {
    const postId = `${channelUsername}/${post.id}`;

    if ((allFlags.get(postId)?.size ?? 0) >= FLAG_THRESHOLD) {
      console.log(`[flags] <${postId}> excluded`);
      continue;
    }

    const postMediaUrls = post.media
      .map((m) => m.asset_url)
      .filter((u): u is string => u !== null);

    if (postMediaUrls.some((url) => feedMediaUrls.has(url))) {
      console.log(`[media] <${postId}> skipped — shared media with existing feed post`);
      continue;
    }

    toProcess.push({ channelUsername, channelTitle, post, postId, postMediaUrls, excerpt: textExcerpt(post.plain_text) });
  }

  // Phase 2: batch embed all posts not yet in cache (single API call)
  const toEmbed = toProcess.filter((c) => c.excerpt.length > 0 && cache.embeddings[c.postId] === undefined);

  if (toEmbed.length > 0) {
    console.log(`Embedding ${toEmbed.length} posts in one batch call...`);
    const embeddings = await withRetry("embed", () => embedBatch(ghToken, toEmbed.map((c) => c.excerpt)));
    for (let i = 0; i < toEmbed.length; i++) {
      const c = toEmbed[i];
      const emb = embeddings[i];
      if (c && emb) cache.embeddings[c.postId] = emb;
    }
  }

  // Phase 3: per-post cosine dedup, LLM only for ambiguous range.
  // Embeddings are already computed — cosine comparison is pure math, no API calls for clear cases.
  // Posts added earlier in this run become candidates for later posts (incremental within the run).
  for (const { channelUsername, channelTitle, post, postId, postMediaUrls, excerpt } of toProcess) {
    let isDuplicate = false;
    let clusterId = sha256(postId).slice(0, 12);

    const embedding = cache.embeddings[postId];
    const candidates = existingFeed.posts.filter(
      (p) => p.channel_username !== channelUsername && cache.embeddings[p.post_id] !== undefined
    );

    if (embedding && candidates.length > 0) {
      const scored = candidates
        .map((p) => ({ p, score: cosineSim(embedding, cache.embeddings[p.post_id]!) }))
        .sort((a, b) => b.score - a.score);

      const top = scored[0];

      if (top && top.score >= DEDUP_DEFINITE_MATCH) {
        isDuplicate = true;
        console.log(`[dedup] <${postId}> duplicate of <${top.p.post_id}> (cosine ${top.score.toFixed(3)})`);
      } else if (top && top.score >= DEDUP_DEFINITE_NEW) {
        const llmCandidates = scored.slice(0, DEDUP_CANDIDATES).map((s) => ({
          id: s.p.post_id,
          excerpt: textExcerpt(s.p.plain_text),
        }));
        const decision = await withRetry("llm-dedup", () => llmDedupDecision(ghToken, excerpt, llmCandidates));
        isDuplicate = decision.is_duplicate;
        if (decision.is_duplicate && decision.matching_post_id) {
          const match = existingFeed.posts.find((p) => p.post_id === decision.matching_post_id);
          if (match) {
            clusterId = match.cluster_id;
            console.log(`[dedup] <${postId}> duplicate of <${decision.matching_post_id}> (LLM)`);
          }
        }
      } else {
        if (top) console.log(`[dedup] <${postId}> new story (cosine ${top.score.toFixed(3)})`);
      }
    }

    if (!isDuplicate) {
      const voteCount = importantVotes.get(postId)?.size ?? 0;
      existingFeed.posts.push({
        post_id: postId,
        channel_username: channelUsername,
        channel_title: channelTitle,
        plain_text: post.plain_text,
        body_html: post.body_html,
        media: post.media,
        posted_at: post.posted_at,
        hot_score: hotScore(voteCount, post.posted_at),
        vote_count: voteCount,
        cluster_id: clusterId,
      });
      for (const url of postMediaUrls) feedMediaUrls.add(url);
    }
  }

  // 8. Community Reports: top N encrypted room comments by importance votes
  const roomCommentScores: CommunityReport[] = [];

  for (const issue of roomIssues) {
    const roomSlug = issue.title.slice("room-".length, -(today.length + 1));
    const comments = await ghGet<GHComment[]>(
      `/repos/${SOCIAL_REPO}/issues/${issue.number}/comments?per_page=100`,
      ghToken
    );

    const roomVotes = tallySignal(comments, "vote", "important");
    const roomFlags = tallySignal(comments, "flag");

    for (const comment of comments) {
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

  // 9. Finalize and write
  existingFeed.posts.sort((a, b) => b.hot_score - a.hot_score);
  existingFeed.community_reports = roomCommentScores.slice(0, COMMUNITY_REPORT_TOP_N);
  existingFeed.generated_at = new Date().toISOString();

  cache.media_urls = [...feedMediaUrls];

  mkdirSync(feedDir, { recursive: true });
  writeFileSync(feedPath, JSON.stringify(existingFeed, null, 2) + "\n");
  writeFileSync(cachePath, JSON.stringify(cache, null, 2) + "\n");

  console.log(
    `Wrote feed/${today}.json — ${existingFeed.posts.length} posts, ${existingFeed.community_reports.length} community reports`
  );
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
