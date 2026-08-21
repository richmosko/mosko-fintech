-- =====================================================================
-- Feature battery — SELF-200 (§2.4.1.e) pending-symbol classification.
--   The DERIVED-READ two-tenant isolation + ever-transacted semantic + the
--   classify UPSERT (ON CONFLICT DO UPDATE) path exercising the EXISTING 022
--   Decision-3 fences (#8 matched-tenant sub_cat + #9 novel global-OR-owned asset).
--   (V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — touches the Decision-3 fence family.)
-- =====================================================================
-- NO MIGRATION IN SELF-200 (F/CTO-ratified derived-view approach): "pending
--   classification" is COMPUTED AT READ TIME (pendingSymbols.ts anti-join over two
--   RLS-scoped selects), never stored. So this battery does NOT re-prove 022's DDL —
--   it proves the two NEW surfaces SELF-200 introduces at the app-query layer, both of
--   which run ENTIRELY under caller-RLS + the 022 triggers:
--     (D) the DERIVED READ: `transacted-securities MINUS classified-assets`, computed
--         over `select security_id from account_trans where security_id is not null`
--         (RLS: account_users rd_access JOIN — account_trans has no own users_id) and
--         `select asset_id from user_asset_category` (RLS: direct-owner). The app does
--         the DISTINCT + set-difference in TS (pendingSymbols.computePendingIds, unit-
--         tested by Backend); the SECURITY property is that BOTH scoped reads are
--         tenant-isolated, so the derived set can never include another tenant's
--         securities or reflect another tenant's classifications. This battery mirrors
--         the anti-join as a single RLS-scoped SQL statement (the RLS scoping is
--         identical — the outer read AND the NOT IN subquery both scope to the caller).
--     (U) the classify WRITE: `INSERT … ON CONFLICT (users_id, asset_id) DO UPDATE SET
--         sub_cat_id = excluded.sub_cat_id` (the exact shape supabase-js `.upsert(…,
--         {onConflict:'users_id,asset_id'})` compiles to). 022's battery exercises the
--         fences via plain INSERT (3b/3c) and plain UPDATE (3d/3e); it does NOT drive
--         the ON CONFLICT DO UPDATE path. This block proves the fences fire on BOTH the
--         INSERT branch AND the DO-UPDATE (re-classify) branch of the upsert.
--
-- BINDS TO (all already on main — SELF-200 authors no DDL):
--   - supabase/migrations/022_user_asset_category.sql — the classify target + fences #8/#9.
--   - supabase/migrations/017_account_trans_investment.sql — account_trans.security_id
--       (the transacted-securities source; nullable → NULL rows = cash, dropped).
--   - supabase/migrations/006_account_trans.sql — account_trans rd_access-JOIN RLS.
--   - supabase/migrations/003_account_and_account_users.sql — the creator-grant trigger
--       (seeds account_users rd/wr on account insert — the JOIN the derived read rides).
--   - supabase/migrations/016_asset_registry.sql — pfin.asset (global-OR-owned).
--   - api/src/lib/server/queries/pendingSymbols.ts — the derived read under test.
--   - api/src/routes/portfolio/classify/+page.server.ts — the classify UPSERT action.
--
-- ┌─ TRIGGER FIRING ORDER (load-bearing for the upsert fence cases — same as 022) ──────┐
-- │ Same-event BEFORE-ROW triggers fire in trigger-NAME ALPHABETICAL order:              │
-- │   user_asset_category_asset (#9)  <  user_asset_category_matched_sub_cat (#8)         │
-- │ so #9 (asset) fires FIRST. To surface #8 the asset must PASS #9 (global/owned); to    │
-- │ surface #9 the asset FAILS #9 first regardless of sub_cat. Built into u2/u3 below.    │
-- │ For ON CONFLICT DO UPDATE the BEFORE INSERT triggers fire for the PROPOSED row first; │
-- │ on conflict the DO UPDATE runs and BEFORE UPDATE triggers fire. Because the app's     │
-- │ upsert sets `sub_cat_id = excluded.sub_cat_id` (the proposed value), a cross-tenant   │
-- │ sub_cat is caught at the BEFORE-INSERT stage of the upsert (u5) — the security        │
-- │ property (upsert re-classify is fenced, fails closed, no mutation) holds either way;  │
-- │ 022 (3d)/(3e) prove the BEFORE-UPDATE fence teeth independently via plain UPDATE.     │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- INVERSION-PROVE (the battery has teeth — a real violation flips it RED):
--   (d1)/(d5) — if account_trans RLS (006 rd_access JOIN) leaked, A's transacted read
--        would include B's disjoint security (g_qqq) → the exact-set assertion RED.
--   (d3)/(d6) — if the classified read (022 uac_select) leaked, or the set-difference
--        composed cross-tenant, the pending set would drift → RED.
--   (d7) — if uac_select leaked, B would see A's classification rows → RED.
--   (u2)/(u3)/(u5) — if fence #8 or #9 were dropped, the cross-tenant upsert would
--        COMMIT instead of raising → throws_like RED (a real cross-tenant write leaks).
--        These are the two-fence inversion proofs asked for at hand-off.
--   (u5v) — if a failed cross-tenant re-classify PARTIALLY applied, the existing row's
--        sub_cat would change → RED (proves fail-closed = no mutation).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27). SELF-200 adds NO
--   migration, NO service_role grant, NO SECURITY DEFINER, NO new cross-tenant FK — it
--   REUSES 022's #8 + #9 (already canonically enumerated + realized). This battery is a
--   coverage EXTENSION for a new access path, not a new §10 or Decision-3 instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. Two tenants with OVERLAPPING (both
--   transact the GLOBAL asset g_voo) and DISJOINT (A→g_spy, B→g_qqq) securities; one
--   security (g_spy) bought THEN sold to net-zero (still ever-transacted). All in a
--   rolled-back txn. Global assets seeded users_id NULL; per-user assets set users_id
--   EXPLICITLY (auth.uid() is NULL under postgres — an omitted users_id lands GLOBAL).
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated;
--   tenant UUIDs + row ids resolve to psql LITERALS via \gset at role=postgres; every
--   _rls.set_tenant is called at role=postgres and each block restores role=postgres
--   before the next. \gset var names are ALL-LOWERCASE. Inline pgTAP assertions run under
--   the tenant context (harness precedent: 017 a1/a2 call lives_ok under authenticated).
--
-- ⟦WIRE-VALIDATE⟧ 022 (+ 003/006/016/017) are on main, so `supabase test db` (directory-
--   mode pg_prove, db-tests.yml) reaches this against the 001→040 reset stack — no
--   pre-apply RED window (contrast the 017/022 batteries authored ahead of apply). plan(21).
--
-- SELF-235 QA ADDITIONS (Block V, appended below the original SELF-200 content unchanged above):
--   (v1)/(v1v) KNOWN-GAP, documented not silently fixed: a same-tenant WRONG-DOMAIN sub_cat_id
--     (cashflow, not asset) IS accepted by the #8 DB fence today — matched-DOMAIN is app-layer
--     only (isAssignableAssetSubCat; taxonomy.test.ts covers it directly, QA-added). If this leg
--     ever goes RED (throws instead of succeeding), someone added DB-level domain enforcement —
--     UPDATE this record alongside that change, do not just delete the leg.
--   (v-embed-1)/(v-embed-2) RLS coverage for the loadSymbols() read SHAPE specifically — the
--     user_asset_category -> user_taxonomy embedded join PostgREST compiles that call to — proven
--     tenant-isolated on BOTH the ids returned (asset_id) and the referenced taxonomy row
--     (sub_cat_id), not just the bare user_asset_category table self200 (d7)/(d8) already cover.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(21);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-A, B owns acct-B (003 creator-grant trigger seeds rd=t/wr=t on each,
--    keyed on new.users_id — this is what lets authenticated A/B read their own
--    account_trans via the 006 rd_access JOIN below).
--  - GLOBAL assets (users_id NULL): g_voo (transacted by BOTH — overlap), g_spy (A only,
--    the net-zero ever-transacted case), g_qqq (B only — the cross-tenant leak probe).
--  - a_asset OWNED BY A, b_asset OWNED BY B (users_id EXPLICIT) — the upsert #9 targets.
--  - user_taxonomy asset-domain Sub-Cats: a_sub, a_sub2 (A — a_sub2 the re-classify
--    target); b_sub (B — the cross-tenant #8 target).
--  - account_trans security-legs are GLOBAL assets, so 017's #7 fence passes trivially
--    at seed time; the cash row (security_id NULL) proves the NULL-drop in the derived read.
--  - INITIAL classifications: A classifies g_voo; B classifies g_qqq. So the derived
--    pending sets are: A = {g_spy} (g_voo classified-out, g_spy pending, cash dropped);
--    B = {g_voo} (g_qqq classified-out).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-A', 'depository', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-B', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'VOO', 'Vanguard S&P 500') returning asset_id as g_voo \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'SPY', 'SPDR S&P 500') returning asset_id as g_spy \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'QQQ', 'Invesco QQQ') returning asset_id as g_qqq \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A owned asset') returning asset_id as a_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'tb', 'collectible', 'manual_valuation', 'B owned asset') returning asset_id as b_asset \gset

insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Brokerage', 'US Equity', 'asset') returning id as a_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Brokerage', 'Index Funds', 'asset') returning id as a_sub2 \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'tb', 'Brokerage', 'US Equity', 'asset') returning id as b_sub \gset
-- SELF-235 QA addition (Block V, below), RE-DERIVED POST-084: A's OWN posting-prototype
--   row (was cashflow-domain user_taxonomy pre-split) — the (v1) KNOWN-GAP target, which
--   the split closes as a side effect of the FK re-target rather than via the domain-
--   enforcement mechanism this note originally anticipated (see (v1) below for the flip).
--   'Revenue' is a legitimate posting_prototype cat (Decision 4's enum).
insert into pfin.posting_prototype (users_id, cat, sub_cat)
  values (:'ta', 'Revenue', 'Salary') returning id as a_cf_sub \gset

-- account_trans security-legs (privileged; 017 #7 fence passes — all global securities).
--  A: buys g_voo; buys g_spy THEN sells g_spy to net-zero (2 rows, same security → proves
--     DISTINCT + ever-transacted); one pure-cash row (security NULL → dropped by the read).
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:accta, '2026-03-01', -1000, 10, :g_voo, 'a-voo-buy');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:accta, '2026-03-02', -500, 5, :g_spy, 'a-spy-buy');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:accta, '2026-03-09', 520, -5, :g_spy, 'a-spy-sell');   -- sold to net-zero, still ever-transacted
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:accta, '2026-03-10', -25, 0, 'a-cash');                -- pure-cash (security_id NULL) → dropped
--  B: buys g_voo (overlap) + g_qqq (B-disjoint — the cross-tenant leak probe).
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:acctb, '2026-03-03', -800, 8, :g_voo, 'b-voo-buy');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, vendor)
  values (:acctb, '2026-03-04', -300, 3, :g_qqq, 'b-qqq-buy');

