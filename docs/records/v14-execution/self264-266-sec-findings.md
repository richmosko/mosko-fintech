# SELF-264 / SELF-266 — Security joint review

**Reviewer:** security-engineer · **Date:** 2026-09-04
**Refs measured:** `origin/main` @ `524d273` · `origin/feature/self-264` @ `18b1015` · `origin/feature/self-266` @ `6d8dc6b` (= review HEAD)
**Worktree:** `~/Projects/mosko-fintech-worktrees/sec-264` on `feature/self-264-266-sec`, cut from `origin/feature/self-266`.

**Verdict — SELF-264: GREEN. SELF-266: GREEN.** No blocking findings (no `F-n`). Nine notes below, all
prospective hardening or recorded-so-it-is-not-read-as-cleared; none gates either PR.

Suite measured in this worktree after `npm ci` (never a symlinked `node_modules`): `npx vitest run` →
**179 files passed / 5 skipped, 2238 tests passed / 23 skipped, exit 0.**

---

## Verify-hook — ADR-011 read live and verbatim

Read from `DECISIONS.md` **on this branch**, located by bracketing `## ADR-` header (never by line
number). `git diff --stat origin/main...HEAD -- DECISIONS.md` is **empty** — neither branch edits the ADR,
so the branch copy is `main`'s.

- **Decision 3** — read live. The family is eighteen labeled instances (#1–#18), fifteen DDL-realized,
  #5 (`account.sub_cat_id`) DROPPED at `048`, #3 + #4 canonically-locked but DDL-deferred, #18 realized at
  `101`. **Unchanged by these PRs**: `git diff --stat origin/main...HEAD -- supabase/` is empty — no table,
  no column, no FK-shaped reference, no `INTEGER[]`. No reviewed file states an instance number.
- **Decision 4** — the numbered catalogued-instance list, the Privileged-context-surfaces bullet and the
  three-layer composition definitions read verbatim before writing this. **Ledger unchanged**: nothing
  appended, reordered or renumbered; no layer re-attributed; no surface becomes "four-layer". No reviewed
  file makes a §10 statement of any kind, and **no count is carried into these branches**.
  `git diff --stat origin/main...HEAD -- .github/ docs/` is empty, so no CI fence moved either.
  ⚠ The §10 **catalogued** set and the **CI-fenced** set are different sets and are **not** reconciled here.
- **Lock 11** (Decision 15) — no new `SECURITY DEFINER` function. The DEFINER allowlist (Decision 9) is
  untouched. `104` is and stays `security invoker` (`supabase/migrations/104_fn_compute_tax_liability.sql:462`).
- **Lock 15** (Decision 19) — read verbatim. Its own words: *"server-derived-only fence for §2.6 paths (NO
  client-asserted `data_as_of` for cron + on-demand monthly_report; §2.3.3 drill-down is the ONLY surface
  where client toggle is legitimate)"*. See item 2 below.

**Three-axis drift cross-check.**
(i) **instance-numbering** — clean; no reviewed file names a Decision-3 or §10 instance number.
(ii) **layer-attribution** — clean; no reviewed file attributes a §10 layer.
(iii) **verbatim-vs-paraphrase** — clean, with one item surfaced for the record: `taxLiability.ts:11-12`
glosses Lock 15 as *"Lock 15's client-toggle allowance is §2.3.3's alone"* where Decision 19 reads
*"§2.3.3 drill-down is the ONLY surface where client toggle is legitimate"*. Same scope, same exclusivity,
presented as a gloss and not inside quotation marks — **not drift.** Every ADR-067 Decision-5 sub-letter
cited in the reviewed files was checked against the ADR body and is correct: 5(a) envelopes, 5(b)
`capital_gains` no-`rows`, 5(c) prior-year fallback, 5(d) installments, 5(f) R8 window, 5(h) standard
deduction, 5(i) multiplier.

---

## Per-issue verdicts

### 1. Nothing rendered comes from anywhere but the payload — **GREEN**

- No coalescing anywhere on the surface. `grep -n "?? 0\|?? '0'\|||[[:space:]]*0\b\|toFixed\|\* 100\|/ 100\|Number("`
  over both client mirrors, all three components and both `+page.svelte` returns **one hit — a comment
  forbidding it** (`api/src/lib/tax-quarterly.ts:38`).
