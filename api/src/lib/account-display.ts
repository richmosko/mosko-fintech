// account-display.ts — presentation labels for the account enum value-sets.
//
// The VALUE-SETS are canonical (src/lib/schemas/account-constants.ts, tracked to the
// 003 DB CHECK). These are only the human-readable DISPLAY strings for the selects /
// detail view. Copy is PROVISIONAL — final user-facing wording is UX Designer's call
// (flagged at authoring). Kept exhaustive-by-type so a value-set change is a compile
// error here (Record<AccountType,…> / Record<TaxTreatment,…>), not a silent gap.

import type { AccountType, TaxTreatment } from '$lib/schemas/account-constants';

export const ACCOUNT_TYPE_LABELS: Record<AccountType, string> = {
	depository: 'Depository',
	investment: 'Investment',
	retirement: 'Retirement',
	crypto: 'Crypto',
	manual_other: 'Manual / other',
	real_estate: 'Real estate',
	liability: 'Liability'
};

export const TAX_TREATMENT_LABELS: Record<TaxTreatment, string> = {
	taxable: 'Taxable',
	tax_deferred: 'Tax-deferred',
	tax_free: 'Tax-free'
};

/** Safe lookup that falls back to the raw value if an unknown value ever appears. */
export function accountTypeLabel(v: string): string {
	return (ACCOUNT_TYPE_LABELS as Record<string, string>)[v] ?? v;
}
export function taxTreatmentLabel(v: string): string {
	return (TAX_TREATMENT_LABELS as Record<string, string>)[v] ?? v;
}
