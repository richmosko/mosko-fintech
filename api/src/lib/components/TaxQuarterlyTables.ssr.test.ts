// TaxQuarterlyTables.ssr.test.ts — SELF-361 / P9 render-footprint battery: the D1
// stale-data-marker on the §2.5.3 quarterly page. Dep-free: server-side render via
// `svelte/server` (no jsdom / no @testing-library), mirroring NavCompositionTable.ssr.test.ts's
// own convention. Full AC1-8 coverage for this shell lives in TaxQuarterlyTables.dom.test.ts
// (SELF-266); this file covers ONLY what SELF-361 added — badge present/absent, ONE mount for
// both jurisdiction tables, and that it never merges with the other two registers (AC3).
//
// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { render } from 'svelte/server';
import TaxQuarterlyTables from './TaxQuarterlyTables.svelte';
import type { TaxQuarterlyLiability, TaxJurisdictionPayload } from '$lib/tax-quarterly';
import { EMPTY_STALENESS, type StaleConstituentItem } from '$lib/staleness/stale-constituent';

function jurisdiction(over: Partial<TaxJurisdictionPayload> = {}): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2026,
		schedules: {
			federal_ordinary: { present: true, basis_year: 2026, current_year_schedule_empty: false }
		},
		inputs: { ordinary_input: 100000, lt_cg_input: 0, standard_deduction: 14600 },
		taxable_income: { ordinary: 85400, lt_cg: null },
		annual_liability: 12000,
		tax_balance_prior_year: 0,
		installments: [
			{ quarter: 1, due_date: '2026-04-15', amount: 3000 },
			{ quarter: 2, due_date: '2026-06-15', amount: 3000 },
			{ quarter: 3, due_date: '2026-09-15', amount: 3000 },
			{ quarter: 4, due_date: '2027-01-15', amount: 3000 }
		],
		installments_due_through_next: 1,
		next_due_date: '2026-04-15',
		ytd_paid: { status: 'designated', amount: 0 },
		funds_due: { status: 'computed', amount: 3000 },
		applied_marginal_rate: { ordinary: 0.24 },
		...over
	};
}

const LIABILITY: TaxQuarterlyLiability = {
	as_of: '2026-05-01',
	tax_year: 2026,
	jurisdictions: {
		federal: jurisdiction(),
		california: jurisdiction({ applied_marginal_rate: { ordinary: 0.093 } })
	},
	prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' }
};

const STALE_ITEM: StaleConstituentItem = {
	linked_source_id: '42',
	institution_name: 'Test Bank',
	provider: 'plaid',
	connection_status: 'login_required',
	status_class: null
};

describe('TaxQuarterlyTables — SELF-361 / P9: D1 stale-data-marker', () => {
	it('staleness confirmed healthy (EMPTY_STALENESS) → zero-footprint, no badge markup', () => {
		const { body } = render(TaxQuarterlyTables, {
			props: {
				liability: LIABILITY,
				noTaxAuthorityDesignated: false,
				priorYearQ4: null,
				staleness: EMPTY_STALENESS
			}
		});
		expect(body).not.toContain('stale-connection-marker');
		expect(body).not.toContain('May be stale');
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the page heading, exactly ONCE for both jurisdiction tables', () => {
		const { body } = render(TaxQuarterlyTables, {
			props: {
				liability: LIABILITY,
				noTaxAuthorityDesignated: false,
				priorYearQ4: null,
				staleness: { is_stale: true, stale_items: [STALE_ITEM] }
			}
		});
		const occurrences = body.split('May be stale').length - 1;
		expect(occurrences).toBe(1);
	});

	it('AC3 separation: the badge and the noTaxAuthorityDesignated banner render TOGETHER, neither substituting for the other', () => {
		const { body } = render(TaxQuarterlyTables, {
			props: {
				liability: LIABILITY,
				noTaxAuthorityDesignated: true,
				priorYearQ4: null,
				staleness: { is_stale: true, stale_items: [STALE_ITEM] }
			}
		});
		expect(body).toContain('May be stale');
		expect(body).toContain('No account is marked as a tax authority.');
	});

	it('AC3 separation: the badge and a per-jurisdiction "no ledger designated" reasonCopy() CTA render TOGETHER, neither substituting for the other', () => {
		const { body } = render(TaxQuarterlyTables, {
			props: {
				liability: {
					...LIABILITY,
					jurisdictions: {
						federal: jurisdiction(),
						california: jurisdiction({
							ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' }
						})
					}
				},
				noTaxAuthorityDesignated: false,
				priorYearQ4: null,
				staleness: { is_stale: true, stale_items: [STALE_ITEM] }
			}
		});
		expect(body).toContain('May be stale');
		expect(body).toContain('Designate an FTB (California) account');
	});

	it('staleness unknown (RPC-read failure) → the muted "Staleness unknown" register, never a confirmed-stale tag', () => {
		const { body } = render(TaxQuarterlyTables, {
			props: {
				liability: LIABILITY,
				noTaxAuthorityDesignated: false,
				priorYearQ4: null,
				staleness: { is_stale: null, stale_items: [] }
			}
		});
		expect(body).toContain('Staleness unknown');
		expect(body).not.toContain('May be stale');
	});
});
