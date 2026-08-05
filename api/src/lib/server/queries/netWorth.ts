// netWorth.ts — server-side read for the §2.1.1 headline Net Worth surface (SELF-211).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// The §2.1.1 read is a SINGLE trustworthy number: pfin.fn_compute_nav, the Architect-authored
// SECURITY INVOKER uniform-valuation helper landed at migration 019 (SELF-277). INVOKER means
// the caller's RLS context propagates — we call it through the per-request anon client
// (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11). fn_compute_nav takes NO
// users_id/scope param (tenancy is auth.uid()); the Wave-1 issue's fn_nav(users_id, scope[])
// contract predates the substrate and is superseded (SELF-210 reconciled to a verification
// note — the substrate absorbed the aggregation).
//
// OPEN-AS-OF SCOPE (SELF-322 / ADR-039, migration 050; re-pointed at 059 per ADR-042): the
// headline calls the 2-arg fn_compute_nav(p_as_of, p_active_only => true) so the NAV counts only
// accounts OPEN AS OF p_as_of, and reconciles EXACTLY with the §2.1.5 composition (049). The
// 019/1-arg wrapper (all accounts, including closed) is reserved for the book/GL memo (037) +
// historical trend — NOT the headline.
//
// ⛔ THE ADR-039 N3 TEMPORAL FENCE THAT STOOD HERE IS STRUCK, NOT RELAXED — and it is called out
//    rather than deleted, because the deletion is the part nobody can review. It read:
//    "p_active_only => true is sound ONLY at p_as_of = current_date … a future §2.1.2 trajectory /
//    historical NAV must NOT reuse this active-only path with a past date."
//    That was TRUE of is_active and is FALSE of closed_at. It rested entirely on the filter being
//    a CURRENT-STATE boolean, so filtering it into a past as_of rewrote history. 059's predicate
//    is `closed_at is null or closed_at > p_as_of` — temporal — and 059's own catalog comment
//    states the strike verbatim: the path is now sound at ANY p_as_of. Left standing, this comment
//    would forbid exactly the path 059 made correct, and A FALSE PROHIBITION LEAVES NO ARTIFACT:
//    nobody tests the path they were told not to take, so nothing ever fails to reveal it.
//    A §2.1.2 trajectory MAY now call this path with a past date. (Whether it SHOULD, versus
//    reading frozen nav_daily checkpoints, is a cost/consistency question — not a soundness one.)
//
// The composition breakdown (GAV / Debt / tax lines) is §2.1.5 = V1.1 (SELF-225); V1.0
// renders the single number only, per PRD §2.1.1 verbatim + F/CTO Option A.

import type { SupabaseClient } from '@supabase/supabase-js';

export type NetWorthView = {
	/**
	 * USD net worth as of the requested date, from pfin.fn_compute_nav. `null` iff the
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
	 *   The inference is available and SOUND — a non-zero NAV entails at least one open account,
	 *   since fn_compute_nav sums over the same population at the same asOf, so an empty set
	 *   yields exactly 0 — and consumers SHOULD use it (see the precedence note below). But it is
	 *   not applied here, deliberately. Deriving 'some' from a non-zero NAV would make this field
	 *   depend on an invariant living in ANOTHER function: if fn_compute_nav's scope ever stopped
	 *   matching this count's population, the field would silently report a presence nobody
	 *   measured, and nothing would catch it. A field that says "the read failed" is never wrong;
	 *   a field that says "I deduced it from something else" is wrong the moment the something
	 *   else moves. Keep the measurement and the inference in different places.
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
 * Two independent reads (both fail soft, logged): the NAV compute + an open-account count, BOTH
 * scoped to the same `asOf`. `asOf` is an ISO date string (YYYY-MM-DD) — the LOCF valuation date
 * passed to fn_compute_nav.
 */
export async function loadNetWorthView(
	supabase: SupabaseClient,
	asOf: string
): Promise<NetWorthView> {
	// ── NAV compute (INVOKER; RLS-scoped to auth.uid()) ───────────────────────────
	// fn_compute_nav(p_as_of date, p_active_only boolean) RETURNS numeric. p_active_only:true =
	// the headline scope — accounts OPEN AS OF p_as_of (SELF-322 / ADR-039, re-pointed at 059).
	// ⚠ p_active_only is a PROVABLE NO-OP ON VALUE post-059 (a closed account holds zero at and
	// after closure by the 058 gate + transfer-in fence), so `true` and `false` return the same
	// number for every date. It is passed explicitly ANYWAY, and NOT because the value differs:
	// TRUE and FALSE remain different QUESTIONS ("open as of d" vs "all accounts, closed
	// included"), and 059's comment enumerates four fences in other files whose weakening
	// restores a real divergence this argument would then be selecting between. Dropping it
	// because "it makes no difference today" discards the only record of which question we asked.
	// supabase-js returns a scalar RPC as the raw value; a Postgres numeric may arrive as number
	// OR string → coerce. A NaN coercion (should never happen — the DB NaN-fences price) degrades
	// to null, not a poisoned render.
	let netWorth: number | null = null;
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_compute_nav', { p_as_of: asOf, p_active_only: true });
	if (error) {
		console.error('[netWorth] fn_compute_nav failed:', error.message);
	} else {
		const n = data === null || data === undefined ? 0 : Number(data);
		netWorth = Number.isFinite(n) ? n : null;
	}

	// ── open-account presence (empty-state disambiguator) ─────────────────────────
	// head:true + count:'exact' → no rows shipped, just the RLS-scoped count.
	//
	// THE PREDICATE MIRRORS fn_compute_nav's, WHICH IS DATE-GRANULAR (059 / ADR-042):
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
	// fn_compute_nav(asOf, true) and this count describe the SAME population at the SAME date, so
	// a non-empty position implies a non-empty count. The combination becomes reachable only if an
	// account closes BETWEEN the two reads — or if the two predicates drift apart, which is the
	// failure the asOf-and-granularity synchronization above exists to prevent and the ONLY
	// symptom it would ever produce. The UI cannot surface it (it renders the number either way,
	// correctly), so without this line the drift is invisible everywhere. (fe-adr042's catch.)
	// Logged WITHOUT the amount: netWorth is a real account balance and operator logs are not a
	// scoped destination for financial values (Sec #318 F8). The FACT is the diagnostic here; the
	// figure adds nothing an operator could act on differently.
	if (accountPresence === 'none' && netWorth !== null && netWorth !== 0) {
		console.error(
			'[netWorth] INVARIANT: non-zero NAV with a zero open-account count — the two reads ' +
				'disagree about one population. Check that the count predicate still matches ' +
				'fn_compute_nav (same asOf, same ::date granularity).'
		);
	}

	return { netWorth, accountPresence };
}
