-- =====================================================================
-- Per-Wave battery — pfin.cashflow_target: per-user Lock-14 cash-flow target
--   settings (income_target_annual, expense_target_monthly), ONE wide row per
--   user, unique(users_id) as the UPSERT conflict target + full authenticated
--   CRUD RLS + the 025 aal2 step-up backstop on every policy + SD-22 DELETE-
--   policy fence (SECURITY §4.6, never trimmed) (SELF-246 AC12; V1-SHIP-BLOCK;
--   JOINT-REVIEW-MANDATORY per the migration's own Sec-gate)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/090_cashflow_target.sql
--   - pfin.cashflow_target (id, users_id NOT NULL DEFAULT auth.uid() -> auth.users
--       ON DELETE CASCADE, income_target_annual numeric(20,4) NULL, expense_target_
--       monthly numeric(20,4) NULL, created/updated_at, unique(users_id)). Both
--       amount columns: CHECK (x is null or (x >= 0 and x <> 'NaN'::numeric)) —
--       TWO-SIDED, because NaN is storable in a constrained numeric and sorts
--       above every non-NaN numeric, so a one-sided >= 0 would ADMIT it.
--   - RLS direct-owner (users_id = auth.uid()) ANDed with the ADR-029/025 aal2
--       backstop clause on ALL FOUR policies (select/insert/update/delete); full
--       authenticated CRUD; anon zero-grant; service_role UNGRANTED.
--   - trigger cashflow_target_set_updated_at (reuses the 001 DEFINER allowlist
--       entry). This migration authors NO function and NO BEFORE INSERT fence —
--       unlike 074's sibling, there is no matched-sub_cat trigger here (Decision 3
--       family +0, no FK-shaped column beyond the users_id tenant anchor), so
--       WITH CHECK is DIRECTLY behaviourally reachable on INSERT — no §9
--       BEFORE-trigger shadowing applies to this table (contrast 074's (M5)).
-- Prereqs exercised (already on main / applied by Backend on the reset stack): 001
--   (pfin schema + fn_refresh_updated_at), 024 (pfin.user_settings.mfa_policy —
--   user_settings_select is the NON-NEGOTIABLE aal2 EXCLUSION per 025's own header,
--   so the backstop's subquery reads it at aal1 with no shadowing), 025 (the aal2
--   backstop clause shape this migration reuses byte-faithfully), auth.users.
-- Reuses the 074/025/012/... idiom: \ir verbs, ALL-LOWERCASE \gset literals,
--   MESSAGE-precise throws_like / SQLSTATE-precise throws_ok, role restored to
--   postgres between blocks (PR #121 root-cause), savepoint/rollback around every
--   exception-raising probe and every ALTER POLICY corruption.
--
-- ┌─ AC12 CORE LEG — the DELETE-policy leg isolates that policy's OWN clause ────┐
-- │ The migration's own DELETE POLICY comment (090:115-128) states the mechanism │
-- │ this leg exists to prove: Postgres consults the SELECT policy during a       │
-- │ DELETE only when the statement READS OR FILTERS BY A COLUMN. A cross-tenant  │
-- │ DELETE assertion written WITH a `where users_id = ...` filter is therefore   │
-- │ satisfied by EITHER policy (SELECT's USING or DELETE's USING, ANDed) and     │
-- │ proves nothing about the DELETE policy specifically — this is the exact      │
-- │ measurement QA made on 074/(M12), 2026-08-20, and the reason AC12 requires a │
-- │ different instrument here rather than reusing (M12)'s shape.                 │
-- │ BLOCK DEL below runs the cross-tenant probe as an UNQUALIFIED                │
-- │ `delete from pfin.cashflow_target;` — NO WHERE, no column reference — so the │
-- │ SELECT policy is never consulted at all; only cashflow_target_delete's own   │
-- │ USING clause gates which rows the intruder's blanket delete can touch. (DEL1)│
-- │ is the real-world proof (A's row survives an unqualified delete issued by    │
-- │ B); (DEL2)/(DEL3) are the complementary corrupt-the-control pair AC12 asks   │
-- │ for — corrupting DELETE's clause alone (open) and SELECT's clause alone      │
-- │ (open), independently, to show which corruption moves the result. Per §8's   │
-- │ "when a control fails closed, corrupt it — do not delete it" rule (a dropped │
-- │ policy default-denies and would pass on the nothing).                        │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ UNSET SEMANTICS — UPSERT-to-NULL, never a row DELETE (090:46-61) ───────────┐
-- │ This table carries TWO independent scalars in ONE row, so a row DELETE would │
-- │ unset BOTH columns at once — the SELF-242/074 DELETE-as-unset verb does NOT  │
-- │ transplant here (090's own header states this explicitly). BLOCK U proves    │
-- │ the actual mechanism: an UPSERT that names only ONE column in its DO UPDATE  │
-- │ SET leaves the sibling column untouched, the row survives, and a stored 0 is │
-- │ a different, storable fact from NULL (0 is a target — "spend nothing"; NULL  │
-- │ is "never set one"). Two independent scalars -> two independent fixtures per │
-- │ DESIGN.md's "count the predicates, then check each has a fixture" rule.      │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NaN vs ±Infinity — two distinct mechanisms, two distinct SQLSTATEs (090:72-88)┐
-- │ ±Infinity is refused by the numeric(20,4) TYPMOD before it ever reaches the   │
-- │ CHECK (22003, numeric field overflow). NaN IS storable and reaches the CHECK, │
-- │ where the explicit `<> 'NaN'::numeric` literal refuses it (23514). BLOCK N    │
-- │ asserts both SQLSTATEs, on BOTH columns independently (the CHECK is written   │
-- │ once per column, so a regression on one column's literal must be caught      │
-- │ without relying on the sibling column's CHECK still being correct).          │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 catalogued ledger — read ADR-011 Decision 4 live, never
--   from here; 090 adds ZERO catalogued instances (Lock-14 user-facing-direct-DB-
--   write surface; SD-22 already scopes it). Decision-3 family: +0, NO LABEL — a
--   `users_id -> auth.users` tenant anchor is not a cross-tenant reference and no
--   other FK-shaped column exists on this table (090's own header + rederived-acs
--   AC5-strike both confirm this; this file carries NO tally and no BLOCK-L
--   matched-sub_cat legs, unlike 074, because there is no such fence to prove).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(), plus a raw literal for the totp tenant (D,
--   suffixed '90' to keep this file's fixture diffable against other batteries'
--   fixed literals in the same cluster — each file's txn rolls back independently
--   so collision is not actually live). NO PII / NO real account numbers / NO
--   prod data. All inside one rolled-back transaction.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated, so NO `_rls.*` call runs under authenticated. Tenant UUIDs are
--   resolved to psql LITERALS via \gset at role=postgres; every _rls.set_tenant(_aal)
--   call happens at role=postgres and each block restores role=postgres before the
--   next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 090's committed contract; verified against a
--   hand-built scratch DB — `createdb` + auth/extensions/vault schemas dumped from
--   the live local Supabase container, `pgtap` installed in `public` (not
--   `extensions` — role-search-path gotcha), migrations 001->090 applied
--   SEQUENTIALLY in order as `postgres` (never a TEMPLATE clone — that drops
--   per-database `ALTER DATABASE ... SET` rows silently), verified via `pg_prove`
--   (never bare `psql` — a plan under-run exits 0 there). `supabase db reset` is
--   mechanically banned and was not used; F/CTO's local dev DB was not touched.
--   plan(39): 7 structural (S1-S5 + S6a-S6b) + 3 fresh-row single-column INSERT,
--   row-absent (F1a-F1c) + 1 unique-per-user (UQ1) + 6 numeric mechanism, both
--   columns (N1-N6) + 5 UPSERT/unset/zero-vs-null (U1a-U1c, U2a-U2b) + 2
--   two-tenant read isolation (R1-R2) + 2 cross-tenant write blocked (W1-W2) +
--   3 DELETE-policy isolation + corrupt-the-control pair (DEL1-DEL3) + 1
--   corrupt-SELECT exact-value leak (X1) + 8 aal2 backstop, all four verbs
--   (M1-M8) + 1 anon zero-grant (G1) = 39.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(39);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-000000000d90'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users: A/B (plain 'none' mfa_policy — the two-tenant
--    cross-read/write/delete baseline), D (totp — the aal2 backstop subject,
--    seeded with NO cashflow_target row; BLOCK M builds D's row itself via
--    authenticated INSERT so the INSERT leg of the aal2 backstop gets exercised
--    too, unlike a service_role pre-seed which would skip it).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- BLOCK S (postgres — pg_policy catalog) — STRUCTURAL presence proof,
--   independent of any behavioural path (declaratively, from pg_policies).
-- =====================================================================
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass and polname = 'cashflow_target_select'),
  '(S1) STRUCTURAL: cashflow_target_select carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass and polname = 'cashflow_target_insert'),
  '(S2) STRUCTURAL: cashflow_target_insert carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass and polname = 'cashflow_target_update'),
  '(S3) STRUCTURAL: cashflow_target_update carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass and polname = 'cashflow_target_update'),
  '(S4) STRUCTURAL: cashflow_target_update carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass and polname = 'cashflow_target_delete'),
  '(S5) STRUCTURAL: cashflow_target_delete carries its OWN USING expression referencing users_id = auth.uid() (pg_policy catalog) — the SD-22 / SECURITY §4.6 fence, never trimmed on the reasoning that SELECT already covers it'
);

-- (S6a)/(S6b) — SPLIT by clause half (074/(S3a-S3b) precedent): an OR-combined
--   single count would go green if aal2 survives in EITHER half of a policy,
--   masking a WITH-CHECK-only regression on cashflow_target_update. USING-half:
--   select/update/delete (3 policies with a USING clause). WITH CHECK-half:
--   insert/update (2 policies with a WITH CHECK clause).
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'),
  3::bigint,
  '(S6a) STRUCTURAL — USING half: select/update/delete all carry the ADR-029/025 aal2 backstop in polqual — RED if any USING-side aal2 clause were dropped, independent of the WITH CHECK half'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.cashflow_target'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'),
  2::bigint,
  '(S6b) STRUCTURAL — WITH CHECK half: insert/update both carry the ADR-029/025 aal2 backstop in polwithcheck — RED if cashflow_target_update''s WITH CHECK lost its aal2 clause while USING kept it'
);

