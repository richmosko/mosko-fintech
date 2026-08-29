-- =====================================================================
-- Per-Wave battery — pfin.cpi_u_index GLOBAL public reference table
--   (CPI-U / BLS series CUUR0000SA0; SELF-230 / migration 053 / V1.1 Platform)
-- =====================================================================
-- ⚠ EXPECTED-TO-FAIL AGAINST A LIVE LOCAL STACK carrying the real committed CPI reference
--   data (the 2026-08-14 recovery; docs/records/2026-08-14-db-reset-incident.md) — this
--   fixture's "table is EMPTY before I seed it" precondition (z1) collides with real,
--   PERMANENT, monotonically-growing BLS prints. Not a bug in this file, and not fixed by
--   picking different fixture dates: CPI is an ever-advancing real time series, so any date
--   chosen today to dodge today's coverage will itself collide once BLS catches up to it —
--   a fixture-side date pick has a built-in expiration, not a permanent fix (team-lead/QA
--   disposition, meta/battery-local-stack-disposition). THE SANCTIONED LOCAL RUN for this
--   file is a hand-built scratch DB (`createdb` + `psql -f` per migration, never `supabase
--   db reset` — mechanically banned). CI's clean-apply lane builds a fresh DB every run and
--   is UNAFFECTED — it is the actual gating venue for this file.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/053_cpi_u_index.sql
--   - pfin.cpi_u_index                    (NEW global public reference table: cpi_period
--                                         DATE PK (first-of-month) / cpi_value NUMERIC
--                                         (NaN-fenced) / source TEXT DEFAULT
--                                         'BLS_CUUR0000SA0' / ingested_at TIMESTAMPTZ)
--   - constraint cpi_u_index_value_finite (CHECK cpi_value <> 'NaN' — 014 NaN idiom)
--   - policy cpi_u_index_select           (FOR SELECT TO authenticated USING (true) —
--                                         GLOBAL shared-read; NOT users_id-scoped)
--   - grant select on pfin.cpi_u_index to authenticated          (ACL-before-RLS; SELECT only)
--   - grant select, insert, update on pfin.cpi_u_index to service_role  (upsert writer; NO DELETE)
--   - NO authenticated write policy / NO authenticated write grant  (a user cannot forge a
--                                         CPI print — writes are service_role-only via DB-ACL)
--   - anon: ZERO grant                    (pfin schema-usage denial)
--
-- ┌─ WHY THIS IS A GLOBAL-REFERENCE + SERVICE_ROLE-WRITER BATTERY, NOT VANILLA ISOLATION ──┐
-- │ cpi_u_index has NO tenant dimension — it is GLOBAL public macro reference read by EVERY │
-- │ authenticated user via USING (true) (the tax_character/011 + eod_price/019 global class).│
-- │ So there is NO cross-tenant read/write leg — a "tenant B sees 0 of A's rows" assertion   │
-- │ is MEANINGLESS here (there is no users_id, no per-tenant row). See NOTE ON ABSENT CROSS- │
-- │ TENANT LEG below — the absence is by construction, NOT a coverage gap. The load-bearing  │
-- │ properties this battery guards instead:                                                  │
-- │   (a*) GLOBAL shared-read: BOTH distinct tenants read the SAME rows (USING (true)). RED   │
-- │        if the policy were users_id-scoped or over-restrictive.                            │
-- │   (b*) NO-FORGE: authenticated cannot INSERT/UPDATE/DELETE a CPI print AT ALL (no write   │
-- │        grant + no write policy). LOAD-BEARING — a forged/edited CPI level feeds every     │
-- │        reader's real/inflation-adjusted SUMs (§2.1.x). RED if a write grant/policy landed.│
-- │   (g*) SERVICE_ROLE WRITER: the ETL (system-mode TBC) CAN INSERT new months + UPDATE      │
-- │        revised prints (the upsert path) — non-vacuous proof the 053 grant is LIVE.        │
-- │   (h4) LEAST-PRIVILEGE: service_role holds INSERT+UPDATE but NOT DELETE (a revision is an  │
-- │        UPDATE, never a delete). RED if a DELETE grant were added.                          │
-- │   (f1) NaN FENCE: cpi_value = NaN is rejected by the CHECK even for the service_role writer│
-- │        (service_role bypasses RLS but NOT a table CHECK) — keeps a poisoned index level    │
-- │        out of downstream inflation math.                                                   │
-- │   (k1) PK GRAIN: a duplicate cpi_period is rejected (23505) — the one-row-per-month key    │
-- │        the worker UPSERT depends on (ON CONFLICT (cpi_period)).                            │
-- └────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DIFFERENT SIGNAL (no fence passes for another; 004 lesson) ─┐
-- │  • authenticated INSERT/UPDATE/DELETE   -> table-ACL denial -> 'permission denied for table │
-- │       (no write grant)                     cpi_u_index' (message-precise throws_like, NOT a  │
-- │                                            bare 42501 and NOT a WITH-CHECK RLS message)      │
-- │  • cpi_value = NaN                       -> CHECK cpi_u_index_value_finite (name-precise)    │
-- │  • duplicate cpi_period                  -> PK unique_violation 23505 (SQLSTATE-precise)     │
-- │ message-precise (grant denial) + constraint-name (NaN) + SQLSTATE (PK) keeps one fence from  │
-- │ ever passing for another.                                                                    │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- NOTE ON ABSENT CROSS-TENANT LEG (so the absence is not read as a gap): cpi_u_index is GLOBAL
--   public reference data — NO users_id, NO FK-shaped column, NO tenant anchor (per the 053 header
--   §10 3-axis + Decision-3 eval: "same global shared-read class as tax_character"). A cross-tenant
--   read/write assertion is therefore not applicable; the two-tenant fixture is used ONLY to prove
--   the SHARED-read golden property (BOTH tenants see the SAME rows), the exact INVERSE of a
--   per-user isolation battery. This mirrors 011_tax_character_rls.sql.
--
-- NOTE ON FIRST-OF-MONTH GRAIN (DB vs worker layer): the "first-of-month" normalization is a
--   WORKER-LAYER invariant enforced by PFinBackend._map_cpi_u_index_df (pl.date(year, month, 1) +
--   the 1<=month<=12 M13-drop filter), covered by the pytest unit tests test_first_of_month_grain +
--   test_m13_annual_average_dropped (workers/etl/tests/test_core.py). The DB PK enforces ONE ROW
--   PER cpi_period (uniqueness — (k1)); it does NOT (by design) CHECK day-of-month = 1. So the
--   absence of a DB-layer first-of-month CHECK assertion here is intentional, not a gap — the grain
--   is a producer-side invariant, the uniqueness is the DB invariant.
--
-- Reuses the 011/019 idiom: \ir shared verbs, ALL-LOWERCASE \gset literals (005 case-fold lesson),
--   MESSAGE-precise throws_like + CONSTRAINT-NAME-precise throws_like + SQLSTATE-precise throws_ok
--   (004 all-42501 false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE
--   root-cause). The (f1)/(g1)/(g2) service_role legs run pgTAP under role=service_role — the exact
--   precedent set by 019 leg (g1) (service_role lives_ok), so service_role holds EXECUTE on pgTAP.
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (a1)     -> non-vacuous positive: tenant A reads the 2 seeded rows (guards an over-restrictive
--                read that hid even the global rows).
--   (a2)     -> GLOBAL shared-read golden property: tenant B reads the SAME 2 rows. RED if the
--                policy were users_id-scoped instead of USING (true) (INVERSE of a per-user battery).
--   (b1)/(b2)/(b3) -> LOAD-BEARING no-forge: authenticated INSERT/UPDATE/DELETE fail closed with the
--                SPECIFIC 'permission denied for table cpi_u_index' (grant-layer). RED if a write
--                GRANT were opened — a user could forge/edit a CPI level feeding every reader's
--                inflation-adjusted SUMs. UPDATE/DELETE target a real seeded row (non-vacuous).
--   (b4)     -> RLS-layer write denial: ZERO non-SELECT policies on the table (defence-in-depth
--                alongside the grant-layer fence). RED if an INSERT/UPDATE/DELETE/ALL policy landed.
--   (f1)     -> NaN fence: cpi_value = NaN REJECTED by cpi_u_index_value_finite (constraint-name-
--                precise) even under service_role (bypasses RLS but NOT the CHECK) — a NaN would
--                poison every downstream real/inflation-adjusted SUM.
--   (f2)/(f3)-> ±Infinity fence (SELF-230 N1 / Sec-flagged): cpi_value = +Infinity / -Infinity
--                REJECTED by the SAME cpi_u_index_value_finite CHECK — unbounded `numeric` admits
--                'Infinity'/'-Infinity', so an explicit bar is required (a poisoned ±Inf level would
--                blow up every downstream SUM exactly as a NaN would). Mirrors (f1), service_role.
--   (f4)     -> non-vacuous finite control: a normal finite cpi_value INSERTs successfully under
--                service_role — proves the finiteness CHECK rejects ONLY the three special values,
--                not legitimate prints (guards an over-broad CHECK).
--   (g1)     -> non-vacuous SERVICE_ROLE control: service_role INSERTs a NEW month -> ACCEPTED
--                (proves the 053 service_role INSERT grant is LIVE — a green write-fence is not a
--                vacuously-absent grant; and proves (b1) is a missing authenticated grant, not a
--                blanket table lock).
--   (g2)     -> non-vacuous SERVICE_ROLE control: service_role UPDATEs an EXISTING month (the BLS-
--                revision path) -> ACCEPTED (MUTABLE reference posture; the upsert's DO UPDATE leg).
--   (k1)     -> PK grain: a duplicate cpi_period is REJECTED (23505 unique_violation) — the one-row-
--                per-month key the ON CONFLICT (cpi_period) upsert depends on.
--   (h1)     -> non-vacuous ACL positive: authenticated HOLDS SELECT (the global-read path; a1/a2
--                are not vacuously blocked).
--   (h2)/(h3)-> service_role HOLDS INSERT + UPDATE (the upsert writer — grants are live).
--   (h4)     -> LEAST-PRIVILEGE: service_role holds NO DELETE (a revision is an UPDATE, never a
--                delete). RED if a DELETE grant were added.
--   (h5)     -> authenticated holds NO INSERT (proves (b1) is a missing grant; guards the SELECT-
--                only authenticated grant against an accidental widening to a write grant).
--   (h6)     -> anon zero-grant: anon holds NO SELECT. CRITICAL for a USING (true) table — a global
--                read policy means anon would read ALL rows IF it ever held a grant.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27); 053 introduces ZERO
--   catalogued §10 instances — the cpi_u_index service_role SELECT+INSERT+UPDATE grant is a
--   DB-LAYER ACL, NOT the RT-26 code-layer SUPABASE_SERVICE_ROLE_KEY allowlist grep surface (per
--   the 053 header §10 3-axis, Path B; identical reasoning to eod_price/019). Decision-3 family
--   UNCHANGED: cpi_u_index carries NO users_id, NO FK-shaped column, NO INTEGER[] array — no tenant
--   anchor to matched-tenant-validate (same "global reference, not a family member" class as
--   tax_character). This battery adds no ledger change.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b() supply the
--   authenticated RLS context ONLY (there is no per-tenant data on this GLOBAL table). NO PII / NO
--   real account numbers / NO prod data. The 2 seeded CPI rows are SYNTHETIC macro reference values
--   inserted PRIVILEGED (role=postgres — RLS-bypassed; the only unblocked seed path, since
--   authenticated has no write grant). No auth.users rows are needed (cpi_u_index has NO auth.users
--   FK and the USING (true) policy never dereferences auth.uid()). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs while switched to authenticated. Tenant UUIDs are resolved to psql LITERALS
--   via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 053's working-tree contract; the authoritative run is against the
--   001->053 reset stack (CI, pg_prove directory-mode, after Backend applies 053). RED-until-053-
--   applied is EXPECTED on any pre-053 stack (the table would not exist). Locally verified NON-
--   DESTRUCTIVELY by QA: 053 + this file applied inside a single psql txn that was ROLLED BACK
--   (no supabase db reset — the F/CTO's local data was untouched). plan(29) (f2/f3/f4 added at
--   SELF-230 N1 — the ±Infinity CHECK extension + finite control; p1-p6/q1-q3/r1 added at SELF-343/095
--   — the cpi_u_index_value_positive_finite CHECK, per BACKLOG §7.14's first entry, condition (1)).
--
-- ┌─ LEG (p)/(q)/(r) — 095's cpi_u_index_value_positive_finite CHECK (SELF-343) ──────────────────┐
-- │ (p1)/(p2) 0 and -1 REJECTED under the INTACT stack, constraint-name-precise on the NEW          │
-- │   constraint — UNAMBIGUOUS because cpi_u_index_value_finite's predicate (<> NaN/Infinity/       │
-- │   -Infinity) does not evaluate 0 or -1 at all, so only the new constraint can fire.              │
-- │ (p3) 300.000 ACCEPTED — the non-optional accept control (095 header ⚠: "a constraint that        │
-- │   rejects everything passes every rejection assertion").                                         │
-- │ (p4)-(p6) NaN / Infinity / -Infinity, inside a SAVEPOINT that drops ONLY                          │
-- │   cpi_u_index_value_finite — MEASURED (095 header): with BOTH constraints present, these three    │
-- │   values are rejected by cpi_u_index_value_finite FIRST (it is evaluated first), so a name-       │
-- │   precise assertion against the NEW constraint on the intact stack would FAIL on correct DDL.     │
-- │   Dropping only the finiteness CHECK attributes the rejection to cpi_u_index_value_positive_finite│
-- │   specifically — -Infinity is caught via its `> 0` clause, needing no clause of its own.          │
-- │ (q1)-(q3) ADDITIVITY WATCHERS (095 condition 2, made mechanical): both constraints EXIST BY NAME  │
-- │   on the table, and BOTH target cpi_value — a future replacement of either reds this leg rather   │
-- │   than silently losing coverage.                                                                  │
-- │ (r1) COMMENT RE-ISSUE WATCHER: col_description(cpi_value) names the NEW constraint and the CHECK- │
-- │   fenced/cumulative framing 095 STEP 3 re-issues — catalog-read, not a file-text check.            │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(29);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the only write path, since
-- authenticated has NO write grant). Two SYNTHETIC first-of-month CPI-U rows. No
-- auth.users rows needed (no FK; USING (true) never reads auth.uid()).
-- ---------------------------------------------------------------------
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2024-11-01', 315.493);
insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2024-12-01', 315.605);

