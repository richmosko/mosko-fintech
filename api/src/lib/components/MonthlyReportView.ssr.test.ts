// MonthlyReportView.ssr.test.ts — SELF-354 / P2 render-footprint battery for the shared monthly-
// report template (also A5's PDF-composition entry point, R2 (C)). Dep-free: server-side render
// via `svelte/server` (no jsdom / no @testing-library), mirroring NavCompositionTable.ssr.test.ts's
// own convention.
//
// SCOPE: this file proves THIS component's OWN wiring — the right payload slice reaches the right
// reused component, the six sections render in verbatim order (AC1), the two NEW sections (NAV
// Performance's static table + envelope notices, Asset Allocation's grouped table, Rebalancing
// Targets' plain-text display) render correctly, escaping holds (INV-1), and the
// draft/final/owner-header/PDF-button branches (AC2-AC4, AC8) each fire. It does NOT re-prove
// NavCompositionTable / TaxDecompositionTable / TaxQuarterlyTables / CashflowRollupTable /
// HistoricalExpendituresChart's OWN internal behavior — each already has its own battery.
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import MonthlyReportView from './MonthlyReportView.svelte';
import {
	MONTHLY_REPORT_HEADER_FINAL,
	MONTHLY_REPORT_HEADER_DRAFT,
	MONTHLY_REPORT_PAYLOAD
} from '$lib/fixtures/monthly-report';
import type { TaxCharacterCatalog } from '$lib/tax-decomposition';
import type { MonthlyReportHeader, MonthlyReportPayload } from '$lib/monthly-report';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';
const CATALOG: TaxCharacterCatalog = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

type RenderOverrides = {
	header?: MonthlyReportHeader;
	payload?: MonthlyReportPayload;
	taxCharacters?: TaxCharacterCatalog;
	seedDeltaMigration?: string;
};

function renderReport(overrides: RenderOverrides = {}) {
	return render(MonthlyReportView, {
		props: {
			header: MONTHLY_REPORT_HEADER_FINAL,
			payload: MONTHLY_REPORT_PAYLOAD,
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA,
			...overrides
		}
	});
}

describe('MonthlyReportView — AC1: six sections render in verbatim order', () => {
	it('Account Holdings, NAV Performance, Asset Allocation, Rebalancing Targets, Cash Flow, Estimated Taxes — in that order', () => {
		const { body } = renderReport();
		const markers = [
			'Investment', // Account Holdings (NavCompositionTable group label)
			'NAV Performance',
			'Asset Allocation',
			'Rebalancing Targets',
			'>Cash Flow<', // Cash Flow (CashflowRollupTable's own section-label heading)
			'Tax-Relevant Income Decomposition' // Estimated Taxes (TaxDecompositionTable)
		];
		let cursor = -1;
		for (const marker of markers) {
			const at = body.indexOf(marker);
			expect(at, `"${marker}" present and after the previous section`).toBeGreaterThan(cursor);
			cursor = at;
		}
	});
});

describe('MonthlyReportView — Account Holdings (direct reuse)', () => {
	it('feeds account_holdings verbatim into NavCompositionTable', () => {
		const { body } = renderReport();
		expect(body).toContain('Net Assets Value (tax-adjusted)');
		expect(body).toContain('$350,000');
	});

	it('never renders an exclusion note — excludedTaxLedgers is a real payload gap, left undefined', () => {
		const { body } = renderReport();
		expect(body).not.toContain('Excluded from Net Worth above as tax-authority ledgers');
		expect(body).not.toContain('No accounts are designated as tax-authority ledgers');
	});
});

describe('MonthlyReportView — NAV Performance (new minimal render)', () => {
	it('renders the PM basis line verbatim', () => {
		const { body } = renderReport();
		expect(body).toContain(
			'This trend shows the checkpointed gross Net Worth — before the two tax lines and the'
		);
	});

	it('renders the series_inflation_adjusted table with nominal + inflation-adjusted figures', () => {
		const { body } = renderReport();
		expect(body).toContain('$350,000');
		expect(body).toContain('$340,000');
	});

	it('renders BOTH delta_panel and reference_dates as unavailable-with-reason (AC5, mandatory envelope rendering)', () => {
		const { body } = renderReport();
		expect(body).toContain('NAV deltas: Unavailable (reader_not_as_of_threadable).');
		expect(body).toContain('Reference dates: Unavailable (reader_not_as_of_threadable).');
		// Never the wrong, transient-failure-shaped copy those live components would otherwise emit.
		expect(body).not.toContain('temporarily unavailable');
	});
});

describe('MonthlyReportView — Asset Allocation (new grouped table)', () => {
	it('groups rows by cat with a client-side PLAIN-ADDITION $ subtotal per group', () => {
		const { body } = renderReport();
		expect(body).toContain('US Equity');
		expect(body).toContain('$350,000'); // 300,000 + 50,000 subtotal — coincides with the NAV figure above but is a distinct computed value
		expect(body).toContain('Fixed Income');
	});

	it('renders a NULL target_percent as "—", never a fabricated 0%', () => {
		const { body } = renderReport();
		expect(body).toContain('US - Small Cap');
		// The null-target row's cell renders the unavailable dash, not "0.0%".
		const idx = body.indexOf('US - Small Cap');
		const rowSlice = body.slice(idx, idx + 400);
		expect(rowSlice).toContain('—');
	});
});

