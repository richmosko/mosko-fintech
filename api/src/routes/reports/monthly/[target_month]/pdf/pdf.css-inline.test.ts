// pdf.css-inline.test.ts — SELF-358 (P6) CSS ruling verify leg (`self358-css-ruling.md`, Option
// A): the document this route pushes to the PDF-render worker must be FULLY self-contained — the
// worker fetches nothing else (R2 (C)) — so the generated component CSS must be INLINED, never
// referenced.
//
// PRIOR REVISION'S HEADER WAS WRONG — corrected, DevOps-c's live-verified triage: the vitest
// `node` project's `.css`/`?raw` empty-string result is vitest-dev/vitest#10788, NOT a `vite:css-
// post` quirk. `test.css` defaults `false`; vitest's OWN css-disable short-circuit fires BEFORE
// Vite's raw-import pipeline ever runs, unconditionally, regardless of `?raw`/`?inline` — that is
// why both queries returned empty. Reproduced on vitest 3.2.4 / 4.1.9 / this repo's 4.1.10; no
// version bump fixes it. Fix: `test.css: true` on the `node` project (`vitest.config.ts`), scoped
// so the `dom` project (already `?raw`-unaffected — never exercised the empty-string defect) is
// unchanged; both projects measured green after the change. Also corrected: `npm run dev`'s real
// `vite` server does NOT share this path — DevOps-c's own `ssrLoadModule('report.css?raw')`
// against a live dev server returned the full 37,352-byte artifact, not empty; the prior header's
// "may also ship unstyled" guess was wrong and is retracted.
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { render } from 'svelte/server';
import MonthlyReportView from '$lib/components/MonthlyReportView.svelte';
import { composeReportDocument } from '$lib/server/pdf/composeReportDocument';
import { MONTHLY_REPORT_HEADER_FINAL, MONTHLY_REPORT_PAYLOAD } from '$lib/fixtures/monthly-report';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import { EMPTY_CASHFLOW_ROW_STALENESS_MAP } from '$lib/cashflow-row-staleness';
import reportCss from '$lib/generated/report.css?raw';

function renderDocument(): string {
	const { head, body } = render(MonthlyReportView, {
		props: {
			header: MONTHLY_REPORT_HEADER_FINAL,
			payload: MONTHLY_REPORT_PAYLOAD,
			taxCharacters: [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }],
			seedDeltaMigration: '100_tax_value_inventory_seed_delta.sql',
			staleness: EMPTY_STALENESS,
			cashflowRowStaleness: EMPTY_CASHFLOW_ROW_STALENESS_MAP,
			staleAccountNames: [],
			renderContext: 'print'
		}
	});
	return composeReportDocument(head, body, MONTHLY_REPORT_HEADER_FINAL.target_month);
}

describe('PDF export — SELF-358 / P6 CSS ruling: the extracted component CSS is inlined', () => {
	it('the `?raw` import matches the artifact on disk byte-for-byte (proves the import mechanism itself, independent of what any one render happens to use)', () => {
		const onDisk = readFileSync('src/lib/generated/report.css', 'utf-8');
		expect(reportCss).toBe(onDisk);
	});

	it('never emits an empty or near-empty extracted-CSS artifact — the ruling\'s own named failure mode (a build drift that silently ships an unstyled PDF while every value assertion still passes)', () => {
		// Byte length within tolerance of the measured baseline (37,352 B at `fbf2fd8`) rather than
		// an exact pin — the component tree is expected to grow, a hard pin would just bit-rot.
		expect(reportCss.length).toBeGreaterThan(20000);
		expect(reportCss.length).toBeLessThan(80000);
	});

	it('inlines the FULL extracted report.css verbatim inside a <style> tag', () => {
		const document = renderDocument();
		expect(document).toContain(`<style>${reportCss}</style>`);
	});

	it('carries a distinctive component-scoped selector from the report tree (not just the two pre-existing global sheets)', () => {
		const document = renderDocument();
		// MonthlyReportView.svelte's own root class, scoped-hash-suffixed — proves this is the
		// COMPONENT tree's CSS, not merely tokens.css/app.css re-asserted under a new name.
		expect(document).toMatch(/\.monthly-report\.svelte-[a-z0-9]+/);
	});

	it('introduces no external stylesheet or script reference — the worker fetches nothing else (R2 (C))', () => {
		const document = renderDocument();
		// Strip <style>...</style> blocks first — real CSS content (now visible thanks to the
		// #10788 fix above) legitimately contains the SUBSTRING "<link" inside a comment
		// (tokens.css documents its own font loading via a review-page `<link>` tag); a bare
		// document-wide match would false-positive on that comment, not on an actual tag this
		// document emits.
		const withoutStyleBlocks = document.replace(/<style>[\s\S]*?<\/style>/g, '');
		expect(withoutStyleBlocks).not.toMatch(/<link\b/i);
		expect(withoutStyleBlocks).not.toMatch(/<script\s+src=/i);
	});
});
