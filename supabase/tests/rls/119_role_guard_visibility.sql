-- =====================================================================
-- 119_role_guard_visibility.sql — battery for the GUARD-UNVERIFIED branch
--   added to the creation guards of migrations 055 / 116 / 118.
--   ADR-072 Decision A §A6 (Sec, 2026-09-16). Sec-joint-review-mandatory.
-- =====================================================================
-- ⚠ WHAT THIS FILE ASSERTS, AND WHAT IT DELIBERATELY DOES NOT — read this
--   before adding a leg, because the obvious missing leg is a trap.
--
--   It asserts the PREDICATE THAT FORCES THE BRANCH, not the branch's message.
--   pgTAP cannot capture a `RAISE WARNING`: a warning is a client-directed
--   message, not a value and not an exception, so there is nothing for `ok()`,
--   `is()` or `throws_ok()` to read. ⚠ A leg that re-implemented the guard's own
--   `select … from pg_authid … exception when insufficient_privilege` logic and
--   asserted the result would be a MOCK RESTATING THE CODE — it would pass
--   whether or not the migration carries the branch, which is the definition of
--   a vacuous green. So the legs below assert the two facts the branch exists
--   BECAUSE of, and each one goes RED exactly when the branch stops being needed
--   or stops being correct.
--
--   The message text is proven instead by the PR's strike measurement (the guard
--   block executed as a non-superuser emits the sentinel; executed as the true
--   superuser it is silent). That is evidence in the PR, not a standing check —
--   stated plainly so nobody reads these legs as covering more than they do.
--
--   ⚠ SPECIFICATION FOR ANY FUTURE SENTINEL WATCHER — the naive form is VACUOUS,
--   and this is Sec's condition on PR #781, recorded where the next author will
--   look. The sentinel must be counted over COMMENT-STRIPPED source, expecting
--   EXACTLY ONE occurrence per file:
--       grep -v '^[[:space:]]*--' <file> | grep -c '<sentinel>'   -> must equal 1
--   A raw `grep -c` counted TWO per file when this fix was written — the `raise`
--   and a comment describing it — so a watcher asserting `>= 1` would have stayed
--   GREEN with the `raise` deleted. The migrations were then reworded to DESCRIBE
--   the token rather than quote it, so raw and stripped counts now agree at 1;
--   ⚠ use the stripped form ANYWAY, because that agreement is a property of
--   today's prose and the next person to explain the branch will break it.
--
--   Decision 3 family unchanged (+0); §10 catalogued ledger unchanged; no RLS
--   surface, no policy, no function.
--   FAIL-CLOSED: every leg reads a catalog function that returns a boolean for a
--   named role; a missing role makes the read NULL and `ok(NULL)` is RED.
-- =====================================================================

begin;

select plan(8);

-- ---------------------------------------------------------------------
-- (g0) DEPENDENCY GUARD.
-- ---------------------------------------------------------------------
select ok(
  (select count(*) = 3 from pg_roles where rolname in ('pfin_etl','pfin_provider_sync','migrator')),
  '(g0) DEPENDENCY: migrations 055, 116 and 118 are applied and all three cluster roles exist. If this is the only RED, apply them rather than editing (g1)-(g6)'
);

-- ---------------------------------------------------------------------
-- (g1)-(g3) THE FORCING PREDICATE, per role: pg_authid is NOT readable by
--   the role, so the LOGIN-with-no-password check cannot evaluate when that
--   role is the applier — which is exactly why the GUARD-UNVERIFIED branch
--   exists.
--   ⚠ THESE LEGS MEASURE EFFECTIVE REACH, AND THAT IS NOT THE SAME AS
--   WATCHING THE VETOED GRANT. An earlier revision of this file claimed they
--   were also the watcher for Sec's VETO on granting the applier
--   `pg_read_all_data`. THE STRIKE FALSIFIED THAT: all three roles are
--   NOINHERIT, so `grant pg_read_all_data to migrator` confers nothing through
--   inheritance, `has_table_privilege` keeps returning false, and these legs
--   stayed GREEN through the injected violation. The vetoed grant is LATENT
--   under NOINHERIT — it confers nothing until an explicit `SET ROLE`, and it
--   is then fully available. **(g7) is the watcher**; these three are the
--   forcing predicate only. Recorded rather than quietly fixed, because a leg
--   that is believed to watch something it does not is worse than no leg.
-- ---------------------------------------------------------------------
select ok(
  not has_table_privilege('pfin_etl', 'pg_catalog.pg_authid', 'SELECT'),
  '(g1) `pfin_etl` cannot read pg_catalog.pg_authid, so a 055 apply under that identity cannot evaluate the LOGIN-with-no-password fence and must announce the gap. RED means this role acquired an EFFECTIVE pg_authid read. See (g7) for the membership watcher — under NOINHERIT a granted role is latent and this leg would NOT see it'
);
select ok(
  not has_table_privilege('pfin_provider_sync', 'pg_catalog.pg_authid', 'SELECT'),
  '(g2) `pfin_provider_sync` cannot read pg_catalog.pg_authid — same forcing predicate for 116. Membership watcher is (g7)'
);
select ok(
  not has_table_privilege('migrator', 'pg_catalog.pg_authid', 'SELECT'),
  '(g3) `migrator` cannot read pg_catalog.pg_authid — same forcing predicate for 118, and the one that matters most: migrator is the UNSUPERVISED applier, so this is the lane where a silently-unreachable fence would never be seen by anyone'
);

