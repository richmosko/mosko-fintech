// NavDeltaPanel.ssr.test.ts — SELF-222 render-state coverage for the §2.1.3 multi-horizon
// NAV-delta panel. Dep-free: server-side render via `svelte/server` (already-installed svelte
// 5) — NO jsdom / NO @testing-library, same idiom as StaleConstituentBadge.ssr.test.ts.
//
// COVERS THE FIVE STATES the SELF-222 brief calls out: normal (incl. both delta directions),
// insufficient-history, cpi_unavailable, carried (panel-wide Jan/Feb basis-line copy), and the
// delta_percent NULL-vs-zero distinction. Also covers the read-failed fail-soft branch.
//
// EXTENDED FOR MIGRATION 072 (2026-08-14, F/CTO-ratified Option B on the AC3 gap):
// delta_inflation_adjusted_percent now renders alongside the dollar figure for 1Y/3Y/5Y, same
// format as the NAV Delta column. New coverage: dollar+percent together, and the ONE-WAY NULL
// case (dollar present, percent NULL on a non-positive deflated base) — distinguished from a
// real 0.0% the same way the existing NAV-delta NULL-vs-zero tests already prove for delta_percent.

// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import NavDeltaPanel from './NavDeltaPanel.svelte';
import { isCpiApplicable, type NavDeltaPanelRow } from '$lib/nav-delta-panel';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';

function row(overrides: Partial<NavDeltaPanelRow> & { horizon: NavDeltaPanelRow['horizon'] }): NavDeltaPanelRow {
	return {
		anchor_date: '2025-08-31',
		anchor_checkpoint_date: '2025-08-31',
		current_checkpoint_date: '2026-08-12',
		delta_nominal: 15_000,
		delta_percent: 6.2,
		delta_inflation_adjusted: isCpiApplicable(overrides.horizon) ? 9_000 : null,
		delta_inflation_adjusted_percent: isCpiApplicable(overrides.horizon) ? 4.5 : null,
		cpi_basis_period: isCpiApplicable(overrides.horizon) ? '2025-12-01' : null,
		cpi_any_carried: false,
		cpi_unavailable: false,
		...overrides
	};
}

// A complete, "everything normal" five-row fixture — individual tests override one row.
function fixture(overrides: Partial<Record<NavDeltaPanelRow['horizon'], Partial<NavDeltaPanelRow>>> = {}): NavDeltaPanelRow[] {
	return (['month', 'ytd', '1y', '3y', '5y'] as const).map((h) => row({ horizon: h, ...(overrides[h] ?? {}) }));
}

describe('NavDeltaPanel — read-failed (fail-soft)', () => {
	it('rows === null → unavailable notice, no table', () => {
		const { body } = render(NavDeltaPanel, { props: { rows: null } });
		expect(body).toContain('temporarily unavailable');
		expect(body).not.toContain('<table');
	});
});

