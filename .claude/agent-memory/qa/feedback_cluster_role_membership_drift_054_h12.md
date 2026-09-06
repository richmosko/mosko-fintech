---
name: feedback-cluster-role-membership-drift-054-h12
description: Full /tests regression on a rebuilt pfin_tmpl surfaced 054_nav_daily_rls.sql (h12) failing — pfin_etl carries a doubled service_role/authenticated membership, unrelated to the migration under review. Cluster-level role state, not a real regression.
metadata:
  type: feedback
---

Running the FULL `/tests` tree (not just `/tests/rls`) against a freshly-rebuilt
`pfin_tmpl` (SELF-352, 2026-09-05) surfaced `054_nav_daily_rls.sql` (h12) failing:
`pfin_etl` reported membership `authenticated,authenticated,service_role,service_role`
instead of `authenticated,service_role`. The test file's own comment names this exact
failure mode as a previously-observed live drift (2026-08-17, duplicate grantor, not a
third role) — so this is a KNOWN CLASS, not a novel bug, but it recurred on a
freshly-built template with only a single sequential 001→106 apply behind it.

**Root cause, consistent with [[feedback_postgres_roles_are_cluster_level_not_per_db]]
(`pfin_etl`, `service_role`, `authenticated` are CLUSTER-LEVEL roles):** every
`db-template-build.sh` run across every session that has ever built `pfin_tmpl` (or any
other from-scratch scratch DB) on this same local Postgres cluster re-executes
`grant service_role to pfin_etl; grant authenticated to pfin_etl;` from migration 055.
Because the ROLE and its memberships live in a shared, cluster-wide catalog
(`pg_auth_members`), NOT the freshly-created database, repeated template rebuilds over
the project's history can accumulate duplicate membership rows recorded under different
grantors — the exact shape (h12) checks for and the exact failure mode 2026-08-17 already
named. This is orthogonal to which DATABASE you're building; a `createdb` a fresh database
does not reset cluster-level role state.

**How to apply:** if a full-tree regression run surfaces (h12) failing with a doubled
membership list, do NOT treat it as a regression introduced by the migration or test file
under review — check the failure is this exact shape (`have` string repeats each role
name) before investigating further. It is NOT this session's finding to fix (no Write/Edit
access to `pfin_etl`'s cluster-level grants from a scratch-DB verification pass, and fixing
it would require a `REVOKE ... GRANTED BY <grantor>` per duplicate grantor against the
role, which is a DevOps/cluster-hygiene action, not a migration or test edit). Report it as
a pre-existing, unrelated finding in the hand-off and move on — re-cloning `pfin_tmpl` does
NOT clear it (the drift lives in the cluster, survives every clone and every template
rebuild).
