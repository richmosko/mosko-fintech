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
//
// ⚠ NAMESPACED, F/CTO-RATIFIED 2026-08-13 (Sec's param-fence finding, option A). The prior
// shape strict-parsed `Object.fromEntries(url.searchParams)` on `/` — the WHOLE page's query
// string, not just the chart's three keys. Any unrelated param on that URL (a tracker's
// `?utm_source=`, anything) tripped `.strict()`'s unknown-key rejection and disabled the
// chart — a page-scoped BLAST RADIUS for what was designed to be chart-scoped. The fix is a
// namespace, not a looser schema: every chart param is prefixed `chart_`, and validation is
// two mechanical steps — (1) extract ONLY the `chart_`-prefixed subset of the URL's params
// (2) `.strict()`-parse THAT subset. A key OUTSIDE the namespace is simply not chart input and
// is never presented to the schema at all (correctly excluded, not filtered-then-hidden); a
// key INSIDE the namespace that the schema doesn't recognize (`chart_bogus`) still reaches
// `.strict()` and is still REJECTED — the fence is exactly as strict as before, only its
// domain narrowed to what the chart actually owns. Server, client mirror, and every `goto()`
// URL write in NavHistoryChart.svelte all moved to this same prefix together — see that
// component and its server counterpart (Backend's +page.server.ts) for the paired halves.
// ⚠ NOT "pick expected keys then parse" — that pattern (cherry-picking known key names before
// `.strict()` sees the object) would hide an unknown key WITHIN the namespace from the fence
// entirely, defeating it. This extracts by NAMESPACE MEMBERSHIP (a structural prefix test),
// never by an allowlist of specific expected keys — every namespaced key, known or not,
// reaches `.strict()` undiminished.

import { z } from 'zod';

export const NAV_SERIES_GRANULARITIES = ['monthly', 'weekly', 'daily'] as const;
export type NavSeriesGranularity = (typeof NAV_SERIES_GRANULARITIES)[number];

/** The chart's URL query-param namespace prefix. Every param this surface reads or writes
 * carries it; nothing outside it is the chart's input. Shared value with Backend's server-side
 * schema (coordinated, not auto-synced — the server/client file split forbids a shared module
 * per api/CLAUDE.md's file-glob rule, same reason nav-series.ts's row type and vocabulary are
 * duplicated-by-coordination rather than imported across the boundary). */
export const NAV_SERIES_PARAM_PREFIX = 'chart_';

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
 * The chart's URL search-param contract: `?chart_granularity=&chart_start=&chart_end=`. All
 * three are OPTIONAL at the URL level — absent means the surface's default 60-month-monthly
 * window, which is SERVER-derived (see temp/frontend-self220.md's role-boundary note: a client
 * `new Date()` default here would be exactly the clock-skew hazard ADR-043 exists to avoid,
 * matching how `+page.server.ts` already derives the §2.1.1 headline's asOf via
 * serverTodayAsOf() rather than a browser clock). This schema's job is narrower: IF the
 * params are present (a shared/back-button URL, or this surface's own granularity-toggle /
 * zoom navigation), they must be WELL-FORMED and non-inverted before anything builds a
 * navigation or a request off them. `.strict()` here is scoped to the ALREADY-NAMESPACE-
 * FILTERED object `parseNavSeriesParams` builds below — never called directly against a raw,
 * unfiltered `URLSearchParams`-derived object (that would reintroduce the page-scoped blast
 * radius this namespace exists to close).
 */
export const navSeriesParamsSchema = z
	.object({
		chart_granularity: z.enum(NAV_SERIES_GRANULARITIES).optional(),
		chart_start: isoDate().optional(),
		chart_end: isoDate().optional()
	})
	.strict()
	.refine((v) => !(v.chart_start && v.chart_end) || v.chart_start <= v.chart_end, {
		message: 'Start date must not be after end date.',
		path: ['chart_start']
	});

export type NavSeriesParams = z.infer<typeof navSeriesParamsSchema>;

/**
 * Extracts the `chart_`-namespaced subset of a URL's search params, by prefix membership —
 * a structural test, never a list of specific expected key names (that would be the forbidden
 * "pick-then-parse" shape: cherry-picking known keys before `.strict()` sees the object hides
 * an unrecognized key WITHIN the namespace from the fence). Every `chart_*` key survives this
 * step, known or not, and is handed to `.strict()` undiminished; every non-`chart_*` key is
 * excluded because it is simply not this surface's input, not because it was filtered away
 * after being considered.
 */
function extractNamespacedParams(search: URLSearchParams, prefix: string): Record<string, string> {
	const result: Record<string, string> = {};
	for (const [key, value] of search) {
		if (key.startsWith(prefix)) result[key] = value;
	}
	return result;
}

/**
 * Parses a chart URL's search params into a validated {@link NavSeriesParams}, degrading
 * unparseable/invalid input to `{}` (all-absent) rather than throwing — a malformed URL falls
 * back to the surface's default window instead of breaking the page. Never silently "fixes" a
 * bad value into a different valid one (e.g. clamping an inverted range): absent is the only
 * degrade target, so a bad URL is visibly the default, not a guessed correction.
 */
export function parseNavSeriesParams(search: URLSearchParams): NavSeriesParams {
	const raw = extractNamespacedParams(search, NAV_SERIES_PARAM_PREFIX);
	const result = navSeriesParamsSchema.safeParse(raw);
	return result.success ? result.data : {};
}
