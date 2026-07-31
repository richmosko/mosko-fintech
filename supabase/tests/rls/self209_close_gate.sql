-- =====================================================================
-- SELF-209 — §2.4.5 RLS CLOSE-GATE (consolidated V1-SHIP-BLOCK verification battery)
-- =====================================================================
-- SEAM-ONLY. Authors NO schema (no migration / function / policy / column). This file
-- is the single end-to-end proof that the ALREADY-LANDED §2.4 Onboarding RLS surface
-- holds closed. It COMPOSES the per-migration two-tenant batteries (run green by the
-- full `supabase test db` suite) and adds the NET-NEW close-gate assertions (bucket B)
-- that no single per-migration battery asserts as a consolidated whole.
--
-- Sec joint-review-mandatory (touches the RLS isolation surface + the DEFINER-allowlist
-- posture assertion, both veto-adjacent). Ledgers all FLAT (SEAM-only): §10 = 3
-- (RT-22/RT-26/RT-27); SECURITY DEFINER allowlist = 4 (3 authored + 1 reserved-unauthored);
-- Decision-3 family = 15 labeled / 13 DDL-realized. This file MOVES no ledger.
--
-- ┌─ COMPOSE (verified green by the full suite; this file re-proves the cross-cutting seams) ┐
-- │ 003 (account + account_users own-RLS + creator-grant DEFINER trigger), 004 (account_trans │
-- │ immutability cross-tier), 006 (account_trans rd/wr-JOIN), 009 (user_taxonomy), 012/013     │
-- │ (acct setup + manual account), 015/021/040/043/044 (linked_source / dedup / sync_audit /   │
-- │ connection-state), 022 (user_asset_category — #8/#9), 023/029/038 (annotation / split /    │
-- │ manual-entry write), 042 (fn_land_linked_accounts + SELF-199 attribute-write), 045 (Plaid  │
-- │ webhook tenant-resolution + cursor), self200 (pending-classification).                      │
-- │ Per-table isolation for the tables NOT re-seeded here (uac 022, annotation 023, split 029,  │
-- │ manual-trans 038, land-accounts 042) is COMPOSED from those green batteries — this gate     │
-- │ does not re-derive their heavy fixtures; it proves the §2.4 core spine + the seams.         │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- NET-NEW (this file):
--   (a) DEFINER-allowlist posture — prosecdef=t set in pfin is EXACTLY the 3 authored fns.
--   (b) Manual-entry edit-path immutability — every user-facing edit leaves the ORIGINAL
--       account_trans row byte-identical (append/overlay); direct UPDATE/DELETE rejected at
--       BOTH the authenticated (ACL) and service_role (immutability-trigger) tiers.
--   (c) account_users deferred-write DENY-BY-DEFAULT (AC item 2) — no authenticated
--       INSERT/UPDATE/DELETE at BOTH the ACL and RLS layers; cross-tenant users_id pivot
--       rejected. Certifies the V1 posture (deny-by-default), NOT an implemented
--       column-restricted UPDATE (that stays DEFERRED to V2/SELF-190, Fork-1=A).
--   (d) End-to-end §2.4 two-tenant cross-tenant sweep — read-empty on the own-users_id
--       spine; cross-tenant write fails closed; cross-account WITHIN-tenant gated by
--       wr_access; webhook forged-tenant isolation (045); cursor ACL (045).
--
-- THE 3 CONSCIOUS DEFERRALS — each explicitly certified (Block E), never silently passed:
--   (i)   user_taxonomy (009): UPDATE/DELETE deny-by-default at BOTH ACL + RLS.
--         ⚑ RECONCILIATION: the reconciliation memo said "authenticated SELECT only". LIVE
--           schema shows authenticated holds INSERT+SELECT — migration 041 (SELF-311)
--           UN-DEFERRED user_taxonomy INSERT (tenant-scoped users_id=auth.uid() policy +
--           grant; the 009 battery header documents this). INSERT is NOT a hole (RLS-gated,
--           tenant-scoped). This gate certifies what is ACTUALLY deferred: UPDATE/DELETE.
--   (ii)  Decision-3 #15 lenient-on-NULL (044): NULL linked_source_id TOLERATED (completeness
--         gap, not a bypass); non-null cross-tenant RAISES (fence has teeth).
--   (iii) SELF-201 Task #7 general audit-log helper: reserved-unauthored — proved by (a) +
--         the explicit (E-iii) "zero DEFINER fns outside the 3-entry allowlist".
--
-- INVERSION-CHECKED (RED-on-regression proved in-file, canary-pattern per 00_rls_inversion):
--   (a-inv) a stray SECURITY DEFINER fn planted in pfin is DETECTED (prosecdef count → 4),
--           then rolled back to savepoint — the allowlist guard has teeth.
--   (c-inv) a stray authenticated UPDATE grant on account_users makes the ACL stop denying
--           (RLS-filters to 0 rows, no 42501) — proving the (c1) deny-by-default is
--           non-vacuous — then rolled back to savepoint.
--   Plus the non-vacuous positive companions: (b6) the append DID add a row; (d-w4) a
--   wr_access=true insert SUCCEEDS; (d-cursor2) service_role CAN write the cursor;
--   (E-ii-b) the same-tenant/non-null path is the mismatch-driven control for (E-ii-a).
--
-- 42501/message-PRECISION (per the 003/004 lesson): schema-USAGE-denied, table-ACL-denied,
--   and RLS-WITH-CHECK are ALL 42501, so ACL denials are matched on the MESSAGE
--   ('permission denied for table X') and RLS-WITH-CHECK on 'new row violates row-level
--   security policy%for table "X"' — the INTENDED failure, never an incidental 42501.
--
-- ROLE/SCHEMA DISCIPLINE (003 root-cause): `_rls` grants no USAGE to authenticated, so every
--   `_rls.*` verb + every pg_catalog query runs ONLY at role=postgres; tenant UUIDs are
--   resolved to psql literals via \gset while privileged and interpolated via format(%L)
--   OUTSIDE any dynamic SQL that runs under authenticated. throws_like/throws_ok/is/ok/
--   lives_ok under authenticated is proven safe by the green 003/004/006 batteries.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers (SD-15) / NO real Plaid access tokens (SD-03) / NO prod
--   data. Item ids + provider_event_ids are readable synthetic strings. All in a rolled-back
--   txn. ⟦WIRE-VALIDATE⟧ authored against the 001→045 reset stack; RED-until-045-applied is
--   expected on any pre-045 stack.
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(36);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres session — RLS-bypassed; the sole seed path).
--   Tenant A owns TWO accounts (acct1 = full creator wr_access; acct2 = DEMOTED to
--   rd-only, so cross-account WITHIN-tenant wr_access gating is testable), ONE committed
--   account_trans (the immutable-ledger target), and ONE plaid linked_source. Tenant B
--   owns ONE plaid linked_source (the isolation victim). auth.uid() is NULL under postgres,
--   so account.users_id is set explicitly; the 003 creator-grant DEFINER trigger fires on
--   each account INSERT (writes account_users rd+wr for the creator).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct-1', 'depository', 'household', 'taxable')
  returning account_id as acct1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct-2', 'depository', 'household', 'taxable')
  returning account_id as acct2 \gset

