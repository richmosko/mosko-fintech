---
name: control-build-at-earlier-head-via-template-rebuild
description: To get a genuine "before this migration" control DB for isolating pre-existing reds from a new migration's own effect, temporarily move the new migration + its test file out of the tree, rerun db-template-build.sh, clone, test, then restore both and rebuild the template again.
metadata:
  type: reference
---

Used at SELF-268/105 (2026-09-04) to answer "are these known local-cluster reds
identical on a control at 104" honestly, rather than asserting it from memory.

Recipe: `mv supabase/migrations/105_*.sql /tmp/hold/` AND `mv
supabase/tests/rls/105_*.sql /tmp/hold/` (both — leaving the test file in place
errors trying to exercise a shape the earlier migration doesn't have yet, which
is noise, not signal) → `./scripts/db-template-build.sh` (rebuilds `pfin_tmpl`
stamped at the new head, here `104`) → `./scripts/db-template-clone.sh
<name>_ctrl104` → install pgtap → run the SAME `pg_prove -r /tests/rls` →
compare file-for-file against the run at the real head. Then **restore both
moved files and rebuild the template again** before finishing, or every
subsequent clone in the session silently serves the wrong head.

This is a genuine sequential-apply control (not a copy of a copy), so it is
trustworthy for any per-database-setting claim too (unlike chaining
`CREATE DATABASE ... TEMPLATE` off another scratch clone — see
[[feedback_scratch_db_pgtap_harness_gotchas]] gotcha 4).

Payoff: confirmed `054_nav_daily_rls.sql`'s 3 pfin_etl-membership reds are
IDENTICAL on both 104-control and 105-applied (real cluster-level role state,
unrelated to either migration) — but ALSO surfaced that Architect's stated
list of other known reds (074/084/090/101, errors in 057/062/069) did NOT
reproduce on EITHER run. Flagged as a discrepancy rather than silently
reconciled or silently trusted — the dispatched list may describe F/CTO's
real persistent local dev DB, which a template-cloned scratch cannot
reproduce from here.

`createdb --template template0` does NOT work as a stand-in base for this —
it's a bare Postgres template with no `auth`/`extensions` schema, so any
migration referencing `auth.*` fails immediately. Always go through
`db-template-build.sh`'s real dump-and-apply chain.
