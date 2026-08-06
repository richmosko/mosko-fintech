# GOLDEN FIXTURE — semantic drift (the runbook half)

Not a real runbook. Consumed only by the `tz-sweep-identical` inversion step in
`.github/workflows/security-scan.yml`. Paired with `semantic-test.sql`.

**The perturbation is `s.setrole <> 0`, which this copy is MISSING.** That is not an
arbitrary difference — it is the exact clause whose absence was the real defect: without
it the sweep matches `061`'s own database-level pin (a `setrole = 0` row), returns one
row against a correctly pinned database, and STOPs a correct deployment on the very
declaration it exists to confirm. Encoding the real defect as the golden means this
fixture proves the fence catches the thing that actually happened, not a synthetic
difference chosen for convenience.

The indentation here is deliberately IDENTICAL to `semantic-test.sql` so that the only
difference the fence can be reacting to is the semantic one. If this fixture also varied
whitespace, a red would not distinguish "caught the semantics" from "caught the spacing."

```sh
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where c ilike 'timezone=%'"
```
