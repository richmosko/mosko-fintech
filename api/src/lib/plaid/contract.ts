// contract.ts — CLIENT-side view of the SELF-197 Plaid relay contract (leg-1 / leg-2).
//
// SCOPE: this is the browser's assumed contract for the two api/src relay routes that
// SELF-197 will implement. Backend owns the source of truth (api/CLAUDE.md: "API
// contracts are Backend's source of truth"); this file is the mirror the client builds
// against so leg-1/leg-2 can be implemented to match. It carries NO Plaid secret and NO
// server logic — it ships to the browser (non-`server` lib surface).
//
// SECURITY POSTURE (SELF-198 AC #5 — hard V1-SHIP-BLOCK):
//   • The client holds ONLY the short-TTL `link_token` (leg-1 output) and the
//     `public_token` (Plaid onSuccess output → leg-2 input).
//   • `access_token` and the Plaid client secret NEVER cross into browser code. They
//     live exclusively behind the worker/relay (the whole worker-owns-exchange design).
//   • The leg-2 request carries ONLY `{ public_token, metadata? }`. `ownerUserId` is
//     derived server-side from the session (SC3-C1) — the client NEVER sends a tenant
//     identifier. `exchangeRequestSchema.strict()` is the mass-assignment fence that
//     proves no extra key (least of all a token/secret) rides along.

import { z } from 'zod';

// ── Relay route paths (assumed; confirm with Backend at SELF-197) ────────────────────
/** Leg 1 — GET → `{ link_token, expiration }`. Short-TTL token; client-held. */
export const PLAID_LINK_TOKEN_ROUTE = '/api/plaid/link-token';
/** Leg 2 — POST `{ public_token, metadata? }` → `{ success, accounts }`. */
export const PLAID_EXCHANGE_ROUTE = '/api/plaid/exchange';

// ── Leg 1 response ───────────────────────────────────────────────────────────────────
// Own-relay response; parsed defensively (unknown keys stripped, not rejected — response
// shapes may grow server-side without breaking the client). `.strict()` is reserved for
// the REQUEST fence below, where "no extra key leaves the browser" is the security goal.
export const linkTokenResponseSchema = z.object({
	link_token: z.string().min(1),
	/** ISO-8601 expiry Plaid returns alongside the link_token (TTL ≤ 4h). */
	expiration: z.string().min(1)
});
export type LinkTokenResponse = z.infer<typeof linkTokenResponseSchema>;

// ── Leg 2 request (client → relay) ─────────────────────────────────────────────────────
// `.strict()` mass-assignment fence: the ONLY keys the browser may send. No tenant id,
// no access_token, no secret. Mirrors Backend's server-side `.strict()` posture (Lock 14
// Sec mod #1/#2). `metadata` is Plaid Link's own onSuccess metadata (institution +
// selected-account refs) — non-secret, useful to the relay for account naming.
export const exchangeRequestSchema = z
	.object({
		public_token: z.string().min(1),
		metadata: z.unknown().optional()
	})
	.strict();
export type ExchangeRequest = z.infer<typeof exchangeRequestSchema>;

// ── Leg 2 response ───────────────────────────────────────────────────────────────────
// ASSUMED account-ref shape (re-scoped SELF-197: relay returns success + account-refs,
// NOT a plaid_items persist confirmation). Fields beyond `account_id` are best-effort;
// confirm the canonical ref shape with Backend. Parsed leniently (unknown keys stripped).
export const accountRefSchema = z.object({
	account_id: z.string().min(1),
	name: z.string().optional(),
	mask: z.string().nullish(),
	type: z.string().optional(),
	subtype: z.string().nullish()
});
export type AccountRef = z.infer<typeof accountRefSchema>;

export const exchangeResponseSchema = z.object({
	success: z.literal(true),
	accounts: z.array(accountRefSchema)
});
export type ExchangeResponse = z.infer<typeof exchangeResponseSchema>;
