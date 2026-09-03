---
name: scratch-db-full-chain-recipe
description: The working recipe for a clean-apply of the FULL migration chain from an empty database, without touching F/CTO's dev DB — four gotchas that each cost a round to find
metadata:
  type: reference
---

Verifying a new migration means applying `001..NNN` onto an **empty** database (a
migration applied on top of its own prior outcome demonstrates nothing). `supabase db
reset` is banned — it wipes F/CTO's test data and the guard denies it. The scratch DB goes
on the **same cluster** as the local stack, so the real `authenticated` / `anon` /
`service_role` roles exist (roles are cluster-level and do not travel in a dump).

Recipe, in the order that matters:

1. **Use the container's `pg_dump`, not the host's.** Homebrew ships 14.x against a
   supabase/postgres 17.x server and refuses cross-major dumps outright. `docker exec
   supabase_db_<project> pg_dump -U postgres -d postgres --schema-only --schema=auth
   --schema=extensions --schema=vault --schema=graphql --schema=net --schema=storage
   --schema=supabase_functions`.
2. **Load and create the scratch DB as `supabase_admin`, not `postgres`.** The dump does
   `ALTER SCHEMA auth OWNER TO supabase_admin`, and `postgres` cannot `SET ROLE` to it —
   the load dies on the first statement.
3. **Load the dump FIRST, then create extensions.** Pre-creating the schemas makes the
   dump's own `CREATE SCHEMA extensions` fail; creating the extensions afterward into the
   schemas the dump made works. Needed: `uuid-ossp`, `pgcrypto`, `pg_net` (in
   `extensions`), `supabase_vault` (in `vault`).
4. **`vault.decrypted_secrets` is extension-owned**, so `--schema=vault` alone does NOT
   carry it — `007` fails without step 3's `supabase_vault`.

⚠ **Step 2 is about the DUMP LOAD only. Before applying the MIGRATIONS, hand the database
to `postgres`** — `alter database <scratch> owner to postgres`, then apply every migration
`-U postgres`, and connect `pg_prove` as `postgres` too. In the real stack the `postgres`
DATABASE is owned by `postgres` and every `pfin` table is `postgres`-owned; a scratch left
owned by `supabase_admin` diverges, and the divergence is **not** a clean failure. Measured
once: the full `rls` suite came back with mass *"Bad plan. You planned N but ran M"*
truncations across a dozen files plus a `permission denied for table user_taxonomy` on an
inversion leg that was actually correct. **It looks like the code is broken and it is the
harness.** (`postgres` cannot even `create schema` in a `supabase_admin`-owned DB, so `001`
dies immediately if you try to apply as `postgres` without the ownership transfer.)

