-- =====================================================================
-- SELF-244 — §2.2 V1.2 CLOSE-GATE (consolidated multi-function cross-tenant
--   RLS battery). Team-lead-relayed AC package (Linear SELF-244, verbatim
--   cross-checked against team-lead's relay 2026-08-20 — no drift found).
-- =====================================================================
-- SEAM-ONLY. Authors NO schema. Proves the §2.2 read/write surface holds closed AS A
-- WHOLE, under ONE shared multi-tenant fixture, exercised together — which no single
-- per-migration battery does. Composes already-green per-migration batteries for the
-- deep per-function proofs; adds only the NET-NEW seam + the AC2/AC3 scope-aggregation
-- legs neither per-migration battery makes on its own. Shape mirrors self228_v1_1_close_
-- gate.sql (the explicit precedent named at dispatch) — same block letters (A posture /
-- B signature / C isolation / D scope-aggregation), plus a new BLOCK E for the
-- planning_target read+write seam (AC4/AC5), which self228 had no counterpart for.
--
-- Ratified AC coverage (verbatim mapping):
--   AC1 — coverage inventory across SELF-235/236/237/238/240/242/(325). COMPOSED —
--         no new SQL surface beyond what's cited below. Two flagged items, recorded
--         here (not silently worked around):
--         · SELF-236 retired at 048 (account.sub_cat_id column + its trigger + the
--           7-arg fn_create_manual_account param all dropped) — N/A, nothing to test.
--         · SELF-325 (236's successor) is UNSHIPPED as of 2026-08-20 — Linear status
--           Backlog, no PR, no migration. F/CTO's multi-asset design ruling (2026-08-16)
--           fixed the SHAPE but nothing has landed. This gate does NOT invent coverage
--           for an unshipped surface. Re-check before V1.2 milestone-close.
--   AC2/AC3 — "the three allocation functions": resolved LIVE (catalog query, not a
--         carried draft count) to fn_subcat_market_value + fn_subcat_contributors +
--         fn_holdings_as_of (team-lead ruling: include fn_holdings_as_of as the third,
--         self228's own precedent already treats a shared-substrate function as a
--         first-class close-gate member when the surface depends on it directly).
--         fn_holdings_as_of gets BLOCK A/B/C treatment only (posture/signature/isolation)
--         — it has no sub_cat_id to scope-aggregate against, so BLOCK D does not apply
--         to it, matching self228's own asymmetric D-block precedent (not every function
--         in that gate's isolation blocks got a D-block leg either).
--         BLOCK D structural note: fn_subcat_market_value's output carries NO account_id
--         (it is pre-aggregated across accounts, unlike self228's fn_account_unrealized_gl)
--         — so AC3's SQL-layer scope filter cannot join the FUNCTION's own output to
--         account.scope the way self228 did. D1/D2 instead independently reconstruct the
--         dollar total from the SUBSTRATE tables (account_trans × eod_price, joined to
--         account.scope) and tie the partition back to the function's own bare-call total
--         — a deliberate divergence from self228's shape, recorded here so it reads as a
--         decision, not a drift. fn_subcat_contributors DOES carry account_id in its
--         output, so its D-block (D3) follows self228's D3/D4/D5 join-the-output shape
--         verbatim.
--   AC4 — planning_target RLS read isolation, exercised together with the allocation
--         functions under this gate's OWN shared fixture (the seam; 074_planning_target_
--         rls.sql already proves the mechanism at the per-migration level — COMPOSED,
--         not re-derived). BLOCK E1.
--   AC5 — forged user_taxonomy_id injection rejected. AC's literal wording ("naming
--         another tenant's seed") is 074's own LEG 1 (unresolvable) shape, NOT leg 2
--         (cross-tenant) — RLS on user_taxonomy hides the foreign row from the fence's
--         own SELECT before leg 2's owner-mismatch compare is ever reached (074's own
--         CONTRACT box; QA finding on that file already corrected the "leg 2 only" framing
--         for the ownership-forge shape). BLOCK E2 exercises leg 1 (the AC's literal
--         shape); BLOCK E3 additionally exercises leg 2 (ownership-forge: own real
--         sub_cat_id + forged users_id) as defense-in-depth, citing 074's own (L2a) as the
--         precedent this leg re-exercises on this gate's fixture identities. DB-layer half
--         only — the Zod `.strict()` half is Backend's app-route-layer leg, no HTTP
--         surface in a SQL battery. AC5's endpoint wording says "POST/PATCH"; grep of
--         api/src/routes/api/settings/planning-target/+server.ts confirms only POST
--         (upsert) and DELETE (unset) exist, no PATCH — Linear's own AC text, not a
--         paraphrase error (verified independently by Backend-2 and QA); the real surface
--         is POST/DELETE per the SELF-242 unset-is-DELETE ruling, cited not duplicated
--         (Backend's existing planning-target.rt23-adversarial.server.test.ts and
--         planning-target.server.test.ts already cover it at the app layer).
--   AC6 — Sec joint-review. Nothing authored here; procedural. Draft-ready signal fires
--         when this file is green.
--   AC7 — forward-fence enumeration, names read LIVE from the tree, not carried
--         provisional: `022` #8 = fn_user_asset_category_matched_sub_cat, `022` #9 =
--         fn_user_asset_category_asset, SELF-324 substrate (was "NAME PROVISIONAL") =
--         fn_planning_target_matched_sub_cat / trigger planning_target_matched_sub_cat,
--         both on migration 074. Declarative existence/posture/trigger-enabled proof —
--         BLOCK A3 (a behavioural probe alone cannot prove a trigger's mere EXISTENCE,
--         only that whatever fires first refuses the write; self228's own DESIGN.md §9
--         discipline).
--
--   The two SELF-243-arc items booked onto this issue (§2.2.3 live-venue tenant-isolation
--   counterpart; io-level null-arm coverage on both surfaces) are NOT in this file — the
--   former is a Vitest/PostgREST file (api/src/lib/server/queries/usEquityAllocation.
--   tenant-isolation.server.test.ts), the latter was ruled Backend's files (one-owner-
--   per-file; team-lead overruled QA's initial claim on nonReAllocation.io.test.ts /
--   usEquityAllocation.io.test.ts). Cited from this file's own coverage inventory (AC1
--   note above), not duplicated here.
--
-- ┌─ COMPOSE (verified green by the full suite; this file re-proves the cross-cutting seam) ─┐
-- │ self200_pending_symbol_classification_rls.sql (SELF-235) · 076_fn_subcat_market_value_    │
-- │ rls.sql (SELF-237, latest DEFINITION 084 — signature/posture unchanged 076→081→084) ·       │
-- │ 086_fn_subcat_contributors_rls.sql (SELF-330) · 074_planning_target_rls.sql (AC4/AC5        │
-- │ mechanism proof, all raise legs) · 019_eod_price_and_valuation.sql's own battery for         │
-- │ fn_holdings_as_of. App-layer (SELF-238/240/242) is out of this SQL battery's scope by        │
-- │ construction — Vitest, not pgTAP. Plan counts are a derived, unwatched property — read       │
-- │ each file's own plan() line live, never transcribe it here (Sec F3).                         │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- Ledgers all FLAT (SEAM-only, no schema authored): §10 catalogued-instance ledger (ADR-011
-- Decision 4) and the SECURITY DEFINER allowlist (ADR-011 Decision 9) are both untouched — all
-- six functions here (3 allocation + 3 fence triggers) are INVOKER. Decision-3 family
-- unchanged. Read ADR-011 Decisions 4/9 live at point of use — this file moves no ledger and
-- states no count of its own.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c();
-- NO PII / NO real account numbers (SD-15) / NO production data. All seeds PRIVILEGED
-- (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY (auth.uid() is NULL under
-- postgres); functions/writes invoked ONLY under the authenticated tenant contexts under test.
-- All in a rolled-back txn — NO INSERT/UPDATE/DELETE against real tenant data; every row this
-- file writes carries one of the three fixed synthetic tenant UUIDs.
--
-- Sec joint-review-mandatory (financial calculation + multi-tenant isolation + Lock-14
-- planning_target write surface). This file must be GREEN before Sec review, and the PR must
-- not merge before Sec's verdict (AC6).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 35: A 5 (2 posture set_eq + 3 AC7 trigger-shape legs) + B 4 (3 positive-pin
-- signature legs + 1 non-vacuous three-function match) + C 12 (3 functions x 4 legs:
-- own-value / non-vacuity-or-probe / zero-owner-closed / cross-tenant probe) + D 8
-- (D0 fixture pin + D1 + D2a/b/c + D3a/b/c) + E 6 (E1 x3 read isolation + E2 leg-1 +
-- E3 leg-2 + E4 non-vacuous control). Recorded so a silent plan-edit shows as an
-- arithmetic change.
select plan(35);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');
insert into pfin.user_settings (users_id, mfa_policy) values (:'ta', 'none'), (:'tb', 'none');
-- tenant_c deliberately gets NO user_settings row (062 lazy-provision precedent) — the
-- zero-owner legs below prove fail-closed even without one.

