-- ============================================================================
-- 061_pin_database_timezone_utc.sql — pin the database TimeZone to UTC.
--
-- Numbering: 061 follows 060, which is the comment this makes true. 060 states
--   that the app derives p_as_of as UTC in the Node process while
--   closed_at::date evaluates in the POSTGRES SESSION TimeZone, and that the two
--   agree only if the database is UTC. Until this file, that was a DECLARED
--   dependency with nothing declaring it.
--
-- ----------------------------------------------------------------------------
-- WHY A MIGRATION AND NOT THE PROVISIONING LAYER — the layer question, ruled.
--
--   PRECEDENT SETTLES IT, not preference: `055_pfin_etl_role.sql` already ships
--   a CLUSTER-LEVEL object — a LOGIN role — through this channel, F/CTO-ratified
--   at ADR-041. A database-scoped SET is strictly less invasive than creating a
--   cluster role. The channel has already been ruled appropriate for exactly
--   this class, so putting it elsewhere would be the inconsistency.
--
--   AND THE PROPERTY THAT MAKES IT WORTH IT (devops-tz's argument, adopted):
--   because CI applies the SAME migration production runs, >> a green CI becomes
--   evidence about PRODUCTION'S MECHANISM rather than about CI's own ambient
--   state. << A postgresql.conf pin is the unversioned layer we are already
--   implicitly trusting; a runbook step is a human check nobody verifies; and
--   either leaves CI verifying something production does not run.
--
--   It also re-applies on every `supabase db reset`, so a developer cannot drift
--   out of the pinned state by rebuilding.
--
--   DEPENDENCY, NAMED: ALTER DATABASE requires OWNERSHIP of the database, not
--   superuser. Verified on the stack as it actually ships — `postgres` has
--   rolsuper = f and IS datdba, and ownership suffices. If migrations are ever
--   run as a role that does not own the database, this file fails LOUDLY, which
--   is the correct direction.
--
--   MEASURED, and it is why this is safe to run against a provisioned database:
--   ALTER DATABASE ... SET is ADDITIVE. The local cluster already carries
--   app.settings.jwt_secret and app.settings.jwt_exp in pg_db_role_setting;
--   applying this appends TimeZone=UTC and leaves both intact. It does not
--   replace the array.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT THIS PIN DOES **NOT** CLOSE. It is NECESSARY AND NOT SUFFICIENT, and
--   the gap is not theoretical — it was measured on this stack, with the pin
--   ACTIVE, in a new session:
--
--     pin active, no PGTZ          -> TimeZone = UTC          source = database
--     pin active, PGTZ=Asia/Tokyo  -> TimeZone = Asia/Tokyo   source = client
--
--   >> `PGTZ` IN A CONNECTING CLIENT'S ENVIRONMENT DEFEATS THIS PIN OUTRIGHT. <<
--   libpq sends it as a startup parameter, so it resolves at `client`, which
--   outranks `database`. Every libpq-backed client — `psycopg` in workers/etl,
--   psql, anything else — can move ITS OWN session zone while the database
--   still reads UTC to anyone inspecting it. THAT IS THE DANGEROUS SHAPE: a
--   half-pinned deployment that INSPECTS CLEAN.
--
--   `TZ` alone is a NO-OP on the database session (measured: still UTC, still
--   source = configuration file). Recorded because it is the obvious first
--   instinct and it is wrong in the reassuring direction — someone sets TZ,
--   sees no change, and concludes the environment cannot affect the session.
--
--   ALSO NOT CLOSED: `ALTER ROLE ... SET timezone` outranks the database-level
--   setting, and this is a DEMONSTRATED vector rather than a theoretical one:
--   one was live on the LOGIN role `authenticator` on 2026-08-04 — found by QA,
--   cleared 2026-08-05 — while a `postgres`-session read-back showed a clean
--   UTC | database throughout, and the suite ran green. NOT `authenticated`:
--   per-role settings apply at LOGIN and do not survive `SET ROLE`, so checking
--   that role finds nothing and proves nothing.
--   The runbook §4.1 catalog sweep is what checks this, not this comment.
--
--   SO THE SUFFICIENCY CONDITION IS: this pin, AND no client supplying PGTZ,
--   AND no role-level override. Only the first is enforced here. The other two
--   are held by the runbook §4.1 / §10 TZ-1 deploy gate and the `.env.example`
--   PGTZ prohibitions (devops-tz), and by QA's read-back assertion.
--   Stated per the standing rule, which this file is the second consecutive
--   instance of: A FENCE MUST NAME WHERE ITS SUFFICIENCY COMES FROM. The clause
--   060 corrects got that wrong; this one says it out loud rather than implying
--   the pin is the whole answer.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   Sets `timezone = 'UTC'` on the CURRENT database. Idempotent (re-running
--   sets the same value). No schema change, no data change, no grants.
--   ⚠ TAKES EFFECT FOR NEW SESSIONS ONLY — the session running this migration
--     keeps its existing zone. The read-back below therefore proves the setting
--     was RECORDED, never that it is EFFECTIVE; those are different claims and
--     conflating them would reproduce 060's defect one file later. Effective
--     verification requires a NEW session and is QA's read-back assertion.
-- ============================================================================

do $$
begin
  -- format/%I + current_database(): ALTER DATABASE needs a literal name, and the
  -- database is `postgres` locally but must not be assumed identical on the
  -- greenfield stack. Never hardcode the name here.
  execute format('alter database %I set timezone = %L', current_database(), 'UTC');
end
$$;

-- FAIL-LOUD READ-BACK (catalog, not behaviour — see the CONTRACT caveat).
-- A guard that never fires has never been shown to fire, so this asserts the
-- catalog actually carries the setting rather than trusting the statement above
-- to have done something.
do $$
declare
  v_ok boolean;
begin
  select 'TimeZone=UTC' = any(s.setconfig)
    into v_ok
    from pg_db_role_setting s
    join pg_database d on d.oid = s.setdatabase
   where d.datname = current_database()
     and s.setrole = 0;

  if not coalesce(v_ok, false) then
    raise exception
      'database TimeZone pin did NOT land: pg_db_role_setting for % carries no TimeZone=UTC entry. The ALTER DATABASE above either failed silently or was applied to a different database than current_database() resolved to.',
      current_database();
  end if;
end
$$;