-- Demote A's creator wr_access on acct2 to rd-only (account_users is mutable under postgres;
-- superuser bypasses the authenticated ACL). This makes acct2 a same-tenant, readable-but-
-- not-writable account for the (d-w3) cross-account wr_access-gating assertion.
update pfin.account_users set wr_access = false where account_id = :acct2 and users_id = :'ta';

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acct1, '2026-01-15', 100, 'seed-v', 'committed original in acct1')
  returning trans_id as t1 \gset

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'item-a-209', 'Bank A', 'healthy') returning source_id as a_ls \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'tb', 'plaid', 'item-b-209', 'Bank B', 'healthy') returning source_id as b_ls \gset

-- =====================================================================
-- BLOCK A — (a) SECURITY DEFINER allowlist posture (\df+ style).
--   The prosecdef=t set in schema pfin must be EXACTLY the 3 authored fns. Catches any
--   stray/escalated DEFINER on the whole §2.4 surface (and the reserved SELF-201 Task #7
--   audit-log helper appearing as an actual function).
-- =====================================================================

-- (a-inv) INVERSION (teeth): plant a stray DEFINER fn in pfin -> the guard DETECTS it
--   (count -> 4), then roll it back. Mirrors 00_rls_inversion_self_test's canary pattern.
savepoint sp_definer_canary;
create function pfin._zzz_definer_canary() returns void
  language plpgsql security definer set search_path = '' as $$ begin end $$;
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.prosecdef),
  4,
  '(a-inv) DEFINER-guard TEETH: a stray SECURITY DEFINER fn planted in pfin is DETECTED (prosecdef count -> 4) -> the (a1)/(a2) posture assertions are non-vacuous'
);
rollback to savepoint sp_definer_canary;

