// asOf.ts — the branded as-of date, and the only place one can be minted.
// Backend-owned server source (ARCH §4.1 allowlist). Server-only BY PLACEMENT, not by
// convention: an as-of date minted in the browser carries the USER'S zone, which is the whole
// hazard this module exists to fence.
//
// ── WHAT THIS PROTECTS, stated as the property rather than the mechanism ────────────────────
// `fn_compute_nav(p_as_of, …)`, `fn_nav_composition(p_as_of)` and `fn_holdings_as_of(date)` all
// compare a DATE against `timestamptz::date`, which Postgres evaluates in the SESSION TimeZone.
// The app produces that date in the NODE process, where `toISOString()` is unconditionally UTC.
// TWO CLOCKS IN TWO PROCESSES. They agree today only because the DB TimeZone is pinned to UTC
// (devops-tz) and the app's producer is UTC by construction — an agreement that holds by two
// independent facts, not by one shared mechanism.
//
// That is fine while every as-of date is TODAY, from the server. The deferred hazard (BACKLOG
// §7.7, "Hazard B") is the first user-supplied `p_as_of`: a user in UTC-5 asking for "2026-07-20"
// means their local day, and nothing in a bare `string` records whether that question was ever
// asked, let alone answered.
//
// ── WHY A BRANDED TYPE AND NOT A COMMENT ────────────────────────────────────────────────────
// The obligation previously lived in a sentence: "whoever makes p_as_of user-supplied owns
// resolving the zone explicitly." That is an obligation on a future author WHO MUST FIRST FIND
// THE SENTENCE. A brand moves it to the one place they cannot route around — the compile error
// they get for passing a plain `string`. Closing that error means minting through a factory, and
// a factory is code they must WRITE rather than prose they must FIND.
// Enforced by `npm run check`, which already runs on every commit. Deliberately NOT a CI fence:
// per Sec, the fence set stays meaningful by not accumulating entries for hazards with no live
// path, and this one is better served by the type system.
//
// ── THE NAME CARRIES THE GUARANTEE, AND THAT IS DELIBERATE ──────────────────────────────────
// It is `ZoneResolvedAsOf`, not `AsOfDate` and not `ServerAsOfDate`. Two reasons, and the first
// is the one that decided it:
//
//   1. THE TYPE NAME IS THE DELIVERY MECHANISM. The future author does not read this file; they
//      read an error that says
//          Argument of type 'string' is not assignable to parameter of type 'ZoneResolvedAsOf'
//      which names the missing property. `AsOfDate` would name only the role and tell them
//      nothing about what they have failed to establish.
//
//   2. IT DESCRIBES THE GUARANTEE, NOT THE PROVENANCE, so it survives the change that motivates
//      it. Branding on provenance ("this came from the server") would force the eventual
//      user-supplied-date factory either to mislabel its output or to introduce a SECOND type —
//      fragmenting the very invariant this centralises. Server-derivation is one WAY to satisfy
//      the guarantee, and today the only one; it is not the guarantee.
//
// ── WHEN A USER-SUPPLIED AS-OF ARRIVES ──────────────────────────────────────────────────────
// SELF-238 / SELF-240 (the §2.2.2 / §2.2.3 allocation backends) are the FIRST VALIDATED
// CAPABILITY, NOT a live path — CORRECTED (V1.3 pre-flight sitting D-7, Sec bounded consult,
// HIGH confidence, 2026-08-22): no route wires a client-supplied `as_of` anywhere in the tree;
// both allocation route loaders call `serverTodayAsOf()` unconditionally, and `userSuppliedAsOf`
// has no caller outside its own schema module (`schemas/asOf.ts`) and its tests. Their ratified
// AC8/AC6 require the Zod-typed validation to EXIST for a client-supplied `as_of`. `userSuppliedAsOf`
// below is that second factory. THE ZONE ANSWER IT GIVES: UTC, unconditionally — matching every
// other as-of in the system today (the DB session TimeZone pin + `serverTodayAsOf`'s own UTC
// derivation). This is a DELIBERATE, NARROW resolution, not a placeholder: V1 has no captured
// user-timezone-preference anywhere (no client-supplied zone reaches the server on any surface),
// so "the user's local day" is not a value this server can currently know — treating the
// caller's ISO string as an already-UTC calendar date is the only answer available without
// inventing zone-capture plumbing no AC asks for. If a genuine user-zone requirement lands later,
// it is a NEW factory (or a widened signature here) — not a silent behavior change to this one.
// Flagged for the mandatory Sec joint-review this surface already carries (076's own
// JOINT-REVIEW-MANDATORY note): this is exactly the kind of exemption that must be reviewable,
// which is the whole reason it lives in the one file that can produce this type.
//
// ⚠ THE CASTS IN THIS FILE ARE THE ONLY ONES ALLOWED TO PRODUCE THIS TYPE — currently THREE
//   (two production, one test-only), all below, and they are enumerable on purpose. A cast
//   anywhere else silently re-opens the hazard while still compiling, which is precisely the
//   state the brand exists to make impossible. `grep -rn 'as ZoneResolvedAsOf' src/` should only
//   ever return this file; that grep is the review check, and it is cheap enough to actually run.