-- =====================================================================
-- FIXTURE — global securities, tenant-A taxonomy (3 scopes, 1 unused control sub_cat for
--   the BLOCK E4 non-vacuous write control), tenant-B taxonomy/control, tenant-A/B
--   investment accounts (one security each, funded to NET EXACTLY ZERO cash — checkpoint
--   balance = price = the sole buy's amount, mirrors 086's funding discipline so each
--   sub_cat's/account's market_value is the security value alone, no stray Unsorted-cash
--   row to contaminate the AC2(b) bare-total comparison), tenant-C empty account
--   (fail-closed control), and one planning_target row per tenant (AC4/AC5 substrate).
-- =====================================================================
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCP244','Sec Personal-scope (a_pers)') returning asset_id as secp \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCT244','Sec Trust-scope (a_trust)') returning asset_id as sect \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCU244','Sec Business-scope (a_biz)') returning asset_id as secbu \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCB244','Sec tenant-B control') returning asset_id as secb \gset

insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:secp,'2026-08-01','market_feed',150.00),
  (:sect,'2026-08-01','market_feed',225.00),
  (:secbu,'2026-08-01','market_feed',300.00),
  (:secb,'2026-08-01','market_feed',90.00);

insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Marketable Securities','US-06-Financials','asset') returning id as a_eq \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Cash','CD','asset') returning id as a_cd \gset
-- a_cd deliberately carries NO user_asset_category junction row anywhere in this file —
-- it exists ONLY as BLOCK E4's non-vacuous write-control target, unrelated to any dollar
-- total this gate asserts.
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'tb','Marketable Securities','US-06-Financials','asset') returning id as b_eq \gset

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-pers-244','investment','personal','taxable') returning account_id as a_pers \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_pers, 150.00, 'USD', '2026-08-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_pers,'2026-08-01',-150.00,1,:secp,150.00,'standard','buy-p');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-trust-244','investment','trust','taxable') returning account_id as a_trust \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_trust, 225.00, 'USD', '2026-08-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_trust,'2026-08-01',-225.00,1,:sect,225.00,'standard','buy-t');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-biz-244','investment','business','taxable') returning account_id as a_biz \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_biz, 300.00, 'USD', '2026-08-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_biz,'2026-08-01',-300.00,1,:secbu,300.00,'standard','buy-u');

insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', :secp, :a_eq),
  (:'ta', :sect, :a_eq),
  (:'ta', :secbu, :a_eq);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-inv-244','investment','household','taxable') returning account_id as b_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_inv, 90.00, 'USD', '2026-08-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:b_inv,'2026-08-01',-90.00,1,:secb,90.00,'standard','buy-b');
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'tb', :secb, :b_eq);

-- TENANT C — empty (fail-closed control). No account/holdings/taxonomy at all.

insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values
  (:'ta', :a_eq, 60.00);
insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values
  (:'tb', :b_eq, 40.00);

-- =====================================================================
-- BLOCK A — AC5(posture)/AC7: SECURITY INVOKER for the 3 allocation functions AND the
--   3 fence trigger functions, plus AC7's structural trigger-existence/shape proof.
-- =====================================================================
select set_eq(
  $$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.prosecdef = false
         and p.proname in ('fn_subcat_market_value','fn_subcat_contributors','fn_holdings_as_of') $$,
  $$ values ('fn_subcat_market_value'::text), ('fn_subcat_contributors'), ('fn_holdings_as_of') $$,
  '(A1) all THREE §2.2 allocation functions are SECURITY INVOKER (prosecdef=false) — execute under the caller''s authenticated identity'
);
select set_eq(
  $$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.prosecdef = false
         and p.proname in ('fn_user_asset_category_matched_sub_cat','fn_user_asset_category_asset',
                            'fn_planning_target_matched_sub_cat') $$,
  $$ values ('fn_user_asset_category_matched_sub_cat'::text), ('fn_user_asset_category_asset'),
            ('fn_planning_target_matched_sub_cat') $$,
  '(A2) all THREE §2.2 fence trigger functions (022 #8/#9, SELF-324/074) are SECURITY INVOKER too — no DEFINER escalation on any forward fence'
);
select ok(
  (select tgenabled = 'O' and (tgtype & 2) <> 0 and (tgtype & 4) <> 0 and (tgtype & 16) <> 0 and (tgtype & 1) <> 0
     from pg_trigger where tgname = 'planning_target_matched_sub_cat' and tgrelid = 'pfin.planning_target'::regclass),
  '(A3a) AC7: trigger planning_target_matched_sub_cat exists on pfin.planning_target, ENABLED, fires BEFORE INSERT OR UPDATE FOR EACH ROW — the SELF-324 substrate fence (074), name resolved live not carried provisional'
);
select ok(
  (select tgenabled = 'O' and (tgtype & 2) <> 0 and (tgtype & 4) <> 0 and (tgtype & 16) <> 0 and (tgtype & 1) <> 0
     from pg_trigger where tgname = 'user_asset_category_matched_sub_cat' and tgrelid = 'pfin.user_asset_category'::regclass),
  '(A3b) AC7: trigger user_asset_category_matched_sub_cat (022 canonical #8) exists on pfin.user_asset_category, ENABLED, fires BEFORE INSERT OR UPDATE FOR EACH ROW'
);
select ok(
  (select tgenabled = 'O' and (tgtype & 2) <> 0 and (tgtype & 4) <> 0 and (tgtype & 16) <> 0 and (tgtype & 1) <> 0
     from pg_trigger where tgname = 'user_asset_category_asset' and tgrelid = 'pfin.user_asset_category'::regclass),
  '(A3c) AC7: trigger user_asset_category_asset (022 canonical #9) exists on pfin.user_asset_category, ENABLED, fires BEFORE INSERT OR UPDATE FOR EACH ROW'
);

