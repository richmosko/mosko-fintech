// importHash.ts — THE canonical manual↔provider content-hash (SELF-204; ADR-034 Decision 4).
//
// CANONICAL SOURCE OF TRUTH (Location B, F/CTO-ratified 2026-07-27). This file is the ONE
// authoritative copy; `scripts/generate-import-hash-copy.mjs` emits a byte-identical, banner-
// marked copy into `api/src/lib/server/dedup/importHash.ts` for the SvelteKit tier, and a CI
// byte-equality fence (security-scan.yml) fails loudly on any drift. NEVER hand-edit the copy —
// edit HERE and regenerate.
//
// LOAD-BEARING NO-DRIFT MODULE: computed identically on BOTH paths — the SvelteKit manual-entry
// server action AND the workers/provider-sync ingest mapper — and passed into
// fn_create_manual_trans as p_import_hash (the RPC stores it, computes nothing). A divergent
// canonicalization would break manual↔provider dedup detection INVISIBLY (ADR-034 D4), which is
// why it is a single shared source, never copy-pasted. The canonicalization imprints on stored
// import_hash values → a ONE-WAY DOOR (historical rows cannot be re-hashed).
//
// Canonical field-set (ADR-034 D4): account + date + amount + normalized descriptor.
//   account    → String(accountId)                         (integer id, no formatting)
//   date       → ISO YYYY-MM-DD, verbatim (trimmed)         (both tiers already produce this)
//   amount     → amount.toFixed(4)                          (numeric(20,4) scale; collapses
//                                                            54.3 / 54.30 / 54.3000; keeps sign;
//                                                            -0 → "0.0000")
//   descriptor → (vendor + ' ' + description) normalized:   strip control chars → trim →
//                                                            lowercase → collapse whitespace
// Joined with U+001F (unit separator) — control chars are stripped from the descriptor first, so
// the delimiter can never be injected via user text. Digest: SHA-256, hex (Node built-in
// `node:crypto` — no new dependency; both tiers run on Node).

import { createHash } from 'node:crypto';

export interface ImportHashInput {
	/** pfin.account.account_id the row lands in (the hash is account-scoped, ADR-034 D4). */
	accountId: number;
	/** Transaction date as an ISO YYYY-MM-DD string. */
	date: string;
	/** The SIGNED ledger amount (+inflow / −outflow). */
	amount: number;
	/** Free-text vendor/merchant (nullable). */
	vendor: string | null;
	/** Free-text description/memo (nullable). */
	description: string | null;
}

/**
 * Normalize the free-text descriptor to a stable canonical form: concatenate vendor + a single
 * space + description, replace every Unicode control char (incl. the U+001F join delimiter) with
 * a space, trim, lowercase, then collapse internal whitespace runs to a single space.
 */
function normalizeDescriptor(vendor: string | null, description: string | null): string {
	return `${vendor ?? ''} ${description ?? ''}`
		.replace(/\p{Cc}/gu, ' ') // strip control chars (incl. U+001F) → space (no delimiter injection)
		.trim()
		.toLowerCase()
		.replace(/\s+/g, ' ');
}

/**
 * Compute the canonical content hash for a transaction (SELF-204 / ADR-034 D4). Deterministic:
 * the SAME input yields the SAME SHA-256 hex on the manual-entry and provider-sync paths.
 */
export function computeImportHash(input: ImportHashInput): string {
	const canonical = [
		String(input.accountId),
		input.date.trim(),
		input.amount.toFixed(4),
		normalizeDescriptor(input.vendor, input.description)
	].join('\x1f');
	return createHash('sha256').update(canonical, 'utf8').digest('hex');
}
