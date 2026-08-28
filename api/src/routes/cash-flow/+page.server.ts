// cash-flow/+page.server.ts — loader for the §2.3.2.b cross-account cash-flow rollup page
// (SELF-251). Backend-owned server surface (ARCH §4.1 allowlist); frontend consumes ONLY the
// already-hardened `loadCashflowCrossAccountRollup` wrapper (SELF-250) — no reader logic is
// authored here.
//
// ROUTE: `/cash-flow` — confirmed by SELF-252 AC8 (`docs/records/v13-preflight/rederived-acs.md`):
// "Submit redirects to `/cash-flow`, showing the updated inline target captions," so this is the
// canonical route name, not a frontend-invented path.
//
// ONE-SOURCE / ADR-044 D2: `asOf` is resolved ONCE via `serverTodayAsOf()` and threaded to the
// SINGLE `loadCashflowCrossAccountRollup` call below — the S-2 banner's `unclassified.count_ytd`
// and every section sum come out of that SAME call/payload, never a second independently-
// defaulted read (cashflowCrossAccountRollup.ts's own module header states the hazard this
// avoids: two requests each defaulting `p_as_of` independently can straddle midnight and
// disagree). No client-supplied as-of exists on this surface (Lock 15 reserves that for
// §2.3.3 / SELF-253).
//
// FAIL-SOFT: `rollup` degrades to `null` on any read error — loadCashflowCrossAccountRollup
// already fails soft internally; this try/catch is the belt-and-suspenders boundary for an
// unexpected throw, matching every other §2.1/§2.2 loader's posture (netWorth.ts /
// nonReAllocation.ts / navComposition.ts). NEVER a fabricated zero-valued rollup.
//
// SELF-258 (staleness ramp) is a SOFT dependency and is NOT wired here — see
// CashflowRollupTable.svelte's own module header for the marked seam. This loader does not call
// `loadStaleness()` at all; wiring it is SELF-258's job, not this issue's.

import { redirect } from '@sveltejs/kit';
import {
	loadCashflowCrossAccountRollup,
	type CashflowCrossAccountRollup
} from '$lib/server/queries/cashflowCrossAccountRollup';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const asOf = serverTodayAsOf();

	let rollup: CashflowCrossAccountRollup | null = null;
	try {
		rollup = await loadCashflowCrossAccountRollup(locals.supabase, asOf);
	} catch (err) {
		console.error('[cash-flow/+page.server] rollup load threw; degrading to null:', err);
		rollup = null;
	}

	return { rollup };
};
