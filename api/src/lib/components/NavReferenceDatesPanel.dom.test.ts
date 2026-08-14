// NavReferenceDatesPanel.dom.test.ts — SELF-229 QA wiring-fidelity + signal-distinctness
// battery. Same division of labor as NavDeltaPanel.dom.test.ts / NavHistoryChart.dom.test.ts's
// new SELF-229-QA block: disclosure CONTENT (account names, Re-authenticate link) is proven
// once, generically, in StaleConstituentBadge.dom.test.ts since all four ramp surfaces pass the
// identical props through unchanged. This file covers what needs a real DOM and is specific to
// THIS surface: the actual staleItems array reaching the badge, and the D1 badge staying
// structurally distinct from this panel's OWN per-row carried-CPI marker (`.carried-flag`) —
// two different staleness sources per this panel's own module header, never merged.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import NavReferenceDatesPanel from './NavReferenceDatesPanel.svelte';
import type { NavReferenceDateRow } from '$lib/nav-reference-dates';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import type { StaleConstituentItem } from '$lib/staleness/stale-constituent';

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

function fixture(
	overrides: Partial<Record<NavReferenceDateRow['reference'], Partial<NavReferenceDateRow>>> = {}
): NavReferenceDateRow[] {
	return (['this_month', 'prior_month', 'prior_year_end'] as const).map((r) =>
		row({ reference: r, ...(overrides[r] ?? {}) })
	);
}

const item = (id: string): StaleConstituentItem => ({
	linked_source_id: id,
	institution_name: `Bank ${id}`,
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null
});

describe('NavReferenceDatesPanel — SELF-229 wiring fidelity: the ACTUAL staleItems array reaches the badge', () => {
	it('a two-item staleItems array yields the PLURAL summary, not a single-item count', () => {
		const rows = fixture();
		const { getByRole } = render(NavReferenceDatesPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [item('1'), item('2')] } }
		});
		expect(getByRole('group', { name: '2 accounts are contributing possibly-stale data to this total.' })).toBeTruthy();
	});
});

describe('NavReferenceDatesPanel — D1 badge (canary, connection-health) stays distinct from the PER-ROW carried-CPI flag (neutral, informational)', () => {
	it('D1 stale + a per-row carried-CPI flag BOTH present: both markers render, neither substitutes for the other', () => {
		const rows = fixture({ this_month: { cpi_any_carried: true, cpi_period: '2026-06-01' } });
		const { container, getByText } = render(NavReferenceDatesPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [item('1')] } }
		});
		expect(container.querySelector('.stale-connection-marker')).not.toBeNull();
		expect(container.querySelector('.carried-flag')).not.toBeNull();
		expect(getByText('Carried', { selector: '.carried-flag' })).toBeTruthy();
	});

	it('D1 healthy + a per-row carried-CPI flag present: ONLY the carried-flag renders, no D1 badge', () => {
		const rows = fixture({ this_month: { cpi_any_carried: true, cpi_period: '2026-06-01' } });
		const { container } = render(NavReferenceDatesPanel, { props: { staleness: EMPTY_STALENESS, rows } });
		expect(container.querySelector('.stale-connection-marker')).toBeNull();
		expect(container.querySelector('.carried-flag')).not.toBeNull();
	});
});

// ============================================================================
// F/CTO ruling (a), FINAL BATTERY PASS (team-lead, post-442dac8): the badge's own tri-state
// distinguishability is proven exhaustively at the shared-component level
// (StaleConstituentBadge.ssr.test.ts). What was NOT proven anywhere: that `staleness.is_stale
// === null` (UNKNOWN_STALENESS) actually reaches THIS surface's own mount and renders — every
// prior wiring-fidelity leg on this file only ever exercised `is_stale: true`. Closing that gap.
// ============================================================================

describe('NavReferenceDatesPanel — SELF-229 tri-state wiring: staleness.is_stale === null reaches this surface', () => {
	it('is_stale === null renders "Staleness unknown" at this surface, distinct from "May be stale"', () => {
		const rows = fixture();
		const { getByText, queryByText } = render(NavReferenceDatesPanel, {
			props: { rows, staleness: { is_stale: null, stale_items: [] } }
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		expect(queryByText('May be stale')).toBeNull();
	});

	it('is_stale === false (confirmed healthy) stays zero-footprint — never confused with the unknown case above', () => {
		const rows = fixture();
		const { queryByText } = render(NavReferenceDatesPanel, {
			props: { rows, staleness: { is_stale: false, stale_items: [] } }
		});
		expect(queryByText('Staleness unknown')).toBeNull();
		expect(queryByText('May be stale')).toBeNull();
	});
});
