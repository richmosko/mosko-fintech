-- =====================================================================
-- Per-Wave battery — pfin.owner_identification: FIFTH and LAST Lock-14
--   per-domain settings table (ADR-011 Decision 18, as amended 2026-08-16 —
--   the family is FIVE, not four). Single-scalar owner-header settings row:
--   one TEXT column (owner_id_header_text), UNIQUE(users_id), full
--   authenticated CRUD RLS + the 025 aal2 step-up backstop (Sec F-9) on
--   every policy, NOT a Decision-3 instance (no label — 090/AC6), NO JSONB
--   (Lock-14 forward-compat fence, AC7). Canonical test label: RT-12
--   (SECURITY §4.1 axis iv, Sec D-3) (SELF-352 AC1-AC10; V1.5; V1-SHIP-BLOCK;
--   JOINT-REVIEW-MANDATORY per Lock-14 membership, Sec R-6).
-- =====================================================================
-- ⚠⚠⚠ DRAFT STATUS — AUTHORED AGAINST THE RULED AC, NOT YET AGAINST
--   ARCHITECT'S COMMITTED MIGRATION. `106_owner_identification.sql` did not
--   exist on `feature/self-352` at drafting time (checked: branch tip ==
--   `main`@3de6be7, no migration file, no uncommitted worktree changes).
--   This file assumes, pending rebase onto Architect's sha:
--     - users_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id)
--       ON DELETE CASCADE (the 074/090/101 tenant-anchor shape).
--     - owner_id_header_text TEXT NULLable (AC1 does not mark NOT NULL), one
--       CHECK enforcing BOTH AC2 (length <= 120) and AC3 (no embedded
--       newline), permitting NULL.
--     - trigger reusing pfin.fn_refresh_updated_at() (AC5).
--   CHECK-constraint legs below assert generically on SQLSTATE 23514
--   (check_violation), NOT a named-constraint throws_like, because the
--   constraint's name is not yet known. Upgrade to throws_like(name) at
--   rebase if Sec wants name-pinning (101/LBL-CHECK precedent) — tracked in
--   the QA report, not silently done.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/106_owner_identification.sql
--   (sha TBD — see DRAFT STATUS above)
-- Prereqs exercised (already on main / applied by Backend on the reset
--   stack): 001 (pfin schema + fn_refresh_updated_at), 024
--   (pfin.user_settings.mfa_policy), 025 (the aal2 backstop clause shape
--   this migration reuses byte-faithfully), auth.users.
-- Reuses the 090/101 idiom: \ir verbs, ALL-LOWERCASE \gset literals,
--   MESSAGE-precise throws_like / SQLSTATE-precise throws_ok, role restored
--   to postgres between blocks (PR #121 root-cause), savepoint/rollback
--   around every exception-raising probe and every ALTER POLICY corruption.
--
-- ┌─ AC10 — the aal2 leg is a SEPARATE leg from the cross-tenant leg ───────────┐
-- │ BLOCK M (aal2 backstop, tenant D/totp) is entirely independent of BLOCK W   │
-- │ (cross-tenant, tenant B intruding on tenant A). Neither block's fixture nor │
-- │ assertions depend on the other; D builds its OWN row via authenticated     │
-- │ INSERT (not a service_role pre-seed) so the INSERT leg of the backstop is  │
-- │ genuinely exercised, per the 090/(M1-M2) precedent.                        │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ AC4 — UPSERT-in-place, not a fresh row (090's BLOCK U model) ──────────────┐
-- │ BLOCK UPS forces `updated_at` to a sentinel (privileged, bypassing the      │
-- │ trigger), then performs the REAL authenticated UPSERT (`on conflict         │
-- │ (users_id) do update`) and asserts: row count unchanged (still 1 — no       │
-- │ second row), the value moved to the new content, and updated_at advanced    │
-- │ away from the sentinel. `now()` is transaction-constant across this whole   │
-- │ file, so a wall-clock before/after compare would be a false negative — the  │
-- │ sentinel technique (101/UPD1 precedent) sidesteps that.                     │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ BLOCK X — the fence's own inversion, encoded permanently ──────────────────┐
-- │ Structural presence (BLOCK S) and behavioural fail-closed (BLOCK R/W) are   │
-- │ each individually provable-green-vacuously if the OTHER half regressed.     │
-- │ (X1) corrupts cashflow_target-style: breaks owner_identification_select    │
-- │ open (`using (true)`) and asserts the cross-tenant read STOPS being empty   │
-- │ (B now sees A's row) — the fence's own control, kept in the suite, not      │
-- │ just run once by hand at authoring time.                                   │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 catalogued ledger — read ADR-011 Decision 4 live,
--   never from here; this migration adds ZERO catalogued instances beyond
--   RT-12 (Sec D-3, AC8). Decision-3 family: +0, NO LABEL (AC6) — the only
--   reference column is the direct users_id owner anchor; no FK-shaped
--   column beyond it exists on this table.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(), plus a raw literal for the totp tenant
--   (D, suffixed '06' for migration 106 to keep this file's fixture
--   diffable against other batteries' fixed literals in the same cluster —
--   each file's txn rolls back independently so collision is not actually
--   live). NO PII / NO real account numbers / NO prod data. All inside one
--   rolled-back transaction.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated, so NO `_rls.*` call runs under authenticated. Tenant
--   UUIDs are resolved to psql LITERALS via \gset at role=postgres; every
--   _rls.set_tenant(_aal) call happens at role=postgres and each block
--   restores role=postgres before the next. \gset var names are
--   ALL-LOWERCASE. `_rls.expect_cross_tenant_write_blocked` is deliberately
--   NOT used (it does not self-restore role on return — 090/101 precedent
--   is the manual set_tenant/savepoint/throws_ok/rollback/set_config shape
--   used throughout this file).
--
-- ⟦WIRE-VALIDATE⟧ NOT YET RUN against a real migration — see DRAFT STATUS.
--   To verify: hand-built scratch DB, `pgtap` installed in `public`,
--   migrations 001->105 + 106 applied SEQUENTIALLY as `postgres` (never a
--   TEMPLATE clone), `pg_prove` (never bare `psql`). `supabase db reset` is
--   mechanically banned. plan(35): 5 structural (S1-S5) + 2 structural aal2
--   split (S6a-S6b) + 4 grants (GR1-GR4) + 1 no-JSONB fence (NEG1) + 1 fresh
--   INSERT round-trip (INS1) + 1 unique-per-user (UQ1) + 4 CHECK
--   (CHK1-CHK4: length bound pair + newline pair) + 3 UPSERT-in-place
--   (UPS1-UPS3) + 2 two-tenant read isolation (R1-R2) + 3 cross-tenant write
--   blocked (W1-W3) + 1 corrupt-the-control inversion (X1) + 8 aal2
--   backstop, all four verbs (M1-M8) = 35.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(35);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-000000000d06'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users: A/B (plain 'none' mfa_policy — the
--    two-tenant cross-read/write baseline), D (totp — the aal2 backstop
--    subject; builds its OWN row via authenticated INSERT in BLOCK M so
--    the INSERT leg of the backstop is genuinely exercised).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- BLOCK S (postgres — pg_policy catalog) — STRUCTURAL tenant presence,
--   each of the four verbs' policies, plus the aal2 backstop split by
--   clause half (090/101's S6a/b masking lesson: an OR-combined count goes
--   green if a clause survives in EITHER half, masking a WITH-CHECK-only
--   regression on the update policy).
-- =====================================================================
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_select'),
  '(S1) STRUCTURAL: owner_identification_select carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_insert'),
  '(S2) STRUCTURAL: owner_identification_insert carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_update'),
  '(S3) STRUCTURAL: owner_identification_update carries a USING expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_update'),
  '(S4) STRUCTURAL: owner_identification_update carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog)'
);
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass and polname = 'owner_identification_delete'),
  '(S5) STRUCTURAL: owner_identification_delete carries its OWN USING expression referencing users_id = auth.uid() (pg_policy catalog) — never trimmed on the reasoning that SELECT already covers it (SECURITY §4.6)'
);

