// TaxJurisdictionTable.dom.test.ts — SELF-266 verification battery for the §2.5.3.b jurisdiction
// table's ACs.
//
// ENV: jsdom + @testing-library/svelte. Query via testing-library helpers (getByRole/getByText),
// never `container.querySelector` for element lookup — this repo's own
// testing-library-container-queryselector-rune-error gotcha (see NonReAllocationTable.dom.test.ts
// header). `getByLabelText` is avoided entirely here (no form fields on this read-only surface).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, screen, within } from '@testing-library/svelte';
import TaxJurisdictionTable from './TaxJurisdictionTable.svelte';
import type { TaxJurisdictionPayload, PriorYearQ4 } from '$lib/tax-quarterly';

// null === R8 window closed (the shape `+page.server.ts` passes through when
// `liability.prior_year_q4_window.open` is false — see load.server.test.ts).
const NO_PRIOR_YEAR_Q4: PriorYearQ4 | null = null;

// E39 fixture — mirrors loadPriorYearQ4's real return shape (taxLiability.ts), verified against
// the merged `taxes/quarterly/load.server.test.ts` PRIOR_YEAR_Q4_STUB.
const PRIOR_YEAR_Q4: PriorYearQ4 = {
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
		funds_due_envelope: { status: 'unavailable', reason: 'no_ledger_designated' }
	}
};

function installments(amounts: [number, number, number, number]) {
	return [1, 2, 3, 4].map((q) => ({
		quarter: q as 1 | 2 | 3 | 4,
		due_date: q === 1 ? '2026-04-15' : q === 2 ? '2026-06-15' : q === 3 ? '2026-09-15' : '2027-01-15',
		amount: amounts[q - 1]
	}));
}

function federalFixture(over: Partial<TaxJurisdictionPayload> = {}): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2026,
		schedules: {
			federal_ordinary: { present: true, basis_year: 2026, current_year_schedule_empty: false },
			federal_lt_cg: { present: true, basis_year: 2026, current_year_schedule_empty: false, standard_deduction_ignored: false }
		},
		inputs: { ordinary_input: 100000, lt_cg_input: 5000, standard_deduction: 14600 },
		taxable_income: { ordinary: 85400, lt_cg: 5000 },
		annual_liability: 12000,
		tax_balance_prior_year: 500,
		installments: installments([3000, 3000, 3000, 3000]),
		installments_due_through_next: 2,
		next_due_date: '2026-06-15',
		ytd_paid: { status: 'designated', amount: 3000 },
		funds_due: { status: 'computed', amount: 3000 },
		applied_marginal_rate: { ordinary: 0.24, lt_cg: 0.15 },
		...over
	};
}

function californiaFixture(over: Partial<TaxJurisdictionPayload> = {}): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2025,
		schedules: {
			california_ordinary: { present: true, basis_year: 2025, current_year_schedule_empty: true }
		},
		inputs: { ordinary_input: 100000, lt_cg_input: 0, standard_deduction: 5202 },
		taxable_income: { ordinary: 94798, lt_cg: null },
		annual_liability: 8000,
		tax_balance_prior_year: null,
		installments: installments([2000, 2000, 2000, 2000]),
		installments_due_through_next: 2,
		next_due_date: '2026-06-15',
		ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' },
		funds_due: { status: 'unavailable', reason: 'no_ledger_designated' },
		applied_marginal_rate: { ordinary: 0 },
		...over
	};
}

