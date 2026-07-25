-- =====================================================================
-- Per-Wave battery — M4-GL-write (SELF-300): pfin.lot_match WRITE-ENABLEMENT — the INSERT
--   grant + the wr_access WITH CHECK policy lot_match_insert that open the fenced write path on
--   the append-only lot-matching junction (dormant since 032). This battery proves the newly-
--   opened write path is gated on THREE independent layers, exercised UNDER THE REAL
--   `authenticated` ROLE (Sec AMBER B1): ACL (grant) + RLS (wr_access WITH CHECK on the sell leg)
--   + the 032 #14 BEFORE-INSERT fence (matched-tenant + matched-security) — and that 032's
--   append-only immutability is unbroken on the now-open path.
--   V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (Decision-3 family + money/tax basis). Sec AMBER B1+B2.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/036_lot_match_write_enablement.sql
--   - grant insert on pfin.lot_match to authenticated (the ACL half; 032 write-dormancy flips
--       here — SELECT was granted at 032, INSERT lands now; UPDATE/DELETE stay ungranted).
--   - policy lot_match_insert FOR INSERT TO authenticated WITH CHECK: caller holds wr_access on
--       the SELL leg's account (sell_trans_id -> account_trans.account_id -> account_users,
--       au.users_id = auth.uid() AND au.wr_access). The RLS WRITE companion to 032's rd_access
--       SELECT policy — STRICTER (wr_access, not rd_access).
--   - refreshed comment on table. No new object/function; DEFINER stays 4; §10 stays 3.
-- Depends (as 032 + the exercised write path): 001 (pfin), 003 (account owner-only visibility +
--   the fn_grant_creator_access rd=t/wr=t row the write policy JOINs), 004/017 (account_trans +
--   security_id/quantity), 006 (account_users rd/wr_access-JOIN), 016 (pfin.asset), 032 (the
--   table + #14 fence + immutability triple-fence + lot_match_select).
--
-- ┌─ Sec AMBER B1 — the write path is EXERCISED UNDER `authenticated`, not privileged ─────────┐
-- │ 032 seeded PRIVILEGED (RLS-bypass) to prove the #14 TRIGGER teeth — which does NOT exercise │
-- │ the new lot_match_insert WITH CHECK. So every write assertion that tests the 036 surface     │
-- │ runs under `set role authenticated` + a set auth.uid() (via _rls.set_tenant): AC3 (matched-  │
-- │ security, same-tenant, fully real-tier), AC4 (the five B1 gate cases), AC5 (read isolation), │
-- │ AC6 (immutability by authenticated). ONE block stays privileged by necessity — see AC2.      │
-- │                                                                                              │
-- │ ORDERING (load-bearing, Sec B1 mechanism): the #14 fence resolves each leg's tenant via      │
-- │ pfin.account, which is OWNER-ONLY-visible (account_select: users_id = auth.uid()) — NOT      │
-- │ rd_access-shared. And #14 is a BEFORE-INSERT trigger, so it fires BEFORE the RLS WITH CHECK. │
-- │ Consequence at the authenticated tier: ANY foreign leg (sell OR buy) the caller cannot see   │
-- │ makes #14 fail-closed at 'cannot resolve' BEFORE the WITH CHECK is evaluated. So:            │
-- │   - B1(b) own-sell + foreign-buy: #14 catches it ('cannot resolve') — the WITH CHECK would   │
-- │     pass on the owned sell leg; #14 is the sole catch (AC4c). LOAD-BEARING.                   │
-- │   - B1(a) foreign-sell: in NORMAL operation #14 ALSO catches it ('cannot resolve', AC4e). To │
-- │     prove the WITH CHECK INDEPENDENTLY denies a foreign sell (the migration's defence-in-     │
-- │     depth claim: "the WITH CHECK fails on a foreign sell leg"), #14 must be ISOLATED OUT —    │
-- │     we DISABLE the #14 trigger and re-run under authenticated so the WITH CHECK is the sole   │
-- │     gate -> 42501 (AC4d; 030-precedent trigger-disable isolation, re-enabled immediately).    │
-- │   - B1(d) own legs, rd_access but NOT wr_access: #14 PASSES (owner resolves both legs), so    │
-- │     the WITH CHECK alone denies -> 42501 (AC4b; the wr≠rd proof).                             │
-- │ Roles restored to postgres between phases (PR #121 discipline).                              │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ Sec AMBER B2 — 032's two reversed assertions are MIGRATED HERE ──────────────────────────┐
-- │ 032's battery (032_lot_match_rls.sql) asserted (4b) "authenticated holds NO INSERT grant" +  │
-- │ (4c) "a direct authenticated INSERT fails at the GRANT layer (write-dormant)". 036 GRANTs     │
-- │ INSERT, so under the 001->036 reset those two would FALSE-FAIL. Per Sec's steer they are      │
-- │ REMOVED from 032 (plan 21 -> 19) and RE-HOMED here in the write-ENABLED posture:              │
-- │   - 032(4b) "NO INSERT grant"  -> AC1b "authenticated HOLDS INSERT" (the ACL flip).           │
-- │   - 032(4c) "INSERT fails at the GRANT layer" -> AC4a "authorized authenticated INSERT        │
-- │     SUCCEEDS through the real path" + AC4b/d "unauthorized INSERT is gated at RLS, not the     │
-- │     grant layer". Same PR (paired-artifact / supabase/CLAUDE.md convention 4).                 │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED / INVERSION (each assertion flips RED when its guard is broken):
--   AC1 — ACL flip (privilege catalog, postgres):
--   (1a) authenticated HOLDS SELECT — RED if the 032 read grant regressed.
--   (1b) authenticated HOLDS INSERT — RED if 036's `grant insert` were dropped (the write path
--        never opens; the migration is vacuous). [migrated 032(4b), reversed.]
--   (1c) authenticated holds NO UPDATE — RED if write-enablement wrongly opened the immutable
--        UPDATE surface at the ACL layer.
--   (1d) authenticated holds NO DELETE — RED if write-enablement wrongly opened DELETE.
--   AC2 — #14 matched-tenant PREDICATE teeth (postgres RLS-bypass — the ONLY tier where the
--        distinct `v_sell_tenant <> v_buy_tenant` branch is reachable; under authenticated a
--        foreign leg is RLS-invisible so the NULL-safe branch fires instead — see AC4c/4e. This
--        block is COMPLEMENTARY: it proves the tenant-inequality comparison itself has teeth):
--   (2a) foreign sell (B) × own buy (A) RAISES 'cross-tenant lot-match rejected' — RED if the
--        matched-tenant `<>` predicate were removed (B's basis leaks into A's tax compute).
--   (2b) own sell (A) × foreign buy (B) RAISES 'cross-tenant lot-match rejected' — mirror.
--   (2c) same-tenant same-security INSERT SUCCEEDS — non-vacuous control; seeds lm_id.
--   AC3 — #14 matched-security, UNDER AUTHENTICATED A (same-tenant correctness — fully real-tier):
--   (3a) A's secA sell × A's secB buy RAISES 'security mismatch' — RED if the correctness fold-in
--        were absent (a sell closing the wrong security's lot). #14 fires before WITH CHECK.
--   (3b) NULL security_id leg (cash) RAISES 'security mismatch' (fail-closed) — RED if a NULL
--        slipped the equality (`<>` returns NULL -> IF skipped -> leak).
--   (3c) same-tenant same-security partial lot SUCCEEDS through the real path — non-vacuous
--        control (proves 3a/3b are correctness-driven, not a blanket real-tier block).
--   AC4 — the FIVE B1 write-path gate cases, UNDER AUTHENTICATED:
--   (4a) [B1(c)] own sell × own buy + wr_access SUCCEEDS — the 036 write-path POSITIVE anchor;
--        RED if the WITH CHECK over-blocked a legitimate owner-write (feature dead). [migrated
--        032(4c): the authenticated INSERT now PASSES the grant layer and lands when authorized.]
--   (4b) [B1(d)] rd_access but NOT wr_access (acct-ro) RAISES 42501 — #14 PASSES (A owns acct-ro
--        -> both legs resolve, same tenant/security), so the wr_access WITH CHECK is the SOLE
--        gate. RED if the write policy keyed on rd_access (write as permissive as read). PROOF
--        the write policy is STRICTER than read.
--   (4c) [B1(b), LOAD-BEARING] own sell × foreign buy RAISES 'cannot resolve' — the WITH CHECK
--        passes on the owned sell leg; only #14 catches the foreign buy (NULL-safe, since A's RLS
--        hides B's leg). RED if #14's NULL-safe branch were removed (the cross-tenant buy would
--        slip past the sell-leg WITH CHECK and INSERT — the exact basis-leak Decision 3 fences).
--   (4d) [B1(a)] foreign sell RAISES 42501 with #14 DISABLED — proves the WITH CHECK
--        INDEPENDENTLY denies a foreign sell (the migration's "WITH CHECK fails on a foreign sell
--        leg" defence-in-depth claim), isolated from #14. RED if the WITH CHECK checked the buy
--        leg / omitted the sell-leg wr_access-JOIN.
--   (4e) [defence-in-depth complement to 4d] foreign sell with #14 ENABLED RAISES 'cannot
--        resolve' — proves that in NORMAL operation #14 ALSO catches a foreign sell before the
--        WITH CHECK. Together 4d+4e = both layers independently guard the sell leg.
--   AC5 — two-tenant read isolation over the write-ENABLED table (authenticated):
--   (5a) B reads 0 of A's lot_matches — RED if the 032 rd_access parent-chain SELECT policy
--        regressed when the write path opened.
--   (5b) A reads its 3 own lot_matches (2 privileged seeds 2c/3c... see counts) — RED if the read
--        policy became over-restrictive.
--   AC6 — 032 immutability UNBROKEN on the write-open path (Sec B1(e)):
--   (6a) authenticated UPDATE RAISES 'permission denied' (no UPDATE grant) — RED if 036 leaked an
--        UPDATE grant to authenticated.
--   (6b) authenticated DELETE RAISES 'permission denied' (no DELETE grant).
--   (6c) service_role UPDATE (RLS bypassed, grant held OPEN test-only) STILL RAISES the
--        immutability TRIGGER — the TRIGGER, not the ACL, is the durable gate (004/031 cross-tier
--        lesson); RED if opening INSERT relaxed the row fence.
--   (6d) TRUNCATE RAISES (block_truncate) — the history cannot be wiped.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 036 adds ZERO catalogued
--   §10 instances — an authenticated-tier INSERT grant + one wr_access WITH CHECK policy; no
--   service_role grant, no credential, no admission channel). Decision-3 #14 stays a SINGLE
--   instance realized at 032 — 036 makes it EXERCISABLE, adds no FK column, no new fence; family
--   delta = 0 (Sec pins 1-vs-2 at joint-review). SECURITY DEFINER allowlist UNCHANGED at 4.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO
--   real account numbers / NO prod data. A owns acct-alpha (wr=t) + acct-ro (creator-grant
--   downgraded to rd=t/wr=f — the wr-gate probe); B owns acct-beta. Two GLOBAL assets (users_id
--   NULL); a cash txn (NULL security). Rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 036's firmed contract; the AUTHORITATIVE run is the 001->036
--   reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's clean-apply +
--   `supabase migration up`). The committed file does NOT self-apply migrations. plan(21).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres). A owns acct-alpha (creator-grant rd=t/wr=t) + acct-ro (a 2nd
-- A-owned account whose creator-grant we DOWNGRADE to rd=t/wr=f — the wr_access-gate probe).
-- B owns acct-beta. Two GLOBAL securities (users_id NULL); one cash txn (NULL security).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-ro',    'investment', 'household', 'taxable') returning account_id as acctro \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta',  'investment', 'household', 'taxable') returning account_id as acctb \gset

