-- =====================================================================
-- 059 — ACCOUNT CLOSURE, PHASE 2 (ADR-042): the reconciliation assert, the `is_active`
--        drop, and the as-of re-point of `049` / `050` / `051`.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `059`.
-- Sec joint-review-mandatory (financial calculation · multi-tenant isolation · a column
-- drop on a financial surface · the ADR-039 amendment).
--
-- ⟦DESIGN: TWO-PHASE — Sec-adjudicated + Architect-confirmed 2026-08-03⟧
--   `059` runs, in this ORDER and the order is load-bearing:
--     1. call pfin.fn_assert_closure_reconciled()  — aborts on any mismatch
--     2. DROP the assert function                  — see (R5); it reads is_active
--     3. DROP pfin.account.is_active
--     4. drop the `058` transitional sync trigger
--     5. the as-of re-point of `049` / `050` / `051`
--
-- ⚠ OPERATIONAL — THIS FILE EXERCISES A DESTRUCTIVE MIGRATION.
--   `059` DROPS A COLUMN. Sec: scratch database, non-negotiable — `supabase db reset` on
--   the dev DB destroys the F/CTO's active local test data. NOTHING in this file requires a
--   reset (it seeds and rolls back in place), but APPLYING `059` to reach a state where
--   this file can run does. See the report: a faithful scratch DB was ATTEMPTED and BLOCKED
--   (the local cluster's `postgres` DB has 11 live platform sessions — PostgREST, realtime,
--   pg_cron, pg_net — so `create database … template postgres` is refused). The natural and
--   correct home for this file is CI, where the DB is built clean from the full migration
--   stack every run. A hand-stubbed scratch DB was deliberately NOT built: that is an
--   approximation of the production stack, and ADR-040's B9 lesson is that a test exercising
--   an approximation is worse than no test, because it reports green over an unproven path.
--
-- ┌─ WHY (R5) MATTERS MORE THAN IT LOOKS ──────────────────────────────────────────────┐
-- │ fn_assert_closure_reconciled() READS `is_active`, and this migration DROPS          │
-- │ `is_active`. If the function survives the migration it becomes a function that      │
-- │ RAISES AT RUNTIME on any future call — worse than dead code, because the caller     │
-- │ gets an error they may reasonably read as "reconciliation failed" when in fact      │
-- │ nothing was reconciled and nothing is wrong. (R5) asserts it is GONE.               │
-- │ Corollary for this battery: the tests that EXERCISE it are migration-time only.     │
-- │ A standing post-`059` test that CALLS it would go red for the right reason and read │
-- │ as a regression. The only permanent assertion about it is that it no longer exists. │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ CALL IT AS OWNER — this is load-bearing, not convention (Architect).
--   The function is SECURITY INVOKER, so its correctness depends on the caller seeing ALL
--   rows. The migration runs as owner and does. Called under `set role authenticated`, the
--   INVOKER body evaluates over that tenant's rows only and PASSES VACUOUSLY FOR EVERY
--   OTHER TENANT — a green that proves nothing, reached from exactly the call path a test
--   is most likely to reach for. Every (R*) assertion below runs at role=postgres.
--   (R6) asserts the structural fence that makes the vacuous path unreachable in
--   production: no EXECUTE grant to authenticated or anon.
--
-- LAYER (Sec, standing): NONE of these fences is RLS. The reconciliation is a migration-time
--   `DO … RAISE`; the gate is a BEFORE trigger. An RLS-denial assertion goes green for a
--   property that holds independently of this entire ADR.
--
-- ┌─ LAYER MAP — WHICH MECHANISM EACH ASSERTION ACTUALLY TARGETS ──────────────────────┐
-- │ Required by Sec 2026-08-03; the file was renamed off `..._rls.sql` because that name │
-- │ misdescribed the content and would bias the next author toward an RLS assertion that │
-- │ goes green independently of every fence here.                                        │
-- │                                                                                      │
-- │   Migration-time `DO … RAISE`, reached via the callable assert function              │
-- │     R1 · R2 · R3                    ← run AS OWNER; see the call-as-owner note above │
-- │   pg_catalog / information_schema — structural                                       │
-- │     R4 · R5 · R6 · R7a · X6                                                          │
-- │   SECURITY INVOKER function behaviour (the as-of re-point)                           │
-- │     X1 · X2 · X3 · X4 · X5                                                           │
-- │   RLS — genuinely RLS, and the ONLY RLS assertions in the closure set                │
-- │     T1 · T2 · T3   (inherited row filtering on the NAV driving table)                │
-- │                                                                                      │
-- │ The T block is the one place an RLS assertion is the RIGHT assertion, because Sec's  │
-- │ seventh-surface concern IS an RLS question: a dated predicate resolved through a      │
-- │ join that is not tenant-scoped leaks while every single-tenant test stays green.      │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- CORRESPONDENCE (Sec's joint-review check — run on this file before sending). The honest
--   result, including the part that failed:
--     · R7a (`is_active` is GONE) — FAILS against `058`, passes only post-`059`. ✓ discriminating
--     · X1–X5 (as-of re-point)    — FAIL against `058`. ✓ discriminating
--     · R1–R3, R6                 — reference `fn_assert_closure_reconciled`, created in `059`. ✓
--     · ⚑ R5 as first written was NOT discriminating — "the function does not exist" passes
--       vacuously at every point BEFORE `059` creates it. Caught by running Sec's check on my
--       own split rather than waiting for review. R5 is now conjoined with the post-drop state
--       so it can only pass where it means something. Recorded rather than quietly fixed,
--       because a presence-check that passes vacuously is the same defect class this whole
--       battery exists to catch.
--
-- ┌─ ⚠ MEASURED vs WRITTEN — READ BEFORE QUOTING A COUNT FROM THIS FILE ─────────────┐
-- │ This file's assertions are **WRITTEN, NOT MEASURED**: its migration is not applied │
-- │ to any database I can reach (local stack at `056`; verified `account_event`,       │
-- │ `closed_at` and `account_closure_gate` all ABSENT). **No assertion here has ever   │
-- │ run.** They are authored against the DDL text at a cited ref, which is a weaker    │
-- │ claim than green and must not be aggregated with one.                              │
-- │ Reporting rule adopted 2026-08-03 after Architect flagged that a single total      │
-- │ ("95 assertions") sitting beside a green ("22/22") invites reading all of them as  │
-- │ measured — wrong about 57. **Quote two numbers, never one sum.**                   │
-- │ Same defect as the (B5) it superseded: comparing what I had WRITTEN rather than    │
-- │ what the database SAID. Applied there to an assertion, here to a status report.    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⟦EXPECTED STACK⟧ — READ BEFORE INTERPRETING ANY RESULT FROM THIS FILE ──────────┐
-- │ **A RESULT FROM THIS BATTERY IS UNINTERPRETABLE WITHOUT THE MIGRATION SET IT RAN │
-- │ AGAINST.** A red cannot be distinguished from "this DB predates the change"; a    │
-- │ green cannot be distinguished from "this DB already had it". Report the applied   │
-- │ set alongside the result, every run — `select max(version) from                   │
-- │ supabase_migrations.schema_migrations;`                                           │
-- │                                                                                   │
-- │ EXPECTED STACK: `059`-applied.                                                      │
-- │ reconciliation called, assert-fn dropped, `is_active` dropped, `049`/`050`/`051`
-- │    re-pointed. Below `059`: RED. This file is only meaningful post-`059`.
-- │                                                                                   │
-- │ ⚠ SECOND STATE VARIABLE, added after it bit us: **WHICH BRANCH / WORKTREE.** A     │
-- │ FILE read is branch-dependent, so "I read the migration" is not a fixed referent   │
-- │ either. Cite migrations by COMMIT REF, never by working-tree path:                 │
-- │   git show <ref>:supabase/migrations/<file>                                        │
-- │ So a claim needs THREE coordinates, not one: DATABASE STATE (this block) +         │
-- │ ARTIFACT REF + the assertion itself. Two of the three bit this review.             │
-- │                                                                                   │
-- │ Convention follows `self209_close_gate.sql`'s ⟦WIRE-VALIDATE⟧ note. Generalized    │
-- │ to every file 2026-08-03 after I reported a pre-`056` database's expected red as   │
-- │ a code defect — the error was mine and this header is the fence on repeating it.   │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY; no PII, no real account numbers (SD-15), no prod
--   data; rolled-back txn.
--
-- ⟦WIRE — PROVISIONAL⟧ Architect's provisional reconciliation message:
--   'closure reconciliation failed: % account(s) with is_active = false and closed_at IS NULL'
--   Signature confirmed argument-free under two-phase; treat as provisional until pinned.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_reconcile '%closure reconciliation failed%'

-- plan = 13: R 3 (was 7 — see the BLOCK R reconcile note) · X 7 · T 3.
select plan(13);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-closed-in-june', 'depository', 'household', 'taxable') returning account_id as aclosed \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-never-closed', 'depository', 'household', 'taxable') returning account_id as aopen \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-account', 'depository', 'household', 'taxable') returning account_id as bacct \gset

