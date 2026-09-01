// HistoricalExpendituresChart.dom.test.ts — SELF-256 §2.3.4 chart battery. Proves the
// placeholder-state gating (read-failed vs genuinely-empty must never collapse — mirrors
// NavHistoryChart.dom.test.ts's own rationale), the AC9 unclassified banner/caption's N-gate
// (null vs 0 vs >0 — three distinguishable states, never conflated), the AC5 partial-history
// legend fallback, and the AC6 whole-series-CPI-unavailable nominal fallback.
//
// SCOPE NOTE: this does not assert exact SVG bar/path geometry — same jsdom/ResizeObserver
// caveat as NavHistoryChart.dom.test.ts. The pure MATH (segments, y-domain, per-row unavailable
// detection) is covered node-side, DOM-free, in historical-expenditures.test.ts.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import HistoricalExpendituresChart from './HistoricalExpendituresChart.svelte';
import type { HistoricalExpenditurePoint } from '$lib/historical-expenditures';

// jsdom has no ResizeObserver — same no-op stub as NavHistoryChart.dom.test.ts; LayerCake needs
// it present to mount without throwing, and this suite doesn't assert on real pixel layout.
class ResizeObserverStub {
	observe() {}
	unobserve() {}
	disconnect() {}
}
globalThis.ResizeObserver ??= ResizeObserverStub;