-- Downgrade acct-ro's creator-grant to READ-ONLY (rd=t, wr=f) — the (4b) gate: A owns acct-ro
-- (so #14 resolves both legs and PASSES), but holds NO wr_access (so the WITH CHECK is the sole
-- gate). account_users is write-locked for authenticated; we edit it PRIVILEGED (postgres).
update pfin.account_users set wr_access = false
  where account_id = :acctro and users_id = :'ta';

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZQATSTA', 'QA Test Sec A') returning asset_id as g_seca \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZQATSTB', 'QA Test Sec B') returning asset_id as g_secb \gset

-- A's trades on acct-alpha (secA + one secB buy + one cash/NULL-security leg).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-01',  500, 'vSELLA', 'A sell secA',   :g_seca, -5) returning trans_id as sell_a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-02', -500, 'vBUYA',  'A buy secA',    :g_seca,  5) returning trans_id as buy_a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-03', -300, 'vBUYA2', 'A buy secA #2', :g_seca,  3) returning trans_id as buy_a2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-05-04', -400, 'vBUYAM', 'A buy secB',    :g_secb,  4) returning trans_id as buy_a_secb \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-05', -100, 'vCASHA', 'A cash (no security)') returning trans_id as cash_a \gset

-- A's trades on acct-ro (secA sell + buy; the wr_access-gate legs).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctro, '2026-05-06',  500, 'vSELLRO', 'A(ro) sell secA', :g_seca, -5) returning trans_id as sell_ro \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctro, '2026-05-07', -500, 'vBUYRO',  'A(ro) buy secA',  :g_seca,  5) returning trans_id as buy_ro \gset

