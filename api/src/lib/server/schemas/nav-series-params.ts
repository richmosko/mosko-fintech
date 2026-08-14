// nav-series-params.ts — server-side Zod schema for the §2.1.2.d NAV-over-time
// chart's URL search-param boundary (SELF-220). Backend-owned server source
// (ARCH §4.1 allowlist). THE SECURITY BOUNDARY — Frontend's
// $lib/schemas/nav-series-params.ts is a client-side MIRROR ONLY (fast
// feedback; api/CLAUDE.md: "client check is UX fast feedback; server check is
// the security boundary"). Field names and the vocabulary below are
// coordinated with Frontend directly and MUST stay in lockstep — this schema
// must be AT LEAST as strict as the client mirror, never looser.
//
// `.strict()` is the mass-assignment / unknown-param fence (Lock 14 mod #2);
// every recognized param's VALUE is independently validated (the
// type-confusion fence, Lock 14 mod #1).
//
// ⚠ NAMESPACED, F/CTO-RATIFIED 2026-08-13 (Sec's param-fence finding, option
// A; mirrors Frontend's $lib/schemas/nav-series-params.ts field-for-field —
// read that file's header for the full incident writeup). The PRIOR shape
// strict-parsed `Object.fromEntries(url.searchParams)` on `/` — the WHOLE
// page's query string, not just the chart's three keys. Any unrelated param
// on that URL (a tracker's `?utm_source=`, anything) tripped `.strict()`'s
// unknown-key rejection and disabled the chart — a PAGE-scoped blast radius
// for what was designed to be CHART-scoped (the same "chart-scoped, page
// survives" invariant the earlier fail-hard-vs-fail-soft ruling already
// established for a DIFFERENT axis of this same surface). The fix is a
// namespace, not a looser schema: every chart param is prefixed `chart_`,
// and validation is two mechanical steps — (1) extract ONLY the
// `chart_`-prefixed subset of the URL's params (`extractNamespacedParams`
// below) (2) `.strict()`-parse THAT subset. A key OUTSIDE the namespace is
// simply not chart input and is never presented to the schema at all
// (correctly excluded, not filtered-then-hidden); a key INSIDE the namespace
// the schema doesn't recognize (`chart_bogus`) still reaches `.strict()` and
// is still REJECTED — the fence is exactly as strict as before, only its
// domain narrowed to what the chart actually owns.
//
// ⚠ NOT "pick expected keys then parse" — that pattern (cherry-picking known
// key names before `.strict()` sees the object) would hide an unknown key
// WITHIN the namespace from the fence entirely, defeating it. This extracts
// by NAMESPACE MEMBERSHIP (a structural prefix test), never by an allowlist
// of specific expected keys — every namespaced key, known or not, reaches
// `.strict()` undiminished. See `extractNamespacedParams`.
//
// Granularity vocabulary is IMPORTED from $lib/nav-series.ts (Frontend-owned,
// browser-safe — server code may import a non-server module, just not the
// reverse) rather than re-declared here: that file already carries the
// canonical `NAV_SERIES_GRANULARITIES`, copied VERBATIM from 062's validated
// parameter set (067 adds no validation of its own — see that file's own
// header). A THIRD independent declaration of this three-value list was the
// wrong thing to add; importing the existing one is the anti-drift move,
// matching account.ts's own precedent of importing shared value-sets from a
// single canonical module rather than re-typing them per consumer. The
// `chart_` PREFIX ITSELF is coordinated with, not imported from, Frontend's
// client mirror — the server/client file-glob split (api/CLAUDE.md) forbids
// a shared module here, the same reason the row type and vocabulary above
// are duplicated-by-coordination across that specific boundary.

import { z } from 'zod';
import { NAV_SERIES_GRANULARITIES } from '$lib/nav-series';

/** The chart's URL query-param namespace prefix. Coordinated value with
 * Frontend's `NAV_SERIES_PARAM_PREFIX` — must match exactly. */
export const NAV_SERIES_PARAM_PREFIX = 'chart_';

/**
 * Real-calendar-date guard (rejects e.g. 2026-02-31) — same idiom as
 * account.ts's `isoDate()` and Frontend's client-mirror copy. A small,
 * stable four-line validator; kept as a local unexported copy here rather
 * than extracted into a shared module, matching the existing convention
 * (account.ts's own isoDate() is likewise module-private).
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
 * The chart's query-param boundary: `?chart_granularity=&chart_start=&chart_end=`,
 * all INDEPENDENTLY OPTIONAL — absence is not an error (+page.server.ts
 * derives the 60-month-monthly default window when chart_start/chart_end are
 * absent). `.strict()` against everything else — but ONLY within the already
 * namespace-filtered object `extractNamespacedParams` builds below. This
 * schema must NEVER be called directly against a raw, unfiltered
 * `Object.fromEntries(url.searchParams)` — that would reintroduce the
 * page-scoped blast radius the namespace exists to close. The inverted-range
 * refine mirrors Frontend's client-side schema exactly (same message, same
 * `path: ['chart_start']`) so a caller sees the identical complaint
 * whichever side catches it first.
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
 * Extracts the `chart_`-namespaced subset of a URL's search params, by
 * PREFIX MEMBERSHIP — a structural test, never a list of specific expected
 * key names (that would be the forbidden "pick-then-parse" shape:
 * cherry-picking known keys before `.strict()` sees the object hides an
 * unrecognized key WITHIN the namespace from the fence). Every `chart_*` key
 * survives this step, known or not, and is handed to `.strict()`
 * undiminished; every non-`chart_*` key is excluded because it is simply not
 * this surface's input, not because it was filtered away after being
 * considered. Mirrors Frontend's client-side `extractNamespacedParams`
 * exactly (same algorithm, same signature shape).
 */
export function extractNamespacedParams(
	search: URLSearchParams,
	prefix: string
): Record<string, string> {
	const result: Record<string, string> = {};
	for (const [key, value] of search) {
		if (key.startsWith(prefix)) result[key] = value;
	}
	return result;
}
