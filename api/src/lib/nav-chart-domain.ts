// nav-chart-domain.ts — browser-safe pure-logic helpers for the §2.1.2.d chart's
// rendering/interaction math (SELF-220 · flows/phase-2-flows-2.1-net-worth.md §12,
// merged dba7bf1). Kept separate from the LayerCake-wrapped component so this logic
// is testable without a DOM environment.

import type { NavSeriesPoint, NavSeriesGranularity } from './nav-series';

/**
 * The shared y-domain `[min, max]` across BOTH lines (nominal always-present,
 * inflation-adjusted nullable) so one linear y-scale fits both series. NULL
 * inflation-adjusted points contribute no value to the domain — consistent with
 * 067's "never a fabricated zero" rule; a NULL must never pull the domain toward 0.
 * Returns `[0, 1]` as an inert default for an empty series (never actually rendered
 * against — the `chart-placeholder` empty state takes over instead — but a safe,
 * non-degenerate default avoids a NaN d3 scale if ever called on one anyway).
 */
export function sharedYDomain(points: NavSeriesPoint[]): [number, number] {
	const values: number[] = [];
	for (const p of points) {
		values.push(p.nav_nominal);
		if (p.nav_inflation_adjusted !== null) values.push(p.nav_inflation_adjusted);
	}
	if (values.length === 0) return [0, 1];
	return [Math.min(...values), Math.max(...values)];
}

/** UTC whole-day count between two ISO dates (end − start). Mirrors
 * Backend's UTC-`Date`-methods idiom (never string surgery) so day/month/year
 * boundaries resolve the same way client- and server-side. */
function daysBetween(startIso: string, endIso: string): number {
	const start = new Date(`${startIso}T00:00:00Z`);
	const end = new Date(`${endIso}T00:00:00Z`);
	return Math.round((end.getTime() - start.getTime()) / 86_400_000);
}

/** `iso` minus `months`, UTC calendar-month arithmetic — mirrors the server's
 * `monthsBeforeIso` idiom (nav-series.ts) in kind. This is pure relative-date math
 * on an EXPLICITLY GIVEN date string, never a read of the actual current moment —
 * not a party to the ADR-043 client-clock hazard, which is specifically about
 * inferring "now" client-side. The server independently re-validates and
 * re-derives whatever window this suggests; nothing here is a security boundary. */
function monthsBeforeIso(iso: string, months: number): string {
	const d = new Date(`${iso}T00:00:00Z`);
	d.setUTCMonth(d.getUTCMonth() - months);
	return d.toISOString().slice(0, 10);
}

/**
 * §12.7 granularity auto-suggestion for a drilled date range, by width: a range
 * under ~3 months suggests Daily, ~3–12 months suggests Weekly, wider keeps
 * Monthly. A SUGGESTION only — the chip-group still shows the toggle and the user
 * can override it (§12.7: "a suggestion... the user can override").
 */
export function suggestGranularity(startIso: string, endIso: string): NavSeriesGranularity {
	const days = daysBetween(startIso, endIso);
	if (days <= 92) return 'daily';
	if (days <= 366) return 'weekly';
	return 'monthly';
}

/**
 * §12.7 density-bounded auto-narrow: switching TO Weekly/Daily while the current
 * view is wider than that granularity's legible span narrows the view to a shorter
 * recent default — Daily to the last 3 months, Weekly to the last 6 — anchored at
 * the CURRENTLY VIEWED `endIso` (never re-anchored to "today"; a drilled view keeps
 * drilling from where it is). Monthly never narrows — it is the 60-month default
 * itself. Returns `null` when no narrowing is needed (already within the
 * granularity's legible bound), so the caller can leave the range untouched.
 */
export function autoNarrowWindow(
	granularity: NavSeriesGranularity,
	startIso: string,
	endIso: string
): { start: string; end: string } | null {
	const days = daysBetween(startIso, endIso);
	if (granularity === 'daily' && days > 92) {
		return { start: monthsBeforeIso(endIso, 3), end: endIso };
	}
	if (granularity === 'weekly' && days > 183) {
		return { start: monthsBeforeIso(endIso, 6), end: endIso };
	}
	return null;
}