-- =====================================================================
-- LEG (a) GLOBAL shared-read — BOTH distinct tenants read the SAME rows (USING (true)).
--   [READS FIRST], before any write, so counts are deterministic.
-- =====================================================================
-- (a1) non-vacuous positive: tenant A reads the 2 seeded rows.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.cpi_u_index)::bigint, 2::bigint,
  '(a1) global shared-read: tenant A reads all 2 cpi_u_index rows (USING (true) — not users_id-scoped, not over-restrictive)'
);
select set_config('role', 'postgres', true);

-- (a2) GLOBAL shared-read golden property: tenant B reads the SAME 2 rows (shared, not isolated).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.cpi_u_index)::bigint, 2::bigint,
  '(a2) global shared-read: tenant B ALSO reads all 2 cpi_u_index rows (shared public reference — RED if the SELECT were users_id-scoped; the INVERSE of a per-user isolation battery)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (b) NO-FORGE — authenticated cannot write a CPI print (grant-layer denial + no policy).
--   Run under authenticated A: even a legit tenant cannot INSERT/UPDATE/DELETE reference data.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (b1) authenticated INSERT fails closed at the GRANT layer (no INSERT grant; no write policy).
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-06-01', 999.999) $$,
  'permission denied for table cpi_u_index',
  '(b1) LOAD-BEARING no-forge: authenticated INSERT denied at the GRANT layer (permission denied — SELECT-only grant, no write policy) — a user cannot forge a CPI print that feeds every reader''s inflation-adjusted SUMs'
);
-- (b2) authenticated UPDATE fails closed at the GRANT layer (targets a real seeded row).
select throws_like(
  $$ update pfin.cpi_u_index set cpi_value = 1.000 where cpi_period = '2024-12-01' $$,
  'permission denied for table cpi_u_index',
  '(b2) LOAD-BEARING no-forge: authenticated UPDATE of a seeded CPI row denied at the GRANT layer (no UPDATE grant — a user cannot revise a published CPI level)'
);
-- (b3) authenticated DELETE fails closed at the GRANT layer.
select throws_like(
  $$ delete from pfin.cpi_u_index where cpi_period = '2024-12-01' $$,
  'permission denied for table cpi_u_index',
  '(b3) LOAD-BEARING no-forge: authenticated DELETE of a seeded CPI row denied at the GRANT layer (no DELETE grant)'
);
select set_config('role', 'postgres', true);