-- :aclosed held 800 through May, zeroed 2026-06-15, closed 2026-06-30.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:aclosed, 800.0000, 'USD', '2026-04-30', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:aclosed, '2026-06-15', -800.0000, 0, 'zeroed');
-- :aopen holds a steady 250 — the never-closed population, for behaviour preservation.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:aopen, 250.0000, 'USD', '2026-01-31', 'seed');
-- B holds 9999 — the cross-tenant leak target for the as-of matrix.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:bacct, 9999.0000, 'USD', '2026-01-31', 'seed');

-- The seed block runs at postgres with no tenant, so auth.uid() is NULL and 057's writer
-- refuses rather than letting absence become a value. Declare the writer, as its own raise
-- instructs. 'system:remediation' is the ONLY system actor 057 admits (enumerated, not an open
-- pattern, so a new system identity fails the CHECK).
--   ⚑ THIS IS THE FAILURE THAT STOPPED THIS FILE RUNNING AT ALL. It predates 057's writer
--     (ADR-042 Amendment 1), so it closed an account without declaring an identity and the very
--     first seed statement aborted the transaction — 17 planned, 0 emitted. Not a battery
--     defect so much as evidence of the thing the writer exists to enforce: a closure with no
--     recorded actor is refused, including one performed by a test fixture.
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :aclosed;

