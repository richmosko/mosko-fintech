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

-- plan = 16: R (reconciliation + drop) 7 · X (as-of re-point) 6 · T (two-tenant x as-of) 3.
select plan(16);

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

update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :aclosed;

-- =====================================================================
-- BLOCK R — RECONCILIATION + THE DROP  (Sec revised cases 3 / 4 / 5)
--   All at role=postgres (owner). See the header: calling as authenticated makes the
--   INVOKER body pass vacuously for every other tenant.
-- =====================================================================

-- (R1) SEC CASE 5 — nothing to reconcile. The production state today (`pfin.account` = 4
--   rows, all active, zero inactive — measured 2026-08-03), and therefore the branch that
--   ships UNEXERCISED unless something makes it fire. It is the NON-VACUOUS ANCHOR: without
--   it, (R2)/(R3) could both be passing against a function that aborts unconditionally.
savepoint sp_r1;
update pfin.account set is_active = (closed_at is null);  -- force the biconditional true
select lives_ok(
  $$ select pfin.fn_assert_closure_reconciled() $$,
  '(R1) SEC CASE 5: with the biconditional holding on every row, the reconciliation PASSES. NON-VACUOUS ANCHOR — without it (R2)/(R3) could both pass against a function that aborts unconditionally, and the abort assertions would prove nothing'
);
rollback to savepoint sp_r1;

-- (R2) SEC CASE 3 — is_active = false while closed_at IS NULL. The account someone
--   deactivated under the OLD mis-implementation and never dispositioned through the gate.
savepoint sp_r2;
update pfin.account set is_active = (closed_at is null);
update pfin.account set is_active = false where account_id = :aopen;  -- inactive, not closed
select throws_like(
  $$ select pfin.fn_assert_closure_reconciled() $$,
  :'m_reconcile',
  '(R2) SEC CASE 3: an account with is_active = false and closed_at IS NULL ABORTS the migration. This is the un-dispositioned row — deactivated under the old flag, never validated by the gate — and dropping is_active with it unresolved makes which accounts were wrongly deactivated PERMANENTLY UNRECOVERABLE on a financial surface'
);
rollback to savepoint sp_r2;

-- (R3) SEC CASE 4 — the REVERSE mismatch: closed_at set while is_active is still true.
--   Asserted separately from (R2) because they fail for opposite reasons and a
--   one-directional check passes one of them while looking complete.
savepoint sp_r3;
update pfin.account set is_active = (closed_at is null);
update pfin.account set is_active = true where account_id = :aclosed;  -- closed, but active
select throws_like(
  $$ select pfin.fn_assert_closure_reconciled() $$,
  :'m_reconcile',
  '(R3) SEC CASE 4, REVERSE MISMATCH: closed_at SET while is_active is still TRUE also ABORTS. Asserted separately from (R2) because the two fail for opposite reasons — a one-directional check passes this one while appearing complete. This is also the exact state a MISSING `058` sync trigger produces'
);
rollback to savepoint sp_r3;

-- (R4) THE BICONDITIONAL IS THE PROPERTY, stated directly. The reconciliation is not "count
--   the inactive rows" — it is an IFF over every row, in both directions.
select is(
  (select count(*)::int from pfin.account
    where (is_active = false) is distinct from (closed_at is not null)),
  0,
  '(R4) THE BICONDITIONAL, directly: zero rows where (is_active = false) differs from (closed_at IS NOT NULL). Asserted independently of the function so a reconciliation that silently checks only one direction is visible here even if (R2)/(R3) were mis-wired'
);

-- (R5) ORDERING — the assert function is GONE after `059`. It READS a column this migration
--   DROPS, so surviving it means a function that raises at runtime on any future call:
--   worse than dead code, because the error reads as "reconciliation failed".
select ok(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_assert_closure_reconciled') = 0
  and not exists (select 1 from information_schema.columns
                   where table_schema = 'pfin' and table_name = 'account'
                     and column_name = 'is_active'),
  '(R5) ORDERING: fn_assert_closure_reconciled no longer EXISTS **and** is_active is already dropped — i.e. we are genuinely post-`059`. CONJOINED DELIBERATELY: the absence half alone passes VACUOUSLY at every point before `059` creates the function, so as first written this assertion was green on a database where nothing had happened. Caught by running Sec''s correspondence check against my own split. The function reads is_active; surviving the drop leaves a function that raises at runtime on any future call, with error text reading "reconciliation failed" when nothing failed. This is the ONLY permanent assertion about it — a standing test that CALLS it would go red for the right reason and read as a regression'
);

-- (R6) …and while it existed it was unreachable from a tenant session. This is the
--   structural fence behind the call-as-owner requirement: under `authenticated` the
--   INVOKER body sees one tenant's rows and passes vacuously for every other tenant.
--   Asserted as a NEGATIVE over the whole catalog so it survives the function's removal.
select ok(
  not exists (
    select 1 from information_schema.routine_privileges
     where routine_schema = 'pfin' and routine_name = 'fn_assert_closure_reconciled'
       and grantee in ('authenticated', 'anon', 'PUBLIC')),
  '(R6) the assert function was never EXECUTE-able by authenticated/anon/PUBLIC. Load-bearing rather than hygiene: it is SECURITY INVOKER, so called under a tenant role its body evaluates over that tenant''s rows only and PASSES VACUOUSLY for every other tenant — a green from exactly the call path a test reaches for first'
);

-- (R7) THE COLUMN IS GONE, and the transitional sync trigger with it.
select hasnt_column('pfin', 'account', 'is_active',
  '(R7a) ONE-WAY DOOR: pfin.account.is_active is DROPPED, not retained-as-derived. A retained boolean cannot answer an as-of question, so any future query reaching for it in an as-of context is silently wrong — the exact defect this model removes');

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

-- (X5) p_active_only = FALSE still includes closed accounts — the book/as-of engine
--   (`037` GL memo + historical trend) is unchanged.
select ok(
  (select pfin.fn_compute_nav('2026-07-31'::date, false))
    > (select pfin.fn_compute_nav('2026-07-31'::date, true)),
  '(X5) p_active_only = FALSE still includes closed accounts -> only the TRUE branch changed meaning; the book/as-of engine consumed by `037`''s GL memo is untouched'
);

-- (X6) `051` INHERITS THE FIX WITHOUT CHANGE. Architect: `051:152` records that it composes
--   on `049` and "adds no is_active predicate", so it needs no edit — but "needs no edit"
--   is a claim about a composition, and this is the assertion that it actually held.
select ok(
  (select pg_get_functiondef(p.oid) not like '%is_active%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  '(X6) `051` fn_nav_composition carries NO is_active predicate of its own, so it inherits the re-point through `049` rather than needing an edit. Architect asserts this from `051:152`; this is the mechanical confirmation, and it would also catch the column surviving in a function body after the DROP'
);
select set_config('role', 'postgres', true);

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
