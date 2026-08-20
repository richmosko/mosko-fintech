-- =====================================================================
-- Per-Wave battery — pfin.fn_subcat_market_value(p_as_of, p_include_real_estate)
--   — per-Sub-Cat market-value rollup (SELF-237; PRD §2.2.2.a). Shared primitive
--   for §2.2.2 Non-RE allocation (SELF-238) and §2.2.3 US Equity sub-allocation
--   (SELF-240). Read-only: NO new base table, NO write path, NO new DEFINER,
--   NO new FK-shaped column. Paired with the migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/076_fn_subcat_market_value.sql
--   pfin.fn_subcat_market_value(p_as_of date default current_date,
--     p_include_real_estate boolean default false)
--     RETURNS TABLE (sub_cat_id bigint, cat text, sub_cat text, market_value numeric)
--     SECURITY INVOKER · STABLE · set search_path = ''. NO tenant/scope parameter
--   (R1 — isolation is INHERITED from the RLS on every relation read). One row per
--   asset-domain Sub-Cat the caller HOLDS VALUE IN, plus AT MOST ONE unclassified
--   row (all three taxonomy columns NULL — R2, the silent-money-leak guard).
--   market_value COALESCEs to 0 (R3). EMPTY PORTFOLIO = EMPTY SET. Closed accounts
--   excluded on the 059 three-conjunct dated predicate. PRE-084: domain='asset' was
--   enforced IN THE JOIN, not the WHERE, so a cash-flow-classified holding degraded
--   to the unclassified row instead of vanishing. POST-084 (ADR-058 Decision 1): the
--   join carries no domain predicate at all — user_taxonomy is asset-only by
--   construction, and a cross-vocabulary reference is rejected at WRITE time by
--   022's own fence before it can ever reach this function's read (see (U1-REJECT)
--   below) — true by table identity, not by a runtime conjunct. p_include_real_estate=false excludes
--   cat='Real Estate' ENTIRELY (no row); Alternatives/REIT is a DIFFERENT cat and
--   is NOT swept; the unclassified row is NEVER excluded by the flag.
--   ⚠ L1 (cannot fix here): cash resolves to ONE Sub-Cat per user per currency via
--   the 022 cash-via-currency-asset model — every USD balance across every account
--   lands in whichever ONE Sub-Cat the user classified the global USD asset to.
--   ⚠ L2 (cannot fix here): the unclassified population is LIVE NON-ZERO POSITIONS
--   (fn_holdings_as_of filters quantity<>0), a DIFFERENT SET from the app-layer
--   pendingSymbols query (ever-transacted minus classified) — do not reconcile.
--   ⚠ The price/source same-date tie-break is NOT total ('market_feed'/'spot_feed'/
--   'fx_feed' share rank 2) — pre-existing in every copy of this kernel (019 through
--   049/050/056/059), flagged for the reviewer in 076's own header. NOT fixed here
--   and NOT tested here per team-lead's explicit instruction — Sec's call to weigh.
--
-- Prereqs exercised (on the 001→076 stack): 003 (pfin.account direct-owner RLS +
--   account_users rd_access grant chain); 006 (account_trans rd_access-JOIN + 025
--   aal2); 009 (user_taxonomy id/cat/sub_cat/domain); 016/017 (hybrid pfin.asset
--   registry + the global currency-asset rows, seeded at asset_id=1..7); 019
--   (eod_price + fn_holdings_as_of, quantity<>0 filter); 022 (user_asset_category
--   junction + its own Decision-3 #8 fence — irrelevant here, this battery never
--   crosses a Sub-Cat between tenants through the junction); 041 (seeded taxonomy
--   vocabulary: Cash/CD, Equity/US-06-Financials, Real Estate/Residential,
--   Alternatives/REIT — reused verbatim rather than invented, so the fixture reads
--   as a real portfolio, not synthetic vocabulary); 056 (fn_account_cash_as_of,
--   TOTAL over pfin.account); 058 (fn_close_account / the closure gate's three
--   legs — the REASON the boundary leg below is the reachable one, see (B1));
--   059 (the dated closure predicate this fn's sec_leg reproduces three-conjunct).
--
-- ┌─ ARCHITECT ITEM 1 — AC4's closure predicate is UNFALSIFIABLE BY VALUE ──────────┐
-- │ 058's close gate refuses to close an account holding value (three legs: zero    │
-- │ holdings, zero cash, no activity dated after closed_at) — so there is no way to  │
-- │ construct "a closed account whose value should have been excluded but wasn't":  │
-- │ a closed account is ALREADY at zero as of its closed_at, by construction. The    │
-- │ "closed excluded" claim therefore cannot RED by money disappearing — a naive     │
-- │ predicate that always returned TRUE (never excludes) would still show every      │
-- │ closed account contributing exactly 0, indistinguishable from correct exclusion. │
-- │ Two independent reachable proofs instead: (S1) STRUCTURAL — the three-conjunct   │
-- │ predicate text is present in prosrc, scoped past the header comment that also    │
-- │ names it (062's own lesson: a bare grep hits the prose explaining the fence).    │
-- │ (B1) THE BOUNDARY — an account with closed_at STRICTLY AFTER p_as_of holds REAL  │
-- │ nonzero value and MUST still be INCLUDED (a_close: funded 500, zeroed only as of │
-- │ its own closed_at, queried at an EARLIER as_of where it is real money, still     │
-- │ open, and counted). This is the reachable leg — before closed_at the account can │
-- │ hold real value and the predicate is exercised on genuine money, not a phantom.  │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 2 — THE UNCLASSIFIED ROW IS THE HIGHEST-VALUE ASSERTION, RE-DERIVED AT 084 ┐
-- │ Two DIFFERENT ways to land unclassified, both value-preserving: secx has NO      │
-- │ user_asset_category row at all (200.00); secy's junction row is now REJECTED     │
-- │ AT WRITE TIME (135.00) — pre-084 it landed and degraded via a join-condition     │
-- │ miss (`ut.domain='asset'`); post-084 there is no domain to miss on, because a    │
-- │ cross-vocabulary reference is now STRUCTURALLY IMPOSSIBLE (Decision 5 Finding    │
-- │ (b), independently confirmed by Architect from the migration side, same shape as │
-- │ self200's (v1)): 022's own #8 fence rejects the INSERT outright (P0001), so secy │
-- │ ends up with NO junction row at all — mechanically identical to secx's case, not │
-- │ merely coincidentally the same total. (U1-REJECT) proves the write is refused;   │
-- │ (U1) then asserts the SAME 335.00 total, via the SAME mechanism as secx (no      │
-- │ junction row exists) rather than a join miss on one that does. This is a         │
-- │ coverage STRENGTHENING: the R2 money-leak class this leg exists to catch is now  │
-- │ prevented one layer earlier, at write time, not merely degraded safely at read   │
-- │ time.                                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 3 — POPULATION DIVERGENCE IS ENCODED, NOT RECONCILED ─────────────────────┐
-- │ secz is bought (qty 2) then FULLY SOLD (qty -2, net 0) before the query date.    │
-- │ fn_holdings_as_of filters quantity<>0, so secz emits ZERO rows here — not a      │
-- │ phantom-zero row, an absence. api/.../pendingSymbols.ts computes ever-transacted │
-- │ MINUS classified with NO quantity filter, so the SAME symbol is PENDING there.   │
-- │ Both are correct for their own contract. (P1) proves secz contributes NOTHING —  │
-- │ (U1)'s exact 335.00 (not 435.00) is the proof: if secz's 100.00 leaked into the  │
-- │ unclassified bucket, the sum would be visibly wrong. Named here so a future      │
-- │ "reconciliation" between the two populations is a deliberate scope change, not a │
-- │ silent fix of either side.                                                       │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 4 — L1 CASH SUBSTRATE LIMIT + full-household ≥2-scope reconciliation ─────┐
-- │ a_dep1 (scope='personal', 300.00) and a_dep2 (scope='trust', 200.00) are TWO     │
-- │ accounts, TWO DISTINCT free-text scopes (ADR-004 Decision B — scope is an        │
-- │ ATTRIBUTE, not a partition; no pfin.scope type; the SELF-228 AC3 shape, reused   │
-- │ rather than re-derived). Classifying the GLOBAL USD currency-asset (asset_id=1,  │
-- │ seeded at 016) to Cash/CD moves ALL of it — both accounts, both scopes, AND      │
-- │ a_inv's own brokerage cash sweep (funded to net exactly 0 so the arithmetic      │
-- │ stays legible) — into ONE Sub-Cat row (C1: 500.00). No account-level or          │
-- │ scope-level split exists in the output; the seeded CD/FDIC/SPIC/T-Bill Sub-Cats  │
-- │ genuinely cannot be told apart per account, exactly as 076's header states.      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 5 — REAL ESTATE: exclusion by ABSENT ROW, Alternatives/REIT NOT swept ────┐
-- │ (R1) include_re=false: NO Real Estate row at all (NOT EXISTS, not a zero row).   │
-- │ (R2) include_re=true: the SAME row appears, value 250.00 — the flag TOGGLES      │
-- │ presence, it does not toggle a value from 0. (R3) Alternatives/REIT (a DIFFERENT │
-- │ cat, seeded vocabulary) is present in BOTH states unchanged — the match is EXACT │
-- │ on cat, not a semantic "is this real-estate-like" test. (R4) the unclassified    │
-- │ row's value is IDENTICAL in both states — NULL cat cannot be known to be Real    │
-- │ Estate, so the flag can never touch it (076:322-325's own `is distinct from`     │
-- │ reasoning, exercised rather than read).                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 6 — EMPTY PORTFOLIO → EMPTY SET (the phantom-Unsorted defect, fenced) ────┐
-- │ 076's own header (lines 300-309) documents this defect was MEASURED on the      │
-- │ scratch chain before the `coalesce(c.balance_native,0) <> 0` filter existed:     │
-- │ every OPEN account with no cash and no holdings manufactured a 0.00 UNCLASSIFIED │
-- │ row, which SELF-238 would have rendered as a phantom "Unsorted" line for nearly  │
-- │ every user. Tenant C: one open depository account, NO checkpoint, NO trans, NO   │
-- │ holdings — exactly the shape that used to leak. (E1) asserts ZERO rows, not a    │
-- │ zero-valued row — fencing the defect at its own most-likely reintroduction site. │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ CORRUPT-THE-CONTROL — the inherited-fence claim, MEASURED not assumed ────────┐
-- │ 076's own JOINT-REVIEW-MANDATORY note: "if any relation it reads were to lose   │
-- │ its policy, this function would silently widen." Measured which relation:       │
-- │ corrupting `account_select` ALONE does NOT leak B's value into A's total (X1) — │
-- │ fn_holdings_as_of / fn_account_cash_as_of gate through account_trans's and       │
-- │ account_balance_checkpoint's OWN rd_access-JOIN policies, a SEPARATE fence from  │
-- │ account's direct-owner RLS (defense in depth, empirically confirmed, not         │
-- │ assumed). Corrupting all THREE together (`account_select` +                      │
-- │ `account_trans_select` + `account_balance_checkpoint_select`) DOES leak (X2):    │
-- │ A's total rises by EXACTLY B's contribution. LIMIT-1 DISPLACEMENT CLASS (PR      │
-- │ #474 F2): does not apply here — every value in this function is a GROUP BY / SUM │
-- │ aggregate, no `order by ... limit 1` selector anywhere in the composition, so    │
-- │ there is no tie-break for a real row to win; (X2) asserts an EXACT total, not    │
-- │ merely non-zero. Stated per house discipline, not because the class applies.     │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (076 is READ-ONLY: no write path, no new
--   credential surface — read ADR-011 Decision 4 live). Decision-3 family UNCHANGED
--   (076 authors no table, no FK-shaped column — it reads existing fenced relations).
--   SECURITY DEFINER allowlist UNCHANGED (this fn is INVOKER). This battery
--   introduces no catalogued instance; it is the pgTAP proof the composition fails
--   closed cross-tenant and reproduces §2.2.2.a's rollup contract exactly.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '76' for this migration) + real seeded taxonomy vocabulary (Cash/CD,
--   Equity/US-06-Financials, Real Estate/Residential, Alternatives/REIT,
--   Revenue/Dividend). NO PII / NO real account numbers / NO prod data. All seeds
--   PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY. All
--   in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated. Tenant UUIDs + row ids resolve to psql LITERALS via \gset/\set at
--   role=postgres; every _rls.set_tenant is called at role=postgres and each block
--   restores role=postgres before the next.
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of 076
--   against the 001→075 local stack (NON-destructive; `supabase db reset` never
--   invoked). Every numeric claim in this file (335.00, 500.00, 895.00/395.00, the
--   1660.00/60.00/1720.00 corrupt-the-control figures) was MEASURED against the
--   live composition, not derived on paper — three arithmetic/ordering mistakes in
--   early drafts (an unfunded a_inv producing negative cash; a too-narrow
--   corrupted-policy set showing no leak; tenant P's fixture built BEFORE the
--   corrupt-the-control block, so its 10000.00 silently absorbed into X2's global
--   `using (true)` corruption) were caught this way before landing in the file.
--   plan(22): 5 isolation (I1-I5) + 1 structural (S1) + 1 boundary (B1) + 2
--   unclassified (U1-U2) + 1 population-divergence (P1) + 1 cash-substrate (C1) +
--   4 real-estate (R1-R4) + 1 empty-portfolio (E1) + 2 corrupt-the-control
--   (X1-X2) + 2 grant/negative (G1-G2) + 2 AC6 perf (PERF1-PERF2) = 22.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(23);