-- =====================================================================
-- BLOCK F (authenticated A, ROW ABSENT — genuinely A's FIRST row, unlike
--   BLOCK U's (U1)/(U2) which UPSERT-clobber an ALREADY-EXISTING row via an
--   explicit `on conflict do update set <one column>`). SELF-252's write path
--   (POST /api/settings/cashflow-target) builds its upsert row object from
--   ONLY the dirty keys (+server.ts), so a user's very FIRST save touching
--   just one field sends a single-column row to an ABSENT row. The mechanism
--   that makes the sibling column land NULL here is plain Postgres INSERT
--   column-list omission -> column DEFAULT (NULL, no default specified) — NOT
--   the DO-UPDATE-SET narrowing BLOCK U proves. Wrapped in a savepoint/
--   rollback so BLOCK 1 below still seeds A's row from a clean, row-absent
--   state.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_f1;
insert into pfin.cashflow_target (income_target_annual) values (1234.56);
select is(
  (select count(*) from pfin.cashflow_target where users_id = auth.uid())::bigint,
  1::bigint,
  '(F1a) fresh single-column INSERT (row was ABSENT for A): the row now exists — one column named, one row created'
);
select is(
  (select income_target_annual from pfin.cashflow_target where users_id = auth.uid()),
  1234.56::numeric(20,4),
  '(F1b) fresh single-column INSERT: the NAMED column (income_target_annual) round-trips as given'
);
select ok(
  (select expense_target_monthly is null from pfin.cashflow_target where users_id = auth.uid()),
  '(F1c) fresh single-column INSERT: the OMITTED column (expense_target_monthly) lands NULL via plain column-DEFAULT on a row that did not exist a moment ago — NOT via BLOCK U''s DO-UPDATE-SET narrowing (this is a different mechanism from (U1)/(U2), exercised on a row-absent INSERT rather than an existing row''s UPSERT) — RED if the app-layer write object ever grew an implicit default value for an omitted key instead of leaving the column to Postgres'
);
rollback to savepoint sp_f1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 1 (authenticated A) — seed A's real committed row. Both columns SET
--   (non-NULL) so BLOCK N's CHECK probes have real, storable starting values,
--   and BLOCK U's UPSERT-to-NULL has something real to null out.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.cashflow_target (income_target_annual, expense_target_monthly)
  values (60000.00, 2000.00);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK UQ (authenticated A) — unique(users_id): a second row for the SAME