select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'),
  3::bigint,
  '(S6a) STRUCTURAL — USING half: select/update/delete all carry the ADR-029/025 aal2 backstop (Sec F-9) in polqual — RED if any USING-side aal2 clause were dropped, independent of the WITH CHECK half'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.owner_identification'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'),
  2::bigint,
  '(S6b) STRUCTURAL — WITH CHECK half: insert/update both carry the ADR-029/025 aal2 backstop in polwithcheck — RED if owner_identification_update''s WITH CHECK lost its aal2 clause while USING kept it'
);

-- =====================================================================
-- BLOCK GR (postgres — grants) — anon/service_role zero-grant,
--   authenticated full CRUD and nothing wider, PLUS one behavioral proof.
-- =====================================================================
select ok(
  not has_table_privilege('anon', 'pfin.owner_identification', 'SELECT')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'INSERT')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'UPDATE')
  and not has_table_privilege('anon', 'pfin.owner_identification', 'DELETE'),
  '(GR1) anon holds ZERO table-level privileges, all four verbs (pg_catalog has_table_privilege)'
);
select ok(
  not has_table_privilege('service_role', 'pfin.owner_identification', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'INSERT')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'UPDATE')
  and not has_table_privilege('service_role', 'pfin.owner_identification', 'DELETE'),
  '(GR2) service_role holds ZERO table-level privileges, all four verbs — 008 establishes no default privileges, this records rather than effects that'
);
select ok(
  has_table_privilege('authenticated', 'pfin.owner_identification', 'SELECT')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'INSERT')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'UPDATE')
  and has_table_privilege('authenticated', 'pfin.owner_identification', 'DELETE')
  and not has_table_privilege('authenticated', 'pfin.owner_identification', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'pfin.owner_identification', 'REFERENCES'),
  '(GR3) authenticated holds EXACTLY the four CRUD verbs — all present, TRUNCATE/REFERENCES absent (explicit grants, nothing wider)'
);
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.owner_identification',
  '42501', null,
  '(GR4) BEHAVIORAL: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (42501), before RLS is ever consulted'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK NEG (postgres — pg_attribute) — AC7 / Lock-14 forward-compat
