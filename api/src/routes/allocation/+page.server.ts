// allocation/+page.server.ts — loader for the §2.2.2 Non-RE allocation table page (SELF-239).
// Backend-owned server surface (ARCH §4.1 allowlist). Frontend's allocation/+page.svelte +
// NonReAllocationTable.svelte are the SOLE consumers of this loader's `data` shape — the same
// division of labor as the root `+page.server.ts` / dashboard pair.
//
// Mirrors root `+page.server.ts`'s established fail-soft, three-signal pattern:
//
//   - `allocation` : NonReAllocation | null — loadNonReAllocation's result (this ticket's own
//     query layer), `.ok` collapsed to `null` on failure. NEVER a fabricated zero-valued table —
//     matches netWorth.ts's own "null = the read failed; a genuine 0/negative total is a genuine
//     0/negative total" discipline. loadNonReAllocation already fails soft internally to
//     `{ ok: false }`; the try/catch below is the belt-and-suspenders boundary for an unexpected
//     throw, same posture root takes around every one of its own reads.
//
//   - `staleness` : StalenessData — the SAME whole-tenant `loadStaleness()` read every other V1.1
//     NAV/composition surface already consumes (staleness.ts: `fn_aggregation_has_stale_constituent()`
//     takes no per-surface argument — a whole-tenant read, not a scoped one), NOT a re-derived or
//     table-scoped call. Degrades to UNKNOWN_STALENESS on failure, never EMPTY_STALENESS (SELF-229
//     convention) — loadStaleness() already degrades an RPC error internally; this try/catch is the
//     belt-and-suspenders boundary for an unexpected throw.
//
//   - `accountPresence` : 'some' | 'none' | 'unknown' — REUSED VERBATIM from loadNetWorthView
//     (netWorth.ts), not a second, independently-authored open-account count. Two reasons:
//       (1) netWorth.ts's own predicate (open-as-of-`asOf`, the 059 half-open-bound rewrite) IS the
//           "does this tenant own any account" signal AC10 needs — hand-copying it a second time
//           here is a drift risk this file does not need to take on, on a predicate netWorth.ts's
//           own header already spends its full length getting right.
//       (2) netWorth.ts's own stated invariant — "a non-zero valuation implies at least one open
//           account, because the valuation and the count read the SAME population at the SAME
//           asOf" — is a fact about accounts, not about `fn_compute_nav` specifically: it holds
//           just as well for `total_non_re` (also sourced from positions tied to open accounts) as
//           it does for `netWorth`. Pairing THIS page's `accountPresence` against `total_non_re` is
//           therefore sound PROVIDED both reads share the same `asOf` — which they do below.
//     `netWorth` itself (the number) is discarded — it is never part of this page's `data` and is
//     never rendered here. Cost: one extra `fn_compute_nav` RPC call per page-load, traded against
//     NOT maintaining a second copy of netWorth.ts's closed-account predicate. If this page ever
//     needs Non-RE-SCOPED presence semantics (distinct from "any account at all"), that is a NEW,
//     differently-named signal — not a repurposing of this one. Same fail-soft-with-try/catch
//     belt-and-suspenders posture as the other two reads; degrades to 'unknown' on an unexpected
//     throw (loadNetWorthView already fails its own count read soft to 'unknown' internally).
//
// NO `as_of` QUERY-PARAM SUPPORT YET. `schemas/allocation.ts`'s `allocationAsOfSchema` /
// `resolveAllocationAsOf` exist for exactly this (SELF-238 AC8 / SELF-240 AC6's shared clause),
// but that file's own header explicitly defers wiring to "whoever builds the route" and requires
// either a namespace prefix or confirmation the route carries no other params (root's own
// `chart_`-prefix precedent, for the identical reason). Frontend's delivered `+page.svelte` reads
// no query string at all today — no as-of picker exists to exercise it — so wiring an unused
// param here would be speculative surface with nothing behind it. `serverTodayAsOf()` matches
// root's own headline default. Revisit (and namespace or confirm-no-other-params at that point)
// when a historical-as-of control actually lands on this page.

import { redirect } from '@sveltejs/kit';
import { loadNonReAllocation, type NonReAllocation } from '$lib/server/queries/nonReAllocation';
import { loadNetWorthView, type NetWorthView } from '$lib/server/queries/netWorth';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const asOf = serverTodayAsOf();

	let allocation: NonReAllocation | null = null;
	try {
		const result = await loadNonReAllocation(locals.supabase, asOf);
		allocation = result.ok ? result.data : null;
	} catch (err) {
		console.error('[allocation/+page.server] allocation load threw; degrading to null:', err);
		allocation = null;
	}

	let accountPresence: NetWorthView['accountPresence'] = 'unknown';
	try {
		({ accountPresence } = await loadNetWorthView(locals.supabase, asOf));
	} catch (err) {
		console.error('[allocation/+page.server] accountPresence load threw; degrading to unknown:', err);
		accountPresence = 'unknown';
	}

	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[allocation/+page.server] staleness load threw; degrading to unknown staleness:', err);
		staleness = UNKNOWN_STALENESS;
	}

	return { allocation, staleness, accountPresence };
};