--   tenant is refused (23505), independent of column values.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_uq1;
select throws_ok(
  $$ insert into pfin.cashflow_target (income_target_annual) values (999.00) $$,
  '23505', null,
  '(UQ1) unique(users_id): A''s second INSERT (users_id defaults to auth.uid()=A again) is refused (23505 unique_violation) — one row per user by construction'
);
rollback to savepoint sp_uq1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK N (authenticated A) — NaN / negative / +Infinity on BOTH amount
--   columns, via UPDATE + savepoint/rollback against A's seeded row (still
--   60000.00 / 2000.00 at this point — BLOCK U runs after this block).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (N1) income NaN -> storable, reaches the CHECK, caught by the explicit
--      <> 'NaN'::numeric literal -> 23514.
savepoint sp_n1;
select throws_ok(
  $$ update pfin.cashflow_target set income_target_annual = 'NaN'::numeric where users_id = auth.uid() $$,
  '23514', null,
  '(N1) income_target_annual NaN rejected (23514 check_violation) — NaN IS storable in numeric(20,4) and reaches the CHECK, where the explicit <> ''NaN''::numeric literal (014/053 idiom) refuses it'
);
rollback to savepoint sp_n1;

-- (N2) income negative -> caught by the lower bound -> 23514.
savepoint sp_n2;
select throws_ok(
  $$ update pfin.cashflow_target set income_target_annual = -100.00 where users_id = auth.uid() $$,
  '23514', null,
  '(N2) income_target_annual negative (-100.00) rejected (23514 check_violation) — the lower bound half of the two-sided CHECK'
);
rollback to savepoint sp_n2;