-- B's trades on acct-beta (same global security A).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctb, '2026-05-08',  500, 'vSELLB', 'B sell secA', :g_seca, -5) returning trans_id as sell_b \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:acctb, '2026-05-09', -500, 'vBUYB',  'B buy secA',  :g_seca,  5) returning trans_id as buy_b \gset

-- =====================================================================
-- AC1 — ACL FLIP (privilege catalog, postgres). 036 opens INSERT; the 032 write-dormancy
--   (authenticated held SELECT only, NO INSERT) flips HERE (migrated 032(4b)). UPDATE/DELETE
--   stay ungranted (append-only).
-- =====================================================================
select ok(
  has_table_privilege('authenticated', 'pfin.lot_match', 'SELECT'),
  '(1a) ACL: authenticated still holds SELECT on lot_match (the 032 read grant, unregressed)'
);
select ok(
  has_table_privilege('authenticated', 'pfin.lot_match', 'INSERT'),
  '(1b) ACL FLIP: authenticated now HOLDS INSERT on lot_match (036 write-enablement — migrated from 032(4b) "no INSERT grant", reversed)'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.lot_match', 'UPDATE'),
  '(1c) ACL: authenticated holds NO UPDATE grant (write-enablement did NOT open the immutable UPDATE surface)'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.lot_match', 'DELETE'),
  '(1d) ACL: authenticated holds NO DELETE grant (append-only — DELETE stays ungranted)'
);

