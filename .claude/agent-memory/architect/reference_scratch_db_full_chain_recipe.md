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

Do NOT pass `--no-privileges`: it drops the bootstrap's REVOKEs as well as its grants and
makes the harness **more permissive than production**, so denial assertions pass
vacuously. Drop the scratch DB when done, and confirm the dev DB is untouched
(`select to_regclass('pfin.<new_table>') is null`).

Related: [[set-local-outside-a-transaction-is-a-noop]] — the harness can switch role and
still prove nothing.
