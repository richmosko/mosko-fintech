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

	// ⭐ REGRESSION test, added in response to Architect's contract-conformance flag
	// (2026-08-13) — not QA's SELF-220-QA-r1 content above, a Frontend fix-verification
	// added alongside the isImportedEraPoint correction in nav-boundary.ts. The bug: in
	// the IMPORTED-ONLY state (has_cron_rows === false), every point's staleness
	// suppression was computed via isPreBoundaryPoint alone, which answers `false` for
	// every point when first_cron_checkpoint is NULL (there is no date to be "before")
	// — so the ENTIRE imported-only series rendered stale-carry markers, exactly the
	// defect §12.1's suppress-and-disclose ruling exists to prevent. This is the DOM-
	// level assertion Architect named as the one that would have caught it: a unit test
	// of resolutionDisclosureFires alone (which was always correct) passes right over
	// this, because the bug is confined to the SEPARATE suppression path.
	it('⭐ imported-only state (no cron era at all): ZERO staleness markers render, however many carried points exist', () => {
		const boundary = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true };
		const carried1 = point({ point_date: '2018-01-31', checkpoint_date: '2017-12-31' });
		const carried2 = point({ point_date: '2018-02-28', checkpoint_date: '2018-01-31' });
		const { queryAllByRole } = render(NavHistoryChart, {
			props: {
				points: [carried1, carried2],
				paramsError: null,
				params: PARAMS,
				boundary
			}
		});
		expect(queryAllByRole('img', { name: /NAV checkpoint carried from/ })).toHaveLength(0);
	});
});

// ============================================================================
// SELF-220-QA-r3 — QA reconcile pass (2026-08-13) against Frontend's landed
// regression test above and team-lead/Sec's audit of it. Two residuals, not a
// full re-cover: the disclosure-still-fires and mixed-state-splits-correctly
// controls this reconcile also asked about are ALREADY covered by
// SELF-220-QA-r1 above (the "resolution-disclosure copy" and "staleness
// markers fire post-boundary ONLY" blocks) — nothing duplicated here.
//
// (A) SEC'S STATE-DRIVEN REQUIREMENT: the landed regression test above queries
// `getByRole('img', { name: /NAV checkpoint carried from/ })` — coupled to the
// marker's aria-label COPY, which a wording change would silently decouple
// (the query would just stop matching and the test would pass VACUOUSLY, not
// because the bug is fixed). It also independently reproduces a real crash: run
// as-landed against the pre-fix source, `queryAllByRole` + `toHaveLength` on
// the failing (non-empty) case throws an unrelated Svelte-internals error
// instead of failing cleanly (same root cause recorded against SELF-220-QA-r2's
// draft: the failure-message pretty-printer chokes serializing a raw array of
// DOM elements) — confirmed while retro-proving RED, see hand-off notes.
// Supplementing with a class-selector, state-driven form: same (null, false,
// true) input Sec asked for, asserts on `.stale-marker` (the semantic marker
// class) and on `.length` (a number, not the array), not on rendered text.
//
// (B) LINE-TREATMENT COVERAGE GAP: the landed regression test only asserts on
// markers. It does not touch §12.6's other imported-only-state requirement —
// the nominal line must draw its stepped treatment for EVERY point, not
// collapse into the plain post-boundary linear segment. Added here.
// ============================================================================

describe('SELF-220-QA-r3 — imported-only state, reconciled: state-driven marker check + line-treatment (residual after 94c298c)', () => {
	const IMPORTED_ONLY_BOUNDARY = { first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true };
	const CARRIED_IMPORTED_POINTS = [
		point({ point_date: '2025-01-15', checkpoint_date: '2015-12-31' }),
		point({ point_date: '2025-02-15', checkpoint_date: '2015-12-31' }),
		point({ point_date: '2025-03-15', checkpoint_date: '2015-12-31' })
	];

	it('(A) state-driven: zero .stale-marker elements — not coupled to aria-label copy', () => {
		const { container } = render(NavHistoryChart, {
			props: {
				points: CARRIED_IMPORTED_POINTS,
				paramsError: null,
				params: PARAMS,
				boundary: IMPORTED_ONLY_BOUNDARY
			}
		});
		const markers = container.querySelectorAll('.stale-marker');
		expect(markers.length).toBe(0);
	});

	it('(B) the nominal line draws ENTIRELY as the stepped treatment — no plain post-boundary linear segment renders', () => {
		// A bare ".line-stepped exists" check is NOT sufficient — NavChartLines.svelte's
		// join-point mechanism always appends the first post-boundary point to the
		// pre-boundary array when the latter is non-empty, so a degenerate ONE-POINT
		// stepped path can render even under a bug that misclassifies everything else.
		// The discriminating signal is the ABSENCE of the plain (non-stepped) segment.
		const { container } = render(NavHistoryChart, {
			props: {
				points: CARRIED_IMPORTED_POINTS,
				paramsError: null,
				params: PARAMS,
				boundary: IMPORTED_ONLY_BOUNDARY
			}
		});
		const nominalPaths = Array.from(container.querySelectorAll('.line-nominal'));
		const plainLinearSegments = nominalPaths.filter((el) => !el.classList.contains('line-stepped'));
		expect(container.querySelector('.line-stepped')).not.toBeNull();
		expect(plainLinearSegments.length).toBe(0);
	});
});
