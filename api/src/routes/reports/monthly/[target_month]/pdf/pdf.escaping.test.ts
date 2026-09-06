// pdf.escaping.test.ts — SELF-358 (P6) AC7 / INV-2: the escaping PROOF LEG for the FULL
// self-contained document this route pushes to the PDF-render worker, not just the bare
// MonthlyReportView component (that per-component leg already exists at
// MonthlyReportView.ssr.test.ts, INV-1). Sec R-5 / rederived-acs.md § SELF-358 AC7 states this
// proof "spans both engines" — the WORKER side (the two-abort interception leg) is A4's own
// battery, named for QA at P10; THIS file is the APP side: given a stored `<script>` payload
// reaches this route's props, the DOCUMENT STRING this route actually hands to `renderReportHtml`
// never contains a live `<script>` tag carrying that payload.
//
// FIELDS COVERED, per AC7: (1) a stored `<script>` in commentary (rebalancing_targets.cash, the
// same field MonthlyReportView.ssr.test.ts's own INV-1 leg uses), (2) the owner string
// (header.owner_header_at_generation, A8). `schedule_label` (101) is DELIBERATELY OUT OF SCOPE —
// see the note below; this is a flag, not a silent narrowing.
//
// ⚠ SCOPE NOTE ON `schedule_label` (AC7 names it; this file does not test it): `schedule_label`
// (migration 101, `pfin.tax_bracket_schedule`) belongs to the /settings/tax-brackets surface —
// grepped the full `MonthlyReportPayload` shape (monthly-report.ts) and MonthlyReportView.svelte's
// own import graph (the 14-file {@html} census closure): `schedule_label` does not appear in
// either. It cannot render inert here because it never reaches this template at all. AC7's own
// text explains why it is named regardless: "BACKLOG.md §7.32 item 6 was drafted against
// schedule_label before the other fields existed and reaches them only through its 'every other
// free-text field' clause" — i.e. schedule_label is cited as the PRECEDENT that already has its
// own proof elsewhere (its own settings-editor battery), not as a claim that it flows through the
// monthly report. AC7 itself says the §7.32 ledger entry "reduces to header + citation once this
// lands — team-lead's edit, not this issue's"; flagged at hand-off for that edit rather than
// fabricated into this payload to force a literal match.
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import MonthlyReportView from '$lib/components/MonthlyReportView.svelte';
import { composeReportDocument } from './+server';
import {
	MONTHLY_REPORT_HEADER_FINAL,
	MONTHLY_REPORT_PAYLOAD
} from '$lib/fixtures/monthly-report';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import { EMPTY_CASHFLOW_ROW_STALENESS_MAP } from '$lib/cashflow-row-staleness';

const SCRIPT_PAYLOAD = '<script>alert(document.cookie)</script>';

function renderDocument(overrides: { ownerHeader?: string; commentaryScript?: boolean } = {}) {
	const header = {
		...MONTHLY_REPORT_HEADER_FINAL,
		owner_header_at_generation: overrides.ownerHeader ?? MONTHLY_REPORT_HEADER_FINAL.owner_header_at_generation
	};
	const payload = overrides.commentaryScript
		? {
				...MONTHLY_REPORT_PAYLOAD,
				sections: {
					...MONTHLY_REPORT_PAYLOAD.sections,
					rebalancing_targets: {
						...MONTHLY_REPORT_PAYLOAD.sections.rebalancing_targets,
						cash: SCRIPT_PAYLOAD
					}
				}
			}
		: MONTHLY_REPORT_PAYLOAD;

	const { head, body } = render(MonthlyReportView, {
		props: {
			header,
			payload,
			taxCharacters: [{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }],
			seedDeltaMigration: '100_tax_value_inventory_seed_delta.sql',
			staleness: EMPTY_STALENESS,
			cashflowRowStaleness: EMPTY_CASHFLOW_ROW_STALENESS_MAP,
			staleAccountNames: []
		}
	});
	return composeReportDocument(head, body, header.target_month);
}

describe('PDF export — AC7/INV-2 escaping proof, over the FULL pushed document', () => {
	it('a stored <script> in commentary (rebalancing_targets.cash) never reaches the document as a live tag', () => {
		const document = renderDocument({ commentaryScript: true });
		expect(document).not.toContain(SCRIPT_PAYLOAD);
		expect(document).not.toMatch(/<script>alert/);
		// Inert as escaped text — proves the payload was RENDERED, not silently dropped.
		expect(document).toContain('&lt;script>alert(document.cookie)&lt;/script>');
	});

	it('a <script>-carrying owner string never reaches the document as a live tag', () => {
		const document = renderDocument({ ownerHeader: SCRIPT_PAYLOAD });
		expect(document).not.toContain(SCRIPT_PAYLOAD);
		expect(document).not.toMatch(/<script>alert/);
		expect(document).toContain('&lt;script>alert(document.cookie)&lt;/script>');
	});

	it('the document shell itself introduces no live <script> tag anywhere (worker-facing negative assertion)', () => {
		const document = renderDocument();
		// Mirrors A4's own AC #0/#5 negative assertion, restated app-side: this route's own
		// template-free document shell (composeReportDocument) never emits a live <script> tag —
		// only the two inline <style> blocks and the component's own (escaped) output.
		expect(document).not.toMatch(/<script(?!.*&lt;)/);
	});

	it('a clean (non-adversarial) render still produces a well-formed, non-empty document', () => {
		const document = renderDocument();
		expect(document).toContain('<!doctype html>');
		expect(document).toContain('<title>Monthly Report — 2026-08</title>');
		expect(document.length).toBeGreaterThan(500);
	});
});
