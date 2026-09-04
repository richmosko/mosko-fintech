// navComposition.ts — server-side read for the §2.1.5 NAV-composition table (V1.1; SELF-226).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's `051` pfin.fn_nav_composition(p_as_of date default current_date) — a
// SECURITY INVOKER read-composition helper (Lock 11; prosecdef=f) — through the per-request
// anon/authenticated client so the caller's RLS context propagates (users_id = auth.uid()),
// NEVER service_role (RT-26 / Lock 11). 051 composes on `049` (fn_account_unrealized_gl, itself
// INVOKER) + a direct-owner read of pfin.account, so owner-isolation is INHERITED at the DB: a
// cross-tenant caller sees no leaf rows → empty groups / nav 0 (fails closed).
//
// fn_nav_composition RETURNS jsonb (a SCALAR jsonb, NOT set-returning) — supabase-js hands the
// parsed object straight back (contrast staleness.ts, whose RPC is set-returning → array[0]).
//
// ⚠ THE `nav` KEY HERE IS NOW THE §2.1.1 HEADLINE'S OWN READ SOURCE (SELF-268 / ADR-067 Decision
//   3 / R3 rider 0 — "one composed value, one reader; no surface composes its own"). netWorth.ts
//   no longer calls `fn_compute_nav` for the headline; it reads THIS function's `nav`, via
//   `fetchNavComposition` below. This function's return NO LONGER foots to
//   `fn_compute_nav(p_as_of, true)` — that identity was DELIBERATELY BROKEN at `102` (the E-2
//   tax-authority-ledger exclusion lands in `051`'s leaf set only; `fn_compute_nav` is untouched
//   and keeps its gross, pre-exclusion definition) and MUST NOT be "restored" by a future edit —
//   see `102`'s own `comment on function` for the identical warning at the DB layer. We still pass
//   the SAME asOf the §2.1.1 headline passes (see call site; R3 rider 4) so both surfaces describe
//   the same day, but "same day" is no longer "same value via two definitions" — it is now the
//   SAME single value, period. `fn_compute_nav` is retained ONLY for `nav_daily` writes (the
//   permanently-gross checkpoint series) and is read by no live surface.
//
// Fail-soft is load-bearing (mirrors netWorth.ts / staleness.ts): any error degrades to `null`
// (logged server-side, never thrown). `null` = "composition unavailable" (the table simply
// doesn't render) — it must NEVER take down the §2.1.1 headline NAV. A genuine zero-account
// tenant still gets a well-formed tree ({ groups: [], buildups: {…0…}, nav: 0 }), not null.
// ⚠ Because the headline now depends on THIS SAME read, a `null` composition also degrades the
// headline to `null` (netWorth.ts's own "compute failed" state) — see that module's header.
//
// PER-ROW STALENESS (SELF-229 · per ADR-013 D1, staleness-marking surface scope is illustrative,
// not exhaustive — further surfaces ramp later; Sec F4 (AMBER round): read D1 live, this is a
// paraphrase not a quote). `051` carries
// NO staleness of its own — `fn_nav_composition` leaf rows key on `account_id` only, while `046`
// `fn_aggregation_has_stale_constituent()`'s stale_items[] key on `linked_source_id`. NO migration:
// per nav-composition.ts's own deferral note (ratified D4) this needs "a Backend contract
// extension + a linked_source_id↔account_id join" — realized here as a SERVER-SIDE join, NOT a
// change to 051 or a new DB function (a schema/function change would pull in Architect + Sec for
// a join `pfin.account.linked_source_id` already makes possible with zero new DDL). Stays
// SECURITY INVOKER throughout: the extra read is a plain RLS-scoped select on `pfin.account`
// through the SAME per-request client as the 051 RPC — `account_select`'s owner + aal2 policy
// applies unchanged, never service_role.
//
// ⚠ is_stale IS TRI-STATE (`boolean | null`), NOT a plain boolean. Two INDEPENDENT causes can
// produce the UNKNOWN (`null`) value, and BOTH degrade every leaf together — never a mix of
// `null` and `false` from the same call:
//   (1) THE CALLER'S ROOT STALENESS READ WAS ITSELF UNKNOWN (SELF-229 second REWORK, F/CTO-ruled
//       2026-08-14, after staleness.ts's own `046` degrade was fixed from EMPTY_STALENESS to
//       UNKNOWN_STALENESS on failure). `staleLinkedSourceIds` is `null` in this case — the caller
//       (+page.server.ts) passes `null` rather than an empty Set when `staleness.is_stale ===
//       null`, and this function skips the join ENTIRELY: there is nothing meaningful to look up
//       against if we don't even know whether anything is stale tenant-wide.
//   (2) THE JOIN QUERY ITSELF FAILED (the original SELF-229 rework, team-lead-caught) — the root
//       staleness read succeeded (a real, possibly-empty set of stale linked_source_ids), but the
//       pfin.account lookup that maps those to account_ids errored.
// Both are the EXACT shape SELF-220 Sec round 2 rejected on the chart: a staleness marker
// suppressed on a read failure, so the user sees fresh-looking data precisely when the system can
// least vouch for it. `null` = "could not determine" is a DISTINCT value from `false` = "confirmed
// not stale" (a successful read that checked and found this leaf healthy).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';