-- (N3) income +Infinity -> refused by the numeric(20,4) TYPMOD BEFORE the
--      CHECK is ever consulted -> 22003, a DIFFERENT SQLSTATE from (N1)/(N2).
savepoint sp_n3;
select throws_ok(
  $$ update pfin.cashflow_target set income_target_annual = 'Infinity'::numeric where users_id = auth.uid() $$,
  '22003', null,
  '(N3) income_target_annual +Infinity rejected by the numeric(20,4) TYPMOD (22003 numeric_value_out_of_range) — a DIFFERENT mechanism and SQLSTATE than (N1)''s CHECK violation: the typmod refuses the value before the CHECK is ever reached'
);
rollback to savepoint sp_n3;

-- (N4) expense NaN -> the CHECK is written ONCE PER COLUMN; a regression on
--      this column's literal must be caught independent of income's CHECK.
savepoint sp_n4;
select throws_ok(
  $$ update pfin.cashflow_target set expense_target_monthly = 'NaN'::numeric where users_id = auth.uid() $$,
  '23514', null,
  '(N4) expense_target_monthly NaN rejected (23514 check_violation) — same mechanism as (N1), asserted independently on the SIBLING column''s own CHECK'
);
rollback to savepoint sp_n4;

-- (N5) expense negative -> 23514.
savepoint sp_n5;
select throws_ok(
  $$ update pfin.cashflow_target set expense_target_monthly = -50.00 where users_id = auth.uid() $$,
  '23514', null,
  '(N5) expense_target_monthly negative (-50.00) rejected (23514 check_violation) — the lower bound half, asserted independently on the sibling column'
);
rollback to savepoint sp_n5;