// Not exported: an external module cannot name this symbol, so it cannot construct the branded
// type. That unconstructibility IS the fence — the type is otherwise just a string.
declare const zoneResolved: unique symbol;

/**
 * An ISO `YYYY-MM-DD` date whose TIMEZONE QUESTION HAS BEEN RESOLVED — safe to send as a
 * `p_as_of` argument that will be compared against `timestamptz::date` in the DB session zone.
 *
 * Structurally a `string` at runtime (zero cost, serializes normally). The brand exists only at
 * compile time and only to make the producers enumerable.
 */
export type ZoneResolvedAsOf = string & { readonly [zoneResolved]: true };

/**
 * TODAY, from the SERVER clock, in UTC — the only as-of any V1 surface asks for.
 *
 * Resolves the zone question by construction rather than by choice: `toISOString()` is
 * unconditionally UTC in the Node process, and the DB session TimeZone is pinned to UTC, so both
 * sides of every `timestamptz::date` comparison land in the same zone.
 *
 * ⚠ THAT AGREEMENT RESTS ON THE PIN, WHICH LIVES IN ANOTHER REPO SURFACE (devops-tz), and is
 *   asserted by a QA read-back rather than by anything here. This function cannot verify it and
 *   does not pretend to — if the pin is ever removed, this stays UTC while the DB moves, and the
 *   symptom is an off-by-one-day row set with no error anywhere. Named so the dependency is
 *   visible from the code that depends on it, per the standing rule that every exemption names
 *   what it rests on.
 */
export function serverTodayAsOf(): ZoneResolvedAsOf {
	return new Date().toISOString().slice(0, 10) as ZoneResolvedAsOf;
}

/**
 * A CLIENT-SUPPLIED `YYYY-MM-DD` as-of, resolved to UTC — see the module header's WHEN A
 * USER-SUPPLIED AS-OF ARRIVES section for why UTC is the answer this factory gives.
 *
 * Defense-in-depth, not the only line: callers MUST already have Zod-validated the input
 * (real-calendar-date, no coercion — the Lock-14 fence lives at the schema boundary, e.g.
 * `schemas/asOf.ts`'s `isoDate()` — moved there from `schemas/allocation.ts` at SELF-247/D-6),
 * but this factory re-checks the shape itself rather
 * than trusting an upstream caller's validation to never be bypassed — the same layered
 * discipline `sanitizeDecimal`'s DB-CHECK backstop and `fn_planning_target_matched_sub_cat`'s
 * trigger apply to their own callers. Throws on a malformed date rather than minting the brand
 * on unvalidated input; callers that already validated will never hit the throw.
 */
export function userSuppliedAsOf(isoDate: string): ZoneResolvedAsOf {
	if (!/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) {
		throw new Error(`userSuppliedAsOf: not a YYYY-MM-DD date: ${JSON.stringify(isoDate)}`);
	}
	const d = new Date(`${isoDate}T00:00:00Z`);
	if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== isoDate) {
		throw new Error(`userSuppliedAsOf: not a real calendar date: ${JSON.stringify(isoDate)}`);
	}
	return isoDate as ZoneResolvedAsOf;
}

/**
 * ⚠ TESTS ONLY. Mints an arbitrary as-of date, bypassing the guarantee the type asserts.
 *
 * It exists because the brand's purpose and the tests' purpose pull in opposite directions and
 * both are legitimate: the brand fences the PROVENANCE of production dates, while the batteries
 * must exercise BEHAVIOUR at chosen dates — month ends, leap days, the `::date` boundary. A test
 * that could only pass `serverTodayAsOf()` could not test any of them.
 *
 * NAMED TO BE UGLY AND GREPPABLE, deliberately. It is a real hole and the mitigation is that it
 * is a LOUD one: `unsafeAsOfForTest` imported from any non-`.test.ts` file is a review stop, and
 * that is a one-line grep rather than a judgement call. The alternative — a private helper in
 * each test file — would put three unreviewable casts in three places instead of one reviewable
 * hole in this one, which is worse on every axis except appearances.
 *
 * It does NOT weaken the production fence: a production path importing this is as visible as a
 * production path casting, and unlike a cast it names itself.
 */
export function unsafeAsOfForTest(isoDate: string): ZoneResolvedAsOf {
	return isoDate as ZoneResolvedAsOf;
}
