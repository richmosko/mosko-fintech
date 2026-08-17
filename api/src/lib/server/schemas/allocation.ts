// allocation.ts — server-side Zod schema + as-of resolution for the §2.2.2 / §2.2.3 allocation
// backends (SELF-238 AC8 / SELF-240 AC6 — identical clauses, one shared schema). Backend-owned
// server surface (ARCH §4.1 allowlist).
//
// Lock-14 READ-path fence for these two surfaces' one client-supplied parameter, `as_of`:
//   (a) Zod-typed, parse-don't-coerce real-calendar-date validation (`isoDate()`, same idiom as
//       account.ts / nav-series-params.ts — kept as a local unexported copy per that file's own
//       stated convention, not extracted into a shared module).
//   (b) `.strict()` — an explicit single-field allowlist; any other key is rejected.
//   (c) `resolveAllocationAsOf` is the ONLY place either surface's query module may obtain a
//       `ZoneResolvedAsOf` from a validated param — it calls `userSuppliedAsOf` (the asOf.ts
//       factory), never a cast, so the branded-type containment invariant
//       (asOfBrand.invariant.test.ts) stays true.
//
// ⚠ NAMESPACE, NOT SOLVED HERE. This schema validates an ALREADY-ISOLATED `{ as_of }` object —
// it must NOT be called against a raw, unfiltered `Object.fromEntries(url.searchParams)` from a
// page that may carry OTHER, unrelated params: `.strict()` would then reject the whole request
// on a stray param this surface doesn't own, the EXACT page-scoped blast-radius bug
// nav-series-params.ts's own header documents and fixes with a `chart_`-style namespace prefix
// (F/CTO-ratified 2026-08-13). Whoever wires this schema into an actual route/page — no such
// route exists yet as of SELF-238/240 (backend-only tickets) — MUST either isolate `as_of` by
// namespace (coordinated with Frontend, mirroring nav-series-params' precedent) or confirm the
// route carries no other params ever. Not deciding that here, on purpose: it is a routing-layer
// choice that depends on a page this ticket does not build.

import { z } from 'zod';
import { serverTodayAsOf, userSuppliedAsOf, type ZoneResolvedAsOf } from '$lib/server/time/asOf';

/** Real-calendar-date guard (rejects e.g. 2026-02-31) — same idiom as account.ts's `isoDate()`
 *  and nav-series-params.ts's own local copy. */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/** `as_of` is OPTIONAL — absence resolves to today (server clock), per `resolveAllocationAsOf`
 *  below. `.strict()` rejects any other key. */
export const allocationAsOfSchema = z.object({ as_of: isoDate().optional() }).strict();

export type AllocationAsOfParams = z.infer<typeof allocationAsOfSchema>;

/**
 * The one function that turns a VALIDATED `AllocationAsOfParams` into the `ZoneResolvedAsOf`
 * both allocation query modules require. Absent `as_of` → `serverTodayAsOf()` (today, from the
 * server clock — the V1 default every other read surface uses); present → `userSuppliedAsOf`
 * (UTC-resolved — see that factory's own doc for why). Never called on unvalidated input: the
 * type parameter is `AllocationAsOfParams`, produced only by `allocationAsOfSchema.parse` /
 * `.safeParse`, so a caller cannot skip validation and still compile.
 */
export function resolveAllocationAsOf(params: AllocationAsOfParams): ZoneResolvedAsOf {
	return params.as_of ? userSuppliedAsOf(params.as_of) : serverTodayAsOf();
}
