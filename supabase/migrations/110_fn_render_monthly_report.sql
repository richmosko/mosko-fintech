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
--   **OPTIONS, WITH THE ONE TAKEN AND WHY:**
--     (α) **TAKEN, for this migration.** Compose NAV Performance from the
--         AS-OF-THREADABLE readers only (`fn_nav_series` +
--         `fn_nav_series_inflation_adjusted`, both bounded by `p_data_as_of`), and
--         EMIT THE §2.1.3 / §2.1.4 SECTIONS AS AN EXPLICIT `unavailable` ENVELOPE
--         CARRYING A STABLE MACHINE CODE — `reader_not_as_of_threadable`. **The
--         report says the panel is absent and why; it does not silently omit it and
--         it does not print a wrong one.** Cost, named: the §2.6.1 NAV Performance
--         section is incomplete against AC 4 until (γ) lands.
--     (β) **NOT TAKEN.** Call them anyway and accept a today-anchored panel. Rejected
--         on the reasoning above — it is the fabrication-shaped-like-a-measurement
--         failure, made permanent by the freeze.
--     (γ) **THE REAL FIX, AND IT IS F/CTO's CALL BECAUSE IT WIDENS THIS PR.** Add an
--         as-of parameter to both readers so they can be threaded. ⚠ **It is NOT a
--         free additive change:** `fn_nav_delta_panel()` takes zero arguments, so
--         adding `p_as_of date default …` creates an AMBIGUOUS zero-argument call
--         against the existing signature; the old signature must be DROPPED, which
--         **invalidates every `regprocedure`-anchored assertion in other files'
--         batteries** and re-opens two shipped financial read surfaces under Sec
--         review. That is a real cost on real files, which is why it is not taken
--         unilaterally inside a migration whose subject is a different table.
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
--   no opinion about who calls it. What is owed is a P2/P5 decision on how the draft
--   view is rendered (compose-on-open, compose-on-explicit-refresh, or a draft-scoped
--   cache), and it is NOT a schema question.
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
--   7. The §2.1.3 / §2.1.4 sections carry the `reader_not_as_of_threadable`
--      envelope (Finding 1, option α) — asserted so that closing Finding 1 REDS this
--      leg and forces the payload contract to be re-read.
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
--   **THE ACTUAL FIX, RECOMMENDED AND NOT TAKEN HERE:** a second partial unique index
--   on `108` — `unique (users_id, target_month) where generation_status = 'draft'` —
--   which makes *"the draft for this month"* well-defined and makes the ruled
--   signature coherent by construction. **It is not added unilaterally because it is
--   PRODUCT-VISIBLE: a second Regenerate click would fail 23505 instead of creating a
--   draft, and no ruling covers that.** It is one line in `108` if F/CTO says yes.
--   ⚠ Recorded rather than papered over, because *"pending = draft"* (the R10
--   presentation bridge) is phrased in the singular and reads as though the
--   guarantee already exists.
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
--          "delta_panel":     {"status":"unavailable","reason":"reader_not_as_of_threadable"},
--          "reference_dates": {"status":"unavailable","reason":"reader_not_as_of_threadable"}
--          -- ⚠ the last two are Finding 1. They are ABSENT-WITH-A-REASON, never
--          -- silently omitted and never today-anchored.
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

      -- (2) NAV Performance. See Finding 1: two of the three named readers derive
      -- their own clock and cannot be threaded, so they are ABSENT-WITH-A-REASON
      -- rather than today-anchored. The reason is a STABLE MACHINE CODE.
      'nav_performance', jsonb_build_object(
        'series',                    (select j from nav_series),
        'series_inflation_adjusted', (select j from nav_series_infl),
        'delta_panel',     jsonb_build_object('status', 'unavailable',
                                              'reason', 'reader_not_as_of_threadable'),
        'reference_dates', jsonb_build_object('status', 'unavailable',
                                              'reason', 'reader_not_as_of_threadable')
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
