// MonthlyReportView.cssCoverage.test.ts — P10 item (e): every `svelte-[a-z0-9]+` scoped-class
// token that appears in MonthlyReportView's server-rendered body (across the fixtures needed to
// reach every conditional branch) must match >= 1 selector in the committed report.css build
// artifact (api/src/lib/generated/report.css, SELF-358 / P6, Architect's Option A ruling —
// self358-css-ruling.md). A SINGLE default fixture undercounts: Backend measured 4 of 14 distinct
// svelte-hash groups uncovered by one render — this file's fixture VARIANTS are chosen specifically
// to reach the conditional branches that carry those groups (draft vs final, report-level stale vs
// healthy, per-row cashflow staleness populated vs the zero-footprint default).
//
// ⚠ SCOPED TO SELECTOR SYNTAX, NOT A RAW SUBSTRING SEARCH — the AC's own warning: a naive
// substring regex over an arbitrary CSS file can hit an HTML-tag-shaped (or here, hash-shaped)
// string sitting inside a COMMENT rather than a real selector (this repo's hand-authored
// tokens.css carries comments; report.css is machine-generated and carries none today, but the
// extraction below matches only `.svelte-xxxxx` immediately after a selector dot-boundary, so it
// stays correct if this pattern is ever reused against a commented file).
//
// @vitest-environment node
import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
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
import {
	EMPTY_CASHFLOW_ROW_STALENESS_MAP,
	type CashflowRowStalenessMap
} from '$lib/cashflow-row-staleness';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';
const CATALOG: TaxCharacterCatalog = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

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

// Keyed to MONTHLY_REPORT_PAYLOAD's own cross_account_rollup cat/sub_cat values (Revenue/Salary,
// Expense/Rent) so the lookup actually resolves to these entries rather than the map's own
// missing-key UNKNOWN default — a map with the WRONG keys would render identically to the empty
// default and this leg's own non-vacuous precondition below would catch that.
const CASHFLOW_ROW_STALE: CashflowRowStalenessMap = {
	Revenue: { Salary: { is_stale: true, staleAccountNames: ['Chase Checking'] } },
	Expense: { Rent: { is_stale: false, staleAccountNames: [] } }
};

type RenderOverrides = {
	header?: MonthlyReportHeader;
	payload?: MonthlyReportPayload;
	taxCharacters?: TaxCharacterCatalog;
	seedDeltaMigration?: string;
	staleness?: StalenessData;
	cashflowRowStaleness?: CashflowRowStalenessMap;
	staleAccountNames?: string[];
	renderContext?: 'browser' | 'print';
};

// A deep clone of the shared payload with ONE historical_expenditures point marked
// `cpi_is_carried: true` — `HistoricalExpendituresChart` only mounts `InformationalMarkerBadge`
// (svelte-1hsjqhs) when a carried-forward CPI point exists (`latestCarried`); the shared fixture's
// own single point is NOT carried, so no existing test in this tree reaches that branch.
const PAYLOAD_WITH_CARRIED_CPI: MonthlyReportPayload = structuredClone(MONTHLY_REPORT_PAYLOAD);
PAYLOAD_WITH_CARRIED_CPI.sections.cash_flow.historical_expenditures =
	PAYLOAD_WITH_CARRIED_CPI.sections.cash_flow.historical_expenditures.map((pt) => ({
		...pt,
		cpi_is_carried: true,
		cpi_carried_from: '2026-06'
	}));

function renderReport(overrides: RenderOverrides = {}) {
	return render(MonthlyReportView, {
		props: {
			header: MONTHLY_REPORT_HEADER_FINAL,
			payload: MONTHLY_REPORT_PAYLOAD,
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA,
			staleness: EMPTY_STALENESS,
			cashflowRowStaleness: EMPTY_CASHFLOW_ROW_STALENESS_MAP,
			staleAccountNames: [],
			...overrides
		}
	});
}