-- (N6) expense +Infinity -> 22003.
savepoint sp_n6;
select throws_ok(
  $$ update pfin.cashflow_target set expense_target_monthly = 'Infinity'::numeric where users_id = auth.uid() $$,
  '22003', null,
  '(N6) expense_target_monthly +Infinity rejected by the numeric(20,4) TYPMOD (22003) — same distinct mechanism as (N3), asserted independently on the sibling column'
);
rollback to savepoint sp_n6;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK U (authenticated A) — AC12's UPSERT-to-NULL leg. A's row is still
--   (60000.00, 2000.00) here (BLOCK N's probes were all rolled back).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (U1) UPSERT names ONLY expense_target_monthly in its DO UPDATE SET -> sets
--      it to NULL, leaves income_target_annual UNTOUCHED, row SURVIVES (no
--      DELETE — the migration's own POSTURE for this table's unset mechanism).
insert into pfin.cashflow_target (expense_target_monthly) values (null)
  on conflict (users_id) do update set expense_target_monthly = excluded.expense_target_monthly;

select is(
  (select count(*) from pfin.cashflow_target where users_id = auth.uid())::bigint,
  1::bigint,
  '(U1a) UPSERT-to-NULL: the row SURVIVES (still exactly 1 row) — unset is NULL written in place, never a row DELETE'
);
select ok(
  (select expense_target_monthly is null from pfin.cashflow_target where users_id = auth.uid()),
  '(U1b) UPSERT-to-NULL: expense_target_monthly is now NULL (round-trips as NULL)'
);
select is(
  (select income_target_annual from pfin.cashflow_target where users_id = auth.uid()),
  60000.00::numeric(20,4),
  '(U1c) UPSERT-to-NULL: income_target_annual is UNTOUCHED (still 60000.00) — the DO UPDATE SET named only expense_target_monthly, proving one column''s unset write does not disturb its independent sibling'
);

-- (U2) a stored 0 is a DIFFERENT, storable, user-asserted fact from NULL —
--      UPSERT income_target_annual to 0.00 (expense_target_monthly, set to
--      NULL by (U1), stays untouched by this UPSERT's own DO UPDATE SET).
insert into pfin.cashflow_target (income_target_annual) values (0.00)
  on conflict (users_id) do update set income_target_annual = excluded.income_target_annual;

select is(
  (select income_target_annual from pfin.cashflow_target where users_id = auth.uid()),
  0.00::numeric(20,4),
  '(U2a) explicit 0.00 IS a storable fact, distinct from NULL: income_target_annual is now 0.00 (a stated target, "intend to earn/spend nothing"), not unset'
);
select ok(
  (select expense_target_monthly is null from pfin.cashflow_target where users_id = auth.uid()),
  '(U2b) expense_target_monthly is STILL NULL (untouched by the income-only UPSERT) — same row, two independent scalars, one now 0.00 and one still NULL: 0 and NULL are simultaneously distinguishable on sibling columns of the SAME row'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK R (postgres — _rls verbs) — two-tenant read isolation. A owns exactly
--   1 row at this point (income=0.00, expense=NULL, per BLOCK U).
-- =====================================================================
-- (R1) owner-reads-own: A sees exactly its 1 row (guards an over-restrictive policy).
select _rls.expect_owner_can_read('pfin.cashflow_target'::regclass, :'ta'::uuid, 1::bigint);

-- (R2) cross-tenant read fails closed: B sees 0 of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.cashflow_target'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK W (authenticated B) — cross-tenant WRITE fails closed (INSERT forge +
--   UPDATE no-op). A's row is (0.00, NULL) throughout this block.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (W1) B forges users_id=A on an INSERT -> RLS WITH CHECK requires
--      users_id = auth.uid() = B -> mismatch -> rejected (42501), no
--      BEFORE-trigger in front of this table to shadow the conjunct (unlike
--      074/(M5) — see the header box).
savepoint sp_w1;
select throws_ok(
  format($$ insert into pfin.cashflow_target (users_id, income_target_annual) values (%L, 500.00) $$, :'ta'),
  '42501', null,
  '(W1) cross-tenant INSERT forge: B inserts claiming users_id=A -> RLS WITH CHECK rejects (42501) -- directly behaviourally reachable (no trigger shadows this conjunct on cashflow_target)'
);
rollback to savepoint sp_w1;

-- (W2) B's UPDATE targets A's row by users_id -> USING filters it to 0 rows
--      (silently, no exception) -> A's row is UNCHANGED.
update pfin.cashflow_target set income_target_annual = 999.00 where users_id = :'ta';
select set_config('role', 'postgres', true);
select ok(
  (select income_target_annual = 0.00 and expense_target_monthly is null
     from pfin.cashflow_target where users_id = :'ta'),
  '(W2) cross-tenant UPDATE: B''s update where users_id=A matches 0 rows under RLS (USING filters it out) -- A''s row is UNCHANGED (income still 0.00, expense still NULL)'
);

-- =====================================================================
-- BLOCK DEL (authenticated B, then corrupted) — AC12's core leg: the
--   DELETE-policy isolation, via an UNQUALIFIED delete (no WHERE, no column
--   reference at all) so the SELECT policy is never consulted (see header box).
-- =====================================================================
-- (DEL1) REAL WORLD: B issues an unqualified `delete from pfin.cashflow_target;`
--        (B owns no row of its own) -> cashflow_target_delete's OWN USING
--        clause is the SOLE gate (no WHERE for the SELECT policy to be
--        consulted through) -> 0 rows match B's tenant -> A's real row SURVIVES.
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.cashflow_target;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'ta')::bigint,
  1::bigint,
  '(DEL1) AC12 CORE: unqualified cross-tenant DELETE (no WHERE) issued by B -- A''s real row SURVIVES. Non-vacuous: A''s row genuinely exists in the table when B''s blanket delete runs, so survival is the DELETE policy''s own USING clause actively filtering it out, not an empty match by construction'
);

