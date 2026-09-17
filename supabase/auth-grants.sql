-- ============================================================================
-- supabase/auth-grants.sql — THE PRIVILEGED HALF OF THE PRE-STEP.
-- Must be applied by a role with authority over schema `auth`
-- (`supabase_admin` on this image — NOT `postgres`, and NOT the CLI's seeder).
--
-- ⚠ WHY THIS IS A SEPARATE FILE, MEASURED RATHER THAN PREFERRED.
-- Schema `auth` is owned by `supabase_auth_admin`. The Supabase CLI seeds
-- `supabase/roles.sql` as a NON-SUPERUSER (measured in CI, run 35172826387):
--     Seeding globals from roles.sql...
--     WARNING (01007): no privileges were granted for "auth"
--     WARNING (01007): not all privileges were granted for column "id" of relation "users"
-- ⚠⚠ NOTE THE FAILURE MODE, because it defeats the obvious guard: a grant made
-- without authority does NOT raise — it emits WARNING 01007 and GRANTS NOTHING.
-- An `exception when insufficient_privilege` handler therefore never fires, and
-- the seed completes "successfully" having established nothing. The apply then
-- dies much later, at the first foreign key to `auth.users`, with an error that
-- names the schema and not the cause. THE ONLY RELIABLE CHECK IS THE OUTCOME:
-- read the privilege back. roles.sql does exactly that and points here.
--
-- No ordering or split INSIDE roles.sql can fix this — it is a property of who
-- runs it, not of what it contains.
--
-- CONSUMERS — this file is the single source for these statements:
--   · CI / local: applied as `supabase_admin` over the local stack, between the
--     stack coming up and the migrations being applied.
--   · Production: runbook §6.3's supervised pre-step, as `supabase_admin`.
-- Idempotent; safe to re-run.
-- ============================================================================

-- pfin_owner owns every pfin object and therefore declares the foreign keys to
-- auth.users. It needs only enough to do that, and nothing more.
grant usage on schema auth to pfin_owner;

-- ⚠ COLUMN-LEVEL, NOT TABLE-LEVEL. `id` is the only column the 24 FK sites and the
-- one seed read require. Table-level would hand every user row — including
-- `encrypted_password` — to a role that `PROD_DB_URL` reaches by SET ROLE.
grant references (id), select (id) on auth.users to pfin_owner;

-- Read the outcome back and FAIL LOUD if the grants did not take. Without this the
-- file can "succeed" having granted nothing (see the header).
do $verify$
begin
  if not has_schema_privilege('pfin_owner', 'auth', 'USAGE')
     or not has_column_privilege('pfin_owner', 'auth.users', 'id', 'REFERENCES') then
    raise exception using errcode = '42501',
      message = format('auth-grants.sql: the grants DID NOT TAKE as %I — pfin_owner still lacks USAGE on schema auth or REFERENCES on auth.users(id).', current_user),
      detail  = 'A grant made without authority over schema auth emits WARNING 01007 and grants nothing rather than raising, so this read-back is the only reliable check. Schema auth is owned by supabase_auth_admin.',
      hint    = 'Re-run this file as the image''s true superuser (supabase_admin). Do NOT work around it by widening pfin_owner elsewhere or by granting table-level access to auth.users.';
  end if;
  raise notice 'auth-grants.sql OK: pfin_owner holds USAGE on auth and REFERENCES on auth.users(id).';
end
$verify$;
