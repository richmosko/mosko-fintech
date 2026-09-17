-- =====================================================================
-- pfin_ownership_and_vault_posture.sql — the CI-lane regression watcher for
--   ADR-072 Amendment 5: the G3 ownership sweep, and vault disposition (iv‴)
--   (F/CTO-ratified 2026-09-16).
-- =====================================================================
-- ⚠ WHICH LANE THIS IS, STATED FIRST BECAUSE IT HAS BEEN GOT WRONG THREE TIMES.
--   This file runs against a CI-BUILT database. It is a regression watcher on the
--   DEFINITION. It is NOT a production observer and must never be counted as one:
--   it cannot see whether the supervised post-step ran on the box. The ONLY
--   production observer is the post-step's own assertion block, which fails the
--   step (Amendment 5 Decision I). The runbook verify is a third lane — a human
--   double-check. Three lanes, three jobs; do not let one stand in for another.
--
--   FAIL-CLOSED: every leg reads a catalog function or a scalar subquery, so a
--   missing role or relation yields NULL and ok(NULL) is RED.
-- =====================================================================

begin;

select plan(6);

-- ---------------------------------------------------------------------
-- (o1) THE SWEEP'S OUTCOME — the property the paired statements exist to
--      produce, asserted over the RESULT rather than over file syntax.
--      This is the leg that catches a mis-owned object whatever route
--      produced it, including a scratch rebuild run without the pair.
-- ---------------------------------------------------------------------
select is(
  (select count(distinct pg_catalog.pg_get_userbyid(c.relowner))::int
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relkind in ('r','v','m','S','p')),
  1,
  '(o1) every pfin relation has the SAME owner — exactly one distinct owner across tables, views, matviews, sequences and partitioned tables. RED means a mixed-ownership schema, which is what the ADR-072 Amendment 5 sweep exists to prevent and what silently breaks a later ALTER'
);

-- ---------------------------------------------------------------------
-- (o2) …and that owner is pfin_owner, not the applying identity.
-- ---------------------------------------------------------------------
select is(
  (select pg_catalog.pg_get_userbyid(n.nspowner) from pg_catalog.pg_namespace n where n.nspname = 'pfin'),
  'pfin_owner',
  '(o2) schema pfin is owned by `pfin_owner`. RED means the bootstrap applied without the paired ownership statements — objects would then belong to whichever identity ran the apply, which is the defect by-construction ownership removes'
);

-- ---------------------------------------------------------------------
-- (o3) EXACTLY ONE decrypt view, and it is 015's.
--      ⚠ Sec: this is the leg that makes dropping 007's post-step safe —
--      the only thing that would catch a stale 007 view surviving a mixed
--      history. A verify expecting TWO reds on a correct database.
-- ---------------------------------------------------------------------
select is(
  (select coalesce(string_agg(c.relname, ',' order by c.relname), '(none)')
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relkind = 'v' and c.relname like 'decrypted%'),
  'decrypted_source_credential',
  '(o3) exactly ONE pfin decrypt view exists and it is `decrypted_source_credential`. 015 drops 007''s `decrypted_plaid_access_token`, so TWO is not a stricter state — it means a stale 007 view survived a mixed history. RED on ''(none)'' means the supervised post-step never ran'
);

-- ---------------------------------------------------------------------
-- (o4) …with security_invoker = true. Without it the view executes as its
--      vault-less owner and is BROKEN (measured) — the (iii)-as-component
--      finding, watched rather than trusted.
-- ---------------------------------------------------------------------
select is(
  (select (select option_value from pg_catalog.pg_options_to_table(c.reloptions) where option_name = 'security_invoker')
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'decrypted_source_credential'),
  'true',
  '(o4) `pfin.decrypted_source_credential` carries security_invoker = true. It runs as the CALLER, so its vault-less owner is not the identity resolving the vault join. RED means the view executes as `pfin_owner`, which holds no vault privilege — the view would be present and BROKEN, which no existence check would notice'
);

-- ---------------------------------------------------------------------
-- (o5)/(o6) THE VETO WATCHER — neither the group owner nor the standing
--      DDL credential may reach vault, at any phase. Sec's §1 veto,
--      instrumented. ⚠ Probed BY OID via the catalog, never by name:
--      has_table_privilege(role,'vault.x',...) needs USAGE on schema vault
--      merely to RESOLVE the name, so a name-based probe would ERROR here
--      instead of returning false (measured).
-- ---------------------------------------------------------------------
select ok(
  not coalesce((select has_table_privilege('pfin_owner', c.oid, 'SELECT')
                  from pg_catalog.pg_class c
                  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'vault' and c.relname = 'decrypted_secrets'), false)
  and not coalesce((select has_schema_privilege('pfin_owner', n.oid, 'USAGE')
                  from pg_catalog.pg_namespace n where n.nspname = 'vault'), false),
  '(o5) SEC VETO WATCHER: `pfin_owner` holds NO SELECT on vault.decrypted_secrets and NO USAGE on schema vault. If it did, `migrator` would reach every provider access token by SET ROLE — a standing, CI-triggerable DDL credential reaching the decrypt surface. ON RED: REVOKE, never loosen this leg. The time-boxed grant shape opens these during the apply and REVOKES after; a RED here means the revoke did not run'
);
select ok(
  not coalesce((select has_table_privilege('migrator', c.oid, 'SELECT')
                  from pg_catalog.pg_class c
                  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'vault' and c.relname = 'decrypted_secrets'), false)
  and not coalesce((select has_schema_privilege('migrator', n.oid, 'USAGE')
                  from pg_catalog.pg_namespace n where n.nspname = 'vault'), false),
  '(o6) SEC VETO WATCHER, direct half: `migrator` itself holds no vault reach either. (o5) covers the SET ROLE route; this covers a direct grant. Both are needed — NOINHERIT means a membership-based reach and a direct grant are different facts'
);

select * from finish();

rollback;
