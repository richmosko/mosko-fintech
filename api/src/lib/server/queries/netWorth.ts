// netWorth.ts — server-side read for the §2.1.1 headline Net Worth surface (SELF-211).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// ⚠ THE READ SOURCE FLIPPED AT SELF-268 (ADR-067 Decision 3 / sitting-log R3, option A′ — ONE-WAY
//   DOOR — riders 0 / 4). The §2.1.1 read is now the composed value pfin.fn_nav_composition's
//   `nav` key (`051`, as amended at `102`) — the SAME single reader the §2.1.5 foot consumes
//   (navComposition.ts) — via `fetchNavComposition`/`loadNavComposition`, NOT a second,
//   independently-defined aggregation. "ONE composed value, ONE reader; no surface composes its
//   own" (R3 rider 0). This function no longer calls `pfin.fn_compute_nav` at all.
//
//   WHY: `fn_compute_nav` keeps its GROSS, pre-tax-exclusion definition and is retained ONLY so
//   `nav_daily` (the permanently-gross checkpoint series) keeps writing — it is now read by NO
//   live surface. Leaving the headline on `fn_compute_nav` would retain the exact double-count
//   E-2's `051` leaf-set exclusion was ruled to fix: paying a tax authority $P would still raise
//   the headline by $P while the §2.1.5 foot (already reading the exclusion-filtered `051`) would
//   not move, so the two "live surfaces sharing one value" would not actually share it.
//   SELF-226's own foot-to-headline reconciliation battery is the watcher that goes RED if this
//   flip is ever reverted for the headline alone (R3) — it stays in the suite (SELF-269).
//
//   INVOKER propagation is unchanged in kind: `fn_nav_composition` is itself `SECURITY INVOKER`
//   (Lock 11), called through the per-request anon/authenticated client so RLS applies
//   (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11) — see navComposition.ts's own
//   header for `051`'s full INVOKER/tenant-isolation story, which this module now inherits rather
//   than restates.
//
// AS-OF (R3 rider 4): the SAME `fn_server_today()`-derived `ZoneResolvedAsOf` is threaded through
// this call and the §2.1.5 foot's on one request (see the root `+page.server.ts` call site) — not
// re-derived here. `fn_nav_composition` composes on `049` (fn_account_unrealized_gl), which
// carries its own OPEN-AS-OF predicate (`closed_at is null or closed_at::date > p_as_of`, 059 /
// ADR-042) — the identical population the open-account count below scopes to, so the two remain
// reconciled the same way they always were.
//
// The composition breakdown (GAV / Debt / tax lines) is §2.1.5 = V1.1 (SELF-225); V1.0
// renders the single number only, per PRD §2.1.1 verbatim + F/CTO Option A.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { fetchNavComposition, type RawNavComposition } from './navComposition';