/** One per-account leaf row inside a category group (straight from 051 → 049, naturally signed). */
export type NavCompositionAccount = {
	/** pfin.account.account_id — bigint, arrives as a JSON number in the jsonb projection. */
	account_id: number;
	account_name: string;
	/** 049 current_market_value; liability leaves are naturally negative (051 DEBT-SIGN D-1). */
	current_market_value: number;
	/** 049 unrealized G/L; NULL for non-investment accounts (051 AC#3). */
	unrealized_gl: number | null;
	/**
	 * SELF-229: TRI-STATE, not a plain boolean — see the module header's REWORK notes (two
	 * independent causes of `null`).
	 *   true  = this leaf's `pfin.account.linked_source_id` IS in the caller's `046` stale_items[].
	 *   false = the join succeeded (against a KNOWN root staleness read) and it is CONFIRMED not
	 *           in that set (or the account is manual/unlinked — `linked_source_id IS NULL` never
	 *           has anything to go stale).
	 *   null  = UNKNOWN — either the root `046` staleness read itself failed, or the per-row join
	 *           against `pfin.account` failed. NEVER collapsed to `false`. Render this as an
	 *           explicit "staleness unknown" state, not as "not stale" (Frontend's call on the
	 *           visual).
	 */
	is_stale: boolean | null;
};

/** One category group — canonical order, empty categories omitted (051 A4). */
export type NavCompositionGroup = {
	/** pfin.account.account_type discriminator (depository/investment/…/real_estate/liability). */
	category: string;
	accounts: NavCompositionAccount[];
	/** Σ current_market_value in-category (natural sign; liability subtotal is negative). */
	subtotal: number;
};