--   fence: NO JSONB column exists on this table.
-- =====================================================================
select is(
  (select count(*)::bigint from pg_attribute a
     join pg_type t on t.oid = a.atttypid
    where a.attrelid = 'pfin.owner_identification'::regclass
      and not a.attisdropped
      and t.typname in ('jsonb', '_jsonb')),
  0::bigint,
  '(NEG1) Lock-14 forward-compat fence: pfin.owner_identification carries ZERO jsonb columns'
);

-- =====================================================================
-- BLOCK 1 (authenticated A) — seed A's real committed row (fresh INSERT,
--   row was absent). INS1 proves the round-trip.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.owner_identification (owner_id_header_text) values ('Mosko Household');
select set_config('role', 'postgres', true);

select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household',
  '(INS1) fresh INSERT (row was ABSENT for A): owner_id_header_text round-trips as given'
);

-- =====================================================================
-- BLOCK UQ (authenticated A) — unique(users_id): a second row for the
--   SAME tenant is refused (23505), independent of column value.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_uq1;
select throws_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('Second Row Attempt') $$,
  '23505', null,
  '(UQ1) unique(users_id): A''s second INSERT (users_id defaults to auth.uid()=A again) is refused (23505 unique_violation) — one row per user by construction'
);
rollback to savepoint sp_uq1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK CHK (authenticated A) — AC2 (120-char length bound) and AC3 (no
--   embedded newline), each as a boundary/mechanism-isolating pair.
--   Runs via UPDATE, savepoint/rollback per leg, against A's seeded row
--   (still 'Mosko Household' at this point).
-- =====================================================================
-- (CHK1) 121 characters -> rejected (23514) — one past the AC2 bound.
savepoint sp_chk1;
select throws_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat('x', 121)),
  '23514', null,
  '(CHK1) a 121-character owner_id_header_text is REJECTED (23514 check_violation) — one past the AC2 120-character bound'
);
rollback to savepoint sp_chk1;

-- (CHK2) CONTROL: 120 characters (the bound, exactly) -> accepted.
savepoint sp_chk2;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, repeat('y', 120)),
  '(CHK2) CONTROL: a 120-character owner_id_header_text (the AC2 bound, exactly) is ACCEPTED — proves (CHK1) is the LENGTH conjunct specifically, not a blanket rejection'
);
rollback to savepoint sp_chk2;

-- (CHK3) an embedded newline -> rejected (23514), content otherwise short
--        and well within the length bound (isolates the newline mechanism
--        from the length mechanism).
savepoint sp_chk3;
select throws_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, E'Line One\nLine Two'),
  '23514', null,
  '(CHK3) an owner_id_header_text carrying an embedded newline is REJECTED (23514 check_violation) — AC3 single-line enforcement, well within the AC2 length bound so this is NOT the length conjunct firing'
);
rollback to savepoint sp_chk3;