- AC 4 caption: `federalRateCaption` / `californiaRateCaption` (`api/src/lib/tax-quarterly.ts:188-200`)
  read `applied_marginal_rate` and compute no rate. **Absent key → unavailable** (`!rate` guard, `:190`).
  **Genuine 0% LT CG renders "0%"**, not unavailable — the guard is on `=== undefined`, not on the value
  (`:191`). Correct per AC 4. One residual at N-1.
- AC 2 multiplier: `subTotalThroughNext` (`:161-165`) **sums the payload's own installment amounts** through
  `installments_due_through_next` — it does not multiply, which is the form ADR-067 Decision 5(i) rejects.
- AC 2a boundary: the R8 window is read from `liability.prior_year_q4_window` and re-derived nowhere.
  `TaxJurisdictionTable.svelte` re-checks nothing (`:161`); `isCurrentInstallmentRow`
  (`tax-quarterly.ts:170-175`) carries no date logic of its own.
- NULL / unavailable is never `$0`: `tax_balance_prior_year === null` → "Not entered"
  (`TaxJurisdictionTable.svelte:229-231`); `installments === null` → "Unavailable" (`:245-249`);
  `subTotal === null` → "Unavailable" (`:255`); both envelopes gate on `status` before touching `.amount`
  (`:262-268`, `:280-285`); the prior-year Q4 block gates identically (`:186-207`).
  `fmtCell` (`tax-decomposition.ts:188-190`) renders `null` as "—".
- Every row's ST CG / LT CG cell is a literal "—", not `$0` (`TaxDecompositionTable.svelte:181-182`).
- **Unit check:** `pctFmt` uses `style:'percent'` (×100) and `101_tax_bracket_tables.sql:764-767` constrains
  `bracket_rate` to `0 ≤ rate ≤ 1`, non-NaN — the caption's unit is right.

### 2. E39's second read vs Lock 15 / AC 8a — **GREEN. Server-derived, not client-reachable.**

**I do NOT require any change to satisfy Lock 15 or AC 8a.** Measured:

- Neither loader reads request-derived input. `grep -n "params\|searchParams\|request\.\|url\."` over
  `api/src/routes/taxes/decomposition/+page.server.ts` and `.../quarterly/+page.server.ts` returns **only
  `url.pathname`, inside the `/login` redirect** (both at `:51`). No query string, route param, header or
  body reaches either RPC's arguments. Neither route exports `actions`.
- `loadTaxLiability` passes **no argument at all** (`taxLiability.ts:215`), so Postgres applies `104`'s own
  `p_data_as_of date default current_date`. `pfin.fn_server_today()` is literally `select current_date`
  (`070_fn_server_today.sql:159-171`), so the omitted-argument path **is** the app's server-today primitive —
  there is no second derivation that could drift from it.
- `loadPriorYearQ4` builds `` `${window.tax_year}-12-31` `` (`taxLiability.ts:303`) where `window` is the
  **first payload's own** `prior_year_q4_window`, DB-computed inside `104` (`p.tax_year - 1`). This is a
  citation of an already-computed boundary, gated on `.open` at the single call site
  (`quarterly/+page.server.ts:65-67`). This matches E39's ruling verbatim: *"the `/taxes/quarterly` loader
  calls `fn_compute_tax_liability(p_data_as_of := <window.tax_year>-12-31)` a second time ONLY while
  `prior_year_q4_window.open`"*.
- The interpolated string is sent as a PostgREST JSON parameter, not concatenated into SQL — no injection
  surface even on a malformed value.
- Watchers exist for both halves: `taxLiability.test.ts:92` asserts `loadTaxLiability` calls with **no**
  `p_data_as_of`; `:173` asserts the second call is pinned to Dec 31 of `window.tax_year`.

Residual at N-4 (function-boundary hardening, not a Lock 15 gap).

### 3. Fail-loud loader and the 500 body — **GREEN. No leak.**

- `grep -rn "handleError" api/src/` returns **nothing**, and `find api/src -name "+error.svelte"` is empty.
  SvelteKit's default `handleError` therefore applies: the error is logged server-side and the client
  receives `{ message: 'Internal Error' }` — no stack, no SQL, no tenant data, in dev and in production.
