// NavReferenceDatesPanel.ssr.test.ts — SELF-223 render-state coverage for the §2.1.4 NAV-at-
// three-reference-dates panel. Dep-free: server-side render via `svelte/server` — same idiom as
// NavDeltaPanel.ssr.test.ts / StaleConstituentBadge.ssr.test.ts.
//
// COVERS: normal state (3 rows, both columns populated, NEUTRAL ink — no pos/neg anywhere),
// insufficient-history (whole-row NULL → row-level badge, colspan), cpi_unavailable (nav
// stands, prior-Yr-$ cell shows a distinct label — not "—", not conflated with
// insufficient-history's rendering), and the read-failed fail-soft branch. Fixtures are
// synthetic — no live demo per team-lead (local DB unseeded for this surface).

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