export type NetWorthView = {
	/**
	 * USD net worth as of the requested date — pfin.fn_nav_composition's composed `nav` (R3 rider
	 * 0; SELF-268), the SAME value the §2.1.5 foot reads, NOT pfin.fn_compute_nav. `null` iff the
	 * compute failed (the surface degrades to an "unavailable" state, never throws / never
	 * renders a wrong number). A genuine $0 position returns `0`, not `null`.
	 */
	netWorth: number | null;
	/**
	 * Whether the caller owns any account OPEN AS OF the same `asOf` the NAV was computed at —
	 * THREE-VALUED, and deliberately not a boolean.
	 *
	 *   'some'    — the count read succeeded and found at least one open account
	 *   'none'    — the count read succeeded and found zero
	 *   'unknown' — THE COUNT READ FAILED. We did not measure it. This is NOT 'none'.
	 *
	 * ⚠ THE THIRD MEMBER EXISTS BECAUSE `false` WAS A LIE. This was `hasAccounts: boolean`, and a
	 *   failed count degraded to `false` — so any read error rendered "connect your first account"
	 *   to a user with a real net worth. That was FAIL-SOFT, and it was a deliberate prior
	 *   decision, not an oversight (see netWorth.test.ts for the superseded contract). What it got
	 *   wrong is the thing worth carrying: fail-soft is safe when the degraded value is INERT.
	 *   `false` here is not inert — it drives a screen that TELLS THE USER THEY OWN NOTHING.
	 *   Degrading to a claim is not degrading gracefully.
	 *
	 * ⚠ THIS DELIBERATELY DIVERGES FROM `/accounts`, WHICH RETURNS `{ accounts: [], error: true }`.
	 *   Stated here rather than left to be discovered, because a future reader will otherwise
	 *   either "harmonise" them back or wonder which is house style. The two are NOT the same
	 *   situation, and the difference is what the payload MEANS on the error path:
	 *     `/accounts` degrades to an EMPTY ARRAY — a container that happens to be empty. It is
	 *       INERT: the page checks `error` first and never reads it. Nothing is asserted.
	 *     this surface degraded to `false` — which is a CLAIM, and the specific wrong one. The
	 *       boolean form has a falsy value for "unknown" to collapse into, and THAT COLLAPSE IS
	 *       THE DEFECT.
	 *   So the precedent's shape is safe because its payload is inert, not because the shape is
	 *   inherently safe; copying the silhouette here would inherit the look and not the safety.
	 *   (fe-adr042's framing.) Whether `/accounts` should eventually move to a union too is a
	 *   real question and deliberately NOT decided here — it has no defect to justify the churn.
	 *
	 * ⚠ AND IT IS A STRING UNION, NOT `boolean | null`, BY CONSTRUCTION. Under `boolean | null`
	 *   every existing `!hasAccounts` call site keeps compiling and keeps being wrong, because
	 *   `!null` is `true` — the unknown state collapses into exactly the branch it must not take.
	 *   Removing the boolean makes the old reading a COMPILE ERROR rather than a runtime surprise.
	 *   Same principle as 059's `closed_at is null` trap: a wrong form that is indistinguishable
	 *   from the right one under today's data will be chosen, and will not announce itself.
	 *
	 * ⚠ THIS FIELD REPORTS WHAT THE COUNT READ SAID. IT IS NEVER INFERRED FROM `netWorth`.
	 *   The inference is available and SOUND — a non-zero NAV entails at least one open account: NAV
	 *   is a sum over fn_nav_composition's leaf set, which is a SUBSET of open accounts at the same
	 *   asOf (open accounts minus any tax-authority-designated ledgers, 102/E-2), so an empty
	 *   open-account population forces an empty leaf set and NAV = 0 — and consumers SHOULD use it
	 *   (see the precedence note below). But it is not applied here, deliberately. Deriving 'some'
	 *   from a non-zero NAV would make this field depend on an invariant living in ANOTHER function:
	 *   if fn_nav_composition's scope ever stopped being a subset of this count's population, the
	 *   field would silently report a presence nobody measured, and nothing would catch it. A field
	 *   that says "the read failed" is never wrong; a field that says "I deduced it from something
	 *   else" is wrong the moment the something else moves. Keep the measurement and the inference
	 *   in different places.
	 *
	 * ⚠ AN OBLIGATION THIS FIELD CREATES AND CANNOT EXPRESS (fe-adr042, building the consumer).
	 *   The third state tempts a consumer into a FOURTH TOP-LEVEL BRANCH — "render something else
	 *   when presence is unknown". Do not. On this surface the NAV hero carries the ADR-013 INV-1
	 *   StaleConstituentBadge, so a sibling branch that re-renders the hero produces A NAV RENDER
	 *   PATH WITH NO STALENESS BADGE ON IT — a silent-staleness V1-ship-block defect, introduced
	 *   by the SHAPE of a fix for something unrelated. The third state belongs NESTED INSIDE the
	 *   number surface, where the badge is present by construction rather than by remembering.
	 *   Recorded here because the obligation is invisible from this type: nothing in
	 *   `'some' | 'none' | 'unknown'` hints that adding a branch can drop a badge, and the next
	 *   consumer to widen this will be reading the type, not the dashboard.
	 *
	 * PRECEDENCE FOR CONSUMERS (the rule, not a rendering): this field is only LOAD-BEARING when
	 * `netWorth === 0`, which is the sole cell where the NAV cannot distinguish "no accounts" from
	 * "a real $0 position". When `netWorth` is non-zero the NAV is itself proof that accounts
	 * exist and OUTRANKS this field, including when it is 'unknown'. When `netWorth === null` the
	 * compute failed and this field is moot. Check the NAV first; a consumer that branches on
	 * presence BEFORE the number lets a failed count override evidence that outranks it — which is
	 * precisely how the original defect rendered onboarding over a perfectly good number.
	 * (Finding: fe-adr042.)
	 *
	 * "As of the SAME asOf" is the load-bearing half of the measurement: this count and the NAV are
	 * two reads that must describe one population. Scoping them differently makes the disambiguator
	 * disagree with the thing it disambiguates — and it is also what would break the entailment
	 * above, which is the second reason the two dates must not drift apart.
	 */
	accountPresence: 'some' | 'none' | 'unknown';
};

