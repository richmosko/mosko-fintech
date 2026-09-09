-- =====================================================================
-- 116_pfin_provider_sync_role.sql — credential-model battery for the dedicated
--   `pfin_provider_sync` NOINHERIT login role created by
--   supabase/migrations/116_pfin_provider_sync_role.sql.
--   BACKLOG.md §7.6 item S5 (PHASE-7 DEPLOY GATE). ADR-019 Condition C2 as
--   renamed and promoted by ADR-041. Sec-joint-review-mandatory surface.
-- =====================================================================
-- WHAT THIS FILE IS, AND WHAT IT DELIBERATELY IS NOT
--   It is a CLUSTER-ROLE battery, not an RLS battery: 116 creates no table, no
--   policy and no function, so there is no two-tenant read/write surface to
--   fence here and a two-tenant fixture would be decoration. It lives under
--   tests/rls/ anyway because that directory is where migration-number-paired
--   batteries are discoverable, and `pg_prove -r supabase/tests` collects it
--   either way. The RLS surfaces this role reaches are already covered by their
--   own migration-paired batteries; nothing in 116 changes any of them.
--
--   It asserts exactly one thing in many directions: that the login identity
--   provider-sync will use holds NO privilege of its own, can only reach
--   privilege through an explicit SET ROLE to exactly two memberships, and ships
--   unable to authenticate.
--
-- ⚠ WHAT NO ASSERTION IN THIS FILE CAN SEE — read this before concluding the
--   deploy gate is discharged. The gate is discharged by the provider-sync
--   container's `PFIN_DB_USER` environment variable reading
--   `pfin_provider_sync` instead of `authenticator`. That is an env fact, not a
--   catalog fact. Every leg here can be GREEN on a cluster where provider-sync
--   is still logging in as `authenticator` and the PostgREST rotation coupling
--   is still live. `rolcanlogin = t` on this role would prove only that an
--   operator ran the deploy step. The two half-applied states are asymmetric:
--   env-switched-but-role-absent fails LOUDLY at connect; role-present-but-env-
--   unswitched is SILENT and looks finished from here. The silent one is the
--   dangerous one, and it is the deploy pass's job, not this file's.
--
-- DEPENDENCY: migration 116 must be applied to the stack under test. On the CI
--   reset stack all migrations are applied before the battery runs, so ordering
--   is a non-issue there. A local run against a scratch DB must include 116.
--   RED-until-116-applied is EXPECTED, and (r0) below turns that into ONE
--   legible line instead of a hard abort — `has_table_privilege('pfin_provider_
--   sync', …)` RAISES on a non-existent role, which would kill the file and
--   leave the rest of the plan UNRUN, reading in CI as a broken test rather than
--   as a missing dependency. Every leg below that touches the role is
--   additionally written FAIL-CLOSED so a missing role can never pass vacuously.
--
-- WHY EACH LEG EXISTS — what goes undetected if it is removed:
--   (r0) -> a missing dependency masquerading as a broken file.
--   (r1) -> the whole least-privilege model collapsing silently: with rolinherit
--           flipped, the login session ambiently holds every granted role's
--           privileges and the SET ROLE discipline evaporates with nothing else
--           going RED.
--   (r2) -> the login identity acquiring superuser / BYPASSRLS / CREATEROLE —
--           any of which puts the owner-only trigger bypasses (ALTER TABLE …
--           DISABLE TRIGGER, session_replication_role) back within reach of the
--           very process the schema's matched-tenant and immutability fences
--           exist to constrain.
--   (r3) -> a migration shipping a login-capable role: on a `trust` pg_hba line
--           (the local stack trusts 127.0.0.1/32, ::1/128 and local) rolcanlogin
--           is the ONLY thing between an inert role and a directly usable one,
--           because `trust` never consults a password at all.
--   (r4) -> a credential committed to the repository — including a dormant one
--           that would go live the instant someone flipped LOGIN.
--           (r3) and (r4) are SPLIT rather than combined into one
--           "cannot authenticate as shipped" so a RED self-identifies which half
--           fired, and so a legitimate change to one does not produce a
--           misleading RED naming the other.
--   (r5) -> a THIRD membership creeping onto the role — most consequentially
--           `anon`, which the shared `authenticator` carries and which this role
--           deliberately drops. Also RED on the SAME membership granted twice
--           under two grantors.
--   (r6) -> INHERIT silently turned ON for the privileged membership behind a
--           `rolinherit = false` that still reads correctly. On PG 16+
--           inheritance is PER-MEMBERSHIP: `GRANT service_role TO r WITH INHERIT
--           TRUE` confers privileges implicitly while rolinherit stays false.
--           (r1) governs FUTURE memberships; this governs the existing one.
--   (r7) -> the same, for the tenant read path: an un-impersonated statement
--           silently running under a tenant identity.
--   (r8) -> SET silently turned OFF: `GRANT … WITH SET FALSE` flips set_option
--           to f while MEMBER stays TRUE, so (r5)/(r6)/(r7) all stay green while
--           every `set local role` in the worker fails 42501 on every run. This
--           is the exact mirror of (r6)/(r7) and neither catches the other.
--   (r9) -> a direct grant to the login role on the surfaces the worker actually
--           touches, which would quietly bypass the SET ROLE discipline on
--           precisely the objects that matter.
--   (r10) -> the general case (r9) cannot reach: ANY privilege granted to this
--           role anywhere in the cluster, on any relation, column, schema,
--           function, type, database, tablespace or default-ACL, or this role
--           becoming the owner of anything. 116 grants object privileges to
--           NOTHING, so the correct assertion is an EMPTY inventory, and this
--           leg REDs on the first grant of any kind — including one added by a
--           future migration that never touches this file.
--   (r11) -> the role's `comment on role` going missing. That comment is where
--           the deploy-time two-step, the prohibition on the single-statement
--           password form, and the PFIN_DB_USER caveat reach an operator who is
--           reading the catalog with no repository in front of them.
--
-- LEG INDEPENDENCE: (r5) owns "which memberships exist"; (r8) is SCOPED to the
--   two required edges so that a third membership REDs (r5) alone. (r9) names
--   representative objects for a legible diagnostic; (r10) is the unscoped
--   catch-all. A grant on a named object REDs both — accepted deliberately: the
--   pair is diagnostic-plus-completeness, and losing (r9) would leave only an
--   inventory string to read.
--
-- ⚠ `string_agg` in (r5) and (r8) is NOT de-duplicated, on purpose. `distinct`
--   is FORBIDDEN in these legs: a duplicate-grantor drift (the SAME membership
--   recorded twice under two grantors) is a real defect class measured on this
--   project at 2026-08-17 against the sibling `pfin_etl` role, and `distinct`
--   would make these assertions permanently tolerate it. Fix a real duplicate
--   with `REVOKE <role> FROM pfin_provider_sync GRANTED BY <grantor>` per
--   grantor — never by loosening the query.
--
-- §10 / DECISION 3 (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is carried into this file):
--   116 introduces ZERO catalogued §10 instances and this battery adds none; no
--   layer attribution moves. LAYER-ATTRIBUTION NOTE: `pfin_provider_sync` is a
--   DB-layer cluster role reached over a DIRECT Postgres connection — it is not
--   the code-layer Supabase service-role KEY allowlist surface, and provider-sync
--   stays off that allowlist exactly as before. Decision 3 family unchanged (+0):
--   116 creates no table, column or FK-shaped reference of any kind.
-- =====================================================================

