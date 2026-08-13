-- =====================================================================
-- Catalog battery — pfin.nav_daily table-comment amendment (SELF-217; migration
--   068). COMMENT-ONLY migration: authors no function, table, column, policy,
--   grant, or trigger — the one executable statement is `comment on table`. The
--   052 shape (self227_investment_mv_verification.sql's AC#3) applies: render-
--   verify the CATALOG, not the .sql source text, because that is what a reader
--   with no repo in front of them (`\d+ pfin.nav_daily`) actually sees, and a
--   doubled `''` leaking into rendered text would be invisible in source.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/068_nav_daily_backfill_amendment_comment.sql,
--   commit df25878 on branch richmosko/self-217-212a-... (architect worktree).
--   Authored against that migration's own QA TEST-PAIRING block (4 items) —
--   not from the team-lead relay text, per the same discipline applied on
--   SELF-218's 067 battery.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ─┐
-- │ (1) The catalog was actually amended: obj_description contains 'SELF-217'.      │
-- │     Fires if 068 was never applied, or landed on the wrong object.              │
-- │ (2) The FALSIFIED claim is GONE: obj_description no longer contains 'no         │
-- │     historical backfill in V1.1'. This is the whole point of the migration.     │
-- │ (3) The SURVIVING prohibition is STILL stated: obj_description still contains   │
-- │     'must NOT be' (050's recompute-forbidding TEMPORAL CONSTRAINT clause).      │
-- │     Without this, a future "simplification" could drop the recompute            │
-- │     prohibition while item 2 stayed green — the exact misreading ADR-053        │
-- │     exists to prevent.                                                         │
-- │ (4) NOTHING ELSE MOVED: 054's grants and both mutation-block triggers are       │
-- │     unchanged. A `comment on table` cannot alter privileges or triggers by      │
-- │     itself, so this leg exists to catch a migration that quietly did MORE      │
-- │     than its own header claims — the regression class this file is FOR.        │
-- └──────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ NO TENANT FIXTURE. Every assertion here reads pg_catalog metadata
--   (obj_description, has_table_privilege, has_column_privilege, pg_trigger) at
--   role=postgres. No auth.users row, no _rls.* verb, no nav_daily data row is
--   needed — this migration touches no data and no RLS-relevant state. Matches
--   self227's AC#3 precedent ("obj_description checks run at role=postgres").
--
-- §10 / DECISION 3 / DEFINER ALLOWLIST: this battery introduces NO catalogued
--   instance and changes none — 068 authors one `comment on table`, no function,
--   no column. Read ADR-011 Decision 3 and Decision 4 LIVE at the canonical
--   anchor at merge time; no count restated here.
--
-- POSTURE (SECURITY §4.5): N/A in the usual two-tenant sense — this migration
--   creates no per-tenant write path of its own (068 amends a comment on an
--   existing table; 054's own two-tenant battery already covers nav_daily's RLS
--   surface and is not re-derived here). SYNTHETIC-only where relevant: item
--   (4)'s privilege checks name no real credential and touch no row.
--
-- ⚠ NOT YET RUN AGAINST A LIVE DATABASE. Verify on a SCRATCH database only
--   (apply 001->068 in order; 068 is comment-only and creates nothing, so a
--   rolled-back transaction against that stack suffices) — pg_prove, never
--   bare psql (plan-count enforcement). Mirror BOTH grants AND revokes when
--   constructing the scratch auth schema (the permissive-harness lesson from
--   SELF-218: `pg_dump --no-privileges` drops denials too, which would make
--   item (4)'s negative assertions vacuous if it touched auth-schema privilege
--   — it does not, but the discipline is recorded here for whoever reuses this
--   file as a template).
-- =====================================================================

begin;

-- plan = 6 : 1 catalog-amended (item 1) + 1 falsified-claim-gone (item 2) +
-- 1 surviving-prohibition-stated (item 3) + 2 grant-set-unchanged (item 4a/4b)
-- + 1 both-mutation-block-triggers-present (item 4c).
select plan(6);

-- =====================================================================
-- (1) THE CATALOG WAS ACTUALLY AMENDED.
-- =====================================================================
select ok(
  obj_description('pfin.nav_daily'::regclass, 'pg_class') like '%SELF-217%',
  '(1) obj_description(pfin.nav_daily) CONTAINS ''SELF-217'' — the table comment was actually replaced by 068, not left as 054 shipped it. RED if 068 was never applied, or the `comment on table` targeted the wrong relation'
);

-- =====================================================================
-- (2) THE FALSIFIED CLAIM IS GONE — the whole point of this migration.
-- =====================================================================
select ok(
  obj_description('pfin.nav_daily'::regclass, 'pg_class') not like '%no historical backfill in V1.1%',
  '(2) obj_description(pfin.nav_daily) does NOT contain ''no historical backfill in V1.1'' — the present-tense claim SELF-217 falsifies. RED if a future edit reinstates it verbatim, which is the exact regression this amendment exists to prevent'
);

-- =====================================================================
-- (3) THE SURVIVING PROHIBITION IS STILL STATED.
-- =====================================================================
select ok(
  obj_description('pfin.nav_daily'::regclass, 'pg_class') like '%must NOT be%',
  '(3) obj_description(pfin.nav_daily) STILL contains ''must NOT be'' (050''s TEMPORAL CONSTRAINT clause forbidding on-the-fly recomputation). ⚠ Without this leg, an over-eager future "simplification" could drop the recompute prohibition while (2) stayed green — the exact misreading ADR-053 exists to prevent: import is now admitted, recomputation is NOT'
);

-- =====================================================================
-- (4) NOTHING ELSE MOVED — 054's grant set and both mutation-block triggers,
--   asserted from the catalog directly rather than assumed unchanged. A
--   `comment on table` statement cannot itself alter an ACL or a trigger, but
--   this leg exists to catch a migration that quietly did more than one
--   comment — matching 054's OWN established assertion shapes (054_nav_daily_rls.sql)
--   rather than re-deriving new ones, so a drift in either file's idiom would
--   show up as a divergence between them.
-- =====================================================================
select ok(
  has_table_privilege('authenticated', 'pfin.nav_daily', 'SELECT')
  and not has_table_privilege('authenticated', 'pfin.nav_daily', 'INSERT')
  and not has_table_privilege('authenticated', 'pfin.nav_daily', 'UPDATE')
  and not has_table_privilege('authenticated', 'pfin.nav_daily', 'DELETE')
  and has_table_privilege('service_role', 'pfin.nav_daily', 'INSERT')
  and not has_table_privilege('service_role', 'pfin.nav_daily', 'UPDATE')
  and not has_table_privilege('service_role', 'pfin.nav_daily', 'DELETE')
  and not has_table_privilege('service_role', 'pfin.nav_daily', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'pfin.nav_daily', 'TRUNCATE')
  and not has_table_privilege('anon', 'pfin.nav_daily', 'SELECT'),
  '(4a) TABLE-LEVEL grant set is byte-for-byte what 054 shipped: authenticated SELECT-only, service_role INSERT-only (no UPDATE/DELETE/TRUNCATE for either role), anon holds nothing. RED if 068 — a comment-only migration by its own header — silently carried a GRANT or REVOKE statement'
);
select ok(
  has_column_privilege('service_role', 'pfin.nav_daily', 'users_id', 'SELECT')
  and has_column_privilege('service_role', 'pfin.nav_daily', 'nav_date', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'nav_value', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'nav_id', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'created_at', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.nav_daily', 'SELECT'),
  '(4b) COLUMN-LEVEL grant is unchanged: service_role reads ONLY (users_id, nav_date) — the ON CONFLICT arbiter columns 054 grants for the targeted upsert — and CANNOT read nav_value, nor hold a table-level SELECT. A positive assertion alone cannot distinguish a column grant from a table grant, so both the positives and the negatives are asserted together'
);
select is(
  (select count(*)::int from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'nav_daily'
      and t.tgname in ('nav_daily_block_mutation', 'nav_daily_block_truncate')
      and not t.tgisinternal),
  2,
  '(4c) BOTH mutation-block triggers are present by name: nav_daily_block_mutation (UPDATE/DELETE) and nav_daily_block_truncate (TRUNCATE). RED if 068 dropped or renamed either — which would silently reopen the append-only/irreversibility property ADR-053''s entire risk posture depends on ("the only repair is a migration")'
);

rollback;
