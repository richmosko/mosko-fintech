// monthly-report.test.ts — unit coverage for `noLedgerDesignated` (SELF-356 / P4 AC4), the
// pure-function derivation this ticket adds to $lib/monthly-report.ts. Everything else in that
// module (parseTargetMonth, groupAllocationByCat, rebalancingSubSections, monthYearStamp) already
// has coverage via the routes/components that exercise it; this file is scoped to the ONE new
// piece of standalone logic P4 introduces.

import { describe, it, expect } from 'vitest';
import { noLedgerDesignated } from './monthly-report';
import type { MonthlyReportPayload } from './monthly-report';
import type { TaxJurisdictionPayload } from './tax-quarterly';

/** A structurally-complete TaxJurisdictionPayload with innocuous defaults — only `ytd_paid` is
 *  varied per test, matching the ONE field `noLedgerDesignated` actually inspects. */
function jurisdiction(ytdPaid: TaxJurisdictionPayload['ytd_paid']): TaxJurisdictionPayload {
	return {
		status: 'computed',
		basis_year: 2026,
		schedules: {},
		inputs: { ordinary_input: 0, lt_cg_input: 0, standard_deduction: 0 },
		taxable_income: { ordinary: 0, lt_cg: 0 },
		annual_liability: 0,
		tax_balance_prior_year: 0,
		installments: [],
		installments_due_through_next: 0,
		next_due_date: '2026-09-15',
		ytd_paid: ytdPaid,
		funds_due: { status: 'computed', amount: 0 }
	};
}

const DESIGNATED: TaxJurisdictionPayload['ytd_paid'] = { status: 'designated', amount: 100 };
const NO_LEDGER: TaxJurisdictionPayload['ytd_paid'] = {
	status: 'unavailable',
	reason: 'no_ledger_designated'
};
const OTHER_UNAVAILABLE: TaxJurisdictionPayload['ytd_paid'] = {
	status: 'unavailable',
	reason: 'some_other_reason'
};

/** Only `sections.estimated_taxes.jurisdictions` is load-bearing for this function — the other
 *  five section keys are cast past rather than filled out, since this is pure-logic coverage on
 *  one derivation, not a payload-shape test. */
function payload(
	federal: TaxJurisdictionPayload,
	california: TaxJurisdictionPayload
): Pick<MonthlyReportPayload, 'sections'> {
	return {
		sections: {
			estimated_taxes: { jurisdictions: { federal, california } }
		}
	} as unknown as Pick<MonthlyReportPayload, 'sections'>;
}

describe('noLedgerDesignated — AC4 pre-finalize prompt derivation', () => {
	it('false when both jurisdictions carry a designated ledger', () => {
		expect(noLedgerDesignated(payload(jurisdiction(DESIGNATED), jurisdiction(DESIGNATED)))).toBe(false);
	});

	it('true when federal (IRS) has no ledger designated, california (FTB) does', () => {
		expect(noLedgerDesignated(payload(jurisdiction(NO_LEDGER), jurisdiction(DESIGNATED)))).toBe(true);
	});

	it('true when california (FTB) has no ledger designated, federal (IRS) does — an ANY, not an ALL', () => {
		expect(noLedgerDesignated(payload(jurisdiction(DESIGNATED), jurisdiction(NO_LEDGER)))).toBe(true);
	});

	it('true when BOTH jurisdictions have no ledger designated', () => {
		expect(noLedgerDesignated(payload(jurisdiction(NO_LEDGER), jurisdiction(NO_LEDGER)))).toBe(true);
	});

	it('false when a jurisdiction is unavailable for a DIFFERENT reason — the reason string is load-bearing, not just the status', () => {
		expect(
			noLedgerDesignated(payload(jurisdiction(OTHER_UNAVAILABLE), jurisdiction(DESIGNATED)))
		).toBe(false);
	});
});
