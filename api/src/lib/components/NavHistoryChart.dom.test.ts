// NavHistoryChart.dom.test.ts — SELF-220 §2.1.2.d NAV chart battery. Proves the
// placeholder-state gating (the highest-value, easiest-to-get-wrong logic: error vs
// read-failed vs genuinely-empty must never collapse into one rendered message —
// see nav-series.ts / nav-boundary.ts headers for why) and the top-level structural
// render for a populated series (legend, basis-line, chip-group present).
//
// SCOPE NOTE: this does not assert exact SVG path geometry — LayerCake's
// ResizeObserver-driven container sizing is unreliable under jsdom (no real layout
// engine), so pixel-level path assertions would be fragile and low-value here. The
// pure MATH that geometry depends on (gap segmentation, boundary suppression,
// shared y-domain, zoom/narrow math) is already covered node-side in
// nav-series.test.ts / nav-boundary.test.ts / nav-chart-domain.test.ts, DOM-free.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach, type Mock } from 'vitest';
import { render } from '@testing-library/svelte';
import NavHistoryChart from './NavHistoryChart.svelte';
import type { NavSeriesPoint } from '$lib/nav-series';
import { EMPTY_NAV_BOUNDARY } from '$lib/nav-boundary';
// Resolves to tests/stubs/app-navigation.ts under the vitest.config.ts alias — a real
// vi.fn(), the SAME instance NavHistoryChart.svelte calls internally (the alias IS
// the resolution, no vi.mock() needed). See that stub's header for why it exists.
//
// TYPE vs RUNTIME SPLIT, WORTH NAMING: svelte-check resolves `$app/navigation`'s
// TYPE against SvelteKit's real ambient declarations (from `svelte-kit sync`), which
// know nothing of the vitest alias below — so the imported binding types as the real
// `goto` signature, not a mock. The vitest ALIAS (vitest.config.ts) still resolves
// the RUNTIME value to the stub. Cast once, here, rather than fight svelte-check.
import { goto as gotoImport } from '$app/navigation';
const goto = gotoImport as unknown as Mock;

beforeEach(() => {
	goto.mockClear();
});

// jsdom has no ResizeObserver (a real browser API) — LayerCake's container binds
// `clientWidth`/`clientHeight` via one to size the SVG canvas. A minimal no-op stub
// (never actually fires, matching every other component in this suite that doesn't
// assert on real layout) is enough to let LayerCake mount without throwing; the
// component's own logic being tested here doesn't depend on real pixel dimensions.
class ResizeObserverStub {
	observe() {}
	unobserve() {}
	disconnect() {}
}
globalThis.ResizeObserver ??= ResizeObserverStub;

const PARAMS = { granularity: 'monthly' as const, start: '2021-06-01', end: '2026-06-01' };

function point(overrides: Partial<NavSeriesPoint>): NavSeriesPoint {
	return {
		point_date: '2026-01-31',
		nav_nominal: 100_000,
		checkpoint_date: '2026-01-31',
		nav_inflation_adjusted: 95_000,
		cpi_period: '2026-01-01',
		cpi_value: 300,
		cpi_is_carried: false,
		cpi_carried_from: null,
		cpi_period_was_due: false,
		cpi_nonpublication_on_record: false,
		cpi_coverage_through: '2026-06-01',
		...overrides
	};
}

// A well-formed 12+ month series so isSparseHistory is false and the default
// (non-placeholder) render path is exercised.
const POPULATED = Array.from({ length: 13 }, (_, i) =>
	point({
		point_date: `202${5 + Math.floor((6 + i) / 12)}-${String(((6 + i) % 12) + 1).padStart(2, '0')}-15`,
		nav_nominal: 100_000 + i * 1_000,
		nav_inflation_adjusted: 95_000 + i * 900
	})
);

describe('NavHistoryChart — placeholder-state gating never collapses distinct states', () => {
	it('paramsError set: renders the error notice, never the empty/unavailable copy', () => {
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: {
				points: [],
				paramsError: 'granularity: Invalid enum value',
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY
			}
		});
		expect(getByText(/Chart parameters were invalid/)).toBeTruthy();
		expect(queryByText('Collect data over time.')).toBeNull();
		expect(queryByText(/temporarily unavailable/)).toBeNull();
	});

	it('points === null (read failed): renders the unavailable notice, never the empty-history copy', () => {
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: { points: null, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText(/temporarily unavailable/)).toBeTruthy();
		expect(queryByText('Collect data over time.')).toBeNull();
	});

	it('points === [] (genuinely empty): renders "Collect data over time.", never the unavailable copy', () => {
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: { points: [], paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText('Collect data over time.')).toBeTruthy();
		expect(queryByText(/temporarily unavailable/)).toBeNull();
	});
});

