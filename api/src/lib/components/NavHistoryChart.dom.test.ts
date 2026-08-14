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
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
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
// Same alias-resolved stub idiom as `goto` above — resolves to tests/stubs/app-state.ts, a
// plain mutable object (not genuinely Svelte-reactive). Reassigning `page.url` directly between
// tests is that stub's own documented usage for varying the URL mid-suite.
import { page } from '$app/state';
const goto = gotoImport as unknown as Mock;

// Same type-vs-runtime split as `goto` above, one level deeper: svelte-check types
// `page.url` against SvelteKit's real route-manifest-derived literal union for
// `pathname` (the ambient `$app/state` declarations), which a plain `new URL(...)`
// never satisfies — even though the vitest alias resolves `page` to the plain-object
// stub (tests/stubs/app-state.ts) at runtime, where `url` is just `URL`. Reassigning
// through this typed helper (instead of `page.url = ...` at each call site) casts
// once, here, rather than fighting svelte-check five times over.
function setPageUrl(url: string): void {
	(page as unknown as { url: URL }).url = new URL(url);
}

beforeEach(() => {
	goto.mockClear();
	// page is a module-level singleton stub (tests/stubs/app-state.ts) — reset between tests
	// so a test that mutates page.url (e.g. to prove a stray param survives navigation) can't
	// leak its URL into an unrelated later test.
	setPageUrl('http://localhost/');
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
			props: { staleness: EMPTY_STALENESS,
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
			props: { staleness: EMPTY_STALENESS, points: null, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText(/temporarily unavailable/)).toBeTruthy();
		expect(queryByText('Collect data over time.')).toBeNull();
	});

	it('points === [] (genuinely empty): renders "Collect data over time.", never the unavailable copy', () => {
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: [], paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText('Collect data over time.')).toBeTruthy();
		expect(queryByText(/temporarily unavailable/)).toBeNull();
	});
});

describe('NavHistoryChart — default render (populated series)', () => {
	it('renders both legend entries and the granularity chip-group', () => {
		const { getByText, getByRole } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText('Net Worth (Nominal)')).toBeTruthy();
		expect(getByText('Net Worth (Inflation-Adjusted)')).toBeTruthy();
		expect(getByRole('radiogroup', { name: 'Chart granularity' })).toBeTruthy();
	});

	it('the selected granularity chip carries aria-checked="true"; the others false', () => {
		const { getByRole } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
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
			props: { staleness: EMPTY_STALENESS,
				points: cpiUnavailablePoints,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY
			}
		});
		expect(queryByText('Net Worth (Inflation-Adjusted)')).toBeNull();
		expect(getByText(/Inflation-adjusted figures are unavailable/)).toBeTruthy();
	});

	it('clicking a granularity chip navigates via goto with the NAMESPACED query param', async () => {
		const { getByRole } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		const daily = getByRole('radio', { name: 'Daily' });
		daily.click();
		await Promise.resolve();
		expect(goto).toHaveBeenCalledTimes(1);
		const [calledUrl] = goto.mock.calls[0] as [string];
		const params = new URL(calledUrl, 'http://localhost').searchParams;
		expect(params.get('chart_granularity')).toBe('daily');
		expect(params.has('granularity')).toBe(false);
	});

	// ⭐ F/CTO-ratified 2026-08-13 (Sec's param-fence finding) — every goto() URL write on this
	// surface must preserve params it doesn't own, not just avoid rejecting them on read.
	it('⭐ a stray non-chart param on the page URL survives a granularity-chip navigation untouched', async () => {
		setPageUrl('http://localhost/?utm_source=newsletter');
		const { getByRole } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		const daily = getByRole('radio', { name: 'Daily' });
		daily.click();
		await Promise.resolve();
		const [calledUrl] = goto.mock.calls[0] as [string];
		const params = new URL(calledUrl, 'http://localhost').searchParams;
		expect(params.get('utm_source')).toBe('newsletter');
		expect(params.get('chart_granularity')).toBe('daily');
	});
});