-- (DEL2) CORRUPT-THE-CONTROL, half 1: break cashflow_target_delete''s OWN
--        clause open. The IDENTICAL unqualified delete now REMOVES A's row --
--        proving (DEL1)'s survival really is DELETE's own clause at work.
savepoint sp_del2;
alter policy cashflow_target_delete on pfin.cashflow_target using (true);
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.cashflow_target;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'ta')::bigint,
  0::bigint,
  '(DEL2) CORRUPT-THE-CONTROL (DELETE clause broken OPEN): the SAME unqualified delete by B now REMOVES A''s row -- proves cashflow_target_delete''s own USING clause is what gated (DEL1), not RLS default-deny on an empty match'
);
rollback to savepoint sp_del2;

-- (DEL3) CORRUPT-THE-CONTROL, half 2 (the complementary half AC12 asks for):
--        restore DELETE's real clause (done by the rollback above); instead
--        break cashflow_target_select open ALONE. The unqualified delete
--        STILL leaves A's row untouched -- proving SELECT's clause is
--        IRRELEVANT to an unqualified delete, isolating that (DEL1)'s
--        survival is DELETE's clause ALONE, independent of SELECT's.
savepoint sp_del3;
alter policy cashflow_target_select on pfin.cashflow_target using (true);
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.cashflow_target;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'ta')::bigint,
  1::bigint,
  '(DEL3) COMPLEMENTARY CONTROL (SELECT clause broken open ALONE, DELETE''s own clause real): the unqualified delete by B STILL leaves A''s row untouched -- proves SELECT''s clause plays NO role in an unqualified delete''s outcome; (DEL1) isolates DELETE''s OWN clause, exactly as AC12 requires'
);
rollback to savepoint sp_del3;

-- =====================================================================
-- BLOCK X (authenticated A, cashflow_target_select corrupted) — general
--   corrupt-the-control: prove RLS, not application logic, confines A to its
--   own rows. Single row on the table (B's own is empty) -> asserts the EXACT
--   value, immune to any #474-class limit-1 displacement (no such selector
--   is used anywhere in this file).
-- =====================================================================
savepoint sp_leak;
alter policy cashflow_target_select on pfin.cashflow_target using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select income_target_annual = 0.00 and expense_target_monthly is null
     from pfin.cashflow_target where users_id = :'ta'),
  '(X1) CORRUPT-THE-CONTROL: with cashflow_target_select broken OPEN, A''s own read still returns A''s REAL row (0.00 / NULL) -- this leg is same-tenant by construction (A reading A''s own row) and exists to pin the exact fixture state (DEL1-DEL3''s "A''s row" is genuinely 0.00/NULL, not an assumption); B''s cross-tenant exposure under this SAME corruption is already asserted at (DEL3), where B''s blanket delete demonstrably could not act on A''s row through the corrupted SELECT policy'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_leak;

