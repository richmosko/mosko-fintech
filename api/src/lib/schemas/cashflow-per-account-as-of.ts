// cashflow-per-account-as-of.ts — CLIENT-SIDE Zod mirror of the §2.3.3 per-account drill-down's
// `as_of` input boundary (SELF-254). Frontend-owned NON-server module (ships to the browser).
//
// MIRROR ONLY — the security boundary is Backend's `asOfSchema(maxAsOf)`
// (api/src/lib/server/schemas/asOf.ts), which this file cannot import: browser code cannot
// import `$lib/server/**` (SvelteKit's build-time guard refuses it regardless of `import type`).
// Same posture, hand-copied: real-calendar-date shape, a `.strict()` single-key `{ as_of }`
// object, BOTH bounds inclusive against a caller-supplied ceiling. This mirror exists so a
// hand-edited URL or a manually-typed date degrades to a client-side message BEFORE a request
// fires — the server's own `asOfSchema` re-checks unconditionally regardless (frontend-engineer
// discipline #2: the client check is UX, the server check is the boundary — never looser).
//
// ⚠ NEITHER BOUND IS EMBEDDED HERE, on purpose — mirroring the server file's own "THE CEILING IS
// INJECTED, NEVER EMBEDDED" discipline, extended to the floor too. `CashflowAsOfToggle.svelte`
// receives both `floor` and `max` from `+page.server.ts`'s page data (which itself imports the
// real `AS_OF_FLOOR` and resolves `maxAsOf` from `pfin.fn_server_today()`), so there is exactly
// ONE place either constant is spelled — a second hardcoded copy of `AS_OF_FLOOR` here would be
// the same drift risk `asOf.ts`'s own header warns against for the ceiling.
//
// No `chart_`-style namespace prefix (unlike nav-series-params.ts): cashflowPerAccount.ts's own
// module header records why — this surface's loader takes `asOfRaw` as an ALREADY-EXTRACTED
// single value (`url.searchParams.get('as_of')`), never a raw unfiltered searchParams object, so
// there is no page-scoped blast-radius hazard a namespace would need to fence. This mirror
// follows the same posture: it validates an already-isolated `{ as_of }` object.

import { z } from 'zod';

/** Real-calendar-date guard (rejects e.g. 2026-02-31) — same idiom as every other client-side
 *  isoDate() in this tree (nav-series-params.ts / schemas/account.ts's own local copies). */
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
 * `cashflowPerAccountAsOfSchema(floor, maxAsOf)` — same shape and posture as the server's
 * `asOfSchema(maxAsOf)`: `as_of` optional, `.strict()`, both bounds inclusive against the
 * request's already-resolved floor/ceiling (never a client-derived `new Date()`).
 */
export function cashflowPerAccountAsOfSchema(floor: string, maxAsOf: string) {
	return z
		.object({ as_of: isoDate().optional() })
		.strict()
		.superRefine((val, ctx) => {
			if (val.as_of === undefined) return;
			if (val.as_of < floor) {
				ctx.addIssue({
					code: z.ZodIssueCode.custom,
					path: ['as_of'],
					message: `Date cannot be before ${floor}.`
				});
			}
			if (val.as_of > maxAsOf) {
				ctx.addIssue({
					code: z.ZodIssueCode.custom,
					path: ['as_of'],
					message: 'Date cannot be in the future.'
				});
			}
		});
}
