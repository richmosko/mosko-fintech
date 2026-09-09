---
name: role-battery-inversion-recipes-self386-s5
description: How to construct a duplicate-grantor (h12-class) fixture and a large-object-ACL probe against a live cluster role battery (116_pfin_provider_sync_role.sql, PR #671); the ran-count watcher's real location; two confirmed leg-blindness findings.
metadata:
  type: reference
---

SELF-386 / BACKLOG §7.6 S5, 2026-09-08. QA adoption review of Architect-authored
`supabase/tests/rls/116_pfin_provider_sync_role.sql` (role-boundary flag in the PR
body — Architect authored it on team-lead instruction; QA re-verified rather than
trusted).

**Duplicate-grantor (h12-class) fixture recipe, when you need a SECOND real
grantor and `postgres` isn't a true superuser.** On this project's local Supabase
stack `postgres` has `rolsuper = f` (it's a managed fake-superuser role with
`rolbypassrls = t`, not `rolsuper`). `GRANT x TO y GRANTED BY supabase_admin` from
`postgres` fails even though `postgres` looks superuser-ish
(`permission denied to grant privileges as role "supabase_admin"`), and
`SET ROLE supabase_admin` from `postgres` ALSO fails
(`"supabase_admin" role memberships are reserved, only superusers can grant them`).
Working recipe: connect **directly as** `supabase_admin`
(`docker exec ... psql -U supabase_admin -d <db> -c "grant authenticated to
pfin_provider_sync;"`) — it IS `rolsuper = t` and can log in. This produces a real
second `pg_auth_members` row for the SAME membership under a DIFFERENT grantor,
exactly the 2026-08-17 `pfin_etl` drift class ([[feedback_cluster_role_membership_
drift_054_h12]]). Clean up with `revoke ... from ... granted by supabase_admin`
run AS `supabase_admin` (not `postgres`) — `postgres` can't revoke a grant it
didn't make either.

**Confirmed empirically (not just read from the query text): 116's (r5)/(r8) DO
catch this class**, not merely `anon`-widening — `string_agg` without `distinct`
produces `authenticated,authenticated,service_role` (or the `=true,=true` sibling
for (r8)), which fails the `is()` equality. Battery went RED on exactly (r5)+(r8)
with the duplicate grantor in place, GREEN once revoked back to single-grantor.

**Confirmed empirically: (r10)'s "zero object privilege anywhere" catch-all DOES
enumerate `pg_default_acl`** (tested: `alter default privileges in schema pfin
grant select on tables to pfin_provider_sync` → (r10) REDs) **but is BLIND to
`pg_largeobject_metadata.lomacl`** (tested: `select lo_create(...); grant select
on large object <oid> to pfin_provider_sync;` → full battery stayed GREEN,
12/12). Low-severity in this repo (no `lo_*` usage anywhere in the schema, and
`pfin_provider_sync` gets zero grants by 116's own contract so it will never be a
large-object grantee through any real code path) — flagged, not fixed; a future
role battery claiming a truly unscoped object-privilege inventory should either
add this branch or narrow the claim in prose.

**The "ran-count watcher" (`_get('plan') - _get('curr_test')`) precedent lives in
`115_fn_finalize_monthly_report_rls.sql` (search `_get(`), NOT
`self362_v15_close_gate.sql`** — a team-lead brief named the wrong file (self362
has no `_get(` call at all; grepped the whole `tests/rls/` tree to confirm before
reporting this as a brief error, not a memory slip). Doesn't matter for a battery
with zero trailing savepoint-wrapped legs (116 has none — every leg runs straight
through inside one `begin/rollback`, no nested savepoints), so the watcher class
doesn't apply to 116 at all; noting the correct location for the next file that
actually needs one.

**Scratch-DB mechanics that worked cleanly this round, worth repeating:**
`scripts/db-template-clone.sh` refuses to clone once the new migration file is
back in the tree (its sha256 covers the WHOLE migrations directory) — hold the
new migration+battery file out via `mv` to a scratchpad dir, clone, `mv` the
migration back into the tree, then `docker exec -i psql -f` it directly onto the
clone (not through the CLI). `public.ecr.aws/supabase/pg_prove:3.36` is the
correct pg_prove image (found via `docker images`, not documented anywhere);
invoke with `--network supabase_network_<project>` and `-v
<real-host-tests-dir>:/tests`, target `-d
postgresql://postgres:postgres@supabase_db_<project>:5432/<scratchdb>`.
