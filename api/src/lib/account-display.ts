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
 * ⚠ SETTLED AT ADR-043 — this no longer carries an open UX flag. Whether a user-facing surface
 * should show UTC at all was a UX/Visual question; it is ruled: **UTC, unlabelled, for V1**, on all
 * three closure surfaces (accounts hub · account detail · connections detail).
 *
 * ⚠⚠ IT DOES, HOWEVER, CARRY A LIVE DEPENDENCY — AND CLOSING THE UX FLAG IS WHAT NEARLY BURIED IT.
 * The claim that makes this rendering *correct* rather than merely *consistent* — that the date on
 * the screen is the date the ledger reasoned with — holds **IF AND ONLY IF the Postgres session
 * TimeZone is UTC**. This function pins the RENDER to UTC; `closed_at::date` is evaluated in the
 * DATABASE SESSION zone. Off UTC the screen shows one day, the gate reasoned about another, and
 * NOTHING ERRORS. The pin is declared at migration `061` (`alter database … set timezone`) and is
 * NECESSARY-NOT-SUFFICIENT: a client `PGTZ`, or a role-level override on a LOGIN role, each defeat
 * it — both measured, both outranking the database-level setting. Deploy-gated at runbook §10 TZ-1.
 *
 * ⚠ The later `fn_server_today()` slice does NOT relieve this. It makes both sides of the DB-side
 * comparison share a zone; it does not make THIS render agree with them, because `current_date` is
 * session-zone-evaluated while the line below is hard-pinned to UTC. **For this function the
 * database pin is the sole load-bearing dependency, permanently.** Do not weaken this note when
 * that slice lands and the other TZ surfaces get re-pointed.
 *
 * **ANY CHANGE HERE IS ALL-THREE-SURFACES OR NONE.** A per-surface "fix" re-opens the
 * off-by-one-day that `059` measures. The trap is that ONE screen looks wrong in isolation — a
 * sweep of these three to local rendering was already proposed and stopped once — so the intuition
 * that prompts the change is exactly the one that must not be acted on per-surface. **The three
 * agreeing is the property; it is not the same defect copied three times.**
 * Re-opens on EITHER trigger (ADR-043 expiry conditions): (E1) a database whose session TimeZone is
 * not UTC, or reads UTC from `source = client` / `source = user` — which fires with NO user action
 * at all; or (E2) the first caller supplying `p_as_of` from a user's calendar rather than the
 * server's. E1 was missing from the original ruling and is the one that fires by itself.
 *
 * ⚠ NO TEST GUARDS ANY OF THE ABOVE AS OF THIS WRITING. The UTC pin, the three-surface invariant and
 * the unlabelled decision are enforced by this comment alone; QA's battery is specified at
 * `temp/closedatlabel-test-spec.md`. A test that passes under every process TZ is blind to the
 * variable at issue, not robust to it — it must be made to fail once with the zone pinned off UTC.
 *
 * `formatTimestamp` in transaction-util.ts carries a similarly-worded flag and **ADR-043 does NOT
 * settle it** — deliberately, not by omission. It is a different question: its single consumer is
 * SyncHistoryTable rendering provider-sync event times, which no gate compares against and which
 * no second surface has to agree with. The reasoning above is entirely about closure dates footing
 * to the ledger and to `058`'s legs, and none of it transfers. Left open on purpose.
 *
 * `null` → `''`: callers branch on open/closed and never render this for an open account.
 */
export function closedAtLabel(iso: string | null): string {
	if (!iso) return '';
	const d = new Date(iso);
	if (Number.isNaN(d.getTime())) return iso;
	return d.toLocaleString('en-US', { dateStyle: 'medium', timeZone: 'UTC' });
}