-- =====================================================================
-- AC2 — #14 matched-tenant PREDICATE teeth (postgres/RLS-bypass, DELIBERATELY privileged). This
--   is the ONLY tier where the distinct `v_sell_tenant <> v_buy_tenant` branch is reachable: it
--   needs BOTH legs to resolve to two different non-null tenants, which requires both rows
--   visible. Under authenticated one leg is always RLS-invisible -> the NULL-safe branch fires
--   (AC4c/4e). This block is COMPLEMENTARY to the authenticated write-path battery — it proves
--   the tenant-inequality comparison itself has teeth (not covered by the NULL-safe path).
-- =====================================================================
-- (2a) foreign sell (B) × own buy (A) -> cross-tenant RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_b, :buy_a),
  '%cross-tenant lot-match rejected%',
  '(2a) #14 matched-tenant PREDICATE (RLS-bypass, sole gate): B''s sell × A''s buy RAISES cross-tenant (the `<>` branch has teeth)'
);
-- (2b) own sell (A) × foreign buy (B) -> cross-tenant RAISE (mirror direction).
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_b),
  '%cross-tenant lot-match rejected%',
  '(2b) #14 matched-tenant PREDICATE: A''s sell × B''s buy RAISES cross-tenant (mirror direction)'
);
-- (2c) same-tenant same-security -> SUCCEEDS (non-vacuous control). Capture the row id for AC6.
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_a),
  '(2c) matched control: A''s sell × A''s buy (same security) SUCCEEDS (privileged seed)'
);
select id as lm_id from pfin.lot_match where sell_trans_id = :sell_a and buy_trans_id = :buy_a and match_seq = 1 \gset

