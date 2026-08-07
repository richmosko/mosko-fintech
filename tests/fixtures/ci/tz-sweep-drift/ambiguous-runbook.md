# GOLDEN FIXTURE — ambiguous anchor (two sweep blocks)

Not a real runbook. Consumed only by the `tz-sweep-identical` ambiguity-guard step in
`.github/workflows/security-scan.yml`.

**Two `-Atc` continuation blocks below.** The fence must FAIL CLOSED rather than
silently compare the first one, because it cannot know which block is the sweep — and the
first is not reliably the right answer.

This is not a hypothetical. The runbook grew a **step (1b)** catalog query in the very next
change after this fence was written. That one was deliberately written with `-At -c` so it
would not match the anchor — but a fence whose correctness depends on the next author
happening to pick a different flag spelling is not fenced, it is lucky. The second block
below is the same query with a trivially different `where` clause, so a fence that guessed
"the first match" would compare the wrong pair and report **green** while the property it
claims to guard went unexamined.

```sh
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where s.setrole <> 0
      and c ilike 'timezone=%'"
```

And a second, later block that also matches the anchor:

```sh
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting
     from pg_db_role_setting s
     join pg_roles r on r.oid = s.setrole
     left join pg_database d on d.oid = s.setdatabase
     cross join lateral unnest(s.setconfig) as c
    where s.setrole = 0
      and c ilike 'timezone=%'"
```