/**
 * One `nav_components` tax-liability scalar's availability (SELF-268 / ADR-067 Decision 3;
 * execution-log E41/E42 addendum, Q2 option (2)). Carried VERBATIM off `pfin.fn_compute_tax_liability`
 * (`104`)'s own `nav_components.{realized_tax_liab,unrealized_tax_liab}` envelope shape into `051`'s
 * (as amended at migration 105) `buildups.{realized_tax_liab,unrealized_tax_liab}` keys — NOT a
 * separate `tax_components` side-channel, and NOT a plain `number` with an availability flag beside
 * it (that shape was this repo's own FIRST DRAFT of this contract and was superseded by the ruling
 * before it landed on any branch's migration).
 *
 * ⚠ A DISCRIMINATED UNION, DELIBERATELY, NOT `{status, amount?, reason?}` (Sec P-18) — the SHIPPED
 *   precedent is `tax-quarterly.ts`'s `FundsDueEnvelope` (SELF-264/266, landed `7c81dda`); this type
 *   follows it key-for-key rather than inventing a second spelling of "envelope." A
 *   required-`status`-field-with-optional-siblings shape lets `amount` be read while `status ===
 *   'unavailable'` and silently be `undefined` — `env.amount` type-checks and IS `undefined` at
 *   runtime, a `NaN` waiting to happen the moment a consumer does arithmetic on it. Under this
 *   union, `amount` and `reason` are each UNREACHABLE without narrowing on `status` first — reading
 *   `env.amount` without narrowing is a COMPILE ERROR, so `usd.format(env)` (passing the whole
 *   envelope to a number formatter, the exact regression this exists to make impossible) is also a
 *   compile error rather than a silently-rendered `$NaN` or `$0`.
 *
 * `nav` (on `NavComposition` below) is ALREADY net of `coalesce((env->>'amount')::numeric, 0)` for
 * BOTH scalars, computed ONCE inside `051`'s own SQL (P-17) — this type is a DISPLAY/AVAILABILITY
 * signal only; no server-side code in this module (or netWorth.ts) does arithmetic on `.amount`, and
 * none should — `nav` already carries the arithmetic effect of an `unavailable` scalar (subtract 0).
 *
 * ⚠ COORDINATION NOTE, not yet resolved (Sec P-18 / team-lead 2026-09-04): `api/src/lib/nav-
 *   composition.ts` (Frontend-owned) is the canonical home for this type per P-18's instruction —
 *   "export it from nav-composition.ts and import it server-side," so the two modules declare it
 *   once. Frontend's `c6c62c5` landed a DIFFERENT, now-superseded shape (`TaxComponentStatus =
 *   {status:'computed'} | {status:'unavailable',reason}` behind a separate optional
 *   `tax_components` block, with `buildups.*_tax_liab` staying `number`) — that predates the E41/Q2
 *   ruling this type implements. Defined LOCALLY here for now (rather than importing Frontend's
 *   current, pre-ruling shape, which would encode the wrong contract) so this module's own type
 *   change is not blocked on Frontend's rework landing first. TODO once Frontend updates
 *   `nav-composition.ts` to the ruled shape: delete this local definition and import theirs instead,
 *   per P-18 — do not let both definitions stand once that lands.
 */
export type TaxLiabilityEnvelope =
	| { status: 'unavailable'; reason: string }
	| { status: 'computed'; amount: number };

/** Buildup subtotals over the FULL active-account set (051 A3). ⚠ NO LONGER foots to
 * `fn_compute_nav` — see the module header (identity deliberately broken at `102`, E-2). */
export type NavCompositionBuildups = {
	total_non_re: number;
	gross_total: number;
	/** −(liability subtotal) = a positive magnitude, so nav = gross_total − debt reads literally. */
	debt: number;
	/** `104`'s `nav_components.realized_tax_liab` envelope, carried verbatim (SELF-268 / E41-E42). */
	realized_tax_liab: TaxLiabilityEnvelope;
	/** `104`'s `nav_components.unrealized_tax_liab` envelope, carried verbatim (SELF-268 / E41-E42). */
	unrealized_tax_liab: TaxLiabilityEnvelope;
};

/** The full §2.1.5 composition tree — the raw shape of the 051 jsonb return. */
export type NavComposition = {
	groups: NavCompositionGroup[];
	buildups: NavCompositionBuildups;
	nav: number;
};

/**
 * The DIRECT `fn_nav_composition` jsonb return — before this module's own per-row `is_stale` join
 * is attached. `051` emits no `is_stale` key at all (staleness is a server-side enrichment, not a
 * DB column on the leaf; see the module header), so a value fresh off the RPC structurally cannot
 * satisfy `NavCompositionAccount` (which requires it). Kept as a DISTINCT type rather than an
 * `Omit<..., 'is_stale'>` cast-of-convenience at each call site, so a caller reading `.is_stale` on
 * a raw value is a compile error, not a `undefined` surprise at runtime.
 */
export type RawNavCompositionAccount = Omit<NavCompositionAccount, 'is_stale'>;
export type RawNavCompositionGroup = Omit<NavCompositionGroup, 'accounts'> & {
	accounts: RawNavCompositionAccount[];
};
export type RawNavComposition = Omit<NavComposition, 'groups'> & {
	groups: RawNavCompositionGroup[];
};

