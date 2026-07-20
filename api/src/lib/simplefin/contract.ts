// contract.ts — CLIENT-side view of the OQ-2 SimpleFIN connect relay contract (leg-S).
//
// SCOPE: the browser's mirror of the single api/src relay route Backend shipped for the
// in-app SimpleFIN connect flow (`POST /api/simplefin/connect`). Backend owns the source
// of truth (api/CLAUDE.md: "API contracts are Backend's source of truth"); this file is
// the mirror the client builds against. It carries NO SimpleFIN credential and NO server
// logic — it ships to the browser (non-`server` lib surface).
//
// STRUCTURAL ASYMMETRY vs Plaid (temp/oq2-connect-seam-design.md §1): Plaid needs a
// server pre-mint (leg-1 link_token) before the user acts, so it is TWO legs. SimpleFIN
// needs no pre-step — the user obtains a one-time setup token from the SimpleFIN Bridge
// out-of-band and pastes it, so it is ONE leg (paste → claim → Vault admit). There is no
// SimpleFIN link-token analogue; hence one route, not two.
//
// SECURITY POSTURE (OQ-2 §4 — credential-class handling):
//   • The SETUP TOKEN (a base64 claim string) is an SD-03-class bearer credential (RT-02),
//     handled exactly like the Plaid `public_token`: held transiently in the form field,
//     posted ONCE over the session-authed relay body (never a URL query), never rendered
//     back, never logged, never persisted (no localStorage).
//   • The Access URL the token claims into NEVER crosses back to the browser — it lives
//     only in vault.secrets, server-side. No credential is ever in this contract.
//   • The request carries ONLY { setup_token, institutionName? }. `ownerUserId` is derived
//     server-side from the session (SC3-C1) — the client NEVER sends a tenant identifier.
//     `connectRequestSchema.strict()` is the mass-assignment fence proving no extra key
//     (least of all a tenant id or a credential) rides along.

import { z } from 'zod';

// ── Relay route path (mirrors the shipped /api/plaid/* convention) ───────────────────
/** Leg-S — POST { setup_token, institutionName? } → { success, accounts }. */
export const SIMPLEFIN_CONNECT_ROUTE = '/api/simplefin/connect';

// ── Request (client → relay) ─────────────────────────────────────────────────────────
// `.strict()` mass-assignment fence: the ONLY keys the browser may send. No tenant id, no
// credential beyond the setup token itself. Mirrors Backend's server-side `.strict()`
// posture VERBATIM (api/src/routes/api/simplefin/connect/+server.ts `connectBodySchema`):
// `setup_token: z.string().min(1)` + `institutionName: z.string().min(1).optional()`.
// The client check is UX (fast feedback); the server check is the security boundary.
export const connectRequestSchema = z
	.object({
		setup_token: z.string().min(1),
		institutionName: z.string().min(1).optional()
	})
	.strict();
export type ConnectRequest = z.infer<typeof connectRequestSchema>;

// ── Response ─────────────────────────────────────────────────────────────────────────
// Identical shape to the Plaid exchange response (OQ-2 §3c — no new mapping leg). Parsed
// leniently (unknown keys stripped, not rejected — response shapes may grow server-side
// without breaking the client). SimpleFIN refs carry `type: 'unknown'` (no provider type
// signal); the shared attributes flow lets the user classify each account, so `unknown`
// simply means the type field starts unselected rather than pre-filled — a UX nicety.
export const accountRefSchema = z.object({
	account_id: z.string().min(1),
	name: z.string().optional(),
	type: z.string().optional(),
	subtype: z.string().nullish(),
	currency: z.string().optional()
});
export type AccountRef = z.infer<typeof accountRefSchema>;

export const connectResponseSchema = z.object({
	success: z.literal(true),
	accounts: z.array(accountRefSchema)
});
export type ConnectResponse = z.infer<typeof connectResponseSchema>;