- The typed error's own messages interpolate **only** PostgREST's `error.message` and a key-name list
  (`taxLiability.ts:219-237`) — no row values, no identifiers, no tenant data. They reach the server log
  only. Same shape for the two route-level throws (`decomposition/+page.server.ts:62-65`,
  `quarterly/+page.server.ts:59-63`).
- The shape guard is genuinely watched: `taxLiability.test.ts:115-127` runs an `it.each` over **all six**
  top-level keys and asserts the thrown message names the missing one; `:99-113` cover RPC error, `null`
  payload and array payload.
- **The fail-loud divergence from this directory's fail-soft convention is the right call here** and I
  endorse it: the payload *is* the page, and a fail-soft degrade on a tax-liability read is exactly the
  "renders live off dead data" shape ADR-067 Decision 5(a)'s envelope design exists to prevent.

### 4. Cross-tenant — **GREEN. No `service_role`, no unscoped read.**

- `locals.supabase` is built in `authHandle` from `PUBLIC_SUPABASE_ANON_KEY`, cookie-bound per request
  (`api/src/hooks.server.ts:41-67`). Identity is `getUser()`-validated (`:70-95`). RT-26 allowlist untouched.
- `pfin.fn_compute_tax_liability` — `security invoker` (`104:462`), `revoke execute … from public` /
  `grant execute … to authenticated` (`104:913-914`). `service_role` holds no EXECUTE, which is what makes
  the surface correct for a `rolbypassrls` caller.
- `pfin.fn_tax_authority_ledgers()` — same posture (`102_tax_jurisdiction_ytd_paid.sql:320-321`),
  RLS-scoped, and is the single home of the `tax_jurisdiction is not null` predicate. The loader reads it
  rather than restating the predicate against `pfin.account` — correct.
- The one direct table read is `pfin.tax_character` (`decomposition/+page.server.ts:55-59`). RLS **enabled**
  with `tax_character_select … using (true)` and `grant select … to authenticated`
  (`011_tax_character_registry.sql:192-202`) — shared-read reference data with no tenant column. Reading it
  from the table rather than hardcoding a client-side list is the AC 5 requirement and is the right shape.
- Both routes are behind `mfaHandle`'s fail-closed step-up guard: `/taxes` is not in
  `STEP_UP_EXEMPT_PREFIXES` (`hooks.server.ts:141`), and each loader independently redirects an
  unauthenticated caller. Both directions are watched
  (`decomposition/load.server.test.ts:66,74` · `quarterly/load.server.test.ts:59,66`).
- QA's two-tenant live walk relied on for browser behaviour only, per brief.

### 5. Money precision (E40) — **GREEN. The mixed precision is not a correctness risk on these surfaces.**

- Quarterly renders every money cell at 2 dp through **one** formatter
  (`TaxJurisdictionTable.svelte:119-124`), matching E40 (1) verbatim. The footing is genuinely tested by
  parsing the **rendered strings** back to numbers (`TaxJurisdictionTable.dom.test.ts:165-191`) — that is the
  right instrument for this property.
- Decomposition renders at 0 dp (`TaxDecompositionTable.svelte:115-120`), the house convention; E40 (1)
  scoped the cent ruling to the quarterly tables only, so this is compliant, not a divergence.
- **Why the mix is safe here, measured rather than assumed:** `grep -n "ordinary_input\|taxable_income"`
  over `TaxJurisdictionTable.svelte` returns **empty** — the quarterly tables render no income input and no
  taxable-income figure. No number appears at both precisions, and no rendered figure on one surface must
  foot to a rendered figure on the other. Notes N-5 (intra-surface) and N-6 (forward) record the residuals.
- E40 (2): no staleness marker on either surface. Confirmed — no `staleness` prop anywhere, and
  `TaxDecompositionTable.svelte:74-75` states the absence with its ADR-013 D1 reasoning rather than leaving
  it silent.

### 6. Vocabulary, links, basis note, no inline edit — **GREEN.**

- `tax_character` labels come **only** from the loader's catalog read: `lookupTaxCharacter`
  (`tax-decomposition.ts:76-83`) resolves against the catalog and falls back to the **raw code as its own
  label**, never a guessed English string; the component maintains no code→label switch
  (`TaxDecompositionTable.svelte:175-179`). A V2+ sixth seeded code needs no client change.