⚠ **Run the battery through `pg_prove`, never `psql`** — and the CI image is already local:
`docker run --rm --network container:supabase_db_<project> -v "$PWD/supabase/tests:/tests"
--entrypoint pg_prove public.ecr.aws/supabase/pg_prove:3.36 --ext .pg --ext .sql -r /tests
-d "postgresql://postgres:postgres@127.0.0.1:5432/<scratch>"`. The `--entrypoint` override is
required (the image's default entrypoint swallows the flags). Also `create extension pgtap`
in the scratch — the migration chain does not.

⚠⚠ **THE SCRATCH IS A FRESH *DATABASE* ON A DIRTY *CLUSTER*, AND THAT BOUNDS WHAT IT CAN
CONTROL FOR.** The same-cluster placement above is stated as a setup instruction — *roles
are cluster-level and do not travel in a dump* — and that is exactly the sentence I read
as a convenience and not as a limit. `pg_auth_members`, `pg_roles` and grantor identity
are **shared catalogs**: every scratch on the cluster inherits whatever drift the dev
cluster carries. Measured case: `054`'s membership legs came back RED on a scratch, I
reported it as falsifying a booked *"CI is unaffected (fresh cluster)"* claim, and the
truth was the opposite — `pfin_etl` holds four membership rows (two ratified, duplicated
across the `supabase_admin` and `postgres` grantors) **at cluster level**, so the scratch
reproduced the very drift it was supposed to isolate. **A scratch is a control for
schema-level and data-level claims ONLY. For anything reading roles, memberships or
grantors, the control must be a fresh CLUSTER — which is what CI builds and what you
cannot build this way.** Nearly landed the falsification in a tracked artifact.

⚠ **A pre-existing failure is a CONTROL result, not a relayed claim.** Build a second scratch
without the new migrations and re-run the failing file: identical failure set = pre-existing.
And read the failing legs BY NAME — a file can document *some* of its local failures as
expected while another leg on the same file is a live finding.

⚠ **`CREATE DATABASE … TEMPLATE <an already-migrated scratch>` is NOT a substitute for a
sequential apply, and the way it differs is silent.** `pg_db_role_setting` is a
**shared** catalog keyed by database OID — a templated copy gets a NEW oid and therefore
**no row at all**, so every per-database `ALTER DATABASE … SET` the chain installed is
missing. Measured 2026-08-19 (QA, `085`): a TEMPLATE clone lost `061`'s `TimeZone=UTC`
pin and `01_session_timezone.sql` (T2) failed with *"have: configuration file, want:
database"* — an artifact of the clone shortcut, not a gap in the tree. A sequential apply
does not hit it, because `061` runs `alter database current_database() set timezone`
against whatever database it is applied to. Confirmed on a sequential scratch:
`select setconfig from pg_db_role_setting` returns `{TimeZone=UTC}`.
**So: clone to save time only for claims that read no per-database setting; anything
touching timezone, JWT settings, or any `ALTER DATABASE … SET` needs the real chain.**
Related: [[timezone-pin-is-a-default-not-a-fence]].

Do NOT pass `--no-privileges`: it drops the bootstrap's REVOKEs as well as its grants and
makes the harness **more permissive than production**, so denial assertions pass
vacuously. Drop the scratch DB when done, and confirm the dev DB is untouched
(`select to_regclass('pfin.<new_table>') is null`).

Related: [[set-local-outside-a-transaction-is-a-noop]] — the harness can switch role and
still prove nothing.

⚠ **NAME THE SCRATCH DB IN ALL LOWERCASE.** `create database scratchF` creates
`scratchf` (Postgres folds unquoted identifiers), but psql's `-d scratchF` is
**case-sensitive** and fails with *"database scratchF does not exist"*. The
symptom is catastrophic-looking and misleading: the chain silently never applies
and **every** battery reports `(Wstat: 512 (exited 2) Tests: 0 Failed: 0)` — 79
files "failing" with zero tests run, which reads as a total regression rather
than as a connection error. Note `alter database scratchF owner to postgres`
SUCCEEDS (it is SQL, so it folds), which makes the setup look healthy.
⚠ Compounding trap measured at the same moment: `grep -c "^ERROR" || echo 0` on
the load log printed **0 errors** for a load that never connected. A guard
chained to its action reports success about a step that did not run — print the
counts unconditionally and assert the connection separately.

## The chain apply is NOT the time sink — measured

**3 seconds** for a raw `psql -f` of all 99 migration files onto an already-prepared scratch DB
(2026-09-03, local stack). A `create database <new> template <prepared>` clone of the same state:
**under a second**. So if you need many scratch DBs in one session, prepare one and CLONE it —
but note the apply itself was never expensive.

⚠ **Scope this claim precisely when you cite it.** It measures *only* the psql apply onto a DB
that already has auth/vault/extensions loaded. It EXCLUDES the local-stack reset path, container
restarts, the auth/vault dump-and-load prep, CI, and fixture construction. The loop-mechanics
ratification named full `001→0NN` rebuilds as the biggest measured time sink; my measurement does
not refute that, it says the sink is probably a different step and someone should measure which.
In my own `099` leg the real cost was **fixture authoring and verification reasoning**, not the
rebuild — plus one whole detour caused by the container crossing midnight UTC mid-fixture.