-- (b4) RLS-layer write denial: ZERO non-SELECT (write / ALL) policies on the table (defence-in-
--      depth alongside the grant-layer fence). Catalog query; role-independent — run privileged.
select is(
  (select count(*) from pg_policies
     where schemaname = 'pfin' and tablename = 'cpi_u_index' and cmd <> 'SELECT')::bigint,
  0::bigint,
  '(b4) write fails closed: ZERO non-SELECT (write/ALL) policies exist on cpi_u_index (RLS-layer write denial — defence-in-depth; RED if an INSERT/UPDATE/DELETE/ALL policy were added)'
);

-- =====================================================================
-- LEG (f) FINITENESS FENCE — the cpi_u_index_value_finite CHECK bars NaN + ±Infinity
--   (SELF-230 N1 Option A), under the service_role WRITER (service_role bypasses RLS but
--   NOT a table CHECK). Constraint-name-precise. Includes a finite-accepted positive control.
-- =====================================================================
select set_config('role', 'service_role', true);
-- (f1) cpi_value = NaN REJECTED by the finite CHECK (role-agnostic value invariant).
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-07-01', 'NaN'::numeric) $$,
  '%cpi_u_index_value_finite%',
  '(f1) NaN fence: cpi_value = NaN is REJECTED by the cpi_u_index_value_finite CHECK (constraint-name-precise) even under the service_role writer (bypasses RLS but NOT the CHECK — a NaN would poison every downstream real/inflation-adjusted SUM)'
);
-- (f2) cpi_value = +Infinity REJECTED by the SAME CHECK (SELF-230 N1 — unbounded numeric admits Infinity).
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-08-01', 'Infinity'::numeric) $$,
  '%cpi_u_index_value_finite%',
  '(f2) +Infinity fence (SELF-230 N1): cpi_value = +Infinity is REJECTED by the cpi_u_index_value_finite CHECK (constraint-name-precise) — PostgreSQL numeric admits ''Infinity'', so the explicit bar is load-bearing; a +Inf level would blow up every downstream inflation-adjusted SUM'
);
-- (f3) cpi_value = -Infinity REJECTED by the SAME CHECK.
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-09-01', '-Infinity'::numeric) $$,
  '%cpi_u_index_value_finite%',
  '(f3) -Infinity fence (SELF-230 N1): cpi_value = -Infinity is REJECTED by the cpi_u_index_value_finite CHECK (constraint-name-precise) — the third numeric special value barred alongside NaN and +Infinity'
);
-- (f4) non-vacuous finite control: a normal finite value INSERTs successfully (CHECK not over-broad).
select lives_ok(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-10-01', 317.250) $$,
  '(f4) finite control: a normal finite cpi_value (317.250) INSERTs successfully under service_role — proves the finiteness CHECK rejects ONLY NaN/±Infinity, not legitimate CPI prints (guards an over-broad CHECK)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (p) POSITIVITY FENCE (SELF-343/095) — cpi_u_index_value_positive_finite, ADDITIVE to
--   cpi_u_index_value_finite. Under service_role (bypasses RLS but NOT a table CHECK), same
--   idiom as LEG (f).
-- =====================================================================
select set_config('role', 'service_role', true);
-- (p1) cpi_value = 0 REJECTED, constraint-name-precise on the NEW constraint. cpi_u_index_value_finite's
--      predicate never evaluates 0, so this attribution is unambiguous under the intact stack.
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-11-01', 0) $$,
  '%cpi_u_index_value_positive_finite%',
  '(p1) zero fence (SELF-343): cpi_value = 0 is REJECTED by cpi_u_index_value_positive_finite (constraint-name-precise) — a zero print would raise inside every downstream deflator division'
);
-- (p2) cpi_value = -1 REJECTED, same attribution reasoning.
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-12-01', -1) $$,
  '%cpi_u_index_value_positive_finite%',
  '(p2) negative fence (SELF-343): cpi_value = -1 is REJECTED by cpi_u_index_value_positive_finite (constraint-name-precise) — a negative print would flip the sign of every downstream inflation-adjusted figure silently'
);
-- (p3) non-vacuous accept control — the CHECK rejects ONLY the poisoned states, not legitimate prints.
select lives_ok(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-01-01', 300.000) $$,
  '(p3) accept control (SELF-343): a normal finite positive cpi_value (300.000) INSERTs successfully — the accepting leg is not optional (095 header ⚠: a constraint that rejects everything passes every rejection assertion)'
);
select set_config('role', 'postgres', true);