-- =====================================================================
-- BLOCK M (aal2 backstop, ADR-029/025 shape, all FOUR verbs) — D (totp),
--   builds its own row via authenticated INSERT (not a service_role pre-seed)
--   so the INSERT leg of the backstop is genuinely exercised, not skipped.
-- =====================================================================
-- (M1) INSERT: totp D at aal1 -> WITH CHECK's aal2 conjunct rejects (42501) --
--      DIRECTLY reachable here (no BEFORE-trigger shadows it, unlike 074/(M5)).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
savepoint sp_m1;
select throws_ok(
  $$ insert into pfin.cashflow_target (income_target_annual, expense_target_monthly) values (30000.00, 1000.00) $$,
  '42501', null,
  '(M1) INSERT: totp-declared D at aal1 -- the aal2 WITH CHECK conjunct rejects (42501), directly (no trigger shadows this table''s WITH CHECK)'
);
rollback to savepoint sp_m1;
select set_config('role', 'postgres', true);

-- (M2) INSERT: SAME totp D at aal2 -> succeeds -- proves (M1) non-vacuous, and
--      creates D's row for the remaining M-block legs.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.cashflow_target (income_target_annual, expense_target_monthly) values (30000.00, 1000.00) $$,
  '(M2) INSERT: SAME totp D at aal2 -- the identical insert now SUCCEEDS -- proves (M1) is non-vacuous and the backstop does not over-block aal2 writes'
);
select set_config('role', 'postgres', true);

-- (M3) SELECT: totp D at aal1 -> 0 of its OWN rows (backstop blocks the read
--      even though D genuinely owns one, per (M2)).
select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.cashflow_target where users_id = %L', :'td')),
  0::bigint,
  '(M3) SELECT: totp D at aal1 sees 0 of its OWN rows -- the aal2 backstop blocks a direct read even though D genuinely has a row (from M2)');

-- (M4) SELECT: SAME totp D at aal2 -> row VISIBLE (proves M3 non-vacuous).
select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.cashflow_target where users_id = %L', :'td')),
  1::bigint,
  '(M4) SELECT: SAME totp D at aal2 sees its 1 own row -- proves (M3) is non-vacuous and the backstop does not over-block aal2');

-- (M5) UPDATE: totp D at aal1 -> USING hides the row -> 0 rows affected, value
--      unchanged (still 30000.00 from M2).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.cashflow_target set income_target_annual = 99999.00 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select income_target_annual from pfin.cashflow_target where users_id = :'td'),
  30000.00::numeric(20,4),
  '(M5) UPDATE: totp D at aal1 -- the UPDATE USING aal2 backstop hides D''s own row (0 rows affected); value UNCHANGED (still 30000.00) -- RED if the backstop were dropped from cashflow_target_update USING'
);

-- (M6) UPDATE: SAME totp D at aal2 -> succeeds, value changes.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.cashflow_target set income_target_annual = 99999.00 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select income_target_annual from pfin.cashflow_target where users_id = :'td'),
  99999.00::numeric(20,4),
  '(M6) UPDATE: SAME totp D at aal2 -- the UPDATE now APPLIES (value is 99999.00) -- proves (M5) is non-vacuous'
);

-- (M7) DELETE: totp D at aal1 -> USING hides the row -> 0 rows affected, row
--      still present. (Qualified delete, deliberately -- this leg proves the
--      aal2 conjunct on the DELETE verb; AC12's unqualified-isolation
--      instrument is BLOCK DEL's separate job, cross-tenant not same-tenant.)
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.cashflow_target where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'td')::bigint,
  1::bigint,
  '(M7) DELETE: totp D at aal1 -- the DELETE USING aal2 backstop hides D''s own row (0 rows affected); the row STILL EXISTS -- RED if the backstop were dropped from cashflow_target_delete USING'
);

-- (M8) DELETE: SAME totp D at aal2 -> succeeds, row gone.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.cashflow_target where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'td')::bigint,
  0::bigint,
  '(M8) DELETE: SAME totp D at aal2 -- the DELETE now APPLIES (row is GONE) -- proves (M7) is non-vacuous'
);

-- =====================================================================
-- BLOCK G (anon) — zero-grant.
-- =====================================================================
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.cashflow_target',
  '42501', null,
  '(G1) anon zero-grant: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (42501), before RLS is ever consulted -- the table is not anon-reachable'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
