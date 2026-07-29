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
// Account-ref shape is the CANONICAL provider-blind `AccountRef` (SELF-199) — the SAME type
// the Plaid path converges on, re-exported here so existing `$lib/simplefin/contract`
// importers are unaffected. SimpleFIN responses omit the Plaid-only `mask` and carry
// `type: 'unknown'` (no provider type signal), so the attributes flow simply starts each
// account's type UNSELECTED (recommendAccountType → undefined) rather than pre-filled — a UX
// nicety, not a gap. Parsed leniently (unknown keys stripped, not rejected).
export { accountRefSchema, type AccountRef } from '$lib/accounts/account-ref';
import { accountRefSchema } from '$lib/accounts/account-ref';

// `linked_source_id` (SELF-199 seam): the connect relay returns it alongside `accounts` so the
// attributes step can carry it to the persist action. It is `pfin.linked_source.source_id` —
// a **bigint serialized as a decimal string** (e.g. "42"), NOT a UUID. Backend confirmed the
// relay always returns it, so it is required here (numeric-string shape mirrors the envelope).
export const connectResponseSchema = z.object({
	success: z.literal(true),
	linked_source_id: z.string().regex(/^\d+$/),
	accounts: z.array(accountRefSchema)
});
export type ConnectResponse = z.infer<typeof connectResponseSchema>;