begin;

select plan(12);

-- ---------------------------------------------------------------------
-- (r0) DEPENDENCY GUARD — must come first and must be LEGIBLE.
-- ---------------------------------------------------------------------
select ok(
  (select count(*) = 1 from pg_roles where rolname = 'pfin_provider_sync'),
  '(r0) DEPENDENCY: migration 116 is applied and the role `pfin_provider_sync` exists. If this is the only RED in the file, 116 has not been applied to this stack — apply it rather than editing (r1)-(r11), every one of which reads this role'
);

-- ---------------------------------------------------------------------
-- (r1) NOINHERIT — the flag the entire least-privilege model rests on.
-- ---------------------------------------------------------------------
select ok(
  (select not rolinherit from pg_roles where rolname = 'pfin_provider_sync'),
  '(r1) NOINHERIT: `pfin_provider_sync` has rolinherit = f — it is a member of service_role and authenticated but holds NONE of their privileges ambiently, so any privileged or tenant-scoped statement requires an explicit SET ROLE and a FORGOTTEN one fails 42501 loudly instead of silently running elevated. RED if rolinherit ever flipped, which collapses the model every other leg here rests on'
);

-- ---------------------------------------------------------------------
-- (r2) NOT superuser / NOT BYPASSRLS / NOT CREATEROLE / NOT CREATEDB /
--      NOT REPLICATION — what keeps the trigger-realized fences un-bypassable
--      by the writer, and keeps the role from re-granting itself reach.
-- ---------------------------------------------------------------------
select ok(
  (select not rolsuper and not rolbypassrls and not rolcreaterole
          and not rolcreatedb and not rolreplication
     from pg_roles where rolname = 'pfin_provider_sync'),
  '(r2) un-bypassable-by-the-writer: `pfin_provider_sync` is NOT superuser, NOT BYPASSRLS, NOT CREATEROLE, NOT CREATEDB and NOT REPLICATION — so it can reach NEITHER owner-only trigger bypass (ALTER TABLE … DISABLE TRIGGER needs ownership, session_replication_role needs superuser) and cannot widen its own reach. This is what makes the matched-tenant and immutability fences its own writes pass through un-switchable by the process they constrain'
);

