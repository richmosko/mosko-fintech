-- ============================================================================
-- supabase/roles.sql — CLUSTER-ROLE PRE-STEP. ONE ARTIFACT, EVERY CONSUMER.
--
-- ⚠ THIS FILE IS THE SOURCE OF TRUTH FOR THE ROLE HALF OF THE ADR-072
-- AMENDMENT 5 BOOTSTRAP. The Supabase CLI sources it automatically when it
-- brings a local stack up ("Seeding globals from roles.sql…"), BEFORE it applies
-- supabase/migrations/**. The deployment runbook's §6.3 pre-step runs THIS FILE
-- by path rather than restating its SQL.
--
-- WHY IT EXISTS AT ALL — a defect, measured in CI at PR #784 / dc081d50:
-- the paired-ownership convention landed in 114 migration files and every CI lane
-- then died at the first `set role pfin_owner;` with
--     ERROR: role "pfin_owner" does not exist (SQLSTATE 22023)
-- because the convention was taught to the files and never to the harness that
-- applies them. ⚠ The fix is deliberately NOT a CI-only role stub: a stub lets the
-- runbook and CI drift, and the whole point of this design is that ownership is
-- right WHICHEVER identity applies the files. One file, both lanes, or the next
-- divergence is silent.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* HERE, and why the split is ORDERING, not tidiness:
--   · The SCHEMA-SCOPED backstop (`revoke create on schema pfin from migrator`)
--     cannot run here — schema `pfin` does not exist until migration 001 creates
--     it, which happens AFTER this file. It stays an operator step in runbook
--     §6.3, and the standing battery leg (o7) asserts the resulting property
--     rather than the statement. In CI the property holds BY CONSTRUCTION (no
--     grant is ever made), so (o7) is green there without the revoke — the revoke
--     is defence against a later explicit grant, not the source of the property.
--   · The 007/015 VAULT POST-STEP and the 117/119 supervised role-comment
--     statements are NOT here either. Those guards branch on PRIVILEGE, not on
--     lane: CI applies as a superuser, so they take the "applier holds it" branch
--     and run in-file; under `migrator` they take the verified-skip branch.
--
-- ⚠⚠ TWO DIFFERENT IDENTITIES ACT ON THIS FILE, AND CONFLATING THEM IS THE SINGLE
-- MOST EXPENSIVE MISTAKE AVAILABLE HERE. It cost three red CI matrices before it was
-- written down. State which one you mean, every time:
--
--   (A) THE SEEDING IDENTITY — whoever executes THIS FILE. The Supabase CLI sources it
--       on bring-up ("Seeding globals from roles.sql…"); the runbook's §6.3 pre-step
--       runs it as `supabase_admin`. ⚠ WHICH ROLE THE CLI USES IS NOT YET MEASURED.
--       It decides one thing only, and decisively: the `auth` grants below. Schema
--       `auth` is owned by `supabase_auth_admin`, so a NON-SUPERUSER seeder cannot
--       grant on it at all — no ordering and no split inside this file changes that.
--       If the CLI seeds as a non-superuser, those grants CANNOT live here and the CI
--       wiring needs a privileged step the CLI's own bring-up does not currently
--       provide, because it applies the migrations itself with no window in between.
--       The guarded block below fails LOUD rather than silent on exactly that case.
--
--   (B) THE MIGRATION-APPLY IDENTITY — whoever the CLI then connects as to apply
--       `supabase/migrations/**` and to write its own ledger. ⚠ **MEASURED, NOT
--       ASSUMED: it is `postgres`, and `postgres` is NOT a superuser on this image
--       (`rolsuper = f`).** The evidence is a CI failure, not an inference from
--       configuration: after the database-owner transfer below, the CLI reported
--           failed to create migration table: ERROR: permission denied for database postgres
--       which can only be the role creating the ledger, and it lacked a privilege the
--       owner transfer had just removed from it.
--       THIS FACT IS WHY TWO ROWS IN THIS FILE EXIST AT ALL — the membership granting
--       `pfin_owner` to `postgres` (without it, every swept migration dies at its own
--       opener with `permission denied to set role "pfin_owner"`) and the explicit
--       re-grant of CREATE on the database to `postgres` after the transfer. Delete
--       either and the CLI cannot apply this project's migrations.
--
-- ⚠ (A) and (B) may or may not be the same role. Do not reason from one to the other:
--    every failure in this file's history came from assuming they were.
--
-- Idempotent: safe to source repeatedly (the CLI does).
-- ============================================================================

do $roles$
begin
  -- pfin_owner — the group role that OWNS every pfin object, whichever identity
  -- applies the migrations. NO CREATEROLE, deliberately: a creator receives ADMIN
  -- OPTION (PG16+), and 055/116 then grant an app role to what they create, which
  -- would be a transitive path into service_role. Sec condition, ADR-072 Am. 5.
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'pfin_owner') then
    create role pfin_owner with nologin noinherit;
  end if;

  -- migrator — the bounded DDL-apply identity (attributes asserted by 118's own
  -- apply-time C8 block; created NOLOGIN here and switched on only at the
  -- supervised handoff, never by this file).
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'migrator') then
    create role migrator with nologin noinherit createrole;
  end if;
end
$roles$;

-- Membership, with the options stated EXPLICITLY. In PG16+ they are stored
-- per-membership and SURVIVE a later `alter role migrator inherit`, so making them
-- explicit is what stops one ALTER from making pfin_owner's whole reach ambient on
-- every migrator connection. No admin option.
grant pfin_owner to migrator with inherit false, set true;

-- ⚠ AND TO EVERY OTHER IDENTITY THAT APPLIES THE FILES — measured, because omitting
-- this is what made PR #784 RED in four CI lanes for a SECOND reason after the role
-- itself existed. On the Supabase image `postgres` is NOT a superuser
-- (`rolsuper = f`, measured), so it cannot enter `pfin_owner` without an explicit
-- membership: every swept migration dies at its opener with
--     ERROR: permission denied to set role "pfin_owner"
-- CI and local `supabase start` apply as `postgres`; production's main pass applies
-- as `migrator`; the supervised passes apply as `supabase_admin`, which needs no
-- grant because it IS the superuser. Guarded on existence so this file stays
-- portable to a cluster without that role.
-- ⚠ This is a ROLE-GRAPH change and is flagged as one rather than slipped in: it
-- makes `postgres` able to SET ROLE to the object owner. It widens nothing in
-- production — `postgres` is already the bootstrap identity that owns everything
-- before this design and holds CREATEROLE/CREATEDB — but it is Sec's to grade, not
-- Architect's to assume. INHERIT FALSE keeps it non-ambient: an explicit SET ROLE is
-- still required, which is exactly what the migration files do.
do $applier$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'postgres') then
    execute 'grant pfin_owner to postgres with inherit false, set true';
  end if;
end
$applier$;

-- Out-of-pfin reach the migration set genuinely needs, and nothing beyond it.
-- ⚠ COLUMN-LEVEL on auth.users, not table-level: `id` is the only column the FK
-- sites and the seed read need, and table-level would hand every user row —
-- encrypted_password included — to a role that PROD_DB_URL reaches by SET ROLE.
-- ⚠ ISSUED ONLY IF THE SEEDING IDENTITY HAS AUTHORITY, and it says so loudly when it
-- does not. `auth` is owned by `supabase_auth_admin`, so a NON-SUPERUSER seeder
-- (e.g. `postgres` on this image) cannot grant on it and the bare statements abort the
-- whole seed. Skipping is safe ONLY because the failure is then loud and immediate at
-- the first FK to auth.users — never silent.
do $authgrants$
begin
  execute 'grant usage on schema auth to pfin_owner';
  execute 'grant references (id), select (id) on auth.users to pfin_owner';
exception when insufficient_privilege then
  raise warning 'roles.sql: could NOT grant pfin_owner its auth reach as % — this seeding identity lacks authority over schema auth (owned by supabase_auth_admin). Every migration declaring a foreign key to auth.users WILL FAIL under the paired convention. Re-seed this file as the image''s true superuser, or run those two grants separately as one.', current_user;
end
$authgrants$;

-- The schema itself, owned by pfin_owner FROM CREATION. ⚠ Not cosmetic and not
-- redundant with `001`'s `create schema if not exists pfin`: the supervised pre-step
-- runs 117 (and 055/116/118) BEFORE the main pass, and 117 also carries
-- `create schema if not exists pfin`. Whoever wins that race OWNS the schema — measured,
-- the supervised identity did, and every later `set role pfin_owner` create then failed
-- with `permission denied for schema pfin`. Creating it here, authorized to pfin_owner,
-- makes every later `if not exists` a no-op and removes the race entirely.
do $pfinschema$
begin
  if not exists (select 1 from pg_catalog.pg_namespace where nspname = 'pfin') then
    execute 'create schema pfin authorization pfin_owner';
  end if;
end
$pfinschema$;

-- ⚠ NO VAULT GRANT OF ANY KIND, AT ANY PHASE. Sec's standing veto: migrator reaches
-- pfin_owner by SET ROLE, and a standing, CI-triggerable DDL credential must not
-- reach every provider access token. The 007/015 decrypt views are handled by their
-- own applier guards plus a supervised post-step (ADR-072 Am. 5 (iv‴)), never by a
-- grant here. Asserted by battery legs (o5)/(o6).

-- Database-scoped grants: pfin_owner creates schema pfin; migrator creates and keeps
-- owning the migration ledger schema (it is the connecting role the CLI's own INSERT
-- runs as, so the ledger must NOT move to pfin_owner).
do $dbgrants$
declare d text := current_database();
begin
  -- ⚠ ORDER AND EXECUTING ROLE ARE BOTH LOAD-BEARING. Measured twice, each time by a
  -- red CI matrix, so both facts are written down rather than left to be re-derived.
  --
  -- (1) THE FLIP FIRST. `alter database … owner to` REWRITES the owner's ACL entry:
  --     the old owner's row is dropped. A `grant create … to postgres` issued BEFORE
  --     the flip is therefore ERASED BY IT.
  -- (2) THE GRANTS AFTER IT, AND ISSUED **AS THE NEW OWNER**. This file is seeded by
  --     whichever identity the harness runs as — and locally/in CI that is `postgres`,
  --     which is NOT a superuser on this image. Once it hands ownership to pfin_owner
  --     it no longer holds grant authority on this database, so a bare
  --     `grant create on database … to postgres` SILENTLY FAILS TO TAKE, leaving the
  --     CLI unable to create its own ledger:
  --         failed to create migration table: ERROR: permission denied for database postgres
  --     Entering pfin_owner first makes the grants work for EVERY seeding identity —
  --     `postgres` reaches it by the membership granted above, and `supabase_admin`
  --     reaches it as superuser. Identity-agnostic by construction, which is the whole
  --     property this file exists to provide.
  --
  -- The flip itself is PRODUCTION BEHAVIOUR, not a harness concession: 061's
  -- `alter database … set` needs DATABASE OWNERSHIP and runs as pfin_owner under the
  -- paired convention. It is a net REDUCTION in migrator's standing reach — migrator
  -- loses `alter database … set` and keeps only CONNECT plus create-on-database.
  execute format('alter database %I owner to pfin_owner', d);

  set local role pfin_owner;
  execute format('grant create on database %I to migrator', d);
  -- ⚠ HARNESS-RELEVANT, and named as such: `postgres` is the identity the Supabase CLI
  -- applies as locally and in CI. In production the appliers are `migrator` (main pass)
  -- and `supabase_admin` (supervised), neither of which needs this row. It is restored
  -- EXPLICITLY rather than by declining the flip, because the flip is required and an
  -- explicit grant is auditable where implicit owner privilege is not.
  execute format('grant create on database %I to postgres', d);
  reset role;
end
$dbgrants$;