describe('NavDeltaPanel — normal state', () => {
	it('renders 5 rows × the Horizon/NAV Delta/Inflation Adjusted columns, both delta directions', () => {
		const rows = fixture({
			month: { delta_nominal: -1200, delta_percent: -0.8 },
			ytd: { delta_nominal: 3400, delta_percent: 2.1 }
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });

		// All 5 horizon labels present.
		for (const label of ['Month', 'YTD', '1-Year', '3-Year', '5-Year']) {
			expect(body).toContain(`>${label}<`);
		}
		expect(body).toContain('NAV Delta');
		expect(body).toContain('Inflation Adjusted');

		// Negative delta: U+2212 minus, never a hyphen-minus, .neg class present (Svelte injects
		// a scoped-style hash class alongside the static/dynamic ones, so match loosely on the
		// class ATTRIBUTE containing the "neg" token rather than an exact string).
		expect(body).toContain('−$1,200');
		expect(body).toContain('−0.8%');
		expect(body).toMatch(/class="num[^"]*\bneg\b[^"]*"/);

		// Positive delta: '+' sign, .pos class present.
		expect(body).toContain('+$3,400');
		expect(body).toContain('+2.1%');
		expect(body).toMatch(/class="num[^"]*\bpos\b[^"]*"/);

		// Month/YTD Inflation Adjusted cells render '—' (NOT APPLICABLE), never a computed value.
		expect(body).not.toContain('Insufficient history');
		expect(body).not.toContain('CPI unavailable');
	});

	it('a CPI-applicable row with a real inflation-adjusted figure renders dollar + percent (AC3)', () => {
		const rows = fixture({ '1y': { delta_inflation_adjusted: 9_000, delta_inflation_adjusted_percent: 4.5 } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('+$9,000');
		expect(body).toContain('+4.5%');
	});
});

describe('NavDeltaPanel — insufficient history (AC4)', () => {
	it('anchor_checkpoint_date NULL → "Insufficient history" badge spans both value columns', () => {
		const rows = fixture({
			'5y': {
				anchor_checkpoint_date: null,
				delta_nominal: null,
				delta_percent: null,
				delta_inflation_adjusted: null,
				delta_inflation_adjusted_percent: null
			}
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('Insufficient history');
		expect(body).toContain('colspan="2"');
		// The other four rows are unaffected.
		expect(body).toContain('+$15,000');
	});
});

describe('NavDeltaPanel — cpi_unavailable (structural discriminator #2)', () => {
	it('nominal stands, Inflation Adjusted cell shows "CPI unavailable", not "—"', () => {
		const rows = fixture({
			'3y': {
				cpi_unavailable: true,
				delta_inflation_adjusted: null,
				delta_inflation_adjusted_percent: null,
				delta_nominal: 22_000,
				delta_percent: 9.4
			}
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('CPI unavailable');
		// The nominal figure for that same row still renders — the outage is scoped to real terms only.
		expect(body).toContain('+$22,000');
	});
});

describe('NavDeltaPanel — carried CPI basis (AC5(iv), panel-wide Jan/Feb copy)', () => {
	it('cpi_any_carried on any CPI-applicable row → ONE panel-wide basis-line note, dated + cause-named, not an outage', () => {
		const rows = fixture({
			'1y': { cpi_any_carried: true },
			'3y': { cpi_any_carried: true },
			'5y': { cpi_any_carried: true }
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('December 2025');
		expect(body).toContain('Carried forward');
		expect(body).toContain('one to two months in arrears');
		expect(body).toContain('No action needed');
		// Reads as a dated calendar fact, not an incident/error/outage.
		expect(body.toLowerCase()).not.toContain('outage');
		expect(body.toLowerCase()).not.toContain('error');
		// Series-level: exactly one note, not three (one per CPI-applicable row).
		expect(body.split('Carried forward').length - 1).toBe(1);
	});

	it('no carried rows → basis line present, no carried-note copy', () => {
		const { body } = render(NavDeltaPanel, { props: { rows: fixture() } });
		expect(body).toContain('CPI-U basis through');
		expect(body).not.toContain('Carried forward');
	});
});

describe('NavDeltaPanel — real backend sample (SELF-222 hand-off, seeded tenant b1aa21a2)', () => {
	// Verbatim local smoke-verify payload from Backend's SELF-222 hand-off (migration 071 against
	// real seed data). Exercises the "everything resolved cleanly" happy path against a REAL
	// payload shape rather than only synthetic fixtures — including the SQL-NULL (not `false`)
	// cpi_any_carried/cpi_unavailable on month/ytd that motivated widening this file's types.
	//
	// ⚠ delta_inflation_adjusted_percent values below are SYNTHETIC, not backend-verified: this
	// sample predates migration 072 (which added the column), and no regenerated real sample was
	// available at the time of this update — the local DB lost its seed data in a QA incident
	// (recovery is F/CTO-gated per team-lead). Deliberately round, non-derived placeholder values
	// (NOT computed from the dollar figures above) so this fixture can never be mistaken for a
	// client-side derivation of the real formula — exactly what this surface must never do.
	const realSample: NavDeltaPanelRow[] = [
		{
			horizon: 'month',
			anchor_date: '2026-07-31',
			anchor_checkpoint_date: '2026-07-31',
			current_checkpoint_date: '2026-08-10',
			delta_nominal: -8217654.37,
			delta_percent: -99.40310112495464,
			delta_inflation_adjusted: null,
			delta_inflation_adjusted_percent: null,
			cpi_basis_period: null,
			cpi_any_carried: null,
			cpi_unavailable: null
		},
		{
			horizon: 'ytd',
			anchor_date: '2025-12-31',
			anchor_checkpoint_date: '2025-12-31',
			current_checkpoint_date: '2026-08-10',
			delta_nominal: -7828654.37,
			delta_percent: -99.37362744351358,
			delta_inflation_adjusted: null,
			delta_inflation_adjusted_percent: null,
			cpi_basis_period: null,
			cpi_any_carried: null,
			cpi_unavailable: null
		},
		{
			horizon: '1y',
			anchor_date: '2025-07-31',
			anchor_checkpoint_date: '2025-07-31',
			current_checkpoint_date: '2026-08-10',
			delta_nominal: -7546654.37,
			delta_percent: -99.35037348604529,
			delta_inflation_adjusted: -7571771.53943,
			delta_inflation_adjusted_percent: -95.1,
			cpi_basis_period: '2025-12-01',
			cpi_any_carried: false,
			cpi_unavailable: false
		},
		{
			horizon: '3y',
			anchor_date: '2023-07-31',
			anchor_checkpoint_date: '2023-07-31',
			current_checkpoint_date: '2026-08-10',
			delta_nominal: -6955654.37,
			delta_percent: -99.2955655960029,
			delta_inflation_adjusted: -7377910.52013,
			delta_inflation_adjusted_percent: -94.8,
			cpi_basis_period: '2025-12-01',
			cpi_any_carried: false,
			cpi_unavailable: false
		},
		{
			horizon: '5y',
			anchor_date: '2021-07-31',
			anchor_checkpoint_date: '2021-07-31',
			current_checkpoint_date: '2026-08-10',
			delta_nominal: -6307654.37,
			delta_percent: -99.22375916312726,
			delta_inflation_adjusted: -7497862.86149,
			delta_inflation_adjusted_percent: -94.5,
			cpi_basis_period: '2025-12-01',
			cpi_any_carried: false,
			cpi_unavailable: false
		}
	];

	it('renders without crashing and shows all-negative deltas correctly signed', () => {
		const { body } = render(NavDeltaPanel, { props: { rows: realSample } });
		// Every horizon is a loss in this seed — every NAV Delta cell should be a .neg U+2212 figure.
		expect(body).toContain('−$8,217,654');
		expect(body).toContain('−99.4%');
		expect(body).toContain('−$7,497,863'); // 5y inflation-adjusted, rounds to nearest dollar
		expect(body).toContain('−94.5%'); // 5y inflation-adjusted percent (synthetic fixture value)
		expect(body).not.toContain('Insufficient history');
		expect(body).not.toContain('CPI unavailable');
		expect(body).not.toContain('Carried forward');
	});

	it('month/ytd rows with SQL-NULL (not false) cpi_any_carried/cpi_unavailable render "—" for Inflation Adjusted', () => {
		const { body } = render(NavDeltaPanel, { props: { rows: realSample } });
		const monthRow = body.split('>Month<')[1]?.split('</tr>')[0] ?? '';
		expect(monthRow).toContain('—');
	});
});

describe('NavDeltaPanel — delta_percent NULL vs zero (AC2 / migration AC2)', () => {
	it('a real zero percent renders "0.0%", never "—"', () => {
		const rows = fixture({ month: { delta_nominal: 0, delta_percent: 0 } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('0.0%');
		expect(body).toContain('$0');
	});

	it('a NULL percent (non-positive anchor) renders "—" in the percent slot, never "0.0%", nominal still shows', () => {
		const rows = fixture({ ytd: { delta_nominal: 500, delta_percent: null } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('+$500');
		expect(body).not.toContain('(+0.0%)');
		expect(body).not.toContain('0.0%');
	});

	it('the two cases render distinguishably in the SAME document (no collapse)', () => {
		const rows = fixture({
			month: { delta_nominal: 0, delta_percent: 0 },
			ytd: { delta_nominal: 500, delta_percent: null }
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('0.0%');
		expect(body).toContain('+$500');
	});
});

describe('NavDeltaPanel — Inflation Adjusted percent (072 AC3 amendment)', () => {
	it('a normal CPI-applicable row renders dollar + percent in the NAV-Delta-matching format', () => {
		const rows = fixture({ '3y': { delta_inflation_adjusted: -2500, delta_inflation_adjusted_percent: -12.3 } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('−$2,500');
		expect(body).toContain('−12.3%');
		expect(body).toMatch(/class="num[^"]*\bneg\b[^"]*"/);
	});

	it('a real zero inflation-adjusted percent renders "0.0%", never "—"', () => {
		const rows = fixture({ '1y': { delta_inflation_adjusted: 0, delta_inflation_adjusted_percent: 0 } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('$0');
		expect(body).toContain('0.0%');
	});

	it('ONE-WAY NULL: dollar PRESENT, percent NULL (non-positive deflated base) → dollar shown, "—" in the percent slot, never "0.0%"', () => {
		const rows = fixture({ '5y': { delta_inflation_adjusted: -1800, delta_inflation_adjusted_percent: null } });
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('−$1,800');
		expect(body).not.toContain('(−0.0%)');
		expect(body).not.toContain('(+0.0%)');
		// The inexpressible-percent title fires for this cell specifically.
		expect(body).toContain('Percent change cannot be expressed against a zero or negative deflated starting value.');
	});

	it('the zero and NULL real-terms-percent cases render distinguishably in the SAME document (no collapse)', () => {
		const rows = fixture({
			'1y': { delta_inflation_adjusted: 0, delta_inflation_adjusted_percent: 0 },
			'3y': { delta_inflation_adjusted: -1800, delta_inflation_adjusted_percent: null }
		});
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).toContain('0.0%');
		expect(body).toContain('−$1,800');
	});
});

describe('NavDeltaPanel — SELF-229 D1 stale-data-marker (whole-user, shared with the other 3 surfaces)', () => {
	const staleItem: StaleConstituentItem = {
		linked_source_id: '42',
		institution_name: 'Test Bank',
		provider: 'plaid',
		connection_status: 'login_required',
		status_class: null
	};

	it('staleness prop omitted → zero-footprint, no badge markup', () => {
		const rows = fixture();
		const { body } = render(NavDeltaPanel, { props: { rows } });
		expect(body).not.toContain('stale-connection-marker');
		expect(body).not.toContain('May be stale');
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the section heading, distinct from the carried-CPI basis line', () => {
		const rows = fixture();
		const { body } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [staleItem] } }
		});
		expect(body).toContain('May be stale');
		// Institution name only renders inside the collapsed disclosure panel (StaleConstituentBadge's own {#if open} — closed by default); the tag + its accessible summary are what SSR proves here.
		expect(body).toContain('possibly-stale');
	});
});