\set ta '00000000-0000-0000-0000-000000000a76'
\set tb '00000000-0000-0000-0000-000000000b76'
\set tc '00000000-0000-0000-0000-000000000c76'
\set tp '00000000-0000-0000-0000-00000000ff76'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'tp');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL -> 016/017 #7: readable by every tenant's
--   INVOKER). One price each, single source, no tie-break ambiguity (deliberately
--   avoiding the flagged-not-fixed nondeterminism in this battery's own fixture).
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBX76','Sec X unclassified') returning asset_id as secx \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBY76','Sec Y cashflow-misclassified') returning asset_id as secy \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBZ76','Sec Z sold-to-zero') returning asset_id as secz \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBQ76','Sec Q classified equity') returning asset_id as secq \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBRE76','Sec RE classified') returning asset_id as secre \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBALT76','Sec Alt REIT classified') returning asset_id as secalt \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBB76','Sec B tenant-B control') returning asset_id as secb \gset

insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:secx,'2026-07-01','market_feed',200.00),
  (:secy,'2026-07-01','market_feed',135.00),
  (:secz,'2026-07-01','market_feed',50.00),
  (:secq,'2026-07-01','market_feed',400.00),
  (:secre,'2026-07-01','market_feed',250.00),
  (:secalt,'2026-07-01','market_feed',175.00),
  (:secb,'2026-07-01','market_feed',60.00);

