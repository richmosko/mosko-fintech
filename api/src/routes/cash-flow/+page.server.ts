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
// SELF-258 (staleness ramp): `staleness: StalenessData` is now wired via the SAME whole-tenant
// `loadStaleness()` call every other V1.1 surface already uses (root `+page.server.ts` /
// `allocation/+page.server.ts`) — one call, independent try/catch, degrades to UNKNOWN_STALENESS
// (never EMPTY_STALENESS — SELF-229 convention) on either an internal RPC failure or an
// unexpected throw. CashflowRollupTable.svelte's own module header names this as the marked seam
// this closes. Not threaded into any per-row join here (unlike root's composition table) — this
// route's rollup/panel have no per-Sub-Cat staleness leaf yet, so the whole-tenant value is
// passed straight through to `data.staleness` for Frontend's banner/footnote to render.
//
// §2.3.4 HISTORICAL EXPENDITURES PANEL (SELF-256, loader leg): `historicalExpenditures` /
// `historicalExpendituresUnclassifiedCount` come from ONE `loadHistoricalExpendituresPanel` call,
// on the SAME `asOf` this loader already resolved for the rollup above — see that module's own
// header for why one function/one parameter is what stands in for 098's "invoke both in one
// statement" contract on a PostgREST client. Independent try/catch, mirroring the rollup's own
// belt-and-suspenders boundary: a chart-panel read failure must never take down the rollup above
// it, and a rollup failure must never suppress the chart — HistoricalExpendituresChart.svelte
// does its own internal read-failed/empty/populated gating on these two props (VD's ruling, per
// +page.svelte's own module header). NULL-vs-0 on the count is passed through verbatim; never
// coalesced here (see historicalExpendituresPanel.ts's own header).

import { redirect } from '@sveltejs/kit';
import {
	loadCashflowCrossAccountRollup,
	type CashflowCrossAccountRollup
} from '$lib/server/queries/cashflowCrossAccountRollup';
import { loadHistoricalExpendituresPanel } from '$lib/server/queries/historicalExpendituresPanel';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { HistoricalExpenditurePoint } from '$lib/historical-expenditures';
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

	let historicalExpenditures: HistoricalExpenditurePoint[] | null = null;
	let historicalExpendituresUnclassifiedCount: number | null = null;
	try {
		const panel = await loadHistoricalExpendituresPanel(locals.supabase, asOf);
		historicalExpenditures = panel.points;
		historicalExpendituresUnclassifiedCount = panel.unclassifiedCount;
	} catch (err) {
		console.error('[cash-flow/+page.server] historical-expenditures panel load threw; degrading to null:', err);
		historicalExpenditures = null;
		historicalExpendituresUnclassifiedCount = null;
	}

	// SELF-258: the SAME whole-tenant `loadStaleness()` read every other V1.1 surface consumes —
	// NOT a second, route-scoped invocation of the 046 primitive. Independent try/catch,
	// mirroring the rollup/panel legs above: a staleness-read failure must never take down the
	// rollup or the historical-expenditures panel, and vice versa. Degrades to UNKNOWN_STALENESS
	// (never EMPTY_STALENESS) on either loadStaleness()'s own internal fail-soft or an unexpected
	// throw — see staleness.ts's own SELF-229 REWORK note for why "unknown" and "confirmed
	// healthy" must never collapse into each other.
	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[cash-flow/+page.server] staleness load threw; degrading to unknown staleness:', err);
		staleness = UNKNOWN_STALENESS;
	}

	return { rollup, historicalExpenditures, historicalExpendituresUnclassifiedCount, staleness };
};