/**
 * Fetch the caller's §2.1.5 composition tree DIRECTLY off `pfin.fn_nav_composition`, RLS-scoped
 * via the per-request anon client — no per-row staleness join. Fail-soft: any error (RPC failure,
 * unexpected null payload) degrades to `null`, logged, never thrown.
 *
 * ⚠ THE SINGLE RPC CALL SITE (SELF-268 / R3 rider 0). `pfin.fn_nav_composition`'s `nav` key is now
 * the ONE composed value the §2.1.1 headline and the §2.1.5 foot both read (netWorth.ts / R3 rider
 * 0 — the §2.1.1 headline no longer calls `fn_compute_nav`, which is retained ONLY for `nav_daily`
 * writes and reads by no live surface). Both surfaces reading this same underlying value must NOT
 * mean two RPC round-trips for one page load: a caller serving BOTH surfaces (root
 * `+page.server.ts`) calls this ONCE and threads the SAME `RawNavComposition` into both
 * `loadNetWorthView` and `loadNavComposition` below (their `precomputed` parameter). A caller
 * needing only one surface (e.g. `allocation/+page.server.ts`'s `accountPresence`-only use of
 * `loadNetWorthView`) may omit `precomputed` and let that function fetch for itself — that is a
 * SEPARATE request context, not a second call within one.
 */
export async function fetchNavComposition(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<RawNavComposition | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_nav_composition', { p_as_of: asOf });

	if (error) {
		console.error('[navComposition] fn_nav_composition failed:', error.message);
		return null;
	}

	// Scalar jsonb RPC → the parsed object directly. A null/undefined payload is not an expected
	// state (the fn always returns a well-formed tree) — degrade rather than assert a shape.
	if (data === null || data === undefined) {
		console.error('[navComposition] fn returned no jsonb payload; degrading to null');
		return null;
	}

	return data as RawNavComposition;
}

/**
 * Load the caller's §2.1.5 NAV-composition tree, RLS-scoped via the per-request anon client.
 * `asOf` is an ISO date string (YYYY-MM-DD) — passed explicitly (not left to the fn default) so
 * the composition foots to the §2.1.1 headline's composed NAV by construction (R3 rider 0: both
 * now read the SAME `fn_nav_composition(asOf)` value).
 * Fail-soft: any error (read failure, unexpected null) degrades to `null` — logged, never thrown.
 *
 * `staleLinkedSourceIds` (SELF-229) — the CALLER's already-loaded `046` stale_items[], as a set of
 * `linked_source_id` strings (mirrors the SELF-199 bigint→string convention `staleness.ts` already
 * applies). THREE distinct inputs, all meaningful:
 *   `EMPTY_STALE_LINKED_SOURCE_IDS` (or any empty, non-null Set) — a KNOWN root read: nothing is
 *     stale tenant-wide. The join is skipped (nothing to look up), every leaf becomes `false`.
 *   a non-empty Set — a KNOWN root read with real stale sources. The join runs.
 *   `null` — the caller's OWN `046` read was itself UNKNOWN (staleness.is_stale === null). The
 *     join is skipped (there is nothing meaningful to check against), every leaf becomes `null`.
 *
 * `precomputed` (SELF-268 / R3 rider 0) — an ALREADY-FETCHED `RawNavComposition`, typically the
 * SAME value `loadNetWorthView` derived `netWorth` from on this same request. Pass it to avoid a
 * second `fn_nav_composition` RPC round-trip for one page load. `undefined` (the default) means
 * "fetch it yourself" — this function still works standalone. An explicit `null` means the caller
 * already tried and the RPC failed; this function returns `null` in turn rather than retrying.
 */
