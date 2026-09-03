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
biggest per-issue time sink across four recent arcs. That framing doesn't
survive contact with a direct measurement, and the honest rationale has
three parts:

1. **Raw migration apply is ~4s, measured.** 99 files, sequential, two
   independent runs on 2026-09-02: 4.119s and 4.018s. Not free, but not the
   multi-minute drag the "biggest sink" framing implies either.
2. **Prep (auth/extensions/vault dump + supabase_admin load + ownership
   transfer) is ~0.6s, measured** — dump 0.13s, createdb 0.05s, load 0.35s,
   extensions 0.04s, ownership transfer 0.03s. This was the alternative
   hypothesis (Architect's premise-check: maybe prep, not apply, was the
   real sink) — it measured smaller than apply, not larger, so it isn't
   either.
3. **The dominant historical cost was neither of those — it was per-agent
   recipe re-derivation and gotcha retries.** QA's and Architect's own
   memory catalogs the individual traps hand-executing this recipe hits
   (`docker exec -i` swallowing stdin silently, load-before-vs-after
   extension-creation ordering, supabase_admin-vs-postgres ownership at the
   wrong step, pgtap needing `public` not `extensions`, the
   `--no-privileges` posture trap, database-name case-folding) — each one
   independently documented as having "cost real time on first use" or "a
   wasted retry." A scripted run of the whole recipe takes under 5 seconds
   of computer time; an agent hand-deriving ~15 discrete steps and hitting
   even one of those traps costs far more than that in retries and
   round-trips.

**All three are what a one-shot fenced command removes** —
`db-template-clone.sh` has no discrete steps left to mis-order or retry, so
gotcha cost (3) drops to zero regardless of how small (1) and (2) turned out
to be; the sub-second clone (vs. the ~4.8s full sequential build) is then a
real but secondary bonus, not the headline. See the design report for the
reasoning that ruled out a two-layer (rarely-refreshed prep base + fresh
apply per use) split: since apply (1) is the larger of the two measured
command costs, splitting would only remove the smaller one (2) and still pay
(1) on every use.

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
  (`public._template_meta`: head migration filename, sha256 of the full
  migrations tree, the running container's image id, and the build
  timestamp) before promoting the build — a failed or partial build is
  dropped, never promoted.
- `db-template-clone.sh <name>` reads that marker, recomputes the same
  values from your CURRENT tree/container, and compares all three. Any
  mismatch — editing an already-numbered migration file in place (a
  filename-only check would miss it), or a Supabase CLI / Postgres image
  upgrade that changes the auth schema with zero change to the migrations
  tree (which neither migration-tree leg can see) — refuses to clone. On a
  match, it clones via `createdb --template=pfin_tmpl` (seconds, not a full
  apply), then replays every `pg_db_role_setting` row keyed to `pfin_tmpl`'s
  own database OID onto the clone — `CREATE DATABASE ... TEMPLATE` does NOT
  copy that catalog at all (new OID, no row), which is exactly the gap QA
  measured 2026-08-19 (085) losing migration 061's `TimeZone=UTC` pin. Two
  shapes are keyed to a specific database this way — `ALTER DATABASE d SET`
  (`setrole = 0`) and `ALTER ROLE r IN DATABASE d SET` (`setrole <> 0`,
  `setdatabase = d`) — and the replay covers both generically (Sec caught an
  earlier version of this doc/script claiming the second shape was
  cluster-level and already-shared, which is false: `setdatabase` pins it to
  one database exactly like the first shape; zero such rows exist today, but
  the replay no longer assumes that stays true). A plain `ALTER ROLE r SET`
  with no `IN DATABASE` (`setdatabase = 0`) IS genuinely cluster-wide and
  correctly excluded — nothing to replay there.

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
  control: **byte-identical, 177/177 lines** — applying (not just deciding)
  the no-`--no-privileges` posture, verified.
