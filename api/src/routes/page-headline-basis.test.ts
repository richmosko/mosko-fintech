// page-headline-basis.test.ts — Frontend-owned. SELF-268 (Sec item 3, relayed by team-lead): the
// §2.1.1 headline reads the SAME composed value as the §2.1.5 foot (R3 rider 0), so it carries the
// SAME three-state tax-adjustment basis (Sec P-5 / option (C)) in short form, plus the AC 4a fact
// that the trend chart further down the page is a different, permanently-gross basis.
//
// Named WITHOUT the `+` prefix deliberately, same convention as page-staleness.test.ts (`src/
// routes/` is SvelteKit-reserved for `+page.svelte` etc.; a second `+`-prefixed file breaks
// `svelte-kit sync`).
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import Page from './+page.svelte';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import type { NavComposition, TaxLiabilityEnvelope } from '$lib/nav-composition';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const computed = (amount: number): TaxLiabilityEnvelope => ({ status: 'computed', amount });
const unavailable = (reason: string): TaxLiabilityEnvelope => ({ status: 'unavailable', reason });

function composition(realized: TaxLiabilityEnvelope, unrealized: TaxLiabilityEnvelope): NavComposition {
	return {
		groups: [],
		buildups: {
			total_non_re: 500_000,
			gross_total: 500_000,
			debt: 0,
			realized_tax_liab: realized,
			unrealized_tax_liab: unrealized
		},
		nav: 500_000
	};
}

// Minimal PageData satisfying every field +page.svelte's template reaches for on the nav-hero
// branch — mirrors page-staleness.test.ts's own `pageData()` helper (kept local/duplicated rather
// than imported: that file is QA-owned and this one is Frontend-owned, per the repo's role split).
function pageData(overrides: Partial<Record<string, unknown>> = {}) {
	return {
		userEmail: null,
		pendingClassificationCount: 0,
		connectionHealth: { reauthCount: 0, institutionDownCount: 0 },
		netWorth: 500_000,
		accountPresence: 'some' as const,
		asOf: unsafeAsOfForTest('2026-08-14'),
		staleness: EMPTY_STALENESS,
		navReferenceDates: null,
		navDeltaPanel: null,
		composition: null,
		navSeries: null,
		navSeriesParamsError: null,
		navSeriesParams: { granularity: 'monthly' as const, start: '2021-06-01', end: '2026-06-01' },
		navBoundary: null,
		...overrides
	};
}

describe('+page.svelte — SELF-268 headline basis note: present when composition loaded, absent when it did not', () => {
	it('composition null (read failure) → the headline number still renders, no basis note fabricated', () => {
		const { body } = render(Page, { props: { data: pageData({ composition: null }) } });
		expect(body).toContain('$500,000');
		expect(body).not.toContain('tax-adjusted');
		expect(body).not.toContain('tax lines unavailable');
		expect(body).not.toContain('tax not yet deducted');
	});

	it('both envelopes computed → "tax-adjusted" short form + the AC 4a chart-gross pointer', () => {
		const { body } = render(Page, {
			props: { data: pageData({ composition: composition(computed(4_200), computed(1_800)) }) }
		});
		expect(body).toContain('tax-adjusted');
		expect(body).toContain('the trend chart below is gross, before tax.');
	});

	it('both envelopes unavailable → "pre-tax — tax lines unavailable" short form', () => {
		const { body } = render(Page, {
			props: {
				data: pageData({
					composition: composition(
						unavailable('ytd_paid_unavailable'),
						unavailable('no_schedule_any_year')
					)
				})
			}
		});
		expect(body).toContain('pre-tax — tax lines unavailable');
	});

	it('realized unavailable only (partial) → names the realized line, never a boolean/generic "partial" word', () => {
		const { body } = render(Page, {
			props: {
				data: pageData({
					composition: composition(unavailable('ytd_paid_unavailable'), computed(1_800))
				})
			}
		});
		expect(body).toContain('realized tax not yet deducted');
	});

	it('the basis note text is VISIBLE page content, not hidden inside a title attribute (PRD §2.4.4 / ADR-013 — never hover-only)', () => {
		const { body } = render(Page, {
			props: { data: pageData({ composition: composition(computed(4_200), computed(1_800)) }) }
		});
		expect(body).not.toContain('title="tax-adjusted');
	});
});
