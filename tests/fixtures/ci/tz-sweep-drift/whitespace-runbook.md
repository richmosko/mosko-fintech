# GOLDEN FIXTURE — whitespace-only difference (the runbook half)

Not a real runbook. Paired with `whitespace-test.sql`. Consumed only by the
`tz-sweep-identical` inversion step in `.github/workflows/security-scan.yml`.

**This pair must stay GREEN.** It is the other half of "make it fail once" and it is the
half that is usually skipped: a fence proven only to red has not been shown to red *for
the right reason*. Without this fixture, a fence that reds on everything — including a
re-indent — would look identical to a working one, right up until someone reformats the
runbook, gets a red they cannot explain, and deletes the job.

The query below is **token-identical** to `whitespace-test.sql` and **byte-different**
from it: this copy is flattened onto fewer lines with different indentation. That is not
a contrived difference — it is the real one. The two production copies live in
structurally different contexts (a shell double-quoted `psql -Atc` argument versus a
`$$ … $$` SQL literal) and cannot be indented alike, which is precisely why the fence
normalizes whitespace and why the claim it enforces is "token-for-token, modulo
indentation" rather than plain "identical".

```sh
psql "$PROD_DB_URL" -Atc \
  "select r.rolname, d.datname, c as setting from pg_db_role_setting s
        join pg_roles r on r.oid = s.setrole
            left join pg_database d on d.oid = s.setdatabase
   cross join lateral unnest(s.setconfig) as c where s.setrole <> 0 and c ilike 'timezone=%'"
```