-- =====================================================================
-- BLOCK B — AC2(a): full-household-by-construction, SIGNATURE level. POSITIVE PIN
--   (Sec F1 shape, self228 B1 precedent).
-- =====================================================================
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_subcat_market_value'),
  array['p_as_of', 'p_include_real_estate']::text[],
  '(B1) fn_subcat_market_value IN-argument vector = {p_as_of,p_include_real_estate} exactly — no scope/tenant/household parameter'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_subcat_contributors'),
  array['p_as_of', 'p_include_real_estate']::text[],
  '(B2) fn_subcat_contributors IN-argument vector = {p_as_of,p_include_real_estate} exactly'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_holdings_as_of'),
  array['p_as_of']::text[],
  '(B3) fn_holdings_as_of IN-argument vector = {p_as_of} exactly — no scope/tenant/household parameter'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin'
       and p.proname in ('fn_subcat_market_value','fn_subcat_contributors','fn_holdings_as_of')),
  3,
  '(B4) non-vacuous companion: the three-name IN-list resolves to EXACTLY 3 live pfin functions — (A1)/(B1-3) are not silently narrowed by a typo''d name nor inflated by an unexpected overload'
);

-- =====================================================================
-- BLOCK C — AC1: per-function two-tenant isolation, non-vacuously, + cross-tenant
--   parameter/value probing on all three functions.
-- =====================================================================

