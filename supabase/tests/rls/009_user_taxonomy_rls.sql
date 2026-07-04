-- =====================================================================
-- Per-Wave battery — pfin.user_taxonomy two-tenant RLS (SELF-231 / 009 —
--   C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/009_user_taxonomy.sql
--                    + supabase/migrations/010_user_taxonomy_notes.sql (additive `notes text`)
--   - pfin.user_taxonomy               (RLS: direct-owner users_id = auth.uid();
--                                       V1-WRITE-DORMANT — SELECT policy + SELECT grant ONLY;
--                                       NO write policy, NO write grant)
--   - policy user_taxonomy_select      (FOR SELECT TO authenticated; users_id = auth.uid())
--   - grant select on pfin.user_taxonomy to authenticated   (ACL-before-RLS; SELECT only)
--   - CHECK domain in ('asset','cashflow'); tax_character membership: was inline CHECK (009),
--     CONVERTED to FK -> pfin.tax_character(code) at 011. Membership enforcement now lives in
--     the 011 battery (011_tax_character_rls.sql c1: bad code -> 23503), NOT here — the (4c)
--     CHECK assertion was REMOVED because 011 drops that CHECK. See BLOCK 4 note below.
--   - UNIQUE (users_id, domain, cat, sub_cat)
--   - column notes text NULL (010) — nullable, no default, NO new grant/policy: inherits the
--                                    009 SELECT grant + user_taxonomy_select policy verbatim.
-- Reuses the SELF-187/189/190/196 idiom: \ir verbs, ALL-LOWERCASE \gset literals
--   (005 case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like
--   (004 all-42501 false-green lesson), role restored to postgres between blocks.
--
-- ┌─ V1-WRITE-DORMANT: WHY THE WRITE DENIAL IS A GRANT-LAYER (NOT WITH-CHECK) FENCE ──┐
-- │ 009 grants authenticated SELECT ONLY and ships NO write policy. So an authenticated │
-- │ INSERT/UPDATE/DELETE — even of the caller's OWN row — is denied at the TABLE ACL     │
-- │ BEFORE RLS is consulted: 'permission denied for table user_taxonomy' (42501). This   │
-- │ is DISTINCT from the 006-style WITH-CHECK RLS rejection ('new row violates row-level  │
-- │ security policy%'): there is no write policy here to reach. Matching the SPECIFIC     │
-- │ grant-layer message (not a bare 42501, and NOT the RLS-policy message) asserts the    │
-- │ MECHANISM is grant-layer denial, per the migration's EXPOSURE/C6 note — and guards    │
-- │ the SELECT-only grant against an accidental widening to a write grant.                │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a)         -> non-vacuous POSITIVE: owner A reads its own rows (guards an over-
--                  restrictive / absent SELECT policy).
--   (1b)         -> RED if the SELECT policy were dropped/widened (B would see A's taxonomy).
--   (2a)/(2b)/(2c)-> RED if a write GRANT were opened to authenticated (V1-write-dormancy
--                  broken): the message would change from grant-layer 'permission denied'
--                  (or the write would commit). Guards the SELECT-only grant against widening.
--   (3a)/(3b)    -> RED if anon gained SELECT on user_taxonomy OR USAGE on schema pfin
--                  (ADR-023 C2 internet-facing outer fence).
--   (4a)         -> RED if UNIQUE(users_id,domain,cat,sub_cat) were dropped (dup taxonomy row).
--   (4b)         -> RED if the domain CHECK were dropped (bad value commits). [(4c) tax_character
--                  membership was REMOVED at 011: the inline CHECK became an FK -> tax_character
--                  (code), so a bad code now raises 23503 (not 23514). Coverage moved to the 011
--                  battery c1; keeping (4c) here would assert a CHECK 011 deleted. Teeth preserved
--                  — bad code still fails closed, just at the FK layer now.]
--   (5a)/(5b)/(5c)-> RED if the 010 `notes` column were dropped/renamed, retyped off text, or
--                  made NOT NULL (guards the additive-nullable-column contract).
--   (5d)         -> RED if the new column were NOT readable under user_taxonomy_select (owner A
--                  could no longer read its own notes — the column-add broke owner-reads-own).
--   (5e)         -> RED if the SELECT policy were dropped/widened so B could see A's notes
--                  CONTENT — the notes-specific golden cross-tenant violation. Non-vacuous:
--                  with RLS off, B's `where notes = <A's value>` returns A's row (count 1 ≠ 0).
--
-- §10 / DECISION 3: ledger UNCHANGED at 2 (RT-22 + RT-26); Decision-3 family UNCHANGED
--   (009's sole reference column users_id -> auth.users IS the tenant anchor — no second
--   anchor to mismatch; the deferred sub_cat_id -> user_taxonomy FK is a separate Decision-3
--   evaluation at THAT migration, not here). Per the 009 header §10 3-axis + Decision-3 eval.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real financial data / NO prod data. Rows are seeded PRIVILEGED (role=postgres)
--   because there is NO authenticated write path (V1-write-dormant); auth.uid() is NULL under
--   postgres, so users_id is set explicitly for the seeds. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs while switched to authenticated. Tenant UUIDs + row ids are resolved to
--   psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres
--   and each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 009's firmed contract; the authoritative run is against the
--   001→009 reset stack. Roles `authenticated` / `anon` name-checked in (2*)/(3*). RED-until-
--   009-applied is expected on any pre-009 stack (the table would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(14);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed; the only write path, since
-- user_taxonomy is V1-write-dormant). A owns TWO taxonomy rows (asset + cashflow); B owns ONE.
-- users_id is set explicitly (auth.uid() is NULL under postgres).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant, tax_character)
  values (:'ta', 'asset', 'Brokerage', 'US Equity', true, 'qualified_dividend')
  returning id as a_row \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant)
  values (:'ta', 'cashflow', 'Income', 'Salary', true);
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
  values (:'tb', 'asset', 'Brokerage', 'US Equity');

-- =====================================================================
-- BLOCK 1 — RLS SELECT isolation (two-tenant core).
-- =====================================================================
-- (1a) POSITIVE (non-vacuous): owner A reads exactly its 2 own taxonomy rows.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint, 2::bigint,
  '(1a) two-tenant core: owner A reads exactly its 2 own user_taxonomy rows (direct-owner RLS users_id = auth.uid() — not over-restrictive)'
);
select set_config('role', 'postgres', true);

-- (1b) cross-tenant read fails closed: B sees ZERO of A's taxonomy rows.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint, 0::bigint,
  '(1b) cross-tenant read fails closed: B sees 0 of A''s user_taxonomy rows (RLS direct-owner isolation)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 — V1-WRITE-DORMANT: authenticated I/U/D fail closed at the GRANT layer.
--   SELECT-only grant + no write policy => 'permission denied for table user_taxonomy' (42501),
--   the grant-layer mechanism (NOT the WITH-CHECK RLS-policy message). Run under authenticated
--   A (its OWN rows) to prove even the owner cannot write in V1 — a pure grant-layer denial.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (2a) authenticated INSERT fails closed at the ACL (no INSERT grant; no write policy).
select throws_like(
  $$ insert into pfin.user_taxonomy (domain, cat, sub_cat) values ('asset', 'Brokerage', 'Intl Equity') $$,
  'permission denied for table user_taxonomy',
  '(2a) V1-write-dormant: authenticated INSERT fails closed at the GRANT layer (permission denied — SELECT-only grant, no write policy; distinct from a WITH-CHECK RLS rejection)'
);
-- (2b) authenticated UPDATE fails closed at the ACL (targets A's own row; ACL denies pre-RLS).
select throws_like(
  format($$ update pfin.user_taxonomy set cat = 'Changed' where id = %s $$, :a_row),
  'permission denied for table user_taxonomy',
  '(2b) V1-write-dormant: authenticated UPDATE fails closed at the GRANT layer (no UPDATE grant — guards the SELECT-only grant against widening)'
);
-- (2c) authenticated DELETE fails closed at the ACL.
select throws_like(
  format($$ delete from pfin.user_taxonomy where id = %s $$, :a_row),
  'permission denied for table user_taxonomy',
  '(2c) V1-write-dormant: authenticated DELETE fails closed at the GRANT layer (no DELETE grant)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 — C2 ADR-023 internet-facing anon outer fence.
-- =====================================================================
-- (3a) anon holds NO SELECT on user_taxonomy (table-ACL zero-grant).
select ok(
  not has_table_privilege('anon', 'pfin.user_taxonomy', 'SELECT'),
  '(3a) ADR-023 C2 outer fence: anon holds NO SELECT on pfin.user_taxonomy (internet-facing table not anon-readable)'
);
-- (3b) ...and anon holds NO USAGE on schema pfin (the primary schema-usage-layer denial).
select ok(
  not has_schema_privilege('anon', 'pfin', 'USAGE'),
  '(3b) ADR-023 C2 outer fence: anon holds NO USAGE on schema pfin (denied at the schema-usage layer before any table ACL is consulted)'
);

-- =====================================================================
-- BLOCK 4 — shape constraints (privileged inserts; each catches a dropped constraint).
-- =====================================================================
-- (4a) UNIQUE(users_id, domain, cat, sub_cat): a duplicate of A's existing row raises 23505.
select throws_ok(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
              values (%L, 'asset', 'Brokerage', 'US Equity') $$, :'ta'),
  '23505', null,
  '(4a) UNIQUE(users_id,domain,cat,sub_cat): a duplicate (users_id,domain,cat,sub_cat) raises unique_violation (23505)'
);
-- (4b) domain CHECK: a value outside ('asset','cashflow') raises 23514.
select throws_ok(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat)
              values (%L, 'not_a_domain', 'X', 'Y') $$, :'ta'),
  '23514', null,
  '(4b) domain CHECK: a domain outside (asset,cashflow) raises check_violation (23514) — fails closed on a bad value'
);
-- (4c) REMOVED at 011: the inline tax_character CHECK was converted to an FK ->
--   pfin.tax_character(code), so a bad code now raises 23503 (foreign_key_violation), not 23514.
--   Directory-mode pgTAP runs this file against the post-011 schema, so the old 23514 premise is
--   stale. Membership-enforcement coverage moved to 011_tax_character_rls.sql (c1: bad code ->
--   23503; c2: valid code lives; c3: NULL lives). Teeth preserved — bad code still fails closed,
--   just at the FK layer now. (4a) UNIQUE + (4b) domain CHECK are unchanged by 011 and stay.

-- =====================================================================
-- BLOCK 5 — MIGRATION 010: additive nullable `notes text` column.
--   010 adds `notes text NULL` (no default) and NO new grant/policy — the column
--   inherits 009's SELECT grant + user_taxonomy_select (users_id = auth.uid()). This
--   block is a lightweight EXTENSION of the existing two-tenant battery (reusing the
--   BLOCK-1 fixture: A owns 2 rows, B owns 1), NOT a new battery. It asserts (i) the
--   additive-nullable-column shape and (ii) that the column-add introduced no leak —
--   owner-reads-own still holds WITH the column present, and A's notes CONTENT does
--   not cross to B.
-- =====================================================================
-- (5a) column exists (catalog; role-independent).
select has_column(
  'pfin', 'user_taxonomy', 'notes',
  '(5a) 010: pfin.user_taxonomy.notes column exists'
);
-- (5b) type is text.
select col_type_is(
  'pfin', 'user_taxonomy', 'notes', 'text',
  '(5b) 010: notes is type text'
);
-- (5c) nullable (optional per-row note; no default).
select col_is_null(
  'pfin', 'user_taxonomy', 'notes',
  '(5c) 010: notes is nullable (optional; no default) — additive-nullable contract'
);

-- Seed a distinct notes value on A's asset row. Privileged (role=postgres) — the only
-- write path (V1-write-dormant). Gives the read assertions TEETH: a real, tenant-A-owned
-- value that (5d) must surface to A and (5e) must NOT surface to B.
update pfin.user_taxonomy set notes = 'tenant-A private note' where id = :a_row;

-- (5d) owner-reads-own-INCLUDING-notes: A reads its own row and sees the notes value
--      (proves the new column is readable under the existing SELECT policy — no column
--       restriction crept in; owner-reads-own still holds with the column present).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select notes from pfin.user_taxonomy where id = :a_row),
  'tenant-A private note',
  '(5d) 010: owner A reads its own notes under user_taxonomy_select (new column readable; owner-reads-own holds with the column present)'
);
select set_config('role', 'postgres', true);

-- (5e) cross-tenant notes CONTENT fails closed: B sees ZERO rows carrying A's notes value.
--      The column-add introduced NO leak — the direct-owner RLS filter still holds with the
--      new column present. Non-vacuous: with RLS off/widened, this returns 1 (A's row).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where notes = 'tenant-A private note')::bigint, 0::bigint,
  '(5e) 010: cross-tenant fails closed — B sees 0 rows carrying A''s notes (no leak from the column add; RLS direct-owner isolation holds with the new column)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