// ⭐ F/CTO-ratified 2026-08-13 (Sec's param-fence finding, option A) — the reset breadcrumb and
// its goto() write are namespace-scoped exactly like the granularity toggle above: the
// breadcrumb reflects THIS surface's own drilled state, and a reset clears only what this
// surface owns.
describe('NavHistoryChart — reset breadcrumb is namespace-scoped, not page-scoped', () => {
	it('a page URL with ONLY a stray non-chart param does NOT show "Reset to 60 months"', () => {
		setPageUrl('http://localhost/?utm_source=newsletter');
		const { queryByText, getByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(queryByText('Reset to 60 months')).toBeNull();
		// The non-breadcrumb range label renders instead — proves the false branch is reachable
		// and this isn't a fixture that happens to show neither.
		expect(getByText(/Showing:/)).toBeTruthy();
	});

	it('a page URL WITH a chart_* param shows "Reset to 60 months"', () => {
		setPageUrl('http://localhost/?chart_granularity=daily');
		const { getByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(getByText('Reset to 60 months')).toBeTruthy();
	});

	it('⭐ clicking reset clears only chart_* keys — a stray non-chart param on the URL survives', async () => {
		setPageUrl('http://localhost/?utm_source=newsletter&chart_granularity=daily&chart_start=2026-01-01');
		const { getByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		getByText('Reset to 60 months').click();
		await Promise.resolve();
		expect(goto).toHaveBeenCalledTimes(1);
		const [calledUrl] = goto.mock.calls[0] as [string];
		const params = new URL(calledUrl, 'http://localhost').searchParams;
		expect(params.get('utm_source')).toBe('newsletter');
		expect(params.has('chart_granularity')).toBe(false);
		expect(params.has('chart_start')).toBe(false);
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
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary }
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
			props: { staleness: EMPTY_STALENESS, points: [preBoundaryPoint, ...POPULATED], paramsError: null, params: PARAMS, boundary }
		});
		expect(getByText(/Monthly resolution before/)).toBeTruthy();
		expect(getByText('January 2026', { selector: '.basis-value' })).toBeTruthy();
		expect(queryByText("Monthly resolution — daily/weekly tracking hasn't started yet.")).toBeNull();
	});

	it('cron-only (no imported rows at all): the disclosure never renders — nothing to disclose', () => {
		const boundary = { first_cron_checkpoint: '2026-01-01', has_cron_rows: true, has_imported_rows: false };
		const { queryByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary }
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
			props: { staleness: EMPTY_STALENESS, points: SPARSE, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		// PARAMS spans 2021-06-01..2026-06-01 = 60 requested months; SPARSE carries 5
		// distinct calendar months — both halves of the label are asserted so a
		// regression in EITHER the numerator (months-of-history) or the denominator
		// (windowMonths threaded down from the parent's own params) is caught.
		expect(getByText('5 of 60 months of history')).toBeTruthy();
	});

	it('a populated (non-sparse) series never renders the tracking-history label', () => {
		const { queryByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
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
			props: { staleness: EMPTY_STALENESS,
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
			props: { staleness: EMPTY_STALENESS,
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
			props: { staleness: EMPTY_STALENESS,
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
			props: { staleness: EMPTY_STALENESS,
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

// ============================================================================
// SELF-220-QA-r4 — Sec's round-2 finding (2026-08-13), fail-OPEN on a boundary
// READ FAILURE, not a data state. Base sha for this catching test: `e0edfac`.
//
// isImportedEraPoint's `!has_cron_rows` guard is TRUE on EMPTY_NAV_BOUNDARY
// (null, false, false) — it was written to answer "is this the imported-only
// STATE" (069 state (b): has_cron_rows=false, has_imported_rows=true), but
// EMPTY_NAV_BOUNDARY shares has_cron_rows=false with state (b) while actually
// meaning something else entirely: "the boundary READ FAILED" (nav-boundary.ts
// / server/queries/nav-boundary.ts's own fail-soft-to-null contract) or "the
// store is genuinely empty" (state (a)). Keying suppression on has_cron_rows
// ALONE collapses THOSE two into state (b) too — the same single-field
// conflation the original imported-only bug had, one field over. Sec's own
// framing: my prior four-consumer enumeration passed because the criterion
// checked "does this branch on a state FIELD" without checking "does it
// branch on the FULL three-field tuple" — a single boolean is never enough to
// disambiguate four states.
//
// REACHABILITY (Sec, why this isn't hypothetical): a genuinely empty store
// yields `[]` for `points` under the same RLS the boundary read uses — so
// EMPTY_NAV_BOUNDARY paired with REAL, non-empty, carried points can only
// happen via the fail-soft substitution: +page.svelte's
// `boundary={data.navBoundary ?? EMPTY_NAV_BOUNDARY}` fires when the 069 RPC
// call failed, while the SEPARATE navSeries fetch on the same load() may have
// succeeded independently and returned real carried points. In that reachable
// state: EVERY point gets treated as imported-era (has_cron_rows is false,
// same as it would be for a genuine state (b)) — every real staleness marker
// is SUPPRESSED, and the resolution-disclosure ALSO never fires (it requires
// has_imported_rows === true, and EMPTY has that false) — so the user sees
// NEITHER signal. A real cron-gap staleness event goes completely silent on a
// transient, unrelated read failure. Fail-OPEN, not fail-closed.
// ============================================================================

describe('SELF-220-QA-r4 — boundary READ FAILURE (EMPTY tuple) + real carried points: markers must SHOW, not silently suppress', () => {
	const CARRIED_POINTS_UNDER_FAILED_BOUNDARY = [
		point({ point_date: '2026-01-31', checkpoint_date: '2025-12-01' }),
		point({ point_date: '2026-02-28', checkpoint_date: '2025-12-01' }),
		point({ point_date: '2026-03-31', checkpoint_date: '2026-03-31' }) // one fresh, non-carried point too
	];

	it('⭐ RED-at-e0edfac: staleness markers SHOW under EMPTY_NAV_BOUNDARY — a boundary read failure must not silently hide real staleness', () => {
		const { container } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS,
				points: CARRIED_POINTS_UNDER_FAILED_BOUNDARY,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY
			}
		});
		// State-driven input (EMPTY_NAV_BOUNDARY, the exact tuple), structural
		// assertion (class presence + count, never rendered text) — not a DOM
		// string pin. Two real carried points in the fixture; the third is fresh
		// and must NOT produce a marker, so this also isn't satisfied by an
		// implementation that marks everything regardless of carry state.
		const markers = container.querySelectorAll('.stale-marker');
		expect(markers.length).toBe(2);
	});

	it('⭐ RED-at-e0edfac: the resolution-disclosure does NOT fire under EMPTY_NAV_BOUNDARY — nothing to disclose when has_imported_rows is false', () => {
		const { container } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS,
				points: CARRIED_POINTS_UNDER_FAILED_BOUNDARY,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY
			}
		});
		// Structural class check (.resolution-disclosure), not a copy-string match —
		// this leg is expected to ALREADY pass at e0edfac (resolutionDisclosureFires
		// keys on has_imported_rows, which is false on EMPTY); included as the
		// non-vacuity companion to the marker leg above, on the SAME input.
		expect(container.querySelector('.resolution-disclosure')).toBeNull();
	});
});

describe('NavHistoryChart — SELF-229 D1 stale-data-marker (whole-user, shared with the other 3 surfaces)', () => {
	// Sec F3(B) (F/CTO-ruled): `staleness` is now a REQUIRED prop — there is no more implicit
	// "omitted" case (a caller that forgets it fails at TYPECHECK). This asserts the explicit
	// EMPTY_STALENESS (confirmed-healthy) value stays zero-footprint, same as before.
	it('staleness confirmed healthy (EMPTY_STALENESS) → zero-footprint, no badge markup', () => {
		const { queryByText } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points: POPULATED, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(queryByText('May be stale')).toBeNull();
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the section heading', () => {
		const { getByText } = render(NavHistoryChart, {
			props: {
				points: POPULATED,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY,
				staleness: {
					is_stale: true,
					stale_items: [
						{
							linked_source_id: '42',
							institution_name: 'Test Bank',
							provider: 'plaid',
							connection_status: 'login_required',
							status_class: null
						}
					]
				}
			}
		});
		expect(getByText('May be stale')).toBeTruthy();
	});
});

// ============================================================================
// F/CTO ruling (a), FINAL BATTERY PASS (team-lead, post-442dac8): the badge's own tri-state
// distinguishability is proven exhaustively at the shared-component level
// (StaleConstituentBadge.ssr.test.ts). What was NOT proven anywhere: that `staleness.is_stale
// === null` (UNKNOWN_STALENESS) actually reaches THIS surface's own mount and renders — every
// prior wiring-fidelity leg on this file only ever exercised `is_stale: true`. Closing that gap.
// ============================================================================

describe('NavHistoryChart — SELF-229 tri-state wiring: staleness.is_stale === null reaches this surface', () => {
	it('is_stale === null renders "Staleness unknown" at this surface, distinct from "May be stale"', () => {
		const { getByText, queryByText } = render(NavHistoryChart, {
			props: {
				points: POPULATED,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY,
				staleness: { is_stale: null, stale_items: [] }
			}
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		expect(queryByText('May be stale')).toBeNull();
	});

	it('is_stale === false (confirmed healthy) stays zero-footprint — never confused with the unknown case above', () => {
		const { queryByText } = render(NavHistoryChart, {
			props: {
				points: POPULATED,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY,
				staleness: { is_stale: false, stale_items: [] }
			}
		});
		expect(queryByText('Staleness unknown')).toBeNull();
		expect(queryByText('May be stale')).toBeNull();
	});
});

// ============================================================================
// SELF-229-QA — the D1 stale-data-marker (StaleConstituentBadge, wired in f103586) now
// coexists on this ONE surface with the two markers already proven above: the checkpoint-carry
// marker (NavChartLines' `<circle class="stale-marker" role="img">`, §12.1/§12.2) and the
// CPI-carry InformationalMarkerBadge (`.info-marker-badge`). ⚠ NAME COLLISION (FOUND, FIXED):
// the badge's wrapper originally carried the IDENTICAL class `stale-marker` as the
// checkpoint-carry `<circle>` — flagged to Frontend, who renamed it to `.stale-connection-marker`
// in 1a5745d. A bare `.querySelectorAll('.stale-marker')` — exactly the pattern
// SELF-220-QA-r3/r4 above use — would have SILENTLY SUMMED both signals pre-rename. The distinct
// class name is now the primary discriminator below; `role` (group vs img) is asserted too as a
// belt-and-suspenders check against a future rename collision.
//
// Team-lead's ramp brief: "a leg must fail if any two [of the three signals] collapse into one
// rendered element (vary each signal independently; invariance to a varied signal = blindness)."
// Four legs: each signal varied ALONE (the other two absent), then all three present at once —
// the last leg is the one that actually catches a collapse, since the first three would each
// individually pass even under an implementation that conflated any TWO of the signals whenever
// only one is present in the fixture.
// ============================================================================

describe('SELF-229-QA — three distinct staleness/carry signals never collapse into one rendered element', () => {
	const D1_BADGE_SEL = '.stale-connection-marker[role="group"]';
	const CARRY_MARKER_SEL = '.stale-marker[role="img"]';
	const CPI_INFO_BADGE_SEL = '.info-marker-badge';

	const D1_STALE = {
		is_stale: true,
		stale_items: [
			{
				linked_source_id: '42',
				institution_name: 'Test Bank',
				provider: 'plaid',
				connection_status: 'login_required',
				status_class: null
			}
		]
	};

	// NOTE: deliberately NOT reusing the shared `POPULATED` fixture here — its `point_date`
	// overrides shift each point off `point()`'s FIXED default `checkpoint_date` ('2026-01-31'),
	// so nearly every POPULATED point is ALREADY checkpoint-carried by construction (confirmed:
	// carry=13 on a first draft of this leg). Every fixture below sets checkpoint_date EXPLICITLY
	// so each signal is genuinely isolated rather than accidentally tripping another.
	const FRESH = (dateIso: string) => point({ point_date: dateIso, checkpoint_date: dateIso, cpi_is_carried: false, cpi_period_was_due: false });
	const CHECKPOINT_CARRIED = (dateIso: string, fromIso: string) =>
		point({ point_date: dateIso, checkpoint_date: fromIso, cpi_is_carried: false, cpi_period_was_due: false });
	// cpi_carried_from MUST be set (not left at point()'s default null): InformationalMarkerBadge
	// only renders when its computed `message` is non-empty, and with a single carried point
	// (carriedCount === 1) the message branch requires `cpiPeriod && carriedFrom` BOTH truthy —
	// confirmed by a first draft of this leg going cpi:0 instead of 1 with carriedFrom left null.
	const CPI_CARRIED = (dateIso: string) =>
		point({
			point_date: dateIso,
			checkpoint_date: dateIso,
			cpi_is_carried: true,
			cpi_period_was_due: true,
			cpi_carried_from: '2025-12-01'
		});
	const FRESH_SERIES = [FRESH('2026-01-15'), FRESH('2026-02-15'), FRESH('2026-03-15'), FRESH('2026-04-15')];

	function counts(container: HTMLElement) {
		return {
			badge: container.querySelectorAll(D1_BADGE_SEL).length,
			carry: container.querySelectorAll(CARRY_MARKER_SEL).length,
			cpi: container.querySelectorAll(CPI_INFO_BADGE_SEL).length
		};
	}

	it('D1 signal varied ALONE (stale connection, no carry, no CPI-carry): only the badge renders', () => {
		const { container } = render(NavHistoryChart, {
			props: { points: FRESH_SERIES, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY, staleness: D1_STALE }
		});
		expect(counts(container)).toEqual({ badge: 1, carry: 0, cpi: 0 });
	});

	it('checkpoint-carry signal varied ALONE (no D1 staleness, no CPI-carry): only the carry marker renders', () => {
		const points = [FRESH('2026-01-15'), CHECKPOINT_CARRIED('2026-02-15', '2026-01-10'), FRESH('2026-03-15')];
		const { container } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(counts(container)).toEqual({ badge: 0, carry: 1, cpi: 0 });
	});

	it('CPI-carry signal varied ALONE (no D1 staleness, no checkpoint-carry): only the info-badge renders', () => {
		const points = [FRESH('2026-01-15'), CPI_CARRIED('2026-02-15'), FRESH('2026-03-15')];
		const { container } = render(NavHistoryChart, {
			props: { staleness: EMPTY_STALENESS, points, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY }
		});
		expect(counts(container)).toEqual({ badge: 0, carry: 0, cpi: 1 });
	});

	it('⭐ all THREE signals present at once: each renders independently — none suppresses or duplicates another', () => {
		const points = [
			FRESH('2026-01-15'),
			CHECKPOINT_CARRIED('2026-02-15', '2026-01-10'),
			CPI_CARRIED('2026-03-15'),
			FRESH('2026-04-15')
		];
		const { container } = render(NavHistoryChart, {
			props: { points, paramsError: null, params: PARAMS, boundary: EMPTY_NAV_BOUNDARY, staleness: D1_STALE }
		});
		// Exactly one of each — a collapse (two signals rendering as one element) would show up
		// as a count of 0 on one side and 2 on the other, or the wrong element under the wrong
		// role; a duplication would show up as >1 on a signal that should be singular.
		expect(counts(container)).toEqual({ badge: 1, carry: 1, cpi: 1 });
	});

	// FINAL BATTERY PASS addition (team-lead, post-442dac8): the badge is now TRI-STATE — the
	// UNKNOWN render (`.staleness-unknown`, a DIFFERENT class from the confirmed-stale
	// `.stale-connection-marker` counted above) must be independently isolable from the other two
	// signals too, same rigor as the confirmed-stale case.
	it('D1 UNKNOWN varied ALONE (staleness read failed, no carry, no CPI-carry): only the unknown note renders, never the confirmed-stale badge', () => {
		const { container } = render(NavHistoryChart, {
			props: {
				points: FRESH_SERIES,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY,
				staleness: { is_stale: null, stale_items: [] }
			}
		});
		expect(container.querySelectorAll('.staleness-unknown').length).toBe(1);
		expect(counts(container)).toEqual({ badge: 0, carry: 0, cpi: 0 });
	});

	it('D1 UNKNOWN + checkpoint-carry + CPI-carry all present at once: the unknown note and the two carry signals render independently, none suppresses another', () => {
		const points = [
			FRESH('2026-01-15'),
			CHECKPOINT_CARRIED('2026-02-15', '2026-01-10'),
			CPI_CARRIED('2026-03-15'),
			FRESH('2026-04-15')
		];
		const { container } = render(NavHistoryChart, {
			props: {
				points,
				paramsError: null,
				params: PARAMS,
				boundary: EMPTY_NAV_BOUNDARY,
				staleness: { is_stale: null, stale_items: [] }
			}
		});
		expect(container.querySelectorAll('.staleness-unknown').length).toBe(1);
		expect(counts(container)).toEqual({ badge: 0, carry: 1, cpi: 1 });
	});
});
