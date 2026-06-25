-- =====================================================================
-- RLS battery — INVERSION SELF-TEST (the harness proves itself)
-- =====================================================================
-- Mirrors W1's CI inversion-mode: a fence is only trustworthy if it FAILS
-- against a known-bad fixture. This proves the cross-tenant probe has TEETH —
-- it detects a leak when isolation is absent — so a green battery is never
-- vacuous. Ships with the framework; runs every battery invocation.
--
-- Negative-detection is proven here (probe DETECTS a leak on an unprotected
-- table). Positive isolation (probe returns 0 on a PROTECTED table) is proven
-- by per-table cases once real RLS tables land (Phase 6).
-- =====================================================================

begin;

-- load the shared verbs textually into this txn (Option C via \ir)
-- (.psql non-test extension: pg_prove -r mounts it in directory-mode but does
--  not run it as a planless test)
\ir _fixtures/rls_verbs.psql

select plan(2);

-- throwaway, deliberately UNPROTECTED canary (RLS never enabled -> leaks)
create table _rls_canary (users_id uuid not null, val text not null);
insert into _rls_canary (users_id, val) values
  (_rls.tenant_a(), 'A-owned-secret'),
  (_rls.tenant_b(), 'B-owned');

-- 1) the probe DETECTS the leak: intruder B sees A's row on an unprotected table.
--    (isnt 0 => the same assertion the battery uses WOULD fire on a real leak.)
select isnt(
  _rls._visible_owner_rows('_rls_canary'::regclass, _rls.tenant_a(), _rls.tenant_b()),
  0::bigint,
  'inversion: cross-tenant probe DETECTS a leak on an unprotected table (has teeth)'
);

-- 2) sanity: the probe sees the owner''s own row (context switch + count works)
select is(
  _rls._visible_owner_rows('_rls_canary'::regclass, _rls.tenant_a(), _rls.tenant_a()),
  1::bigint,
  'inversion: probe sees owner''s own row'
);

select * from finish();
rollback;