describe('NavHistoryChart — default render (populated series)', () => {
	it('renders both legend entries and the granularity chip-group', () => {
		const { getByText, getByRole } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText('Net Worth (Nominal)')).toBeTruthy();
		expect(getByText('Net Worth (Inflation-Adjusted)')).toBeTruthy();
		expect(getByRole('radiogroup', { name: 'Chart granularity' })).toBeTruthy();
	});

	it('the selected granularity chip carries aria-checked="true"; the others false', () => {
		const { getByRole } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		const monthly = getByRole('radio', { name: 'Monthly' });
		const weekly = getByRole('radio', { name: 'Weekly' });
		expect(monthly.getAttribute('aria-checked')).toBe('true');
		expect(weekly.getAttribute('aria-checked')).toBe('false');
	});

	it('cpi-unavailable series (every point NULL): omits the inflation-adjusted legend entry, shows the unavailable basis line', () => {
		const cpiUnavailablePoints = POPULATED.map((p) => ({
			...p,
			nav_inflation_adjusted: null,
			cpi_value: null,
			cpi_coverage_through: null
		}));
		const { queryByText, getByText } = render(NavHistoryChart, {
			props: {
				points: cpiUnavailablePoints,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY
			}
		});
		expect(queryByText('Net Worth (Inflation-Adjusted)')).toBeNull();
		expect(getByText(/Inflation-adjusted figures are unavailable/)).toBeTruthy();
	});

	it('clicking a granularity chip navigates via goto with updated query params', async () => {
		const { getByRole } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		const daily = getByRole('radio', { name: 'Daily' });
		daily.click();
		await Promise.resolve();
		expect(goto).toHaveBeenCalledTimes(1);
		const [calledUrl] = goto.mock.calls[0] as [string];
		expect(calledUrl).toContain('granularity=daily');
	});
});

// ============================================================================
// SELF-220-QA-r1 — QA-added coverage (content marker for this revision). Three
// gaps identified by audit against the SELF-220 dispatch's items 3/4: none of
// the RULED disclosure copy, the `sparse` placeholder state, or the
// post-boundary-only staleness-marker property had a DOM-level assertion
// anywhere in the existing suite (the pure functions they're built on —
// isSparseHistory / isPreBoundaryPoint / shouldSuppressCarryStaleness — are
// covered node-side in nav-series.test.ts / nav-boundary.test.ts, but the
// COMPONENT WIRING that reads those functions and renders accordingly was
// not). Added here rather than as new files, matching this file's own
// established idiom (render + testing-library queries, no SVG path-geometry
// assertions — see this file's SCOPE NOTE at the top).
// ============================================================================

describe('SELF-220-QA-r1 — resolution-disclosure copy, bound to the UX-ruled string exactly', () => {
	it('imported-only (no cron yet): renders the RULED no-boundary-date copy verbatim', () => {
		const boundary = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true };
		const { getByText } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary }
		});
		// Bound to the EXACT ruled string (team-lead, 2026-08-12) — not a substring/regex
		// match, so a future edit that alters the copy fails here rather than passing on a
		// loose /Monthly resolution/ match that both branches would satisfy.
		expect(
			getByText("Monthly resolution — daily/weekly tracking hasn't started yet.")
		).toBeTruthy();
	});

	it('mixed (a real boundary date): renders the dated variant, NOT the no-boundary-date copy', () => {
		const boundary = { first_cron_checkpoint: '2026-01-01', has_cron_rows: true, has_imported_rows: true };
		const preBoundaryPoint = point({ point_date: '2025-06-15', checkpoint_date: '2025-06-15' });
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: { points: [preBoundaryPoint, ...POPULATED], paramsError: null, params: PARAMS, boundary }
		});
		expect(getByText(/Monthly resolution before/)).toBeTruthy();
		expect(getByText('January 2026', { selector: '.basis-value' })).toBeTruthy();
		expect(queryByText("Monthly resolution — daily/weekly tracking hasn't started yet.")).toBeNull();
	});

	it('cron-only (no imported rows at all): the disclosure never renders — nothing to disclose', () => {
		const boundary = { first_cron_checkpoint: '2026-01-01', has_cron_rows: true, has_imported_rows: false };
		const { queryByText } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary }
		});
		expect(queryByText(/Monthly resolution/)).toBeNull();
	});
});