-- --- C1: pfin.fn_subcat_market_value(p_as_of, p_include_real_estate) [076/081/084] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-08-01') where sub_cat_id = :a_eq),
  675.00::numeric,
  '(C1a) fn_subcat_market_value: A''s a_eq market_value = 675 (150+225+300 across 3 scoped accounts) — reflects ONLY tenant-A rows'
);
select ok(
  not exists (select 1 from pfin.fn_subcat_market_value('2026-08-01') where market_value = 90.00),
  '(C1b) PARAMETER-PROBE: under tenant A auth, no returned row carries tenant B''s known control value (90) — a broken tenant predicate could not serve both (C1a) and B''s own value off the identical as_of'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-08-01') where sub_cat_id = :b_eq),
  90.00::numeric,
  '(C1c) NON-VACUITY (Sec F2): the IDENTICAL as_of under tenant B returns 90, not 675 — A and B hold DIFFERENT values, so a broken predicate cannot produce both answers'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_subcat_market_value('2026-08-01')),
  0,
  '(C1d) fn_subcat_market_value: tenant C (zero accounts) fails closed — ZERO rows, never an error, never another tenant''s data'
);
select set_config('role', 'postgres', true);

-- --- C2: pfin.fn_subcat_contributors(p_as_of, p_include_real_estate) [086/SELF-330] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(distinct account_id)::int from pfin.fn_subcat_contributors('2026-08-01') where sub_cat_id = :a_eq),
  3,
  '(C2a) fn_subcat_contributors: A''s a_eq has EXACTLY 3 distinct contributing accounts — reflects ONLY tenant-A rows'
);
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-08-01') where account_id = :b_inv),
  '(C2b) PARAMETER-PROBE: under tenant A auth, no returned (sub_cat_id, account_id) pair names tenant B''s known account_id (:b_inv) — no cross-tenant identifier leak, not just no cross-tenant value leak'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(distinct account_id)::int from pfin.fn_subcat_contributors('2026-08-01') where sub_cat_id = :b_eq),
  1,
  '(C2c) NON-VACUITY: the IDENTICAL as_of under tenant B returns 1 contributing account, not 3'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_subcat_contributors('2026-08-01')),
  0,
  '(C2d) fn_subcat_contributors: tenant C fails closed — ZERO rows'
);
select set_config('role', 'postgres', true);

-- --- C3: pfin.fn_holdings_as_of(p_as_of) [019; shared NAV substrate] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_holdings_as_of('2026-08-01')),
  array[:a_pers, :a_trust, :a_biz]::bigint[],
  '(C3a) fn_holdings_as_of: A''s holdings span EXACTLY its 3 accounts (a_pers,a_trust,a_biz) — reflects ONLY tenant-A rows'
);
select ok(
  not exists (select 1 from pfin.fn_holdings_as_of('2026-08-01') where account_id = :b_inv),
  '(C3b) PARAMETER-PROBE: under tenant A auth, no returned row names tenant B''s known account_id (:b_inv)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select array_agg(account_id) from pfin.fn_holdings_as_of('2026-08-01')),
  array[:b_inv]::bigint[],
  '(C3c) NON-VACUITY: the IDENTICAL as_of under tenant B returns EXACTLY {b_inv}, not A''s 3 accounts'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_holdings_as_of('2026-08-01')),
  0,
  '(C3d) fn_holdings_as_of: tenant C fails closed — ZERO rows'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK D — AC2(b)/AC3: full-household-by-construction (BEHAVIORAL) + SQL-layer
--   scope-aware filtering (V2-readiness; no function param, no UI, no enum).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select is(
  (select count(distinct scope)::int from pfin.account where users_id = :'ta'),
  3,
  '(D0) fixture pin: tenant A''s three accounts carry THREE DISTINCT scope values (personal/trust/business) — the AC2(b)/AC3 sums below are only meaningful if this partition is real'
);

-- (D1) AC2(b): fn_subcat_market_value's bare (unfiltered, sub_cat_id=a_eq) total EQUALS
--   an INDEPENDENTLY-RECONSTRUCTED SQL-layer sum over the substrate tables (account_trans
--   x eod_price, joined to account.scope), summed across every distinct scope. Structural
--   note (see header): fn_subcat_market_value's own output carries no account_id, so this
--   cannot join the FUNCTION's output to scope the way self228 did — it reconstructs the
--   dollar total independently instead, from KNOWN fixture literals via a real join, not a
--   restated formula.
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-08-01') where sub_cat_id = :a_eq),
  (select sum(t.quantity * ep.price)
     from pfin.account_trans t
     join pfin.account a on a.account_id = t.account_id
     join pfin.eod_price ep on ep.asset_id = t.security_id and ep.price_date = '2026-08-01'
    where a.users_id = :'ta' and a.scope in ('personal', 'trust', 'business')),
  '(D1) AC2(b): fn_subcat_market_value''s bare a_eq total EQUALS the independently-reconstructed SQL-layer sum across every distinct scope — full-household is the DEFAULT, not a coincidence of an absent filter'
);

