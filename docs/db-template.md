# Scratch-DB template — fast clone instead of sequential apply

**Status:** DevOps-owned tooling (loop-mechanics option A, F/CTO-ratified 2026-09-02
sitting). Replaces, for QA/Architect verification work, the sequential
`supabase/migrations/001..0NN` apply documented in
`.claude/agent-memory/architect/reference_scratch_db_full_chain_recipe.md` and
`reference_scratch_db_for_migration_verify.md` — those recipes remain the ground
truth for WHAT a correct scratch DB looks like; this doc is HOW to get one in
seconds instead of a full sequential apply.

## The short version

```bash
# once, or whenever pfin_tmpl is stale (see below)
scripts/db-template-build.sh

# every time you need a throwaway migrated DB
scripts/db-template-clone.sh my_scratch_name
```

`db-template-clone.sh` refuses to clone — loudly, exit 1, no DB created — if the
template doesn't match the current `supabase/migrations/` tree. If you see that,
run `db-template-build.sh` and retry.

## What's actually happening

- `db-template-build.sh` runs the real sequential chain **once** (the same
  auth/extensions/vault dump + supabase_admin ownership dance + full
  001..0NN apply the existing recipes document — deliberately NOT
  `--no-privileges`/`--no-owner`, which would drop REVOKEs and make the
  result more permissive than the real bootstrap) and leaves the result as a
  Postgres template database, `pfin_tmpl`. It stamps a marker
  (`public._template_meta`: head migration filename + sha256 of the full
  migrations tree + build timestamp) before promoting the build — a failed
  or partial build is dropped, never promoted.
- `db-template-clone.sh <name>` reads that marker, recomputes the same two
  values from your CURRENT `supabase/migrations/` tree, and compares. Any
  mismatch — including editing an already-numbered migration file in place,
  which a filename-only check would miss — refuses to clone. On a match, it
  clones via `createdb --template=pfin_tmpl` (seconds, not a full apply),
  then replays every database-level (`pg_db_role_setting`, `setrole = 0`)
  setting `pfin_tmpl` carries onto the clone — `CREATE DATABASE ... TEMPLATE`
  does NOT copy that catalog (it's keyed by database OID; a clone gets a new
  one), which is exactly the gap QA measured 2026-08-19 (085) losing
  migration 061's `TimeZone=UTC` pin. The replay is generic — it reads
  whatever `pfin_tmpl` actually carries, not a hardcoded TimeZone-only fix —
  so a future migration adding another `ALTER DATABASE ... SET` is covered
  with no edit needed here.

## Verified end-to-end (2026-09-02, devops)

- Cloned `pfin_tmpl` and ran `supabase/tests/01_session_timezone.sql`
  (T1 value / T2 mechanism / T3 cluster) via `pg_prove` against the clone:
  **3/3 pass**, `pg_settings.source = 'database'` — i.e. the clone reads as a
  real `061` pin, not an image default or an unpinned override.
- Built a genuine sequential-apply scratch DB by hand as a control and ran
  the same file: **3/3 pass**, identical result.
- Diffed the full `GRANT`/`REVOKE` posture (`pg_dump --schema-only`,
  `pfin`+`public`) between the template-clone and the sequential-build
  control: **byte-identical, 177/177 lines** — the `--no-privileges` trap
  (dropping REVOKEs, making a harness more permissive than production) does
  not apply here.
- `has_schema_privilege('anon','pfin','USAGE')` reads `false` on both —
  the outer fence (anon holds zero grants on every pfin relation, per
  `supabase/config.toml`'s own comment) survives the clone identically.

## Refresh trigger

`.husky/post-merge` calls `db-template-build.sh` automatically whenever a
local merge changes `supabase/migrations/` — best-effort, never blocks the
merge that already happened. **This is a convenience, not the correctness
boundary** — `db-template-clone.sh`'s own staleness check is what actually
prevents a stale clone, independent of whether the hook fired, fired against
the right tree, or even exists in your checkout. If you're not in the shared
main checkout, or the hook didn't run for any reason, just run
`db-template-build.sh` by hand before cloning.

## What this does not cover

- Local/CI throwaway tooling only — no opinion on Coolify or production.
- Role-level GUC overrides (`ALTER ROLE ... SET`) are cluster-level, already
  shared by every database including a clone — nothing to replay for those.
- A clone is disposable per **session**, not per query — QA's existing
  discipline
  (`.claude/agent-memory/qa/feedback_scratch_db_perf_seed_must_be_rolled_back.md`)
  still applies: don't leave ad hoc committed rows in a clone across
  unrelated verification runs; drop and re-clone instead.
- `db-template-build.sh` needs the local Supabase stack up (same container
  discovery convention as `scripts/db-snapshot.sh`) and a host `psql`/
  `createdb`/`dropdb`. It does not touch F/CTO's own local dev database —
  everything happens in `pfin_tmpl` and whatever scratch name you clone to.