-- ---------------------------------------------------------------------
-- (r3) FAIL-CLOSED AT MIGRATION TIME, half one: NOLOGIN as shipped.
--      RED ON ANY STACK, FOR ANY REASON — not an environment difference.
-- ---------------------------------------------------------------------
select ok(
  (select not rolcanlogin from pg_roles where rolname = 'pfin_provider_sync'),
  '(r3) fail-closed provisioning, NEVER-EXCUSED half: as shipped by migration 116, `pfin_provider_sync` is NOLOGIN (rolcanlogin = false) — it cannot authenticate as shipped and is flipped to a working credential only at deploy, by an operator, from the Coolify secret. Most load-bearing locally: the local stack''s pg_hba grants `trust` on 127.0.0.1/32, which never consults a password at all, so NOLOGIN is the ONLY thing standing between an inert role and a directly usable one here'
);

-- ---------------------------------------------------------------------
-- (r4) FAIL-CLOSED AT MIGRATION TIME, half two: no password as shipped.
--      Reads pg_authid, not pg_roles: pg_roles.rolpassword is the literal
--      '********' for every role and is a metric that reads like a check.
--      FAIL-CLOSED: an unreadable pg_authid yields no row -> NULL -> RED.
-- ---------------------------------------------------------------------
select ok(
  (select rolpassword is null from pg_authid where rolname = 'pfin_provider_sync'),
  '(r4) fail-closed provisioning, second half: as shipped by migration 116, `pfin_provider_sync` carries NO PASSWORD (pg_authid.rolpassword is null) — no credential committed to the repository, not even a dormant one that would go live the instant someone flipped LOGIN. Read from pg_authid deliberately: pg_roles.rolpassword is the constant ''********'' for every role, so a check against it is always true and proves nothing. RED (not vacuous) if pg_authid is unreadable to the running role'
);

-- ---------------------------------------------------------------------
-- (r5) EXACTLY the two ratified memberships — no third role, `anon` in
--      particular, and no duplicate grantor. NOT de-duplicated: see the
--      header note. FAIL-CLOSED: a missing role aggregates to NULL, which
--      fails the is().
-- ---------------------------------------------------------------------
select is(
  (select string_agg(g.rolname, ',' order by g.rolname)
     from pg_auth_members m
     join pg_roles g on g.oid = m.roleid
     join pg_roles u on u.oid = m.member
    where u.rolname = 'pfin_provider_sync'),
  'authenticated,service_role',
  '(r5) membership set: `pfin_provider_sync` holds EXACTLY the two ratified memberships — authenticated (the INVOKER / caller-RLS path) and service_role (the privileged path). Membership in `anon` is deliberately WITHHELD: the shared `authenticator` this role replaces carries it, and the worker never SET ROLEs to it, so anon appearing here is a real widening. RED on ANY third membership, and RED on the SAME membership granted twice under two grantors (`distinct` is forbidden in this query — it would make the leg permanently tolerate that drift; fix a real duplicate with REVOKE … GRANTED BY <grantor>)'
);

