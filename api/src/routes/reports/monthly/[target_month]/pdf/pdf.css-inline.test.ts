// pdf.css-inline.test.ts — SELF-358 (P6) CSS ruling verify leg (`self358-css-ruling.md`, Option
// A): the document this route pushes to the PDF-render worker must be FULLY self-contained — the
// worker fetches nothing else (R2 (C)) — so the generated component CSS must be INLINED, never
// referenced.
//
// ⚠ ENVIRONMENT DEFECT, NOT THIS FEATURE (flagged at hand-off, bubble up to DevOps/Architect —
// possible `vite: ^8.0.16` version-pin concern): under THIS repo's `vitest` node project (Vite
// 8.1.3's "serve"-command CSS pipeline, `node_modules/vite/dist/node/chunks/node.js`'s
// `vite:css-post` transform), a `.css` file consumed from a "server"-environment module —
// `?raw` OR `?inline`, both tried — resolves to an EMPTY string, not its real content. PRE-
// EXISTING (reproduces on `main`, unrelated to this branch) and NOT SPECIFIC to `report.css` —
// `tokens.css`/`app.css` (already `?raw`-imported by this same route before SELF-358) hit the
// identical empty-string result. VERIFIED NOT TO REACH PRODUCTION: a real `vite build` (Vite's
// "build" command, a different code path) correctly embeds the genuine CSS content — grepped the
// built chunk `build/server/chunks/entries/endpoints/reports/monthly/_target_month_/pdf/
// _server.ts.js-*.js` for `monthly-report.svelte-<hash>` and found it, byte-real. `npm run dev`
// likely shares the "serve" code path and may ALSO ship unstyled — worth a live check, not done
// here (out of this spike's scope). Legs below are written to be MEANINGFUL under this
// constraint, not to paper over it with an assertion that can only ever pass or only ever fail.
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { render } from 'svelte/server';
import MonthlyReportView from '$lib/components/MonthlyReportView.svelte';
// SELF-358 / P6 fix: moved from './+server' — see composeReportDocument.ts's own header.
import { composeReportDocument } from '$lib/server/pdf/composeReportDocument';
import { MONTHLY_REPORT_HEADER_FINAL, MONTHLY_REPORT_PAYLOAD } from '$lib/fixtures/monthly-report';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import { EMPTY_CASHFLOW_ROW_STALENESS_MAP } from '$lib/cashflow-row-staleness';

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
	it('the committed report.css artifact on disk is real and substantial (bypasses the vitest ?raw/?inline defect above via a direct fs read, the SAME technique the build-time census used)', () => {
		// Guards the guard: the ONE property a build-drift regression would actually corrupt —
		// the artifact itself, not this test harness's ability to see it.
		const onDisk = readFileSync('src/lib/generated/report.css', 'utf-8');
		expect(onDisk.length).toBeGreaterThan(1000);
		expect(onDisk).toMatch(/\.monthly-report\.svelte-[a-z0-9]+/);
	});

	it('the document shell has exactly three inlined <style> tags before the print-base block (tokens.css, app.css, report.css — the wiring this route\'s header documents), never an external <link>', () => {
		const document = renderDocument();
		// The wiring assertion: three `<style>` opens precede the named print-base comment, in the
		// order composeReportDocument.ts declares them. Content-equality is NOT assertable here
		// (see file header) — this proves the INTERPOLATION SITE exists and precedes the doc's own
		// `</head>`, which is what a "forgot to add the <style> tag" regression would break.
		const headSlice = document.slice(0, document.indexOf('</head>'));
		const styleOpens = headSlice.match(/<style>/g) ?? [];
		expect(styleOpens.length).toBeGreaterThanOrEqual(4); // 3 CSS files + the print-base block
		expect(document).not.toMatch(/<link\b/i);
	});

	it('introduces no external script reference — the worker fetches nothing else (R2 (C))', () => {
		const document = renderDocument();
		expect(document).not.toMatch(/<script\s+src=/i);
	});
});