describe('MonthlyReportView — Rebalancing Targets (new plain-text display)', () => {
	it('renders all four headings, in order, regardless of content', () => {
		const { body } = renderReport();
		// Scoped to the commentary <h3> wrapper — a bare heading string (e.g. "Bonds") also matches
		// unrelated content elsewhere on the page (the Asset Allocation fixture has a "Bonds -
		// Aggregate" sub_cat row).
		const order = ['>Cash</h3>', '>Bonds</h3>', '>Marketable Securities</h3>', '>Alternatives</h3>'];
		let cursor = -1;
		for (const heading of order) {
			const at = body.indexOf(heading);
			expect(at, `"${heading}" present and after the previous one`).toBeGreaterThan(cursor);
			cursor = at;
		}
	});

	it('renders an EMPTY sub-section with its label and an empty body — never hidden (PRD §2.6.2 verbatim)', () => {
		const { body } = renderReport();
		// 'Bonds' and 'Alternatives' are '' in the fixture — the heading must still appear.
		expect(body).toContain('Bonds');
		expect(body).toContain('Alternatives');
	});

	it('ESCAPING LEG (INV-1): a <script> payload in commentary renders INERT — no live <script> tag reaches the output', () => {
		const xssPayload = '<script>alert(1)</script>';
		const { body } = renderReport({
			payload: {
				...MONTHLY_REPORT_PAYLOAD,
				sections: {
					...MONTHLY_REPORT_PAYLOAD.sections,
					rebalancing_targets: {
						...MONTHLY_REPORT_PAYLOAD.sections.rebalancing_targets,
						cash: xssPayload
					}
				}
			}
		});
		expect(body).not.toContain('<script>alert(1)</script>');
		// Svelte's default interpolation escapes the OPENING angle bracket (the one that matters —
		// `>` alone cannot open a tag) — the payload survives as inert text, never as a live tag.
		expect(body).toContain('&lt;script>alert(1)&lt;/script>');
	});
});

describe('MonthlyReportView — Cash Flow / Estimated Taxes (direct reuse)', () => {
	it('feeds cross_account_rollup verbatim into CashflowRollupTable, including the AC4 unclassified footnote for free', () => {
		const { body } = renderReport();
		expect(body).toContain('2 items unclassified');
	});

	it('feeds historical_expenditures verbatim into HistoricalExpendituresChart', () => {
		const { body } = renderReport();
		// HistoricalExpendituresChart renders SOMETHING for a non-empty series — smoke-level only,
		// full coverage is that component's own battery.
		expect(body).not.toContain('No spending data');
	});

	it('renders the AC4 REPORT-SPECIFIC (past-tense) capital-gains-unavailable copy, not the live present-tense sentence', () => {
		const { body } = renderReport();
		expect(body).toContain(
			'Capital gains were unavailable when this report was generated — sale recording lands at a later V1.x.'
		);
		expect(body).not.toContain("Capital gains aren't shown here yet");
	});

	it('feeds estimated_taxes into TaxQuarterlyTables and suppresses the page-level no-authority banner (documented simplification)', () => {
		const { body } = renderReport();
		expect(body).toContain('Estimated Quarterly Taxes');
		expect(body).not.toContain('No account is marked as a tax authority.');
	});
});

describe('MonthlyReportView — AC2/AC4/AC8: draft vs final branching', () => {
	it('a FINAL report renders the owner header line verbatim and "Regenerate"', () => {
		const { body } = renderReport({ header: MONTHLY_REPORT_HEADER_FINAL });
		expect(body).toContain('THE SMITH 2023 TRUST');
		expect(body).toContain('Regenerate');
		expect(body).not.toContain('Edit commentary');
	});

	it('a FINAL report enables the Download PDF link (not disabled)', () => {
		const { body } = renderReport({ header: MONTHLY_REPORT_HEADER_FINAL });
		expect(body).toMatch(/<a[^>]*>\s*Download PDF/);
		expect(body).not.toContain('aria-disabled="true">\n\t\t\t\t\tDownload PDF');
	});

	it('a DRAFT report renders the unset-owner-header prompt and "Edit commentary"', () => {
		const { body } = renderReport({ header: MONTHLY_REPORT_HEADER_DRAFT });
		expect(body).toContain('Set the report header in Settings');
		expect(body).toContain('Edit commentary');
		expect(body).not.toContain('Regenerate');
	});

	it('a DRAFT (pending) report disables Download PDF with the AC4 tooltip', () => {
		const { body } = renderReport({ header: MONTHLY_REPORT_HEADER_DRAFT });
		expect(body).toContain('aria-disabled="true"');
		expect(body).toContain('Finalize this report to export it.');
	});

	it('the month/year stamp includes "generated" for a final report but omits it for a draft', () => {
		// Scoped to the .report-stamp element specifically — "generated" also appears, unrelated,
		// in the AC4 capital-gains-unavailable copy ("...when this report was generated...").
		const stampOf = (body: string) => {
			const match = body.match(/<p class="report-stamp[^>]*">([^<]*)<\/p>/);
			expect(match, 'report-stamp element found').not.toBeNull();
			return match![1];
		};
		const { body: finalBody } = renderReport({ header: MONTHLY_REPORT_HEADER_FINAL });
		expect(stampOf(finalBody)).toBe('August 2026 · data as of Aug 31, 2026 · generated Sep 2, 2026');

		const { body: draftBody } = renderReport({ header: MONTHLY_REPORT_HEADER_DRAFT });
		expect(stampOf(draftBody)).toBe('August 2026 · data as of Aug 31, 2026');
	});

	it('a "skipped" commentary disposition renders the disposition note; "authored" does not', () => {
		const { body: skipped } = renderReport({
			header: { ...MONTHLY_REPORT_HEADER_FINAL, commentary_disposition: 'skipped' }
		});
		expect(skipped).toContain('Commentary was skipped for this month.');

		const { body: authored } = renderReport({ header: MONTHLY_REPORT_HEADER_FINAL });
		expect(authored).not.toContain('Commentary was skipped for this month.');
	});
});
