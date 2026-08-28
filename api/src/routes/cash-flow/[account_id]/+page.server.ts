// cash-flow/[account_id]/+page.server.ts — loader for the §2.3.3.b per-account cash-flow
// drill-down page (SELF-254). Backend-owned server surface (ARCH §4.1 allowlist); frontend
// consumes ONLY the already-hardened `loadCashflowPerAccountForRequest` wrapper (SELF-253) — no
// reader logic, no validation logic, is authored here. Mirrors cash-flow/+page.server.ts's own
// SELF-251 shape and its own precedent of frontend-engineer authoring thin wiring over an
// already-built Backend query wrapper in the same feature commit.
//
// ONE LOADER CALL PER REQUEST (binding constraint #1): `accountIdRaw` is the route param string,
// unparsed — `loadCashflowPerAccountForRequest`'s own `validateCashflowPerAccountParams` is the
// ONE place either boundary input is checked, so this file performs no pre-validation of its own
// that could drift from it. `asOfRaw` is `url.searchParams.get('as_of')`, an ALREADY-EXTRACTED
// single value — never a raw unfiltered searchParams object (cashflowPerAccount.ts's own module
// header: this is exactly the shape its NAMESPACE-SAFE-BY-CONSTRUCTION note requires).
//
// THE CLOCK (AC4 / ADR-044 D2): `maxAsOf` is resolved ONCE via `serverTodayAsOf()` and threaded
// to the ONE `loadCashflowPerAccountForRequest` call below — both the as-of widget's default AND
// its upper bound are this SAME value, passed through page data, never re-derived client-side.
//
// 400 SPLIT (AC4 item 3 of the dispatch brief): `validateCashflowPerAccountParams` runs BOTH
// checks unconditionally, so a 400 may name `account_id`, `as_of`, or both.
//   - `account_id` invalid: NOT a user-correctable input on this page (the account picker only
//     ever offers real, owned account ids — AC3's structural-picker fence; this path is reachable
//     only via a hand-edited URL, same posture as accounts/[account_id]'s own 404 for a bad id) →
//     `error(404, …)`, matching that page's own convention.
//   - `as_of` invalid (and `account_id` valid): a user-correctable input via the AC4 toggle — no
//     RPC was ever attempted (validateCashflowPerAccountParams checks both fields BEFORE any SQL
//     invocation), so this degrades to a SANE INLINE ERROR STATE (`asOfError` in the returned
//     data), never a thrown `error()` — a thrown error page is the "crash" surface the brief's
//     item 3 explicitly rules out for this case.
//
// ACCOUNT LIST (AC3): a second, independent read — `account_id, name, closed_at` for every one of
// the caller's OWN accounts (RLS-scoped), INCLUDING closed (`closed_at !== null`), matching
// accounts/+page.server.ts's own account-list read verbatim in shape (same columns subset, same
// "management/render surface asks closed_at !== null, nothing more" posture — api/CLAUDE.md's
// closure contract). Fail-soft to `[]` on a read error: the picker degrades to absent rather than
// blocking the page, and the current account's own name/closed_at (looked up from this SAME list,
// no second per-account read) falls back to a bare "Account #<id>" label — a page that already
// has valid cashflow data must not be taken down by a decorative header field.
//
// AC8 of cashflowSections.ts: `CASHFLOW_OTHER_CASH_FLOWS_NOTE` is threaded through page data
// rather than hand-copied into a browser module — that module lives under `$lib/server/**` and is
// unreachable from `+page.svelte` / `$lib/components/**` by the compiler's own server-boundary
// guard, so threading through the ONE loader that CAN import it is the only way to keep this a
// true single source (a hand-copy client-side would open a second home for the sentence).

import { error, redirect } from '@sveltejs/kit';
import {
	loadCashflowPerAccountForRequest,
	type CashflowPerAccount
} from '$lib/server/queries/cashflowPerAccount';
import { CASHFLOW_OTHER_CASH_FLOWS_NOTE } from '$lib/server/queries/cashflowSections';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import { AS_OF_FLOOR } from '$lib/server/schemas/asOf';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { PageServerLoad } from './$types';

export type CashflowAccountOption = {
	account_id: number;
	name: string;
	closed_at: string | null;
};

// RLS-scoped read. acct_number intentionally NOT selected — masked-only render posture (SD-15),
// same as every other account-list read in this tree.
async function loadAccountOptions(supabase: SupabaseClient): Promise<CashflowAccountOption[]> {
	const { data, error: err } = await supabase
		.schema('pfin')
		.from('account')
		.select('account_id, name, closed_at')
		.order('name', { ascending: true });

	if (err) {
		console.error('[cash-flow/[account_id]] account list read failed:', err.message);
		return [];
	}
	return (data ?? []) as CashflowAccountOption[];
}

export const load: PageServerLoad = async ({ locals, params, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const maxAsOf = serverTodayAsOf();
	const asOfRaw = url.searchParams.get('as_of');

	const result = await loadCashflowPerAccountForRequest(locals.supabase, {
		accountIdRaw: params.account_id,
		asOfRaw,
		maxAsOf
	});

	const accounts = await loadAccountOptions(locals.supabase);

	if (result.status === 400) {
		if (result.fieldErrors.account_id) throw error(404, 'Account not found');
		return {
			drilldown: null as CashflowPerAccount | null,
			asOfError: result.fieldErrors.as_of?.[0] ?? 'That date is invalid.',
			accounts,
			maxAsOf,
			asOfFloor: AS_OF_FLOOR,
			otherCashFlowsNote: CASHFLOW_OTHER_CASH_FLOWS_NOTE
		};
	}

	return {
		drilldown: result.data,
		asOfError: null as string | null,
		accounts,
		maxAsOf,
		asOfFloor: AS_OF_FLOOR,
		otherCashFlowsNote: CASHFLOW_OTHER_CASH_FLOWS_NOTE
	};
};