/**
 * The day AFTER an ISO date, as an ISO date — the upper half of the half-open closure bound.
 *
 * Exists because PostgREST cannot express `closed_at::date > p_as_of` and the equivalent it CAN
 * express is `closed_at >= (p_as_of + 1 day)`. UTC arithmetic, so month / year / leap boundaries
 * come from Date rather than from string surgery: '2026-02-28' -> '2026-03-01',
 * '2028-02-28' -> '2028-02-29', '2026-12-31' -> '2027-01-01'.
 */
function nextDayIso(iso: string): string {
	const d = new Date(`${iso}T00:00:00Z`);
	d.setUTCDate(d.getUTCDate() + 1);
	return d.toISOString().slice(0, 10);
}

/**
 * Load the §2.1.1 headline view for the caller, RLS-scoped via the per-request anon client.
 * Two independent reads (both fail soft, logged): the composed NAV read + an open-account count,
 * BOTH scoped to the same `asOf`. `asOf` is an ISO date string (YYYY-MM-DD) — the LOCF valuation
 * date passed to `fn_nav_composition`.
 *
 * `precomputedComposition` (SELF-268 / R3 rider 0) — an already-fetched `RawNavComposition` from
 * THIS SAME request, typically the value a caller ALSO threads into `loadNavComposition` for the
 * §2.1.5 foot (see navComposition.ts's `fetchNavComposition`). Passing it means this call makes
 * ZERO additional `fn_nav_composition` RPC round-trips — the headline and the foot then read the
 * literal same fetched value, not two calls to the same definition. Omit it (the default,
 * `undefined`) to have this function fetch for itself — the correct choice for a caller that only
 * needs `accountPresence` and never renders `netWorth` (e.g. `allocation/+page.server.ts`), which
 * is a separate request context, not a second call within one page load.
 */