-- =====================================================================
-- BLOCK R — RECONCILIATION + THE DROP  (Sec revised cases 3 / 4 / 5)
--   All at role=postgres (owner). See the header: calling as authenticated makes the
--   INVOKER body pass vacuously for every other tenant.
-- =====================================================================

-- ⚑⚑ BLOCK R WAS RECONCILED 2026-08-04 — 7 ASSERTIONS DOWN TO 3, AND THE REASON MATTERS
--   MORE THAN THE COUNT. This file's sole home was the wip branch, so it was authored against
--   a SUPERSEDED 059 design in which the reconciliation was a function,
--   `pfin.fn_assert_closure_reconciled()`, called mid-migration.
--
--   059 AS MERGED HAS NO SUCH FUNCTION. The reconciliation is one statement:
--       alter table pfin.account validate constraint account_closure_biconditional;
--
--   WHAT THAT CHANGES, precisely:
--     (R1)(R2)(R3) called the function and wrote `is_active` to build each mismatch. The
--       function does not exist AND the column is dropped by this very migration, so these
--       were unrunnable against any database `supabase test db` can produce. Measured: the
--       file emitted 0 of 17 assertions — the first seed statement aborted the transaction.
--     (R4) read `is_active` directly. Same.
--     (R5)(R6) asserted the function was ABSENT and UNGRANTED. Both PASSED — vacuously, on a
--       function that was never created. (R5)'s own comment records it being caught once
--       already for exactly this vacuity and conjoined against it; the conjunction saved it
--       from being green pre-059, and did nothing about being green because the subject never
--       existed. **An absence assertion is vacuous whenever the thing was never present, and
--       no amount of conjoining fixes that — only naming a subject that exists does.**
--
--   ⚠ WHERE THE STRUCK COVERAGE ACTUALLY LIVES — this is a REDIRECT, not a deletion, and it
--     is stated so nobody re-derives the cases as missing:
--       · Sec case 3 (is_active=false, closed_at NULL) is proven at the PREDICATE level in
--         058's battery: (P4) on the INSERT path and (S4a) on the UPDATE path, both against
--         `account_closure_biconditional` itself. That predicate is what VALIDATE evaluates.
--       · The VALIDATE STEP's own behaviour — that a NOT VALID constraint, once validated,
--         rejects pre-existing violators — is a POSTGRES guarantee, not our logic, and it is
--         NOT RE-TESTABLE HERE BY CONSTRUCTION: 059 drops the constraint and the column
--         immediately afterwards, so no artifact survives to exercise. Reconstructing them
--         inside the test transaction would assert against a fixture of our own making —
--         DESIGN.md rule 0, the fixture standing in for the thing it claims to test.
--   ⚠ ONE GAP I DO NOT THINK IS COVERED ANYWHERE, flagged rather than quietly absorbed:
--     Sec case 4's direction — closed_at SET while is_active is still TRUE — has no assertion
--     in 058's battery. (P4) covers only the (false, null) direction. It is unconstructible by
--     UPDATE at 058 (the sync trigger overwrites is_active), but an INSERT carrying
--     (is_active=true, closed_at=<date>) would be rejected by the CHECK with nothing asserting
--     it. 058 is merged and this column dies here, so the window is closed by 059 itself —
--     reported for the record, not proposed as work.
--
--   WHAT REMAINS BELOW IS THE POST-STATE, which is the only thing this file can honestly
--   observe about the reconciliation: the migration ran to completion and left nothing behind.