-- INITIAL classifications (privileged; both fences pass — global asset + own Sub-Cat).
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (:'ta', :g_voo, :a_sub);
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (:'tb', :g_qqq, :b_sub);

-- =====================================================================
-- BLOCK D — the DERIVED READ, two-tenant. (D1–D4 under A; D5–D6 under B; D7–D8 verbs.)
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (d1) transacted-securities read (select #1) under A = {g_spy, g_voo}, DISTINCT, NULL-
--      dropped, and EXCLUDING B's g_qqq — the RLS (006 rd_access JOIN) isolation of the
--      transacted source. g_spy appears once despite 2 rows (buy+sell) → DISTINCT proven.
select is(
  (select array_agg(distinct security_id order by security_id)
     from pfin.account_trans where security_id is not null),
  array[:g_voo, :g_spy]::bigint[],
  '(d1) transacted-securities read under A = {g_voo, g_spy}: DISTINCT (g_spy 2 rows→1), NULL-security dropped (cash row absent), and B''s g_qqq NOT present — account_trans RLS isolates select #1 (array ordered by security_id asc; g_voo seeded before g_spy)'
);

-- (d2) classified read (select #2) under A = {g_voo}: only A''s own classification, NOT
--      B''s g_qqq classification — 022 uac_select direct-owner isolation of select #2.
select is(
  (select array_agg(distinct asset_id order by asset_id) from pfin.user_asset_category),
  array[:g_voo]::bigint[],
  '(d2) classified read under A = {g_voo}: only A''s own classification; B''s g_qqq classification NOT visible — user_asset_category RLS isolates select #2'
);

-- (d3) COMPOSED derived pending under A = {g_spy}: transacted MINUS classified, computed
--      exactly as the app (both the outer read AND the NOT IN subquery scope to A). g_voo
--      classified-out; g_spy pending; cash dropped; B''s g_qqq never enters.
select is(
  (select array_agg(distinct t.security_id order by t.security_id)
     from pfin.account_trans t
    where t.security_id is not null
      and t.security_id not in (select c.asset_id from pfin.user_asset_category c)),
  array[:g_spy]::bigint[],
  '(d3) derived pending set under A = {g_spy}: transacted({g_spy,g_voo}) MINUS classified({g_voo}); the end-to-end RLS-scoped anti-join never includes B''s securities or reflects B''s classifications'
);

-- (d4) ever-transacted semantic (deliverable #5): g_spy was bought THEN sold to net-zero,
--      yet it is STILL pending for A (no quantity/net-position filter) — mirrors Backend''s
--      pure-logic test, end-to-end through RLS.
select is(
  (select :g_spy = any(
     select distinct t.security_id from pfin.account_trans t
      where t.security_id is not null
        and t.security_id not in (select c.asset_id from pfin.user_asset_category c))),
  true,
  '(d4) ever-transacted (not net-position): a security bought then SOLD to net-zero (g_spy) is STILL pending for A until classified — no quantity filter, end-to-end through RLS'
);
select set_config('role', 'postgres', true);

-- BLOCK D (under B) — reverse-direction isolation: B never sees A''s g_spy.
select _rls.set_tenant(:'tb'::uuid);

-- (d5) transacted read under B = {g_voo, g_qqq}, EXCLUDING A''s g_spy — select #1 isolation
--      proven in the OTHER tenant direction (no A→B leak either).
select is(
  (select array_agg(distinct security_id order by security_id)
     from pfin.account_trans where security_id is not null),
  array[:g_voo, :g_qqq]::bigint[],
  '(d5) transacted read under B = {g_voo, g_qqq}: A''s disjoint g_spy NOT present — account_trans RLS isolates select #1 in the B→A direction too'
);

-- (d6) COMPOSED derived pending under B = {g_voo}: transacted({g_voo,g_qqq}) MINUS
--      classified({g_qqq}); disjoint from A''s pending and never includes A''s g_spy.
select is(
  (select array_agg(distinct t.security_id order by t.security_id)
     from pfin.account_trans t
    where t.security_id is not null
      and t.security_id not in (select c.asset_id from pfin.user_asset_category c)),
  array[:g_voo]::bigint[],
  '(d6) derived pending set under B = {g_voo}: transacted({g_voo,g_qqq}) MINUS classified({g_qqq}); disjoint from A''s pending — the derived read is tenant-isolated in both directions'
);
select set_config('role', 'postgres', true);

-- (d7) cross-tenant read fails closed: B sees 0 of A''s user_asset_category rows (the
--      classified-source RLS the derived read rides). Reusable verb.
select _rls.expect_cross_tenant_read_empty('pfin.user_asset_category'::regclass, :'ta'::uuid, :'tb'::uuid);

-- (d8) owner reads own: A sees exactly its 1 classification (guards an over-restrictive
--      policy that would spuriously empty the classified set).
select _rls.expect_owner_can_read('pfin.user_asset_category'::regclass, :'ta'::uuid, 1::bigint);

-- =====================================================================
-- BLOCK U — the classify UPSERT (ON CONFLICT DO UPDATE) path, under authenticated A.
--   Raw SQL mirrors supabase-js `.upsert({users_id,asset_id,sub_cat_id},
--   {onConflict:'users_id,asset_id'}).select('asset_id')` → the DB path the action drives.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (u1) INSERT branch PASS: A upserts its OWN asset with its OWN Sub-Cat; (A, a_asset) does
--      not yet exist → INSERT branch; both fences pass. This is the classify happy path.
select lives_ok(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :a_asset, :a_sub),
  '(u1) upsert INSERT branch PASS: A classifies its OWN asset with its OWN Sub-Cat via ON CONFLICT DO UPDATE — no conflict yet, both fences accept (classify happy path)'
);

-- (u1v) the row landed carrying a_sub.
select is(
  (select sub_cat_id from pfin.user_asset_category where users_id = :'ta' and asset_id = :a_asset)::bigint,
  :a_sub::bigint,
  '(u1v) upsert INSERT landed: (A, a_asset) now carries a_sub'
);

-- (u2) upsert INSERT branch, #8 RAISE: A upserts a GLOBAL asset (passes #9) with B''s
--      Sub-Cat → fn_user_asset_category_matched_sub_cat RAISES. Cross-tenant classify blocked.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :g_spy, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(u2) upsert #8 RAISE: A classifies a global asset with B''s Sub-Cat via upsert → #8 fence raises (cross-tenant taxonomy tagging blocked on the upsert INSERT branch — a real violation, not a silent pass)'
);

-- (u3) upsert INSERT branch, #9 RAISE: A upserts B''s per-user asset (fails #9, fires first)
--      with A''s own Sub-Cat → fn_user_asset_category_asset RAISES. Cross-tenant asset blocked.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :b_asset, :a_sub),
  'cross-tenant asset rejected%',
  '(u3) upsert #9 RAISE: A references B''s per-user asset via upsert → #9 novel fence raises (asset neither global nor A-owned — cross-tenant asset reference blocked on the upsert path)'
);