describe('SELF-220-QA-r1 — sparse-history state (§12.9) does not collapse into the default render', () => {
	// Fewer than 12 distinct months — isSparseHistory's own threshold (nav-series.test.ts).
	const SPARSE = Array.from({ length: 5 }, (_, i) =>
		point({ point_date: `2026-0${i + 1}-15`, nav_nominal: 100_000 + i * 1_000 })
	);

	it('sparse series: the tracking-history label renders with the correct "N of M months" text', () => {
		const { getByText } = render(NavHistoryChart, {
			props: { points: SPARSE, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		// PARAMS spans 2021-06-01..2026-06-01 = 60 requested months; SPARSE carries 5
		// distinct calendar months — both halves of the label are asserted so a
		// regression in EITHER the numerator (months-of-history) or the denominator
		// (windowMonths threaded down from the parent's own params) is caught.
		expect(getByText('5 of 60 months of history')).toBeTruthy();
	});

	it('a populated (non-sparse) series never renders the tracking-history label', () => {
		const { queryByText } = render(NavHistoryChart, {
			props: { points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(queryByText(/months of history/)).toBeNull();
	});
});

describe('SELF-220-QA-r1 — staleness markers fire post-boundary ONLY (§12.1/§12.2)', () => {
	it('a pre-boundary carried point gets NO marker; a post-boundary carried point DOES', () => {
		const boundary = { first_cron_checkpoint: '2026-01-01', has_cron_rows: true, has_imported_rows: true };
		const preBoundaryCarried = point({
			point_date: '2025-06-30',
			checkpoint_date: '2025-05-31' // carried (checkpoint_date !== point_date), but pre-boundary
		});
		const postBoundaryCarried = point({
			point_date: '2026-03-31',
			checkpoint_date: '2026-02-28' // carried, and post-boundary — a real cron gap
		});
		const postBoundaryFresh = point({ point_date: '2026-04-30', checkpoint_date: '2026-04-30' });
		const { getAllByRole } = render(NavHistoryChart, {
			props: {
				points: [preBoundaryCarried, postBoundaryCarried, postBoundaryFresh],
				paramsError: null,
				params: PARAMS,
				boundary
			}
		});
		// EXACTLY one marker — proves both directions at once: the post-boundary carried
		// point got one (not silently dropped) AND the pre-boundary carried point did not
		// (not over-rendered). A count of 0 or 2 would each fail a different half of §12.1.
		const markers = getAllByRole('img', { name: /NAV checkpoint carried from/ });
		expect(markers).toHaveLength(1);
		expect(markers[0].getAttribute('aria-label')).toBe(
			'NAV checkpoint carried from 2026-02-28 to 2026-03-31'
		);
	});

});

// ============================================================================
// SELF-220-QA-r2 — 069 four-state RENDERED OUTPUT, not just helper math.
// Architect-traced finding (2026-08-13, verified at b409e29): isPreBoundaryPoint
// requires `boundary.first_cron_checkpoint !== null`, so in the IMPORTED-ONLY
// state (069 state (b) — has_cron_rows=false, no boundary DATE exists yet
// because no cron row exists yet) it returns FALSE for every point — there is
// no date to compare against. That collapses suppression entirely in exactly
// the state where it matters most: every carried imported point gets an
// actionable staleness marker it shouldn't, and the nominal line's stepped
// pre-boundary treatment never draws — the whole line renders as the post-
// boundary linear segment instead. nav-boundary.test.ts's unit tests don't
// catch this: they test isPreBoundaryPoint's RETURN VALUE correctly for what
// it's asked, not what the COMPONENT does when that value is false across an
// entire series. This describe block is the catching test, RED-proven at
// b409e29 before Frontend's era-membership fix (isImportedEraPoint, landed
// 94c298c) — re-run and confirmed GREEN on the combined tree before this file
// itself was committed.
// ============================================================================

describe('SELF-220-QA-r2 — imported-only state: suppression and line-split by ERA MEMBERSHIP, not boundary-date presence', () => {
	const IMPORTED_ONLY_BOUNDARY = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true };
	// All three carried (checkpoint_date !== point_date) — a historical import gap, the
	// exact shape ADR-053 Decision 7 exists to suppress. Dates sit inside PARAMS' window.
	const CARRIED_IMPORTED_POINTS = [
		point({ point_date: '2025-01-15', checkpoint_date: '2015-12-31' }),
		point({ point_date: '2025-02-15', checkpoint_date: '2015-12-31' }),
		point({ point_date: '2025-03-15', checkpoint_date: '2015-12-31' })
	];

	it('⭐ RED-at-b409e29: zero staleness markers — every point is carried, but there is no cron era yet to be stale relative to', () => {
		// Plain DOM query (not queryAllByRole) — matches this block's other assertions'
		// idiom and sidesteps an unrelated testing-library/jsdom role-query interaction
		// that throws under this specific fixture; .stale-marker is the exact class
		// NavChartLines.svelte applies to the same circles' role="img" element.
		const { container } = render(NavHistoryChart, {
			props: {
				points: CARRIED_IMPORTED_POINTS,
				paramsError: null,
				params: PARAMS,
				boundary: IMPORTED_ONLY_BOUNDARY
			}
		});
		const markers = container.querySelectorAll('.stale-marker');
		expect(markers).toHaveLength(0);
	});

	it('control — already correct at b409e29: the resolution-disclosure still fires, isolating the marker/line defect from the disclosure logic', () => {
		const { getByText } = render(NavHistoryChart, {
			props: {
				points: CARRIED_IMPORTED_POINTS,
				paramsError: null,
				params: PARAMS,
				boundary: IMPORTED_ONLY_BOUNDARY
			}
		});
		expect(getByText("Monthly resolution — daily/weekly tracking hasn't started yet.")).toBeTruthy();
	});

	it('⭐ RED-at-b409e29: the nominal line draws ENTIRELY as the stepped PRE-boundary treatment — no plain post-boundary linear segment renders', () => {
		// NOTE: a bare "does .line-stepped exist" check is NOT sufficient here and was
		// caught as a false-negative while authoring this leg — NavChartLines.svelte's
		// join-point mechanism (preBoundaryJoined always appends postBoundaryPoints[0]
		// when it's non-empty, so the two segments visually meet) makes a degenerate
		// ONE-POINT `.line-stepped` path render even under the bug, because the single
		// shared join point still satisfies `preBoundaryJoined.length > 0`. The actual
		// defect is that ALL THREE real points end up classified post-boundary instead
		// of pre-boundary, so the discriminating signal is the PLAIN linear segment's
		// PRESENCE (it shouldn't exist at all when every point is pre-era), not the
		// stepped segment's presence alone.
		const { container } = render(NavHistoryChart, {
			props: {
				points: CARRIED_IMPORTED_POINTS,
				paramsError: null,
				params: PARAMS,
				boundary: IMPORTED_ONLY_BOUNDARY
			}
		});
		// Plain JS filtering over querySelectorAll results, not a `:not()` compound CSS
		// selector — the compound form triggered an unrelated jsdom/Svelte-internals
		// interaction under this specific fixture while authoring this leg. Root-caused
		// further: it wasn't the selector OR the filter, it was asserting `toHaveLength`
		// on an ARRAY OF RAW DOM ELEMENTS on a FAILING case — the failure-message
		// pretty-printer tries to serialize the SVG <path> element and that's what
		// crashes (a plain NodeList, e.g. the marker test's `.stale-marker` query below,
		// printed fine on the identical kind of failure). Asserting on `.length` (a
		// number) rather than the array itself sidesteps the printer entirely and keeps
		// a clean, readable failure message on the actual RED case.
		const nominalPaths = Array.from(container.querySelectorAll('.line-nominal'));
		const plainLinearSegments = nominalPaths.filter((el) => !el.classList.contains('line-stepped'));
		expect(container.querySelector('.line-stepped')).not.toBeNull();
		expect(plainLinearSegments.length).toBe(0);
	});

	it('control — mixed state (already correct at b409e29): BOTH the stepped pre-boundary and linear post-boundary segments render, proving the selectors above are real and not absent-by-construction', () => {
		const boundary = { first_cron_checkpoint: '2026-06-01', has_cron_rows: true, has_imported_rows: true };
		const mixedPoints = [
			point({ point_date: '2025-06-15', checkpoint_date: '2025-06-15' }),
			point({ point_date: '2026-06-15', checkpoint_date: '2026-06-15' }),
			point({ point_date: '2026-07-15', checkpoint_date: '2026-07-15' })
		];
		const { container } = render(NavHistoryChart, {
			props: { points: mixedPoints, paramsError: null, params: PARAMS, boundary }
		});
		const nominalPaths = Array.from(container.querySelectorAll('.line-nominal'));
		const plainLinearSegments = nominalPaths.filter((el) => !el.classList.contains('line-stepped'));
		expect(container.querySelector('.line-stepped')).not.toBeNull();
		expect(plainLinearSegments.length).toBeGreaterThan(0);
	});
});