-- (p4)-(p6): MEASURED (095 header) — with BOTH constraints present, NaN/±Infinity are rejected by
-- cpi_u_index_value_finite FIRST, so a name-precise assertion on the NEW constraint would fail on
-- correct DDL. Drop ONLY cpi_u_index_value_finite inside a savepoint to attribute the rejection to
-- cpi_u_index_value_positive_finite specifically, then restore. postgres owns pfin.cpi_u_index
-- (measured directly against this scratch build; postgres is already the active role here).
savepoint drop_finiteness_only;
alter table pfin.cpi_u_index drop constraint cpi_u_index_value_finite;
select set_config('role', 'service_role', true);
-- (p4) NaN, now attributable to cpi_u_index_value_positive_finite alone.
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-02-01', 'NaN'::numeric) $$,
  '%cpi_u_index_value_positive_finite%',
  '(p4) NaN, finiteness CHECK dropped (SELF-343): cpi_u_index_value_positive_finite alone REJECTS NaN — proves the new constraint carries its own finiteness coverage rather than leaning entirely on the sibling'
);
-- (p5) +Infinity, same attribution.
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-03-01', 'Infinity'::numeric) $$,
  '%cpi_u_index_value_positive_finite%',
  '(p5) +Infinity, finiteness CHECK dropped (SELF-343): cpi_u_index_value_positive_finite alone REJECTS +Infinity — PostgreSQL numeric places it ABOVE every finite value, so this is the explicit clause, not the `> 0` fallthrough'
);
-- (p6) -Infinity, caught via `> 0` alone — no explicit clause needed (095 header: a clause that
--      cannot fire is a fence that cannot be tested).
select throws_like(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2026-04-01', '-Infinity'::numeric) $$,
  '%cpi_u_index_value_positive_finite%',
  '(p6) -Infinity, finiteness CHECK dropped (SELF-343): cpi_u_index_value_positive_finite alone REJECTS -Infinity via its `> 0` clause — -Infinity sorts below every finite value, so no dedicated clause was needed or written'
);
select set_config('role', 'postgres', true);
rollback to savepoint drop_finiteness_only;

