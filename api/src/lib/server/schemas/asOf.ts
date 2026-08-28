// asOf.ts — the shared as-of Zod schema + resolution factory for V1's client-supplied as-of
// surfaces. Backend-owned server surface (ARCH §4.1 allowlist).
//
// MOVED HERE from `allocation.ts` (SELF-238 AC8 / SELF-240 AC6's original home) per the V1.3
// pre-flight sitting's D-6 ruling (item 12, `docs/records/v13-preflight/sitting-log.md`):
// "the existing shared schema gets the bound and a surface-neutral rename (`asOfSchema`); one
// constant serves §2.2 + §2.3." The schema was §2.2-scoped by accident of its first caller, not
// by design — SELF-238/240 are the FIRST consumer, not the ONLY one; §2.3 threading
// (SELF-250/253, D-1) is the next. Moving it here — before a second caller exists — is what
// keeps that a rename instead of a fork.
//
// WHY THE MOVE WAS NEEDED, NOT COSMETIC (D-6, sitting item 12): the shipped schema had NO range
// bound. ADR-011 Decision 19 / Lock 15's V1-SHIP-BLOCK app-layer DATE range battery
// (`2015-12-01 <= as_of_date <= CURRENT_DATE`, no future dates) was never applied to it — LATENT
// rather than live, because no route wires `as_of` yet (all FOUR route loaders under
// `api/src/routes` that take an as-of call `serverTodayAsOf()` unconditionally — root
// `+page.server.ts`, `accounts/[account_id]`, `allocation`, `allocation/us-equity`; the two §2.2
// allocation loaders are among them. The count is over ALL routes, not over §2.2 — measured at
// this sha, and it is the tree-wide claim that matters here; Sec's D-7 bounded consult, HIGH
// confidence, confirmed no live client-supplied as-of exists anywhere in the tree as of the
// sitting). This module ships
// the remediation. It does NOT wire any route — that is SELF-253/D-1's ticket.
//
// Lock-14 / Lock-15 fences on the one client-supplied `as_of` field:
//   (a) Zod-typed, parse-don't-coerce real-calendar-date validation (`isoDate()`, same idiom as
//       account.ts / nav-series-params.ts — kept as a local unexported copy per those files' own
//       stated convention, not extracted into a shared module).
//   (b) `.strict()` — an explicit single-field allowlist; any other key is rejected.
//   (c) a two-sided range check, BOTH bounds inclusive (`AS_OF_FLOOR <= as_of <= maxAsOf`),
//       evaluated on the already-shape-validated ISO string — the D-6 remediation this file
//       exists to deliver.
//   (d) `resolveAllocationAsOf` is the ONLY place a §2.2 allocation query module may obtain a
//       `ZoneResolvedAsOf` from a validated param — it calls `userSuppliedAsOf` (the asOf.ts
//       TIME-module factory, `$lib/server/time/asOf` — same base name, different directory, do
//       not conflate the two), never a cast, so the branded-type containment invariant
//       (`asOfBrand.invariant.test.ts`) stays true.
//
// ⚠ THE CEILING IS INJECTED, NEVER EMBEDDED (sitting item 12a). `asOfSchema(maxAsOf)` is a
// FACTORY, not a constant — it takes the request's already-resolved `D` as an argument, and the
// VALIDATOR derives no "today" of its own.
//
// ⚠ SETTLED AT SELF-253 (§2.3.3, the first surface to actually wire this factory into a
// request): the two-clock hazard this paragraph used to warn about is now closed BY
// CONSTRUCTION, not left to a future author. `resolveAllocationAsOf` takes `maxAsOf` as a SECOND,
// REQUIRED argument and its absent-`as_of` branch returns `maxAsOf` itself — the SAME
// already-resolved `pfin.fn_server_today()` value the caller threads into `asOfSchema(maxAsOf)`
// for the ceiling check — rather than independently reading `serverTodayAsOf()` (the Node clock).
// A wired request that omits `as_of` is therefore VALIDATED and SERVED against the identical
// value, in the identical call, because there is only one value in scope to use — not because two
// independently-read clocks happen to agree today. Option (a) named below was taken; option (b)
// does not apply. `serverTodayAsOf()` remains the right call for a surface with NO client-supplied
// `as_of` at all (`cash-flow/+page.server.ts`'s SELF-251 loader, the two §2.2 allocation loaders
// today) — this settlement is about the factory that sits BETWEEN a validated client value and its
// absent-value default, and does not change how an as-of-less surface resolves "today".
//
// The caller resolves `D` ONCE per request, from
// `pfin.fn_server_today()` (migration `070`, ADR-044 Decision 2 — the DATABASE clock, not the
// Node clock) and threads it to every consumer that needs it (ADR-044's "resolve once, thread
// everywhere" discipline — the same discipline the S-3 sitting ruling applies to the §2.3 reader).
// ANY `new Date()` ANYWHERE IN THIS FILE, INCLUDING INSIDE THE FACTORY IT RETURNS, IS A DEFECT —
// Node's clock and the DB's clock can disagree by up to ~26h across a session-TimeZone boundary
// day (ADR-044's two-clock hazard), and a schema that mints its own ceiling reopens exactly the
// hazard `fn_server_today()` exists to close. The only `new Date()` in this file is inside
// `isoDate()`'s `.refine()`, and that use is legitimate: it tests whether the CANDIDATE string is
// a real calendar date (round-trips through `Date` and back), never derives "today" from it.
//
// ⚠ NAMESPACE, NOT SOLVED HERE — unchanged from the schema's prior header. This schema validates
// an ALREADY-ISOLATED `{ as_of }` object — it must NOT be called against a raw, unfiltered
// `Object.fromEntries(url.searchParams)` from a page that may carry OTHER, unrelated params:
// `.strict()` would then reject the whole request on a stray param this surface doesn't own, the
// EXACT page-scoped blast-radius bug `nav-series-params.ts`'s own header documents and fixes with
// a `chart_`-style namespace prefix (F/CTO-ratified 2026-08-13). Whoever wires this schema into an
// actual route/page — no such route exists yet as of this ticket (SELF-247, backend-only) — MUST
// either isolate `as_of` by namespace (coordinated with Frontend, mirroring nav-series-params'
// precedent) or confirm the route carries no other params ever. Not decided here, on purpose: a
// routing-layer choice this ticket does not build (out of scope — SELF-253/D-1).
//
// SCOPE FENCE (this ticket, SELF-247): this module ships the BOUND schema + its resolution
// helper only. It does NOT wire any route to accept a client `as_of` — the TWO shipped §2.2
// route loaders (`/allocation`, `/allocation/us-equity`) keep calling `serverTodayAsOf()`
// unconditionally, unchanged by this PR.

