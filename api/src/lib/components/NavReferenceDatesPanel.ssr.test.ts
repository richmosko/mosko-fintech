// NavReferenceDatesPanel.ssr.test.ts — SELF-223 render-state coverage for the §2.1.4 NAV-at-
// three-reference-dates panel. Dep-free: server-side render via `svelte/server` — same idiom as
// NavDeltaPanel.ssr.test.ts / StaleConstituentBadge.ssr.test.ts.
//
// COVERS: normal state (3 rows, both columns populated, NEUTRAL ink — no pos/neg anywhere),
// insufficient-history (whole-row NULL → row-level badge, colspan), cpi_unavailable (nav
// stands, prior-Yr-$ cell shows a distinct label — not "—", not conflated with
// insufficient-history's rendering), and the read-failed fail-soft branch. Fixtures are
// synthetic — no live demo per team-lead (local DB unseeded for this surface).
//
// QA FINDING 2 (SELF-223 PR review, minor, taken): ALL-THREE-ROWS-insufficient-history is the
// LITERAL CURRENT PRODUCTION STATE — a brand-new user with zero NAV history (073's X1 leg proves
// it at the DB layer) — and the state the app boots into post-seed-recovery-gap. Locks that the
// three-badge render has no cross-row special-casing (no "all rows blank → different treatment"
// shortcut) by construction.
//
// QA FINDING 3 (SELF-223 PR review, cheap guard, taken): the January edge case where This Month
// and Prior Year-End resolve to the IDENTICAL calendar date (PM's ratified "most recent completed
// month-end" Prior-Month definition: in January, before that month's own close, This Month's
// most-recent-completed-month-end IS December 31 of the prior year — the same date Prior Year-End
// names by definition). Locks that two rows sharing reference_date/checkpoint/nav render as two
// PLAIN, independent, identical rows — no dedup, no merge, no "same as above" special-casing —
// against a future "helpful" cleanup that would collapse them.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import NavReferenceDatesPanel from './NavReferenceDatesPanel.svelte';
import type { NavReferenceDateRow } from '$lib/nav-reference-dates';

function row(
	overrides: Partial<NavReferenceDateRow> & { reference: NavReferenceDateRow['reference'] }
): NavReferenceDateRow {
	return {
		reference_date: '2026-07-31',
		reference_checkpoint_date: '2026-07-31',
		nav: 500_000,
		nav_prior_yr_dollars: 510_000,
		cpi_period: '2026-07-01',
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: false,
		...overrides
	};
}

// A complete, "everything normal" three-row fixture — individual tests override one row.
function fixture(
	overrides: Partial<Record<NavReferenceDateRow['reference'], Partial<NavReferenceDateRow>>> = {}
): NavReferenceDateRow[] {
	return (['this_month', 'prior_month', 'prior_year_end'] as const).map((r) =>
		row({ reference: r, ...(overrides[r] ?? {}) })
	);
}

describe('NavReferenceDatesPanel — read-failed (fail-soft)', () => {
	it('rows === null → unavailable notice, no table', () => {
		const { body } = render(NavReferenceDatesPanel, { props: { rows: null } });
		expect(body).toContain('temporarily unavailable');
		expect(body).not.toContain('<table');
	});
});

describe('NavReferenceDatesPanel — normal state', () => {
	it('renders 3 rows × the Reference/NAV/NAV — Prior Yr $ columns, NEUTRAL ink (no pos/neg)', () => {
		const rows = fixture({
			this_month: { nav: 500_000, nav_prior_yr_dollars: 510_000 },
			prior_month: { nav: -25_000, nav_prior_yr_dollars: -25_500 }
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });

		for (const label of ['This Month', 'Prior Month', 'Prior Year-End']) {
			expect(body).toContain(`>${label}<`);
		}
		expect(body).toContain('NAV');
		expect(body).toContain('NAV — Prior Yr $');

		// Plain, unsigned formatting: no leading '+' on a positive value.
		expect(body).toContain('$500,000');
		expect(body).not.toContain('+$500,000');

		// A negative NAV level renders with a plain minus, never U+2212, and NEVER a .pos/.neg
		// class — VALUE-COLOR FENCE: these are levels, not deltas.
		expect(body).toContain('-$25,000');
		expect(body).not.toContain('−$25,000');
		expect(body).not.toMatch(/class="[^"]*\bpos\b[^"]*"/);
		expect(body).not.toMatch(/class="[^"]*\bneg\b[^"]*"/);

		expect(body).not.toContain('Insufficient history');
		expect(body).not.toContain('CPI unavailable');
	});
});