-- ---------------------------------------------------------------------
-- Tenant A taxonomy — REAL seeded vocabulary (041), not invented text.
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Marketable Securities','US-06-Financials','asset') returning id as a_eq \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Real Estate','Residential','asset') returning id as a_re \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Alternatives','REIT','asset') returning id as a_alt \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Cash','CD','asset') returning id as a_cd \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat) values
  (:'ta','Revenue','Dividend') returning id as a_cf \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'tb','Marketable Securities','US-06-Financials','asset') returning id as b_eq \gset

-- ---------------------------------------------------------------------
-- TENANT A — a_inv (investment; secx unclassified, secy cashflow-misclassified,
--   secz bought-then-sold-to-zero, secq/secre/secalt classified). Funded to
--   NET EXACTLY ZERO cash by 2026-07-25 (checkpoint 1155.00 = the exact negative
--   of the trans net, MEASURED not guessed) so the cash-substrate arithmetic in
--   (C1) stays legible — a_inv's own brokerage cash sweep is real and rolls into
--   Cash/CD once classified, it is just netted to zero for readability.
--   a_dep1/a_dep2 — TWO SCOPES ('personal'/'trust'), pure cash (item 4).
--   a_close — the closure-boundary account (Architect item 1 (B1)): funded 500,
--   zeroed via a SECOND checkpoint dated 07-14, closed 07-15 through the REAL
--   058 gate (zero cash as of closed_at, no post-closure activity).
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-inv-76','investment','household','taxable') returning account_id as a_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_inv, 1155.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_inv,'2026-07-05',-200.00,1,:secx,200.00,'standard','buy-x'),
  (:a_inv,'2026-07-05',-135.00,1,:secy,135.00,'standard','buy-y'),
  (:a_inv,'2026-07-05',-100.00,2,:secz,100.00,'standard','buy-z'),
  (:a_inv,'2026-07-20', 105.00,-2,:secz,0.00,'standard','sell-z-to-zero'),
  (:a_inv,'2026-07-05',-400.00,1,:secq,400.00,'standard','buy-q'),
  (:a_inv,'2026-07-05',-250.00,1,:secre,250.00,'standard','buy-re'),
  (:a_inv,'2026-07-05',-175.00,1,:secalt,175.00,'standard','buy-alt');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-dep1-76','depository','personal','taxable') returning account_id as a_dep1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_dep1, 300.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-dep2-76','depository','trust','taxable') returning account_id as a_dep2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_dep2, 200.00, 'USD', '2026-07-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-close-76','depository','household','taxable') returning account_id as a_close \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_close, 500.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_close, 0.00, 'USD', '2026-07-14', 'seed');
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-07-15'::timestamptz where account_id = :a_close;

