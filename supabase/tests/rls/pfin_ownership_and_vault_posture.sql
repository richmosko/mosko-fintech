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

select plan(8);

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

-- ---------------------------------------------------------------------
-- (o7) THE ENGINE BACKSTOP — `migrator` holds no CREATE on schema pfin.
--      ⚠ Sec's B-3: the revoke was BOOKED IN PROSE and executed nowhere, and
--      the battery had no leg for it. A revoke nobody watches is decoration.
--      ⚠ Decision J RAISES the stakes here rather than lowering them: the
--      transaction-scoped role statement is now known to TAKE EFFECT, so a
--      change in the CLI's batching is the SILENT path — ownership lands wrong
--      with nothing raised. This backstop is what converts that into a loud
--      42501 at the first create, which is why it is the PRIMARY control and
--      the paired convention is only the path.
-- ---------------------------------------------------------------------
select ok(
  not coalesce(has_schema_privilege('migrator', 'pfin', 'CREATE'), true),
  '(o7) ENGINE BACKSTOP: `migrator` holds NO CREATE on schema pfin, so a migration that loses its ownership pair fails 42501 instead of quietly creating a migrator-owned object. This is the PRIMARY control — the paired `set role`/`reset role` convention is the path, this is what catches the path being lost, including by a silent change in how the CLI batches statements (Decision J). ON RED: REVOKE it; never grant CREATE here to make a migration pass'
);

-- ---------------------------------------------------------------------
-- (o8) THE relforcerowsecurity WATCHER — DECISIONS.md ADR-072 Amendment 5
--      §5.3/§7 condition. NOT a Decision-4 §10 catalogued instance; this
--      guards the mechanism-equivalence the sweep's D9 co-ownership
--      verification rests on. ⚠ Sec's harness-identity-at-scale ruling
--      (H2) corrected the count here from three to TWO consumers, and
--      said why: under H2, `_liveDb.ts`'s CI cleanup connects as
--      `postgres` (which holds `rolbypassrls = t`, measured) rather than
--      `set local role pfin_owner` — and a BYPASSRLS role is exempt EVEN
--      UNDER FORCE RLS (FORCE only removes the table OWNER's own
--      exemption). So the cleanup is NOT a third consumer today; it is
--      the OWNER-exemption route that is guarded, via these two:
--        (i)  the SECURITY DEFINER functions' owner-exemption basis —
--             a DEFINER fn runs as its owner and reaches rows via
--             `pfin_owner`'s ownership-implied RLS bypass, not a policy;
--        (ii) the migrations' own seed/backfill DML, which Amendment 5
--             records as bypassing RLS AS TABLE OWNER under the
--             post-sweep ownership shape.
--      ⚠ THIS COUNT IS CONDITIONAL, not a fixed fact: it holds only
--      while `postgres` retains `rolbypassrls` — an image property this
--      repo does not control. If a future image drops it, `postgres`
--      falls back to inherited `pfin_owner` ownership for the cleanup
--      too, and the count reverts to three. Both are equivalent to
--      today's exemption ONLY while no `pfin` relation sets FORCE ROW
--      LEVEL SECURITY — measured zero across the set at authorship.
-- ---------------------------------------------------------------------
select is(
  (select count(*)::int
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relkind = 'r' and c.relforcerowsecurity),
  0,
  '(o8) relforcerowsecurity WATCHER: NO pfin table sets FORCE ROW LEVEL SECURITY. RED means one now does, and it silently breaks the TWO consumers of table-OWNER RLS exemption that rest on this today — (i) the SECURITY DEFINER functions'' owner-exemption basis and (ii) the migrations'' own seed/backfill DML (which runs as table owner post-sweep). This count is CONDITIONAL on `postgres` retaining `rolbypassrls` (an image property, not ours to fix) — the CI cleanup fixtures connect as `postgres`, exempt via BYPASSRLS rather than ownership, EXCEPT that if a future image drops that attribute the cleanup falls back to inherited pfin_owner ownership and becomes a THIRD consumer of this same watcher (ADR-072 Amendment 5 harness-identity-at-scale ruling, H2). Fixing only the consumer you were looking at leaves the other broken — check both, and re-check this count''s own precondition, before adding FORCE RLS anywhere in pfin'
);

select * from finish();

rollback;
