// tax-quarterly.test.ts — direct unit coverage for the pure presentation helpers in
// tax-quarterly.ts (SELF-266). Closes Sec's SELF-264/266 review notes N-1 (LT CG rate guard was
// `undefined`-only, not nullish — `Intl.NumberFormat.format(null)` renders a fabricated "0%") and
// N-2 (no guard on `rate.ordinary` at all — an unguarded format would render "NaN%" on a null).
// Matches this directory's own precedent (tax-decomposition.test.ts) — a plain lib/*.ts module
// gets a lib/*.test.ts, not only indirect coverage through a component dom test.

import { describe, it, expect } from 'vitest';
import { federalRateCaption, californiaRateCaption, type TaxJurisdictionPayload } from './tax-quarterly';

function jurisdiction(
	over: Partial<TaxJurisdictionPayload> = {}
): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2025,
		schedules: {},
		inputs: { ordinary_input: 0, lt_cg_input: 0, standard_deduction: 0 },
		taxable_income: { ordinary: 0, lt_cg: 0 },
		annual_liability: 0,
		tax_balance_prior_year: null,
		installments: null,
		installments_due_through_next: 0,
		next_due_date: '2026-04-15',
		ytd_paid: { status: 'unavailable', reason: 'no_ledger_designated' },
		funds_due: { status: 'unavailable', reason: 'no_ledger_designated' },
		...over
	};
}

describe('federalRateCaption', () => {
	it('renders "Federal rates unavailable" when applied_marginal_rate is absent entirely', () => {
		expect(federalRateCaption(jurisdiction())).toBe('Federal rates unavailable');
	});

	it('N-1: renders "unavailable" for LT CG when lt_cg is null — never a fabricated "0%"', () => {
		const caption = federalRateCaption(
			jurisdiction({ applied_marginal_rate: { ordinary: 0.24, lt_cg: null } })
		);
		expect(caption).toBe('Federal ordinary: 24% / Federal LT CG: unavailable');
		expect(caption).not.toContain('0%');
	});

	it('a genuine 0 LT CG rate still renders "0%", not unavailable', () => {
		const caption = federalRateCaption(
			jurisdiction({ applied_marginal_rate: { ordinary: 0.24, lt_cg: 0 } })
		);
		expect(caption).toBe('Federal ordinary: 24% / Federal LT CG: 0%');
	});

	it('LT CG omitted entirely (undefined) still renders "unavailable"', () => {
		const caption = federalRateCaption(jurisdiction({ applied_marginal_rate: { ordinary: 0.24 } }));
		expect(caption).toBe('Federal ordinary: 24% / Federal LT CG: unavailable');
	});

	it('N-2: renders "unavailable" for the ordinary figure when ordinary is null — never "NaN%"', () => {
		const caption = federalRateCaption(
			jurisdiction({ applied_marginal_rate: { ordinary: null, lt_cg: 0.093 } })
		);
		expect(caption).toBe('Federal ordinary: unavailable / Federal LT CG: 9.3%');
		expect(caption).not.toContain('NaN');
	});

	it('a genuine 0 ordinary rate still renders "0%"', () => {
		const caption = federalRateCaption(
			jurisdiction({ applied_marginal_rate: { ordinary: 0, lt_cg: 0.093 } })
		);
		expect(caption).toBe('Federal ordinary: 0% / Federal LT CG: 9.3%');
	});
});

describe('californiaRateCaption', () => {
	it('renders "California rate unavailable" when applied_marginal_rate is absent entirely', () => {
		expect(californiaRateCaption(jurisdiction())).toBe('California rate unavailable');
	});

	it('N-2: renders "unavailable" when ordinary is null — never "NaN%"', () => {
		const caption = californiaRateCaption(jurisdiction({ applied_marginal_rate: { ordinary: null } }));
		expect(caption).toBe('California: unavailable');
		expect(caption).not.toContain('NaN');
	});

	it('a genuine 0 ordinary rate still renders "0%"', () => {
		const caption = californiaRateCaption(jurisdiction({ applied_marginal_rate: { ordinary: 0 } }));
		expect(caption).toBe('California: 0%');
	});
});
