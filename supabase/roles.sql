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
grant usage on schema auth to pfin_owner;
grant references (id), select (id) on auth.users to pfin_owner;

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
  -- ⚠ ORDER IS LOAD-BEARING: THE OWNER FLIP FIRST, EVERY GRANT AFTER IT.
  -- Measured. `alter database … owner to` REWRITES the owner's ACL entry: the old
  -- owner's row is dropped and the new owner gets CTc. A `grant create … to postgres`
  -- issued BEFORE the flip is therefore ERASED BY IT, and the next thing the CLI does
  -- is create the migration-ledger schema as postgres:
  --     failed to create migration table: ERROR: permission denied for database postgres
  -- That failure looks like a missing grant and is actually a grant that was made and
  -- then silently revoked by a later statement in the same block.
  --
  -- 061's `alter database … set` needs DATABASE OWNERSHIP, and under the paired
  -- convention it runs as pfin_owner — so ownership sits with pfin_owner, not with the
  -- applying identity. This is a net REDUCTION in migrator's standing reach: it loses
  -- `alter database … set` and keeps only CONNECT plus create-on-database.
  execute format('alter database %I owner to pfin_owner', d);

  -- Now the grants, on the post-flip ACL.
  --   · migrator creates and keeps OWNING the migration ledger schema — it is the
  --     connecting role the CLI's own INSERT runs as, so the ledger must not move to
  --     pfin_owner.
  --   · postgres must be restored EXPLICITLY: the flip above took its implicit owner
  --     privilege, and CI and local `supabase start` apply as postgres. Explicit is
  --     auditable; implicit owner privilege is not.
  execute format('grant create on database %I to migrator', d);
  execute format('grant create on database %I to postgres', d);
end
$dbgrants$;
