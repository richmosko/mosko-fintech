-- ============================================================================
-- PART 1 OF THIS FILE — pfin.fn_nav_delta_panel_as_of + pfin.fn_nav_reference_dates_as_of:
--   AS-OF-THREADABLE forms of the §2.1.3 period-delta panel and the §2.1.4
--   reference-date panel, plus the two existing zero-argument functions RE-ISSUED
--   as thin delegators onto them. They close Finding 1 below.
--   ⚠ JOINT-REVIEW-MANDATORY IN ITS OWN RIGHT: this part RE-ISSUES TWO SHIPPED
--   FINANCIAL READ SURFACES. A reviewer must read it as a separate concern from the
--   composer in Part 2, even though the two share a file.
--
--   ⚠⚠ **WHY THESE SHARE A FILE WITH THE COMPOSER RATHER THAN SITTING IN THEIR OWN
--   MIGRATION, which was the first shape and was WRONG.** They were drafted as a
--   separate `112`. **That does not apply on a clean chain: migrations run in
--   filename order, and the composer at `110` would then reference functions that do
--   not exist until `112`.** The defect was invisible on the scratch database where
--   the composer had been re-applied AFTER `112` — a migration applied on top of its
--   own prior outcome demonstrates nothing — and surfaced only on a clean
--   `001`-onwards chain. **The prerequisite must precede its consumer, and there is
--   no free number below `110`**, so the two parts share one file with the
--   dependency ordered inside it. Renumbering the already-pushed composer was the
--   alternative and was declined: QA and Backend build against `110` by number.
--
-- ----------------------------------------------------------------------------
-- THE CATCH CRITERION THIS EXISTS TO MEET, stated first because it is the whole
--   point: **a regenerated report about a PAST month must render §2.1.3 and §2.1.4
--   as of THAT month, or say `unavailable` with a stable code — never today's
--   numbers frozen as a measurement.**
--   Before this migration only the second half was reachable. `fn_nav_delta_panel()`
--   and `fn_nav_reference_dates()` take NO parameters and read
--   `pfin.fn_server_today()` internally, so `110` could not thread `p_data_as_of`
--   into them and emitted an `unavailable` envelope carrying
--   `reader_not_as_of_threadable`. **That was correct and safe and it withheld two of
--   the six report sections' content.** This migration makes the first half
--   reachable, so the envelope becomes the fallback rather than the outcome.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ SHAPE — **DISTINCT NAMES, NOT AN OVERLOAD, AND THE REASON IS A SHIPPED
--   POSTGREST CALL PATH RATHER THAN A DATABASE CONCERN.**
--   The shape proposed to me was an overload: add `fn_nav_delta_panel(p_data_as_of
--   date)` as a NEW signature beside the existing zero-argument one, no default, so
--   nothing is dropped. **In the database that is sound** — a no-default one-argument
--   overload beside a zero-argument function is unambiguous in both directions, no
--   `regprocedure`-anchored assertion in any other file breaks, [ADR-011](DECISIONS.md#adr-011)
--   Decision 9 is untouched because both are INVOKER, and Lock 15 threading holds.
--   **It is not taken, and the disqualifying fact is outside the database:** these
--   functions are called over **PostgREST RPC** from shipped app code —
--   `supabase.schema('pfin').rpc('fn_nav_reference_dates')`, verified in
--   `api/src/lib/server/queries/nav-reference-dates.ts` — with **no arguments**.
--   PostgREST resolves an overloaded RPC by matching the request body's KEYS to
--   parameter names, so an empty body would have to select the zero-argument
--   candidate out of a set of two. **That resolution step does not exist today, and I
--   cannot verify it without writing to the dev database, which is not mine to
--   write.** A distinct name **removes the question instead of answering it**: there
--   is no overload, so `rpc('fn_nav_reference_dates')` resolves exactly as it does
--   now, and the only thing that changed for that caller is what the body does
--   internally.
--   **LOSING SIDE, NAMED: the names are uglier**, and a reader meeting
--   `fn_nav_delta_panel_as_of` may reasonably ask why it is not simply an overload.
--   This block is the answer. **A cosmetic cost is the right thing to pay to avoid
--   introducing an unverifiable resolution dependency on a shipped read path.**
--
-- ----------------------------------------------------------------------------
-- ⚠ THE ZERO-ARGUMENT FUNCTIONS ARE RE-ISSUED AS DELEGATORS, AND THAT IS THE HALF
--   THAT NEEDS THE MOST CARE. The alternative — leaving them alone and letting the
--   `_as_of` forms carry their own copy of the logic — would put **two copies of
--   financial arithmetic on the tree that must agree forever**, which is the failure
--   this project's single-substrate rule exists to prevent. So there is ONE body per
--   panel, parameterized, and the zero-argument form supplies
--   `pfin.fn_server_today()` to it.
--   **CONTRACT PRESERVED EXACTLY:** same names, same `RETURNS TABLE` column lists
--   byte-for-byte, same INVOKER posture, same `search_path` pin. Their EXECUTE ACLs
--   survive untouched — `CREATE OR REPLACE` preserves them — so no grant is re-issued
--   here and none should be.
--   ⚠⚠ **VOLATILITY IS RE-DECLARED ON EVERY FUNCTION IN THIS FILE, AND OMITTING IT
--   WOULD BE A SILENT REGRESSION.** `CREATE OR REPLACE` **RESETS volatility to the
--   default (VOLATILE)**; both zero-argument functions are `STABLE` today, and that
--   pin is invisible to every value assertion — a battery comparing rows would stay
--   green while the planner lost every optimisation that depends on it. `stable` is
--   therefore written into all four bodies.
--
-- ----------------------------------------------------------------------------
-- HOW THE `_as_of` BODIES WERE PRODUCED — fidelity by CONSTRUCTION, not by review.
--   They were not retyped. Each was extracted with `pg_get_functiondef` from a clean
--   `001`–`111` scratch apply — **the LIVE definition from the catalog, not the text
--   of whichever migration file appears to define it** — and exactly three
--   substitutions were applied, each asserted to match EXACTLY ONCE:
--     (1) the function name and signature;
--     (2) `v_today := pfin.fn_server_today();` → `v_today := p_data_as_of;`;
--     (3) the posture header, to state `security invoker` explicitly (the catalog
--         omits it because INVOKER is the default).
--   **Substitution (2) is safe because each body reads the clock EXACTLY ONCE, and
--   each says so in its own comment** — *"070's answer; the ONLY clock read in this
--   function"* — which was verified by count rather than trusted: one occurrence of
--   `pfin.fn_server_today()` in each definition. Every date each panel derives
--   (`v_base`, `v_ye_period`, `v_ye_date`, `v_prior_mth`) is computed FROM `v_today`,
--   so parameterizing that one assignment moves the whole panel's anchor coherently.
--   ⚠ **If a future edit adds a second clock read to either body, this migration's
--   substitution is no longer sufficient and the `_as_of` form silently goes back to
--   being partly anchored on today.** That is the regression to watch for, and it is
--   what the paired QA leg below is for.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER on all four (the shipped posture, preserved);
--   NOT SECURITY DEFINER. `set search_path = ''` on all four. Volatility `stable`,
--   declared per signature. **The Decision 9 allowlist is UNCHANGED** — read it live;
--   no size is stated here. EXECUTE on the two NEW functions is revoked from `public`
--   and granted to `authenticated` only, the `104` / `105` shape; **never to a
--   `rolbypassrls` role**, where the EXECUTE grant would be the entire perimeter
--   rather than the weakest fence.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — UNTOUCHED. This migration creates no table, no column and
--   no FK-shaped reference. Read Decision 3 live; no count is carried here.
--
-- §10 3-AXIS CROSS-CHECK ([ADR-011](DECISIONS.md#adr-011) Decision 4 read VERBATIM
--   and LIVE before drafting, 2026-09-05. Path B — not restated, no count carried).
--   (i)   INSTANCE-NUMBERING — nothing added, removed, reordered or renumbered.
--   (ii)  LAYER-ATTRIBUTION — nothing moves; no surface becomes "four-layer".
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--
-- ----------------------------------------------------------------------------
-- Part 1's dependencies: 097 (the two functions it re-issues), 070
--   (`fn_server_today`), and 062 / 095 (the series readers those bodies compose on).
--   ⚠ PART 1 MUST EXECUTE BEFORE PART 2 IN THIS FILE — Part 2's composer calls the
--   `_as_of` forms Part 1 creates. That ordering is the whole reason the two share a
--   file rather than sitting in separate migrations.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST for this file:
--   1. **EQUIVALENCE, the load-bearing leg:** for every returned column,
--      `fn_nav_delta_panel()` equals `fn_nav_delta_panel_as_of(fn_server_today())`,
--      and likewise for the reference-dates pair. The delegation must be
--      behaviour-preserving, and this is what says so.
--   2. **THE PANEL ACTUALLY MOVES:** `..._as_of(D1)` and `..._as_of(D2)` for two
--      dates in different months return DIFFERENT anchors. ⚠ Without this leg, a
--      body that ignored its parameter would pass leg 1 perfectly — the parameter
--      must be shown to be load-bearing, not merely accepted.
--   3. **ONE CLOCK:** `..._as_of(D)` for a PAST `D` must not vary with the server's
--      today. The sharp form is to run it under two different `TimeZone`/clock
--      conditions, or simply to assert its anchors are derived from `D` alone.
--   4. **Volatility is still pinned:** `provolatile = 's'` on all four signatures
--      after this migration. A `CREATE OR REPLACE` that dropped the declaration would
--      be invisible to every value assertion, which is why this is a catalog leg.
--   5. EXECUTE ACL: the two new functions grant `authenticated` and NOT `public`, and
--      no `rolbypassrls` role holds EXECUTE on any of the four.
--   6. The two zero-argument signatures still EXIST (nothing was dropped), so every
--      `regprocedure`-anchored assertion elsewhere still resolves.
-- ============================================================================
--
-- (Part 2 — the composer itself — begins at its own CONTRACT block below.)
-- ============================================================================

-- ============================================================================
-- Migration: pfin.fn_render_monthly_report — the SINGLE SECURITY INVOKER
--   read-composition helper for the §2.6 monthly report. Phase 6 Build Loop,
--   Linear SELF-347 / A3. Realizes [ADR-011](DECISIONS.md#adr-011) Decision 15 /
--   Lock 11's read-composition pattern and Gate A option B (unified).
--   apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface). ⚠ Reviewed as ONE design unit with
--   `108` (A1) and `109` (A2) and `111` (the R7 audit helper) under ONE Sec
--   joint-review — R1 rider 8, R13 step 6. Do not review this file alone.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS FUNCTION IS, AND — MORE IMPORTANTLY — WHEN IT DOES **NOT** RUN.
--   Under R1 (A) this helper is **the COMPOSING form only.** It runs on GENERATION
--   (the cron, and the on-demand endpoint) and on the DRAFT view. **A historical
--   read of a `final` report is a PAYLOAD READ off `pfin.monthly_report`, not a call
--   to this function** — the third entry path takes THE REPORT ROW; it does not
--   re-enter `(month, as_of)`. P2 item 2 and P5 state the same rule from the read
--   side. That is why the render-budget question below bounds generation latency and
--   not every historical view.
--
-- ----------------------------------------------------------------------------
-- ⚠ SIGNATURE — NO `p_users_id`, RULED AT R3 (i), AND THE REASON IS SECURITY, NOT
--   TASTE. `fn_render_monthly_report(p_target_month date, p_data_as_of date)`.
--   Tenant identity is `auth.uid()`, full stop.
--     · PM logs the drafted `p_users_id` as the SIXTH recurrence of the §7.19
--       signature family. Precedent on the tree: `105` (*"p_users_id DROPPED"*) and
--       `101` (*"takes NO tenant parameter"*).
--     · **Sec F-4 states the security half: with `p_users_id` present, a bypass-RLS
--       caller makes the PARAMETER the only tenant fence** — which is
--       [ADR-011](DECISIONS.md#adr-011) Decision 1 clause (c) unacknowledged.
--     · And the trap runs the other way for an RLS-SUBJECT caller: a `p_users_id`
--       naming a foreign tenant on an INVOKER helper returns EMPTY rather than
--       raising, so a wrong question silently becomes "no data".
--   **BIND AN IDENTITY; NEVER PASS AN ID.**
--
-- ----------------------------------------------------------------------------
-- ⚠ TENANT BINDING FOR EVERY NON-JWT CALLER — R3 (i), option α: IMPERSONATION.
--   `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)` per
--   tenant, per transaction, **with the singular `request.jwt.claim.sub` GUC NULLED
--   FIRST** — the pattern already shipped as `TenantBoundConnection` at
--   `workers/etl/src/pfin_back_etl/connection.py`. A7 NAMES AND REUSES that module
--   rather than re-specifying it. Sec's β (`service_role` + a code-layer parameter)
--   and γ (session-minting) were not taken.
--   **THE HAZARD THE RULING CLOSES (Sec F-4), stated because it is silent:** setting
--   the CLAIMS WITHOUT the ROLE leaves `rolbypassrls` in force — `auth.uid()` returns
--   the intended tenant, **every RLS predicate is skipped, the composition reads
--   EVERY tenant's rows, and NOTHING RAISES.** The output looks like a report.
--   Under R2 (C) this is the ONLY non-JWT path left: the PDF worker no longer
--   reaches the database or this helper at all.
--
--   **ARCH `:208` — RULED AT R3 (ii): the clause constrains the SESSION CONTEXT, not
--   the process identity, and it is PDF-scoped.** *"User-session only"* means the
--   helper always executes under a session where **RLS applies** and `auth.uid()`
--   resolves to the tenant whose data is read. The cron satisfies it BY
--   IMPERSONATING — at the database layer that caller IS a user session. What the
--   sentence forbids is the thing its own second clause is about: a worker reaching
--   the database DIRECTLY, outside any user session. The general reading cannot be
--   right, because under it **A7 could not exist at all** and Lock 11 mod #4 — a
--   ratified V1-SHIP-BLOCK *cron tenant-binding discipline* — would be meaningless.
--   ⚠ **THIS MAKES SEC F-4 SHARPER, NOT WEAKER: claims-without-role does not satisfy
--   a session-context constraint either**, because `rolbypassrls` remains in force
--   and the session is not a user session in the only sense that matters.
--   The sentence is NARROWED on the tree in this PR's doc half (ARCH `:208`), not
--   left in a records file.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ FINDING 1 — **TWO OF THE THREE NAMED NAV-PERFORMANCE READERS CANNOT BE
--   THREADED, AND AC 4 AND AC 7 CANNOT BOTH BE SATISFIED OVER THEM. ROUTED TO F/CTO;
--   THIS FILE SHIPS THE SAFE HALF AND MAKES THE GAP LOUD.**
--   AC 4 names *"NAV Performance ← the §2.1.2/§2.1.3/§2.1.4 readers"*. AC 7 is ONE
--   CALL, ONE CLOCK: *"`p_data_as_of` threads unchanged into every callee; nothing
--   derives its own date"* (Lock 15; RT-25). Measured against the live catalog
--   2026-09-05:
--     · §2.1.2 — `pfin.fn_nav_series(p_granularity text, p_start_date date,
--       p_end_date date)` and `pfin.fn_nav_series_inflation_adjusted(...)` take
--       EXPLICIT DATE BOUNDS. **Threadable. Composed here.**
--     · §2.1.3 — `pfin.fn_nav_delta_panel()` takes **NO PARAMETERS** and calls
--       `pfin.fn_server_today()` INTERNALLY.
--     · §2.1.4 — `pfin.fn_nav_reference_dates()` takes **NO PARAMETERS** and calls
--       `pfin.fn_server_today()` INTERNALLY.
--   **The last two derive their own date, by construction. There is no argument this
--   function can pass that changes it.**
--   ⚠ **WHY THAT IS NOT A ROUNDING ERROR, AND WHY (β) IS UNSAFE:** the report is a
--   FROZEN artifact and REGENERATION IS A FIRST-CLASS PATH (P5 item 4, load-bearing
--   under R1 rider 6). On a first generation a few days after the month closes,
--   *today* ≈ the as-of and the difference is small. **On a regeneration MONTHS
--   later, a delta panel anchored to `fn_server_today()` would freeze a panel
--   describing TODAY into a report about a past month** — a confident, plausible,
--   wrong number, indistinguishable from a correct one and permanent once frozen.
--   That is the exact pathology `062`'s header and ADR-053 Decision 1 are built
--   around, arriving on a different surface.
--   ⚠ **CLOSED 2026-09-05 BY PART 1 OF THIS FILE. This function now threads all four readers, and
--   the `unavailable` envelope is the FALLBACK rather than the outcome.**
--   **OPTIONS, AND WHY THE THIRD WAS BUILT:**
--     (α) **SHIPPED FIRST, NOW SUPERSEDED.** Compose from the threadable readers only
--         and emit §2.1.3 / §2.1.4 as an explicit `unavailable` envelope carrying
--         `reader_not_as_of_threadable`. Correct and safe, and it **withheld two of
--         the six sections' content** — which is why it was the interim and not the
--         answer.
--     (β) **NOT TAKEN, EVER.** Call the zero-argument forms anyway and accept a
--         today-anchored panel. It is the fabrication-shaped-like-a-measurement
--         failure, made permanent by the freeze.
--     (γ) **TAKEN, as Part 1 above.** Give both panels AS-OF forms and thread them.
--         ⚠ My earlier note that this required DROPPING the zero-argument signatures
--         **was wrong, and the correction is the whole reason it became cheap:** the
--         ambiguity I described arises only from a parameter with a DEFAULT, which
--         would make a one-argument function callable with zero arguments. **A
--         no-default form creates no ambiguity**, so nothing had to be dropped and no
--         `regprocedure`-anchored assertion anywhere breaks. Recorded because the
--         earlier reasoning was the sole ground for calling this expensive.
--         ⚠ **Part 1 does NOT use an overload, though — it uses DISTINCT NAMES**
--         (`..._as_of(date)`), because these functions are called over PostgREST RPC
--         by shipped app code with no arguments, and an overload would make an empty
--         request body resolve against a candidate SET rather than a single
--         function. That resolution step does not exist today and cannot be verified
--         without writing to the dev database. See Part 1's header block for the
--         full reasoning and its named losing side.
--   **THE CATCH CRITERION IS MET, MEASURED RATHER THAN ASSERTED:** composing a report
--   for a PAST month returns that month's anchors, not today's — verified on a clean
--   apply, `p_data_as_of = 2025-06-30` yielding anchors 2020-06-30 / 2022-06-30 /
--   2024-06-30 / 2024-12-31 / 2025-05-31, against a wholly different set for
--   2026-08-31.
--   **A NOTE ON WHY THIS WAS NOT VISIBLE AT THE SITTING:** AC 4 names the readers by
--   PRD SECTION, not by signature, and the two unthreadable ones were re-issued at
--   `097` under a migration named for something else. The identifiers resolve; the
--   as-of contract was never in the AC's field of view.
--
-- ----------------------------------------------------------------------------
-- ⚠ FINDING 2 — **`fn_compute_tax_liability` IS EVALUATED TWICE PER RENDER, AND TWO
--   IS THE STRUCTURAL MINIMUM. THIS IS THE ANSWER TO THE LATENCY QUESTION, WITH THE
--   ARITHMETIC RATHER THAN AN ASSURANCE.**
--   `pfin.fn_nav_composition` (`105`) calls `fn_compute_tax_liability` ONCE
--   internally, threading its own `p_as_of` unchanged.
--     · **The §2.5.4 NAV-component tax envelopes ARE reachable from
--       `fn_nav_composition`'s payload** at `buildups.realized_tax_liab` and
--       `buildups.unrealized_tax_liab`, carried verbatim from that callee's
--       `nav_components`. **This function therefore reads them THERE and does NOT
--       re-invoke `104` for them.** That removes a THIRD evaluation.
--     · **It cannot remove the second.** The §2.6.1 Estimated Taxes section needs
--       `decomposition`, `jurisdictions` (and inside them `basis_year` and
--       `current_year_schedule_empty`, which **AC 6 requires to travel**) and
--       `prior_year_q4_window`. **NONE of those appears anywhere in
--       `fn_nav_composition`'s payload** — measured against the live body, whose
--       only branches are `groups`, `buildups` and `nav`. They are reachable ONLY by
--       calling `104` directly.
--     · The alternative — composing Account Holdings from `049` + `104` here instead
--       of calling `fn_nav_composition` — would be a SECOND COPY of `105`'s
--       composition logic, including its tax-authority-ledger anti-join and its sign
--       convention. That is the failure this project's single-substrate rule exists
--       to prevent, and it would trade a duplicated call for duplicated arithmetic
--       on money.
--   **SO: TWO EVALUATIONS, AND THE SECOND IS BOUGHT BY AC 6's OWN CONTENT.**
--
--   ⚠⚠ **THIS IS A CORRECTION TO THE LATENCY PROBE'S FOLLOW-UP (a), AND THE
--   DIFFERENCE IS WORTH ~165 ms THAT IS NOT ACTUALLY AVAILABLE.** The probe records
--   that *"dropping the second evaluation would cut the composed total from 548.8ms →
--   ~384ms … roughly a 30% cut … for a pure reuse fix with no schema change"*, and
--   routes it as a signature note. **The envelope-reuse half is IMPLEMENTED here and
--   always was** — this function reads `buildups.realized_tax_liab` and
--   `buildups.unrealized_tax_liab` out of `fn_nav_composition`'s payload and never
--   re-invokes `104` for them. **What is NOT available is dropping the second
--   evaluation, because the two are different things:** reuse removes a THIRD call
--   that this function never made; the SECOND call serves the §2.6.1 Estimated Taxes
--   section, whose `decomposition`, `jurisdictions`, `basis_year`,
--   `current_year_schedule_empty` and `prior_year_q4_window` appear NOWHERE in
--   `fn_nav_composition`'s payload — measured against its live body, whose only
--   branches are `groups`, `buildups` and `nav`. **AC 6 requires every one of those to
--   travel.** So the ~30% is only realizable by dropping AC 6 content, and **549 ms —
--   not ~385 ms — is the number the budget above is correctly set over.** Recorded
--   because a follow-up that reads as free money will otherwise be re-attempted, and
--   the attempt would silently thin the frozen payload.
--   ⚠ **HARD REQUIREMENT THAT FALLS OUT OF IT: both evaluations MUST receive the
--   SAME date.** `fn_nav_composition(p_data_as_of)` threads `p_data_as_of` into its
--   internal call, and this function calls `fn_compute_tax_liability(p_data_as_of)`
--   directly. If those two ever diverge the payload would carry TWO DIFFERENT TAX
--   STATES for one report and the §2.6.1 foot would reconcile to nothing. There is
--   exactly one date variable in this function and it is never modified.
--
-- ----------------------------------------------------------------------------
-- RENDER-BUDGET CLAUSE (AC 11; PM §10, routed to Architect) — **CLOSED 2026-09-05**
--   against `docs/records/v15-execution/a3-latency-probe.md` (commit `7e0deb2`, merged
--   to `main`). Figures below were read from that file on the tree, not from a relay.
--
--   **THE BUDGET: on-demand generation (A10) p95 ≤ 2000 ms, SYNCHRONOUS. No async
--   shape is adopted at V1.5.**
--
--   MEASURED BASELINE, and the conditions that make it the right number to reason
--   from: a synthetic production-shaped tenant — 20 accounts, 4,903 `account_trans`
--   over 24 months, Federal and California both designated, both `fn_nav_composition`
--   and `fn_compute_tax_liability` returning fully `computed` rather than
--   `unavailable` — composed at **549 p50 / 556 p95 ms**, with the checkpoint tables
--   EMPTY. ⚠ **Empty is the DB's real state on every tenant** (nothing in the pipeline
--   populates them), which is why the probe's checkpoint-populated column is a
--   control and not a better case. That leaves roughly **3.6× headroom**.
--
--   ⚠ **THE RISK IS SCALING, NOT THE CURRENT NUMBER, AND IT IS UNBOUNDED BY DESIGN.**
--   Cost is **linear in transaction count**, because the expensive paths have no
--   bounded form in the schema: `fn_gl_entries` walks the full `account_trans` history
--   for trade-position classification with no checkpoint awareness of any kind, and
--   `fn_cashflow_items` takes only `p_as_of` — it has **no lower bound and no
--   since-checkpoint alternative form** in its contract. So the budget is consumed by
--   TENANT TENURE, not by load. **TRIPWIRE, stated as a number so it can be watched
--   rather than felt: linear scaling puts p95 at the 2000 ms budget somewhere near
--   3.5× the measured volume — on the order of 17,000 transactions for a comparable
--   account count.** A tenant approaching that is the signal to build the mechanism
--   named below, or to adopt the async shape as an interim.
--
--   ⚠⚠ **POPULATING THE EXISTING CHECKPOINT TABLES IS NOT THE FIX, AND THAT IS
--   MEASURED RATHER THAN ASSUMED.** The probe populated both at 24 monthly month-ends
--   and cost did not fall — `fn_nav_composition`'s buffer-hit count went UP, the
--   opposite of what a scan-bounding optimisation produces. Traced to the code:
--   **`pfin.holdings_checkpoint` has NO READER in the 049/056/093/104/105 chain at
--   all**, so those rows are structurally inert here. The one genuinely bounded path
--   (`account_balance_checkpoint` via `fn_account_cash_as_of`) works as designed and
--   **was never the expensive part.** Recorded because "populate the checkpoints" is
--   the obvious next idea and it is now falsified, not merely untested.
--
--   **THE IN-APP VIEW DOES NOT COMPOSE LIVE FOR A `final` REPORT** — it reads the
--   frozen payload (R1 (A)), so this budget does not govern historical viewing at all.
--   ⚠ **BUT SEE FINDING 5 BELOW: A `draft` HAS NO PAYLOAD TO READ**, so the draft view
--   is a live composition and inherits this budget per visit. That is not a defect in
--   the ruling; it is a case the ruling's phrasing does not cover, and it is stated
--   rather than absorbed.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ FINDING 5 — **"THE IN-APP VIEW READS THE FROZEN `final`/`draft` PAYLOAD" IS TRUE
--   OF `final` AND CANNOT BE TRUE OF `draft`. ROUTED TO F/CTO AND PM.**
--   `108`'s `monthly_report_payload_by_status` permits `rendered_payload` to be NULL
--   **precisely while `draft`**, because R1 writes the payload **once, at
--   finalization** and the cron creates the draft row before any payload exists.
--   **So there is no draft payload to read.** Any surface rendering a draft either
--   composes live through this function or renders nothing.
--   **AND COMPOSING LIVE IS ALMOST CERTAINLY CORRECT ON PRODUCT GROUNDS, which is why
--   this is a wording gap and not a bug to fix by writing a draft payload:** the draft
--   view exists so the author can see **current** figures before freezing them. A
--   draft that served a stale frozen payload would show numbers the author is about
--   to finalize but which are no longer true — the exact failure the freeze exists to
--   prevent, inverted.
--   **CONSEQUENCE, and it is the load-bearing half:** the draft view pays ~549 ms per
--   visit, and the probe's own recommendation 1 says **do not render that inline.**
--   The probe and the ruling therefore disagree about the draft view specifically,
--   and the schema settles which of them is describing something that exists.
--   **This function is written for either answer** — it composes on demand and holds
--   no opinion about who calls it.
--   ⚠ **RULED 2026-09-05: A `draft` COMPOSES LIVE THROUGH THIS FUNCTION ON VIEW; a
--   `final` READS THE FROZEN PAYLOAD. This function stays exactly as written, and the
--   rendering surface renders both ways.**
--   **The reason the ~549 ms is acceptable here and the probe's recommendation still
--   stands is a distinction the probe did not draw:** its *"do not render this
--   inline"* is about a **per-visit hot page**, and the draft view is an **authoring
--   surface visited rarely** — a handful of times in the window between the cron's
--   draft and finalization, by one author, deliberately. **The probe and the ruling
--   were never actually in conflict about the same page**; they were talking about
--   different surfaces, which is what this finding surfaced by asking the schema
--   which one exists.
--   **CONSEQUENCE THAT SURVIVES THE RULING and is not softened by it:** the draft view
--   is the ONLY surface on which this composition's latency is user-visible, so it is
--   the surface where the tenant-tenure scaling above lands first. **When the tripwire
--   is approached, the draft view is where it will be felt before the on-demand
--   generation path notices**, and that is worth knowing when the rollup mechanism is
--   scheduled.
--
-- ----------------------------------------------------------------------------
-- ⚠ FINDING 3 — DATED IDENTIFIERS IN THE SOURCES, corrected here rather than
--   inherited. Each was true when written; each names something the tree does not
--   have under that name today. **The RULINGS stand; the identifiers are dated.**
--     · Lock 11's own join list names **`pfin.nav`**, which has never existed. The
--       read-composition ruling stands; grep the identifiers, not the list.
--     · AC 4 names **`fn_cashflow_cross`**. The live function is
--       **`pfin.fn_cashflow_cross_account_rollup(p_as_of date)`** (`093`). There is
--       no `fn_cashflow_cross`.
--     · AC 4 cites `fn_subcat_market_value` as `076`/`081` and
--       `fn_historical_expenditures` as `093`/`096`. Those are the ORIGINATING
--       migrations; the LIVE bodies are at **`084`** and **`098`** respectively, both
--       re-issued under migrations named for something else. Cited here so a reader
--       verifying the composition reads the right body — the same class of trap that
--       produced Finding 1.
--     · The drafted *"SELF-260/261 §2.5.1"* citation is struck: **SELF-261 closed
--       unbuilt**; §2.5.1's readers are `100` / `104`.
--
-- ----------------------------------------------------------------------------
-- ⚠ KNOWN TRANSITIVE VOLATILITY GAP — INHERITED, NOT INTRODUCED (AC 9).
--   This function declares `stable`, per the `104`/`105` precedent and because
--   `CREATE OR REPLACE` resets volatility so it must be declared per signature. **The
--   promise is not fully backed and this file does not claim it is:**
--   `pfin.fn_gl_entries` and `pfin.fn_holdings_as_of` are `provolatile = 'v'` at this
--   sha (SELF-326, open), and they sit in this function's transitive read set through
--   `fn_compute_tax_liability` and `fn_account_unrealized_gl`. **A STABLE caller of a
--   VOLATILE callee is an unbacked promise**, and the honest statement is that this
--   function performs no writes and would be STABLE if its transitive set were
--   pinned. It is declared `stable` anyway because the alternative — declaring
--   VOLATILE — would forbid the planner optimisations every sibling reader relies on
--   and would misdescribe this function's own body.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11, V1-SHIP-BLOCK: *"SECURITY INVOKER
--   on read-time composition (no DEFINER bypass)"*); NOT SECURITY DEFINER.
--   `set search_path = ''`. Volatility `stable`, declared in the body per signature.
--   The Decision 9 allowlist is UNCHANGED BY THIS FILE — read Decision 9 live; no
--   size is stated here.
--   ⚠⚠ **THE EXECUTE ACL IS A STANDING ASSERTION, NOT A POSTURE NOTE (R3 rider 1).**
--   `revoke … from public; grant … to authenticated;` — the `104` / `105` shape;
--   `008` grants no function EXECUTE. **NEVER TO A `rolbypassrls` ROLE.** For an
--   INVOKER function the EXECUTE ACL is normally the WEAKEST of several fences; for a
--   bypass-RLS caller RLS applies to nothing, so **the EXECUTE grant is the ENTIRE
--   PERIMETER.** `service_role` has no EXECUTE here and **that ABSENCE is what makes
--   the surface correct for it.**
--   **STANDING CONDITION, inherited because this function composes `104`'s and
--   `105`'s money figures: any grant of EXECUTE on this function, on
--   `pfin.fn_compute_tax_liability` or on `pfin.fn_nav_composition` to a
--   `rolbypassrls` role is SEC-JOINT-REVIEW-MANDATORY.** The failure mode is not an
--   attack; it is a future migration adding a grant to make something work. P10 item
--   3 carries the standing leg.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK ([ADR-011](DECISIONS.md#adr-011) Decision 4 read VERBATIM
--   and LIVE before drafting, 2026-09-05. Path B — not restated, no count carried).
--   (i)   INSTANCE-NUMBERING — nothing added, removed, reordered or renumbered.
--   (ii)  LAYER-ATTRIBUTION — nothing moves; no surface becomes "four-layer". This
--         file authors no grant to any privileged role and no infrastructure control.
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--   DECISION 3: this file creates NO table, NO column and NO FK-shaped reference —
--   the family is untouched by it.
--
-- ----------------------------------------------------------------------------
-- Numbering: 110 follows 109. Depends on `108` (reads nothing from it at DDL time,
--   but the report row is this function's write target one layer up) and on the
--   §2.1–§2.5 reader set: 049/056 · 093 · 095 · 097 · 098 · 084 · 074 · 104 · 105.
--   `111` (the R7 audit helper) is independent of this file and follows it.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST for this file (RT-19 read-time composition tenant-scoping; RT-25
--   as-of parameter-bypass adversarial input):
--   1. **Sec F-4 catch criterion, WITH ITS POSITIVE CONTROL (R3 rider 2).** A
--      two-tenant fixture where the composition runs for tenant A while tenant B's
--      rows EXIST; assert ZERO tenant-B rows in the composed output. ⚠ **The leg is
--      VACUOUS BY DEFAULT on a fresh fixture with no tenant-B rows, so the battery
--      must also prove the leg REDS when the role assumption is struck** (claims set,
--      `SET LOCAL ROLE authenticated` omitted).
--   2. **STANDING catalog assertion (R3 rider 1, P10 item 3):** no `rolbypassrls`
--      role holds EXECUTE on this function, on `fn_compute_tax_liability` or on
--      `fn_nav_composition`. Standing, not one-time.
--   3. **ONE CALL, ONE CLOCK:** the payload's echoed `as_of` equals the
--      `p_data_as_of` passed in, and equals the `as_of` echoed by the Estimated
--      Taxes section — the two `104` evaluations must agree.
--   4. **RT-25:** a client-supplied as-of is REFUSED on the on-demand path (A10 item
--      3), not ignored. The DB half is that this function has no default on
--      `p_data_as_of`, so a caller cannot omit it and get a server date silently.
--   5. Every envelope crosses UNFLATTENED: `{status, reason}` and `{status, amount}`
--      arrive as OBJECTS, `reason` is a stable machine code, and no `?? 0`,
--      zero-fill or currency formatting happens inside this function.
--   6. The `unavailable` case is the BOOTSTRAP DEFAULT, not an edge case: a user with
--      no designated tax ledger gets `unavailable` envelopes and a rendered reason,
--      never `$0`.
--   7. **THE FINDING-1 CATCH CRITERION, and it is the sharp leg in this file:**
--      compose the SAME `p_target_month` twice with two different `p_data_as_of`
--      values in different months, and assert the §2.1.3 `anchor_date` set and the
--      §2.1.4 `reference_date` set DIFFER. ⚠ **A leg that only checks the panels are
--      present passes against a today-anchored implementation**, which is the exact
--      defect Finding 1 exists to prevent — the panels must be shown to MOVE with the
--      as-of, not merely to be there. Pair it with Part 1's own equivalence leg
--      (`fn_nav_delta_panel()` = `fn_nav_delta_panel_as_of(fn_server_today())`), which
--      is what proves the delegation did not change the live behaviour of the
--      zero-argument readers the app already calls.
--   8. A cross-tenant caller (INVOKER, no rows) gets a well-formed payload with empty
--      sections, NOT an error and NOT a NULL — it fails closed INTO A SHAPE THAT SAYS
--      SO.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ⚠⚠ FINDING 4 — **THE RULED TWO-ARGUMENT SIGNATURE CANNOT NAME *WHICH* DRAFT IT
--   COMPOSES FROM, AND NOTHING GUARANTEES THERE IS ONLY ONE. ROUTED TO F/CTO AND
--   SEC; A ONE-LINE FIX EXISTS AND IS NOT TAKEN UNILATERALLY.**
--   AC 4 sources the **Rebalancing Targets** section from *"A1's commentary
--   columns"*, so this function must read a `pfin.monthly_report` ROW. AC 1 fixes
--   the signature at `(p_target_month, p_data_as_of)` — there is no report id to
--   pass. The row must therefore be IDENTIFIED, and the only available key is
--   `(auth.uid(), p_target_month, generation_status = 'draft')`.
--   **`108` guarantees at most one `final` per month. It guarantees NOTHING about
--   drafts.** Two clicks of Regenerate before finalizing produce two draft rows, and
--   this function would then compose from one while the caller writes the payload
--   onto the other — **a report whose commentary came from a row that is not the row
--   it was frozen into.** Silent, and permanent once frozen.
--   **WHAT THIS FILE DOES:** picks the HIGHEST `report_id` in `draft` state for
--   `(auth.uid(), p_target_month)` — deterministic rather than arbitrary — and
--   **echoes the chosen `report_id` back in the payload at
--   `sections.rebalancing_targets.source_report_id`, so the caller can ASSERT it
--   equals the row it is about to write.** That converts a silent mismatch into a
--   checkable one, which is the most a two-argument signature can do from inside.
--   ⚠ **RESOLVED 2026-09-05 — THE GUARANTEE NOW EXISTS, AND THIS FUNCTION IS
--   UNCHANGED BY IT.** `108` gained a second partial unique index,
--   `(users_id, target_month) where generation_status = 'draft'`, on PM's objection:
--   the falsifying case is two tabs, where tab B's Generate inserts a second draft,
--   tab A's Save lands on the first, and P4 finalizes the second BLANK — silent
--   commentary loss, with the orphan persisting forever because DELETE is blocked on
--   everything. So *"pending = draft"* is now singular in fact and not only in
--   phrasing.
--   **WHAT THAT CHANGES HERE: nothing in the body, deliberately.** The
--   highest-`report_id` rule becomes degenerate — there is at most one row to choose
--   from — and `source_report_id` is still echoed. **An assertion that can no longer
--   fail is still the instrument that proves the index is holding**, and if the index
--   is ever dropped or narrowed this function keeps composing deterministically
--   rather than arbitrarily. Removing either would trade a working check for nothing.
--   **The cost moved rather than disappeared:** a second Generate click can now raise
--   23505, so Generate must OPEN an existing live draft rather than insert, and
--   Regenerate becomes a FINAL-only affordance. That is app-layer copy and behaviour,
--   not a schema question, and it is recorded in the ADR rather than here.
--
-- ----------------------------------------------------------------------------
-- CONTRACT — **THIS IS THE PAYLOAD SHAPE BACKEND AND FRONTEND BUILD AGAINST**
--   (P2, P5, P6, A7, A10). It is also, verbatim, what is FROZEN into
--   `pfin.monthly_report.rendered_payload` at finalization, so a change to it is a
--   `payload_schema_version` bump and not an edit.
--
--   pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date)
--     returns jsonb — SECURITY INVOKER, stable, set search_path = ''.
--     NO DEFAULT on either parameter: a caller cannot omit `p_data_as_of` and
--     silently receive a server date (the RT-25 half this function can enforce).
--
--   {
--     "payload_schema_version": 1,
--     "target_month": <date>,                -- echoed, = p_target_month
--     "as_of":        <date>,                -- echoed, = p_data_as_of. ONE CLOCK.
--     "sections": {
--       "account_holdings": {                -- §2.6.1 (1) <- fn_nav_composition(105)
--          "groups": [...], "buildups": {...}, "nav": <numeric>
--          -- carried VERBATIM. buildups.realized_tax_liab and
--          -- buildups.unrealized_tax_liab are the §2.5.4 ENVELOPE OBJECTS and are
--          -- the ONLY source this function uses for those two scalars.
--       },
--       "nav_performance": {                 -- §2.6.1 (2) <- §2.1.2/.3/.4 readers
--          "series":                   [ {point_date, nav_value, checkpoint_date} ],
--          "series_inflation_adjusted":[ {point_date, nav_nominal, nav_inflation_adjusted, ...} ],
--          "delta_panel":     [ {horizon, anchor_date, anchor_checkpoint_date,
--                                current_checkpoint_date, delta_nominal, delta_percent,
--                                delta_inflation_adjusted,
--                                delta_inflation_adjusted_percent, cpi_basis_period,
--                                cpi_any_carried, cpi_unavailable} ],
--          "reference_dates": [ {reference, reference_date, reference_checkpoint_date,
--                                nav, nav_prior_yr_dollars, cpi_period,
--                                cpi_basis_period, cpi_any_carried, cpi_unavailable} ]
--          -- ⚠ BOTH ARE ARRAYS, threaded on p_data_as_of via Part 1's as-of forms —
--          -- NOT the {status, reason} envelopes an earlier draft emitted. A consumer
--          -- written against that draft must be updated; this is a payload-shape
--          -- change and would be a payload_schema_version bump after merge.
--       },
--       "asset_allocation": {                -- §2.6.1 (3) <- fn_subcat_market_value + planning_target
--          "rows": [ {sub_cat_id, cat, sub_cat, market_value, target_percent} ]
--          -- target_percent is NULL when no planning_target row exists (unset is
--          -- row-absent, never a seeded zero; an explicit 0.00 is a distinct fact).
--          -- Real estate is EXCLUDED (p_include_real_estate => false), the §2.2.2
--          -- read-layer rule, which is not fenced in the table and must be applied
--          -- by every reader itself.
--       },
--       "rebalancing_targets": {             -- §2.6.1 (4) <- A1 commentary columns
--          "source_report_id": <bigint|null>,     -- Finding 4: ASSERT this
--          "cash": <text|null>, "bonds": <text|null>,
--          "marketable_securities": <text|null>, "alternatives": <text|null>,
--          "disposition": <'authored'|'skipped'|null>
--       },
--       "cash_flow": {                       -- §2.6.1 (5) <- 093 + 098
--          "cross_account_rollup": {...},        -- fn_cashflow_cross_account_rollup
--          "historical_expenditures": [ {...} ]  -- fn_historical_expenditures
--       },
--       "estimated_taxes": {                 -- §2.6.1 (6) <- fn_compute_tax_liability(104)
--          "as_of":..., "tax_year":..., "decomposition":..., "jurisdictions":...,
--          "nav_components":..., "prior_year_q4_window":...
--          -- carried VERBATIM, unflattened. basis_year and
--          -- current_year_schedule_empty travel inside jurisdictions.*.schedules.*
--          -- and are the reason the second evaluation of 104 cannot be removed.
--       }
--     }
--   }
--
--   INVARIANTS THIS FUNCTION HOLDS, each checkable from the payload alone:
--     · **ONE CALL, ONE CLOCK.** `p_data_as_of` is threaded UNCHANGED into every
--       callee; nothing derives its own date inside this body. The payload echoes
--       `as_of` so a consumer can PROVE the threading, and
--       `sections.estimated_taxes.as_of` must equal it.
--     · **NOTHING IS COLLAPSED.** Every `{status, reason}` and `{status, amount}`
--       envelope crosses as an OBJECT; `reason` stays a stable machine code;
--       `basis_year` and `current_year_schedule_empty` travel. **No coalesce, no
--       zero-fill, no currency formatting inside this function** — the TYPE does the
--       work, not consumer discipline, so a consumer writing `?? 0` receives an
--       object and fails at the first arithmetic instead of rendering "no ledger is
--       designated" as "$0 is owed". ⚠ R1 rider 1 makes this the FROZEN content, so a
--       collapse here is PERMANENT for that month.
--     · **§2.5.4's two NAV-component values render on Account Holdings via the
--       §2.1.5 buildup, NOT as Estimated Taxes rows** (PRD §2.6.1 verbatim). They
--       appear once, under `account_holdings.buildups`.
--     · **THE `unavailable` CASE IS THE BOOTSTRAP DEFAULT, NOT AN EDGE CASE.** No tax
--       ledger is designated at signup, so every new user's report is in it.
-- ============================================================================

create schema if not exists pfin;

-- ---------------- PART 1: the as-of panel readers (prerequisites) -------------

-- ----------------------------------------------------------------------------
-- The AS-OF forms. Bodies are the live catalog definitions with exactly one
-- behavioural substitution: the single clock read becomes the caller's parameter.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_delta_panel_as_of(p_data_as_of date)
 RETURNS TABLE(horizon text, anchor_date date, anchor_checkpoint_date date, current_checkpoint_date date, delta_nominal numeric, delta_percent numeric, delta_inflation_adjusted numeric, delta_inflation_adjusted_percent numeric, cpi_basis_period date, cpi_any_carried boolean, cpi_unavailable boolean)
language plpgsql
security invoker
stable
set search_path = ''
AS $function$
-- Output names collide with column names on the relations read below. Every
-- reference is table-qualified and this directive makes the resolution explicit:
-- an ambiguous bare name resolves to the COLUMN, never the output variable.
#variable_conflict use_column
declare
  v_today       date;      -- 070's answer; the ONLY clock read in this function
  v_base        date;      -- month-end AT-OR-BEFORE today. The grain anchor for
                           -- 1y/3y/5y ONLY -- NOT the month anchor; see below.
  v_cur_nav     numeric;   -- current endpoint value
  v_cur_cp      date;      -- checkpoint that served the current endpoint
  v_ye_period   date;      -- December of the prior calendar year
  v_cpi_ye      numeric;   -- basis CPI
  v_cpi_ye_c    boolean;   -- basis CPI was carried
  v_cpi_cur     numeric;   -- CPI at coverage_through ("now")
  v_cpi_cur_c   boolean;
  v_coverage    date;
  h             record;    -- per-horizon anchor
  v_a_nav       numeric;
  v_a_cp        date;
  v_cpi_a       numeric;
  v_cpi_a_c     boolean;
  v_real_base   numeric;   -- the anchor endpoint IN PRIOR-YEAR-END DOLLARS;
                           -- bound once and used by BOTH real-terms outputs
  v_adj         numeric;
  v_adj_pct     numeric;
  v_unavail     boolean;
  v_carried     boolean;
begin
  -- ONE clock read, via 070, so both sides of every comparison below use the
  -- same day (ADR-044 R2). Everything downstream is date arithmetic on a `date`
  -- and is therefore zone-free; the residual across containers is in the header.
  v_today := p_data_as_of;   -- 110 Part 1: the clock is the CALLER'S as-of, threaded

  -- The month-end AT-OR-BEFORE today, today included. `::timestamp` is
  -- zone-free (WITHOUT time zone) — the 062 idiom.
  -- ⚠ THIS FEEDS 1y/3y/5y ONLY. Its true-branch (today IS a month-end -> today
  -- is its own base) is what keeps those three anchors at EXACTLY 12/36/60
  -- months on a month-end day, and it is why this CASE is kept. The `month`
  -- horizon must NOT use it: month = base would then make the anchor and the
  -- current endpoint the same LOCF predicate and force delta 0. See the header.
  v_base := case
              when v_today = (date_trunc('month', v_today::timestamp)
                              + '1 mon'::interval - '1 day'::interval)::date
                then v_today
              else (date_trunc('month', v_today::timestamp) - '1 day'::interval)::date
            end;

  v_ye_period := (date_trunc('year', v_today::timestamp) - '1 year'::interval
                  + '11 mon'::interval)::date;   -- 1 December of the prior year

  -- Current endpoint: the caller's latest checkpoint at-or-before today.
  select nd.nav_value, nd.nav_date into v_cur_nav, v_cur_cp
  from pfin.nav_daily nd
  where nd.nav_date <= v_today
  order by nd.nav_date desc
  limit 1;

  -- Basis and "now" CPI, both through 066. coverage_through is a property of the
  -- STORE, so any non-NULL argument yields it; the CPI-U epoch is a fixed,
  -- never-NULL, zone-free probe (the 067 idiom).
  select h2.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h2;

  select h2.cpi_value, h2.is_carried into v_cpi_ye, v_cpi_ye_c
  from pfin.fn_cpi_u_index_for_period(v_ye_period) h2;

  if v_coverage is not null then
    select h2.cpi_value, h2.is_carried into v_cpi_cur, v_cpi_cur_c
    from pfin.fn_cpi_u_index_for_period(v_coverage) h2;
  end if;

  for h in
    -- Fixed order. All anchors are month-ends, so every one lands on the
    -- imported decade's grain (ADR-053 D7). 'adj' marks the horizons that carry
    -- an inflation-adjusted figure at all — month/ytd do not, BY DESIGN.
    -- ⚠ 'month' is the month-end STRICTLY BEFORE today, written INLINE rather
    -- than off v_base — deliberately, and in the same shape as the 'ytd' row
    -- directly below it, which has always been written this way. Off v_base it
    -- degenerates to the current endpoint on a month-end (delta 0 every time);
    -- 1y/3y/5y keep v_base because they need its at-or-before branch. The
    -- expression is the CASE's else-branch, now unconditional.
    select * from (values
      ('month'::text, (date_trunc('month', v_today::timestamp)
                       - '1 day'::interval)::date,                         false),
      ('ytd'::text,   (date_trunc('year', v_today::timestamp)
                       - '1 day'::interval)::date,                          false),
      ('1y'::text,    (v_base::timestamp - '12 mon'::interval)::date,       true),
      ('3y'::text,    (v_base::timestamp - '36 mon'::interval)::date,       true),
      ('5y'::text,    (v_base::timestamp - '60 mon'::interval)::date,       true)
    ) as t(name, anchor, adj)
  loop
    -- Anchor endpoint by at-or-before carry-forward (the 062 idiom). No row =
    -- the anchor predates every observation this caller has: insufficient
    -- history, reported as NULLs rather than computed against the earliest
    -- available checkpoint (which would label a two-month change "1-Year").
    select nd.nav_value, nd.nav_date into v_a_nav, v_a_cp
    from pfin.nav_daily nd
    where nd.nav_date <= h.anchor
    order by nd.nav_date desc
    limit 1;

    -- Reset EVERY per-horizon carrier each iteration — these are function-scoped
    -- variables in a loop, so a value left behind would be attributed to the
    -- next horizon.
    v_adj := null; v_adj_pct := null; v_real_base := null;
    v_unavail := null; v_carried := null;

    if h.adj then
      -- CPI pinned to the CALENDAR anchor month, never to the serving
      -- checkpoint — this is what keeps the basis reference from drifting when
      -- carry-forward reaches back (see the header).
      select h2.cpi_value, h2.is_carried into v_cpi_a, v_cpi_a_c
      from pfin.fn_cpi_u_index_for_period(
             date_trunc('month', h.anchor::timestamp)::date) h2;

      -- Strictly positive on ALL THREE legs: 053 bars NaN/±Infinity but not zero
      -- or negative, so this is the only thing standing between a poisoned print
      -- and either a raise or a sign-flipped net-worth figure.
      v_unavail := not (v_cpi_ye  is not null and v_cpi_ye  > 0
                    and v_cpi_cur is not null and v_cpi_cur > 0
                    and v_cpi_a   is not null and v_cpi_a   > 0);
      v_carried := coalesce(v_cpi_ye_c, false)
                or coalesce(v_cpi_cur_c, false)
                or coalesce(v_cpi_a_c, false);

      if not v_unavail and v_cur_nav is not null and v_a_nav is not null then
        -- THE RATIFIED FORMULA: deflate EACH endpoint into prior-year-end
        -- dollars, then subtract. Do NOT "simplify" this to a single ratio over
        -- the nominal delta — that form never deflates the current endpoint and
        -- is the defect 071 corrected.
        -- The anchor term is BOUND, not re-spelled: it is the dollar delta's
        -- subtrahend AND the percent's denominator, and binding it is what
        -- makes the two columns incapable of disagreeing about the anchor.
        v_real_base := v_a_nav * (v_cpi_ye / v_cpi_a);
        v_adj := v_cur_nav * (v_cpi_ye / v_cpi_cur) - v_real_base;

        -- The percent of the DEFLATED anchor — numerator and denominator both
        -- in prior-year-end dollars. NULL, never 0, on a non-positive base:
        -- same alike-rendering principle as delta_percent, and a negative base
        -- would invert the sign of a real-terms figure. The guard is written on
        -- THE DENOMINATOR ITSELF rather than on v_a_nav, which it is currently
        -- equivalent to under the strictly-positive CPI guard above — so it
        -- stays sound if that guard is ever reshaped.
        if v_real_base > 0 then
          v_adj_pct := v_adj / v_real_base * 100;
        end if;
      end if;
    end if;

    return query select
      h.name,
      h.anchor,
      v_a_cp,
      v_cur_cp,
      case when v_cur_nav is not null and v_a_nav is not null
           then v_cur_nav - v_a_nav end,
      -- NULL, never 0, on a zero, NEGATIVE or absent anchor. A NEGATIVE base
      -- INVERTS THE SIGN — improving from -100 to +100 would report -200%,
      -- a negative percentage for a positive improvement — which is the
      -- alike-rendering the ratified principle bars. Nominal and adjusted are
      -- arithmetically sound over a negative base and are NOT guarded here.
      case when v_cur_nav is not null and v_a_nav is not null and v_a_nav > 0
           then (v_cur_nav - v_a_nav) / v_a_nav * 100 end,
      v_adj,
      v_adj_pct,
      case when h.adj then v_ye_period end,
      v_carried,
      v_unavail;
  end loop;
end;
$function$;

create or replace function pfin.fn_nav_reference_dates_as_of(p_data_as_of date)
 RETURNS TABLE(reference text, reference_date date, reference_checkpoint_date date, nav numeric, nav_prior_yr_dollars numeric, cpi_period date, cpi_basis_period date, cpi_any_carried boolean, cpi_unavailable boolean)
language plpgsql
security invoker
stable
set search_path = ''
AS $function$
-- Output names collide with column names on the relations read below. Every
-- reference is table-qualified and this directive makes the resolution explicit:
-- an ambiguous bare name resolves to the COLUMN, never the output variable.
#variable_conflict use_column
declare
  v_today      date;      -- 070's answer; the ONLY clock read in this function
  v_prior_mth  date;      -- month-end STRICTLY BEFORE today = the prior-month
                          -- reference date. Was v_base, an at-or-before CASE.
  v_ye_period  date;      -- 1 December of the prior year — the CPI basis PERIOD
  v_ye_date    date;      -- 31 December of the prior year — the reference DATE
  v_coverage   date;      -- 066's coverage_through: the "now" CPI observation
  v_cpi_ye     numeric;   -- basis CPI value
  v_cpi_ye_c   boolean;   -- basis CPI was carried
  r            record;    -- per-reference row
  v_nav        numeric;
  v_cp         date;
  v_cpi_r      numeric;   -- this row's own reference-date CPI
  v_cpi_r_c    boolean;
  v_real       numeric;
  v_unavail    boolean;
  v_carried    boolean;
begin
  -- ONE clock read, via 070, so both sides of every comparison below use the
  -- same day (ADR-044 R2). Everything downstream is date arithmetic on a `date`
  -- and is therefore zone-free.
  v_today := p_data_as_of;   -- 110 Part 1: the clock is the CALLER'S as-of, threaded

  -- The most recent COMPLETED month-end, where COMPLETED means completed
  -- BEFORE today — the SAME expression THIS MIGRATION gives
  -- pfin.fn_nav_delta_panel's `month` anchor, which is the property that keeps
  -- the two panels reconcilable on screen. (Pointing at this migration rather
  -- than at a file number is deliberate: the sentence below names 072 as an
  -- AUTHORING HOME, and one notation must not carry both meanings here.)
  -- `::timestamp` is zone-free (WITHOUT time zone), the 062 idiom.
  -- ⚠ THE CASE THAT USED TO STAND HERE IS GONE, NOT SIMPLIFIED AWAY. Its
  -- true-branch made today its own base on a month-end, which collapsed
  -- prior_month onto this_month for the whole of those twelve days. 072 keeps
  -- an equivalent CASE (its `v_base`) because its 1y/3y/5y anchors need the
  -- at-or-before reading; this function has no multi-year row, so nothing here
  -- needs it and the variable is gone rather than left unused.
  v_prior_mth := (date_trunc('month', v_today::timestamp)
                  - '1 day'::interval)::date;

  -- Basis PERIOD (1 December, prior year) and prior-year-end reference DATE (31
  -- December, prior year). Both are pure calendar arithmetic — no 066 call — so
  -- carry-forward can move the VALUE served for the period but never the period
  -- itself. v_ye_period matches 072's basis expression exactly.
  v_ye_period := (date_trunc('year', v_today::timestamp) - '1 year'::interval
                  + '11 mon'::interval)::date;
  v_ye_date   := (date_trunc('year', v_today::timestamp) - '1 day'::interval)::date;

  -- coverage_through is a property of the STORE, so any non-NULL argument yields
  -- it; the CPI-U epoch is a fixed, never-NULL, zone-free probe (the 067 idiom).
  select h.coverage_through into v_coverage
  from pfin.fn_cpi_u_index_for_period(date '1913-01-01') h;

  -- The basis leg, read ONCE for the whole table.
  select h.cpi_value, h.is_carried into v_cpi_ye, v_cpi_ye_c
  from pfin.fn_cpi_u_index_for_period(v_ye_period) h;

  for r in
    -- Fixed order. The CPI period per row: "now" for this_month (066's
    -- coverage_through — the same observation 067/072 call now), and the
    -- first-of-month of the CALENDAR reference for the other two. Note that
    -- prior_year_end's calendar reference month IS the basis period, which is
    -- what makes that row's deflator exactly 1 — it falls out of the pinning
    -- rule and is NOT special-cased here.
    select * from (values
      ('this_month'::text,     v_today,   v_coverage),
      ('prior_month'::text,    v_prior_mth,
                               date_trunc('month', v_prior_mth::timestamp)::date),
      ('prior_year_end'::text, v_ye_date, v_ye_period)
    ) as t(name, ref_date, cpi_per)
  loop
    -- The level at this reference date by at-or-before carry-forward (the 062
    -- idiom). No row = no observation reaches this reference date: insufficient
    -- history, reported as NULLs rather than computed against the earliest
    -- available checkpoint.
    select nd.nav_value, nd.nav_date into v_nav, v_cp
    from pfin.nav_daily nd
    where nd.nav_date <= r.ref_date
    order by nd.nav_date desc
    limit 1;

    -- Reset every per-row carrier: these are function-scoped variables in a
    -- loop, so a value left behind would be attributed to the next reference.
    v_cpi_r := null; v_cpi_r_c := null; v_real := null;

    -- CPI pinned to the CALENDAR reference, never to the serving checkpoint —
    -- this is what keeps the basis reference from drifting when carry-forward
    -- reaches back (see the header). A NULL period means 066 has no coverage at
    -- all, which resolves to unavailable below rather than to an error.
    if r.cpi_per is not null then
      select h.cpi_value, h.is_carried into v_cpi_r, v_cpi_r_c
      from pfin.fn_cpi_u_index_for_period(r.cpi_per) h;
    end if;

    -- Strictly positive on BOTH legs: 053 bars NaN/+-Infinity but not zero or
    -- negative, so this is the only thing standing between a poisoned print and
    -- either a raise or a sign-flipped net-worth figure.
    v_unavail := not (v_cpi_ye is not null and v_cpi_ye > 0
                  and v_cpi_r  is not null and v_cpi_r  > 0);

    -- An OR over THIS ROW'S TWO LEGS — basis and reference. Never NULL: every
    -- row of this surface is CPI-eligible, so there is no not-applicable case.
    v_carried := coalesce(v_cpi_ye_c, false) or coalesce(v_cpi_r_c, false);

    if not v_unavail and v_nav is not null then
      -- Level deflation into prior-year-end dollars — the 067 / 072 shape. On
      -- the prior_year_end row both legs are the SAME request to 066, so this
      -- is nav x (v/v) = nav exactly. Do NOT "simplify" the three rows onto a
      -- single coverage_through observation: that is correct only for
      -- this_month, and it would silently destroy that exactness.
      v_real := v_nav * (v_cpi_ye / v_cpi_r);
    end if;

    return query select
      r.name,
      r.ref_date,
      v_cp,
      v_nav,
      v_real,
      r.cpi_per,
      v_ye_period,   -- calendar-derived; identical on all rows, never NULL
      v_carried,
      v_unavail;
  end loop;
end;
$function$;

-- ----------------------------------------------------------------------------
-- The zero-argument forms, RE-ISSUED as thin delegators so there is ONE body per
-- panel. Contract preserved exactly: same names, same RETURNS TABLE column lists,
-- same INVOKER posture, same search_path pin, `stable` RE-DECLARED because
-- CREATE OR REPLACE resets volatility. EXECUTE ACLs survive and are not re-issued.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_delta_panel()
returns table(horizon text, anchor_date date, anchor_checkpoint_date date, current_checkpoint_date date, delta_nominal numeric, delta_percent numeric, delta_inflation_adjusted numeric, delta_inflation_adjusted_percent numeric, cpi_basis_period date, cpi_any_carried boolean, cpi_unavailable boolean)
language sql
security invoker
stable
set search_path = ''
as $$
  select * from pfin.fn_nav_delta_panel_as_of(pfin.fn_server_today());
$$;

create or replace function pfin.fn_nav_reference_dates()
returns table(reference text, reference_date date, reference_checkpoint_date date, nav numeric, nav_prior_yr_dollars numeric, cpi_period date, cpi_basis_period date, cpi_any_carried boolean, cpi_unavailable boolean)
language sql
security invoker
stable
set search_path = ''
as $$
  select * from pfin.fn_nav_reference_dates_as_of(pfin.fn_server_today());
$$;

revoke execute on function pfin.fn_nav_delta_panel_as_of(date) from public;
grant  execute on function pfin.fn_nav_delta_panel_as_of(date) to authenticated;
revoke execute on function pfin.fn_nav_reference_dates_as_of(date) from public;
grant  execute on function pfin.fn_nav_reference_dates_as_of(date) to authenticated;

comment on function pfin.fn_nav_delta_panel_as_of(date) is
  'AS-OF-THREADABLE form of the PRD §2.1.3 period-delta panel (SELF-347 / A3 Finding 1; Part 1 of migration 110). Identical to pfin.fn_nav_delta_panel() in every respect EXCEPT that the anchor clock is the CALLER''S p_data_as_of instead of pfin.fn_server_today(). SECURITY INVOKER, stable, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no size is stated here). ⚠ WHY IT EXISTS: the monthly report is a FROZEN artifact and regeneration is a first-class path, so a panel anchored to the server''s today would, on a regeneration months later, freeze TODAY''S deltas into a report about a PAST month — a confident, plausible, wrong number, indistinguishable from a correct one and permanent once frozen. The report composer threads this function''s parameter from its own p_data_as_of so the panel describes the month the report is about. ⚠ WHY A DISTINCT NAME RATHER THAN AN OVERLOAD ON THE ZERO-ARGUMENT FORM: that form is called over PostgREST RPC by shipped app code with no arguments, and an overload would make an empty request body resolve against a candidate SET rather than a single function — a resolution step that does not exist today and that cannot be verified without writing to the dev database. A distinct name removes the question instead of answering it; the cost is a longer name and it is the right cost to pay. ⚠ THE BODY IS THE LIVE CATALOG DEFINITION OF THE ZERO-ARGUMENT FORM with exactly one behavioural substitution — the single clock read became the parameter — extracted with pg_get_functiondef rather than retyped, and asserted to match exactly once. That substitution is sufficient ONLY BECAUSE the body reads the clock exactly once and derives every other date from it; IF A FUTURE EDIT ADDS A SECOND CLOCK READ, THIS FUNCTION SILENTLY GOES BACK TO BEING PARTLY ANCHORED ON TODAY, which is what the paired equivalence and does-it-move battery legs exist to catch. EXECUTE revoked from public and granted to authenticated only — never to a rolbypassrls role, for which the EXECUTE grant would be the entire perimeter rather than the weakest fence.';

comment on function pfin.fn_nav_reference_dates_as_of(date) is
  'AS-OF-THREADABLE form of the PRD §2.1.4 reference-date panel (SELF-347 / A3 Finding 1; Part 1 of migration 110). Identical to pfin.fn_nav_reference_dates() except that the anchor clock is the CALLER''S p_data_as_of instead of pfin.fn_server_today(). SECURITY INVOKER, stable, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). Same provenance, same rationale and same standing hazard as pfin.fn_nav_delta_panel_as_of(date): body extracted from the live catalog definition with one asserted-unique substitution, sufficient only while the body reads the clock exactly once. See that function''s comment for the full reasoning, including why this is a distinct name rather than an overload on the zero-argument form. EXECUTE revoked from public and granted to authenticated only.';

comment on function pfin.fn_nav_delta_panel() is
  'PRD §2.1.3 period-delta panel, anchored on the SERVER''S TODAY. ⚠ RE-ISSUED IN PART 1 OF MIGRATION 110 AS A THIN DELEGATOR: its logic now lives in pfin.fn_nav_delta_panel_as_of(date), and this function supplies pfin.fn_server_today() to it. THE CONTRACT IS UNCHANGED — same name, same RETURNS TABLE columns, same SECURITY INVOKER posture, same search_path pin, same EXECUTE ACL (CREATE OR REPLACE preserves it, so 112 re-issues no grant here) — and callers, including the PostgREST RPC path in the app, are unaffected. WHY DELEGATE RATHER THAN LEAVE THIS BODY ALONE: the monthly report needs an as-of-threadable form, and the alternative was TWO COPIES OF THE SAME FINANCIAL ARITHMETIC on the tree that would have to agree forever. There is now one body per panel. ⚠ VOLATILITY IS RE-DECLARED stable IN THIS RE-ISSUE BECAUSE CREATE OR REPLACE RESETS IT; omitting the declaration would have silently dropped the pin, invisible to every value assertion. A battery leg asserts this function equals pfin.fn_nav_delta_panel_as_of(pfin.fn_server_today()) column-for-column — that equivalence is what makes the delegation provably behaviour-preserving rather than merely plausible.';

comment on function pfin.fn_nav_reference_dates() is
  'PRD §2.1.4 reference-date panel, anchored on the SERVER''S TODAY. ⚠ RE-ISSUED IN PART 1 OF MIGRATION 110 AS A THIN DELEGATOR onto pfin.fn_nav_reference_dates_as_of(date), which now holds the logic. THE CONTRACT IS UNCHANGED — same name, same RETURNS TABLE columns, same SECURITY INVOKER posture, same search_path pin, same EXECUTE ACL — so the shipped PostgREST RPC call for this function resolves and behaves exactly as before. Volatility is re-declared stable because CREATE OR REPLACE resets it. See pfin.fn_nav_delta_panel() for the full delegation rationale; a battery leg asserts this function equals its _as_of form at fn_server_today(), column-for-column.';

-- ---------------- PART 2: the read-composition helper -------------------------

create or replace function pfin.fn_render_monthly_report(
  p_target_month date,
  p_data_as_of   date
)
returns jsonb
language sql
security invoker
stable
set search_path = ''
as $$
  with
  -- The draft row this composition is FOR (Finding 4). Deterministic: the highest
  -- report_id in `draft` for (auth.uid(), p_target_month). RLS scopes it to the
  -- caller, so no users_id predicate is written here and none should be added — an
  -- explicit one on an INVOKER helper is the p_users_id trap wearing a WHERE clause.
  draft_row as (
    select r.report_id,
           r.commentary_cash,
           r.commentary_bonds,
           r.commentary_marketable_securities,
           r.commentary_alternatives,
           r.commentary_disposition
      from pfin.monthly_report r
     where r.target_month      = p_target_month
       and r.generation_status = 'draft'
     order by r.report_id desc
     limit 1
  ),

  -- §2.6.1 (2) — the AS-OF-THREADABLE half of NAV Performance. Bounded by the
  -- as-of, never by a reader-derived clock. The window opens at the start of the
  -- target month's preceding 12 months so the series has context; it CLOSES at the
  -- as-of, which is what makes it reproducible on a regeneration.
  nav_series as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'point_date',      s.point_date,
             'nav_value',       s.nav_value,
             'checkpoint_date', s.checkpoint_date
           ) order by s.point_date), '[]'::jsonb) as j
      from pfin.fn_nav_series(
             'monthly',
             (date_trunc('month', p_target_month) - interval '11 months')::date,
             p_data_as_of
           ) s
  ),
  nav_series_infl as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'point_date',                s.point_date,
             'nav_nominal',               s.nav_nominal,
             'checkpoint_date',           s.checkpoint_date,
             'nav_inflation_adjusted',    s.nav_inflation_adjusted,
             'cpi_period',                s.cpi_period,
             'cpi_value',                 s.cpi_value,
             'cpi_is_carried',            s.cpi_is_carried,
             'cpi_carried_from',          s.cpi_carried_from,
             'cpi_period_was_due',        s.cpi_period_was_due,
             'cpi_nonpublication_on_record', s.cpi_nonpublication_on_record,
             'cpi_coverage_through',      s.cpi_coverage_through
           ) order by s.point_date), '[]'::jsonb) as j
      from pfin.fn_nav_series_inflation_adjusted(
             'monthly',
             (date_trunc('month', p_target_month) - interval '11 months')::date,
             p_data_as_of
           ) s
  ),

  -- §2.6.1 (3) — Asset Allocation. Real estate EXCLUDED (the §2.2.2 read-layer
  -- rule, which is not fenced in the table and must be applied by every reader).
  -- planning_target is read as a plain RLS-protected table; there is no reader
  -- helper. Unset is ROW-ABSENT, so the LEFT JOIN yields NULL and is NOT coalesced
  -- to zero — an explicit 0.00 is a distinct storable fact and must stay distinct.
  allocation as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'sub_cat_id',     m.sub_cat_id,
             'cat',            m.cat,
             'sub_cat',        m.sub_cat,
             'market_value',   m.market_value,
             'target_percent', pt.target_percent
           ) order by m.cat, m.sub_cat), '[]'::jsonb) as j
      from pfin.fn_subcat_market_value(p_data_as_of, false) m
      left join pfin.planning_target pt on pt.sub_cat_id = m.sub_cat_id
  ),

  -- §2.6.1 (2) — the §2.1.3 / §2.1.4 panels, THREADED. Part 1's as-of forms are the
  -- reason this section is complete rather than an unavailable envelope: the
  -- zero-argument forms read the server's today internally and would have frozen
  -- TODAY's panel into a report about a past month on every regeneration.
  delta_panel as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'horizon',                          d.horizon,
             'anchor_date',                      d.anchor_date,
             'anchor_checkpoint_date',           d.anchor_checkpoint_date,
             'current_checkpoint_date',          d.current_checkpoint_date,
             'delta_nominal',                    d.delta_nominal,
             'delta_percent',                    d.delta_percent,
             'delta_inflation_adjusted',         d.delta_inflation_adjusted,
             'delta_inflation_adjusted_percent', d.delta_inflation_adjusted_percent,
             'cpi_basis_period',                 d.cpi_basis_period,
             'cpi_any_carried',                  d.cpi_any_carried,
             'cpi_unavailable',                  d.cpi_unavailable
           ) order by d.horizon), '[]'::jsonb) as j
      from pfin.fn_nav_delta_panel_as_of(p_data_as_of) d
  ),
  reference_dates as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'reference',                  r.reference,
             'reference_date',             r.reference_date,
             'reference_checkpoint_date',  r.reference_checkpoint_date,
             'nav',                        r.nav,
             'nav_prior_yr_dollars',       r.nav_prior_yr_dollars,
             'cpi_period',                 r.cpi_period,
             'cpi_basis_period',           r.cpi_basis_period,
             'cpi_any_carried',            r.cpi_any_carried,
             'cpi_unavailable',            r.cpi_unavailable
           ) order by r.reference), '[]'::jsonb) as j
      from pfin.fn_nav_reference_dates_as_of(p_data_as_of) r
  ),

  -- §2.6.1 (5) — Cash Flow. Both readers threaded with the same as-of.
  expenditures as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'month_end',                            e.month_end,
             'expense_monthly_nominal',              e.expense_monthly_nominal,
             'expense_monthly_inflation_adjusted',   e.expense_monthly_inflation_adjusted,
             'rolling_12mo_avg_inflation_adjusted',  e.rolling_12mo_avg_inflation_adjusted,
             'cpi_period',                           e.cpi_period,
             'cpi_value',                            e.cpi_value,
             'cpi_is_carried',                       e.cpi_is_carried,
             'cpi_carried_from',                     e.cpi_carried_from,
             'cpi_period_was_due',                   e.cpi_period_was_due,
             'cpi_nonpublication_on_record',         e.cpi_nonpublication_on_record,
             'cpi_coverage_through',                 e.cpi_coverage_through
           ) order by e.month_end), '[]'::jsonb) as j
      from pfin.fn_historical_expenditures(p_data_as_of) e
  )

  select jsonb_build_object(
    'payload_schema_version', 1,
    'target_month',           p_target_month,
    'as_of',                  p_data_as_of,
    'sections', jsonb_build_object(

      -- (1) Account Holdings. Carried VERBATIM — including the two §2.5.4 envelope
      -- objects at buildups.realized_tax_liab / buildups.unrealized_tax_liab, which
      -- is the ONLY source this function uses for those scalars. Re-invoking 104 for
      -- them would be a third evaluation buying nothing.
      'account_holdings', pfin.fn_nav_composition(p_data_as_of),

      -- (2) NAV Performance. ALL FOUR readers are as-of-threaded — Part 1 gave the
      -- §2.1.3 and §2.1.4 panels as-of forms, closing Finding 1. Nothing in this
      -- section derives its own clock any more.
      'nav_performance', jsonb_build_object(
        'series',                    (select j from nav_series),
        'series_inflation_adjusted', (select j from nav_series_infl),
        'delta_panel',     (select j from delta_panel),
        'reference_dates', (select j from reference_dates)
      ),

      -- (3) Asset Allocation.
      'asset_allocation', jsonb_build_object('rows', (select j from allocation)),

      -- (4) Rebalancing Targets — A1's commentary columns. source_report_id is
      -- echoed so the caller can ASSERT it is the row it is about to write (Finding 4).
      'rebalancing_targets', jsonb_build_object(
        'source_report_id',      (select report_id from draft_row),
        'cash',                  (select commentary_cash from draft_row),
        'bonds',                 (select commentary_bonds from draft_row),
        'marketable_securities', (select commentary_marketable_securities from draft_row),
        'alternatives',          (select commentary_alternatives from draft_row),
        'disposition',           (select commentary_disposition from draft_row)
      ),

      -- (5) Cash Flow.
      'cash_flow', jsonb_build_object(
        'cross_account_rollup',    pfin.fn_cashflow_cross_account_rollup(p_data_as_of),
        'historical_expenditures', (select j from expenditures)
      ),

      -- (6) Estimated Taxes. Carried VERBATIM and unflattened. THIS is the second
      -- and structurally-final evaluation of fn_compute_tax_liability: basis_year,
      -- current_year_schedule_empty, decomposition, jurisdictions and
      -- prior_year_q4_window appear NOWHERE in fn_nav_composition's payload, and
      -- AC 6 requires them to travel.
      'estimated_taxes', pfin.fn_compute_tax_liability(p_data_as_of)
    )
  );
$$;

revoke execute on function pfin.fn_render_monthly_report(date, date) from public;
grant  execute on function pfin.fn_render_monthly_report(date, date) to authenticated;