// Every fixture variant needed to reach every conditional branch this component's tree carries —
// each one's own reason is stated so a future reader can tell which branch it targets, and so a
// missing branch is added here rather than the assertion below being loosened to match.
const VARIANTS: Array<{ label: string; overrides: RenderOverrides }> = [
	{ label: 'final, healthy (this file-tree\'s own default elsewhere)', overrides: {} },
	{
		label: 'draft (the unset-owner-header / "Edit commentary" branch, AC2-AC4)',
		overrides: { header: MONTHLY_REPORT_HEADER_DRAFT }
	},
	{
		label: 'report-level stale + non-empty P8 banner (AC3/AC7 + per-section badges, AC2/AC4)',
		overrides: { staleness: STALE, staleAccountNames: ['Chase Checking', 'Fidelity Brokerage'] }
	},
	{
		label: 'per-row cashflow staleness populated (a stale row and a fresh row both present)',
		overrides: { cashflowRowStaleness: CASHFLOW_ROW_STALE }
	},
	{
		label:
			'renderContext="print" (SELF-358/P6): HistoricalExpendituresChart draws its SVG bars ' +
			'from fixed print dimensions instead of waiting on a ResizeObserver, which never fires ' +
			'under svelte/server (no DOM) — the default "browser" context leaves the chart-canvas ' +
			'empty in SSR, which is exactly why the PDF export route passes "print" explicitly',
		overrides: { renderContext: 'print' }
	},
	{
		label:
			'a carried-forward CPI point (cpi_is_carried: true) mounts InformationalMarkerBadge — ' +
			'combined with "print" so the badge AND the bars both reach the SSR output in one render',
		overrides: { payload: PAYLOAD_WITH_CARRIED_CPI, renderContext: 'print' }
	}
];

describe("MonthlyReportView — P10 item (e): report.css hash-coverage", () => {
	let cssHashes: Set<string>;
	let renderedTokens: Set<string>;

	beforeAll(() => {
		const here = dirname(fileURLToPath(import.meta.url));
		const cssPath = join(here, '..', 'generated', 'report.css');
		const css = readFileSync(cssPath, 'utf-8');
		cssHashes = new Set(Array.from(css.matchAll(/\.svelte-([a-z0-9]+)\b/g)).map((m) => m[1]));

		// THIRD-PARTY LIBRARY WRAPPER CLASSES, excluded by design (measured, not assumed): the
		// `print`-context variants below mount LayerCake's own `<LayerCake>`/`<Svg>` wrapper
		// elements (HistoricalExpendituresChart imports them directly from the `layercake` npm
		// package — see that file's own header), which stamp THEIR OWN scoped classes
		// (`layercake-container`, `layercake-layout-svg`) under a svelte-hash that belongs to
		// LayerCake's compiled source, not this app's. report.css's build (vite.report-css.config.mjs,
		// a standalone lib build over THIS app's own src/lib/components) correctly does not carry
		// them — this app never writes a selector for library-internal wrapper markup it does not
		// own. Verified live: both hashes' paired class names, dumped from the actual render, are
		// `layercake-container` and `layercake-layout-svg` — excluded BY NAME, not by hash, so a
		// REAL future gap (an app-owned class the build genuinely dropped) still reds this leg.
		const THIRD_PARTY_CLASS_PREFIXES = ['layercake-'];

		renderedTokens = new Set();
		for (const { overrides } of VARIANTS) {
			const { body } = renderReport(overrides);
			for (const m of body.matchAll(/class="([^"]*)"/g)) {
				const classAttr = m[1];
				const hashMatch = classAttr.match(/\bsvelte-([a-z0-9]+)\b/);
				if (!hashMatch) continue;
				const isThirdParty = THIRD_PARTY_CLASS_PREFIXES.some((prefix) =>
					classAttr.split(/\s+/).some((cls) => cls.startsWith(prefix))
				);
				if (isThirdParty) continue;
				renderedTokens.add(hashMatch[1]);
			}
		}
	});

	it('NON-VACUOUS PRECONDITION: report.css carries a plural set of distinct svelte-hash groups', () => {
		expect(cssHashes.size).toBeGreaterThan(1);
	});

	it('NON-VACUOUS PRECONDITION: the chosen fixture variants render a plural set of distinct svelte-hash tokens — a single fixture undercounting is the exact defect this leg exists to catch', () => {
		expect(renderedTokens.size).toBeGreaterThan(1);
	});

	it('THE LEG: every svelte-hash token rendered across the chosen fixture variants matches >= 1 selector in report.css', () => {
		const missing = Array.from(renderedTokens).filter((t) => !cssHashes.has(t));
		expect(missing, `tokens rendered but absent from report.css: ${missing.join(', ')}`).toEqual([]);
	});

	it("COVERAGE, STATED NOT ASSUMED: the fixture variants reach ALL of report.css's own distinct svelte-hash groups, not merely a subset that happens not to be missing", () => {
		const uncovered = Array.from(cssHashes).filter((t) => !renderedTokens.has(t));
		expect(
			uncovered,
			`report.css groups never reached by any fixture variant: ${uncovered.join(', ')}`
		).toEqual([]);
	});
});
