-- GOLDEN FIXTURE — semantic drift (the (T3) half). Paired with semantic-runbook.md.
--
-- Not a real test. Never collected by pg_prove: it lives under tests/fixtures/ci/, not
-- supabase/tests/, and carries no plan()/finish(). Consumed only by the
-- tz-sweep-identical inversion step in .github/workflows/security-scan.yml.
--
-- This half carries `s.setrole <> 0`; semantic-runbook.md does NOT. Indentation is
-- identical between the two files by construction, so the fence's red can only be
-- attributable to the semantic difference.

select is_empty(
  $$ select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where s.setrole <> 0
      and c ilike 'timezone=%' $$,
  'golden fixture — expects the fence to RED on the missing setrole filter'
);