-- =====================================================================
-- AC3 — #14 MATCHED-SECURITY, under AUTHENTICATED A (same-tenant correctness — both legs A-owned,
--   fully resolvable at the real tier; #14 is BEFORE INSERT so it fires before the WITH CHECK).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (3a) A's secA sell × A's secB buy -> security mismatch RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,4,1) $$, :sell_a, :buy_a_secb),
  '%security mismatch%',
  '(3a) #14 matched-security (authenticated A): A''s secA sell × A''s secB buy RAISES security mismatch (can''t close secA with a secB lot)'
);
-- (3b) NULL security leg (cash) -> fail-closed RAISE.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,1,1) $$, :sell_a, :cash_a),
  '%security mismatch%',
  '(3b) #14 fail-closed (authenticated A): a NULL security_id leg (non-securities trade) RAISES (must be equal and non-null — no NULL <> leak)'
);
-- (3c) same-tenant same-security partial lot -> SUCCEEDS through the real path (non-vacuous control).
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,3,1) $$, :sell_a, :buy_a2),
  '(3c) matched-security control (authenticated A): A''s secA sell × a 2nd secA buy lot (partial lot) SUCCEEDS via the real write path'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC4 — the FIVE Sec B1 write-path gate cases, UNDER AUTHENTICATED.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (4a) [B1(c)] POSITIVE ANCHOR: authenticated A (wr_access on acct-alpha) inserts own sell × own
--      buy -> SUCCEEDS. #14 passes; WITH CHECK passes (wr_access present). Distinct match_seq (5)
--      avoids the (2c) UNIQUE row. [migrated 032(4c): the authenticated INSERT now lands.]
select lives_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,5) $$, :sell_a, :buy_a),
  '(4a) 036 WRITE PATH POSITIVE [B1(c)]: authenticated A (wr_access) inserts own sell × own buy through the real path — SUCCEEDS (the negatives are non-vacuous)'
);

-- (4b) [B1(d)] wr_access GATE (write STRICTER than read): authenticated A on acct-ro (rd=t, wr=f)
--      inserts own sell_ro × buy_ro. #14 PASSES (A owns acct-ro -> both legs resolve), so the
--      wr_access WITH CHECK alone rejects -> 42501.
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_ro, :buy_ro),
  '42501', null,
  '(4b) wr_access GATE [B1(d)]: A holds rd_access but NOT wr_access on acct-ro; #14 passes, so the wr_access WITH CHECK alone rejects the INSERT (42501) — the write policy is stricter than read'
);

-- (4c) [B1(b), LOAD-BEARING] own sell × FOREIGN buy: the WITH CHECK passes on the owned sell leg;
--      only #14 catches the foreign buy. A's RLS hides B's leg -> #14 NULL-safe 'cannot resolve'
--      fires (BEFORE the WITH CHECK). The cross-tenant buy never lands.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_a, :buy_b),
  '%cannot resolve%',
  '(4c) #14 catches FOREIGN BUY [B1(b), load-bearing]: authenticated A''s own sell × B''s buy RAISES ''cannot resolve'' — the WITH CHECK passes on the owned sell; only #14 catches the foreign buy (else B''s basis leaks in)'
);

-- (4e) [defence-in-depth complement to 4d] FOREIGN sell with #14 ENABLED (normal operation): #14
--      ALSO catches a foreign sell ('cannot resolve') before the WITH CHECK.
select throws_like(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,1) $$, :sell_b, :buy_a),
  '%cannot resolve%',
  '(4e) #14 catches FOREIGN SELL (normal operation): authenticated A''s attempt to match B''s sell leg RAISES ''cannot resolve'' — #14 fail-closes on the RLS-invisible foreign leg'
);
select set_config('role', 'postgres', true);

