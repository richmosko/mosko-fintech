-- ============================================================================
-- Migration: pfin.nav_component_daily — the NAV component-checkpoint capture
--   substrate. An append-only audit-class SIBLING of pfin.nav_daily (054) holding
--   ONE ROW PER (user, day, ACCOUNT): the per-account leaf value that the scalar
--   checkpoint aggregates. Written by the SAME W-1 cron worker, in the SAME
--   transaction, under the SAME credential model (055). Phase 6 Build Loop,
--   Linear SELF-353 / A9. Realizes ADR-054 Decision 1 (Option C: capture-only
--   substrate in V1.x; visualization and sheet-history import in V2).
--   apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface) — FOUR independent triggers,
--   enumerated at ADR-054's Governance block: a new tenant-scoped audit-class
--   financial table + new RLS + a cron write-path extension + an ADR-011
--   Decision 3 family extension. Read that block; it is not restated here.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT.
--   DOES: creates one table, four SECURITY INVOKER fences, one RLS SELECT policy,
--     three grants. That is the whole surface.
--   DOES NOT: no read helper, no view, no function returning these rows, no UI,
--     no backfill, no chart, no import path. ADR-054 Decision 5(1) CLOSED the
--     read-helper question — ruled FORBIDDEN in V1.x — and the reasoning is the
--     ADR's: a helper is fence cost with no consumer. The V2 visualization is the
--     first consumer and it ships with its own read surface.
--
--   ⚠ "CAPTURE-ONLY" IS NOT "UNREADABLE BY ITS OWNER", and the distinction is
--     worth stating because a reviewer will reasonably ask. Decision 5(1) forbids
--     a READ HELPER — a function, with its own contract, grants and battery.
--     It does not make the table's own rows invisible to the tenant that owns
--     them: this file ships an owner-only SELECT policy, exactly as 054 does
--     ("read by the owning user", ADR-054 Decision 1). That policy is ALSO what
--     makes the aal2 step-up backstop applicable rather than excluded — see the
--     aal2 block below. A table with zero authenticated policy would fall into
--     025 exclusion (ii) and would carry NO aal2 clause, which is the opposite of
--     what this issue's AC requires.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE CAPTURE SOURCE IS 049, **NOT** fn_nav_composition. READ THIS BEFORE
--   WRITING THE WORKER. This is the single most load-bearing statement in the
--   file, and getting it wrong makes the reconciliation property below false on
--   day one rather than by future drift.
--
--   ADR-054 Decision 3 names `051` (fn_nav_composition) as the function that
--   "already emits per-account leaf values", and it did, on 2026-08-12. Since
--   then that function was REPLACED — at 102 and again at 105 — and it now
--   ANTI-JOINS OUT every tax-authority-designated ledger via
--   pfin.fn_tax_authority_ledgers(). pfin.nav_daily.nav_value is
--   fn_compute_nav(current_date, true), which keeps its GROSS definition and
--   still INCLUDES those ledgers (105's own comment says so, and ADR-067
--   Decision 3 makes nav_daily the gross pre-tax series PERMANENTLY).
--
--   CONSEQUENCE, arithmetic rather than stylistic:
--       Σ(fn_nav_composition leaves)  =  nav_daily.nav_value  −  Σ(designated
--                                        tax-authority ledger balances)
--   so a worker capturing fn_nav_composition's leaves would produce a series that
--   FAILS the AC-6 reconciliation for every user who has designated a ledger, and
--   passes for every user who has not — a divergence that looks like a data bug
--   and is actually a source-selection bug.
--
--   THE CORRECT SOURCE IS pfin.fn_account_unrealized_gl(p_as_of) (049, live body
--   re-issued at 056; leaf set re-predicated at 059), column
--   `current_market_value`, naturally signed. That is the SINGLE LEAF SUBSTRATE
--   fn_nav_composition itself composes on, and Σ over its rows is
--   fn_compute_nav(p_as_of, true) EXACTLY (ADR-038 as tightened by ADR-039 /
--   SELF-322). It is also a plain relational result rather than a JSONB tree, so
--   the worker parses nothing.
--
--   RECORDED AS A FINDING, NOT AS A CORRECTION OF THE ADR: ADR-054 Decision 3's
--   sentence was true when written and is a dated record. The AC's coherence note
--   checked A9 against 105 on the DEFINITION axis ("cannot drift from 105's
--   definition because it never renders") and that check is sound; the LEAF-SET
--   axis is a different axis and was not checked. This block is that check.
--
-- ----------------------------------------------------------------------------
-- WHY A SIBLING TABLE AND NOT COLUMNS ON 054 — ADR-054 Decision 2, a RATIFIED
--   NEVER-ITEM. Not restated here beyond the one consequence that binds this
--   file: 054 is append-only, so a column added to it would give EVERY EXISTING
--   ROW a value nobody measured. The three reasons (surface widening, the
--   retroactive claim, independent failure modes) live at the ADR.
--
--   ⚠ ONE TENSION, STATED RATHER THAN LEFT FOR A REVIEWER TO FIND. Decision 2's
--     third bullet says the two series "should be able to fail independently — a
--     component-capture bug must not be able to corrupt or block the scalar NAV
--     checkpoint". AC 2 and Decision 1 require the SAME TRANSACTION. These pull
--     in opposite directions and the resolution is deliberate:
--       · SAME TRANSACTION IS LOAD-BEARING and is not negotiable here. It is the
--         entire reason Σ(leaves) = scalar holds BY CONSTRUCTION rather than by
--         hope: both figures are frozen from one substrate at one instant. Split
--         the transaction and the reconciliation property — the thing AC 6 asks
--         QA to watch — stops being a property.
--       · DECISION 2's INDEPENDENCE ARGUMENT IS ABOUT THE SURFACE, not the write
--         transaction. Its three bullets are all arguments against WIDENING 054's
--         table: a column on 054 could not fail independently in any sense,
--         because it would be the same row. A sibling table can be dropped,
--         re-shaped, or have its writer removed without touching 054's DDL at all.
--       · THE RESIDUAL IS REAL AND IS NOT ARGUED AWAY: a leaf-side raise DOES
--         roll back that tenant's scalar checkpoint for that day. This file
--         therefore minimises the ways the leaf side can raise — see FAIL
--         SURFACE below — but it does not reduce them to zero, and it must not
--         (the tenant fences MUST raise). Flagged to Sec and F/CTO rather than
--         resolved unilaterally.
--
-- ----------------------------------------------------------------------------
-- FAIL SURFACE — every way an INSERT here can raise, enumerated, because each one
--   is a way the scalar checkpoint can be lost for that tenant-day (see the
--   tension above). There are exactly five, and four of them are fences that MUST
--   raise:
--     (1) nav_component_daily_assert_computed_for  — write-tenant binding (054's
--         GUC, reused). MUST raise.
--     (2) nav_component_daily_matched_account      — ADR-011 Decision 3 #19
--         matched-tenant. MUST raise.
--     (3) nav_component_daily_value_finite         — NaN / ±Infinity. MUST raise;
--         a poisoned leaf is worse than a missing day.
--     (4) the users_id / account_id FKs            — MUST raise.
--     (5) 23505 on the UNIQUE                      — the ONLY avoidable one, and
--         the worker's contract avoids it two ways: it writes leaves ONLY when
--         the scalar INSERT actually inserted (see WORKER CONTRACT), and its
--         statement uses the TARGETED `on conflict (users_id, nav_date,
--         account_id) do nothing` so a partially-written prior state no-ops
--         instead of aborting. 054's own B9 ruling is why the form is targeted
--         rather than bare, and why the arbiter columns carry a column-level
--         SELECT grant.
--   NO OTHER CONSTRAINT IS ADDED. In particular there is NO CHECK enforcing the
--   reconciliation identity — see PARITY, NOT INVARIANT below; a cross-table
--   aggregate CHECK on the nightly cron path is exactly the shape ADR-054
--   Decision 5 rejected.
--
-- ----------------------------------------------------------------------------
-- WRITE-PATH CREDENTIAL MODEL — INHERITED VERBATIM FROM 054/055, NOT RE-DECIDED.
--   LOGIN role = `pfin_etl` (055; NOINHERIT broker, not superuser, not BYPASSRLS,
--   not the pfin owner, owns nothing, holds no direct table privilege; member of
--   service_role + authenticated). WRITE role = `service_role`, reached via
--   `SET LOCAL ROLE service_role` inside the transaction (ADR-023; SD-24).
--   `service_role` is rolcanlogin = f and can never be a login identity — the
--   worker LOGS IN as pfin_etl and WRITES AS service_role.
--   WHY IT MAKES THIS FILE'S FENCES REAL, in one line each:
--     · the INSERT grant below is the privilege that admits the write (service_role
--       is neither owner nor superuser, so ownership does not admit it);
--     · service_role can neither `ALTER TABLE … DISABLE TRIGGER` (must be owner)
--       nor set `session_replication_role` (must be superuser) — 055 states these
--       are the only two ways to suppress a trigger — so the fences below are
--       un-bypassable BY THE WRITER;
--     · under an owner-class login both inversions hold and the fences can be
--       suppressed. That is a KNOWN LIMIT of trigger-realized controls, catalogued
--       at SECURITY §4.4 SD-24 / §4.5 RT-31 and generalised at ADR-011 Decision 4's
--       2026-09-03 amendment. It is why the ratified login role is not owner-class.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — THIS MIGRATION EXTENDS THE FAMILY. The new
--   `account_id` column is an FK-shaped reference on a tenant-scoped table, so
--   matched-tenant validation in the DDL is NON-NEGOTIABLE (ADR-054 Decision 4
--   says so, and says it lands either way — a category-keyed schema would have
--   referenced user_taxonomy and been equally in the family; there is no
--   granularity choice that avoids it).
--
--   Decision 3's body was read LIVE at authoring (2026-09-05), not from memory or
--   from any derived surface. NO COUNT IS CARRIED IN THIS FILE — the family grows,
--   its labels are non-contiguous, one is DROPPED, and *labeled* versus
--   *DDL-realized* diverge. Read the ADR.
--
--   LABEL TAKEN: **#19**, read from Decision 3's own body at authoring, where two
--   forward pointers (the #10 entry and the #17 entry) then named it as the next
--   allocation. ⚠ THOSE POINTERS ARE RETIRED IN THIS SAME PR RATHER THAN ADVANCED
--   TO #20 — the shape Sec ruled at the SELF-259 joint-review, because a pointer
--   that survives its own allocation rebuilds the #16 trap one allocation later.
--   So the next author will find NO number named there and must read the numbered
--   list. That is deliberate; it is not a missing pointer. The fold-in of #19 into Decision 3's
--   numbered list ships IN THIS SAME PR, as a separate labelled commit — per the
--   rule Decision 3's own 2026-08-04 fold-in resolution wrote after the #15 and
--   #16 slips: *the fold-in is due in the PR THAT DDL-REALIZES THE INSTANCE, not
--   at the next reconciliation.* A migration asserting a label whose canon does
--   not yet contain it ships a forward reference to a document it does not
--   control, and converts an un-folded instance into an apparent fabrication for
--   the next reviewer obeying the read-Decision-3-live discipline.
--
--   *** THE FENCE IS A TRIGGER, NOT AN RLS `WITH CHECK`, AND THAT IS FORCED. ***
--   Decision 3 sanctions BOTH forms and names WITH CHECK first for single
--   columns, so a reader may expect one here. A `WITH CHECK` is an RLS POLICY
--   clause: it is evaluated for roles subject to RLS and is NOT evaluated for a
--   `rolbypassrls` role. **The sole writer of this table is `service_role`, which
--   carries rolbypassrls.** A WITH CHECK realization would therefore be VACUOUS
--   against the only writer that exists — the exact class ADR-042 Decision 5a
--   identified for #16 (`account_event.account_id`, 057) and the reason that
--   instance is BEFORE INSERT trigger-realized. #19 copies #16's shape for #16's
--   reason. ⚠ The corollary, stated because it is the cost: being trigger-realized,
--   #19 goes inert under `session_replication_role = replica` together with the
--   FK it backstops (Decision 4's 2026-09-03 amendment), and for the RLS-exempt
--   writer that takes the applicable-layer count to ZERO, not to one. That GUC is
--   superuser-context and is denied to both service_role and authenticated
--   (measured at 054 and re-measured at SELF-257), so it is not tenant-reachable;
--   the exposure is operational — any restore / bulk-load / replication runbook
--   that sets it owes an explicit post-load validation step over this table.
--
--   THE SECOND FK-SHAPED COLUMN, `users_id`, IS **NOT** A DECISION-3 INSTANCE, on
--   054's own reasoning: it is the table's OWN SOLE tenant anchor under a direct
--   RLS predicate (users_id = auth.uid()), identical in shape to 024
--   user_settings.users_id / 009 user_taxonomy.users_id. There is no second
--   anchor for it to mismatch, so there is nothing to validate. One column joins
--   the family here, not two.
--
--   NO FK TO pfin.nav_daily, AND THE OMISSION IS DELIBERATE. Anchoring a leaf to
--   `nav_daily.nav_id` would make the 1:1 correspondence structural and would make
--   a same-day re-run naturally inert. It is NOT taken because (a) ADR-054
--   Decision 5 states the reconciliation key in its own words — *"for a given
--   `(users_id, date)`, Σ(leaf values) reconciles with the scalar `nav_daily`
--   checkpoint"* — so (users_id, nav_date) is the ratified join, and (b) a
--   nav_id FK would be a SECOND Decision 3 family member in one migration, since
--   nav_daily carries its own users_id and both sides are per-user. Two labels
--   and two fences to buy a property the worker contract already provides is the
--   wrong trade. Recorded as the named losing side, not omitted silently.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 2 — WHICH HALF APPLIES, AND WHICH HALF DOES NOT. Decision 2
--   has two halves and a bare "D2 applies" would claim both.
--   APPLIES: rows are append-only at the RLS-policy AND DB-trigger layer, with
--     UPDATE / DELETE / TRUNCATE blocked across BOTH `authenticated` and
--     `service_role` (service_role bypasses RLS but NOT triggers). The audit trail
--     is the table itself; there is no separate audit table.
--   DOES **NOT** APPLY: *"'Updates' become NEW rows with explicit relationship to
--     predecessor (FK or status ENUM)."* THERE IS NO CORRECTION PATH ON THIS
--     TABLE AND THERE IS NOT MEANT TO BE. A row here is a CAPTURED OBSERVATION of
--     what one account was worth at one day's close — a measurement, not an
--     assertion that can be restated. Lock 10's reverse-and-replace and Lock 11's
--     draft→final→superseded both exist because a REPORT can be regenerated from
--     the same facts; an OBSERVATION cannot be re-observed after the day has
--     passed. There is therefore no `replaces_*` FK, no `generation_status`, and
--     no version column, and adding one later would not create a correction path —
--     it would create a way to publish a second, later-computed claim about a past
--     day with the shape of a measurement. That is the fabrication hazard ADR-053
--     Decision 1 and 062's header are both built around, and it is the same reason
--     105 records that nav_daily is not back-filled.
--   ⚠ CONSEQUENCE, so it is not discovered later: a leaf written WRONG is
--     permanent. No role can UPDATE or DELETE it; removing it would require a
--     migration that drops or disables a trigger. That irreversibility is the
--     first of the four reasons 054 gives for fencing its write path at the DB
--     layer, and it is why this file reuses that fence rather than trusting the
--     worker.
--
-- ----------------------------------------------------------------------------
-- PER-ACCOUNT LEAF GRANULARITY + THE GROWTH COMMITMENT (ADR-054 Decision 3,
--   Architect's call, ratified).
--   THE ARGUMENT, in one line: a leaf capture is re-aggregatable retroactively
--   under ANY taxonomy; a pre-rolled category capture is not — and on an
--   append-only table that asymmetry is PERMANENT.
--   THE GROWTH COMMITMENT, STATED RATHER THAN DISCOVERED (the ADR's own words are
--   "a growth commitment, not a free choice"): this table gains ONE ROW PER
--   ACTIVE ACCOUNT PER USER PER DAY, every day, forever, and none of them can ever
--   be deleted. Row count therefore scales with account count × user count × days
--   elapsed and is strictly monotonic. It is bounded and cheap at V1 scale. It is
--   the price of not guessing the taxonomy, and it is not reversible by any means
--   short of a migration that removes the immutability fences.
--   NO CATEGORY / TAXONOMY COLUMN IS STORED, and that is the point: `051`'s
--   `category` output is literally `a.account_type` (an ACCOUNT-TYPE cut), while
--   the incumbent sheet's legend is ASSET-CLASS (a cut that crosses accounts and
--   lives in user_taxonomy / user_asset_category territory). Storing either would
--   silently pick one before the Chart-of-Accounts question is answered.
--   ADR-054 Decision 6 makes that orthogonality structural, and it stays
--   structural only while this table stores no taxonomy.
--
-- ----------------------------------------------------------------------------
-- PARITY, NOT INVARIANT — AC 7 / ADR-054 Decision 5(2), RULED: the sheet identity
--   is a DOCUMENTED PARITY PROPERTY, not a schema-enforced invariant. The F/CTO
--   rider recorded at that ruling is NOT restated here; read it at the ADR (Path B
--   — a rider quoted into a migration is a second copy that cannot be amended).
--   WHY NO CHECK CONSTRAINT, in the ADR's own reasoning: the property holds BY
--   CONSTRUCTION today (both figures derive from one substrate in one transaction),
--   a constraint enforcing a by-construction equality CAN NEVER FIRE, and it would
--   convert a future derivation drift into a NIGHTLY OUTAGE instead of a report.
--   What deserves a watcher is whether the property STAYS by-construction — hence
--   QA's battery leg, below.
--
-- ----------------------------------------------------------------------------
-- THE RECONCILIATION QA WATCHES (AC 6) — stated here so the leg is measurable
--   without re-deriving it:
--
--     for a given (users_id, nav_date):
--       SUM(pfin.nav_component_daily.component_value)  =  pfin.nav_daily.nav_value
--
--   LEFT SIDE  — every leaf row for that (users_id, nav_date), summed with NATURAL
--     SIGNS (liability leaves are naturally NEGATIVE; 049 R-7 / 051's DEBT-SIGN
--     D-1). No abs, no negation, no filtering by account_type.
--   RIGHT SIDE — the `nav_value` column of pfin.nav_daily (054), the GROSS PRE-TAX
--     scalar. NOT fn_nav_composition's `nav`, which subtracts the tax envelopes AND
--     excludes designated tax-authority ledgers; NOT fn_compute_nav re-called at
--     read time, which would re-derive rather than compare what was frozen.
--   WHY IT HOLDS TODAY: both sides are frozen in the same transaction from the same
--     substrate — Σ over 049(as_of).current_market_value IS fn_compute_nav(as_of,
--     true) exactly (ADR-038 / ADR-039), and nav_value is that call's result.
--   ⚠ THE COUPLING THE EQUALITY QUIETLY DEPENDS ON: it holds only while BOTH sides
--     apply the SAME account-set filter — today, 049's as-of predicate
--     (`closed_at is null or closed_at::date > p_as_of`; the boolean flag was
--     retired at 059) which fn_compute_nav shares. Change either filter
--     independently and the reconciliation breaks for reasons that have nothing to
--     do with capture. THAT is what the battery leg exists to say.
--   ⚠ AND THE OTHER WAY IT CAN BREAK, which is a worker-contract property rather
--     than a schema one: a same-day RE-RUN whose account set has changed. The
--     scalar's `on conflict do nothing` keeps the FIRST value while a new account's
--     leaf would insert fresh, and Σ would then exceed it. The worker contract
--     below closes this by writing leaves ONLY when the scalar INSERT actually
--     inserted. There is no DDL that can enforce that, which is precisely why it is
--     written into the contract and why the battery leg is the watcher.
--
-- ----------------------------------------------------------------------------
-- WORKER CONTRACT (Backend, workers/etl — NOT this file). Four obligations; all
--   four are load-bearing and none is optional.
--
--   (W1) SOURCE. Read leaves from `pfin.fn_account_unrealized_gl(<the same as-of
--        the scalar used>)`, taking `account_id` and `current_market_value`. NOT
--        fn_nav_composition — see the capture-source block above. Read it INSIDE
--        the impersonated block, under the tenant's own RLS, exactly as
--        fn_compute_nav is read.
--
--   (W2) GUC. The transaction-local GUC `app.nav_computed_for` — the SAME GUC 054
--        pins, set the SAME way, from `auth.uid()` AS THE DATABASE RESOLVED IT and
--        never from the application's own variable — must be set before either
--        INSERT. ONE binding covers BOTH tables. It is deliberately NOT a second,
--        table-specific GUC: two GUCs could disagree, and a disagreement between
--        them would mean the two rows of one checkpoint were bound to different
--        tenants — which is the exact failure the fence exists to prevent. The
--        name is PINNED: `app.nav_computed_for`, exact.
--
--   (W3) ORDER AND CONDITION. INSERT the scalar row into pfin.nav_daily FIRST,
--        with `returning nav_id`. Write the leaves ONLY IF that INSERT actually
--        returned a row. On a same-day re-run the scalar's `on conflict (users_id,
--        nav_date) do nothing` returns NOTHING, and the correct behaviour is to
--        write NO leaves — the day is already captured. This is what keeps
--        Σ(leaves) = nav_value across re-runs when the account set has changed
--        between runs. (`nav_id` is used ONLY as the did-it-insert signal; it is
--        NOT stored here — there is no nav_id column and no FK, deliberately.)
--
--   (W4) STATEMENT. One multi-row INSERT, in the SAME transaction as the scalar,
--        executing AS service_role:
--            insert into pfin.nav_component_daily
--              (users_id, nav_date, account_id, component_value)
--            values (…), (…), …
--            on conflict (users_id, nav_date, account_id) do nothing
--        The `on conflict` target is TARGETED, not bare — 054's B9 ruling. A
--        targeted ON CONFLICT requires SELECT on its arbiter columns, which is why
--        service_role carries a COLUMN-LEVEL select (users_id, nav_date,
--        account_id) below and nothing else. Do NOT reach for `do update`: that
--        takes an UPDATE path, which the immutability fence blocks by design.
--
--   ⚠ CROSS-ARTIFACT INVARIANT, fenced by QA rather than merely documented: the
--     column list in the arbiter grant must match the arbiter columns the worker
--     names in `on conflict (…)`, which must match a real unique index. Break the
--     pairing and the battery fails 42501 or 42P10 — loudly, in the PR that broke
--     it. QA must exercise the PRODUCTION statement verbatim; a simplified plain
--     INSERT is what let 054's original B9 defect ship green.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (C3 standing obligation; ADR-029 / 025) — INHERITED,
--   NOT EXCLUDED, and named explicitly because AC 5's own sentence says why:
--   the clause is INVISIBLE ONCE OMITTED. A table that silently ships un-claused
--   opens an aal1 read gap on the direct PostgREST API — a stolen password reaches
--   the data before TOTP step-up — and nothing in the DDL marks its absence.
--   nav_component_daily is a NEW sensitive tenant-owned pfin table with an
--   authenticated SELECT policy, so it MUST carry the clause AND-ed into that
--   policy's USING. NONE of 025's three exclusions applies: it is NOT global
--   shared-read (tenant-scoped), NOT service_role-only/default-deny (it has an
--   authenticated SELECT policy), and it is NOT pfin.user_settings itself (the
--   recursion exclusion 025 records as non-negotiable).
--   Clause copied verbatim from 025 (COALESCE null-safe, inlined per 025's
--   ratified shape — no helper): it gates on the READER's OWN declared
--   mfa_policy, never on the row, so a 'none' or missing-settings-row reader is
--   unaffected and the lazy-provisioning null-lockout bug does not arise. It is
--   never a blanket aal2.
--   WORKER NOTE, carried from 054 because it applies identically here: the
--   impersonated session that reads 049 for a user who DECLARED totp/passkey must
--   present an aal2 JWT claim, or that user's underlying account / holdings reads
--   filter to zero and BOTH the frozen NAV and every captured leaf would be
--   silently empty rather than wrong-looking.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. This migration authors FOUR functions and ALL FOUR are
--   SECURITY INVOKER with `set search_path = ''`: two immutability fences, the
--   write-tenant binding fence, and the Decision 3 #19 matched-tenant fence. Each
--   either reads a transaction-local GUC and raises, or performs a single
--   RLS-scoped existence read and raises; none needs elevated privilege. The
--   SECURITY DEFINER allowlist is therefore UNCHANGED by this migration — read
--   ADR-011 Decision 9 live for its contents; no count is stated here.
--   ⚠ EXECUTE-ACL note, stated because the stakes invert by posture: for an
--   INVOKER trigger function the EXECUTE grant is the weakest of several fences;
--   for a DEFINER one it is the entire perimeter. All four here are INVOKER and
--   all four `revoke execute … from public` regardless, on 054's precedent.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (ADR-011 Decision 4 read VERBATIM and LIVE before
--   drafting, 2026-09-05. Path B — drop-enumeration-let-link-carry: the catalogued
--   numbered list is NOT restated here and NO COUNT is carried; this migration is
--   not the canonical anchor).
--   (i)   INSTANCE-NUMBERING — no catalogued instance is added, removed, reordered
--         or renumbered by this migration. Its ordering is untouched.
--   (ii)  LAYER-ATTRIBUTION — nothing moves. This table's service_role INSERT
--         grant is a DB-LAYER ACL. It is NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist grep fence (the W-1 worker reaches
--         Postgres over a DIRECT connection as pfin_etl and holds no such key —
--         same posture as 054 and the other direct-connection workers), NOT the
--         PDF-worker container credential audit, and NOT the app→worker admission
--         network/config surface. The per-surface layer-composition language is
--         UNCHANGED and no surface becomes "four-layer".
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--   DE-CONFLATION GUARD: none of the four fences authored here is a §10 catalogued
--   instance. The two immutability fences are a Decision 2 audit-class mechanism;
--   the write-tenant binding fence is a Decision 1 clause (c) DB-layer
--   reinforcement (054's B7 (c′) shape); the matched-account fence is a Decision 3
--   family member. All three disciplines COMPOSE with Decision 4's
--   defense-in-depth discipline and NONE adds an entry to its catalogued list.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are
--   not reconciled here or anywhere.
--
-- ----------------------------------------------------------------------------
-- WHAT IS NOT CAPTURED, AND THE NAMED LOSING SIDE. 049 emits four columns per
--   leaf — account_id, current_market_value, cost_basis, unrealized_gl. This table
--   stores ONLY `current_market_value`. Recorded as a decision with a cost, because
--   ADR-054's own asymmetry argument cuts toward capturing more:
--     FOR capturing unrealized_gl (and cost_basis) too: they are emitted free by
--       the same call, and an observation not captured on the day it occurred
--       cannot be recovered — which is the ADR's entire clock argument.
--     AGAINST, and why the AGAINST wins here: (1) only current_market_value
--       participates in the reconciliation AC 6 makes measurable, so the other two
--       would ship as UNWATCHED columns on an append-only table; (2) 105 records a
--       NAMED, LIVE RESIDUAL — while wash-sale basis_adjust and substantive
--       corp_action remain Suspense-parked at 035/037, `cost_basis` is UNDERSTATED
--       and therefore `unrealized_gl` is OVERSTATED. Freezing a known-wrong figure
--       into a table with no correction path is worse than not capturing it,
--       because the resulting series would be indistinguishable from a measured one;
--       (3) the want ADR-054 ratified is the component-VALUE legend, not a G/L
--       series.
--     ⚠ THE COST IS REAL AND IS NOT ARGUED AWAY: every day before such a column is
--       added is a permanent hole in that series, and adding the column later gives
--       every existing row a NULL nobody measured. F/CTO-decidable; flagged rather
--       than folded in.
--
-- ----------------------------------------------------------------------------
-- Numbering: 107 follows 106. Order-dependent — must run AFTER 001 (pfin schema),
--   003 (pfin.account, the matched-tenant fence's read target + the auth.users FK
--   target), 024 (pfin.user_settings, which the aal2 clause subqueries), 025 (the
--   aal2 backstop this table inherits), and 054 (pfin.nav_daily — NOT a DDL
--   dependency, there is no FK, but the sibling this file's every claim is stated
--   against and whose GUC it reuses). 049/056/059 (fn_account_unrealized_gl) and
--   050 (fn_compute_nav) are the worker's read sources, not DDL dependencies of
--   this file. No downstream migration depends on 107.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.nav_component_daily — append-only per-(user, day, account) NAV component
--     checkpoint. Columns: component_id (surrogate PK), users_id uuid (sole tenant
--     anchor; → auth.users ON DELETE CASCADE), nav_date date (the checkpoint day,
--     equal to the sibling scalar row's nav_date), account_id bigint (→ pfin.account
--     ON DELETE RESTRICT; the ADR-011 Decision 3 #19 fenced column),
--     component_value numeric (049's current_market_value, NATURALLY SIGNED —
--     liabilities negative; NaN and ±Infinity fenced), created_at timestamptz.
--     UNIQUE (users_id, nav_date, account_id) — one leaf per account per user per
--     day, and the arbiter of the worker's targeted ON CONFLICT.
--   RECONCILIATION (documented parity property, NOT a constraint):
--     SUM(component_value) over (users_id, nav_date)  =  pfin.nav_daily.nav_value
--     for the same (users_id, nav_date). Both frozen in one transaction from one
--     substrate. Watched by QA's battery leg; see THE RECONCILIATION QA WATCHES.
--   MUTATION SURFACE, per role:
--     · authenticated — SELECT only, own rows, aal2-claused. NO write grant and NO
--       write policy: INSERT / UPDATE / DELETE are denied at the table ACL, BEFORE
--       RLS and BEFORE any trigger. Cannot forge a leaf.
--     · service_role (the W-1 write role, via SET LOCAL ROLE) — INSERT only, plus a
--       COLUMN-LEVEL select on the three arbiter columns. Every INSERT must
--       additionally satisfy BOTH BEFORE INSERT fences. UPDATE / DELETE denied at
--       the ACL; TRUNCATE denied by REVOKE and by the statement-level fence.
--       It CANNOT read component_value — no monetary figure is reachable by it.
--     · any role holding UPDATE/DELETE/TRUNCATE (owner-class) — blocked by the
--       immutability triggers, which fire for the owner too. KNOWN LIMIT: an
--       owner-class role can suppress triggers; the ratified login role is not
--       owner-class.
--   pfin.fn_nav_component_daily_block_mutation() — INVOKER; BEFORE UPDATE OR DELETE
--     (row-level); raise. set search_path = ''.
--   pfin.fn_nav_component_daily_block_truncate() — INVOKER; BEFORE TRUNCATE
--     (statement-level); raise. set search_path = ''. + REVOKE TRUNCATE FROM PUBLIC.
--   pfin.fn_nav_component_daily_assert_computed_for() — INVOKER; BEFORE INSERT
--     (row-level); asserts new.users_id::text equals the transaction-local GUC
--     `app.nav_computed_for`. FAIL-CLOSED on unset / empty / NULL / mismatch.
--   pfin.fn_nav_component_daily_matched_account() — INVOKER; BEFORE INSERT
--     (row-level); ADR-011 Decision 3 #19. Asserts the referenced pfin.account row
--     carries the same users_id as the leaf row. NULL-safe fail-closed.
--   RLS: SELECT to authenticated on users_id = auth.uid() AND the aal2 backstop.
--     INSERT / UPDATE / DELETE have NO authenticated policy → default-deny.
--   Security-load-bearing edges: users_id = auth.uid() fences reads to the owner
--     (direct anchor, no JOIN); the aal2 conjunct gates a totp/passkey reader to an
--     aal2 session; the immutability triggers close the privileged-context
--     UPDATE/DELETE/TRUNCATE gap (service_role bypasses RLS but not triggers, and
--     cannot suppress them); the binding fence closes the write-side tenant gap RLS
--     cannot reach (no INSERT policy, and the writer bypasses RLS); #19 closes the
--     cross-tenant account reference the FK is silent about; the finiteness CHECK
--     keeps a poisoned leaf out of the series.
--
--   ⚠ THE TWO BEFORE INSERT FENCES COVER DISJOINT FAILURES AND NEITHER SUBSUMES
--     THE OTHER — stated so nobody removes one as redundant:
--       · assert_computed_for never looks at account_id. A leaf list containing
--         ANOTHER TENANT'S account_id under a correct users_id passes it, and is
--         caught ONLY by #19.
--       · matched_account never looks at the served tenant. A fully self-consistent
--         (users_id, account_id) pair belonging to the WRONG tenant passes it, and
--         is caught ONLY by assert_computed_for.
--     Together they pin account_id to the tenant the database actually served.
--     Trigger firing order within BEFORE INSERT is ALPHABETICAL BY TRIGGER NAME, so
--     `nav_component_daily_assert_computed_for` fires before
--     `nav_component_daily_matched_account`. Both must pass; the order decides only
--     which message a battery observes first, and the two messages are deliberately
--     distinct so a battery can assert WHICH fired.
--
--   ⚠ WHERE #19 BORROWS ITS SUFFICIENCY (the 057 #16 disclosure, restated because
--     it is true here too and the catalog comment is where the next author stands):
--     the fence runs SECURITY INVOKER, so `not exists` is true both when the pair
--     genuinely mismatches AND when the referenced pfin.account row is merely
--     INVISIBLE under the caller's RLS. The two forge directions are NOT equally
--     protected. Under this table's write path the distinction is narrower than at
--     057 — the writer is service_role, which is rolbypassrls, so NO account row is
--     invisible to it and `not exists` there means genuine mismatch, on data. That
--     is what makes #19 a fence that CAN FAIL against its actual writer rather than
--     a leg that cannot fire. For any FUTURE non-exempt writer the 057 caveat
--     applies unchanged.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.nav_component_daily — the per-account leaf checkpoint (ADR-054 Decision 1
-- Option C; SELF-353 / A9). users_id is the sole tenant anchor (direct-owner RLS,
-- 024/054 precedent). account_id is the ADR-011 Decision 3 #19 fenced column.
-- ON DELETE CASCADE on users_id: a user's checkpoints are dependent data.
-- ON DELETE RESTRICT on account_id: a captured observation must not be silently
-- erased by an account deletion — the 057 #16 choice, for the same reason (the
-- table is append-only, so a CASCADE would be the ONE deletion path that bypasses
-- the immutability fences).
-- ----------------------------------------------------------------------------
create table if not exists pfin.nav_component_daily (
  component_id     bigint      generated always as identity primary key,
  users_id         uuid        not null references auth.users (id) on delete cascade,      -- sole tenant anchor (uuid)
  nav_date         date        not null,                                                   -- the checkpoint day; equals the sibling scalar row's nav_date
  account_id       bigint      not null references pfin.account (account_id) on delete restrict,  -- Decision 3 #19 fenced column
  component_value  numeric     not null,                                                   -- 049 current_market_value, NATURALLY SIGNED (liabilities negative)
  created_at       timestamptz not null default now(),                                     -- IMMUTABLE post-INSERT
  constraint nav_component_daily_value_finite
    check (component_value <> 'NaN'::numeric
       and component_value <> 'Infinity'::numeric
       and component_value <> '-Infinity'::numeric),                                       -- 014/054 finiteness idiom (NaN + ±Infinity; the 053 N1 lesson)
  unique (users_id, nav_date, account_id)                                                  -- one leaf per account per user per day; the ON CONFLICT arbiter
);

comment on table pfin.nav_component_daily is
  'Append-only per-(user, day, account) NAV COMPONENT checkpoint — the capture-only '
  'component substrate ratified at ADR-054 Decision 1 (Option C); SELF-353 / A9. '
  'One row per (users_id, nav_date, account_id) = that account''s frozen contribution '
  'to the day''s net worth, captured by the SAME W-1 cron worker in the SAME '
  'transaction as the scalar pfin.nav_daily row (054). SOURCE OF THE VALUE: '
  'pfin.fn_account_unrealized_gl(as_of).current_market_value (049; live body re-issued '
  'at 056, leaf set re-predicated at 059), NATURALLY SIGNED — liability leaves are '
  'negative. ⚠ NOT pfin.fn_nav_composition, which anti-joins out tax-authority-'
  'designated ledgers (102/105) while pfin.nav_daily stays the GROSS pre-tax series '
  '(ADR-067 Decision 3): capturing that function''s leaves instead would make the '
  'reconciliation below false by construction. RECONCILIATION — a DOCUMENTED PARITY '
  'PROPERTY, NOT a schema-enforced invariant (ADR-054 Decision 5(2), with the F/CTO '
  'rider recorded at that ruling): for a given (users_id, nav_date), '
  'SUM(component_value) equals pfin.nav_daily.nav_value for the same (users_id, '
  'nav_date). It holds BY CONSTRUCTION — both are frozen in one transaction from one '
  'substrate, and Sum over 049(as_of).current_market_value IS fn_compute_nav(as_of, '
  'true) exactly (ADR-038/ADR-039) — which is why it is WATCHED BY A QA BATTERY LEG '
  'AND NOT FENCED BY A CHECK: a constraint over a by-construction equality can never '
  'fire, and would convert a future derivation drift into a nightly cron outage '
  'instead of a report. It holds only while BOTH sides apply the SAME account-set '
  'filter; change either independently and it breaks for reasons unrelated to '
  'capture. CAPTURE-ONLY: no read helper, no view, no UI, no backfill, no import — '
  'ADR-054 Decision 5(1), ruled FORBIDDEN in V1.x; the V2 subcomponent visualization '
  'is the first consumer. PER-ACCOUNT LEAF GRANULARITY (Decision 3) with NO taxonomy '
  'column, so any future asset-class or account-type cut can be applied '
  'retroactively and the Chart-of-Accounts question stays orthogonal by construction '
  '(Decision 6). GROWTH COMMITMENT, stated rather than discovered: one row per '
  'active account per user per day, forever, on a table whose rows can never be '
  'deleted. WRITE PATH (ADR-023 credential model; 055): the worker LOGS IN as '
  '`pfin_etl` (service_role is rolcanlogin=f and can never be a login identity) and '
  'WRITES AS `service_role` via SET LOCAL ROLE; INSERT ... ON CONFLICT (users_id, '
  'nav_date, account_id) DO NOTHING — the TARGETED form, which is why service_role '
  'additionally holds a COLUMN-LEVEL select on exactly those three arbiter columns. '
  'service_role CANNOT read component_value and CANNOT select * — both denied, and QA '
  'asserts both negatives, since a positive assertion alone cannot distinguish a '
  'column grant from a table grant. Widening that grant (any extra column, or a move '
  'to table-level) is SEC JOINT-REVIEW-MANDATORY. `authenticated` holds SELECT only — '
  'no write grant and no write policy, so its writes are denied at the ACL before RLS '
  'and it cannot forge a leaf. APPEND-ONLY AUDIT-CLASS (ADR-011 Decision 2): UPDATE + '
  'DELETE + TRUNCATE fenced for ALL roles; service_role bypasses RLS but not '
  'triggers, and is neither owner nor superuser so it cannot suppress them. ⚠ ONLY '
  'THE IMMUTABILITY HALF OF Decision 2 APPLIES: there is NO correction-by-INSERT-new-'
  'version path here and there is not meant to be — a row is a CAPTURED OBSERVATION '
  'of a past day, not a report that can be regenerated, so there is no predecessor '
  'FK, no status ENUM and no version column, and adding one would create a way to '
  'publish a later-computed claim about a past day with the shape of a measurement. '
  'WRITE-TENANT BINDING: a BEFORE INSERT fence requires new.users_id to equal the '
  'transaction-local GUC app.nav_computed_for — the SAME GUC 054 pins, set once per '
  'transaction from auth.uid() as the DB resolved it, so ONE binding covers both '
  'tables and they cannot be bound to different tenants. Every INSERT path (worker, '
  'QA fixture, seed) must set it first. ADR-011 DECISION 3 #19 (account_id): '
  'matched-tenant fence realized as a BEFORE INSERT TRIGGER, not an RLS WITH CHECK — '
  'the sole writer is service_role, which carries rolbypassrls, so a policy clause '
  'would be VACUOUS against the only writer that exists (the ADR-042 Decision 5a '
  'rationale that made #16 trigger-realized at 057). Read Decision 3 live; no count '
  'is stated here. users_id is NOT a Decision 3 instance — it is the sole own anchor '
  'under a direct RLS predicate, with no second anchor to mismatch. aal2 step-up '
  'backstop INHERITED on the SELECT policy (C3 / ADR-029 / 025); none of the three '
  '025 exclusions applies. JOINT-REVIEW-MANDATORY (tenant-scoped audit-class '
  'financial table + new RLS + a cron write-path extension + a Decision 3 family '
  'extension — the four triggers enumerated at ADR-054''s Governance block).';

comment on column pfin.nav_component_daily.users_id is
  'Sole tenant anchor. uuid NOT NULL, FK -> auth.users(id) ON DELETE CASCADE. Direct-'
  'owner RLS (users_id = auth.uid(), no JOIN) — the 024/054 shape: the tenant anchor '
  'IS the reference, with no second anchor to mismatch, so it is NOT a matched-tenant '
  'ADR-011 Decision 3 instance. It is also the value the BEFORE INSERT write-tenant '
  'binding fence compares against the transaction-local GUC app.nav_computed_for.';

comment on column pfin.nav_component_daily.nav_date is
  'The checkpoint day. Equal to the nav_date of the sibling pfin.nav_daily scalar row '
  'written in the same transaction — that equality is what makes (users_id, nav_date) '
  'the reconciliation join key ADR-054 Decision 5 states in its own words. Part of '
  'UNIQUE (users_id, nav_date, account_id).';

comment on column pfin.nav_component_daily.account_id is
  'The account whose contribution this leaf records. FK -> pfin.account(account_id) ON '
  'DELETE RESTRICT — RESTRICT, not CASCADE, because the table is append-only and a '
  'CASCADE would be the one deletion path that bypasses the immutability fences '
  '(the 057 #16 choice, for the same reason). ⚠ ADR-011 DECISION 3 CANONICAL '
  'INSTANCE #19: an FK validates that the referenced row EXISTS, never that it is '
  'within the referring row''s isolation scope — matched-tenant validation is '
  'supplied by the BEFORE INSERT fence fn_nav_component_daily_matched_account, not by '
  'this FK. Realized as a TRIGGER rather than an RLS WITH CHECK because the sole '
  'writer bypasses RLS; see the function''s own comment. NO taxonomy or category '
  'column accompanies it — leaf granularity is what keeps any future asset-class or '
  'account-type roll-up applicable retroactively (ADR-054 Decisions 3 + 6).';

comment on column pfin.nav_component_daily.component_value is
  'This account''s frozen contribution to the day''s net worth, in USD: '
  'pfin.fn_account_unrealized_gl(as_of).current_market_value (049), captured at '
  'compute time. NATURALLY SIGNED — a liability account''s value is NEGATIVE (049 '
  'R-7 / 051 DEBT-SIGN D-1), so the reconciliation is a plain SUM with no abs and no '
  'negation. Finiteness-fenced (nav_component_daily_value_finite: NaN AND +/-Infinity '
  'rejected — a bare numeric admits infinities and either would poison every future '
  'roll-up). Immutable once written. NOT readable by service_role: the column-level '
  'grant covers only the three arbiter columns.';

comment on column pfin.nav_component_daily.created_at is
  'Insert timestamp; IMMUTABLE post-INSERT (append-only audit-class). Distinct from '
  'nav_date (the checkpoint''s logical day): created_at is the wall-clock of the '
  'worker run, nav_date is the day the value is AS-OF.';

comment on constraint nav_component_daily_value_finite on pfin.nav_component_daily is
  'Rejects the numeric special values NaN AND +Infinity AND -Infinity on '
  'component_value (the 014/054 finiteness idiom; a true finiteness guard — an '
  'unbounded numeric admits +/-Infinity and a two-sided NaN test does not catch them, '
  'so all three are barred explicitly). Any would poison every roll-up computed over '
  'this series, and the row could never be corrected. Role-agnostic table CHECK '
  '(service_role bypasses RLS but NOT CHECK); NOT NULL column, so no NULL-passes gap.';

-- ----------------------------------------------------------------------------
-- RLS — owner-only read (direct anchor + the 025 aal2 backstop); writes AS
-- service_role. grant-before-RLS shape (PR #106): authenticated needs the SELECT
-- grant even with RLS enabled — RLS filters rows, the GRANT lets the role reach the
-- table at all. No authenticated write grant and no write policy, so authenticated
-- cannot INSERT/UPDATE/DELETE regardless of policy state.
-- ----------------------------------------------------------------------------
alter table pfin.nav_component_daily enable row level security;

create policy nav_component_daily_select on pfin.nav_component_daily
  for select to authenticated
  using (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy nav_component_daily_select on pfin.nav_component_daily is
  'SELECT: owner-only, users_id = auth.uid() (direct anchor, no JOIN — the 024/054 '
  'precedent) AND the 025 aal2 step-up backstop (C3 standing obligation; INHERITED — '
  'this is a new sensitive tenant-owned pfin table and none of 025''s three exclusions '
  'applies: not global shared-read, not service_role-only/default-deny, not '
  'user_settings itself). The aal2 conjunct requires a reader who DECLARED mfa_policy '
  'totp/passkey to present an aal2 JWT; a ''none'' or missing-settings-row reader is '
  'unaffected (coalesce(...,''none'') — avoids the lazy-provisioning null-lockout bug). '
  'It gates on the READER''s own declared policy, never on the row, and is never a '
  'blanket aal2. THIS IS THE ONLY authenticated POLICY: INSERT / UPDATE / DELETE have '
  'none, so they default-deny and a tenant cannot forge a leaf. Its existence is also '
  'what keeps this table inside the aal2 obligation rather than inside 025 exclusion '
  '(ii) — a zero-authenticated-policy table would carry no clause at all. ⚠ It does '
  'NOT contradict ADR-054 Decision 5(1): that ruling forbids a V1.x READ HELPER (a '
  'function with its own contract, grants and battery), not the owner''s own access to '
  'rows about the owner. Writes execute AS service_role and bypass RLS entirely — '
  'which is exactly why the write side carries its own DB-layer proofs: the '
  'write-tenant binding fence and the Decision 3 #19 matched-tenant fence.';

grant select on pfin.nav_component_daily to authenticated;
grant insert on pfin.nav_component_daily to service_role;

-- ----------------------------------------------------------------------------
-- COLUMN-LEVEL SELECT for service_role — the ARBITER COLUMNS ONLY, on 054's B9
-- ruling. REQUIRED for the worker's idempotency mechanism: a TARGETED
-- `on conflict (users_id, nav_date, account_id) do nothing` needs SELECT on its
-- arbiter columns, and without it the cron raises 42501 on EVERY run — not just
-- re-runs. That was 054's B9 defect, found only by executing the assembled worker
-- statement sequence end-to-end; it is pre-empted here rather than rediscovered.
--
-- WHY COLUMN-LEVEL AND NOT `grant select on pfin.nav_component_daily`: PRECISELY
-- BECAUSE service_role bypasses RLS, the ACL is the ONLY remaining fence on it.
-- "RLS doesn't constrain it, so the ACL needn't either" would justify granting
-- SELECT on every table in pfin and dissolves 008's per-table least-privilege model.
-- A table grant would additionally hand service_role every tenant's full per-account
-- wealth composition — a strictly larger disclosure than 054's, whose sensitivity is
-- already rated HIGH at SD-24 because "the sensitivity is in the sequence". This
-- grant withholds component_value entirely.
--
-- *** RESIDUAL — WHAT service_role DOES GAIN, stated plainly rather than left to
--     the 054 citation to imply equivalence. Across all tenants it gains: leaf
--     EXISTENCE, the per-tenant checkpoint-DATE sequence, and the SET OF ACCOUNT IDS
--     captured per tenant-day. It gains NO monetary value. The date sequence is the
--     same residual 054 already recorded (it reveals when a tenant started using the
--     product and when the cron failed for them). The account-id set is NOT new
--     information to this role — service_role already reads pfin.account, so the
--     (users_id, account_id) mapping is already reachable; what is marginally new is
--     WHICH accounts were ACTIVE on WHICH day, i.e. the account set's history. That
--     is a real, narrow disclosure and it is recorded rather than absorbed into
--     "same as 054".
--
-- WIDENING THIS GRANT IS SEC JOINT-REVIEW-MANDATORY. It is exactly
-- `select (users_id, nav_date, account_id)`. NEVER table-level. NEVER component_value.
--
-- CROSS-ARTIFACT INVARIANT (fenced by QA, not merely documented): the column list
-- here must match the arbiter columns the worker names in `on conflict (...)`, which
-- must match a real unique index. Change one without the others and the battery fails
-- 42501 or 42P10 — loudly, in the PR that broke the pairing. QA must exercise the
-- PRODUCTION statement verbatim; a simplified plain INSERT is what let 054's original
-- defect ship green.
--
-- NOTE ON WHAT IS DELIBERATELY ABSENT: there is NO `revoke ... (component_value)`
-- statement, and one must not be added back. Postgres has NO NEGATIVE GRANTS
-- (measured at 054, rolled-back txn) — such a revoke would be powerless in both
-- directions, and AN EXECUTABLE STATEMENT THAT ENFORCES NOTHING IS WORSE THAN A
-- COMMENT SAYING THE SAME THING, BECAUSE CODE IMPLIES ENFORCEMENT. The actual
-- controls on component_value are the narrowness of the grant below, the
-- joint-review trigger recorded above, and QA's two NEGATIVE assertions.
-- ----------------------------------------------------------------------------
grant select (users_id, nav_date, account_id) on pfin.nav_component_daily to service_role;

-- ----------------------------------------------------------------------------
-- Append-only immutability fences (ADR-011 Decision 2 / Lock 10 mod #8; the 004 and
-- 054 pattern). Surface 1 — row-level UPDATE/DELETE block.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_component_daily_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise, NOT return null — return null would silently no-op the row and
  -- read as "succeeded"). Blocks UPDATE + DELETE for ALL roles; service_role bypasses
  -- RLS but NOT triggers, so this — not RLS-default-deny — closes the
  -- privileged-context immutability gap.
  raise exception
    'pfin.nav_component_daily is immutable (append-only component checkpoint; ADR-011 Decision 2 / ADR-054 Decision 1). % blocked — a captured leaf observation is a historical fact, never edited or deleted.', tg_op;
end;
$$;

revoke execute on function pfin.fn_nav_component_daily_block_mutation() from public;

comment on function pfin.fn_nav_component_daily_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.nav_component_daily (ADR-011 Decision 2 / Lock 10 mod #8; ADR-054 Decision 1; SELF-353). SECURITY INVOKER, set search_path = '''' — touches no table and needs no elevated privilege; NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here). raise exception (fail loud, never return null — a silent no-op would read as success). Blocks UPDATE + DELETE for ALL roles including service_role, which bypasses RLS but not triggers and is neither owner nor superuser so it cannot suppress this. ⚠ ONLY THE IMMUTABILITY HALF of Decision 2 is in force on this table: there is deliberately NO correction-by-INSERT-new-version path, because a row here is a captured observation of a past day rather than a report that can be regenerated. INSERT is NOT blocked here (it is the cron append path) — it is separately gated by fn_nav_component_daily_assert_computed_for (write-tenant binding) and fn_nav_component_daily_matched_account (Decision 3 #19). KNOWN LIMIT: an owner-class role can suppress this trigger (ALTER TABLE ... DISABLE TRIGGER / session_replication_role = replica), which is why the ratified ETL login role is not owner-class (055); catalogued at SECURITY SD-24 / RT-31 and generalised at ADR-011 Decision 4''s 2026-09-03 amendment.';

create trigger nav_component_daily_block_mutation
  before update or delete on pfin.nav_component_daily
  for each row execute function pfin.fn_nav_component_daily_block_mutation();

-- ----------------------------------------------------------------------------
-- Surface 2 — statement-level TRUNCATE block. Row-level triggers do NOT fire on
-- TRUNCATE, so a role holding TRUNCATE could wipe the whole component series without
-- tripping Surface 1. Statement-level fence (covers it regardless of grant) + a
-- defensive REVOKE.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_component_daily_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.nav_component_daily is immutable (append-only component checkpoint; ADR-011 Decision 2 / ADR-054 Decision 1). TRUNCATE blocked — the component series cannot be wiped, and an observation lost cannot be recaptured.';
end;
$$;

revoke execute on function pfin.fn_nav_component_daily_block_truncate() from public;

comment on function pfin.fn_nav_component_daily_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.nav_component_daily (ADR-011 Decision 2 / Lock 10 mod #8; SELF-353). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live). raise exception (fail loud). Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so this statement-level trigger fences the series-wipe path for ALL roles regardless of grant state, and a defensive REVOKE TRUNCATE FROM PUBLIC stands in front of it so a broad platform default cannot reintroduce the privilege. The message is deliberately DISTINCT from the row-level fence''s so a battery can assert which fired. The loss it prevents is not recoverable by recomputation: ADR-054''s ratified argument is that an observation not captured on the day it occurred cannot be recovered, and the same holds for one deleted afterwards.';

create trigger nav_component_daily_block_truncate
  before truncate on pfin.nav_component_daily
  for each statement execute function pfin.fn_nav_component_daily_block_truncate();

-- Defense-in-depth: PUBLIC holds no TRUNCATE by default, but revoke explicitly so a
-- broad platform/default grant cannot reintroduce it. The statement-level trigger
-- above is the regardless-of-grant guarantee.
revoke truncate on pfin.nav_component_daily from public;

-- ----------------------------------------------------------------------------
-- Surface 3 — WRITE-TENANT BINDING FENCE. The 054 B7 (c′) shape, reusing 054's GUC.
-- Proves at the DB layer that the leaf row's tenant IS the tenant the database
-- actually served during the impersonated read. GUC name `app.nav_computed_for` is
-- PINNED and is SHARED WITH 054 BY DESIGN: the worker sets it once per transaction
-- from auth.uid() as the DB resolved it (never from the app's own variable), and one
-- binding then covers both the scalar row and every leaf row of that checkpoint. A
-- second, table-specific GUC is expressly NOT used — two GUCs could disagree, and a
-- disagreement between them would mean the two halves of one checkpoint were bound
-- to different tenants, which is the precise failure this fence exists to prevent.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_component_daily_assert_computed_for()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  -- current_setting(..., true) = missing_ok: returns NULL rather than raising 42704
  -- when the GUC was never set in this transaction. That NULL must REJECT, not pass.
  v_computed_for text := current_setting('app.nav_computed_for', true);
begin
  -- FAIL CLOSED on all four cases: GUC unset (NULL) / empty string / mismatch /
  -- anything non-equal. IS DISTINCT FROM is the NULL-SAFE comparison: a plain
  -- `new.users_id::text = v_computed_for` yields NULL (not false) when v_computed_for
  -- is NULL, and `if not NULL then` does NOT execute — which would fail OPEN
  -- precisely when the worker forgot to bind. The explicit NULL and '' tests are
  -- belt-and-braces and keep the intent legible.
  -- new.users_id is NOT NULL by column constraint, so only the GUC side can be NULL.
  if v_computed_for is null
     or v_computed_for = ''
     or new.users_id::text is distinct from v_computed_for
  then
    raise exception
      'pfin.nav_component_daily write-tenant binding REJECTED (ADR-011 Decision 1 clause (c) DB fence; SELF-353, the 054 B7 shape). Row users_id=% does not match app.nav_computed_for=% — a captured leaf''s tenant must equal the tenant the database actually served during the impersonated read. Set app.nav_computed_for from auth.uid() inside the impersonated block (transaction-local) before INSERT.',
      new.users_id, coalesce(nullif(v_computed_for, ''), '<UNSET>');
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_nav_component_daily_assert_computed_for() from public;

comment on function pfin.fn_nav_component_daily_assert_computed_for() is
  'BEFORE INSERT write-tenant binding fence on pfin.nav_component_daily (ADR-011 Decision 1 clause (c) realized at the DB layer; ADR-054; SELF-353 — the 054 B7 (c-prime) shape reused, not re-decided). SECURITY INVOKER, set search_path = '''' — reads only a transaction-local GUC and raises; NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here). CONTRACT: asserts new.users_id::text equals the transaction-local GUC ''app.nav_computed_for'', which the W-1 worker sets INSIDE the impersonated block via set_config(''app.nav_computed_for'', auth.uid()::text, true) — captured from auth.uid() AS THE DATABASE RESOLVED IT, never from the application''s own variable. That is the security-critical property: it proves the row''s tenant IS the tenant whose data was actually served, which a GUC derived from the app variable could not, and it closes the legacy singular-GUC path auth.uid() prefers (a session- or role-scoped request.jwt.claim.sub would otherwise silently serve ONE tenant''s data for EVERY tenant with no code bug and no app-layer assertion failure). THE GUC IS SHARED WITH pfin.nav_daily DELIBERATELY: one binding per transaction covers the scalar row and every leaf row of the same checkpoint, so the two halves cannot be bound to different tenants. A second table-specific GUC would reintroduce exactly that possibility and MUST NOT be added. FAIL-CLOSED on unset / empty / NULL / mismatch — IS DISTINCT FROM is used because new.users_id::text = NULL is NULL, not false, and would fail OPEN. Transaction-local, so it survives the impersonation teardown''s reset role and auto-clears at COMMIT. ⚠ THIS IS NOT A DECISION 3 FENCE and must not be counted as one: it validates the row''s OWN anchor against the served tenant, not a referenced row''s tenant scope. The Decision 3 obligation on this table is discharged separately by fn_nav_component_daily_matched_account (#19), and NEITHER FENCE SUBSUMES THE OTHER — this one never looks at account_id, so a leaf carrying another tenant''s account_id under a correct users_id passes here and is caught only there. Every INSERT path (worker, QA fixture, seed) must set the GUC first.';

create trigger nav_component_daily_assert_computed_for
  before insert on pfin.nav_component_daily
  for each row execute function pfin.fn_nav_component_daily_assert_computed_for();

-- ----------------------------------------------------------------------------
-- Surface 4 — ADR-011 DECISION 3 #19 MATCHED-TENANT FENCE on account_id.
-- The 057 #16 shape (P1 matched-tenant, local anchor: the row carries its own
-- resolved users_id and the referenced pfin.account row must share it), BEFORE
-- INSERT ONLY — the table is immutable audit-class, so UPDATE and DELETE are
-- trigger-blocked and an UPDATE fence would be dead code (the 019 / 044 / 057
-- precedent, as distinct from the 012 / 022 / 074 / 101 mutable-settings shape
-- which needs BEFORE INSERT OR UPDATE because a repoint path exists).
--
-- ⚠ A TRIGGER, NOT AN RLS `WITH CHECK`, AND THE CHOICE IS FORCED: Decision 3
-- sanctions both realizations and names WITH CHECK first for single columns, but a
-- WITH CHECK is a POLICY clause and is not evaluated for a rolbypassrls role. The
-- sole writer of this table is service_role, which carries rolbypassrls — so a
-- policy realization would be VACUOUS against the only writer that exists. This is
-- ADR-042 Decision 5a's rationale for #16 recurring on a structurally identical
-- surface, and it is why #19 copies #16 rather than the Decision-3 preamble's first
-- named form. The cost is stated at the header: being trigger-realized, #19 and the
-- FK it backstops go inert together under session_replication_role = replica, taking
-- the RLS-exempt writer's applicable-layer count to zero (ADR-011 Decision 4's
-- 2026-09-03 amendment). That GUC is superuser-context and is denied to both
-- service_role and authenticated, so the exposure is operational, not adversarial.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_component_daily_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- NULL-safe fail-closed by construction: `not exists` is true when the pair does
  -- not resolve for ANY reason (missing account, foreign account, or — for an
  -- RLS-subject caller — an invisible one). new.account_id and new.users_id are both
  -- NOT NULL by column constraint, so neither side can be NULL here.
  if not exists (
    select 1 from pfin.account a
    where a.account_id = new.account_id
      and a.users_id   = new.users_id
  ) then
    raise exception
      'cross-tenant nav_component_daily leaf rejected: account_id % is not owned by users_id % (ADR-011 Decision 3 #19 matched-tenant fence)',
      new.account_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_nav_component_daily_matched_account() from public;

comment on function pfin.fn_nav_component_daily_matched_account() is
  'BEFORE INSERT matched-tenant fence on pfin.nav_component_daily.account_id (ADR-011 Decision 3 CANONICAL INSTANCE #19; P1 matched-tenant local anchor, copying the #16 shape at 057 which copied #15 at 044). ADR-054 Decision 4 is the provenance: leaf granularity means this table carries an account_id, which is an FK-shaped reference on a tenant-scoped table, and matched-tenant validation in the DDL is non-negotiable — a PostgreSQL FK validates that the referenced row EXISTS, never that it is within the referring row''s isolation scope. The row carries its own resolved users_id; the referenced pfin.account row must share it. NULL-safe fail-closed (NOT EXISTS -> raise). SECURITY INVOKER + set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here). BEFORE INSERT ONLY: the table is immutable audit-class, so UPDATE and DELETE are trigger-blocked and an UPDATE fence would be dead code (the 019 / 044 / 057 immutable-audit shape, as distinct from the 012 / 022 / 074 / 101 mutable-settings shape which fences INSERT OR UPDATE because a repoint path exists there). ⚠ REALIZED AS A TRIGGER AND NOT AS AN RLS WITH CHECK, AND THE CHOICE IS FORCED: Decision 3 sanctions both forms and names WITH CHECK first for single columns, but a WITH CHECK is a POLICY clause and is not evaluated for a rolbypassrls role. The sole writer here is service_role, which carries rolbypassrls, so a policy realization would be VACUOUS against the only writer that exists — the ADR-042 Decision 5a rationale that made #16 trigger-realized. THE COST OF THAT FORM, stated rather than left to be discovered: a trigger-realized fence and the FK it backstops go INERT TOGETHER under session_replication_role = replica, and for an RLS-exempt writer that takes the applicable-layer count to ZERO rather than to one (ADR-011 Decision 4''s 2026-09-03 amendment). The GUC is superuser-context and is denied to both service_role and authenticated, so it is not tenant-reachable and the exposure is operational: any restore, bulk-load or replication runbook that sets it owes an explicit post-load validation over this table. WHERE THIS FENCE BORROWS ITS SUFFICIENCY (the 057 disclosure, narrower here): running INVOKER, `not exists` is true both when the pair genuinely mismatches AND when the referenced account row is merely INVISIBLE under the caller''s RLS. Under this table''s actual write path that ambiguity does not arise — service_role is rolbypassrls, so no account row is invisible to it and `not exists` means a genuine data mismatch. That is what makes this a fence that CAN FAIL against its real writer rather than a leg that cannot fire (the ADR-062 Decision 2 shape it deliberately avoids). For any FUTURE non-exempt writer the 057 caveat applies unchanged, and whoever adds one should re-derive this comment rather than re-read it. ⚠ IT DOES NOT SUBSUME, AND IS NOT SUBSUMED BY, fn_nav_component_daily_assert_computed_for: this fence never looks at the served tenant, so a fully self-consistent (users_id, account_id) pair belonging to the WRONG tenant passes here and is caught only there; that fence never looks at account_id, so a foreign account_id under a correct users_id passes there and is caught only here. Together they pin account_id to the tenant the database actually served. Both are BEFORE INSERT row triggers and fire in ALPHABETICAL trigger-name order, so assert_computed_for runs first; the two messages are deliberately distinct so a battery can assert which fired.';

create trigger nav_component_daily_matched_account
  before insert on pfin.nav_component_daily
  for each row execute function pfin.fn_nav_component_daily_matched_account();

-- ----------------------------------------------------------------------------
-- No separate users_id index: the `unique (users_id, nav_date, account_id)` btree
-- already serves the RLS predicate (users_id = auth.uid()), the reconciliation join
-- on (users_id, nav_date), and the worker's ON CONFLICT arbiter — all three are
-- leading-column prefixes of it. Mirrors 054's and 106's index reasoning.
-- ----------------------------------------------------------------------------