-- ---------------------------------------------------------------------
-- (r6)/(r7) NOINHERIT as an AUTHORIZATION OUTCOME, per membership.
--      MEMBER-yes / USAGE-no is the posture stated in the terms that
--      decide it. FAIL-CLOSED both directions: a missing role yields NULL,
--      and the coalesce defaults are chosen so NULL is always RED.
-- ---------------------------------------------------------------------
select ok(
  coalesce((select pg_has_role('pfin_provider_sync', 'service_role', 'MEMBER')
              from pg_roles where rolname = 'pfin_provider_sync'), false)
  and not coalesce((select pg_has_role('pfin_provider_sync', 'service_role', 'USAGE')
              from pg_roles where rolname = 'pfin_provider_sync'), true),
  '(r6) NOINHERIT as an authorization outcome, privileged path: `pfin_provider_sync` is a MEMBER of service_role (it MAY SET ROLE to it) but holds NO USAGE (it does NOT hold its privileges without doing so). RED if USAGE ever became true — which is what `GRANT service_role TO pfin_provider_sync WITH INHERIT TRUE` produces on PG 16+ WITHOUT changing rolinherit, so (r1) would stay green while the worker ran privileged by default'
);
select ok(
  coalesce((select pg_has_role('pfin_provider_sync', 'authenticated', 'MEMBER')
              from pg_roles where rolname = 'pfin_provider_sync'), false)
  and not coalesce((select pg_has_role('pfin_provider_sync', 'authenticated', 'USAGE')
              from pg_roles where rolname = 'pfin_provider_sync'), true),
  '(r7) NOINHERIT as an authorization outcome, tenant read path: `pfin_provider_sync` is a MEMBER of authenticated but holds NO USAGE — the worker cannot read or write tenant data without an explicit SET ROLE plus the synthetic request.jwt.claims binding, so an un-impersonated statement cannot silently run under a tenant identity'
);

-- ---------------------------------------------------------------------
-- (r8) SET ROLE MUST ACTUALLY WORK — the per-membership SET option, the
--      third independent PG16+ setting and the exact mirror of (r6)/(r7).
--      SCOPED to the two required edges so a third membership REDs (r5)
--      alone. NOT de-duplicated, same reason as (r5).
-- ---------------------------------------------------------------------
select is(
  (select string_agg(g.rolname || '=' || m.set_option::text, ',' order by g.rolname)
     from pg_auth_members m
     join pg_roles g on g.oid = m.roleid
     join pg_roles u on u.oid = m.member
    where u.rolname = 'pfin_provider_sync'
      and g.rolname in ('service_role', 'authenticated')),
  'authenticated=true,service_role=true',
  '(r8) SET ROLE is actually permitted: BOTH memberships carry set_option = true, so the worker can `set local role authenticated` (INVOKER ingest) and `set local role service_role` (privileged writes). 116 omits any SET clause so the SET-TRUE default applies — asserted rather than assumed, because a re-grant WITH SET FALSE flips set_option to f while MEMBER stays TRUE, leaving (r5)/(r6)/(r7) ALL green while every run failed 42501 at SET ROLE. Also RED on a duplicate grantor'
);

-- ---------------------------------------------------------------------
-- (r9) NO AMBIENT REACH on the surfaces the worker actually touches —
--      the named, legible half. FAIL-CLOSED: has_*_privilege RAISES on a
--      non-existent role, so each call is guarded through a pg_roles
--      lookup and the coalesce defaults to TRUE (= "has it") so a missing
--      role goes RED rather than passing vacuously. Defaulting to FALSE
--      here would be the silent-pass bug this leg exists to catch.
-- ---------------------------------------------------------------------
select ok(
  not coalesce((select has_schema_privilege('pfin_provider_sync', 'pfin', 'USAGE')
                  from pg_roles where rolname = 'pfin_provider_sync'), true)
  and not coalesce((select has_table_privilege('pfin_provider_sync', 'pfin.linked_source', 'SELECT')
                  from pg_roles where rolname = 'pfin_provider_sync'), true)
  and not coalesce((select has_table_privilege('pfin_provider_sync', 'pfin.account', 'INSERT')
                  from pg_roles where rolname = 'pfin_provider_sync'), true)
  and not coalesce((select has_table_privilege('pfin_provider_sync', 'pfin.eod_price', 'INSERT')
                  from pg_roles where rolname = 'pfin_provider_sync'), true)
  and not coalesce((select has_function_privilege('pfin_provider_sync', 'pfin.fn_ingest_transactions(jsonb)', 'EXECUTE')
                  from pg_roles where rolname = 'pfin_provider_sync'), true),
  '(r9) NOINHERIT proven at the PRIVILEGE layer on the worker''s real surfaces: `pfin_provider_sync` reports NO ambient USAGE on schema pfin, NO SELECT on pfin.linked_source, NO INSERT on pfin.account or pfin.eod_price, and NO EXECUTE on pfin.fn_ingest_transactions — even though it is a member of the roles that hold those privileges. Its entire reach is via explicit SET ROLE. RED if NOINHERIT were lost, or if a direct grant were ever made to the login role on any of these'
);

