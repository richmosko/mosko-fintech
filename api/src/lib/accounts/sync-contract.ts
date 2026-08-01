// sync-contract.ts — CLIENT-side mirror of the SELF-317 manual "Sync now" relay contract.
//
// Manual sync is a genuinely client-initiated action (a button press, not server-known at
// render), so it's a `fetch`+JSON relay, NOT a form action (api/CLAUDE.md forms rule). One leg:
//   • POST /api/sync { source_id? } → 202 { status:'accepted', sources:[{source_id, disposition}] }
//     `source_id` PRESENT ⇒ sync that one connection; ABSENT ⇒ "sync all my active sources"
//     (the Frontend only ever sends the present-form per-connection case in V1).
//
// This is the client mirror of Backend's server-side `.strict()` body schema
// (`src/routes/api/sync/+server.ts` — Lock 14 mod #1 mass-assignment fence). The client check is
// UX fast-feedback; the SERVER check is the security boundary. Backend owns the source of truth —
// when the server schema changes, this mirror follows it (never looser). Ships to the browser
// (non-`server` lib surface): holds NO secret, no tenant id — `users_id` is derived server-side
// from the session and is NEVER on the wire.

import { z } from 'zod';

/** source_id = pfin.linked_source.source_id — a bigint serialized as a decimal string
 *  (SELF-199 convention, same as the reauth contract); NOT a UUID. */
const sourceId = () => z.string().trim().regex(/^\d+$/);

// ── Route ────────────────────────────────────────────────────────────────────────────────
export const SYNC_ROUTE = '/api/sync';

// ── request ──────────────────────────────────────────────────────────────────────────────
// `.strict()` mirrors the server body schema exactly: `source_id` is the ONLY key that may
// leave the browser, and it is optional (absent ⇒ sync-all). No provider, no tenant id, no secret.
export const syncRequestSchema = z.object({ source_id: sourceId().optional() }).strict();
export type SyncRequest = z.infer<typeof syncRequestSchema>;

// ── response (202 Accepted) ──────────────────────────────────────────────────────────────
// A2 return-fast contract (ADR-037 amendment): the 202 carries only per-source DISPOSITION —
// `triggered` (a background sync was started) or `debounced` (a recent trigger is still within
// the worker's 60s window, so this one was folded into it). "accepted" ≠ "succeeded": the real
// outcome lands in the 040/043 sync-state views the UI polls, not in this body.
export const syncDispositionSchema = z.enum(['triggered', 'debounced']);
export type SyncDisposition = z.infer<typeof syncDispositionSchema>;

export const syncResponseSchema = z.object({
	status: z.literal('accepted'),
	sources: z.array(
		z.object({
			source_id: z.string(),
			disposition: syncDispositionSchema
		})
	)
});
export type SyncResponse = z.infer<typeof syncResponseSchema>;
