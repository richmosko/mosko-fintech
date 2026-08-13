// nav-series-params.ts — CLIENT-SIDE Zod mirror of the §2.1.2.d NAV-chart query-param input
// boundary (SELF-220). MIRROR ONLY: the security boundary lives server-side in
// +page.server.ts (Backend), which must validate these same params with its own .strict()
// schema before they reach pfin.fn_nav_series_inflation_adjusted (067) — this mirror exists
// so a malformed or hand-edited URL degrades to the surface's default before a request ever
// fires, not because the client check is trusted for anything (api/CLAUDE.md: client check =
// UX fast feedback; server check is the security boundary).
//
// Vocabulary is copied VERBATIM from 062's validated parameter set — 067 adds no validation
// of its own (the granularity + date-bounds checks live in 062 and RAISE there; re-validating
// here would put the vocabulary in a second place, the same drift 066's period_was_due column
// exists to prevent one level down). p_granularity ∈ {'monthly','weekly','daily'}; NULL or
// inverted date bounds are rejected by 062. This schema mirrors that posture only — same
// enum, same well-formed/non-inverted requirement — never looser than what 062 (and whatever
// server-side schema Backend authors) will accept.

import { z } from 'zod';

export const NAV_SERIES_GRANULARITIES = ['monthly', 'weekly', 'daily'] as const;
export type NavSeriesGranularity = (typeof NAV_SERIES_GRANULARITIES)[number];

/**
 * Real-calendar-date guard (rejects e.g. 2026-02-31). Local copy of the same shape as
 * $lib/schemas/account.ts's isoDate() — that file defines its own local (unexported) copy
 * rather than a shared module, so this mirrors the existing convention rather than
 * introducing a new shared one unbidden.
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
 * The chart's URL search-param contract: `?granularity=&start=&end=`. All three are
 * OPTIONAL at the URL level — absent means the surface's default 60-month-monthly window,
 * which is SERVER-derived (see temp/frontend-self220.md's role-boundary note: a client
 * `new Date()` default here would be exactly the clock-skew hazard ADR-043 exists to avoid,
 * matching how `+page.server.ts` already derives the §2.1.1 headline's asOf via
 * serverTodayAsOf() rather than a browser clock). This schema's job is narrower: IF the
 * params are present (a shared/back-button URL, or this surface's own granularity-toggle /
 * zoom navigation), they must be WELL-FORMED and non-inverted before anything builds a
 * navigation or a request off them.
 */
export const navSeriesParamsSchema = z
	.object({
		granularity: z.enum(NAV_SERIES_GRANULARITIES).optional(),
		start: isoDate().optional(),
		end: isoDate().optional()
	})
	.strict()
	.refine((v) => !(v.start && v.end) || v.start <= v.end, {
		message: 'Start date must not be after end date.',
		path: ['start']
	});

export type NavSeriesParams = z.infer<typeof navSeriesParamsSchema>;

/**
 * Parses a chart URL's search params into a validated {@link NavSeriesParams}, degrading
 * unparseable/invalid input to `{}` (all-absent) rather than throwing — a malformed URL falls
 * back to the surface's default window instead of breaking the page. Never silently "fixes" a
 * bad value into a different valid one (e.g. clamping an inverted range): absent is the only
 * degrade target, so a bad URL is visibly the default, not a guessed correction.
 */
export function parseNavSeriesParams(search: URLSearchParams): NavSeriesParams {
	const raw = {
		granularity: search.get('granularity') ?? undefined,
		start: search.get('start') ?? undefined,
		end: search.get('end') ?? undefined
	};
	const result = navSeriesParamsSchema.safeParse(raw);
	return result.success ? result.data : {};
}
