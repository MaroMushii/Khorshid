import type { MediaDTO } from "./schema.js";

export interface FeedPost {
  post_id: string; // "<channel_username>/<telegram_post_id>"
  channel_username: string;
  channel_title: string;
  plain_text: string;
  body_html: string;
  media: MediaDTO[];
  posted_at: string | null;
  hot_score: number;
  vote_count: number; // unique "important" vote_ids
  cluster_id: string; // matches cluster_id of the first post in this story group
}

// A high-scoring encrypted room comment surfaced into the Today feed.
// The client fetches the raw comment from khorshid-social and decrypts locally.
export interface CommunityReport {
  comment_id: string; // SHA256 of raw GitHub Issue comment body
  issue_number: number;
  room_slug: string;
  hot_score: number;
  vote_count: number;
}

export interface Feed {
  date: string; // YYYY-MM-DD
  generated_at: string; // ISO 8601
  posts: FeedPost[];
  community_reports: CommunityReport[];
}

// Aggregator-internal cache, written alongside feed/<date>.json.
// Never read by clients — holds embeddings so the aggregator avoids
// re-embedding posts it has already seen on previous runs.
export interface FeedCache {
  embeddings: Record<string, number[]>; // post_id → text-embedding-3-small vector
  media_urls: string[]; // all asset_urls seen in feed posts (for media fingerprinting)
}
