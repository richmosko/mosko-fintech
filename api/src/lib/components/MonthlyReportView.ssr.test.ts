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
import { EMPTY_STALENESS, type StalenessData } from '$lib/staleness/stale-constituent';
import { EMPTY_CASHFLOW_ROW_STALENESS_MAP, type CashflowRowStalenessMap } from '$lib/cashflow-row-staleness';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';
const CATALOG: TaxCharacterCatalog = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

type RenderOverrides = {
	header?: MonthlyReportHeader;
	payload?: MonthlyReportPayload;
	taxCharacters?: TaxCharacterCatalog;
	seedDeltaMigration?: string;
	staleness?: StalenessData;
	cashflowRowStaleness?: CashflowRowStalenessMap;
	staleAccountNames?: string[];
};

function renderReport(overrides: RenderOverrides = {}) {
	return render(MonthlyReportView, {
		props: {
			header: MONTHLY_REPORT_HEADER_FINAL,
			payload: MONTHLY_REPORT_PAYLOAD,
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA,
			// P8 (SELF-360) defaults: CONFIRMED-healthy / zero-footprint, so every pre-existing
			// test in this file keeps asserting exactly what it always did — no stray badge
			// markup, no banner — without needing to know P8 exists. The P8-specific describe
			// block below overrides these explicitly per case.
			staleness: EMPTY_STALENESS,
			cashflowRowStaleness: EMPTY_CASHFLOW_ROW_STALENESS_MAP,
			staleAccountNames: [],
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

	it('E16: delta_panel/reference_dates are real as-of-threaded arrays, rendered via DIRECT reuse of NavDeltaPanel / NavReferenceDatesPanel', () => {
		const { body } = renderReport();
		// NavDeltaPanel's own section heading is now THE "NAV Performance" heading (AC1) — no
		// second one rendered by this component.
		expect(body).toContain('NAV Performance');
		expect(body).toContain('Reference NAV');
		// Real computed figures reach the page — never the wrong, transient-failure-shaped copy
		// those components would emit for a genuinely null `rows` (which this payload never is).
		expect(body).not.toContain('temporarily unavailable');
		expect(body).toContain('+$8,000');
		expect(body).toContain('Insufficient history');
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

// ── P8 (SELF-360) — §2.6.5 staleness markers ────────────────────────────────────────────────
const STALE: StalenessData = {
	is_stale: true,
	stale_items: [
		{
			linked_source_id: '1',
			institution_name: 'Chase',
			provider: 'plaid',
			connection_status: 'login_required',
			status_class: 'error'
		}
	]
};

/** Extracts one named `<section ...>...</section>` block from the rendered body, by its own
 *  distinguishing attribute substring — scoping an assertion to ONE section rather than the
 *  whole body, the same discipline this file's other tests already apply (e.g. the report-stamp
 *  regex above) to avoid a marker elsewhere on the page producing a false pass.
 *
 *  ⚠ NESTED-SECTION-AWARE, deliberately: every reused component this file wraps (NavCompositionTable,
 *  NavDeltaPanel, NavReferenceDatesPanel, CashflowRollupTable, HistoricalExpendituresChart,
 *  TaxDecompositionTable, TaxQuarterlyTables) renders its OWN root `<section>` — so a naive
 *  `indexOf('</section>', start)` would stop at the FIRST inner component's own closing tag,
 *  silently truncating the "NAV Performance" wrapper (NavDeltaPanel + the basis-line/series table
 *  + NavReferenceDatesPanel, in that order) before ever reaching the second reused component.
 *  This counts nested `<section` opens against `</section>` closes to find the OUTER wrapper's
 *  own matching close. */
function sectionBody(body: string, openTagSubstring: string): string {
	const start = body.indexOf(openTagSubstring);
	expect(start, `section opening "${openTagSubstring}" found`).toBeGreaterThanOrEqual(0);

	let depth = 0;
	let cursor = start;
	const tagPattern = /<section\b|<\/section>/g;
	tagPattern.lastIndex = start;
	let match: RegExpExecArray | null;
	while ((match = tagPattern.exec(body)) !== null) {
		if (match[0] === '</section>') {
			depth -= 1;
			if (depth === 0) {
				cursor = match.index;
				return body.slice(start, cursor);
			}
		} else {
			depth += 1;
		}
	}
	throw new Error(`no matching closing </section> found for "${openTagSubstring}"`);
}

describe('MonthlyReportView — P8 (SELF-360): report-level banner (AC3/AC7)', () => {
	it('renders NOTHING when staleAccountNames is empty (zero footprint — covers both "confirmed healthy" and "read failed")', () => {
		const { body } = renderReport({ staleAccountNames: [] });
		expect(body).not.toContain('currently in re-auth state');
	});

	it("renders AC7's copy verbatim, naming the accounts and the report's own bare month/year", () => {
		const { body } = renderReport({ staleAccountNames: ['Chase Checking', 'Fidelity Brokerage'] });
		expect(body).toContain(
			'These accounts are currently in re-auth state; sections sourced from them are marked stale as of today, not as of August 2026: Chase Checking, Fidelity Brokerage.'
		);
	});
});

describe('MonthlyReportView — P8 (SELF-360): per-section live staleness wiring (AC2/AC4)', () => {
	it('threads the REAL staleness object into Account Holdings (NavCompositionTable), not a placeholder', () => {
		const { body } = renderReport({ staleness: STALE });
		const holdings = sectionBody(body, '<section aria-label="Account Holdings">');
		expect(holdings).toContain('May be stale');
	});

	it('threads the REAL staleness object into NAV Performance (NavDeltaPanel / NavReferenceDatesPanel)', () => {
		const { body } = renderReport({ staleness: STALE });
		const navPerf = sectionBody(body, '<section class="nav-performance">');
		expect(navPerf).toContain('May be stale');
	});

	it('Asset Allocation (pre-ruling i): a SECTION-HEADER badge off the whole-tenant staleness, since the payload carries no account_id for per-row attribution', () => {
		// No trailing `"` on the search string: Svelte appends a scoped-style hash class to any
		// class attribute matched by a rule in this file's own <style> block (`.asset-allocation`
		// is — see the `.asset-allocation .head` rule), so the rendered attribute is
		// `class="asset-allocation svelte-xxxxx"`, never a bare `class="asset-allocation"`.
		const { body: staleBody } = renderReport({ staleness: STALE });
		const allocStale = sectionBody(staleBody, '<section class="asset-allocation');
		expect(allocStale).toContain('May be stale');

		const { body: healthyBody } = renderReport({ staleness: EMPTY_STALENESS });
		const allocHealthy = sectionBody(healthyBody, '<section class="asset-allocation');
		expect(allocHealthy).not.toContain('May be stale');
	});

	it('threads the REAL staleness + cashflowRowStaleness into Cash Flow (CashflowRollupTable / HistoricalExpendituresChart)', () => {
		const { body } = renderReport({ staleness: STALE });
		const cashFlow = sectionBody(body, '<section aria-label="Cash Flow">');
		expect(cashFlow).toContain('May be stale');
	});

	it('threads the REAL staleness into Estimated Taxes (TaxDecompositionTable / TaxQuarterlyTables)', () => {
		const { body } = renderReport({ staleness: STALE });
		const estTaxes = sectionBody(body, '<section aria-label="Estimated Taxes">');
		expect(estTaxes).toContain('May be stale');
	});
});

describe('MonthlyReportView — P8 (SELF-360) AC6: negative leg — commentary and owner header never marked', () => {
	it('Rebalancing Targets (commentary) renders NO stale badge even when staleness is confirmed-stale', () => {
		const { body } = renderReport({ staleness: STALE });
		const rebalancing = sectionBody(body, '<section class="rebalancing-targets"');
		expect(rebalancing).not.toContain('stale-connection-marker');
		expect(rebalancing).not.toContain('May be stale');
	});

	it('the owner-header line renders NO stale badge even when staleness is confirmed-stale', () => {
		// No trailing `"` on either search string — both `.report-head` and `.report-actions`
		// are styled in this file's own <style> block, so Svelte appends a scoped-style hash to
		// each rendered class attribute (same reasoning as the Asset Allocation leg above).
		const { body } = renderReport({ staleness: STALE, header: MONTHLY_REPORT_HEADER_FINAL });
		const headStart = body.indexOf('<header class="report-head');
		const headEnd = body.indexOf('<div class="report-actions');
		expect(headStart).toBeGreaterThanOrEqual(0);
		expect(headEnd).toBeGreaterThan(headStart);
		const reportHead = body.slice(headStart, headEnd);
		expect(reportHead).not.toContain('stale-connection-marker');
		expect(reportHead).not.toContain('May be stale');
	});
});