-- (CHK4) CONTROL: identical content with the newline replaced by a space
--        -> accepted — proves (CHK3) is newline-driven specifically, not
--        content- or length-driven.
savepoint sp_chk4;
select lives_ok(
  format($$ update pfin.owner_identification set owner_id_header_text = %L where users_id = auth.uid() $$, 'Line One Line Two'),
  '(CHK4) CONTROL: the SAME content as (CHK3) with the newline replaced by a space is ACCEPTED — proves (CHK3) is driven by the embedded newline specifically, not by content or length'
);
rollback to savepoint sp_chk4;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK UPS (AC4) — UPSERT-in-place updates the existing row (no second
--   row) and updated_at advances. `now()` is transaction-constant across
--   this file, so a wall-clock compare is a false negative — force a
--   sentinel first (privileged, bypassing the trigger), per 101/(UPD1).
-- =====================================================================
update pfin.owner_identification set updated_at = '2000-01-01'::timestamptz where users_id = :'ta';
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.owner_identification (owner_id_header_text) values ('Mosko Household — Primary')
  on conflict (users_id) do update set owner_id_header_text = excluded.owner_id_header_text;
select set_config('role', 'postgres', true);

select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  1::bigint,
  '(UPS1) UPSERT-in-place: the row SURVIVES as exactly 1 row — no second row created for the same tenant'
);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household — Primary',
  '(UPS2) UPSERT-in-place: owner_id_header_text is now the NEW value'
);
select ok(
  (select updated_at > '2000-01-01'::timestamptz from pfin.owner_identification where users_id = :'ta'),
  '(UPS3) UPSERT-in-place: updated_at was forced to a 2000-01-01 sentinel (privileged, bypassing the trigger), then A''s authenticated UPSERT reset it away from that sentinel — fn_refresh_updated_at fires on the UPDATE arm of the UPSERT'
);

-- =====================================================================
-- BLOCK R (postgres — _rls verbs) — two-tenant read isolation. A owns
--   exactly 1 row at this point ('Mosko Household — Primary', per BLOCK UPS).
-- =====================================================================
-- (R1) owner-reads-own: A sees exactly its 1 row (guards an over-restrictive policy).
select _rls.expect_owner_can_read('pfin.owner_identification'::regclass, :'ta'::uuid, 1::bigint);

-- (R2) cross-tenant read fails closed: B sees 0 of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.owner_identification'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK W (authenticated B) — cross-tenant WRITE fails closed (INSERT
--   forge, UPDATE no-op, DELETE no-op). A's row is unchanged throughout.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (W1) B forges users_id=A on an INSERT -> RLS WITH CHECK requires
--      users_id = auth.uid() = B -> mismatch -> rejected (42501). No
--      matched-tenant trigger sits in front of this table (AC6 — not a
--      Decision-3 instance), so this conjunct is DIRECTLY behaviourally
--      reachable, unlike 074's (M5) shadow.
savepoint sp_w1;
select throws_ok(
  format($$ insert into pfin.owner_identification (users_id, owner_id_header_text) values (%L, 'Forged Row') $$, :'ta'),
  '42501', null,
  '(W1) cross-tenant INSERT forge: B inserts claiming users_id=A -> RLS WITH CHECK rejects (42501) — directly behaviourally reachable (no trigger shadows this table''s WITH CHECK)'
);
rollback to savepoint sp_w1;

-- (W2) B's UPDATE targets A's row by users_id -> USING filters it to 0
--      rows (silently, no exception) -> A's row is UNCHANGED.
update pfin.owner_identification set owner_id_header_text = 'Overwritten By B' where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'ta'),
  'Mosko Household — Primary',
  '(W2) cross-tenant UPDATE: B''s update where users_id=A matches 0 rows under RLS (USING filters it out) — A''s row UNCHANGED'
);

-- (W3) B's DELETE targets A's row by users_id -> USING filters it to 0
--      rows -> A's row SURVIVES.
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.owner_identification where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'ta')::bigint,
  1::bigint,
  '(W3) cross-tenant DELETE: B''s DELETE where users_id=A matches 0 rows under RLS — A''s row SURVIVES'
);

