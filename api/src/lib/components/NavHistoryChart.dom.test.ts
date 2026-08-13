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