describe('TaxJurisdictionTable — computed rendering', () => {
	it('renders both the Federal and California table shapes with their own captions (AC1/AC4)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByRole('heading', { name: 'Federal Income Taxes' })).toBeTruthy();
		expect(screen.getByText('Federal ordinary: 24% / Federal LT CG: 15%')).toBeTruthy();
	});

	it('renders California caption as a single figure, and a genuine 0% LT CG-equivalent as a real 0, not unavailable (AC4)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: californiaFixture(),
			jurisdictionKey: 'california',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByRole('heading', { name: 'California State Income Taxes (CA FTB)' })).toBeTruthy();
		// California's own applied_marginal_rate.ordinary is a genuine 0 here — must render "0%".
		expect(screen.getByText('California: 0%')).toBeTruthy();
	});

	it('emphasizes the current-quarter row via installments_due_through_next (AC3/ξ-1)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({ installments_due_through_next: 2 }),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const q2Row = screen.getByRole('row', { name: /Q2 Estimated Payment/ });
		expect(q2Row.className).toContain('current-row');
		const q1Row = screen.getByRole('row', { name: /Q1 Estimated Payment/ });
		expect(q1Row.className).not.toContain('current-row');
	});

	it('emphasizes Q4 when installments_due_through_next is 4 (the Sep16-Jan15 window; AC3 note)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({ installments_due_through_next: 4 }),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const q4Row = screen.getByRole('row', { name: /Q4 Estimated Payment/ });
		expect(q4Row.className).toContain('current-row');
	});

	it('Sub-Total sums the installments through the next due date, not a naive per-installment multiply (Decision 5(i))', () => {
		// Q4 carries a residual: amounts sum exactly at N=4 even though Q1 != annual/4.
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				installments: installments([3000, 3000, 3000, 3000.02]),
				installments_due_through_next: 4,
				annual_liability: 12000.02
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const subtotalRow = screen.getByRole('row', { name: /Sub-Total/ });
		expect(within(subtotalRow).getByText('$12,000.02')).toBeTruthy();
	});

	it('renders Estimated Funds Due as a NEGATIVE value on overpayment, sign-flipped, no separate refund row (ν-1/AC5)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({ funds_due: { status: 'computed', amount: -450 } }),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const dueRow = screen.getByRole('row', { name: /Estimated Funds Due/ });
		expect(within(dueRow).getByText('-$450.00')).toBeTruthy();
		expect(screen.queryByText(/refund/i)).toBeNull();
	});

	it('E40 (Sec M-8/AC 8b) — renders every money cell to the CENT: the four installments and the Sub-Total foot exactly as displayed, never rounded to whole dollars', () => {
		// Q1-Q3 truncated equal cents, Q4 carries the residual (Decision 5(d)) — a whole-dollar
		// render would show all four as "$3,000" and the Sub-Total as "$12,000", silently hiding
		// the 2-cent residual AC 8b requires to be visible.
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				installments: installments([3000.01, 3000.01, 3000.01, 2999.97]),
				installments_due_through_next: 4,
				annual_liability: 12000
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const displayed = [
			within(screen.getByRole('row', { name: /Q1 Estimated Payment/ })).getByText(/^\$/).textContent,
			within(screen.getByRole('row', { name: /Q2 Estimated Payment/ })).getByText(/^\$/).textContent,
			within(screen.getByRole('row', { name: /Q3 Estimated Payment/ })).getByText(/^\$/).textContent,
			within(screen.getByRole('row', { name: /Q4 Estimated Payment/ })).getByText(/^\$/).textContent
		];
		expect(displayed).toEqual(['$3,000.01', '$3,000.01', '$3,000.01', '$2,999.97']);
		const subtotalRow = screen.getByRole('row', { name: /Sub-Total/ });
		const displayedSubtotal = within(subtotalRow).getByText(/^\$/).textContent;
		expect(displayedSubtotal).toBe('$12,000.00');
		// The displayed cents actually foot: parse every rendered installment string back to a
		// number and sum it — this is the property a whole-dollar render would silently violate.
		const parsedSum = displayed.reduce((sum, s) => sum + Number(s!.replace(/[$,]/g, '')), 0);
		expect(parsedSum).toBeCloseTo(Number(displayedSubtotal!.replace(/[$,]/g, '')), 2);
	});

	it('renders YTD Paid unavailable with a CTA when the reason is no_ledger_designated, never as $0 (AC6(iii)/B3)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: californiaFixture(),
			jurisdictionKey: 'california',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		const ytdRow = screen.getByRole('row', { name: /YTD Paid/ });
		expect(within(ytdRow).queryByText('$0')).toBeNull();
		expect(within(ytdRow).getByText(/No ledger designated/)).toBeTruthy();
		expect(within(ytdRow).getByRole('link', { name: /Designate an FTB \(California\) account/ })).toBeTruthy();
	});

	it('never renders an unavailable envelope as $0 anywhere on the table', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: californiaFixture(),
			jurisdictionKey: 'california',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.queryByText('$0')).toBeNull();
	});

	it('renders a basis-year note when the resolved schedule differs from the tax year, with the empty-schedule reason ONLY when the payload states it (E22)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: californiaFixture(),
			jurisdictionKey: 'california',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(
			screen.getByText('California on the 2025 schedule — no 2026 schedule entered yet.')
		).toBeTruthy();
	});

	it('does not append a "not entered yet" reason when current_year_schedule_empty is false', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				schedules: {
					federal_ordinary: { present: true, basis_year: 2025, current_year_schedule_empty: false },
					federal_lt_cg: { present: true, basis_year: 2026, current_year_schedule_empty: false }
				}
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByText('Federal ordinary on the 2025 schedule.')).toBeTruthy();
	});

	it('renders the standard-deduction-ignored note only when the LT CG schedule flags it (Decision 5(h))', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				schedules: {
					federal_ordinary: { present: true, basis_year: 2026, current_year_schedule_empty: false },
					federal_lt_cg: {
						present: true,
						basis_year: 2026,
						current_year_schedule_empty: false,
						standard_deduction_ignored: true
					}
				}
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByText(/We ignored the standard deduction/)).toBeTruthy();
	});
});