-- (a1) the set is EXACTLY the 3 authored DEFINER fns (no unexpected 4th).
select set_eq(
  $$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.prosecdef $$,
  $$ values ('fn_grant_creator_access'::text), ('fn_reclass_history_insert'), ('fn_refresh_updated_at') $$,
  '(a1) DEFINER allowlist = EXACTLY {fn_refresh_updated_at, fn_grant_creator_access, fn_reclass_history_insert}; no unexpected 4th DEFINER (the SELF-201 Task #7 audit-log helper stays reserved-unauthored)'
);

-- (a2) count is exactly 3 (the reserved 4th allowlist slot is unauthored).
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.prosecdef),
  3,
  '(a2) exactly 3 SECURITY DEFINER functions in pfin (authored=3; the reserved 4th slot is unauthored -> count stays 3)'
);

-- =====================================================================
-- BLOCK B — (b) Manual-entry edit-path immutability composition.
--   Every user-facing "edit" of a committed account_trans row is append/overlay — it leaves
--   the ORIGINAL row byte-identical — and a direct UPDATE/DELETE is rejected at BOTH tiers.
--   fn_create_manual_trans (038) + the 029 split are INSERT-only-by-construction RPCs whose
--   own batteries prove their contracts; this gate proves the immutable SPINE they write onto.
-- =====================================================================

-- Capture the byte-image of the original ledger row BEFORE any edit.
select md5(t::text) as t1_before from pfin.account_trans t where t.trans_id = :t1 \gset

-- (b1)/(b2) authenticated tier: direct UPDATE/DELETE fail closed at the TABLE ACL
--   (account_trans is INSERT+SELECT only for authenticated — no UPDATE/DELETE grant).
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.account_trans set amount = 999 where trans_id = %s $$, :t1),
  'permission denied for table account_trans',
  '(b1) authenticated direct UPDATE of a committed account_trans row fails closed at the table ACL (no UPDATE grant — the ledger is INSERT+SELECT only for authenticated)'
);
select throws_like(
  format($$ delete from pfin.account_trans where trans_id = %s $$, :t1),
  'permission denied for table account_trans',
  '(b2) authenticated direct DELETE of a committed account_trans row fails closed at the table ACL'
);
select set_config('role', 'postgres', true);

-- (b3)/(b4) service_role tier: RLS-bypass does NOT bypass the immutability TRIGGER. Hold the
--   table ACL open to service_role (test-granted, rolled back) so the TRIGGER — not a missing
--   grant — is the sole gate (the "grant-then-trigger" analogue of the grant-then-RLS rule).
grant usage on schema pfin to service_role;
grant select, update, delete on pfin.account_trans to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.account_trans set amount = 999 where trans_id = %s $$, :t1),
  'pfin.account_trans is immutable%UPDATE blocked%',
  '(b3) CROSS-TIER: service_role direct UPDATE blocked by the immutability TRIGGER (RLS-bypass does NOT bypass the trigger — the privileged-context immutability fence RLS-default alone cannot give)'
);
select throws_like(
  format($$ delete from pfin.account_trans where trans_id = %s $$, :t1),
  'pfin.account_trans is immutable%DELETE blocked%',
  '(b4) CROSS-TIER: service_role direct DELETE blocked by the immutability TRIGGER'
);
select set_config('role', 'postgres', true);

-- (b5) REVERSE-AND-REPLACE edit path: an edit APPENDS a new is_reverse row (valid same-account)
--   and leaves the ORIGINAL row byte-identical.
insert into pfin.account_trans (account_id, transaction_date, amount, is_reverse, replaces_trans_id)
  values (:acct1, '2026-02-01', -100, true, :t1);
