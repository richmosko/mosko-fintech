// navHistory.ts — server-side Zod schema for the §2.1.2.c NAV-over-time chart's
// URL search-param boundary (SELF-220). Backend-owned server source (ARCH §4.1
// allowlist).
//
// SOURCE OF TRUTH: Frontend mirrors this client-side (Lock 14) — a client-side
// URL-param guard for fast feedback, never the security boundary. `.strict()` is
// the mass-assignment / unknown-param fence (Lock 14 mod #2); every recognized
// param's VALUE is independently validated (the type-confusion fence, Lock 14
// mod #1). The granularity vocabulary is copied VERBATIM from what `062`
// pfin.fn_nav_series (composed by `067`) validates and RAISEs on — see 062's
// CONTRACT block — so the app layer and the DB agree; the DB's RAISE is the
// authoritative backstop, this schema is what turns a bad value into a clean
// 400 instead of a raised Postgres exception surfacing through the RPC.
//
// Every field is INDEPENDENTLY OPTIONAL. Absence is not an error — the +page.
// server.ts load derives a 60-month default window when start/end are absent
// and defaults granularity to 'monthly'. What `.strict()` refuses is an
// UNRECOGNIZED key or a recognized key holding a value that doesn't parse —
// not the absence of a key.

import { z } from 'zod';

/**
 * p_granularity — VERBATIM from `062`'s validated vocabulary (RAISE on anything
 * else), reused unchanged by `067`. Not sourced from a DB CHECK constraint
 * (062/067 validate in PL/pgSQL, not via a table CHECK) — copied from the
 * migration's own CONTRACT block instead, which is this vocabulary's
 * authoritative statement.
 */
export const NAV_HISTORY_GRANULARITIES = ['monthly', 'weekly', 'daily'] as const;
export type NavHistoryGranularity = (typeof NAV_HISTORY_GRANULARITIES)[number];

/**
 * Real-calendar-date guard (rejects 2026-02-31 etc.) — same idiom as
 * account.ts's `isoDate()`, duplicated rather than imported: that helper is
 * module-private there, and two small identical validators are cheaper to
 * keep in sync (both copy the DB's own real-date semantics, which don't
 * change) than a shared-helper extraction would be to introduce here for a
 * four-line regex+refine.
 */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/**
 * The chart's query-param boundary: `?granularity=monthly&start=YYYY-MM-DD&end=YYYY-MM-DD`,
 * all optional, `.strict()` against everything else. Validated from
 * `Object.fromEntries(url.searchParams)` in +page.server.ts — every value
 * SvelteKit hands back from `URLSearchParams` is already a string, so there is
 * no numeric/boolean coercion to defend against here the way account.ts's
 * `currencyAmount()` must for POSTed form data.
 */
export const navHistoryParamsSchema = z
	.object({
		granularity: z.enum(NAV_HISTORY_GRANULARITIES).optional(),
		start: isoDate().optional(),
		end: isoDate().optional()
	})
	.strict();

export type NavHistoryParams = z.infer<typeof navHistoryParamsSchema>;
