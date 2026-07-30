// reauth-contract.ts — CLIENT-side view of the SELF-207 Phase-2 re-auth relay contract.
//
// Re-auth is CONNECT-flow-shaped, not a form action (ADR-037 AC #4): the user repairs a
// broken connection the same way they made it. Two provider-agnostic relay legs (Backend
// resolves the provider server-side from the linked_source; the client never sends it):
//   • start    POST { linked_source_id } → discriminated handoff telling the client HOW to
//              re-collect the credential (Plaid = open Link in update mode; SimpleFIN = paste
//              a fresh Bridge setup token).
//   • complete POST { linked_source_id, setup_token? } → { connection_status, rotated }.
//
// Ships to the browser (non-`server` lib surface): NO Plaid secret / access_token / Access URL
// — the only credential-class token the client ever holds is the short-TTL Plaid `link_token`
// (update mode) and the SimpleFIN setup token the user pastes (posted once to complete, then
// cleared). Backend owns the source of truth; this is the mirror the client builds against.

import { z } from 'zod';

/** linked_source_id = pfin.linked_source.source_id — a bigint serialized as a decimal string
 *  (same convention as SELF-199); NOT a UUID. */
const linkedSourceId = () => z.string().trim().regex(/^\d+$/);

// ── Routes ─────────────────────────────────────────────────────────────────────────────
export const REAUTH_START_ROUTE = '/api/reauth/start';
export const REAUTH_COMPLETE_ROUTE = '/api/reauth/complete';

// ── start: request ─────────────────────────────────────────────────────────────────────
// `.strict()` mass-assignment fence: the ONLY key the browser sends. Provider is resolved
// server-side from the source; the client never sends a provider or a tenant id.
export const reauthStartRequestSchema = z.object({ linked_source_id: linkedSourceId() }).strict();
export type ReauthStartRequest = z.infer<typeof reauthStartRequestSchema>;

// ── start: response (discriminated on `kind`) ──────────────────────────────────────────
// Parsed leniently within each arm (unknown keys stripped) — a provider arm may grow
// server-side without breaking the client. `link_token` is the short-TTL Plaid update-mode
// token; the recollect arm carries no secret (the client shows its paste field).
export const reauthStartResponseSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('link_update'), link_token: z.string().min(1) }),
	z.object({ kind: z.literal('recollect_credential') })
]);
export type ReauthStartResponse = z.infer<typeof reauthStartResponseSchema>;

// ── complete: request ──────────────────────────────────────────────────────────────────
// `.strict()`. `setup_token` is REQUIRED for the SimpleFIN re-collect path and ABSENT for
// Plaid (update-mode success carries no public_token — the server already has what it needs).
// The token is SD-03 credential-class: posted once over the session-authed body, never a URL
// query, never rendered/logged, and cleared from component state the instant it is sent.
export const reauthCompleteRequestSchema = z
	.object({
		linked_source_id: linkedSourceId(),
		setup_token: z.string().min(1).optional()
	})
	.strict();
export type ReauthCompleteRequest = z.infer<typeof reauthCompleteRequestSchema>;

// ── complete: response ─────────────────────────────────────────────────────────────────
// On success the connection is repaired (server returns 'healthy'); `rotated` reports whether
// the stored credential was rotated (Plaid update-mode = false; SimpleFIN re-claim = true).
export const reauthCompleteResponseSchema = z.object({
	connection_status: z.string().min(1),
	rotated: z.boolean()
});
export type ReauthCompleteResponse = z.infer<typeof reauthCompleteResponseSchema>;
