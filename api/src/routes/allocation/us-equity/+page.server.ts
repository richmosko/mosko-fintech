// allocation/us-equity/+page.server.ts — loader for the §2.2.3 US Equity sub-allocation
// drill-down page (SELF-241; per-row staleness wiring SELF-243). Backend-owned server surface
// (ARCH §4.1 allowlist). Frontend's allocation/us-equity/+page.svelte + UsEquityAllocationTable.svelte
// are the SOLE consumers of this loader's `data` shape (contract documented in that +page.svelte's
// own header at authoring time — this file satisfies it as written, no deviation needed).
//
// Mirrors the parent `/allocation/+page.server.ts`'s fail-soft, try/catch-per-read pattern,
// trimmed to the two signals this drill-down page actually needs:
//
//   - `usEquityAllocation` : UsEquityAllocation | null — `loadUsEquityAllocation()`'s result
//     (usEquityAllocation.ts), `.ok` collapsed to `null` on failure. NEVER a fabricated all-zero
//     table — same discipline as the parent loader's `allocation` field and netWorth.ts's
//     "null = the read failed" convention. loadUsEquityAllocation already fails soft internally to
//     `{ ok: false }`; the try/catch below is the belt-and-suspenders boundary for an unexpected
//     throw. SELF-243: every row inside `usEquityAllocation` now also carries its own `is_stale`
//     tri-state — the per-row staleness tint — derived from `staleLinkedSourceIds` below and
//     threaded into `loadUsEquityAllocation` as its third argument, mirroring the parent loader's
//     own `loadNonReAllocation` threading exactly (SELF-330 pattern, reused verbatim, not forked).
//
//   - `staleness` : StalenessData — the SAME whole-tenant `loadStaleness()` read the parent
//     `/allocation` loader consumes (staleness.ts: `fn_aggregation_has_stale_constituent()` takes
//     no per-surface argument — a whole-tenant read, not a table-scoped one). Degrades to
//     UNKNOWN_STALENESS on failure, never a re-derived call. Loaded FIRST (ahead of
//     `usEquityAllocation` below, unlike the SELF-241 shape) because SELF-243's per-row tint needs
//     `staleLinkedSourceIds` derived from it BEFORE `loadUsEquityAllocation` can run its own
//     contributor/account bridge — mirrors the parent loader's own staleness-before-composition
//     ordering for the identical reason.
//
// No `accountPresence` signal here — the parent `/allocation` page's AC10 empty-account-state
// need does not apply to this drill-down (frontend's documented contract names only the two
// fields above; the twelve rows render unconditionally per SELF-240 AC1, so there is no
// page-level empty-account branch to feed).
//
// Same `serverTodayAsOf()` default as the parent loader, for the same reason: no as-of
// query-param support wired here yet (schemas/asOf.ts's `resolveAllocationAsOf` — moved from
// schemas/allocation.ts at SELF-247/D-6 — exists but the route reads no query string today —
// revisit when a historical-as-of control lands).
//
// ⚠ AC3/AC4 ACCOUNT-NAME THREADING NOT WIRED HERE (F/CTO-pending, see usEquityAllocation.ts's own
// module header): this loader delivers the per-row `is_stale` BOOLEAN signal only — the same
// scope team-lead ratified as ruling-independent (the AC3/AC4 question decides tooltip CONTENT,
// not whether the indicator itself ships). No account-name resolution happens here or in
// usEquityAllocation.ts yet.

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

	// Loaded FIRST — SELF-243's `staleLinkedSourceIds` derivation (below) must exist before
	// `loadUsEquityAllocation` can run its own per-row contributor/account bridge.
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

	// SELF-243: REUSED VERBATIM from the parent `/allocation` loader's own derivation (same field,
	// same semantics) — `staleness.is_stale === null` means the ROOT read itself was unknown,
	// passed through as `null` rather than an empty Set so loadUsEquityAllocation propagates
	// UNKNOWN to every row instead of misreading "we don't know" as "we checked and it's empty."
	const staleLinkedSourceIds =
		staleness.is_stale === null
			? null
			: new Set(staleness.stale_items.map((item) => String(item.linked_source_id)));

	let usEquityAllocation: UsEquityAllocation | null = null;
	try {
		const result = await loadUsEquityAllocation(locals.supabase, asOf, staleLinkedSourceIds);
		usEquityAllocation = result.ok ? result.data : null;
	} catch (err) {
		console.error(
			'[allocation/us-equity/+page.server] usEquityAllocation load threw; degrading to null:',
			err
		);
		usEquityAllocation = null;
	}

	return { usEquityAllocation, staleness };
};