-- (D2a)/(D2b)/(D2c) AC3: SQL-layer scope filter, substrate-reconstructed, ties back to
--   the FUNCTION's own bare total (not just internal consistency of the raw query).
select is(
  (select sum(t.quantity * ep.price)
     from pfin.account_trans t
     join pfin.account a on a.account_id = t.account_id
     join pfin.eod_price ep on ep.asset_id = t.security_id and ep.price_date = '2026-08-01'
    where a.users_id = :'ta' and a.scope in ('personal', 'trust')),
  375.00::numeric,
  '(D2a) AC3: SQL-layer scope filter restricted to (personal,trust) sums to EXACTLY 375 (150+225) — excludes the business-scope leaf'
);
select is(
  (select sum(t.quantity * ep.price)
     from pfin.account_trans t
     join pfin.account a on a.account_id = t.account_id
     join pfin.eod_price ep on ep.asset_id = t.security_id and ep.price_date = '2026-08-01'
    where a.users_id = :'ta' and a.scope = 'business'),
  300.00::numeric,
  '(D2b) AC3 companion: the EXCLUDED scope (business) sums to EXACTLY 300 — the restricted sum in (D2a) is a real partition, not a filter that happens to admit everything'
);
select is(
  375.00::numeric + 300.00::numeric,
  (select market_value from pfin.fn_subcat_market_value('2026-08-01') where sub_cat_id = :a_eq),
  '(D2c) AC3 closes the loop: restricted-scope sum (D2a) + excluded-scope sum (D2b) = the FUNCTION''s own bare total — the SQL-layer partition is exhaustive AND agrees with the live function, no leaf double-counted or dropped'
);

-- (D3a)/(D3b)/(D3c) AC2(b)/AC3 companion via fn_subcat_contributors — its output DOES
--   carry account_id, so this follows self228's D3/D4/D5 join-the-output shape verbatim,
--   using a distinct-account-COUNT (this function carries no money, SELF-330's own header).
select is(
  (select count(distinct g.account_id)::int
     from pfin.fn_subcat_contributors('2026-08-01') g
     join pfin.account a on a.account_id = g.account_id
    where g.sub_cat_id = :a_eq and a.scope in ('personal', 'trust')),
  2,
  '(D3a) fn_subcat_contributors AC3 companion: SQL-layer scope filter (personal,trust) restricted to a_eq contributors = 2 distinct accounts'
);
select is(
  (select count(distinct g.account_id)::int
     from pfin.fn_subcat_contributors('2026-08-01') g
     join pfin.account a on a.account_id = g.account_id
    where g.sub_cat_id = :a_eq and a.scope = 'business'),
  1,
  '(D3b) companion: the EXCLUDED scope (business) contributes 1 distinct account'
);
select is(
  2 + 1,
  (select count(distinct account_id)::int from pfin.fn_subcat_contributors('2026-08-01') where sub_cat_id = :a_eq),
  '(D3c) companion closes the loop: (D3a)+(D3b) = the function''s own bare distinct-account count for a_eq (3) — full-household by construction on the companion function too'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK E — AC4/AC5: planning_target READ isolation + the forged-injection WRITE fence,
--   exercised within THIS gate's shared multi-function fixture (the seam). Mechanism
--   itself is proven exhaustively by 074_planning_target_rls.sql — COMPOSED, not
--   re-derived; this block proves it holds TOGETHER with the allocation-function seam.
-- =====================================================================

-- (E1a)/(E1b)/(E1c) AC4: read isolation, this gate's own two tenants.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select target_percent from pfin.planning_target where users_id = :'ta'),
  60.00::numeric,
  '(E1a) AC4: A reads its own planning_target row (a_eq @ 60.00) — reflects ONLY tenant-A rows'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select target_percent from pfin.planning_target where users_id = :'tb'),
  40.00::numeric,
  '(E1b) AC4 non-vacuity: B reads its own DIFFERENT row (b_eq @ 40.00), not A''s'
);
select set_config('role', 'postgres', true);
select _rls.expect_cross_tenant_read_empty('pfin.planning_target'::regclass, :'ta'::uuid, :'tb'::uuid);

