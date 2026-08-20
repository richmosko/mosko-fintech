// allocation/us-equity/+page.server.ts — loader for the §2.2.3 US Equity sub-allocation
// drill-down page (SELF-241). Backend-owned server surface (ARCH §4.1 allowlist). Frontend's
// allocation/us-equity/+page.svelte + UsEquityAllocationTable.svelte are the SOLE consumers of
// this loader's `data` shape (contract documented in that +page.svelte's own header at
// authoring time — this file satisfies it as written, no deviation needed).
//
// Mirrors the parent `/allocation/+page.server.ts`'s fail-soft, try/catch-per-read pattern,
// trimmed to the two signals this drill-down page actually needs:
//
//   - `usEquityAllocation` : UsEquityAllocation | null — SELF-240's `loadUsEquityAllocation()`
//     result (usEquityAllocation.ts, already landed and tested), `.ok` collapsed to `null` on
//     failure. NEVER a fabricated all-zero table — same discipline as the parent loader's
//     `allocation` field and netWorth.ts's "null = the read failed" convention.
//     loadUsEquityAllocation already fails soft internally to `{ ok: false }`; the try/catch
//     below is the belt-and-suspenders boundary for an unexpected throw.
//
//   - `staleness` : StalenessData — the SAME whole-tenant `loadStaleness()` read the parent
//     `/allocation` loader consumes (staleness.ts: `fn_aggregation_has_stale_constituent()` takes
//     no per-surface argument — a whole-tenant read, not a table-scoped one). Degrades to
//     UNKNOWN_STALENESS on failure, never a re-derived call.
//
// No `accountPresence` signal here — the parent `/allocation` page's AC10 empty-account-state
// need does not apply to this drill-down (frontend's documented contract names only the two
// fields above; the twelve rows render unconditionally per SELF-240 AC1, so there is no
// page-level empty-account branch to feed).
//
// Same `serverTodayAsOf()` default as the parent loader, for the same reason: no as-of
// query-param support wired here yet (schemas/allocation.ts's `resolveAllocationAsOf` exists but
// the route reads no query string today — revisit when a historical-as-of control lands).

import { redirect } from '@sveltejs/kit';
import { loadUsEquityAllocation, type UsEquityAllocation } from '$lib/server/queries/usEquityAllocation';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const asOf = serverTodayAsOf();

	let usEquityAllocation: UsEquityAllocation | null = null;
	try {
		const result = await loadUsEquityAllocation(locals.supabase, asOf);
		usEquityAllocation = result.ok ? result.data : null;
	} catch (err) {
		console.error(
			'[allocation/us-equity/+page.server] usEquityAllocation load threw; degrading to null:',
			err
		);
		usEquityAllocation = null;
	}

	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error(
			'[allocation/us-equity/+page.server] staleness load threw; degrading to unknown staleness:',
			err
		);
		staleness = UNKNOWN_STALENESS;
	}

	return { usEquityAllocation, staleness };
};