-- (R1) THE ONE-WAY DOOR.
select hasnt_column('pfin', 'account', 'is_active',
  '(R1) ONE-WAY DOOR: pfin.account.is_active is DROPPED, not retained-as-derived. A retained boolean cannot answer an as-of question, so any future query reaching for it in an as-of context would be silently wrong — the exact defect this model removes');

-- (R2) THE TRANSITIONAL MACHINERY IS FULLY GONE — all three pieces, as one count.
--   Asserted together because they are one decommission: 059 drops the CHECK, then the sync
--   trigger, then the function, in that order and for stated reasons. Any survivor is a
--   fence maintaining or enforcing a column that no longer exists.
select is(
  (select
     (select count(*)::int from pg_constraint
        where conrelid = 'pfin.account'::regclass and conname = 'account_closure_biconditional')
   + (select count(*)::int from pg_trigger t join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'pfin' and c.relname = 'account'
         and t.tgname = 'account_sync_is_active' and not t.tgisinternal)
   + (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.proname = 'fn_account_sync_is_active')),
  0,
  '(R2) THE TRANSITIONAL MACHINERY IS FULLY DECOMMISSIONED: the biconditional CHECK, the account_sync_is_active trigger and its function are ALL absent. Counted as a sum so a partial decommission is visible as a NUMBER rather than as three separate greens where one might have been forgotten. A surviving CHECK would reference a dropped column; a surviving trigger would maintain one');

