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
// Add a second production factory here — NOT a cast at the call site, and NOT a widening of the
// parameter types. Something of the shape `userSuppliedAsOf(isoDate: string, zone: string)`,
// whose body is where the zone question gets answered and where that answer is reviewable.
//
// ⚠ THE CASTS IN THIS FILE ARE THE ONLY ONES ALLOWED TO PRODUCE THIS TYPE — currently TWO, both
//   below, and they are enumerable on purpose. A cast anywhere else silently re-opens the hazard
//   while still compiling, which is precisely the state the brand exists to make impossible.
//   `grep -rn 'as ZoneResolvedAsOf' src/` should only ever return this file; that grep is the
//   review check, and it is cheap enough to actually run.

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