- The unclassified line's CTA is `classifyHref`, default `/accounts`
  (`TaxDecompositionTable.svelte:99`) — **byte-identical to the sibling precedent**
  (`CashflowRollupTable.svelte:90`). The `--c-attn-*` register it uses is also identical to that sibling's
  own reserved-canary banner (`CashflowRollupTable.svelte:250-280`), so it is not a §5 fence divergence.
- AC 11 hard gate satisfied: `INVENTORY_SEED_DELTA_MIGRATION = '100_tax_value_inventory_seed_delta.sql'`
  (`taxLiability.ts:47`), rendered in the basis note (`TaxDecompositionTable.svelte:230-238`).
  `supabase/migrations/100_tax_value_inventory_seed_delta.sql` exists on `main`.
- **SELF-264 AC 7 (the M-5 / R10 fail-open hazard) is discharged on both branches of the render.** The basis
  note sits at *section* level, outside the `{#if incomeEmpty}` block, so a tenant whose income sits on a
  Sub-Cat inserted after the SELF-263 inventory still sees "built against migration 100" beside the "No
  tax-relevant activity this tax year yet" empty state. Nothing on the page presents `tax_relevant = false`
  as an examined determination. This is the AC's crux and it holds.
- No inline edit, no as-of control: neither route exports `actions`; every CTA is a plain `<a href>`
  (`TaxQuarterlyTables.svelte:74-77`, `TaxJurisdictionTable.svelte:151,265-267`,
  `taxes/decomposition/+page.svelte:40`). `grep -rn "as_of\|asOf\|AsOf"` over all three components returns
  **empty** — no component takes an as-of prop, so there is nothing that could grow a toggle.
- Nav: one "Taxes" entry → `/taxes/quarterly`, active-matched on `path.startsWith('/taxes/')`
  (`+layout.svelte`). `/taxes/decomposition` is reachable only by the in-page cross-link and direct URL —
  deliberate per the team-lead ruling, recorded here so it is not later read as an oversight.