function point(overrides: Partial<HistoricalExpenditurePoint>): HistoricalExpenditurePoint {
	return {
		month_end: '2026-01-31',
		expense_monthly_nominal: 1_000,
		expense_monthly_inflation_adjusted: 950,
		rolling_12mo_avg_inflation_adjusted: 900,
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

// A well-formed 13-month series so the rolling average is present on at least the last row
// (AC5: the first 11 months of ANY series carry no rolling average — this fixture starts the
// rolling figure at month 12, matching 096's own contract).
const POPULATED = Array.from({ length: 13 }, (_, i) =>
	point({
		month_end: `202${5 + Math.floor((6 + i) / 12)}-${String(((6 + i) % 12) + 1).padStart(2, '0')}-28`,
		expense_monthly_nominal: 1_000 + i * 10,
		expense_monthly_inflation_adjusted: 950 + i * 9,
		rolling_12mo_avg_inflation_adjusted: i < 11 ? null : 900 + i * 5
	})
);

describe('HistoricalExpendituresChart — placeholder-state gating never collapses distinct states', () => {
	it('points === null (read failed): renders the unavailable notice, never the empty-classify copy', () => {
		const { getByText, queryByText } = render(HistoricalExpendituresChart, {
			props: { points: null }
		});
		expect(getByText(/temporarily unavailable/)).toBeTruthy();
		expect(queryByText(/Classify your expense transactions/)).toBeNull();
	});

	it('points === [] (genuinely empty): renders the AC10 classify-CTA copy, never the unavailable notice', () => {
		const { getByText, queryByText } = render(HistoricalExpendituresChart, {
			props: { points: [] }
		});
		expect(getByText(/Classify your expense transactions to see your historical expenditures/)).toBeTruthy();
		expect(getByText('Classify transactions')).toBeTruthy();
		expect(queryByText(/temporarily unavailable/)).toBeNull();
	});
});

describe('HistoricalExpendituresChart — AC9 unclassified banner: three distinguishable N states', () => {
	it('unclassifiedCount === null (not yet computed): renders NO banner and NO caption', () => {
		const { queryByText, queryByRole } = render(HistoricalExpendituresChart, {
			props: { points: POPULATED, unclassifiedCount: null }
		});
		expect(queryByRole('status', { name: /unclassified/i })).toBeNull();
		expect(queryByText(/bars partial/i)).toBeNull();
	});

	it('unclassifiedCount === 0: renders NO banner and NO caption (a real, distinguishable zero)', () => {
		const { queryByText } = render(HistoricalExpendituresChart, {
			props: { points: POPULATED, unclassifiedCount: 0 }
		});
		expect(queryByText(/unclassified/i)).toBeNull();
	});

	it('unclassifiedCount > 0: renders the banner (S-2 copy, never claims the items ARE expenses) + caption', () => {
		const { getByText } = render(HistoricalExpendituresChart, {
			props: { points: POPULATED, unclassifiedCount: 4 }
		});
		expect(getByText('4 items unclassified — any of these may be expenses')).toBeTruthy();
		expect(getByText('classify')).toBeTruthy();
		expect(getByText(/Bars partial — 4 unclassified/)).toBeTruthy();
	});
});

describe('HistoricalExpendituresChart — AC6 whole-series CPI-unavailable fallback', () => {
	it('every row unresolvable: falls back to the nominal legend + basis note, never a hatched-out chart', () => {
		const allUnavailable = POPULATED.map((p) =>
			point({ ...p, expense_monthly_inflation_adjusted: null, rolling_12mo_avg_inflation_adjusted: null, cpi_coverage_through: null })
		);
		const { getByText, queryByText } = render(HistoricalExpendituresChart, {
			props: { points: allUnavailable }
		});
		expect(getByText('Monthly Expenses (Nominal)')).toBeTruthy();
		expect(getByText(/Inflation-adjusted figures are unavailable — no CPI-U data on record\. Showing nominal figures\./)).toBeTruthy();
		expect(queryByText('12-Month Rolling Average')).toBeNull();
	});

	it('a normal series renders the adjusted legend + CPI-U basis line, not the fallback note', () => {
		const { getByText, queryByText } = render(HistoricalExpendituresChart, {
			props: { points: POPULATED }
		});
		expect(getByText('Monthly Expenses (Inflation-Adjusted)')).toBeTruthy();
		expect(getByText('12-Month Rolling Average')).toBeTruthy();
		expect(getByText(/CPI-U through/)).toBeTruthy();
		expect(queryByText(/Showing nominal figures/)).toBeNull();
	});
});

describe('HistoricalExpendituresChart — AC8 tooltip content', () => {
	it('a per-bar hit target carries the full tooltip text as its accessible name', () => {
		const single = [point({ month_end: '2026-01-31', expense_monthly_nominal: 1234, expense_monthly_inflation_adjusted: 1100 })];
		const { getByRole } = render(HistoricalExpendituresChart, {
			props: { points: single }
		});
		const hit = getByRole('button', { name: /Jan 26/ });
		expect(hit.getAttribute('aria-label')).toContain('$1,234.00');
		expect(hit.getAttribute('aria-label')).toContain('$1,100.00');
	});

	it('AC6: an unavailable month\'s hit target names the reason instead of a dollar figure', () => {
		const single = [point({ month_end: '2026-01-31', cpi_value: null, expense_monthly_inflation_adjusted: null })];
		const { getByRole } = render(HistoricalExpendituresChart, {
			props: { points: single }
		});
		const hit = getByRole('button', { name: /Jan 26/ });
		expect(hit.getAttribute('aria-label')).toContain('Unavailable');
	});
});

describe('HistoricalExpendituresChart — no leaked doc-comment text (regression watcher)', () => {
	// A shipped defect (caught live by QA, not by any prior test — the walk was the one-time
	// check; THIS is the durable boundary watcher that keeps it caught): the module's own header
	// doc comment quoted a literal `<!-- SELF-258 seam -->` example INSIDE itself. HTML comments
	// don't nest — the browser (and Svelte's own template parser, which this render() path
	// exercises for real, not a string-level check) closes the OUTER comment at the example's
	// own `-->`, and everything after it up to the file's real closing `-->` stops being a
	// comment at all and renders as literal visible page text. A generic "no stray `-->` reaches
	// the DOM" check, rather than one pinned to today's exact leaked wording, is what catches the
	// NEXT nested-example edit too, not just this one.
	it('no "-->" token and no doc-comment prose reach rendered text, across every render state', () => {
		const fixtures: (HistoricalExpenditurePoint[] | null)[] = [
			null, // read-failed
			[], // empty
			POPULATED // normal
		];
		for (const fixture of fixtures) {
			const { container, unmount } = render(HistoricalExpendituresChart, {
				props: { points: fixture, unclassifiedCount: 3 }
			});
			expect(container.textContent).not.toContain('-->');
			// Distinctive phrases from the module's own doc comment — would only appear in
			// rendered text if SOME comment in this file leaked, regardless of which one.
			expect(container.textContent).not.toContain('ADR-013 P5');
			expect(container.textContent).not.toContain('mount point');
			unmount();
		}
	});
});