-- ---------------------------------------------------------------------
-- (r10) THE CATCH-ALL (r9) CANNOT REACH: zero privileges granted to this
--       role ANYWHERE in the cluster, and zero objects owned by it.
--       116 grants object privileges to NOTHING, so the correct expected
--       value is the EMPTY inventory — and this leg REDs on the first
--       grant of any kind, including one added by a future migration that
--       never touches this file.
--       FAIL-CLOSED: to_regrole() yields NULL for a missing role, which
--       would make every comparison false and pass vacuously — so the
--       missing-role case is mapped to a distinct non-empty sentinel.
--       aclexplode compares grantee OIDs, not role-name substrings: an ACL
--       text LIKE would false-match any role whose name contains this one.
-- ---------------------------------------------------------------------
select is(
  case when to_regrole('pfin_provider_sync') is null then 'ROLE MISSING (see r0)'
  else coalesce((
    select string_agg(x, '; ' order by x) from (
      select 'relation-acl ' || c.oid::regclass::text as x
        from pg_class c, aclexplode(c.relacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'column-acl ' || att.attrelid::regclass::text || '.' || att.attname
        from pg_attribute att, aclexplode(att.attacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'schema-acl ' || n.nspname
        from pg_namespace n, aclexplode(n.nspacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'function-acl ' || p.oid::regprocedure::text
        from pg_proc p, aclexplode(p.proacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'type-acl ' || t.oid::regtype::text
        from pg_type t, aclexplode(t.typacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'database-acl ' || d.datname
        from pg_database d, aclexplode(d.datacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'tablespace-acl ' || ts.spcname
        from pg_tablespace ts, aclexplode(ts.spcacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'default-acl ' || da.defaclobjtype::text
        from pg_default_acl da, aclexplode(da.defaclacl) a
       where a.grantee = to_regrole('pfin_provider_sync')
      union all
      select 'owns-relation ' || c.oid::regclass::text
        from pg_class c where c.relowner = to_regrole('pfin_provider_sync')
      union all
      select 'owns-schema ' || n.nspname
        from pg_namespace n where n.nspowner = to_regrole('pfin_provider_sync')
      union all
      select 'owns-function ' || p.oid::regprocedure::text
        from pg_proc p where p.proowner = to_regrole('pfin_provider_sync')
      union all
      select 'owns-type ' || t.oid::regtype::text
        from pg_type t where t.typowner = to_regrole('pfin_provider_sync')
        and t.typtype <> 'b'
      union all
      select 'default-acl-owner ' || da.defaclobjtype::text
        from pg_default_acl da where da.defaclrole = to_regrole('pfin_provider_sync')
    ) t), '') end,
  '',
  '(r10) ZERO object privilege anywhere, and ZERO ownership: `pfin_provider_sync` appears in NO relation, column, schema, function, type, database, tablespace or default ACL in this database, and owns nothing. Migration 116 grants object privileges to NOTHING — the login role''s entire reach is its two memberships — so the correct inventory is EMPTY. This is the leg that REDs when a grant is added, including by a future migration that never touches this file. A non-empty result names exactly what was granted or what is owned; ''ROLE MISSING'' means 116 is not applied (see r0), never that the inventory is clean'
);

-- ---------------------------------------------------------------------
-- (r11) The role's self-documenting comment is present. That comment is
--       the only place the deploy two-step, the prohibition on the
--       single-statement password form, and the PFIN_DB_USER caveat reach
--       an operator reading the catalog with no repository in front of
--       them. `ok(... is not null)` rather than isnt(..., null): pgTAP's
--       isnt() PASSES on a NULL comparand, which would be a fail-open.
-- ---------------------------------------------------------------------
select ok(
  (select shobj_description(oid, 'pg_authid') is not null
     from pg_authid where rolname = 'pfin_provider_sync'),
  '(r11) `comment on role pfin_provider_sync` is present. It carries the deploy-time two-step, the PROHIBITION on the single-statement `ALTER ROLE … WITH LOGIN PASSWORD` form, and the caveat that creating this role does not by itself move provider-sync off `authenticator` — all of which an operator reads from the catalog rather than from the repository. Asserted with ok(… is not null) rather than isnt(…, null) because pgTAP''s isnt() PASSES on NULL and would fail open here'
);

select * from finish();

rollback;