- `has_schema_privilege('anon','pfin','USAGE')` reads `false` on both —
  the outer fence (anon holds zero grants on every pfin relation, per
  `supabase/config.toml`'s own comment) survives the clone identically.
- **The `--no-privileges` hazard itself, inverted (Sec-booked, 2026-09-02):
  demonstrated, not merely reasoned.** Built a throwaway candidate the same
  way `db-template-build.sh` does, except WITH `--no-privileges --no-owner`
  on the auth/extensions/vault dump step, and diffed its ACL census against
  the real `pfin_tmpl`: **181 GRANT/REVOKE lines on the inverted probe vs.
  266 on the real template — 85 lines of privilege posture dropped**,
  entirely inside `auth`/`extensions` (the schemas the dump step touches).
  Losses include `GRANT USAGE ON SCHEMA auth TO anon/authenticated/
  service_role` and two `REVOKE ALL ... FROM supabase_admin` statements —
  the fence itself, not just a grant. Full census + diff + provenance:
  `scripts/fixtures/README.md`. This is the applied-and-demonstrated half of
  BACKLOG §7.14's "Scratch-harness ACL parity (permissive-direction hazard)"
  booking — the byte-identical diff above shows the FIX holds; this inverted
  probe shows the FLAW it fixes is real for this specific recipe, not just
  inferred from QA's differently-shaped 2026-08-12 measurement.
- **Bound on what "parity" means here:** `pfin_tmpl` (built via the
  sequential recipe, same as any hand-built scratch DB) carries only ONE of
  the real local-stack `postgres` database's three `pg_db_role_setting`
  entries — `TimeZone=UTC` (migration-driven, `061`). The
  `app.settings.jwt_secret` / `app.settings.jwt_exp` pair is a local-stack BOOTSTRAP
  artifact the Supabase CLI applies only to the literal `postgres` database
  on `supabase start` — it is absent on every scratch DB regardless of how
  it was built, sequential apply included, not a gap this tooling
  introduces. "Parity" throughout this doc means parity with what a
  sequential migration apply itself produces, not full parity with the
  `postgres` database's own bootstrap state.

## Refresh trigger

`.husky/post-merge` calls `db-template-build.sh` automatically whenever a
local merge changes `supabase/migrations/` — best-effort, never blocks the
merge that already happened. **This is a convenience, not the correctness
boundary** — `db-template-clone.sh`'s own staleness check is what actually
prevents a stale clone, independent of whether the hook fired, fired against
the right tree, or even exists in your checkout. If you're not in the shared
main checkout, or the hook didn't run for any reason, just run
`db-template-build.sh` by hand before cloning.

## Safety guards (Sec-required, 2026-09-02 advisory)

Both scripts run a DROP DATABASE somewhere on their path — `db-template-build.sh`
drops the old `pfin_tmpl` at swap time, `db-template-clone.sh` drops
whatever's at the scratch name before cloning — and `.husky/post-merge`
calls the build script automatically, unattended, on every local merge that
touches migrations. Two structural guards, checked before either script
touches a database:

- **Host guard.** Refuses to run unless `DB_TEMPLATE_HOST` resolves to
  `127.0.0.1`/`localhost`. Set `DB_TEMPLATE_ALLOW_REMOTE=1` to override, for
  anyone who genuinely means to point this at a non-local Postgres.
- **Name guard.** `db-template-build.sh` refuses to build/swap into a
  `DB_TEMPLATE_NAME` of `postgres`/`template0`/`template1`.
  `db-template-clone.sh` refuses a scratch name equal to
  `postgres`/`template0`/`template1`/`pfin_tmpl` (dropping the template
  itself to make room for its own clone would be self-defeating as well as
  destructive).

## What this does not cover

- Local/CI throwaway tooling only — no opinion on Coolify or production.
- Role-level GUC overrides with no `IN DATABASE` clause (`ALTER ROLE r SET
  k=v`, `setdatabase = 0`) are genuinely cluster-level, already shared by
  every database including a clone — nothing to replay for those. (Overrides
  that DO carry `IN DATABASE` are per-database and ARE replayed — see "What's
  actually happening" above; an earlier version of this line conflated the
  two, which Sec caught.)
- A clone is disposable per **session**, not per query — QA's existing
  discipline
  (`.claude/agent-memory/qa/feedback_scratch_db_perf_seed_must_be_rolled_back.md`)
  still applies: don't leave ad hoc committed rows in a clone across
  unrelated verification runs; drop and re-clone instead.
- `db-template-build.sh` needs the local Supabase stack up (same container
  discovery convention as `scripts/db-snapshot.sh`) and a host `psql`/
  `createdb`/`dropdb`. It does not touch F/CTO's own local dev database —
  everything happens in `pfin_tmpl` and whatever scratch name you clone to.
