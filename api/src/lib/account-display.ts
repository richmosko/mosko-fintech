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

/**
 * Display form of `pfin.account.closed_at` (ADR-042 / `059`). DATE ONLY — no time.
 *
 * Shared rather than inlined at each call site because the accounts hub and the account-detail
 * page render the same closure, and **a closure that reads as two different days on two screens
 * is worse than one that reads as neither.**
 *
 * Locale AND time zone are pinned, for two separate reasons that happen to agree:
 *   • SSR/client determinism — an unpinned `toLocale*` renders in the server TZ then re-renders
 *     in the browser TZ, which is a hydration mismatch. (Same rationale as `formatTimestamp` in
 *     transaction-util.ts, whose shape this copies deliberately.)
 *   • UTC specifically, NOT the viewer's zone — the ledger renders its dates in UTC, and `058`'s
 *     close gate evaluates its three legs *as of* this same instant. A closure stamped 18:00
 *     Pacific is 4 August here and 5 August in the ledger if this one surface alone renders
 *     locally, so the account would appear closed the day BEFORE the entries the gate checked.
 *     Small, plausible, and un-diagnosable from the screen.
 *
 * Whether a user-facing surface should show UTC at all is a UX/Visual decision — flagged, not
 * settled here; the same standing flag `formatTimestamp` already carries.
 *
 * `null` → `''`: callers branch on open/closed and never render this for an open account.
 */
export function closedAtLabel(iso: string | null): string {
	if (!iso) return '';
	const d = new Date(iso);
	if (Number.isNaN(d.getTime())) return iso;
	return d.toLocaleString('en-US', { dateStyle: 'medium', timeZone: 'UTC' });
}