-- classify: secq -> Equity; secre -> Real Estate; secalt -> Alternatives/REIT; the
--   GLOBAL USD currency-asset (asset_id=1, seeded 016) -> Cash/CD. secx and secz:
--   NO junction row (secx deliberately; secz because it has zero position by the
--   query date). secy: see (U1-REJECT) below, POST-084 -- the attempt to classify
--   it against a_cf (now a posting_prototype id) is itself the assertion.
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', :secq, :a_eq),
  (:'ta', :secre, :a_re),
  (:'ta', :secalt, :a_alt),
  (:'ta', 1, :a_cd);

-- (U1-REJECT) POST-084: the pre-split fixture classified secy against a_cf (then a
--   cashflow-domain user_taxonomy row) to demonstrate a join-condition miss. Post-
--   split a_cf lives in posting_prototype; user_asset_category.sub_cat_id's FK still
--   targets user_taxonomy only (022, UNCHANGED by 084 — Decision 1). The attempt is
--   REJECTED by 022's own #8 fence (P0001) before it ever reaches a table -- this IS
--   the coverage strengthening ITEM 2's header box describes: the cross-vocabulary
--   reference this leg used to construct can no longer be constructed at all.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (%L, %s, %s) $$, :'ta', :secy, :a_cf),
  '%is not a taxonomy row owned by users_id%',
  '(U1-REJECT) POST-084: classifying secy against a_cf (a posting_prototype id) is REJECTED by 022''s #8 fence -- the cross-vocabulary reference (U1) used to exercise via a join-miss is now structurally impossible to even construct'
);

