// NavDeltaPanel.dom.test.ts — SELF-229 QA wiring-fidelity + signal-distinctness battery.
//
// The SSR battery (NavDeltaPanel.ssr.test.ts) already proves render-state coverage AND the
// basic D1 badge wiring (isStale true/false → badge markup present/absent). What that battery
// CANNOT prove from an SSR string (no click) is closed generically, once, for all four SELF-229
// surfaces by StaleConstituentBadge.dom.test.ts (disclosure content: account names, per-status
// affordance, Re-authenticate link target). This file covers what's specific to THIS surface and
// needs a real DOM: (1) the ACTUAL staleItems array reaches the badge (not a truncated/hardcoded
// stand-in — a multi-item count is the cheap discriminator), and (2) the D1 badge stays
// STRUCTURALLY DISTINCT from this panel's own pre-existing informational marker, `.carried-note`
// (the CPI-basis-carried-forward disclosure — §2.4.4 informational tier, a DIFFERENT staleness
// source per PRD §2.4.4, never merged into one signal per this panel's own module header).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import NavDeltaPanel from './NavDeltaPanel.svelte';
import { isCpiApplicable, type NavDeltaPanelRow } from '$lib/nav-delta-panel';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
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

function fixture(overrides: Partial<Record<NavDeltaPanelRow['horizon'], Partial<NavDeltaPanelRow>>> = {}): NavDeltaPanelRow[] {
	return (['month', 'ytd', '1y', '3y', '5y'] as const).map((h) => row({ horizon: h, ...(overrides[h] ?? {}) }));
}

const item = (id: string): StaleConstituentItem => ({
	linked_source_id: id,
	institution_name: `Bank ${id}`,
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null
});

describe('NavDeltaPanel — SELF-229 wiring fidelity: the ACTUAL staleItems array reaches the badge', () => {
	it('a two-item staleItems array yields the PLURAL summary, not a single-item count', () => {
		const rows = fixture();
		const { getByRole } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [item('1'), item('2')] } }
		});
		// StaleConstituentBadge names the count on the control's aria-label — a truncated/
		// hardcoded single-item pass-through would fail this by naming "1 account" instead.
		expect(getByRole('group', { name: '2 accounts are contributing possibly-stale data to this total.' })).toBeTruthy();
	});
});

describe('NavDeltaPanel — D1 badge (canary, connection-health) stays distinct from the panel-wide carried-CPI basis note (neutral, informational)', () => {
	it('D1 stale + a carried CPI basis period BOTH present: both markers render, neither substitutes for the other', () => {
		const rows = fixture({
			'1y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' },
			'3y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' },
			'5y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' }
		});
		const { container, getByText } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [item('1')] } }
		});
		// D1 badge present (canary hue, actionable connection signal).
		expect(container.querySelector('.stale-connection-marker')).not.toBeNull();
		// The panel's own pre-existing carried-note (neutral, CPI-U reference-series signal) —
		// a DIFFERENT staleness source per this panel's own module header — still renders too.
		expect(getByText(/Carried forward/)).toBeTruthy();
	});

	it('D1 healthy + a carried CPI basis period present: ONLY the carried-note renders, no badge', () => {
		const rows = fixture({
			'1y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' },
			'3y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' },
			'5y': { cpi_any_carried: true, cpi_basis_period: '2026-06-01' }
		});
		const { container, getByText } = render(NavDeltaPanel, { props: { staleness: EMPTY_STALENESS, rows } });
		expect(container.querySelector('.stale-connection-marker')).toBeNull();
		expect(getByText(/Carried forward/)).toBeTruthy();
	});
});

// ============================================================================
// F/CTO ruling (a), FINAL BATTERY PASS (team-lead, post-442dac8): the badge's own tri-state
// distinguishability is proven exhaustively at the shared-component level
// (StaleConstituentBadge.ssr.test.ts). What was NOT proven anywhere: that `staleness.is_stale
// === null` (UNKNOWN_STALENESS) actually reaches THIS surface's own mount and renders — every
// prior wiring-fidelity leg on this file only ever exercised `is_stale: true`. Closing that gap.
// ============================================================================

describe('NavDeltaPanel — SELF-229 tri-state wiring: staleness.is_stale === null reaches this surface', () => {
	it('is_stale === null renders "Staleness unknown" at this surface, distinct from "May be stale"', () => {
		const rows = fixture();
		const { getByText, queryByText } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: null, stale_items: [] } }
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		expect(queryByText('May be stale')).toBeNull();
	});

	it('is_stale === false (confirmed healthy) stays zero-footprint — never confused with the unknown case above', () => {
		const rows = fixture();
		const { queryByText } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: false, stale_items: [] } }
		});
		expect(queryByText('Staleness unknown')).toBeNull();
		expect(queryByText('May be stale')).toBeNull();
	});
});

describe('NavDeltaPanel — Sec F2 surface-level wiring: a malformed (is_stale:true, stale_items:[]) tuple reaches this surface as UNKNOWN', () => {
	it('is_stale:true paired with an EMPTY stale_items array renders "Staleness unknown", never "May be stale" and never silence', () => {
		const rows = fixture();
		const { getByText, queryByText } = render(NavDeltaPanel, {
			props: { rows, staleness: { is_stale: true, stale_items: [] } }
		});
		expect(getByText('Staleness unknown')).toBeTruthy();
		expect(queryByText('May be stale')).toBeNull();
	});
});