describe('TaxJurisdictionTable — empty states', () => {
	it('renders the AC-7a UNAVAILABLE line with a CTA when no schedule resolves in any year, never a table of zeros', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				status: 'unavailable',
				reason: 'no_schedule_any_year',
				basis_year: null,
				installments: null
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByText('No bracket schedule on file for this jurisdiction.')).toBeTruthy();
		expect(screen.getByRole('link', { name: 'Edit tax brackets' })).toBeTruthy();
		expect(screen.queryByRole('table')).toBeNull();
	});

	it('still shows next_due_date on an unavailable jurisdiction (Sec N-11 — a due date is true regardless of computability)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({
				status: 'unavailable',
				reason: 'no_schedule_any_year',
				basis_year: null,
				installments: null,
				next_due_date: '2026-09-15'
			}),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.getByText(/Next installment due Sep 15, 2026/)).toBeTruthy();
	});
});

describe('TaxJurisdictionTable — prior-year Q4 window (AC2a/R8/E39, team-lead ruling)', () => {
	it('renders the prior-year Q4 outstanding notice with the pay-by copy naming the current tax year', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: PRIOR_YEAR_Q4
		});
		expect(screen.getByText('2025 Q4 still outstanding')).toBeTruthy();
		expect(
			screen.getByText("Pay by Jan 15, 2026. Payments made this January appear in 2026's YTD Paid.")
		).toBeTruthy();
	});

	it('renders the obligation from the E39 Dec-31 payload — the PRIOR year\'s own Q4 amount, never a current-year figure — with the prior annual as a secondary figure', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: PRIOR_YEAR_Q4
		});
		const obligationRow = screen.getByRole('row', { name: /Q4 2025 Payment/ });
		expect(within(obligationRow).getByText('$1,200.00')).toBeTruthy();
		expect(within(obligationRow).getByText(/2025 annual: \$4,800\.00/)).toBeTruthy();
	});

	it('renders NO YTD Paid cell in the prior-year block (team-lead ruling — R8 keeps YTD Paid ledger-scoped, never invented per-prior-year)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture({ ytd_paid: { status: 'designated', amount: 3000 } }),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: PRIOR_YEAR_Q4
		});
		// Exactly ONE "YTD Paid" row exists — the current-year table's own — even with the prior-year
		// block rendered alongside it.
		expect(screen.getAllByRole('row', { name: /YTD Paid/ })).toHaveLength(1);
	});

	it("renders the PRIOR year's own Funds Due envelope labelled \"as of Dec 31\", unavailable-with-reason when that envelope says so, never $0", () => {
		render(TaxJurisdictionTable, {
			jurisdiction: californiaFixture(),
			jurisdictionKey: 'california',
			taxYear: 2026,
			priorYearQ4: PRIOR_YEAR_Q4
		});
		const fundsDueRow = screen.getByRole('row', { name: /Funds Due \(as of Dec 31, 2025\)/ });
		expect(within(fundsDueRow).getByText(/No ledger designated/)).toBeTruthy();
		expect(screen.queryByText('$0')).toBeNull();
	});

	it('renders the PRIOR year Funds Due as a real computed figure when the envelope says so', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: PRIOR_YEAR_Q4
		});
		const fundsDueRow = screen.getByRole('row', { name: /Funds Due \(as of Dec 31, 2025\)/ });
		expect(within(fundsDueRow).getByText('$1,200.00')).toBeTruthy();
	});

	it('renders nothing prior-year-Q4-shaped when priorYearQ4 is null (window closed)', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: NO_PRIOR_YEAR_Q4
		});
		expect(screen.queryByText(/still outstanding/)).toBeNull();
		expect(screen.getAllByRole('row', { name: /YTD Paid/ })).toHaveLength(1);
	});

	it('renders "Unavailable" (never $0) when the Dec-31 payload itself had no installments', () => {
		render(TaxJurisdictionTable, {
			jurisdiction: federalFixture(),
			jurisdictionKey: 'federal',
			taxYear: 2026,
			priorYearQ4: {
				...PRIOR_YEAR_Q4,
				federal: { q4_installment: null, annual_liability: null, funds_due_envelope: { status: 'unavailable', reason: 'no_schedule_any_year' } }
			}
		});
		const obligationRow = screen.getByRole('row', { name: /Q4 2025 Payment/ });
		expect(within(obligationRow).getByText('Unavailable')).toBeTruthy();
		expect(within(obligationRow).queryByText('$0')).toBeNull();
	});
});
