// taxes-decomposition-page.dom.test.ts — SELF-264: the in-page cross-link to the §2.5.3
// quarterly page (team-lead ruling, 2026-09-04 — the single primary-nav "Taxes" entry is
// frontend-266's; this page carries no nav entry of its own, only this in-page sibling link).
// Mirrors the established cash-flow-page.dom.test.ts / us-equity-page.dom.test.ts precedent
// (render() over the route's own +page.svelte with a merged-PageData fixture).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import TaxesDecompositionPage from './+page.svelte';
import type { TaxCharacterCatalog } from '$lib/tax-decomposition';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';

// Root +layout.server.ts's own fields (SELF-285/200/207) — this page's props type is the FULL
// merged PageData, so every fixture spreads these the same way cash-flow-page.dom.test.ts's own
// LAYOUT_DEFAULTS does.
const LAYOUT_DEFAULTS = {
	userEmail: 'owner@example.com',
	pendingClassificationCount: 0,
	connectionHealth: { reauthCount: 0, institutionDownCount: 0 }
};

const CATALOG: TaxCharacterCatalog = [
	{ code: 'ordinary', label: 'Ordinary income', display_order: 10 }
];

// The `data.liability` prop at THIS boundary is Backend's FULL `TaxLiabilityPayload` (all six
// ADR-067 Decision 5 top-level keys — `$lib/tax-decomposition.ts`'s own `TaxLiabilitySlice`
// mirror only types the §2.5.1-relevant subset, so it under-satisfies the generated `PageData`
// object-literal check here). This fixture is intentionally NOT typed against that narrower
// mirror — it supplies every key a real payload carries, mirroring `taxLiability.test.ts`'s own
// WELL_FORMED constant shape (verified against `taxLiability.ts` post-merge), so this test
// exercises the same object shape the real loader hands the page. This suite asserts nothing
// about `jurisdictions` / `nav_components` / `prior_year_q4_window` rendering — those are
// SELF-266/268's own coverage; they exist here only so the fixture type-checks.
const UNAVAILABLE_JURISDICTION = {
	status: 'unavailable' as const,
	reason: 'no_schedule_any_year',
	basis_year: null,
	schedules: {},
	inputs: { ordinary_input: null, lt_cg_input: null, standard_deduction: null },
	taxable_income: { ordinary: null, lt_cg: null },
	annual_liability: null,
	tax_balance_prior_year: null,
	installments: null,
	installments_due_through_next: 1,
	next_due_date: '2026-04-15',
	ytd_paid: { status: 'unavailable' as const, reason: 'no_ledger_designated' },
	funds_due: { status: 'unavailable' as const, reason: 'no_schedule_any_year' }
};

const LIABILITY = {
	as_of: '2026-09-04',
	tax_year: 2026,
	decomposition: {
		ordinary_income: { rows: [], total: 0 },
		capital_gains: {
			status: 'unavailable' as const,
			reason: 'no_sale_recording_capability'
		},
		unclassified: { count_ytd: 0 }
	},
	jurisdictions: { federal: UNAVAILABLE_JURISDICTION, california: UNAVAILABLE_JURISDICTION },
	nav_components: {
		realized_tax_liab: { status: 'unavailable' as const, reason: 'no_ledger_designated' },
		unrealized_tax_liab: { status: 'unavailable' as const, reason: 'no_ledger_designated' }
	},
	prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' }
};

describe('taxes/decomposition/+page.svelte — §2.5.3 cross-link', () => {
	it('renders a "Quarterly estimated taxes →" link to /taxes/quarterly beside the heading', () => {
		render(TaxesDecompositionPage, {
			props: {
				data: {
					...LAYOUT_DEFAULTS,
					liability: LIABILITY,
					taxCharacters: CATALOG,
					inventorySeedDeltaMigration: '100_tax_value_inventory_seed_delta.sql',
					staleness: EMPTY_STALENESS
				}
			}
		});

		const link = screen.getByRole('link', { name: 'Quarterly estimated taxes →' });
		expect(link.getAttribute('href')).toBe('/taxes/quarterly');
	});
});