-- =====================================================================
-- BLOCK X (corrupt-the-control) — the fence's own inversion, kept
--   permanently in the suite, not just run once by hand at authoring time.
--   Corrupts owner_identification_select OPEN and asserts the cross-tenant
--   read STOPS being empty — proves (R2)'s fail-closed result is really
--   the SELECT policy's own doing, not a vacuous empty-by-construction match.
-- =====================================================================
savepoint sp_x1;
alter policy owner_identification_select on pfin.owner_identification using (true);
select is(
  _rls._visible_owner_rows('pfin.owner_identification'::regclass, :'ta'::uuid, :'tb'::uuid),
  1::bigint,
  '(X1) CORRUPT-THE-CONTROL: with owner_identification_select broken OPEN (using (true)), B NOW SEES A''s 1 row — proves (R2)''s cross-tenant-empty result was the SELECT policy''s own clause at work, not a vacuous match'
);
rollback to savepoint sp_x1;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK M (aal2 backstop, ADR-029/025 shape, all FOUR verbs, Sec F-9) — a
--   SEPARATE leg from BLOCK W (AC10). D (totp) builds its own row via
--   authenticated INSERT (not a service_role pre-seed) so the INSERT leg
--   of the backstop is genuinely exercised.
-- =====================================================================
-- (M1) INSERT: totp-declared D at aal1 -> WITH CHECK's aal2 conjunct
--      rejects (42501) — directly reachable (no trigger shadows this
--      table's WITH CHECK).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
savepoint sp_m1;
select throws_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('D Household') $$,
  '42501', null,
  '(M1) INSERT: totp-declared D at aal1 — the aal2 WITH CHECK conjunct rejects (42501), directly (no trigger shadows this table''s WITH CHECK)'
);
rollback to savepoint sp_m1;
select set_config('role', 'postgres', true);

-- (M2) INSERT: SAME totp D at aal2 -> succeeds — proves (M1) non-vacuous,
--      and creates D's row for the remaining M-block legs.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.owner_identification (owner_id_header_text) values ('D Household') $$,
  '(M2) INSERT: SAME totp D at aal2 — the identical insert now SUCCEEDS — proves (M1) is non-vacuous and the backstop does not over-block aal2 writes'
);
select set_config('role', 'postgres', true);

-- (M3) SELECT: totp D at aal1 -> 0 of its OWN rows (backstop blocks the
--      read even though D genuinely owns one, per (M2)).
select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.owner_identification where users_id = %L', :'td')),
  0::bigint,
  '(M3) SELECT: totp D at aal1 sees 0 of its OWN rows — the aal2 backstop blocks a direct read even though D genuinely has a row (from M2)');

-- (M4) SELECT: SAME totp D at aal2 -> row VISIBLE (proves M3 non-vacuous).
select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.owner_identification where users_id = %L', :'td')),
  1::bigint,
  '(M4) SELECT: SAME totp D at aal2 sees its 1 own row — proves (M3) is non-vacuous and the backstop does not over-block aal2');

-- (M5) UPDATE: totp D at aal1 -> USING hides the row -> 0 rows affected,
--      value unchanged (still 'D Household' from M2).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.owner_identification set owner_id_header_text = 'D Overwrite Attempt' where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'td'),
  'D Household',
  '(M5) UPDATE: totp D at aal1 — the UPDATE USING aal2 backstop hides D''s own row (0 rows affected); value UNCHANGED — RED if the backstop were dropped from owner_identification_update USING'
);

-- (M6) UPDATE: SAME totp D at aal2 -> succeeds, value changes.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.owner_identification set owner_id_header_text = 'D Household Updated' where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select owner_id_header_text from pfin.owner_identification where users_id = :'td'),
  'D Household Updated',
  '(M6) UPDATE: SAME totp D at aal2 — the UPDATE now APPLIES — proves (M5) is non-vacuous'
);

-- (M7) DELETE: totp D at aal1 -> USING hides the row -> 0 rows affected,
--      row still present.
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.owner_identification where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'td')::bigint,
  1::bigint,
  '(M7) DELETE: totp D at aal1 — the DELETE USING aal2 backstop hides D''s own row (0 rows affected); the row STILL EXISTS — RED if the backstop were dropped from owner_identification_delete USING'
);

-- (M8) DELETE: SAME totp D at aal2 -> succeeds, row gone.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.owner_identification where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.owner_identification where users_id = :'td')::bigint,
  0::bigint,
  '(M8) DELETE: SAME totp D at aal2 — the DELETE now APPLIES — proves (M7) is non-vacuous'
);

select * from finish();
rollback;