-- ⚠ (E2)/(E3)/(E4) are THREE CONSECUTIVE savepoint-wrapped legs, at the FILE'S TAIL, with
--   nothing non-rolled-back after them. Per 085_taxonomy_element_rls.sql's own measured
--   mechanism (its BLOCK C comment, cross-checked there against pgTAP source): the printed
--   `ok N` number comes from a SEQUENCE (exempt from rollback — every number above prints
--   correctly, none repeat), but `ok()` separately calls `_set('curr_test', N)` — an ordinary
--   TABLE write that IS rolled back with its savepoint, and writes an ABSOLUTE value, not an
--   increment. A later assertion's `_set` normally overwrites a rolled-back predecessor's loss
--   (085 measured drift = 1, always, for exactly this reason: one trailing rolled-back leg,
--   nothing after it). Here there are THREE trailing rolled-back legs in a row — each one's
--   `_set` gets undone by ITS OWN rollback before the next leg's `_set` can even run, so
--   `curr_test` ends the file still at (E1c)'s value. `finish()` will therefore emit a benign
--   "# Looks like you planned 35 tests but ran 32" comment — a `#`-prefixed TAP comment, not a
--   result line. pg_prove (the TAP-aware consumer this house requires) parses the real `1..35`
--   / `ok`/`not ok` stream and is UNAFFECTED — verified directly: every `ok N` from 1 through 35
--   prints, sequential, no repeats, no `not ok`, and pg_prove's own Test Summary Report does not
--   list this file among failures. Documented so a future reader does not mistake the comment
--   for a real 3-test gap, and does not have to re-derive 085's own mechanism from scratch.
--
-- (E2) AC5 LEG 1 (unresolvable) — the AC's LITERAL shape: A names B's REAL sub_cat_id
--   (b_eq) as a plain authenticated write. RLS on user_taxonomy hides B's row from A's
--   fence-internal SELECT, so it resolves as NOT FOUND — leg 1, not leg 2 (074's own
--   CONTRACT box; matches this file's header note).
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_e2;
select throws_like(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 10.00) $$, :b_eq),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(E2) AC5 LEG 1: A names tenant B''s REAL sub_cat_id (forged injection, the AC''s literal shape) -> fn_planning_target_matched_sub_cat RAISES leg 1 unresolvable, RLS-composed, before leg 2''s owner-mismatch compare is ever reached'
);
rollback to savepoint sp_e2;

-- (E3) AC5 LEG 2 (ownership-forge, defense-in-depth) — A forges users_id=B on its OWN
--   real sub_cat_id (a_eq). The fence resolves a_eq's TRUE owner (A) and compares against
--   the FORGED new.users_id (B) -> mismatch -> leg 2, reachable from PLAIN authenticated
--   (074's own (L2a) precedent, re-exercised on this gate's fixture identities).
savepoint sp_e3;
select throws_like(
  format($$ insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (%L, %s, 10.00) $$, :'tb', :a_eq),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(E3) AC5 LEG 2 (defense-in-depth): A forges users_id=B on A''s OWN real sub_cat_id (a_eq) -> RAISES leg 2 cross-tenant, from PLAIN authenticated, before RLS''s own WITH CHECK is ever reached — the #8/074-(L2a) ownership-forge shape'
);
rollback to savepoint sp_e3;

-- (E4) non-vacuous write control: A inserts its OWN real sub_cat_id (a_cd, unused
--   elsewhere in this fixture) with its OWN real users_id -> ACCEPTED. Proves (E2)/(E3)
--   are mismatch-driven, not a blanket write-block.
savepoint sp_e4;
select lives_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 15.00) $$, :a_cd),
  '(E4) non-vacuous control: A''s own real sub_cat_id with A''s own real users_id -> ACCEPTED — the fence is mismatch-driven, not a blanket exempt-writer block'
);
rollback to savepoint sp_e4;
select set_config('role', 'postgres', true);

select * from finish();
rollback;