-- (u4) DO UPDATE branch PASS (RE-CLASSIFY): A upserts (a_asset) again with ANOTHER of its
--      OWN Sub-Cats → (A, a_asset) conflicts → DO UPDATE fires → both fences pass on the
--      UPDATE. This is the ON CONFLICT DO UPDATE branch 022''s battery does not exercise.
select lives_ok(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :a_asset, :a_sub2),
  '(u4) upsert DO UPDATE branch PASS: A re-classifies (a_asset) to another of its OWN Sub-Cats via ON CONFLICT DO UPDATE — the conflict/re-classify path passes both fences (idempotent classify)'
);

-- (u4v-count) the re-classify did NOT double-insert — still exactly one (A, a_asset) row.
select is(
  (select count(*) from pfin.user_asset_category where users_id = :'ta' and asset_id = :a_asset)::bigint,
  1::bigint,
  '(u4v-count) upsert re-classify: still exactly ONE (A, a_asset) row — ON CONFLICT (users_id, asset_id) updated in place, no double-insert (unique holds)'
);

-- (u4v-subcat) the DO UPDATE actually applied — (A, a_asset) now carries a_sub2.
select is(
  (select sub_cat_id from pfin.user_asset_category where users_id = :'ta' and asset_id = :a_asset)::bigint,
  :a_sub2::bigint,
  '(u4v-subcat) upsert DO UPDATE applied: (A, a_asset) re-classified from a_sub to a_sub2'
);