select is(
  (select md5(t::text) from pfin.account_trans t where t.trans_id = :t1),
  :'t1_before',
  '(b5) edit = APPEND: the reverse-and-replace edit path leaves the ORIGINAL account_trans row byte-identical (append-only; never in-place mutate)'
);
-- (b6) non-vacuous companion: the append DID add a reverse row.
select is(
  (select count(*)::int from pfin.account_trans where replaces_trans_id = :t1 and is_reverse),
  1,
  '(b6) non-vacuous companion: the reverse-and-replace DID append a new is_reverse row -> (b5) byte-identity is a real append, not a no-op'
);
-- (b7) ANNOTATION OVERLAY edit path: category/note edits write to the SEPARATE 023 overlay
--   table and leave the ledger row byte-identical.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t1, null);
select is(
  (select md5(t::text) from pfin.account_trans t where t.trans_id = :t1),
  :'t1_before',
  '(b7) edit = OVERLAY: annotating t1 (023 overlay table) leaves the ORIGINAL account_trans row byte-identical (category/note edits never mutate the immutable ledger)'
);

-- =====================================================================
-- BLOCK C — (c) account_users deferred-write DENY-BY-DEFAULT certification (AC item 2).
--   Certifies the V1 posture: authenticated has NO INSERT/UPDATE/DELETE at BOTH the ACL and
--   RLS layers; the Lock-3-mod-1 column-restricted UPDATE stays DEFERRED to V2/SELF-190
--   (Fork-1=A). This is deny-by-default, NOT an implemented column-restricted UPDATE.
-- =====================================================================

-- (c-inv) INVERSION (teeth): open a stray authenticated UPDATE grant -> the ACL stops denying
--   (with no UPDATE policy, RLS filters to 0 rows, no 42501) -> the deny-by-default assertion
--   would go RED. Then roll the grant back.
savepoint sp_account_users_grant;
grant update on pfin.account_users to authenticated;
select ok(
  not _rls.stmt_denied_as('authenticated', $$ update pfin.account_users set nickname = 'x' $$),
  '(c-inv) TEETH: with a stray authenticated UPDATE grant the ACL no longer denies (RLS-filters to 0 rows; no 42501) -> the (c1) deny-by-default assertion is non-vacuous'
);
rollback to savepoint sp_account_users_grant;

-- (c1) authenticated UPDATE (even nickname/notes) fails closed at the ACL.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ update pfin.account_users set nickname = 'x', notes = 'y' $$,
  'permission denied for table account_users',
  '(c1) AC2 deny-by-default: authenticated UPDATE of account_users (even nickname/notes) fails closed at the table ACL -> the Lock-3-mod-1 column-restricted UPDATE stays DEFERRED to V2/SELF-190; certified deny-by-default, NOT implemented'
);
-- (c2) cross-tenant users_id pivot (re-tenant a membership row to B) fails closed at the ACL.
select throws_like(
  format($$ update pfin.account_users set users_id = %L $$, :'tb'),
  'permission denied for table account_users',
  '(c2) AC2 cross-tenant pivot: an authenticated attempt to rewrite account_users.users_id (re-tenant a membership row to B) fails closed at the ACL -> the load-bearing re-tenant pivot surface is unreachable in V1'
);
-- (c3) authenticated INSERT fails closed at the ACL (DEFINER trigger is the sole writer).
select throws_like(
  format($$ insert into pfin.account_users (account_id, users_id, rd_access, wr_access) values (%s, %L, true, true) $$, :acct1, :'ta'),
  'permission denied for table account_users',
  '(c3) authenticated INSERT on account_users fails closed at the ACL -> the SECURITY DEFINER fn_grant_creator_access trigger is the SOLE writer'
);
-- (c4) authenticated DELETE fails closed at the ACL.
select throws_like(
  $$ delete from pfin.account_users $$,
  'permission denied for table account_users',
  '(c4) authenticated DELETE on account_users fails closed at the ACL'
);
select set_config('role', 'postgres', true);
-- (c5) RLS-layer deny-by-default: account_users has ZERO write policies (independent of the ACL).
select is(
  (select count(*)::int from pg_policy p
     join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'account_users' and p.polcmd in ('a', 'w', 'd', '*')),
  0,
  '(c5) AC2 deny-by-default at the RLS layer: account_users has ZERO INSERT/UPDATE/DELETE policies (even if a write grant were opened, no policy would admit a row)'
);