import { z } from 'zod';
import { userSuppliedAsOf, type ZoneResolvedAsOf } from '$lib/server/time/asOf';

/** Real-calendar-date guard (rejects e.g. 2026-02-31) — same idiom as account.ts's `isoDate()`
 *  and nav-series-params.ts's own local copy. */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/**
 * ADR-011 Decision 19 / Lock 15's V1-SHIP-BLOCK range floor — the earliest as-of date any V1
 * surface may accept. Net-new here (D-6, sitting item 12a): the shipped schema carried no floor
 * at all, and the constant briefly had "no referent anywhere in the current tree" (Decision 19's
 * 2026-08-22 Amendment 2). The V1.3 pre-flight sitting (item 15a) ruled it KEPT, with the
 * derivation recorded HERE rather than left to drift a second time.
 *
 * DERIVATION — the Dec-2015 NAV anchor, cited from its three live anchors (verified current at
 * this ticket, not recalled): ADR-011 Decision 19 states the range as `2015-12-01 <= as_of_date`
 * ("per NAV anchor floor", DECISIONS.md ADR-011 Decision 19's Locked option); PRD Appendix B flag
 * (c) locks the underlying fact — "V1 imports the existing Google Sheet's monthly NAV history
 * (Dec-2015 forward) so the 5-Year horizon in §2.1.3 is meaningful at launch"; the browser-safe
 * `api/src/lib/nav-boundary.ts`'s header (NOT its `server/queries/nav-boundary.ts` twin — same
 * base name, different module) names the same anchor for the cron/imported chart boundary ("the
 * imported Dec-2015-forward history landed at calendar month-end by construction"). All three
 * still hold as of this ticket.
 *
 * ⚠ A UNIFORM BOUND, NOT A DERIVED FACT ABOUT TRANSACTIONS — stated so it is never mistaken for
 * one. This constant is a NAV-history floor, applied here to a CASH-FLOW as-of (§2.3 reads
 * `pfin.account_trans`, not the NAV series): a transaction can legitimately predate Dec-2015 —
 * the ledger's own history need not start there — so this floor does NOT claim "no transaction
 * exists before this date." It is a deliberate, single, uniform bound shared by every V1 as-of
 * surface (simplicity over per-surface precision), never evidence about transaction data's true
 * earliest date.
 */
