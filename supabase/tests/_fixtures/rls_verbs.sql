-- =====================================================================
-- RLS battery — shared assertion verbs (helper-placement Option C via \ir)
-- =====================================================================
-- NOT a standalone pgTAP test — has no plan()/finish(). It is `\ir`-included
-- at the top of each battery test file (inside that test's begin…rollback txn),
-- so the verbs are (re)created transactionally per test and rolled back with it.
-- This keeps a single DRY verb source (Option C) without depending on cross-file
-- pgTAP state persistence or a specific seed-load mechanism.
--
-- Lives under `_fixtures/` and is excluded from the run by the db-tests.yml job's
-- EXPLICIT file list (NOT by directory name): `supabase test db` runs `pg_prove -r`
-- which recurses, so the bare `supabase/tests` dir would otherwise collect this
-- planless file as a test and fail. Resolved at author-time (DevOps 2026-06-25);
-- the parent dir is still mounted so `\ir _fixtures/rls_verbs.sql` resolves.
--
-- Contract (firmed per team-lead relay 2026-06-25):
--   RLS predicate convention: users_id = auth.uid()  (post 001_users_id_rename)
--   tenant context: role=authenticated + request.jwt.claims.sub
-- =====================================================================

create schema if not exists _rls;

-- fixed synthetic tenant identities (deterministic, diffable)
create or replace function _rls.tenant_a() returns uuid
  language sql immutable as $$ select '00000000-0000-0000-0000-00000000000a'::uuid $$;
create or replace function _rls.tenant_b() returns uuid
  language sql immutable as $$ select '00000000-0000-0000-0000-00000000000b'::uuid $$;

-- set the active tenant RLS context for subsequent statements (within the txn)
create or replace function _rls.set_tenant(p_tenant uuid) returns void
  language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_tenant::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- count rows of p_table with users_id=p_owner that p_intruder can see (the probe)
create or replace function _rls._visible_owner_rows(
  p_table regclass, p_owner uuid, p_intruder uuid
) returns bigint
  language plpgsql as $$
declare n bigint;
begin
  perform _rls.set_tenant(p_intruder);
  execute format('select count(*) from %s where users_id = $1', p_table)
    into n using p_owner;
  perform set_config('role', 'postgres', true);  -- restore for the next assertion
  return n;
end;
$$;

-- VERB: intruder must see ZERO of owner's rows (cross-tenant read fails closed)
create or replace function _rls.expect_cross_tenant_read_empty(
  p_table regclass, p_owner uuid, p_intruder uuid
) returns text
  language sql as $$
  select is(
    _rls._visible_owner_rows(p_table, p_owner, p_intruder),
    0::bigint,
    format('cross-tenant read fails closed: intruder sees 0 owner rows in %s', p_table)
  );
$$;

-- VERB: owner must see exactly N of its own rows (guards over-restrictive policy)
create or replace function _rls.expect_owner_can_read(
  p_table regclass, p_owner uuid, p_expected bigint
) returns text
  language sql as $$
  select is(
    _rls._visible_owner_rows(p_table, p_owner, p_owner),
    p_expected,
    format('owner reads exactly %s own rows in %s (not over-restrictive)', p_expected, p_table)
  );
$$;

-- VERB: intruder write into owner-owned space must fail closed (RLS WITH CHECK)
-- p_insert_sql targets p_table with the OWNER's users_id; must raise under intruder.
create or replace function _rls.expect_cross_tenant_write_blocked(
  p_intruder uuid, p_insert_sql text, p_desc text default null
) returns text
  language plpgsql as $$
begin
  perform _rls.set_tenant(p_intruder);
  return throws_ok(
    p_insert_sql,
    '42501',  -- insufficient_privilege / RLS violation
    null,
    coalesce(p_desc, 'cross-tenant write fails closed (RLS WITH CHECK rejects intruder)')
  );
end;
$$;