-- =====================================================================
-- BLOCK D — (d) End-to-end §2.4 two-tenant cross-tenant sweep.
--   Read-empty on the own-users_id spine; cross-tenant write fails closed; cross-account
--   WITHIN-tenant gated by wr_access; webhook forged-tenant isolation (045); cursor ACL (045).
-- =====================================================================

-- READ SIDE (own-users_id §2.4 tables; A owns rows -> read-empty for B is non-vacuous).
--   account_trans has NO own users_id (scoped via account_id -> account_users rd_access-JOIN);
--   its read-isolation is COMPOSED from the green 006 battery, not the generic users_id probe.
select _rls.expect_owner_can_read('pfin.account'::regclass, :'ta'::uuid, 2::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.account'::regclass, :'ta'::uuid, :'tb'::uuid);
select _rls.expect_cross_tenant_read_empty('pfin.account_users'::regclass, :'ta'::uuid, :'tb'::uuid);
select _rls.expect_owner_can_read('pfin.linked_source'::regclass, :'ta'::uuid, 1::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.linked_source'::regclass, :'ta'::uuid, :'tb'::uuid);

-- WRITE SIDE — cross-tenant injection fails closed.
-- (d-w1) B forging users_id=A on pfin.account -> rejected by the INSERT WITH CHECK.
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  format($$ insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
              values (%L, 'forged-by-B', 'depository', 'household', 'taxable') $$, :'ta'),
  'new row violates row-level security policy%for table "account"',
  '(d-w1) cross-tenant INSERT: B forging users_id=A on pfin.account is rejected by the account INSERT WITH CHECK (RLS-policy violation, not an incidental 42501)'
);
-- (d-w2) B inserting into A''s acct1 -> rejected by the account_trans_insert wr_access-JOIN.
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-05-01', 10, 'x', 'x') $$, :acct1),
  'new row violates row-level security policy%for table "account_trans"',
  '(d-w2) cross-tenant INSERT: B inserting into A''s account (acct1) is rejected by the account_trans_insert wr_access-JOIN WITH CHECK (B holds no wr_access row on A''s account)'
);
select set_config('role', 'postgres', true);

-- (d-w3) cross-account WITHIN-tenant: A inserting into its OWN acct2 (wr_access demoted to
--   false) -> rejected. Same-tenant injection is gated by wr_access, not merely tenant ownership.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-05-02', 10, 'x', 'x') $$, :acct2),
  'new row violates row-level security policy%for table "account_trans"',
  '(d-w3) cross-account WITHIN-tenant: A inserting into its OWN acct2 (wr_access=false) is rejected by the wr_access-JOIN WITH CHECK -> same-tenant injection is gated by wr_access'
);
-- (d-w4) non-vacuous companion: A inserting into acct1 (wr_access=true) SUCCEEDS.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
              values (%s, '2026-05-03', 10, 'ok', 'ok') $$, :acct1),
  '(d-w4) non-vacuous companion: A inserting into acct1 (wr_access=true) SUCCEEDS -> (d-w3)''s rejection is wr_access-driven, not a blanket block'
);
select set_config('role', 'postgres', true);

-- WEBHOOK FORGED-TENANT ISOLATION (045 composition; RPCs called PRIVILEGED — the tenant is
--   resolved FROM the Item id inside the fn, so the binding is role-independent).
-- (d-w5) commit A''s Item WITH a forged users_id=B embedded in the payload (must be ignored).
select is(
  (select committed from pfin.fn_plaid_webhook_commit(
     ('{"item_id":"item-a-209","provider_event_id":"plaid:209:ev-iso","is_transactions_event":false,"status_class":"institution_down","event_type":"ITEM.ERROR","users_id":"' || :'tb' || '"}')::jsonb)),
  true,
  '(d-w5) webhook forged-key commit on A''s Item executes (committed=true) — sets up the isolation assertions'
);
-- (d-w6) the audit row is attributed to TENANT A (resolved from item_id), NOT the forged B.
select is(
  (select users_id from pfin.linked_source_sync_audit where provider_event_id = 'plaid:209:ev-iso'),
  :'ta'::uuid,
  '(d-w6) AC8 privileged-context-write: A''s Item audit row is attributed to tenant A (resolved FROM item_id), NOT the FORGED users_id=B in the payload (ADR-011 Decision 1)'
);
-- (d-w7) tenant B is UNTOUCHED — the forged key wrote nothing to B.
select is(
  (select count(*)::int from pfin.linked_source_sync_audit where users_id = :'tb'),
  0,
  '(d-w7) AC8: tenant B''s linked_source_sync_audit is UNTOUCHED (0 rows) — the forged users_id=B attributed no write to B'
);