-- (u5) DO-UPDATE-path cross-tenant RE-CLASSIFY, #8 RAISE: A tries to re-classify the
--      already-classified (a_asset) to B''s Sub-Cat via upsert → #8 raises. A user cannot
--      pivot an existing classification to another tenant''s Sub-Cat through the upsert.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :a_asset, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(u5) upsert re-classify #8 RAISE: A cannot pivot an EXISTING classification (a_asset) to B''s Sub-Cat via upsert → #8 fence raises (the conflict/re-classify path stays fenced, fails closed)'
);

-- (u5v) fail-closed = NO mutation: after the rejected cross-tenant re-classify, (A, a_asset)
--      STILL carries a_sub2 (the failed upsert did not partially apply).
select is(
  (select sub_cat_id from pfin.user_asset_category where users_id = :'ta' and asset_id = :a_asset)::bigint,
  :a_sub2::bigint,
  '(u5v) fails closed = no mutation: after the rejected cross-tenant re-classify, (A, a_asset) is UNCHANGED (still a_sub2) — the fence raised before any write landed'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK V — SELF-235 QA additions. (v1)/(v1v) the domain-mismatch KNOWN-GAP; (v-embed-1)/
--   (v-embed-2) RLS coverage for loadSymbols()'s embedded-join read shape. Runs under A;
--   reuses g_spy (still unclassified after Blocks D/U — nothing later re-reads its prior state).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (v1) POST-084: was lives_ok (KNOWN-GAP, domain-blind), now throws_like. a_cf_sub no
--   longer resolves in user_taxonomy at all — it moved to posting_prototype under the
--   same id (ADR-058 Decision 1/2). The KNOWN-GAP this leg documented closes as a side
--   effect of the FK re-target, not via the domain-enforcement mechanism the ORIGINAL
--   comment anticipated ("if DB-level domain enforcement is ever added, update lives_ok
--   -> throws") — same outcome, different cause: 022's own #8 fence
--   (fn_user_asset_category_matched_sub_cat, UNCHANGED by 084) does its own NOT-EXISTS
--   resolving read into user_taxonomy, finds nothing, and RAISES its existing message.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
              values (%L, %s, %s)
            on conflict (users_id, asset_id) do update set sub_cat_id = excluded.sub_cat_id $$,
          :'ta', :g_spy, :a_cf_sub),
  '%is not a taxonomy row owned by users_id%',
  '(v1) POST-084: A''s posting-prototype row (a_cf_sub) no longer resolves in user_taxonomy at all -> REJECTED by #8''s own unchanged fence code. The KNOWN-GAP this leg documented closes as a side effect of the FK re-target, not via the domain-enforcement mechanism the original comment anticipated -- same outcome, different cause'
);
-- (v1v) POST-084: was a value-check (row landed carrying a_cf_sub); now an atomicity
--   check (the row never lands -- no orphan (asset_id, sub_cat_id) pair after the
--   rejected insert). g_spy stays unclassified.
select is(
  (select count(*) from pfin.user_asset_category where users_id = :'ta' and asset_id = :g_spy)::bigint,
  0::bigint,
  '(v1v) POST-084 atomicity: after (v1)''s rejected insert, g_spy has NO (users_id, sub_cat_id) row for A -- the failed attempt landed nothing'
);

