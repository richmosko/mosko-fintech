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

Do NOT pass `--no-privileges`: it drops the bootstrap's REVOKEs as well as its grants and
makes the harness **more permissive than production**, so denial assertions pass
vacuously. Drop the scratch DB when done, and confirm the dev DB is untouched
(`select to_regclass('pfin.<new_table>') is null`).

Related: [[set-local-outside-a-transaction-is-a-noop]] — the harness can switch role and
still prove nothing.