-- ---------------------------------------------------------------------
-- TENANT B — isolation control. b_inv funded to net exactly 60.00, holding
--   secb (60.00), classified Equity. Total 60.00, non-vacuous, distinct from A.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-inv-76','investment','household','taxable') returning account_id as b_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_inv, 60.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:b_inv,'2026-07-05',-60.00,1,:secb,60.00,'standard','buy-b');
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'tb', :secb, :b_eq);

-- ---------------------------------------------------------------------
-- TENANT C — empty-portfolio / phantom-Unsorted fence (item 6). One OPEN
--   depository account, NO checkpoint, NO trans, NO holdings.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tc','c-dep-76','depository','household','taxable') returning account_id as c_dep \gset


-- =====================================================================
-- ISOLATION (I1-I5) — the load-bearing cross-tenant proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (I1) A's total = EXACTLY 1660.00 (own value: 335 unclass + 400 eq + 250 re +
--      175 alt + 500 cash — every leg this file exercises, summed).
select is(
  (select sum(market_value) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  1660.00::numeric,
  '(I1) A''s total market value = 1660.00 (335 unclassified + 400 Equity + 250 Real Estate + 175 Alternatives/REIT + 500 Cash/CD) — OWN value only'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
-- (I2) B's total = EXACTLY 60.00 — does NOT include A's 1660.
select is(
  (select sum(market_value) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  60.00::numeric,
  '(I2) B''s total market value = 60.00 (B''s OWN classified holding only) — cross-tenant fail-closed: does not include A''s 1660.00'
);
-- (I4) A's Equity Sub-Cat (a_eq) does not appear in B's result set.
select ok(
  not exists (select 1 from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_eq),
  '(I4) cross-tenant read fails closed: B''s call to fn_subcat_market_value never returns A''s Equity sub_cat_id (a_eq)'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (I3) B's Equity Sub-Cat (b_eq) does not appear in A's result set (reverse direction).
select ok(
  not exists (select 1 from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :b_eq),
  '(I3) cross-tenant read fails closed (reverse): A''s call never returns B''s Equity sub_cat_id (b_eq)'
);
select set_config('role', 'postgres', true);
-- (I5) non-vacuous: both A's and B's totals are demonstrably nonzero (I1/I2 are
--      boundary denials against real value, not an empty database).
select ok(1660.00 > 0 and 60.00 > 0,
  '(I5) non-vacuous companion: both A (1660.00) and B (60.00) hold REAL positive value — (I3)/(I4)''s absences are boundary denials, not an empty DB'
);

-- =====================================================================
-- STRUCTURAL (S1) — Architect item 1: AC4's closure predicate, proven past the
--   062 lesson (a bare grep hits the header prose explaining it, not just the
--   WHERE clause). Scoped substrings that appear ONLY in the executable body.
-- =====================================================================
select ok(
  (select p.prosrc ilike '%where acc2.account_id is not null%'
     and  p.prosrc ilike '%acc2.closed_at is null or acc2.closed_at::date > p_as_of%'
     from pg_proc p
    where p.proname = 'fn_subcat_market_value' and p.pronamespace = 'pfin'::regnamespace),
  '(S1) STRUCTURAL: the LEFT-JOIN-safe three-conjunct closure predicate (`where acc2.account_id is not null and (acc2.closed_at is null or acc2.closed_at::date > p_as_of)`) is present in prosrc, scoped to substrings absent from the header comment that also names it — a text-only regression (predicate deleted, function still parses) would go RED here even though it cannot be caught by value (AC4 is unfalsifiable by money — see the header box)'
);

-- =====================================================================
-- BOUNDARY (B1) — the REACHABLE closure leg: closed_at STRICTLY AFTER p_as_of
--   still counts real money. a_close holds 500.00 on 07-10 (checkpoint 07-01,
--   the 0.00 checkpoint dated 07-14 has not taken effect); by 07-15 (closed_at
--   itself) it is excluded entirely. The DIFFERENCE isolates a_close's own
--   contribution from a_inv's/a_dep*'s (which are IDENTICAL at both dates).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-10'::date, true) where sub_cat_id = :a_cd)
  -
  coalesce((select market_value from pfin.fn_subcat_market_value('2026-07-15'::date, true) where sub_cat_id = :a_cd), 0),
  500.00::numeric,
  '(B1) closure BOUNDARY, the reachable leg: Cash/CD @2026-07-10 minus Cash/CD @2026-07-15 = EXACTLY 500.00 = a_close''s own contribution. At 07-10, closed_at (07-15) is STRICTLY AFTER p_as_of -> a_close is OPEN-AS-OF and its real 500.00 is counted. At 07-15 (=closed_at), it is excluded. RED if the predicate excluded a still-open account (money would vanish from 07-10 too) or failed to exclude at the boundary date (the difference would be 0, not 500)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- UNCLASSIFIED (U1-U2) — item 2, the highest-value assertion.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (U1) POST-084: the unclassified row sums EXACTLY 335.00 = secx (200, no junction)
--      + secy (135, ALSO no junction now -- (U1-REJECT) proved the classification
--      attempt itself is rejected, so secy lands here via the SAME mechanism as
--      secx, not a join-condition miss on a row that exists).
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  335.00::numeric,
  '(U1) ⭐ unclassified row = EXACTLY 335.00 = secx (200.00, NO junction row) + secy (135.00, NO junction row either -- (U1-REJECT) proved the write is refused, not merely that it degrades). A classified-totals-only battery would pass while this 335.00 silently disappeared (the R2 money-leak this function exists to prevent)'
);
-- (U2) the unclassified row''s cat and sub_cat are BOTH NULL (structural, not just
--      sub_cat_id) — a real Sub-Cat could not accidentally alias into this bucket.
select ok(
  (select cat is null and sub_cat is null
     from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  '(U2) unclassified row structural check: cat AND sub_cat are BOTH NULL (not just sub_cat_id) — the row cannot be confused with a real, oddly-named Sub-Cat'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- POPULATION DIVERGENCE (P1) — item 3, sold-to-zero absence (not zero row).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (P1) secz (bought qty 2, fully sold before p_as_of) contributes to NEITHER a
--      classified row NOR the unclassified row: (U1)''s 335.00 (not 435.00) already
--      proves this; restated directly as a row-count check for legibility.
select is(
  (select count(*) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  5::bigint,
  '(P1) population divergence, encoded not reconciled: fn_holdings_as_of filters quantity<>0, so the fully-sold secz emits ZERO rows here (absent, not a phantom zero) — exactly 5 rows total (unclassified + Equity + Real Estate + Alternatives/REIT + Cash/CD), none attributable to secz. The app-layer pendingSymbols query (ever-transacted minus classified, no quantity filter) would still show secz PENDING — a DIFFERENT, correct-for-its-own-contract population, named here so a future "fix" in either direction is a deliberate scope change, not silent drift'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- CASH SUBSTRATE LIMIT (C1) — item 4 + full-household ≥2-scope reconciliation.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (C1) Cash/CD = EXACTLY 500.00 = a_dep1 (300, scope=''personal'') + a_dep2 (200,
--      scope=''trust''), reconciling TWO DISTINCT SCOPES into ONE Sub-Cat (L1: cash
--      cannot be classified per account, and scope is an attribute, never a
--      partition — 076 R1 / ADR-004 Decision B).
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_cd),
  500.00::numeric,
  '(C1) L1 cash substrate limit: Cash/CD = EXACTLY 500.00 = a_dep1 (300.00, scope=personal) + a_dep2 (200.00, scope=trust) — TWO accounts, TWO DISTINCT SCOPES, merged into ONE Sub-Cat because cash classifies via the single per-user currency-asset junction, not per account. Full-household-by-construction: no scope-level split exists in the output (SELF-228 AC3 shape, reused)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- REAL ESTATE (R1-R4) — item 5.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (R1) include_re=false: NO Real Estate row — ABSENCE, not a zero row.
select ok(
  not exists (select 1 from pfin.fn_subcat_market_value('2026-07-25'::date, false) where sub_cat_id = :a_re),
  '(R1) p_include_real_estate=FALSE: the Real Estate Sub-Cat (a_re, 250.00 real value) is ABSENT entirely — not a zero-valued row. RED if it appeared with market_value=0 (exclusion-by-value instead of exclusion-by-row)'
);
-- (R2) include_re=true: the SAME row appears, value 250.00 — the flag toggles
--      presence, not a value from 0.
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_re),
  250.00::numeric,
  '(R2) p_include_real_estate=TRUE: the SAME Real Estate row now appears with its REAL value 250.00 — (R1)''s absence is a genuine toggle, non-vacuous'
);
-- (R3) Alternatives/REIT is NOT swept by the flag, in EITHER state (exact match
--      on cat, not a semantic "real-estate-like" test).
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, false) where sub_cat_id = :a_alt),
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id = :a_alt),
  '(R3) Alternatives/REIT is NOT swept by p_include_real_estate in EITHER state: 175.00 present and IDENTICAL whether the flag is false or true — the match is EXACT on cat=''Real Estate'', a DIFFERENT cat is never touched'
);
-- (R4) the unclassified row is NEVER excluded by the flag — same value both states.
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, false) where sub_cat_id is null),
  (select market_value from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  '(R4) unclassified row is NEVER excluded by p_include_real_estate: 335.00 in BOTH states — a NULL cat cannot be known to be Real Estate, so the `is distinct from` guard (076:322-325) holds regardless of the flag'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- EMPTY PORTFOLIO (E1) — item 6, the phantom-Unsorted defect, fenced.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
-- (E1) tenant C: one open depository account, zero cash, zero holdings -> the
--      EMPTY SET, not a synthesized zero row.
select is(
  (select count(*) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  0::bigint,
  '(E1) empty portfolio -> EMPTY SET: tenant C has one OPEN account with zero cash and zero holdings (exactly the shape 076''s header documents as the pre-fix phantom-Unsorted trigger) -> ZERO rows, not a manufactured 0.00 unclassified row'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- CORRUPT-THE-CONTROL (X1-X2) — the inherited-fence claim, MEASURED.
--   No limit-1 selector anywhere in this function (pure GROUP BY / SUM
--   aggregation) — the #474 F2 displacement class does not apply; (X2) asserts
--   an EXACT total, not merely non-zero, which the class would have forced
--   a weaker assertion for if it did apply.
-- =====================================================================
-- NOTE ON ORDERING (071's own convention, replicated deliberately): ALTER POLICY
--   requires table ownership, so it MUST run while role=postgres — set_tenant
--   (-> role=authenticated) comes AFTER the corruption, never before.
savepoint sp_corrupt1;
-- (X1) account_select ALONE, corrupted open: A's total is UNCHANGED (still
--      1660.00) — B's value does NOT leak. fn_holdings_as_of / fn_account_cash_as_of
--      gate through account_trans's / account_balance_checkpoint's OWN rd_access
--      policies, a SEPARATE fence from account's direct-owner RLS. Defense in
--      depth, empirically confirmed (an earlier draft of this leg assumed a leak
--      and was wrong — measured, not assumed, per house discipline).
alter policy account_select on pfin.account using (true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select sum(market_value) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  1660.00::numeric,
  '(X1) DEFENSE IN DEPTH, measured: with `account_select` alone broken OPEN, A''s total is UNCHANGED at 1660.00 -- B''s value does NOT leak, because fn_holdings_as_of / fn_account_cash_as_of gate through account_trans''s and account_balance_checkpoint''s OWN rd_access-JOIN policies, independent of account''s direct-owner RLS. RED (>1660.00) would mean that independent gate silently vanished'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_corrupt1;

savepoint sp_corrupt2;
-- (X2) ⭐ ALL THREE relations this function actually depends on for value,
--      corrupted together: account_select + account_trans_select +
--      account_balance_checkpoint_select. NOW it leaks: A''s total rises by
--      EXACTLY B''s 60.00, to 1720.00 -- confirming 076''s own "if any relation it
--      reads were to lose its policy, this function would silently widen" against
--      the relations that are ACTUALLY load-bearing, not assumed ones.
alter policy account_select on pfin.account using (true);
alter policy account_trans_select on pfin.account_trans using (true);
alter policy account_balance_checkpoint_select on pfin.account_balance_checkpoint using (true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select sum(market_value) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  1720.00::numeric,
  '(X2) ⭐ CORRUPT-THE-CONTROL, the load-bearing leg: with account_select + account_trans_select + account_balance_checkpoint_select ALL broken OPEN, A''s total rises to EXACTLY 1720.00 = A''s own 1660.00 + B''s leaked 60.00 -- proving the tenant fence really is entirely INHERITED (076''s own JOINT-REVIEW-MANDATORY note), and identifying the SPECIFIC three relations that jointly carry it (not account_select alone -- see X1)'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_corrupt2;

-- =====================================================================
-- GRANTS (G1-G2).
-- =====================================================================
-- (G1) anon zero-grant: no EXECUTE.
select set_config('role', 'anon', true);
select throws_ok(
  $$ select * from pfin.fn_subcat_market_value('2026-07-25'::date, true) $$,
  '42501', null,
  '(G1) anon zero-grant: EXECUTE is revoked from public and not granted to anon -- anon cannot invoke fn_subcat_market_value at all'
);
select set_config('role', 'postgres', true);

-- (G2) negative-arg fence: an as_of far in the past (before any data) returns
--      the EMPTY SET for a real tenant, not an error and not a synthesized row.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.fn_subcat_market_value('2020-01-01'::date, true)),
  0::bigint,
  '(G2) as_of predating all data: A''s call at 2020-01-01 (before every seeded price/trans) returns the EMPTY SET -- no error, no synthesized row, consistent with the empty-portfolio contract (E1) at a real tenant with real (future-dated) holdings'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AC6 PERF (PERF1-PERF2) — tenant P, 20 accounts / 10 classified Sub-Cats.
--   ⚠ VENUE: the LOCAL DEV STACK (Docker, developer machine), same as 076''s own
--   authoritative measurement -- NOT the Phase-7 deploy target (cax21 is the
--   REFERENCE INCUMBENT, not the V1 deploy target; no production figure exists
--   yet). This is a regression SMOKE against a representative shape, not a
--   replica of the AC''s 20/30 authoritative benchmark (which lives in 076''s
--   header) -- a timing assertion is environment-sensitive by nature.
--   ⚠ P's fixture is built HERE, AFTER the corrupt-the-control block (X1/X2),
--   deliberately: `using (true)` on account_trans_select / account_balance_
--   checkpoint_select corrupts the policy GLOBALLY, not per-tenant — an earlier
--   draft built P's fixture up front and X2's expected total silently absorbed
--   P's entire 10000.00 portfolio (measured: 11720.00 instead of the intended
--   1720.00 = A + B only). Building P's data after X1/X2 keeps that leg's
--   arithmetic legible; ordering is load-bearing here, not cosmetic.
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  select null, 'equity', 'market_feed', 'SBP76-' || g, 'Perf Sec ' || g
  from generate_series(1, 10) g;
-- \gset requires a single-row result; capture the whole 10-asset set as one array.
select array_agg(asset_id order by asset_id) as psecs
  from pfin.asset where symbol like 'SBP76-%' \gset
insert into pfin.eod_price (asset_id, price_date, source, price)
  select unnest(:'psecs'::bigint[]), '2026-07-01', 'market_feed', 100.00;
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  select :'tp', 'Marketable Securities', 'US-Perf-Sub-' || g, 'asset' from generate_series(1, 10) g;
select array_agg(id order by id) as psubs
  from pfin.user_taxonomy where users_id = :'tp' \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  select :'tp', 'p-acct-' || g, 'investment', 'household', 'taxable' from generate_series(1, 20) g;
-- checkpoint EXACTLY offsets the single buy (100.00 - 100.00 = 0 net cash per
-- account) so no incidental unclassified-cash row appears — PERF1's count stays
-- exactly 10 (an earlier draft funded 500.00 here and got an 11th UNCLASSIFIED
-- row from the un-netted 400.00/account cash residue; measured, then fixed).
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  select account_id, 100.00, 'USD', '2026-07-01', 'seed' from pfin.account where users_id = :'tp';
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  select account_id, '2026-07-05', -100.00, 1,
         (:'psecs'::bigint[])[1 + (account_id % 10)], 100.00, 'standard', 'buy-p'
  from pfin.account where users_id = :'tp';
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id)
  select :'tp', (:'psecs'::bigint[])[i], (:'psubs'::bigint[])[i] from generate_series(1, 10) i;

select _rls.set_tenant(:'tp'::uuid);
-- (PERF1) non-vacuous: P''s portfolio returns real groups (the perf query does
--         real aggregation work, not an empty-table fast path).
select is(
  (select count(*) from pfin.fn_subcat_market_value('2026-07-25'::date, true)),
  10::bigint,
  '(PERF1) perf fixture is non-vacuous: tenant P''s 20-account portfolio (cycled across 10 classified Sub-Cats) returns 10 groups'
);
-- (PERF2) AC6: completes within the ≤300ms budget, LOCAL venue (per the
--         corrected AC; not a deploy-target claim).
select performs_ok(
  $$ select * from pfin.fn_subcat_market_value('2026-07-25'::date, true) $$,
  300,
  '(PERF2) AC6 perf (LOCAL DEV STACK venue): fn_subcat_market_value over tenant P''s 20-account / 10-Sub-Cat portfolio completes in <=300ms -- regression smoke against the authoritative 076-header measurement, not a replacement for it'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