describe('NavReferenceDatesPanel — insufficient history (AC5 discriminator #1)', () => {
	it('reference_checkpoint_date NULL → whole row renders "Insufficient history", colspan="2"', () => {
		const rows = fixture({
			prior_year_end: {
				reference_checkpoint_date: null,
				nav: null,
				nav_prior_yr_dollars: null
			}
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });
		expect(body).toContain('Insufficient history');
		expect(body).toContain('colspan="2"');
		// The other two rows are unaffected.
		expect(body).toContain('$500,000');
	});
});

describe('NavReferenceDatesPanel — cpi_unavailable (AC5 discriminator #2)', () => {
	it('nav stands, NAV — Prior Yr $ cell shows "CPI unavailable", never "—", never conflated with insufficient-history', () => {
		const rows = fixture({
			this_month: { cpi_unavailable: true, nav: 500_000, nav_prior_yr_dollars: null }
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });
		expect(body).toContain('CPI unavailable');
		expect(body).toContain('$500,000');
		expect(body).not.toContain('Insufficient history');
	});

	it('the two discriminated causes render DIFFERENTLY in the SAME document (AC5 verbatim requirement)', () => {
		const rows = fixture({
			this_month: { cpi_unavailable: true, nav: 500_000, nav_prior_yr_dollars: null },
			prior_month: {
				reference_checkpoint_date: null,
				nav: null,
				nav_prior_yr_dollars: null
			}
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });
		expect(body).toContain('CPI unavailable');
		expect(body).toContain('Insufficient history');
		// Structurally distinct markup, not the same "—" glyph used for both.
		expect(body).not.toContain('CPI unavailable</span> Insufficient history');
	});
});

describe('NavReferenceDatesPanel — ALL THREE ROWS insufficient history (QA Finding 2: the literal current production state)', () => {
	it('a brand-new user (zero NAV history) → all three rows render "Insufficient history" independently, no cross-row special-casing', () => {
		const rows = fixture({
			this_month: { reference_checkpoint_date: null, nav: null, nav_prior_yr_dollars: null },
			prior_month: { reference_checkpoint_date: null, nav: null, nav_prior_yr_dollars: null },
			prior_year_end: { reference_checkpoint_date: null, nav: null, nav_prior_yr_dollars: null }
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });

		// Three badges, one per row — not a single page-level "no data" fallback in place of the
		// table (that would be the readFailed/null-rows branch, a DIFFERENT state entirely).
		// (Each badge contributes TWO "Insufficient history" occurrences — the aria-label AND the
		// visible span text — so count the badge element itself, not the phrase.)
		expect(body.split('insufficient-badge').length - 1).toBe(3);
		expect(body).toContain('Insufficient history');
		expect(body).toContain('<table');
		expect(body).toContain('colspan="2"');
		for (const label of ['This Month', 'Prior Month', 'Prior Year-End']) {
			expect(body).toContain(`>${label}<`);
		}
		// No stray real figure leaked through from any row.
		expect(body).not.toContain('$500,000');
	});
});

describe('NavReferenceDatesPanel — January edge case: This Month = Prior Year-End (QA Finding 3)', () => {
	it('two rows sharing reference_date/checkpoint/nav render as two PLAIN identical rows, no dedup', () => {
		const rows = fixture({
			this_month: {
				reference_date: '2025-12-31',
				reference_checkpoint_date: '2025-12-31',
				nav: 480_000,
				nav_prior_yr_dollars: 480_000
			},
			prior_month: {
				reference_date: '2025-11-30',
				reference_checkpoint_date: '2025-11-30',
				nav: 470_000,
				nav_prior_yr_dollars: 471_000
			},
			prior_year_end: {
				reference_date: '2025-12-31',
				reference_checkpoint_date: '2025-12-31',
				nav: 480_000,
				nav_prior_yr_dollars: 480_000
			}
		});
		const { body } = render(NavReferenceDatesPanel, { props: { rows } });

		// Both labels present — no row was dropped, hidden, or merged into the other.
		expect(body).toContain('>This Month<');
		expect(body).toContain('>Prior Year-End<');
		// The shared figure appears TWICE — one full render per row, not deduplicated to one.
		expect(body.split('$480,000').length - 1).toBe(4); // 2 occurrences x 2 columns (NAV + Prior Yr $)
		// Still exactly 3 <tr> data rows in <tbody> — no row collapsed away.
		const tbody = body.split('<tbody')[1] ?? '';
		expect(tbody.split('<tr').length - 1).toBe(3);
		// The distinct Prior Month row is unaffected and un-conflated with the shared date.
		expect(body).toContain('$470,000');
	});
});