- **XSS:** `grep -rn "{@html"` over the new components returns nothing; every payload-derived string
  (including `reasonCopy`'s `Unavailable (${reason}).` fallback, `tax-quarterly.ts:242`) reaches the DOM
  through Svelte's escaping `{...}` interpolation.
- **Lock 14 is not engaged** by either surface — no write path, no form action, no user input of any kind.

### 7. The route-export watcher — **GREEN. It is a real watcher, with two coverage residuals (N-7).**

Measured: `npx vitest run src/routes/route-module-export-allowlist.server.test.ts --reporter=verbose` →
**25 tests**, one per module plus the not-silently-empty guard, naming every route from
`/src/routes/+page.server.ts` through `/src/routes/taxes/quarterly/+page.server.ts`.
`find src/routes -name "+page.server.ts" | wc -l` → **24**. 24 + 1 = 25: **the glob enumerates the whole
tree, with no silent partial.** `ALLOWED_EXPORTS` (`:22-31`) matches SvelteKit's own error-message
allowlist exactly, and the `!name.startsWith('_')` escape mirrors the validator's. The header's claim that
`export type` is erased before the eager import is correct and is empirically consistent with
`decomposition/+page.server.ts` (which exports `type TaxCharacterRow`) passing.

This is the right instrument for the defect QA hit: neither `svelte-check` nor a normal vitest run
exercises SvelteKit's request-time route-module validator, so a route could 500 on every request with the
suite green. Building the watcher rather than only removing the stray export was the correct response.

---

## Notes

**N-1 · flag · `api/src/lib/tax-quarterly.ts:191` — the LT CG rate guard is `undefined`-only, not nullish.**
`rate.lt_cg === undefined ? 'unavailable' : pctFmt.format(rate.lt_cg)`. **Mechanism:**
`Intl.NumberFormat.format(null)` returns `"0%"`, so a payload emitting `lt_cg: null` would render a
**fabricated 0% LT CG rate** — collapsing exactly the absent-vs-genuine-zero distinction AC 4 exists to
hold, and in the under-reserving direction. **Reachability: not reachable today** —
`104_fn_compute_tax_liability.sql:820-823` wraps the object in `jsonb_strip_nulls`, so a null `lt_cg` is
stripped to absent, never emitted as null. This is prospective hardening, not a live defect. **Catch
criterion:** change the guard to `rate.lt_cg == null` (or `!('lt_cg' in rate)`) so the client mirror is
closed against both shapes independently of a `jsonb_strip_nulls` that lives in another layer and another
repo directory. **Owner:** Frontend.

**N-2 · note · `api/src/lib/tax-quarterly.ts:188-200` — no guard on `rate.ordinary`.**
Both captions guard `!rate` but then format `rate.ordinary` unconditionally. If `jsonb_strip_nulls` ever
strips a null `ordinary` on a `computed` jurisdiction, `applied_marginal_rate` is `{}` — **truthy** — and
the caption renders `"NaN%"`. Not a fabricated money figure, but a broken caption where "unavailable" is
the correct copy. **I have not traced whether `104` can produce `jf.computed = true` with a null
`ord_applied_rate`; I am stating the mechanism, not asserting reachability.** Same one-line fix shape as
N-1. **Owner:** Frontend (reachability question routes to Architect if anyone wants it settled).

**N-3 · note · `api/src/lib/tax-quarterly.ts:161-165` — zero-value sentinel in `subTotalThroughNext`.**
`Math.min(Math.max(n, 0), 4)` on a non-numeric `installments_due_through_next` yields `NaN` →
`slice(0, NaN)` → `[]` → `reduce` returns **`0`**, which renders as **"$0.00"** rather than "Unavailable".
The `null` return exists precisely for the unavailable case and this path bypasses it. **Reachability:**
`104` always emits an integer, so prospective. **Catch criterion:** return `null` unless
`Number.isInteger(jurisdiction.installments_due_through_next)`. **Owner:** Frontend.

**N-4 · flag · `api/src/lib/server/queries/taxLiability.ts:299-312` — `loadPriorYearQ4`'s own boundary
carries no range fence.** As established in item 2, **Lock 15 and AC 8a hold today** and I require no
change for them. The residual is that the function is **exported** and builds its `p_data_as_of` by
template-interpolating `window.tax_year` with no shape or range assertion, while Lock 15 (ADR-011 Decision
19) names a specific fence for as-of inputs: *"Zod `.date()` + tightened range `2015-12-01 ≤ as_of_date ≤
CURRENT_DATE` per NAV anchor floor + no future dates"*. That fence is satisfied **by the discipline of the
single call site**, not by the function. A second call site supplying a client-influenced window would
type-check and reach the RPC unchecked. **Catch criterion:** throw `TaxLiabilityPayloadError` unless
`Number.isInteger(window.tax_year)` **and** the derived `YYYY-12-31` falls in `[2015-12-01, today]`, with a
paired test leg asserting the refusal. **Owner:** Backend. This is a "should fix", not a merge gate.

**N-5 · note · decomposition whole-dollar footing is unwatched, and is NOT novel.**
`104`'s `inc` CTE emits `sum(it.amount_net)::numeric(20,4)` — fractional cents are representable.
`TaxDecompositionTable.svelte:115-120` renders rows at 0 dp while `groupSubtotal`
(`tax-decomposition.ts:178-180`) sums the **unrounded** values, so displayed rows can fail to add to the
displayed subtotal, and likewise to the server `total`. The dom leg at
`TaxDecompositionTable.dom.test.ts:158-171` uses whole-dollar fixtures and therefore cannot observe this.
**I grepped the tree before calling this a finding: it is the house-wide convention, shared by
`NonReAllocationTable` / `CashflowRollupTable` / `NavCompositionTable`, and E40 (1) deliberately scoped the
cent ruling to the quarterly tables only.** Recorded so it is not later read as examined-and-cleared. If PM
wants it closed the shape is a cents-rounded row sum for the subtotal, not a precision change. **Owner:**
PM to decide whether it is worth closing at all.

**N-6 · note · the precision residual is forward, not here.** The mixed precision is safe on these two
surfaces because they share no rendered figure (measured, item 5). The place the two precisions can be
seen contradicting each other is **SELF-268**, where `104`'s tax scalars land in `fn_nav_composition`'s
buildup beside NAV's whole-dollar rows. Naming it now so it is a known question at that review rather
than a discovery.

**N-7 · flag · the route-export watcher's two coverage residuals.**
(a) **No leg proves the predicate can go RED.** Every leg asserts `[]` against a tree that already
satisfies it — a leg that cannot fail is the tell. Circumstantially the predicate is live (the sibling
`load.server.test.ts` files destructure `{ load }` off the same transform, so named value exports do appear
on the module object), but that is inference, not a watcher. **Catch criterion:** extract the filter into a
named exported function used by the glob loop, and add **one** leg applying it to a synthetic module object
`{ load: 1, STRAY: 2 }` asserting `['STRAY']` — a boundary pair one step apart, which also reds if someone
loosens `ALLOWED_EXPORTS`.
(b) **`+layout.server.ts` and `+server.ts` are not globbed.** Both carry their own SvelteKit export
allowlists and both 500 at request time on a stray export — and a stray export on the **root**
`+layout.server.ts` kills every page, not one.
`find src/routes \( -name "+layout.server.ts" -o -name "+server.ts" \) | wc -l` → **16**, all measured
**clean today** (every export is `load` or an HTTP verb), so this is **prospective**, not a live defect.
**Owner:** QA. Neither (a) nor (b) gates these PRs.

**N-8 · note · E39 doubles the §2.5.3 read cost for Jan 1–15.** `fn_compute_tax_liability` transitively
reaches `fn_gl_entries(date)` and `fn_holdings_as_of(date)` — both unpinned `VOLATILE`, named as such in
`104`'s own header — and the second call runs the whole composition again as of Dec 31. Auth-gated,
per-request, bounded at 2×, so this is a cost note and **not** an availability finding. Flagged only
because it is invisible for 350 days a year and will first be observed under load in January.

**N-9 · note · a frozen sha in a code comment has already gone stale in its scoping phrase.**
`api/src/routes/taxes/decomposition/+page.server.ts:26` reads *"on main as of this branch's origin/main @
346d204"*. The **claim** is true and verified — `346d204` is an ancestor of `origin/main` and
`100_tax_value_inventory_seed_delta.sql` exists at it — but *"this branch's origin/main"* is now `524d273`,
so the scoping phrase no longer describes the branch. Cosmetic; recorded because a frozen sha inside a
descriptive phrase is precisely the construction that reads as live state. No action required.

---

## Non-objections, stated explicitly

- **I do NOT require a change to satisfy Lock 15 or AC 8a.** No client-reachable as-of exists on either
  surface, measured rather than assumed (item 2).
- **I do NOT require a `handleError` hook** for this PR pair. SvelteKit's default already withholds the
  message from the client, and the messages carry no tenant data regardless (item 3).
- **I do NOT object to the fail-loud divergence** from this directory's fail-soft convention. It is the
  correct posture for a surface where the payload is the page, and the reasoning is recorded in the module
  header rather than left implicit.
- **I do NOT object to the direct `pfin.tax_character` select.** It is a shared-read reference table with
  RLS enabled, no tenant column, and reading it beats a client-side enum (item 4).
- **I do NOT object to the client-side Cat-grouping or the per-group subtotal.** Grouping is presentational
  and the footing Total reads the server-authoritative `ordinary_income.total` directly; per-Cat subtotals
  are not server-precomputed, so summing them client-side is the only available shape and matches the
  `NonReAllocationTable` precedent. The rounding residual is N-5, not an objection.
- **I do NOT object to the mixed cent/whole-dollar precision** across the two surfaces (item 5).
- **I do NOT require the second RPC call to be merged into the first.** Keeping `priorYearQ4` as its own
  typed value is what E39 ruled and is the shape that keeps the Dec-31 figures from being mistaken for live
  ones.
- **No §10 ledger change, no secrets-manifest change, no CI fence change, no SECURITY DEFINER addition, no
  Decision-3 DDL, no `service_role` path, no PDF-worker reach.** None of my standing veto triggers is
  approached by either branch.

---

## Reviewer's own error, named here rather than in a follow-up

None to report on this review. The one thing I want on the record: **N-2's reachability is unverified** —
I state the mechanism and explicitly decline to assert that `104` can produce it, rather than either
suppressing the note or presenting it as confirmed.
