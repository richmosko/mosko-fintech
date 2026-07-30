-- =====================================================================
-- Per-Wave battery — pfin.linked_source_sync_audit.linked_source_id stable key + 040 re-join
--   (SELF-207 / 044 — §2.4.4.b orthogonality fix; ADR-011 Decision 3 canonical instance #15;
--    C6 EXPOSURE-GATING per ADR-023 / SECURITY §4.5; V1-SHIP-BLOCK; Sec joint-review-mandatory
--    — Decision-3 extension + the 040-view join change / owner-scope re-review)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/044_sync_audit_stable_source_id.sql
--   - pfin.linked_source_sync_audit.linked_source_id bigint (NULLABLE; PLAIN reference, NO declared
--     FK — the table is immutable audit-class); index sync_audit_linked_source_idx.
--   - pfin.fn_sync_audit_matched_linked_source() BEFORE INSERT (INVOKER, set search_path=''):
--     raises when linked_source_id IS NOT NULL AND no same-(users_id) linked_source has that
--     source_id (Decision-3 #15); LENIENT on NULL (deploy-safety). Message:
--     'pfin.linked_source_sync_audit.linked_source_id % is not a same-tenant source for users_id %
--      (Decision-3 #15 matched-tenant fence)'.
--   - pfin.linked_source_sync_history (040) view re-created: IDENTICAL projection + owner-semantics
--     (security_invoker=false) + both-sides auth.uid() scope; the ONLY change is the join key —
--     (provider, external_connection_id) digest  ->  ls.source_id = lsa.linked_source_id (STABLE).
-- Prereqs exercised (all on main):
--   015 — linked_source (mutable external_connection_id digest) + linked_source_sync_audit
--         (service_role-only, append-only; the immutability trigger linked_source_sync_audit_block_
--         mutation raises on UPDATE/DELETE for ALL roles). 040 — the sync-history view. 043 — the
--         connection-state view whose last_successful_sync_at derives from the 040 view.
-- Reuses the 040/042/043 idiom: \ir verbs, ALL-LOWERCASE \gset literals, role restored to postgres
--   between blocks (PR #121 _rls-USAGE root). Owner views read UNDER authenticated (compose with RLS).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (1)-(5) HEADLINE — history SURVIVES a reauth digest-mutation. A source's sync history is       │
-- │      joined to it by the STABLE linked_source_id, NOT the mutable digest. After the source's   │
-- │      external_connection_id is mutated (old→new digest, exactly as SimpleFIN reauth's in-place  │
-- │      vault.update_secret re-admission does), the owner's pre-reauth rows STILL appear in the 040│
-- │      view and 043's last_successful_sync_at is PRESERVED (not reset to NULL). (5) is the teeth: │
-- │      the audit rows are now digest-ORPHANED (their old digest ≠ the source's new digest), so a  │
-- │      digest-join would return ZERO — the id-join is the ONLY thing keeping the history → the    │
-- │      whole point of option (b). RED under the pre-044 (provider, external_connection_id) join.  │
-- │ (6)/(7) 040 owner-isolation PRESERVED across the re-join: A sees ZERO of B's sync rows; B sees  │
-- │      its own (non-vacuous companion) — the both-sides users_id=auth.uid() scope was not weakened.│
-- │ (8)-(10) Decision-3 #15 fence: a cross-tenant linked_source_id INSERT fails closed (inversion-  │
-- │      proved by the same-tenant ACCEPT); a NULL linked_source_id is TOLERATED (lenient — a NULL  │
-- │      is a completeness gap, not a cross-tenant-FK-bypass).                                       │
-- │ (11)/(12) BACKFILL correctness (reproduced): the (provider, external_connection_id, users_id)   │
-- │      match assigns each NULL-linked row its OWN source; a removed/orphan row (no matching source)│
-- │      stays NULL (correctly excluded from the owner view). Tenant-safe (users_id predicate).      │
-- │ (13) Immutability INTACT post-migration: a runtime UPDATE on sync_audit still raises            │
-- │      (block_mutation re-enabled after the migration's transient backfill-disable).               │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; 044 adds a column + an INVOKER
--   trigger + a view re-join on a service_role-only table — no infra-credential, no service_role
--   code-layer, no app->worker surface; per the 044 header §10 3-axis, Path B). Decision-3 family
--   +1: NEW CANONICAL INSTANCE #15 (linked_source_sync_audit.linked_source_id -> linked_source
--   .source_id), fenced by fn_sync_audit_matched_linked_source (BEFORE INSERT, lenient-on-null) —
--   THIS battery is the pgTAP proof it fails closed cross-tenant. Verify the live #15 count against
--   ADR-011 Decision 3 at joint-review (Sec joint-review-mandatory).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO real credentials (SD-03) / NO prod data. Digests are readable
--   synthetic strings (the view now joins on the id, not the digest; the fence/backfill match the
--   digest as an opaque string). sync_audit is service_role-only (no authenticated write path) —
--   seeded PRIVILEGED (role=postgres) with explicit users_id (auth.uid() is NULL under postgres).
--   All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + source ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called
--   at role=postgres and each block restores role=postgres before the next. \gset var names lowercase.
--
-- ⟦WIRE-VALIDATE⟧ authored against 044's firmed contract; the authoritative run is the 001->044 reset
--   stack. RED-until-044-applied is expected on any pre-044 stack (the column/fence/re-join absent).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(13);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — the sole write path for these tables).
--   A owns a_src (2 successful sync-audit rows, linked_source_id set = the post-companion writer
--   behavior) + c_src (for the backfill reproduction). B owns b_src (1 sync-audit row). Digests are
--   readable synthetic strings. users_id explicit.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'simplefin', 'digest-a-old', 'Bank A', 'healthy') returning source_id as a_src \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'simplefin', 'digest-c',     'Bank C', 'healthy') returning source_id as c_src \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'tb', 'simplefin', 'digest-b',     'Bank B', 'healthy') returning source_id as b_src \gset

