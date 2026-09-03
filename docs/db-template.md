# Scratch-DB template — fast clone instead of sequential apply

**Status:** DevOps-owned tooling (loop-mechanics option A, F/CTO-ratified 2026-09-02
sitting). Replaces, for QA/Architect verification work, the sequential
`supabase/migrations/001..0NN` apply documented in
`.claude/agent-memory/architect/reference_scratch_db_full_chain_recipe.md` and
`reference_scratch_db_for_migration_verify.md` — those recipes remain the ground
truth for WHAT a correct scratch DB looks like; this doc is HOW to get one in
seconds instead of a full sequential apply.

## Why this exists (measured, not the ratification's original framing)

The loop-mechanics ratification named the sequential migration apply as the
biggest per-issue time sink across four recent arcs. **Measured step-by-step
(2026-09-02, two independent runs, reproducible ±0.1s), that framing doesn't
hold at the level of raw command wall-clock:** prep (auth/extensions/vault
dump + supabase_admin load + ownership transfer) is ~0.6s; the 99-file
sequential apply is ~4.0–4.1s; the whole sequential build is ~4.8s end to
end. None of that is actually slow in absolute terms — a scripted, one-shot
run of the full recipe takes under 5 seconds.

**So the real win here isn't raw execution time — it's collapsing the
recipe's ~15 discrete steps (each individually documented as a gotcha in
QA's and Architect's own memory: `docker exec -i`, load-order,
supabase_admin-vs-postgres ownership, pgtap schema placement, the
`--no-privileges` trap, database-name case-folding) into one fenced command
that cannot be gotten wrong, instead of re-derived by hand each time by
whichever agent needs a scratch DB.** The clone being under a second instead
of ~4.8s is real and worth having, but it's the bonus, not the headline —
uniformity and gotcha-elimination is the actual case for this tooling. See
the design report for the full step timings and the reasoning that ruled out
a two-layer (rarely-refreshed prep base + fresh apply per use) split: since
apply is the dominant slice of an already-cheap total, splitting would only
shave the ~0.6s prep portion and leave the ~4s apply cost paid on every use.

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

**Step timings** (fresh candidate DB, dropped after; reproduced twice):

| Step | Time |
|---|---|
| `docker exec pg_dump` (auth/extensions/vault/graphql/net/storage/supabase_functions) | 0.13s |
| `createdb` candidate (owner supabase_admin) | 0.05s |
| load auth dump as supabase_admin | 0.35s |
| create extensions | 0.04s |
| ownership transfer to postgres | 0.03s |
| **prep subtotal** | **~0.6s** |
| apply 99 migrations sequentially | **~4.0–4.1s** |
| create extension pgtap | 0.07s |
| **sequential build total** | **~4.8s** |
| **template clone (`db-template-clone.sh`)** | **<1s** |

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
