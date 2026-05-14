/**
 * Wire format for all content written to MaroMushii/Khorshid-Social GitHub Issues.
 *
 * Every GitHub Issue comment body is valid JSON that parses to IssueCommentBody.
 *
 * Channel Issues (channel-<slug>-<date>) contain only PlaintextPayload — votes on
 * that day's Telegram news posts. No comment threads in channel Issues.
 *
 * Room Issues (room-<slug>-<date>) contain both: SocialPayloadWrapper (encrypted
 * posts and comments) and PlaintextPayload (votes and flags on room comments).
 *
 * Issue naming: "channel-<slug>-<YYYY-MM-DD>" or "room-<slug>-<YYYY-MM-DD>"
 * One Issue per context per day. All social content for a given channel/room on a
 * given day lives in one Issue's comment thread.
 *
 * ## ID conventions
 *
 * `post_id` and `target_id` share the same addressing scheme:
 *
 *   - Telegram channel post:  "<channel_username>/<post_id>" (from mirror snapshot)
 *   - Room post or comment:   SHA256 hex of the raw GitHub Issue comment body string
 *
 * The second form is fully content-addressed: the aggregator can compute any ID by
 * hashing the raw comment body — no decryption needed.
 *
 * ## Encryption
 *
 * All encrypted payloads use AES-256-GCM.
 *   - Public rooms:  hardcoded per-room key shipped in the app binary
 *   - Private rooms: key from the invite bundle { owner, repo, pat, key, name }
 */

export const SOCIAL_SCHEMA_VERSION = 1 as const;

// ---------------------------------------------------------------------------
// Encrypted envelope
// ---------------------------------------------------------------------------

/**
 * Appears in a GitHub Issue comment body when the payload is encrypted.
 * The ciphertext decrypts to JSON that parses to DecryptedPayload.
 */
export interface SocialPayloadWrapper {
  /** Schema version — always 1 for this format. */
  v: typeof SOCIAL_SCHEMA_VERSION;
  /** Base64-encoded 12-byte AES-GCM nonce. */
  n: string;
  /** Base64-encoded AES-256-GCM ciphertext of the DecryptedPayload JSON string. */
  c: string;
}

// ---------------------------------------------------------------------------
// Decrypted payload types (inside the wrapper's ciphertext)
// ---------------------------------------------------------------------------

/**
 * A top-level post in a room (not a reply to any specific comment).
 * Only used in rooms, never in channel discussions (channels surface Telegram
 * posts from the mirror instead).
 */
export interface PostPayload {
  type: "post";
  body: string;
  /** Unix timestamp in milliseconds. */
  sent_at: number;
}

/**
 * A comment on a room post. Only used in room Issues — channel Issues contain
 * only plaintext votes, not comment threads.
 *
 * `post_id` is the SHA256 hex of the room post's raw GitHub Issue comment body
 * (see file-level ID conventions). `reply_to` is the SHA256 hex of the parent
 * comment's raw body, or null when replying directly to the post.
 */
export interface CommentPayload {
  type: "comment";
  post_id: string;
  reply_to: string | null;
  body: string;
  /** Unix timestamp in milliseconds. */
  sent_at: number;
}

export type DecryptedPayload = PostPayload | CommentPayload;

// ---------------------------------------------------------------------------
// Plaintext signal types (NOT encrypted — aggregator reads without decryption)
// ---------------------------------------------------------------------------

export type VoteSignal = "up" | "important";

/**
 * An upvote or importance signal on a post or comment.
 *
 * `target_id` identifies what is being voted on (see file-level ID conventions).
 *
 * `vote_id` is a commitment hash: SHA256 hex of (raw_privkey_bytes || utf8(target_id)).
 * Same private key + same target always produces the same vote_id, which enables
 * server-side deduplication without exposing the voter's public key or allowing
 * cross-post vote correlation.
 */
export interface VotePayload {
  type: "vote";
  target_id: string;
  signal: VoteSignal;
  vote_id: string;
  /** Unix timestamp in milliseconds. */
  sent_at: number;
}

/**
 * A content flag on a post or comment. Threshold-based local content hiding
 * uses these; no individual flag is surfaced to other users.
 *
 * `vote_id` uses the same commitment scheme as VotePayload.
 */
export interface FlagPayload {
  type: "flag";
  target_id: string;
  vote_id: string;
  /** Unix timestamp in milliseconds. */
  sent_at: number;
}

export type PlaintextPayload = VotePayload | FlagPayload;

// ---------------------------------------------------------------------------
// Top-level union: what actually appears in a GitHub Issue comment body
// ---------------------------------------------------------------------------

export type IssueCommentBody = SocialPayloadWrapper | PlaintextPayload;

// ---------------------------------------------------------------------------
// Issue naming convention
// ---------------------------------------------------------------------------

/**
 * Template-literal union that documents the Issue title convention.
 * One Issue per context per day in MaroMushii/Khorshid-Social.
 *   channel-<slug>-<YYYY-MM-DD>  — discussion thread for a channel's news posts
 *   room-<slug>-<YYYY-MM-DD>     — post + comment thread for a room
 */
export type IssueContext =
  | `channel-${string}-${string}`
  | `room-${string}-${string}`;