-- (R3) ANTI-VACUITY FOR (R1)/(R2) — the discipline the superseded (R5) recorded and that its
--   own subject then defeated. Every assertion above is an ABSENCE, and absences are all
--   equally true on a database where 057/058 never ran. Conjoin them with something that is
--   ONLY true AFTER 059: closed_at present (058) AND the as-of re-point live in the catalog
--   (059). Without this, BLOCK R is green against an empty schema.
--   ⚑ ANCHOR LOOSENED 2026-08-04, AND THE TIGHT ONE DID ITS JOB ON THE WAY OUT. It matched the
--     literal `closed_at > p_as_of`. Architect then ruled the as-of boundary and the predicate
--     became `closed_at::date > p_as_of` (16d9e52) — a CORRECT change — and this assertion went
--     RED. That is the right failure for an anti-vacuity anchor: it noticed. But it noticed the
--     wrong thing, because it was pinned to the predicate's EXACT FORM when its job is only to
--     establish that the re-point HAPPENED. Now: `closed_at` and `p_as_of` both present in the
--     function's EXECUTABLE text (comments stripped — the (X6) lesson), which is true under any
--     boundary ruling and false pre-059, where the filter was `is_active`.
--     >> AN ANTI-VACUITY ANCHOR MUST BE COARSER THAN THE THING IT GUARDS. Pinned as tightly as
--        the subject, it becomes a second copy of the assertion and reds on correct changes.
select ok(
  exists (select 1 from information_schema.columns
           where table_schema = 'pfin' and table_name = 'account' and column_name = 'closed_at')
  and (select regexp_replace(pg_get_functiondef(p.oid), '--[^' || chr(10) || ']*', '', 'g')
              like '%closed_at%p_as_of%'
         from pg_proc p
        where p.pronamespace = 'pfin'::regnamespace and p.proname = 'fn_compute_nav'
          and pg_get_function_identity_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '(R3) ANTI-VACUITY: closed_at EXISTS and fn_compute_nav carries the AS-OF comparison — so (R1)/(R2) are observing a genuinely post-059 database rather than passing because nothing was ever built. Every assertion in this block is an absence, and absences are indistinguishable from "the migration never ran" without an anchor that is only true once it has. This is the conjunction the superseded (R5) reached for; it failed only because its subject never existed to be absent');

-- =====================================================================
-- BLOCK X — THE AS-OF RE-POINT  (Sec's "seventh surface")
--   `p_active_only` changes MEANING from current-state `is_active` to
--   not-closed-as-of-`p_as_of`. Two DIFFERENT things to prove (Sec):
--     1. behaviour preservation on the NEVER-CLOSED population, PER LEG;
--     2. the two-tenant x as-of matrix (BLOCK T).
--   ⚠ ASSEMBLED-SEQUENCE DISCIPLINE (ADR-040, Sec restated): `049`/`050` are edited TWICE
--     — refactored at `056`, re-pointed here. This file must be run against the REAL
--     assembled `056`-then-`059` stack, NOT `059` against a `056`-shaped assumption.
--     Reported as UNRUN pending that stack; see the header's scratch-DB note.
-- =====================================================================

select _rls.set_tenant(:'ta'::uuid);

-- (X1) THE HEADLINE — the behavioural proof of the entire ADR.
select ok(
  (select pfin.fn_compute_nav('2026-05-31'::date, true)) >= 800,
  '(X1) THE DEFECT THE MODEL REMOVES: an account CLOSED 2026-06-30 still contributes its 800 to the 2026-05-31 headline NAV. Under current-state is_active this returned a NAV excluding it — the GL and the reported number disagreed SILENTLY, with the statement-vs-GL tie-out unbuilt (BACKLOG §7.4)'
);

-- (X2) …and excluded AFTER closure. (X1) alone also passes if p_active_only were quietly
--   neutered into a no-op, which is the cheapest wrong way to make (X1) green.
select ok(
  (select pfin.fn_compute_nav('2026-07-31'::date, true))
    < (select pfin.fn_compute_nav('2026-05-31'::date, true)),
  '(X2) FAIL-CLOSED THE OTHER WAY: the same account is EXCLUDED from a 2026-07-31 NAV. Without this, (X1) also passes for a no-op p_active_only — the cheapest wrong implementation that makes (X1) green'
);

-- (X3) BEHAVIOUR PRESERVATION on the NEVER-CLOSED population (Sec requirement 1), PER LEG.
--   :aopen was never closed, so the dated predicate must return exactly what the old one
--   did. Asserted on the CASH LEG specifically via the `056` measure rather than on the
--   total, because a total can net two compensating leg errors to the right answer.
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-07-31'::date) where account_id = :aopen),
  250.0000::numeric,
  '(X3) BEHAVIOUR PRESERVATION, CASH LEG, never-closed population: :aopen reads 250 unchanged at a post-re-point as-of date. Asserted per-leg rather than on the NAV total, because a total can net two compensating leg errors into the right answer'
);

-- (X4) …and the never-closed account is included in BOTH settings of p_active_only. The
--   re-point must not have narrowed the population it was only supposed to re-predicate.
select ok(
  (select pfin.fn_compute_nav('2026-07-31'::date, true)) >= 250
  and (select pfin.fn_compute_nav('2026-07-31'::date, false)) >= 250,
  '(X4) the never-closed account is counted under BOTH p_active_only settings -> the re-point changed the PREDICATE, not the population. A re-point that accidentally narrowed the base set would still satisfy (X1)/(X2)'
);

-- (X5) ⚑ INVERTED 2026-08-04 — IT ASSERTED THE THING ADR-042 MAKES IMPOSSIBLE.
--   It read: fn_compute_nav(d, false) > fn_compute_nav(d, true), i.e. the closed account
--   carries value into the all-accounts figure. **That is unconstructible now.** A closed
--   account holds ZERO past its closing date (gate legs 1+2 at closed_at, leg 3 and the
--   transfer-in fence after it), so false and true AGREE — p_active_only is a provable no-op
--   on value. The strict `>` could only ever pass while a closed account could still hold
--   something, which is the defect this ADR removes. Same inverted-expectation shape as
--   050's (A4)/(A7), found the same way: by running it.
--   ⚠ SO THE CLAIM "FALSE STILL INCLUDES CLOSED ACCOUNTS" IS NOT OBSERVABLE BY VALUE, and
--     asserting it by value is what produced a permanently-red test. It IS observable
--     STRUCTURALLY, and precisely: both legs gate as `not p_active_only or (<as-of predicate>)`,
--     so FALSE SHORT-CIRCUITS the predicate and the all-accounts engine never evaluates it.
--     That is the property `037`'s GL memo depends on, stated where it can actually fail.
select is(
  (select ((length(d) - length(replace(d, 'not p_active_only', '')))
           / length('not p_active_only'))::int
     from (select pg_get_functiondef(p.oid) d from pg_proc p
            where p.pronamespace = 'pfin'::regnamespace and p.proname = 'fn_compute_nav'
              and pg_get_function_identity_arguments(p.oid) = 'p_as_of date, p_active_only boolean') q),
  2,
  '(X5) THE FALSE BRANCH SHORT-CIRCUITS, ON BOTH LEGS: fn_compute_nav gates the open/closed predicate behind `not p_active_only or (...)` exactly twice — once for securities, once for cash. So p_active_only=FALSE never evaluates the as-of predicate at all and the all-accounts engine `037`''s GL memo consumes is untouched by the re-point. ⚠ ASSERTED STRUCTURALLY BECAUSE IT CANNOT BE ASSERTED BY VALUE: a closed account holds zero, so false and true agree numerically and no arithmetic can distinguish "included and worth nothing" from "excluded". RED at 1 means a leg lost its short-circuit; at 0, both did');

-- (X6) `051` INHERITS THE FIX WITHOUT CHANGE. Architect: `051:152` records that it composes
--   on `049` and "adds no is_active predicate", so it needs no edit — but "needs no edit"
--   is a claim about a composition, and this is the assertion that it actually held.
--   ⚑ ANCHOR CORRECTED 2026-08-04 — IT MATCHED ITS OWN WARNING LABEL. As written this
--     scanned the WHOLE function definition, which includes `059`'s in-body comment
--     "If you came looking for 'where acc.is_active' in 049 because an older comment sent
--     you...". The check tripped on the prose that exists to PREVENT the mistake it checks
--     for, and went red against a correct function. DESIGN.md's anchoring rule, exactly:
--     anchor on the SUBJECT, not on a token that co-occurs with it. SQL comments are stripped
--     before matching, so the assertion is about EXECUTABLE text — which is what "carries no
--     predicate" was always supposed to mean.
--     (The behavioural form of this claim is 051's (A3)/(A4) propagation identity against
--     049; kept here as well because this one also catches the column surviving in a body
--     after the DROP, which a propagation identity would not notice.)
select ok(
  (select regexp_replace(pg_get_functiondef(p.oid), '--[^' || chr(10) || ']*', '', 'g')
            not like '%is_active%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  '(X6) `051` fn_nav_composition carries NO is_active reference in its EXECUTABLE text, so it inherits the re-point through `049` rather than needing an edit. Comments are stripped before matching — the un-stripped form matched `059`''s own in-body warning against looking for that predicate, and went red on a correct function. Also catches the dropped column surviving in a function body'
);
select set_config('role', 'postgres', true);

-- (X7) ⭐ FAIL-CLOSED ON A MISSING ACCOUNT ROW — the null-handling the re-point had to
--   preserve, and the one place a naive translation would have flipped the semantics.
--   ⟦VERIFIED at `422f85f` by diffing the committed body against live pg_get_functiondef:
--     securities leg, BEFORE : where (not p_active_only or coalesce(acc2.is_active, false))
--     securities leg, AFTER  : where (not p_active_only or (acc2.account_id is not null
--                                     and (acc2.closed_at is null or acc2.closed_at > p_as_of)))
--     The `coalesce(..., false)` was doing the fail-closed work on a LEFT JOIN MISS. A naive
--     swap to `(acc2.closed_at is null or ...)` alone would have INVERTED it: a missing
--     account row yields NULL closed_at, `NULL is null` is TRUE, and the orphan holding
--     would be INCLUDED in an active-only NAV instead of excluded. The explicit
--     `acc2.account_id is not null` conjunct is what preserves the original semantics.⟧
--   This is a fail-OPEN a text review passes: both versions read as "is it closed?", both
--   are syntactically fine, and the difference only appears on a row that does not exist.
select set_config('role', 'postgres', true);
-- ⚑⚑ REWRITTEN 2026-08-04. TWO DEFECTS, AND THE SECOND IS THE ONE THAT MATTERS.
--   (1) THE FIXTURE IS UNCONSTRUCTIBLE. It inserted a holdings_checkpoint row for
--       account_id 999999999. Measured: that INSERT is refused — `holdings_checkpoint
--       .account_id` carries an FK to pfin.account, and `017`'s cross-tenant security fence
--       raises first ("security_id N is not a global or account-owned asset for account_id
--       999999999") because no account row exists to own it. Nor can the orphan be made by
--       deleting the account afterwards: BOTH FKs on this table are ON DELETE RESTRICT
--       (measured). **The LEFT JOIN miss this conjunct guards is unreachable through the
--       schema.** Same class as the value-bearing-inactive account 049/050 had to stop
--       fabricating — and the same answer: do not disable a fence to build a state the
--       system prevents.
--   (2) ⚠ THE ASSERTION WAS A TAUTOLOGY. It read
--         is( fn_compute_nav('2026-07-31', true), fn_compute_nav('2026-07-31', true) )
--       — the SAME expression on both sides. It could not fail for any implementation, any
--       fixture, any predicate. **The most elaborately justified assertion in this file, with
--       a verified before/after diff of the exact fail-open it guards, asserted nothing.**
--       A rich justification block is not evidence the assertion under it is wired up; if
--       anything it discourages reading the two lines beneath. Found by running the file.
--   >> SO IT IS PROVEN STRUCTURALLY, which is the honest instrument when the behavioural one
--      is unreachable BY CONSTRUCTION rather than merely unbuilt. The conjunct is real, its
--      absence is a genuine fail-OPEN, and the FK is what currently makes it belt-and-braces
--      rather than sole defence — so it must not be removed as redundant either.
select ok(
  (select pg_get_functiondef(p.oid) like '%acc2.account_id is not null%'
     from pg_proc p
    where p.pronamespace = 'pfin'::regnamespace and p.proname = 'fn_compute_nav'
      and pg_get_function_identity_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '(X7) FAIL-CLOSED ON A LEFT-JOIN MISS: the securities leg carries the explicit `acc2.account_id is not null` conjunct. Pre-re-point this work was done by `coalesce(acc2.is_active, false)`; the naive swap to `(acc2.closed_at is null or ...)` INVERTS it, because a missing account row yields NULL closed_at, `NULL is null` is TRUE, and an orphan holding gets COUNTED in an active-only NAV. A text review passes both — they read identically and differ only on a row that does not exist. ⚠ STRUCTURAL BECAUSE THE STATE IS UNCONSTRUCTIBLE: the FK plus 017''s fence make an orphan holdings row unreachable (measured), so no fixture can drive this. RED means the fail-closed conjunct was dropped');

-- ┌─ ⚠ NAMED GAP — PREFIX SAFETY IS NOT ASSERTED HERE, AND CANNOT BE ────────────────┐
-- │ THE PROPERTY: every prefix of `059` is a valid state — in particular there is no   │
-- │ prefix in which a `closed_at`-set row is counted as ACTIVE by NAV. Verified by      │
-- │ reading `f699a62`: the re-point of 049/050 is at statements 107/234, every drop is  │
-- │ at 298+. Re-point precedes removal, so the window cannot open.                      │
-- │                                                                                     │
-- │ WHY NO ASSERTION. All three candidate homes are dead, each for its own reason —     │
-- │ and the property is FULLY DISCHARGED WITHOUT A TEST, deliberately:                  │
-- │  (1) build each prefix in a rolled-back txn from an INLINED copy of `059`.           │
-- │      REJECTED (Sec) on a ground stronger than cost: it is regression protection for  │
-- │      a file that BY CONVENTION IS MERGED ONCE AND NEVER EDITED. The ordering risk    │
-- │      lived at authoring time and was caught at review. **The copy's divergence is    │
-- │      live from the day it lands; the risk it covers is already closed.**             │
-- │  (2) reconstruct the BAD ordering here and assert it is unsafe — impossible: this    │
-- │      battery's stack is `059`-APPLIED, so `is_active` is already gone. Recorded so   │
-- │      it is not re-proposed; it is not a judgment, it is unreachable.                 │
-- │  (3) assert structurally that no drop precedes the re-point WITHIN `059`.            │
-- │      DROPPED ENTIRELY — for TWO independent reasons, either sufficient:               │
-- │      (a) WRONG INSTRUMENT. That is a claim about MIGRATION FILE TEXT, and pgTAP reads │
-- │          a database, not a repository. Post-`059` every statement has run and the     │
-- │          ordering leaves no trace in the catalog.                                     │
-- │      (b) AND RELOCATING IT TO CI DOES NOT SAVE IT (Sec, applying their own argument   │
-- │          against (1) consistently): a lint asserting statement order in `059`         │
-- │          protects against an EDIT TO `059` THAT WILL NOT HAPPEN. It is cheaper than   │
-- │          (1) and covers the identical closed risk. **Cheap protection of a closed     │
-- │          risk is zero value plus maintenance.** "Non-vacuous" was the wrong bar;      │
-- │          *covers a live risk* is the bar.                                             │
-- │      Recorded because the instinct that kept it alive — leaving SOMETHING rather than │
-- │      nothing — is the same instinct that produced the withdrawn `prosrc` gate:        │
-- │      **building to the shape of diligence rather than to the risk.**                  │
-- │                                                                                     │
-- │ WHERE THE PROPERTY DOES LIVE: `059`'s own header (Architect), stated for the only    │
-- │ consumer it has — an operator mid-incident on a non-CLI path (`psql -f`, a hand-run) │
-- │ deciding whether to stop, continue or roll back. **A green battery in CI does        │
-- │ nothing for that person.** Siting the statement where the confusion happens is the   │
-- │ same argument as every other placement decision in this review.                      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- =====================================================================
-- BLOCK T — THE TWO-TENANT x AS-OF MATRIX  (Sec requirement 2)
--   `050` is SECURITY INVOKER so isolation is INHERITED RLS and should be unchanged. But
--   the predicate is being rewritten, and a DATED predicate resolved through a join that
--   is not tenant-scoped would LEAK WHILE EVERY SINGLE-TENANT TEST STAYS GREEN. Sec:
--   "precisely the shape worth a battery rather than an assumption."
--   The matrix is (tenant A, tenant B) x (before closure, after closure) — because a leak
--   introduced by the dated predicate could be closure-state-dependent, and a single-date
--   probe would miss it.
-- =====================================================================
select is(
  (select _rls.count_as(:'ta'::uuid, null,
     $$ select count(*) from pfin.account where users_id = '00000000-0000-0000-0000-00000000000b' $$)),
  0::bigint,
  '(T1) baseline isolation: A sees ZERO of B''s account rows — the driving table of both NAV legs is tenant-filtered before any dated predicate is applied'
);
select _rls.set_tenant(:'tb'::uuid);
select ok(
  (select pfin.fn_compute_nav('2026-05-31'::date, true)) < 9999.0001
  and (select pfin.fn_compute_nav('2026-05-31'::date, true)) >= 9999,
  '(T2) AS-OF x TENANT, BEFORE the closure boundary: B''s NAV at 2026-05-31 is exactly B''s own 9999 — it does NOT include A''s 800. A dated predicate resolved through a join that is not tenant-scoped leaks here while every single-tenant test stays green'
);
select ok(
  (select pfin.fn_compute_nav('2026-07-31'::date, true)) < 9999.0001
  and (select pfin.fn_compute_nav('2026-07-31'::date, true)) >= 9999,
  '(T3) AS-OF x TENANT, AFTER the closure boundary: B''s NAV at 2026-07-31 is still exactly its own 9999, unaffected by A closing an account. Asserted at BOTH dates because a leak introduced by the dated predicate could be closure-state-dependent, and a single-date probe would miss exactly that'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
