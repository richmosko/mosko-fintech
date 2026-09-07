// MonthlyReportView.renderContextParity.test.ts — P10 item (f): the browser/print one-template
// parity leg for `renderContext`. MonthlyReportView.svelte's own header states the guarantee this
// leg proves: "'renderContext' ... SIZING ONLY, passed straight through to
// HistoricalExpendituresChart ... Must never gate rendered CONTENT here or anywhere downstream —
// AC3's one-template guarantee depends on that." This file is that guarantee, falsifiable.
//
// MECHANISM (measured, not assumed — see HistoricalExpendituresChart.svelte's own header):
// `renderContext: 'browser'` (the default) lets LayerCake auto-measure its container via
// ResizeObserver, which never fires under `svelte/server` (no DOM) — so under SSR the chart-canvas
// renders EMPTY. `renderContext: 'print'` draws from a FIXED PRINT_CHART_HEIGHT instead, so the
// PDF export route (which always renders via svelte/server) passes it explicitly. This is why the
// two renders are NOT literally byte-identical everywhere: the chart-canvas subtree is the one
// place `renderContext` is WIRED to change anything, by design, and this leg proves the difference
// is confined to exactly that subtree — not merely "close enough" or "everything looked fine".
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import MonthlyReportView from './MonthlyReportView.svelte';
import {
	MONTHLY_REPORT_HEADER_FINAL,
	MONTHLY_REPORT_PAYLOAD
} from '$lib/fixtures/monthly-report';
import type { TaxCharacterCatalog } from '$lib/tax-decomposition';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import { EMPTY_CASHFLOW_ROW_STALENESS_MAP } from '$lib/cashflow-row-staleness';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';
const CATALOG: TaxCharacterCatalog = [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }];

function renderReport(renderContext: 'browser' | 'print') {
	return render(MonthlyReportView, {
		props: {
			header: MONTHLY_REPORT_HEADER_FINAL,
			payload: MONTHLY_REPORT_PAYLOAD,
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA,
			staleness: EMPTY_STALENESS,
			cashflowRowStaleness: EMPTY_CASHFLOW_ROW_STALENESS_MAP,
			staleAccountNames: [],
			renderContext
		}
	});
}

/** Extracts the `<div class="chart-canvas ...">...</div>` subtree by depth-counting nested `<div`
 *  opens against `</div>` closes — the same discipline MonthlyReportView.ssr.test.ts's own
 *  `sectionBody` helper applies to `<section>`, for the same reason: a naive `indexOf('</div>',
 *  start)` would stop at the FIRST inner `<div>`'s own close (LayerCake nests its own wrapper divs
 *  inside chart-canvas) and silently truncate the extraction. Returns `{ before, inner, after }` so
 *  the caller can splice `inner` out and compare `before + after` across two renders. */
function extractChartCanvas(body: string): { before: string; inner: string; after: string } {
	const openTag = /<div class="chart-canvas[^"]*"[^>]*>/;
	const openMatch = openTag.exec(body);
	expect(openMatch, 'chart-canvas opening div found').not.toBeNull();
	const start = openMatch!.index;
	const innerStart = start + openMatch![0].length;

	let depth = 1;
	const tagPattern = /<div\b[^>]*>|<\/div>/g;
	tagPattern.lastIndex = innerStart;
	let match: RegExpExecArray | null;
	while ((match = tagPattern.exec(body)) !== null) {
		if (match[0] === '</div>') {
			depth -= 1;
			if (depth === 0) {
				return {
					before: body.slice(0, start),
					inner: body.slice(innerStart, match.index),
					after: body.slice(match.index + '</div>'.length)
				};
			}
		} else {
			depth += 1;
		}
	}
	throw new Error('no matching closing </div> found for chart-canvas');
}

describe('MonthlyReportView — P10 item (f): browser/print renderContext parity', () => {
	const browser = renderReport('browser');
	const print = renderReport('print');

	it('NON-VACUOUS PRECONDITION: the two renders are not trivially identical strings (renderContext genuinely changes SOMETHING, which is what makes the "except the chart" scoping below a real claim rather than a vacuous one)', () => {
		expect(browser.body).not.toEqual(print.body);
	});

	it('THE LEG: outside the chart-canvas subtree, the two renders are BYTE-IDENTICAL — renderContext never gates content anywhere else in the tree (MonthlyReportView\'s own AC3 guarantee, falsified here rather than merely quoted)', () => {
		const b = extractChartCanvas(browser.body);
		const p = extractChartCanvas(print.body);
		expect(b.before).toEqual(p.before);
		expect(b.after).toEqual(p.after);
	});

	it('THE DIFFERENCE IS REAL AND NAMED, not merely "the leg happened to slice something": "browser" SSR leaves the chart-canvas effectively empty (no ResizeObserver fires under svelte/server) while "print" draws real LayerCake geometry from the fixed PRINT_CHART_HEIGHT', () => {
		const b = extractChartCanvas(browser.body);
		const p = extractChartCanvas(print.body);
		expect(p.inner).toContain('layercake-layout-svg');
		expect(b.inner).not.toContain('layercake-layout-svg');
	});
});
