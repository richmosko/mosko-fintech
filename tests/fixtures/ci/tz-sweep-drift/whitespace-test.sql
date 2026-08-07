-- GOLDEN FIXTURE — whitespace-only difference (the (T3) half).
-- Paired with whitespace-runbook.md. MUST STAY GREEN.
--
-- Not a real test: lives under tests/fixtures/ci/, carries no plan()/finish(), and is
-- never collected by pg_prove. Consumed only by the tz-sweep-identical inversion step.
--
-- Token-identical to whitespace-runbook.md, byte-different from it. This pair proves the
-- normalization actually normalizes — i.e. that the fence's reds are attributable to
-- semantics and not to formatting. A fence proven only to RED is not proven to red for
-- the right reason.

select is_empty(
  $$
        select r.rolname, d.datname, c as setting
          from pg_db_role_setting s
                join pg_roles r on r.oid = s.setrole
          left join pg_database d on d.oid = s.setdatabase
                cross join lateral unnest(s.setconfig) as c
         where s.setrole <> 0
           and c ilike 'timezone=%'
  $$,
  'golden fixture — expects the fence to stay GREEN despite the re-indentation'
);
