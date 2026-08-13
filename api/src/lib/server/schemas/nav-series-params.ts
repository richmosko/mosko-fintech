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
// Granularity vocabulary is IMPORTED from $lib/nav-series.ts (Frontend-owned,
// browser-safe — server code may import a non-server module, just not the
// reverse) rather than re-declared here: that file already carries the
// canonical `NAV_SERIES_GRANULARITIES`, copied VERBATIM from 062's validated
// parameter set (067 adds no validation of its own — see that file's own
// header). A THIRD independent declaration of this three-value list was the
// wrong thing to add; importing the existing one is the anti-drift move,
// matching account.ts's own precedent of importing shared value-sets from a
// single canonical module rather than re-typing them per consumer.

import { z } from 'zod';
import { NAV_SERIES_GRANULARITIES } from '$lib/nav-series';

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
 * The chart's query-param boundary: `?granularity=&start=&end=`, all
 * INDEPENDENTLY OPTIONAL — absence is not an error (+page.server.ts derives
 * the 60-month-monthly default window when start/end are absent). `.strict()`
 * against everything else. The inverted-range refine mirrors Frontend's
 * client-side schema exactly (same message, same `path`) so a caller sees the
 * identical complaint whichever side catches it first.
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