export const AS_OF_FLOOR = '2015-12-01';

/**
 * `asOfSchema(maxAsOf)` — the shared as-of Zod schema, as a FACTORY over the request's
 * already-resolved ceiling. See the module header for why the ceiling is injected rather than
 * embedded, and why `maxAsOf` MUST be resolved from `pfin.fn_server_today()` once per request —
 * never minted inside this file. `as_of` is OPTIONAL — absence resolves to today via
 * `resolveAllocationAsOf` below. `.strict()` rejects any other key.
 *
 * Both range bounds are INCLUSIVE (`AS_OF_FLOOR <= as_of <= maxAsOf`), evaluated on the
 * already-shape-validated ISO string. Plain string comparison is correct and sufficient here
 * because every operand is already a real, zero-padded `YYYY-MM-DD` string by the time the
 * `.superRefine` below runs (`isoDate()` has already validated it) — lexical and chronological
 * order coincide for that shape, the same idiom `api/src/lib/nav-boundary.ts`'s `isPreBoundaryPoint` uses
 * (`pointDate < boundary.first_cron_checkpoint`). Out-of-range issues attach to the `as_of` path
 * so a caller's `fieldErrors(parsed.error)` (`schemas/account.ts` — the SELF-233 structured-error
 * shape already shipped for `/api/settings/planning-target`) surfaces them as a field-level 400
 * with user-meaningful copy, with no extra work at the call site.
 */
export function asOfSchema(maxAsOf: ZoneResolvedAsOf) {
	return z
		.object({ as_of: isoDate().optional() })
		.strict()
		.superRefine((val, ctx) => {
			if (val.as_of === undefined) return;
			if (val.as_of < AS_OF_FLOOR) {
				ctx.addIssue({
					code: z.ZodIssueCode.custom,
					path: ['as_of'],
					message: `Date cannot be before ${AS_OF_FLOOR}.`
				});
			}
			if (val.as_of > maxAsOf) {
				ctx.addIssue({
					code: z.ZodIssueCode.custom,
					path: ['as_of'],
					message: 'Date cannot be in the future.'
				});
			}
		});
}

export type AllocationAsOfParams = z.infer<ReturnType<typeof asOfSchema>>;

/**
 * The one function that turns a VALIDATED `AllocationAsOfParams` into the `ZoneResolvedAsOf`
 * every consumer of this schema requires — §2.2 allocation (SELF-238/240) and, as of SELF-253,
 * §2.3.3's per-account drill-down, the first LIVE caller. Absent `as_of` → `maxAsOf` (the SAME
 * already-resolved `pfin.fn_server_today()` value the caller passed to `asOfSchema(maxAsOf)` for
 * the ceiling check — see the module header's SETTLED note); present → `userSuppliedAsOf`
 * (UTC-resolved — see that factory's own doc for why).
 *
 * ⚠ THE TYPE DOES NOT ENFORCE THIS. `AllocationAsOfParams` is `z.infer`'d and therefore
 * STRUCTURAL (`{ as_of?: string }`), so `resolveAllocationAsOf({ as_of: '1900-01-01' }, maxAsOf)`
 * COMPILES, and `userSuppliedAsOf`'s backstop re-checks the SHAPE only — never the range. The
 * floor/ceiling fence exists at exactly ONE layer, `asOfSchema`'s parse, and a caller that skips
 * it skips both bounds. Call this ONLY on the output of `asOfSchema(...).safeParse` / `.parse`:
 * that is a convention with a review check (`grep -rn 'resolveAllocationAsOf' api/src`), not a
 * compile error. ⚠ Pass the SAME `maxAsOf` value used to build `asOfSchema(maxAsOf)` for this
 * request — a mismatched second argument reopens the two-clock hazard this function exists to
 * close, silently, because nothing at the call site can tell the two apart.
 *
 * ⚠ NAME UNCHANGED ON THE MOVE (sitting item 12/AC1 — deliberate, not an oversight). This stays
 * `resolveAllocationAsOf` even though the schema it resolves from is now surface-neutral and its
 * first live caller is a §2.3 surface: renaming it was not part of the sitting's ruling, and
 * `AllocationAsOfParams` (the type this function consumes) carries the same legacy name for the
 * same reason.
 */
export function resolveAllocationAsOf(
	params: AllocationAsOfParams,
	maxAsOf: ZoneResolvedAsOf
): ZoneResolvedAsOf {
	return params.as_of ? userSuppliedAsOf(params.as_of) : maxAsOf;
}
