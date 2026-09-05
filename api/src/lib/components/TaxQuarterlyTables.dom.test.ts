// TaxQuarterlyTables.dom.test.ts — SELF-266 verification for the page-level shell: both jurisdiction
// tables render off one fixture payload, and the AC6(ii) page banner is independent of the
// per-jurisdiction AC6(iii) inline CTA.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/svelte';
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

function fixture(over: Partial<TaxQuarterlyLiability> = {}): TaxQuarterlyLiability {
	return {
		as_of: '2026-05-01',
		tax_year: 2026,
		jurisdictions: {
			federal: jurisdiction(),
			california: jurisdiction({ applied_marginal_rate: { ordinary: 0.093 } })
		},
		prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' },
		...over
	};
}

describe('TaxQuarterlyTables', () => {
	it('renders both parallel tables from one fixture payload', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		expect(screen.getByRole('heading', { name: 'Federal Income Taxes' })).toBeTruthy();
		expect(screen.getByRole('heading', { name: 'California State Income Taxes (CA FTB)' })).toBeTruthy();
	});

	it('renders the page-level "no tax authority account" banner when noTaxAuthorityDesignated is true (AC6(ii))', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(),
			noTaxAuthorityDesignated: true,
			priorYearQ4: null
		});
		expect(screen.getByText('No account is marked as a tax authority.')).toBeTruthy();
	});

	it('omits the page banner when noTaxAuthorityDesignated is false, even if one jurisdiction still lacks a designated ledger (AC6(ii) vs 6(iii) independence)', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture({
				jurisdictions: {
					federal: jurisdiction(),
					california: jurisdiction({
						ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' }
					})
				}
			}),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		expect(screen.queryByText('No account is marked as a tax authority.')).toBeNull();
		// The narrower per-jurisdiction CTA still fires independently.
		expect(screen.getByRole('link', { name: /Designate an FTB \(California\) account/ })).toBeTruthy();
	});

	it('QA-walk regression: "Edit tax brackets" is a page-level STANDING affordance (AC 7) — present even when both jurisdictions are the ordinary `computed` case, not only from the AC-7a unavailable state', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(), // both jurisdictions computed — the default fixture shape
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		expect(screen.getByRole('link', { name: 'Edit tax brackets' })).toBeTruthy();
	});

	it('routes the page-level "Edit tax brackets" link to the given editBracketsHref', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null,
			editBracketsHref: '/settings/tax-brackets'
		});
		const link = screen.getByRole('link', { name: 'Edit tax brackets' }) as HTMLAnchorElement;
		expect(link.getAttribute('href')).toBe('/settings/tax-brackets');
	});

	it('threads priorYearQ4 through to both jurisdiction tables (E39)', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(),
			noTaxAuthorityDesignated: false,
			priorYearQ4: {
				tax_year: 2025,
				due_date: '2026-01-15',
				as_of: '2025-12-31',
				federal: {
					q4_installment: 1200,
					annual_liability: 4800,
					funds_due_envelope: { status: 'computed', amount: 1200 }
				},
				california: {
					q4_installment: 500,
					annual_liability: 2000,
					funds_due_envelope: { status: 'computed', amount: 500 }
				}
			}
		});
		// Both tables render their own "still outstanding" notice — one per jurisdiction.
		expect(screen.getAllByText('2025 Q4 still outstanding')).toHaveLength(2);
	});
});

describe('TaxQuarterlyTables — SELF-361 / P9: D1 stale-data-marker beside the page heading', () => {
	it('staleness confirmed healthy (EMPTY_STALENESS) → zero-footprint, no badge markup', () => {
		render(TaxQuarterlyTables, {
			staleness: EMPTY_STALENESS,
			liability: fixture(),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		expect(screen.queryByText('May be stale')).toBeNull();
	});

	it('is_stale true → the shared StaleConstituentBadge renders beside the page heading, ONE mount for both jurisdiction tables', () => {
		const staleItem: StaleConstituentItem = {
			linked_source_id: '42',
			institution_name: 'Test Bank',
			provider: 'plaid',
			connection_status: 'login_required',
			status_class: null
		};
		render(TaxQuarterlyTables, {
			staleness: { is_stale: true, stale_items: [staleItem] },
			liability: fixture(),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		// ONE badge for the whole page — not one per jurisdiction table.
		expect(screen.getAllByText('May be stale')).toHaveLength(1);
	});

	// AC3 — the badge must never merge with (a) the noTaxAuthorityDesignated banner or (b) the
	// per-jurisdiction reasonCopy()/basis_year register: all three render together, independently.
	it('a stale badge and the noTaxAuthorityDesignated banner render TOGETHER, independently (AC3 separation)', () => {
		const staleItem: StaleConstituentItem = {
			linked_source_id: '42',
			institution_name: 'Test Bank',
			provider: 'plaid',
			connection_status: 'login_required',
			status_class: null
		};
		render(TaxQuarterlyTables, {
			staleness: { is_stale: true, stale_items: [staleItem] },
			liability: fixture(),
			noTaxAuthorityDesignated: true,
			priorYearQ4: null
		});
		expect(screen.getByText('May be stale')).toBeTruthy();
		expect(screen.getByText('No account is marked as a tax authority.')).toBeTruthy();
	});

	it('a stale badge and a per-jurisdiction "no ledger designated" CTA render TOGETHER, independently', () => {
		const staleItem: StaleConstituentItem = {
			linked_source_id: '42',
			institution_name: 'Test Bank',
			provider: 'plaid',
			connection_status: 'login_required',
			status_class: null
		};
		render(TaxQuarterlyTables, {
			staleness: { is_stale: true, stale_items: [staleItem] },
			liability: fixture({
				jurisdictions: {
					federal: jurisdiction(),
					california: jurisdiction({
						ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' }
					})
				}
			}),
			noTaxAuthorityDesignated: false,
			priorYearQ4: null
		});
		expect(screen.getByText('May be stale')).toBeTruthy();
		expect(screen.getByRole('link', { name: /Designate an FTB \(California\) account/ })).toBeTruthy();
	});
});