export async function loadNavComposition(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf,
	staleLinkedSourceIds: ReadonlySet<string> | null,
	precomputed?: RawNavComposition | null
): Promise<NavComposition | null> {
	const composition = precomputed !== undefined ? precomputed : await fetchNavComposition(supabase, asOf);

	// `fetchNavComposition` (or the caller's own precomputed attempt) already logged the specific
	// failure — RPC error vs. null payload — at its own call site; nothing further to log here.
	if (composition === null) {
		return null;
	}

	// staleLinkedSourceIds === null means the CALLER's own root staleness read was unknown — skip
	// the join entirely (there's nothing meaningful to check against) and propagate UNKNOWN
	// straight through. Otherwise resolve the join normally (it may itself still fail — see
	// resolveStaleAccountIds).
	const staleAccountIds =
		staleLinkedSourceIds === null
			? null
			: await resolveStaleAccountIds(supabase, staleLinkedSourceIds);

	// Attach is_stale per leaf. A brand-new object tree, not a mutation of `composition` in place —
	// `051`'s own return is treated as read-only, same discipline as the rest of this loader.
	// `staleAccountIds` is `null` when EITHER cause in the module header applies — every leaf gets
	// `null` together in that case, never `false`.
	return {
		...composition,
		groups: composition.groups.map((group) => ({
			...group,
			accounts: group.accounts.map((account) => ({
				...account,
				is_stale: staleAccountIds === null ? null : staleAccountIds.has(String(account.account_id))
			}))
		}))
	};
}

/**
 * SELF-229 per-row join: which of the caller's OWN `pfin.account` rows are fed by a currently-
 * stale `linked_source_id`. Plain RLS-scoped select through the SAME per-request client the 051
 * RPC uses above — `account_select`'s owner + aal2 policy applies unchanged (SECURITY INVOKER
 * throughout this module; no service_role, no new DB object). Returns account_id as STRING
 * (SELF-199 bigint convention, mirroring staleness.ts's toItem()) so callers never compare a
 * bigint-as-number against a bigint-as-string and silently miss on precision.
 *
 * Skips the query entirely when there's nothing stale to look up — the common (healthy) case
 * costs zero extra round-trips (returns an EMPTY set, a KNOWN "nothing is stale", not `null`).
 * Only called when the caller's root staleness read was itself KNOWN (see loadNavComposition) —
 * the null-root case never reaches this function at all.
 *
 * Return value is TRI-STATE, mirroring is_stale above:
 *   Set<string> (possibly empty) = the join is KNOWN — every leaf's is_stale can be asserted true
 *                                   or false with confidence.
 *   null                         = the join FAILED — every leaf's is_stale must become `null`
 *                                   (UNKNOWN), never `false`. This is the SELF-220-precedent fix:
 *                                   a metadata-enrichment failure must not silently read as "this
 *                                   account is confirmed healthy" when it was never checked.
 * The rollup `data.staleness` badge (loaded independently, upstream of this call) remains the
 * surface of record that SOMETHING is stale even when this per-row detail is unknown — but
 * "something, we just don't know which row" is what must reach the render, not silence.
 *
 * EXPORTED (SELF-330): this is now THE bridge from a resolved `046` stale-`linked_source_id` set
 * to `pfin.account.account_id`s — nonReAllocation.ts's per-Sub-Cat staleness fold (§2.2.2's row
 * tint) reuses this function VERBATIM rather than re-deriving the same join a second time. Do not
 * fork this logic — a second copy is exactly the drift risk the SELF-239/nonre-allocation.ts
 * hand-copy note already flags for the row/group shape; the join itself must stay singular.
 */
export async function resolveStaleAccountIds(
	supabase: SupabaseClient,
	staleLinkedSourceIds: ReadonlySet<string>
): Promise<ReadonlySet<string> | null> {
	if (staleLinkedSourceIds.size === 0) return EMPTY_STALE_ACCOUNT_IDS;

	const { data, error } = await supabase
		.schema('pfin')
		.from('account')
		.select('account_id, linked_source_id')
		.in('linked_source_id', Array.from(staleLinkedSourceIds));

	if (error) {
		console.error(
			'[navComposition] stale-account join failed; every leaf degrades to is_stale=null ' +
				'(UNKNOWN) — NEVER false, per the SELF-220 silent-fresh-on-failure precedent:',
			error.message
		);
		return null;
	}

	return new Set((data ?? []).map((row) => String(row.account_id)));
}

/** Shared zero-value — avoids allocating a fresh empty Set at every no-op call site. */
export const EMPTY_STALE_LINKED_SOURCE_IDS: ReadonlySet<string> = new Set();
const EMPTY_STALE_ACCOUNT_IDS: ReadonlySet<string> = new Set();