-- =====================================================================
-- LEG (q) ADDITIVITY WATCHERS (SELF-343 condition 2, made mechanical) — both constraints EXIST BY
--   NAME on the table and BOTH target cpi_value. RED if either were dropped, renamed, or folded into
--   the other; RED if either landed on the wrong column. Catalog-read, role-agnostic.
-- =====================================================================
select ok(
  (select count(*) from pg_constraint c join pg_class t on t.oid = c.conrelid
     join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'pfin' and t.relname = 'cpi_u_index' and c.conname = 'cpi_u_index_value_finite') = 1,
  '(q1) cpi_u_index_value_finite EXISTS BY NAME on pfin.cpi_u_index — 095 is ADDITIVE, never a replacement; RED if a future edit drops or renames the finiteness CHECK'
);
select ok(
  (select count(*) from pg_constraint c join pg_class t on t.oid = c.conrelid
     join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'pfin' and t.relname = 'cpi_u_index' and c.conname = 'cpi_u_index_value_positive_finite') = 1,
  '(q2) cpi_u_index_value_positive_finite EXISTS BY NAME on pfin.cpi_u_index (SELF-343/095)'
);
select ok(
  (select bool_and(c.conkey = array[(select attnum from pg_attribute
                                        where attrelid = 'pfin.cpi_u_index'::regclass and attname = 'cpi_value')])
     from pg_constraint c join pg_class t on t.oid = c.conrelid
     join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'pfin' and t.relname = 'cpi_u_index'
      and c.conname in ('cpi_u_index_value_finite', 'cpi_u_index_value_positive_finite')),
  '(q3) BOTH constraints target cpi_value (conkey resolves to the same single column on both) — RED if either landed on the wrong column'
);