-- (v-embed-1) RLS coverage for the loadSymbols() read SHAPE, RE-DERIVED POST-084: the
--   user_asset_category -> user_taxonomy embedded join. Under A, the joined set of
--   (asset_id, sub_cat_id) pairs is EXACTLY {g_voo/a_sub, a_asset/a_sub2} — the THIRD
--   pair (g_spy/a_cf_sub) no longer exists: (v1) proved that insert is REJECTED post-084,
--   so g_spy stays unclassified and never enters this joined set at all. B's (g_qqq,
--   b_sub) pair is absent, proving the embed doesn't leak B's junction row OR B's
--   taxonomy label through the join.
-- (asset_id,sub_cat_id) pairs are encoded as "assetid:subcatid" TEXT (not a composite/record
-- comparison — PostgreSQL anonymous record types have no default array equality/ordering
-- operator, so this stays in plain bigint/text domain, same idiom as self209's array_agg(x order
-- by x) pattern). Pairing integrity is preserved because each element encodes BOTH fields
-- together — an array of two SEPARATE sorted id-lists could accidentally validate a scrambled
-- pairing if both lists independently happened to sort the same way.
-- ⚠ CORRECTED (Architect, SELF-330 cross-battery finding, MEASURED): the LEFT side orders by
-- `c.asset_id` — a BIGINT, numeric order. The RIGHT side used to order the encoded TEXT `x`
-- lexicographically (`order by x`), which agrees with numeric order only while every asset_id in
-- play has the SAME digit count — '99:229' < '102:230' numerically but '102:230' < '99:229'
-- lexicographically ('1' < '9'). Both sides ALWAYS had single- or equal-digit ids in every prior
-- run, so this was latent, not fixed: SELF-330's own battery (086, file-order before this one)
-- advances pfin.asset's identity sequence — non-transactional, so a per-file rollback does NOT
-- rewind it — and pushed THIS file's ids across the two-digit boundary for the first time,
-- flipping (v-embed-1) RED on a fresh CI database (3-for-3 reproduced; a REUSED scratch DB masked
-- it, because a prior suite pass had already advanced the sequence past the boundary and the
-- comparison degenerated to "always sorted the same way twice"). Fixed by making the RIGHT side
-- order by the SAME key as the left: the numeric asset_id, extracted back out of the encoded text
-- via split_part rather than changing the left side's own (correct) ordering.
select is(
  (select array_agg(c.asset_id::text || ':' || c.sub_cat_id::text order by c.asset_id)
     from pfin.user_asset_category c join pfin.user_taxonomy t on t.id = c.sub_cat_id),
  (select array_agg(x order by split_part(x, ':', 1)::bigint) from (
     values (:g_voo::text || ':' || :a_sub::text),
            (:a_asset::text || ':' || :a_sub2::text)
   ) v(x)),
  '(v-embed-1) loadSymbols() embed-join shape under A = EXACTLY {(g_voo,a_sub), (a_asset,a_sub2)} POST-084 — g_spy/a_cf_sub is GONE (that insert is rejected, see (v1)); B''s (g_qqq,b_sub) pair is NOT present; the join leaks neither B''s junction row nor B''s taxonomy label'
);
select set_config('role', 'postgres', true);

-- (v-embed-2) non-vacuous companion, reverse direction: under B the SAME joined shape is
--   EXACTLY {(g_qqq, b_sub)} — unaffected by every write A made in this block, and does not
--   include either of A''s two remaining pairs.
-- ⚠ NOT a second instance of (v-embed-1)'s sort-key mismatch TODAY — the right side is a
-- single-element array[...], so there is no ordering to disagree about. It WOULD become one the
-- moment a second element is added here: match (v-embed-1)'s fix (order by the numeric key, not
-- the encoded text) rather than reintroducing the lexicographic form.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select array_agg(c.asset_id::text || ':' || c.sub_cat_id::text order by c.asset_id)
     from pfin.user_asset_category c join pfin.user_taxonomy t on t.id = c.sub_cat_id),
  array[:g_qqq::text || ':' || :b_sub::text],
  '(v-embed-2) loadSymbols() embed-join shape under B = EXACTLY {(g_qqq,b_sub)} — neither of A''s two remaining pairs leak through the B-side join'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