-- ---------------------------------------------------------------------
-- (g4) THE SUBSTITUTE ROUTE IS UNUSABLE — the second reason the branch
--   exists rather than a "fix". pg_roles.rolpassword is the CONSTANT
--   '********' for every role, including one carrying NO password, so a
--   guard rewritten against pg_roles would report "has a password" for a
--   passwordless role: a metric that reads like a check.
--   ⚠ WATCHER: if a future PostgreSQL ever made pg_roles.rolpassword
--   informative, this leg goes RED and the guard SHOULD then be rewritten
--   to use it. RED here is an invitation to improve the guard, not a defect.
-- ---------------------------------------------------------------------
select is(
  (select rolpassword from pg_catalog.pg_roles where rolname = 'pfin_etl'),
  '********',
  '(g4) pg_roles.rolpassword is the literal ''********'' even for `pfin_etl`, which ships with NO password — so pg_roles is NOT a usable substitute for the refused pg_authid read, and a guard rewritten against it would pass a passwordless LOGIN role. RED means this PostgreSQL made the column informative: rewrite the 055/116/118 guards to use it and delete their GUARD-UNVERIFIED branch'
);

-- ---------------------------------------------------------------------
-- (g5) The C8 assertion block's own inputs stay world-readable — the
--   contrast that makes (g1)-(g3) a statement about pg_authid rather than
--   about catalog access generally. 118's C8 fence is designed to work for
--   a non-superuser applier and must keep doing so.
-- ---------------------------------------------------------------------
select ok(
  has_table_privilege('migrator', 'pg_catalog.pg_roles', 'SELECT')
  and has_table_privilege('migrator', 'pg_catalog.pg_auth_members', 'SELECT'),
  '(g5) `migrator` CAN read pg_roles and pg_auth_members — so 118''s C8 attribute assertion (CREATEROLE true / superuser, bypassrls, createdb false / no app-role membership) still hard-fails correctly under a non-superuser applier. This is the contrast that makes (g1)-(g3) a fact about pg_authid specifically, not about catalog visibility in general. RED means the C8 fence has ALSO gone blind, which is a larger failure than the one this file was written for'
);

-- ---------------------------------------------------------------------
-- (g6) The three roles carry no per-role session default — re-asserted
--   here because the guard fix touches all three files and (r12)-class
--   drift on any of them would be invisible to 116's own battery, which
--   only covers pfin_provider_sync.
-- ---------------------------------------------------------------------
select ok(
  not exists (
    select 1 from pg_catalog.pg_roles r
     where r.rolname in ('pfin_etl','pfin_provider_sync','migrator')
       and r.rolconfig is not null
  )
  and not exists (
    select 1 from pg_catalog.pg_db_role_setting drs
     join pg_catalog.pg_roles r on r.oid = drs.setrole
     where r.rolname in ('pfin_etl','pfin_provider_sync','migrator')
  ),
  '(g6) none of the three roles carries a per-role session default (pg_roles.rolconfig IS NULL and zero rows in pg_db_role_setting, global or IN DATABASE). 116 leg (r12) ratifies that such a default is a POSTURE BYPASS, not a convenience — and this file extends that assertion to the two roles (r12) does not cover. ON RED: REVOKE it (ALTER ROLE ... RESET ALL), never loosen this leg'
);

-- ---------------------------------------------------------------------
-- (g7) THE SEC-VETO WATCHER — and it exists because (g1)-(g3) provably do
--   NOT do this job. Sec ruled granting the applier `pg_authid` or
--   `pg_read_all_data` a VETOED remediation: it hands every SCRAM verifier
--   in the cluster to a standing credential. Under NOINHERIT that grant is
--   LATENT — it confers nothing until an explicit SET ROLE, so a privilege
--   check cannot see it and a membership check can. `pg_has_role(...,
--   'MEMBER')` is transitive, so an indirect grant is caught too.
-- ---------------------------------------------------------------------
select ok(
  not exists (
    select 1
      from unnest(array['pfin_etl','pfin_provider_sync','migrator']) as u(rolname)
      cross join unnest(array['pg_read_all_data','pg_monitor','pg_read_all_settings']) as g(grp)
     where exists (select 1 from pg_catalog.pg_roles where rolname = g.grp)
       and pg_catalog.pg_has_role(u.rolname, g.grp, 'MEMBER')
  ),
  '(g7) SEC-VETO WATCHER: none of the three roles is a MEMBER of pg_read_all_data, pg_monitor or pg_read_all_settings. Sec VETOED closing the guard gap that way — those roles expose every SCRAM verifier in the cluster to a standing credential. ⚠ Asserted by MEMBERSHIP, not by has_table_privilege: all three roles are NOINHERIT, so the grant confers nothing through inheritance and a privilege check stays GREEN through the violation (measured — it is why (g1)-(g3) alone were not enough). The grant is LATENT, not harmless: one SET ROLE makes it live. ON RED: REVOKE the membership; do NOT loosen this leg, and do NOT close the guard gap this way'
);

select * from finish();

rollback;