-- =====================================================================
-- LEG (r) COMMENT RE-ISSUE WATCHER (SELF-343 condition 3 discharged on the COLUMN half) — a
--   catalog read, not a file-text check: 095 STEP 3 re-issues col_description so \d+ does not tell a
--   reader the column is finiteness-fenced only.
-- =====================================================================
select ok(
  col_description('pfin.cpi_u_index'::regclass,
    (select attnum from pg_attribute where attrelid = 'pfin.cpi_u_index'::regclass and attname = 'cpi_value')
  ) ~ 'cpi_u_index_value_positive_finite, added at 095',
  '(r1) col_description(cpi_value) names cpi_u_index_value_positive_finite and its 095 landing point — the finiteness-only framing was retired, not left describing a CHECK the column no longer only has'
);

-- =====================================================================
-- LEG (g) SERVICE_ROLE WRITER — the ETL upsert path (INSERT new month + UPDATE revised print).
--   Non-vacuous controls: proves the 053 service_role grant is LIVE (and (b*) is a missing
--   authenticated grant, not a blanket lock). Run under role=service_role (019 (g1) precedent).
-- =====================================================================
select set_config('role', 'service_role', true);
-- (g1) service_role INSERT of a NEW month SUCCEEDS (the upsert INSERT leg).
select lives_ok(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2025-01-01', 316.000) $$,
  '(g1) service_role writer: INSERT of a NEW month SUCCEEDS (bypasses RLS; proves the 053 service_role INSERT grant is LIVE — a green write-fence is not a vacuously-absent grant)'
);
-- (g2) service_role UPDATE of an EXISTING month SUCCEEDS (the BLS-revision / upsert DO UPDATE leg).
select lives_ok(
  $$ update pfin.cpi_u_index set cpi_value = 315.700 where cpi_period = '2024-12-01' $$,
  '(g2) service_role writer: UPDATE of an EXISTING month SUCCEEDS (MUTABLE reference posture — the upsert''s ON CONFLICT DO UPDATE revision path; BLS restates published prints)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (k) PK GRAIN — one row per cpi_period (the ON CONFLICT (cpi_period) upsert key).
--   Duplicate cpi_period rejected. Run privileged (postgres) — the PK is role-agnostic.
--   '2024-12-01' already exists (seeded), so a bare INSERT (not upsert) must raise 23505.
-- =====================================================================
-- (k1) duplicate cpi_period REJECTED (23505 unique_violation) — the one-row-per-month PK grain.
select throws_ok(
  $$ insert into pfin.cpi_u_index (cpi_period, cpi_value) values ('2024-12-01', 400.000) $$,
  '23505', null,
  '(k1) PK grain: a duplicate cpi_period is REJECTED with unique_violation (23505) — the one-row-per-month key the worker ON CONFLICT (cpi_period) upsert depends on'
);

-- =====================================================================
-- LEG (h) GRANT posture (ACL facts, run as postgres — role-agnostic).
-- =====================================================================
-- (h1) non-vacuous ACL positive: authenticated HOLDS SELECT (the global-read path).
select ok(
  has_table_privilege('authenticated', 'pfin.cpi_u_index', 'SELECT'),
  '(h1) ACL positive: authenticated HOLDS SELECT on pfin.cpi_u_index (the global-read path; a1/a2 are not vacuously blocked)'
);
-- (h2) service_role HOLDS INSERT (the upsert writer).
select ok(
  has_table_privilege('service_role', 'pfin.cpi_u_index', 'INSERT'),
  '(h2) ACL positive: service_role HOLDS INSERT on pfin.cpi_u_index (the ETL upsert INSERT leg)'
);
-- (h3) service_role HOLDS UPDATE (the revision path).
select ok(
  has_table_privilege('service_role', 'pfin.cpi_u_index', 'UPDATE'),
  '(h3) ACL positive: service_role HOLDS UPDATE on pfin.cpi_u_index (the BLS-revision upsert DO UPDATE leg)'
);
-- (h4) LEAST-PRIVILEGE: service_role does NOT hold DELETE (a revision is an UPDATE, never a delete).
select ok(
  not has_table_privilege('service_role', 'pfin.cpi_u_index', 'DELETE'),
  '(h4) least-privilege: service_role holds NO DELETE on pfin.cpi_u_index (a CPI revision is an UPDATE, never a delete — RED if a DELETE grant were added)'
);
-- (h5) authenticated does NOT hold INSERT (proves (b1) is a missing grant; guards SELECT-only).
select ok(
  not has_table_privilege('authenticated', 'pfin.cpi_u_index', 'INSERT'),
  '(h5) least-privilege: authenticated holds NO INSERT on pfin.cpi_u_index (proves (b1) is a missing grant, not an RLS reject — guards the SELECT-only authenticated grant against widening)'
);
-- (h6) anon zero-grant by construction — CRITICAL for a USING (true) global-read table.
select ok(
  not has_table_privilege('anon', 'pfin.cpi_u_index', 'SELECT'),
  '(h6) anon zero-grant: anon holds NO SELECT on pfin.cpi_u_index (a USING (true) global-read table must NEVER be anon-reachable — anon would read ALL rows if it ever held a grant). ⚠ THIS LEG HAS A REMOTE CONSUMER: 064''s (A2) triage message tells an operator to downgrade a red (A2) from data-exposure to least-privilege, and it cites THIS leg as one of the three facts that downgrade rests on. If (h6) reddens, that downgrade is VOID — fix this first, and treat any concurrent red (A2) as potentially real exposure rather than a grant tidy-up'
);

select * from finish();
rollback;