-- (4d) [B1(a)] WITH CHECK INDEPENDENTLY denies a foreign sell — ISOLATE #14 out (030-precedent
--      trigger-disable) so the WITH CHECK is the sole gate, then re-run under authenticated. This
--      proves the migration's "the WITH CHECK fails on a foreign sell leg" defence-in-depth claim.
alter table pfin.lot_match disable trigger lot_match_matched_tenant_security;
select _rls.set_tenant(:'ta'::uuid);
select throws_ok(
  format($$ insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (%s,%s,5,2) $$, :sell_b, :buy_a),
  '42501', null,
  '(4d) WITH CHECK denies FOREIGN SELL [B1(a), #14 isolated-out]: with the #14 trigger disabled, authenticated A''s INSERT of a FOREIGN sell leg is rejected by the wr_access WITH CHECK alone (42501) — the two layers are independent (defence in depth)'
);
select set_config('role', 'postgres', true);
alter table pfin.lot_match enable trigger lot_match_matched_tenant_security;

-- =====================================================================
-- AC5 — two-tenant read isolation over the write-ENABLED table (authenticated).
-- =====================================================================
-- (5a) B reads 0 of A's lot_matches.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.lot_match where sell_trans_id = :sell_a)::bigint, 0::bigint,
  '(5a) two-tenant read isolation: B reads 0 of A''s lot_matches (the 032 rd_access parent-chain SELECT policy still fails closed under the write-enabled table)'
);
select set_config('role', 'postgres', true);
-- (5b) owner-reads-own: A reads its 3 lot_matches for sell_a — (2c) buy_a/seq1 + (3c) buy_a2/seq1
--      (privileged/real seeds) + (4a) buy_a/seq5 (the real authenticated INSERT). NOTE: (4d)'s
--      row is on acct-ro (sell_ro), not sell_a, so it does not count here.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.lot_match where sell_trans_id = :sell_a)::bigint, 3::bigint,
  '(5b) owner-reads-own: A reads its 3 own lot_matches for sell_a via the parent-chain rd_access policy (2c seed + 3c authenticated + 4a authenticated)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC6 — 032 IMMUTABILITY UNBROKEN on the write-open path (Sec B1(e)). authenticated is blocked at
--   the GRANT layer (no UPDATE/DELETE grant); the TRIGGER is the durable gate even with a grant
--   held open (service_role). Attacks lm_id.
-- =====================================================================
-- (6a) authenticated UPDATE -> permission denied at the GRANT layer.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.lot_match set quantity_matched = 999 where id = %s $$, :lm_id),
  '%permission denied for table lot_match%',
  '(6a) immutability [B1(e)]: an authenticated UPDATE is denied at the GRANT layer (no UPDATE grant — write-enablement opened INSERT only)'
);
-- (6b) authenticated DELETE -> permission denied at the GRANT layer.
select throws_like(
  format($$ delete from pfin.lot_match where id = %s $$, :lm_id),
  '%permission denied for table lot_match%',
  '(6b) immutability [B1(e)]: an authenticated DELETE is denied at the GRANT layer (no DELETE grant)'
);
select set_config('role', 'postgres', true);
-- (6c) service_role UPDATE (RLS bypassed, grant held OPEN test-only) STILL blocked by the TRIGGER
--      (the durable gate — the ACL is not the only fence; the 004/031 cross-tier lesson).
grant usage on schema pfin to service_role;
grant select, update on pfin.lot_match to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.lot_match set quantity_matched = 999 where id = %s $$, :lm_id),
  '%is immutable%UPDATE blocked%',
  '(6c) cross-tier immutability [B1(e)]: a service_role UPDATE (RLS bypassed, grant held open) is STILL blocked by the immutability TRIGGER — opening INSERT did not relax the row fence'
);
select set_config('role', 'postgres', true);
-- (6d) TRUNCATE (statement-level; distinct message).
select throws_like(
  'truncate pfin.lot_match',
  '%is immutable%TRUNCATE blocked%',
  '(6d) immutability [B1(e)]: TRUNCATE RAISES (statement-level block_truncate — the lot-matching history cannot be wiped)'
);

select * from finish();
rollback;