export async function loadNetWorthView(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf,
	precomputedComposition?: RawNavComposition | null
): Promise<NetWorthView> {
	// ── NAV read (composed value; INVOKER; RLS-scoped to auth.uid()) ──────────────
	// R3 rider 0: the headline reads pfin.fn_nav_composition(asOf)'s `nav` key — the SAME composed
	// value the §2.1.5 foot reads — via navComposition.ts's `fetchNavComposition`, NOT a direct
	// `fn_compute_nav` RPC (see this module's header for why the flip, and why it is a one-way
	// door). `fetchNavComposition` itself fails soft to `null` (logged at its own call site); `null`
	// here means "the composed read failed / is unavailable", not a genuine zero.
	const composition =
		precomputedComposition !== undefined
			? precomputedComposition
			: await fetchNavComposition(supabase, asOf);

	let netWorth: number | null = null;
	if (composition !== null) {
		// `nav` arrives as a JSON number inside the jsonb payload (unlike the old scalar-RPC path,
		// jsonb_build_object never stringifies a numeric operand) — coerced defensively anyway, same
		// discipline as every other numeric read in this module. A NaN coercion (should never
		// happen) degrades to null, not a poisoned render.
		const n = Number(composition.nav);
		netWorth = Number.isFinite(n) ? n : null;
	}

	// ── open-account presence (empty-state disambiguator) ─────────────────────────
	// head:true + count:'exact' → no rows shipped, just the RLS-scoped count.
	//
	// THE PREDICATE MIRRORS 049's (fn_account_unrealized_gl, which fn_nav_composition composes on),
	// WHICH IS DATE-GRANULAR (059 / ADR-042):
	//   SQL:       (acc.closed_at is null or acc.closed_at::date > p_as_of)
	//   PostgREST: closed_at.is.null,closed_at.gte.<asOf + 1 day>
	//
	// ⚠ THE `::date` CAST IS THE WHOLE PREDICATE, AND PostgREST CANNOT EXPRESS A CAST — which is
	//   why this is a half-open bound on the NEXT DAY rather than the obvious `.gt.<asOf>`.
	//   `closed_at` is timestamptz and `asOf` is a date, so `.gt.<asOf>` promotes to MIDNIGHT and
	//   an account closed at 14:00 on asOf counts as still OPEN. 059 measures that exact table:
	//     closure at 00:00 → excluded either way; at 14:00 or 23:59 → `::date >` EXCLUDES,
	//     bare `>` INCLUDES.
	//   And it is the UNIVERSAL case, not an edge: fn_close_account defaults p_closed_at to
	//   now(), so EVERY app-closed account carries a non-midnight time.
	//
	//   `closed_at >= (asOf + 1 day)` is the rewrite 059 explicitly rules "behaviourally
	//   EQUIVALENT and therefore safe" — its ⚠ DO NOT OPTIMIZE THE CAST AWAY warns against the
	//   TEMPTING NEARBY form (simply dropping the cast), which is the regression above. This is
	//   the safe one, and it is the only one PostgREST can say.
	//   Timezone is not a hazard here: `closed_at::date` resolves in the session TimeZone and the
	//   bound literal is parsed in the SAME session, so the equivalence holds under any zone —
	//   what would break it is the two sides resolving in different sessions, which they cannot.
	//
	// THIS COUNT IS A VALUATION SURFACE, not a render one (api/CLAUDE.md): it is paired with a NAV
	// read, so it takes the as-of form at the SAME asOf the NAV used. Do not re-derive that date
	// from a clock here — two reads that must describe one population must not read two different
	// dates, and post-059 they must also not read two different GRANULARITIES.
	const { count, error: countErr } = await supabase
		.schema('pfin')
		.from('account')
		.select('account_id', { count: 'exact', head: true })
		.or(`closed_at.is.null,closed_at.gte.${nextDayIso(asOf)}`);
	if (countErr) {
		console.error('[netWorth] open-account count failed:', countErr.message);
	}
	// THREE STATES, and the error case is resolved FIRST so it can never be reached by the
	// count-comparison path. `count` is null on a failed read, so a single expression ordered the
	// other way (`(count ?? 0) > 0`) silently maps failure onto 'none' — which is the original
	// defect written more compactly. The branch is separate on purpose.
	const accountPresence: NetWorthView['accountPresence'] = countErr
		? 'unknown'
		: (count ?? 0) > 0
			? 'some'
			: 'none';

	// ⚠ 'none' WITH A NON-ZERO NAV SHOULD BE IMPOSSIBLE, and nothing else would ever report it.
	// fn_nav_composition(asOf)'s leaf set is a SUBSET of this count's population (open accounts at
	// asOf, minus any tax-authority-designated ledgers — 102/E-2) — a non-empty composed NAV still
	// implies a non-empty open-account count, since an empty count forces an empty subset. The
	// combination becomes reachable only if an account closes BETWEEN the two reads — or if the
	// count's predicate drifts apart from 049's own open-as-of predicate (which fn_nav_composition
	// composes on), which is the failure the asOf synchronization above exists to prevent and the
	// ONLY symptom it would ever produce. The UI cannot surface it (it renders the number either
	// way, correctly), so without this line the drift is invisible everywhere. (fe-adr042's catch.)
	// Logged WITHOUT the amount: netWorth is a real account balance and operator logs are not a
	// scoped destination for financial values (Sec #318 F8). The FACT is the diagnostic here; the
	// figure adds nothing an operator could act on differently.
	if (accountPresence === 'none' && netWorth !== null && netWorth !== 0) {
		console.error(
			'[netWorth] INVARIANT: non-zero NAV with a zero open-account count — the two reads ' +
				'disagree about one population. Check that the count predicate still matches ' +
				'fn_nav_composition\'s open-as-of subset (same asOf, same ::date granularity).'
		);
	}

	return { netWorth, accountPresence };
}