-- a_src: two SUCCESSFUL sync-audit rows (linked_source_id = a_src; external_connection_id = the
-- CURRENT digest at write time). last successful = 07-05.
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('simplefin', 'scheduled_poll', :'ta', 'digest-a-old', '{"result":{"transactionsInserted":10}}'::jsonb, '2026-07-01T00:00:00Z', :a_src);
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('simplefin', 'scheduled_poll', :'ta', 'digest-a-old', '{"result":{"transactionsInserted":20}}'::jsonb, '2026-07-05T00:00:00Z', :a_src);

-- b_src: one SUCCESSFUL sync-audit row (linked_source_id = b_src).
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('simplefin', 'scheduled_poll', :'tb', 'digest-b', '{"result":{"transactionsInserted":5}}'::jsonb, '2026-07-02T00:00:00Z', :b_src);

-- =====================================================================
-- BLOCK 1a (authenticated A) — baseline BEFORE the digest mutation.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1) baseline: A's 040 sync-history shows both a_src rows (id-join).
select is(
  (select count(*) from pfin.linked_source_sync_history where linked_source_id = :a_src)::bigint,
  2::bigint,
  '(1) baseline: A sees both a_src sync-history rows in the 040 view (joined on the stable linked_source_id)'
);

-- (2) baseline: 043 last_successful_sync_at for a_src = the latest successful (07-05).
select is(
  (select last_successful_sync_at::date from pfin.linked_source_connection_state where linked_source_id = :a_src),
  '2026-07-05'::date,
  '(2) baseline: 043 last_successful_sync_at for a_src = 2026-07-05 (derived from the 040 view)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- SIMULATED REAUTH DIGEST MUTATION (postgres) — SimpleFIN reauth mints a new Access URL → a new
--   digest; the in-place vault.update_secret re-admission UPDATEs linked_source.external_connection_id.
--   The IMMUTABLE sync-audit rows keep their OLD digest + their STABLE linked_source_id.
-- =====================================================================
update pfin.linked_source set external_connection_id = 'digest-a-new' where source_id = :a_src;

-- (5) TEETH: the a_src audit rows are now digest-ORPHANED — their (old) external_connection_id no
--     longer equals the source's CURRENT digest, so a (provider, external_connection_id) digest-join
--     would return ZERO. The id-join is the ONLY thing that still resolves them (read as postgres —
--     sync_audit is service_role-only).
select is(
  (select count(*) from pfin.linked_source_sync_audit
     where linked_source_id = :a_src
       and external_connection_id = (select external_connection_id from pfin.linked_source where source_id = :a_src))::bigint,
  0::bigint,
  '(5) TEETH: after the digest mutation, ALL a_src audit rows are digest-orphaned (old digest <> the source''s current digest) — a digest-join would return 0; only the stable linked_source_id resolves them (RED under the pre-044 digest join)'
);

-- =====================================================================
-- BLOCK 1b (authenticated A) — history SURVIVES the mutation + owner isolation.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (3) HEADLINE: A STILL sees both a_src rows after the digest mutation (id-join survives).
select is(
  (select count(*) from pfin.linked_source_sync_history where linked_source_id = :a_src)::bigint,
  2::bigint,
  '(3) HEADLINE: after the reauth digest mutation, A STILL sees both a_src sync-history rows (the 040 re-join on linked_source_id is stable) — RED if the view still joined on the mutable digest'
);

-- (4) HEADLINE: 043 last_successful_sync_at for a_src is UNCHANGED (not reset to NULL).
select is(
  (select last_successful_sync_at::date from pfin.linked_source_connection_state where linked_source_id = :a_src),
  '2026-07-05'::date,
  '(4) HEADLINE: 043 last_successful_sync_at for a_src is PRESERVED at 2026-07-05 across the digest mutation (the derivation rides the stable id-join; a broken source no longer looks never-synced)'
);

-- (6) owner-isolation preserved: A sees ZERO of B's sync rows through the re-joined view.
select is(
  (select count(*) from pfin.linked_source_sync_history where linked_source_id = :b_src)::bigint,
  0::bigint,
  '(6) owner-isolation: A sees ZERO of B''s sync-history rows after the re-join (the both-sides users_id=auth.uid() scope was preserved; the (7) B-sees-b1 companion proves this is real isolation)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — non-vacuous isolation companion.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (7) B DOES see its OWN b_src sync row (1) — (6)'s ZERO for A is real isolation, not an empty view.
select is(
  (select count(*) from pfin.linked_source_sync_history where linked_source_id = :b_src)::bigint,
  1::bigint,
  '(7) non-vacuous companion: B sees its OWN b_src sync-history row (1) → (6)''s ZERO for A is real cross-tenant isolation, not an empty result set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (postgres) — Decision-3 #15 matched-tenant fence on sync_audit INSERT.
--   sync_audit is service_role-only; INSERTs run privileged. The BEFORE INSERT fence reads
--   pfin.linked_source authoritatively (postgres/service_role bypass RLS → validates the TRUE owner).
-- =====================================================================

-- (8) LOAD-BEARING cross-tenant: an audit row for A (users_id=A) referencing B's source_id → the #15
--     fence RAISES (a worker bug binding an audit row to another tenant's source is fenced).
select throws_like(
  format($$ insert into pfin.linked_source_sync_audit (provider, source, users_id, linked_source_id)
              values ('simplefin', 'scheduled_poll', %L, %s) $$, :'ta', :b_src),
  '%Decision-3 #15 matched-tenant fence%',
  '(8) LOAD-BEARING Decision-3 #15: a sync_audit INSERT with users_id=A but linked_source_id = B''s source RAISES fn_sync_audit_matched_linked_source (cross-tenant reference fails closed; inversion-proved by the (9) same-tenant ACCEPT)'
);

-- (9) non-vacuous control: the SAME-tenant reference (users_id=A, linked_source_id=a_src) is ACCEPTED.
select lives_ok(
  format($$ insert into pfin.linked_source_sync_audit (provider, source, users_id, linked_source_id)
              values ('simplefin', 'scheduled_poll', %L, %s) $$, :'ta', :a_src),
  '(9) non-vacuous control: a same-tenant sync_audit INSERT (users_id=A, linked_source_id=a_src) is ACCEPTED → (8)''s raise is mismatch-driven, not a blanket block'
);

-- (10) LENIENT on NULL: a NULL linked_source_id is TOLERATED (a completeness gap, not a Decision-3
--      bypass — deploy-safety for the old worker during the companion rollout).
select lives_ok(
  format($$ insert into pfin.linked_source_sync_audit (provider, source, users_id, linked_source_id)
              values ('simplefin', 'scheduled_poll', %L, null) $$, :'ta'),
  '(10) lenient-on-null: a NULL linked_source_id sync_audit INSERT is TOLERATED (a NULL is a completeness gap, not a cross-tenant-FK-bypass — the fence validates ONLY when linked_source_id IS NOT NULL)'
);

-- =====================================================================
-- BLOCK 4 (postgres) — BACKFILL reproduction + immutability-intact.
--   The migration backfills linked_source_id on existing NULL rows by (provider, external_connection_id,
--   users_id), transiently disabling the immutability trigger. Reproduce that here on fresh NULL rows.
-- =====================================================================

-- Fresh NULL-linked rows: one whose digest MATCHES c_src, one ORPHAN (matches no source).
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, linked_source_id)
  values ('simplefin', 'scheduled_poll', :'ta', 'digest-c', null)
  returning audit_id as bf_match \gset
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, linked_source_id)
  values ('simplefin', 'scheduled_poll', :'ta', 'digest-orphan-nomatch', null)
  returning audit_id as bf_orphan \gset

-- Reproduce the migration's backfill (UPDATE needs the immutability trigger transiently disabled).
alter table pfin.linked_source_sync_audit disable trigger linked_source_sync_audit_block_mutation;
update pfin.linked_source_sync_audit lsa
   set linked_source_id = ls.source_id
  from pfin.linked_source ls
 where ls.provider = lsa.provider
   and ls.external_connection_id = lsa.external_connection_id
   and ls.users_id = lsa.users_id
   and lsa.linked_source_id is null;
alter table pfin.linked_source_sync_audit enable trigger linked_source_sync_audit_block_mutation;

-- (11) backfill correctness: the matching row got linked_source_id = c_src (matched on provider +
--      digest + users_id).
select is(
  (select linked_source_id from pfin.linked_source_sync_audit where audit_id = :bf_match),
  :c_src::bigint,
  '(11) backfill correctness: the NULL-linked row whose (provider, external_connection_id, users_id) matches c_src got linked_source_id = c_src'
);

-- (12) backfill orphan: a row matching NO live source stays NULL (correctly excluded from the view).
select ok(
  (select linked_source_id from pfin.linked_source_sync_audit where audit_id = :bf_orphan) is null,
  '(12) backfill orphan: a NULL-linked row with no matching source (removed / bad digest) stays NULL (excluded from the owner view — same as today''s digest-orphans; the users_id predicate keeps it tenant-safe)'
);

-- (13) immutability INTACT: after the migration re-enabled block_mutation, a runtime UPDATE on a
--      sync_audit row still raises (the transient backfill-disable did not weaken the append-only guarantee).
select throws_like(
  format($$ update pfin.linked_source_sync_audit set detail = '{}'::jsonb where audit_id = %s $$, :bf_orphan),
  '%is immutable%',
  '(13) immutability intact: a runtime UPDATE on sync_audit still RAISES linked_source_sync_audit_block_mutation (re-enabled post-backfill) — the migration''s transient disable did not weaken the append-only guarantee for runtime roles'
);

select * from finish();
rollback;