-- CURSOR ACL (045 composition). authenticated CANNOT write sync_cursor; service_role CAN.
select ok(
  _rls.stmt_denied_as('authenticated', $$ update pfin.linked_source set sync_cursor = 'x' $$),
  '(d-cursor1) cursor ACL: authenticated CANNOT UPDATE sync_cursor (no authenticated write path on linked_source; the 045 column REVOKE) -> fail-closed'
);
select ok(
  not _rls.stmt_denied_as('service_role', $$ update pfin.linked_source set sync_cursor = 'cursor-209' $$),
  '(d-cursor2) cursor ACL companion: service_role CAN advance sync_cursor (the worker sync path) -> (d-cursor1) is authenticated-scoped, by design'
);

-- =====================================================================
-- BLOCK E — THE 3 CONSCIOUS DEFERRALS, each explicitly certified (never silently passed).
-- =====================================================================

-- (i) user_taxonomy (009): certify UPDATE/DELETE deny-by-default. (INSERT was un-deferred at
--   041/SELF-311 — tenant-scoped, RLS-gated, NOT a hole; the memo's "SELECT only" is stale.)
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ update pfin.user_taxonomy set notes = 'x' $$,
  'permission denied for table user_taxonomy',
  '(E-i-1) deferral #1 user_taxonomy: authenticated UPDATE fails closed at the ACL (UPDATE stays write-dormant). NOTE: INSERT was UN-deferred at 041/SELF-311 (tenant-scoped) — the memo''s "SELECT only" is stale, reconciled here'
);
select throws_like(
  $$ delete from pfin.user_taxonomy $$,
  'permission denied for table user_taxonomy',
  '(E-i-2) deferral #1 user_taxonomy: authenticated DELETE fails closed at the ACL (DELETE stays write-dormant)'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pg_policy p
     join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'user_taxonomy' and p.polcmd in ('w', 'd')),
  0,
  '(E-i-3) deferral #1 user_taxonomy: ZERO UPDATE/DELETE policies at the RLS layer (only insert(a)+select(r) live; UPDATE/DELETE deny-by-default independent of the ACL)'
);

-- (ii) Decision-3 #15 lenient-on-NULL (044): NULL tolerated; non-null cross-tenant raises.
--   sync_audit is service_role-only -> INSERTs run PRIVILEGED (the #15 BEFORE-INSERT fence
--   reads pfin.linked_source authoritatively under BYPASSRLS -> validates the TRUE owner).
select lives_ok(
  format($$ insert into pfin.linked_source_sync_audit (provider, source, users_id, linked_source_id)
              values ('plaid', 'webhook', %L, null) $$, :'ta'),
  '(E-ii-a) deferral #2 Decision-3 #15: a sync_audit INSERT with NULL linked_source_id is TOLERATED (lenient-on-NULL — a completeness gap during worker-companion rollout, NOT a cross-tenant bypass; conscious ratified posture)'
);
select throws_like(
  format($$ insert into pfin.linked_source_sync_audit (provider, source, users_id, linked_source_id)
              values ('plaid', 'webhook', %L, %s) $$, :'ta', :b_ls),
  '%Decision-3 #15 matched-tenant fence%',
  '(E-ii-b) deferral #2 Decision-3 #15 TEETH: a sync_audit INSERT with users_id=A but linked_source_id = B''s source RAISES the #15 fence -> lenient-on-NULL is a conscious completeness posture, NOT a hole; the non-null path fails closed'
);

-- (iii) SELF-201 Task #7 general audit-log helper: reserved-unauthored (empty 4th slot).
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.prosecdef
       and p.proname not in ('fn_refresh_updated_at', 'fn_grant_creator_access', 'fn_reclass_history_insert')),
  0,
  '(E-iii) deferral #3 SELF-201 Task #7: ZERO SECURITY DEFINER functions in pfin outside the 3-entry authored allowlist -> the reserved general audit-log helper is provably unauthored (the 4th slot is empty)'
);

select * from finish();
rollback;
