-- =====================================================================
-- Per-Wave battery — pfin.fn_subcat_contributors(p_as_of, p_include_real_estate)
--   — per-Sub-Cat CONTRIBUTOR map (SELF-330; PRD §2.2.2, completes SELF-239 AC11
--   row-tint half). Shape 1 sibling of 076 (fn_subcat_market_value): 076's join
--   skeleton with every VALUATION expression deleted. Returns DISTINCT
--   (sub_cat_id, account_id) pairs — CARRIES NO MONEY, no eod_price dependency,
--   read-only. NO new base table, NO write path, NO new DEFINER, NO new
--   FK-shaped column. Paired with the migration in the SAME PR.
-- =====================================================================
-- ⟦WIRE-VALIDATE⟧ FULLY GREEN — plan(40), 40/40, via `supabase test db
--   --db-url ...scratch330 supabase/tests` (pg_prove, directory-mode so \ir
--   resolves — NEVER bare psql, which exits 0 on a broken plan count) against
--   Architect's ACTUAL COMMITTED migration (fb3e94e,
--   086_fn_subcat_contributors.sql, applied to `scratch330` — 001→085 already
--   present, NON-destructive, `supabase db reset` never invoked). History,
--   because every number in this file has now been wrong at least once and
--   was caught by running something, never by reading it:
--   (1) drafted before Architect's migration existed, against the RATIFIED
--       SIGNATURE only (SELF-330, Architect options-pass 2026-08-20);
--   (2) the entire fixture was dry-run against the LIVE `fn_subcat_market_value`
--       (076/084) before 086 existed, catching an arithmetic error in a_inv's
--       net-zero cash checkpoint (1160.00 written, 1260.00 required);
--   (3) Architect's reconciliation reply surfaced a real per-Wave gap this
--       file had ZERO coverage of — the `lut.users_id = acc.users_id`
--       liability-route fence, a named joint-review-mandatory ground — closed
--       by (LR1-LR3b) and the a_liab/b_liab/d_liab fixture additions, plus
--       (I6-I7)/(S1)/(F1)/(PAR7), all Architect-requested;
--   (4) the FIRST full pg_prove run against Architect's real function found
--       ONE genuine failure: (P1) expected 3, got 2 — `count(distinct
--       sub_cat_id)` silently drops the NULL/Unsorted group from its own
--       count (SQL's COUNT never counts NULL), so a construct meant to prove
--       "3 groups including Unsorted" instead measured "2 non-NULL groups" —
--       the exact NULL-blindness class this file's own (N1)/(N2) instrument
--       section exists to guard against, self-caught in a sibling assertion
--       that used a different NULL-unsafe construct. Fixed in both (P1) and
--       (F1) by counting DISTINCT GROUPS from a subquery (which materializes
--       one row for NULL) rather than COUNT(DISTINCT col).
--   The SECOND full run was 40/40 green. Every number quoted anywhere in this
--   file is measured, not derived on paper. Re-run before trusting it again —
--   this note is a record of what was checked, not a standing guarantee.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/0NN_fn_subcat_contributors.sql (number
--   TBD at reconciliation) — pfin.fn_subcat_contributors(
--     p_as_of date default current_date, p_include_real_estate boolean default false)
--     RETURNS TABLE (sub_cat_id bigint, account_id bigint) SECURITY INVOKER ·
--     STABLE · set search_path = ''. DISTINCT pairs. Tenant scope INHERITED from
--     RLS (same R1 no-tenant-parameter posture as 076) — no cross-tenant param.
--
-- ┌─ BINDING CONDITION 1 (SELF-330, non-optional, same PR) — THE PARITY LEG ──────┐
-- │ DISTINCT sub_cat_id from this map EQUALS DISTINCT sub_cat_id from 076 at       │
-- │ IDENTICAL arguments, BOTH DIRECTIONS — "the ADR-058 Amendment 2 complement-leg │
-- │ discipline": never a count comparison (two different sets of the same          │
-- │ cardinality would pass silently), always an actual set-difference read live    │
-- │ from BOTH functions in the same call. (PAR1-PAR6) below.                       │
-- │ ⚠ THE INSTRUMENT TRAP THIS LEG MUST NOT STEP IN: Postgres `NOT IN (subquery)`  │
-- │ is BLIND whenever the subquery's result set contains a NULL — `x NOT IN        │
-- │ (a,b,NULL)` evaluates every non-matching x to UNKNOWN, not TRUE, so the WHERE   │
-- │ clause silently drops it. Sub-Cat's Unsorted row has sub_cat_id IS NULL, so a   │
-- │ parity check written with `NOT IN` against either function's raw sub_cat_id    │
-- │ list goes VACUOUSLY GREEN the moment either set contains an unclassified row —  │
-- │ which is every non-trivial portfolio. `EXCEPT` is used instead throughout      │
-- │ (PAR1-PAR6): Postgres set operations treat NULL = NULL for row comparison, so   │
-- │ EXCEPT reports the Unsorted row like any other. (N1)/(N2) below are a small,   │
-- │ synthetic, self-contained proof that this distinction is REAL, not asserted.   │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ SELF-330 BINDING CONDITION 4(b) — "contributor folds must match by IS-NULL,  ┐
-- │ never equality" — covered structurally by (D1)/(G3)/(R4)/(PAR1-4): every       │
-- │ Unsorted-row assertion below anchors on `sub_cat_id is null`, never `= null`   │
-- │ (which is always NULL/false in SQL and would silently match zero rows), and    │
-- │ the parity legs use EXCEPT (NULL-safe) rather than NOT IN (NULL-blind) per the  │
-- │ box above.                                                                     │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ SELF-330 BINDING CONDITION 4(a)/(c) — OUT OF SCOPE HERE, ROUTED ─────────────┐
-- │ (a) "the Cash row's contributor set is the widest on the table... by design"   │
-- │ is a PRODUCT observation about this function's honest behaviour, not a defect  │
-- │ to fence — (G2) exercises the underlying mechanism (one Sub-Cat, multiple      │
-- │ accounts) that MAKES it wide; no separate "is it wide" assertion is owed.      │
-- │ (c) the "US - Sector Diversified" twelve-way OR-fold and staleness.ts's        │
-- │ tri-state propagation are APP-LAYER (Frontend/Backend consumer logic over this │
-- │ function's output) — this file proves the DB primitive; the fold itself is the │
-- │ consumer's own test surface, not re-derived here.                              │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised (on the 001→085 stack, same base as 076): 003/006/025
--   (account + rd_access chains), 009 (user_taxonomy), 016/017 (asset registry +
--   global currency-asset rows, asset_id=1..7), 019 (fn_holdings_as_of,
--   quantity<>0), 022 (user_asset_category), 041 (seeded taxonomy vocabulary,
--   reused verbatim), 056 (fn_account_cash_as_of), 058/059 (closure gate + the
--   dated three-conjunct predicate), 076 + 084 (the sibling this battery
--   parity-checks against, AS CURRENTLY LIVE — VERIFIED against the deployed
--   `pg_get_functiondef`, not the 076 file's own originally-authored text: the
--   `user_taxonomy.domain` column no longer exists at all post-084, and the live
--   taxonomy join carries NO domain/element predicate, per 076's OWN battery
--   header Item 2 box — "the join carries no domain predicate at all... true by
--   table identity, not by a runtime conjunct." This battery's fixture and
--   assumed contributor-map join mirror the LIVE composition, not 076's static
--   file text — flagged so a future reader does not diff against the wrong
--   version of 076).
--
-- ┌─ ITEM 1 — DISTINCT MUST ACTUALLY COLLAPSE, PROVEN BY CONSTRUCTION ────────────┐
-- │ A fixture where it WOULDN'T collapse without the keyword: TWO different        │
-- │ unclassified securities (secx, secu) and TWO different Equity-classified       │
-- │ securities (secq, secq2) are held in the SAME account (a_inv). Without DISTINCT │
-- │ each pair emits 2 rows; (D1)/(D2) assert exactly 1. A fixture with no duplicate │
-- │ source rows to begin with would pass this even if the function forgot the      │
-- │ keyword entirely — the point of building the duplicate source, per DESIGN.md's  │
-- │ "build X and watch it go red" discipline.                                      │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 2 — GRANULARITY IS PER-ACCOUNT, NOT PER-SUB-CAT ────────────────────────┐
-- │ The complementary risk to Item 1: a function that (wrongly) grouped by         │
-- │ sub_cat_id ALONE would ALSO pass a naive "no duplicates" check while silently  │
-- │ losing account identity. (G1) a_eq via a_inv AND a_inv2 (two accounts, one     │
-- │ Sub-Cat) = 2 rows, not 1. (G2) a_cd via a_dep1 AND a_dep2 = 2 rows — the same   │
-- │ L1 cash-substrate limit 076 documents (one Sub-Cat per user per currency),      │
-- │ made visible here as TWO contributor rows rather than one merged value. (G3)   │
-- │ the Unsorted group ITSELF is per-account: secw (a_inv2) and secx/secu (a_inv)   │
-- │ both land at sub_cat_id IS NULL but must remain 2 rows, not fold to one.        │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ITEM 3 — THE E2 ZERO-CASH FILTER IS NOT A "VALUATION EXPRESSION" ────────────┐
-- │ 076's cash_leg carries `coalesce(c.balance_native,0) <> 0` — a WHERE predicate  │
-- │ that reads a balance VALUE, sitting right next to the valuation math Shape 1    │
-- │ deletes. If a future edit reads "delete every expression that touches           │
-- │ balance_native" too literally and drops this predicate along with the actual   │
-- │ multiplication, every open zero-cash account manufactures a phantom            │
-- │ (NULL, account_id) contributor row — 076's own documented pre-fix defect       │
-- │ (076 header, measured on the scratch chain), reintroduced one function over.   │
-- │ a_inv's cash sweep is funded to net EXACTLY zero (E2) — checkpoint 1260.00     │
-- │ offsets buys totalling 1365.00 minus the 105.00 secz sell-back, MEASURED not   │
-- │ guessed — so its ABSENCE from the Cash/CD contributor set is a real,           │
-- │ constructed proof, not an accident of an empty fixture — and tenant C (E1)     │
-- │ reproduces 076's own empty-portfolio shape directly, corroborated by (PAR6).   │
-- └───────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: read ADR-011 Decision 4 + Decision 3 LIVE at reconciliation —
--   not restated/counted here (Path B). This battery assumes, pending Architect's
--   actual migration text, ZERO catalogued §10 instances added (read-only, no
--   write path, no credential surface) and Decision-3 family UNCHANGED (no table,
--   no FK-shaped column authored) — the SAME disposition 076 carries. SECURITY
--   DEFINER allowlist assumed UNCHANGED (INVOKER posture, per the ratified shape).
--   ⚠ RE-VERIFY every claim in this paragraph against Architect's committed file
--   and ADR-011 read live before sign-off — this paragraph is drafted, not checked.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '86' for this migration, provisional) + real seeded taxonomy
--   vocabulary (Cash/CD, Marketable Securities/US-06-Financials, Real Estate/
--   Residential, Alternatives/REIT). NO PII / NO real account numbers / NO prod
--   data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set
--   EXPLICITLY. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated. Tenant UUIDs + row ids resolve to psql LITERALS via \gset/\set
--   at role=postgres; every _rls.set_tenant is called at role=postgres and each
--   block restores role=postgres before the next.
--
-- plan(40) BREAKDOWN — see the ⟦WIRE-VALIDATE⟧ note at the top of this file
--   for the run history. 5 isolation (I1-I5) + 2 account-
--   identity isolation (I6-I7) + 1 structural integrity (S1, account_id never
--   null) + 1 fan-out non-degeneracy (F1) + 2 DISTINCT-collapse (D1-D2) +
--   3 granularity (G1-G3) + 4 liability-route (LR1-LR3b) + 4 real-estate
--   (R1-R4) + 2 closure-boundary (B1-B2) + 2 zero-cash/phantom (E1-E2) + 1
--   sold-to-zero population (P1) + 7 parity (PAR1-PAR7, binding condition 1 +
--   the NULL-key corroboration) + 2 instrument self-test (N1-N2) + 2
--   corrupt-the-control (X1-X2) + 2 grant/negative (G1n-G2n) = 40. (I6-I7),
--   (S1), (F1), (LR1-LR3b) and (PAR7) were added after Architect's committed
--   migration (fb3e94e -> 086_fn_subcat_contributors.sql) surfaced two things
--   this file's first draft had zero coverage of: the `lut.users_id =
--   acc.users_id` liability-route fence (a joint-review-mandatory ground
--   Architect named explicitly) and the account-identity disclosure surface
--   as a distinct isolation axis from 076's sub_cat_id-level checks.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(40);

\set ta '00000000-0000-0000-0000-000000000a86'
\set tb '00000000-0000-0000-0000-000000000b86'
\set tc '00000000-0000-0000-0000-000000000c86'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL -> 016/017 #7: readable by every tenant's
--   INVOKER). Prices seeded for parity-call realism even though the contributor
--   map itself has no valuation dependency (076's parallel call still prices).
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCX86','Sec X unclassified (a_inv)') returning asset_id as secx \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCU86','Sec U unclassified (a_inv, pairs with secx for D1)') returning asset_id as secu \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCQ86','Sec Q Equity (a_inv)') returning asset_id as secq \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCQ2_86','Sec Q2 Equity (a_inv, pairs with secq for D2)') returning asset_id as secq2 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCQ3_86','Sec Q3 Equity (a_inv2, for G1 cross-account)') returning asset_id as secq3 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCW86','Sec W unclassified (a_inv2, for G3 cross-account NULL group)') returning asset_id as secw \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCRE86','Sec RE Real Estate (a_inv)') returning asset_id as secre \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCALT86','Sec Alt REIT (a_inv)') returning asset_id as secalt \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCZ86','Sec Z sold-to-zero (a_inv, for P1)') returning asset_id as secz \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SCB86','Sec B tenant-B control') returning asset_id as secb \gset

insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:secx,'2026-07-01','market_feed',200.00),
  (:secu,'2026-07-01','market_feed',90.00),
  (:secq,'2026-07-01','market_feed',400.00),
  (:secq2,'2026-07-01','market_feed',150.00),
  (:secq3,'2026-07-01','market_feed',300.00),
  (:secw,'2026-07-01','market_feed',120.00),
  (:secre,'2026-07-01','market_feed',250.00),
  (:secalt,'2026-07-01','market_feed',175.00),
  (:secz,'2026-07-01','market_feed',50.00),
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
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta','Liabilities','Liability Balances','liability') returning id as a_lb \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'tb','Marketable Securities','US-06-Financials','asset') returning id as b_eq \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'tb','Liabilities','Liability Balances','liability') returning id as b_lb \gset

-- ---------------------------------------------------------------------
-- TENANT A — a_inv (secx, secu unclassified; secq, secq2 Equity; secre Real
--   Estate; secalt Alternatives/REIT; secz sold-to-zero). Funded to NET EXACTLY
--   ZERO cash (checkpoint 1260.00 offsets buys 1365.00 minus the secz sell-back
--   105.00, MEASURED not guessed) so (E2)'s absence proof is real, not an
--   accident of an unfunded account.
--   a_inv2 — secq3 (Equity, for G1 cross-account) + secw (unclassified, for G3
--   cross-account NULL-group). Funded to net exactly zero (checkpoint 420.00 =
--   buys 300.00 + 120.00) for the same reason.
--   a_dep1/a_dep2 — TWO SCOPES ('personal'/'trust'), pure cash (item 2 / G2).
--   a_close — the closure-boundary account (B1/B2): funded 500, zeroed via a
--   second checkpoint dated 07-14, closed 07-15 through the REAL 058 gate.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-inv-86','investment','household','taxable') returning account_id as a_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_inv, 1260.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_inv,'2026-07-05',-200.00,1,:secx,200.00,'standard','buy-x'),
  (:a_inv,'2026-07-05',-90.00,1,:secu,90.00,'standard','buy-u'),
  (:a_inv,'2026-07-05',-400.00,1,:secq,400.00,'standard','buy-q'),
  (:a_inv,'2026-07-05',-150.00,1,:secq2,150.00,'standard','buy-q2'),
  (:a_inv,'2026-07-05',-250.00,1,:secre,250.00,'standard','buy-re'),
  (:a_inv,'2026-07-05',-175.00,1,:secalt,175.00,'standard','buy-alt'),
  (:a_inv,'2026-07-05',-100.00,2,:secz,100.00,'standard','buy-z'),
  (:a_inv,'2026-07-20', 105.00,-2,:secz,0.00,'standard','sell-z-to-zero');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-inv2-86','investment','household','taxable') returning account_id as a_inv2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_inv2, 420.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_inv2,'2026-07-05',-300.00,1,:secq3,300.00,'standard','buy-q3'),
  (:a_inv2,'2026-07-05',-120.00,1,:secw,120.00,'standard','buy-w');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-dep1-86','depository','personal','taxable') returning account_id as a_dep1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_dep1, 300.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-dep2-86','depository','trust','taxable') returning account_id as a_dep2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_dep2, 200.00, 'USD', '2026-07-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-close-86','depository','household','taxable') returning account_id as a_close \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_close, 500.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_close, 0.00, 'USD', '2026-07-14', 'seed');
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-07-15'::timestamptz where account_id = :a_close;

-- a_liab — the LIABILITY ROUTE fixture (081, mirrored verbatim into 086's
--   cash_leg per Architect's header). This route is NEW territory for THIS
--   battery: none of the accounts above are account_type='liability', so
--   without this account the string-label-matched `lut.users_id =
--   acc.users_id` join (Architect: "the SOLE tenant discriminator on a join
--   keyed by SHARED-VOCABULARY STRING LABELS... fails OPEN under an RLS
--   regression where the id-keyed sibling joins fail CLOSED") would be
--   entirely UNEXERCISED by this file. account_type='liability' routes here
--   by NAME (cat='Liabilities', sub_cat='Liability Balances'), not through
--   the currency-asset junction — added DIRECTLY to tenant A's existing
--   fixture (not a separate tenant) so the EXISTING PAR1-4 parity legs gain
--   liability-route coverage for free, rather than needing a duplicate set.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-liab-86','liability','household','taxable') returning account_id as a_liab \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_liab, -300.00, 'USD', '2026-07-01', 'seed');

-- classify: secq/secq2/secq3 -> Equity; secre -> Real Estate; secalt ->
--   Alternatives/REIT; the GLOBAL USD currency-asset (asset_id=1, seeded 016) ->
--   Cash/CD. secx, secu, secw: NO junction row (unclassified, deliberately, for
--   D1/G3). secz: doesn't matter, zero position by the query date (P1).
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', :secq, :a_eq),
  (:'ta', :secq2, :a_eq),
  (:'ta', :secq3, :a_eq),
  (:'ta', :secre, :a_re),
  (:'ta', :secalt, :a_alt),
  (:'ta', 1, :a_cd);

-- ---------------------------------------------------------------------
-- TENANT B — isolation control. b_inv holds secb, classified Equity. b_liab is
--   B's OWN liability account, routed to B's OWN Liability Balances row
--   (b_lb) — a DISTINCT sub_cat_id and a DISTINCT account_id from A's a_lb/
--   a_liab, for the (LR3) liability-route isolation legs.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-inv-86','investment','household','taxable') returning account_id as b_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_inv, 60.00, 'USD', '2026-07-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:b_inv,'2026-07-05',-60.00,1,:secb,60.00,'standard','buy-b');
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'tb', :secb, :b_eq);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-liab-86','liability','household','taxable') returning account_id as b_liab \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_liab, -120.00, 'USD', '2026-07-01', 'seed');

-- ---------------------------------------------------------------------
-- TENANT C — empty-portfolio / phantom-Unsorted fence (E1). One OPEN depository
--   account, NO checkpoint, NO trans, NO holdings — 076's own documented shape.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tc','c-dep-86','depository','household','taxable') returning account_id as c_dep \gset

-- ---------------------------------------------------------------------
-- TENANT D — LIABILITY ROUTE, MISSING-TARGET (LR2). A liability-type account
--   whose OWNER has NO 'Liabilities'/'Liability Balances' row at all (never
--   inserted, not merely deleted — the 081 battery's own L4a/L4b shape,
--   simplified). The LEFT JOIN to `lut` degrades to NULL keys, so the
--   contributor pair must land at (NULL, d_liab) -- never dropped, never
--   silently misattributed to another tenant's same-named row.
-- ---------------------------------------------------------------------
\set td '00000000-0000-0000-0000-000000000d86'
insert into auth.users (id) values (:'td');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'td','d-liab-86','liability','household','taxable') returning account_id as d_liab \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:d_liab, -75.00, 'USD', '2026-07-01', 'seed');


-- =====================================================================
-- ISOLATION (I1-I5) — the load-bearing cross-tenant proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (I1) A's contributor set for a_eq = EXACTLY {a_inv, a_inv2} — own accounts only.
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_eq),
  array[:a_inv, :a_inv2]::bigint[],
  '(I1) A''s a_eq contributor set = EXACTLY {a_inv, a_inv2} — own accounts only, cross-account granularity preserved'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
-- (I2) B's total contributor row count = EXACTLY 2 -- (b_eq, b_inv) + (b_lb,
--      b_liab) -- does not include any of A's rows.
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true)),
  2::bigint,
  '(I2) B''s contributor map = EXACTLY 2 rows: (b_eq, b_inv) + (b_lb, b_liab) — cross-tenant fail-closed: none of A''s pairs leak in'
);
-- (I4) A's a_eq sub_cat_id does not appear in B's result set.
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_eq),
  '(I4) cross-tenant read fails closed: B''s call to fn_subcat_contributors never returns A''s Equity sub_cat_id (a_eq)'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (I3) B's Equity Sub-Cat (b_eq) does not appear in A's result set (reverse direction).
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :b_eq),
  '(I3) cross-tenant read fails closed (reverse): A''s call never returns B''s Equity sub_cat_id (b_eq)'
);
select set_config('role', 'postgres', true);
-- (I5) non-vacuous: both A's and B's contributor sets are demonstrably non-empty.
select ok(
  (select count(*) > 0 from pfin.fn_subcat_contributors('2026-07-25'::date, true))
  and 2 > 0,  -- B's count=2 already asserted at (I2); restated for a self-contained companion
  '(I5) non-vacuous companion: A holds real contributor rows and B holds exactly 2 — (I3)/(I4)''s absences are boundary denials, not an empty DB'
);

-- (I6)/(I7) — ACCOUNT-IDENTITY isolation, Architect's own distinction: "this
--   function discloses WHICH ACCOUNTS, not sums, so its isolation blast radius
--   differs in kind from 076's, and 076's battery does not cover it." (I1)-(I5)
--   above test sub_cat_id-level absence (inherited from 076's own pattern);
--   these test account_id-level absence directly — a hypothetically different
--   failure mode (e.g. an account-resolution join matching across tenants
--   without ever producing a foreign sub_cat_id) that sub_cat_id checks alone
--   cannot rule out.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id in (:b_inv, :b_liab)),
  '(I6) ACCOUNT-IDENTITY isolation: A''s call never returns EITHER of B''s account_ids (b_inv, b_liab), under ANY sub_cat_id -- checked directly, not inferred from sub_cat_id absence'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id in (:a_inv, :a_inv2, :a_dep1, :a_dep2, :a_close, :a_liab)),
  '(I7) ACCOUNT-IDENTITY isolation (reverse): B''s call never returns ANY of A''s six account_ids, under ANY sub_cat_id'
);
select set_config('role', 'postgres', true);

-- (S1) STRUCTURAL INTEGRITY: account_id is NEVER NULL, per the migration's own
--   CONTRACT ("account_id is NEVER NULL... on the cash leg pfin.account is
--   joined directly and account_id is its primary key"). RED if a future edit
--   introduced a LEFT JOIN to pfin.account on the securities leg elsewhere, or
--   let a NULL account_id through some other path.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id is null),
  0::bigint,
  '(S1) STRUCTURAL: account_id IS NEVER NULL across A''s entire contributor set -- the migration''s own CONTRACT claim, re-verified rather than trusted'
);
select set_config('role', 'postgres', true);

-- (F1) FAN-OUT NON-DEGENERACY (Architect): total contributor row count is
--   STRICTLY GREATER than the distinct sub_cat_id GROUP count for tenant A --
--   proves the map is genuinely per-account, not a degenerate 1:1 restatement
--   of fn_subcat_market_value's own row set wearing an account_id column.
--   (G1-G3) already prove this at specific points; this is the blanket
--   declarative companion Architect asked for directly. ⚠ Counted via COUNT(*)
--   over a DISTINCT subquery, NOT count(distinct sub_cat_id) -- (P1)'s own
--   fix applies here too: the latter silently excludes the NULL/Unsorted
--   group, which would make this inequality pass on a smaller, artificially
--   easier margin than the real group count, rather than on genuine fan-out.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true))
  > (select count(*) from (select distinct sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, true)) d),
  '(F1) fan-out is real: A''s total contributor PAIR count is STRICTLY GREATER than A''s distinct sub_cat_id GROUP count (NULL group counted as one group, via a DISTINCT subquery) -- at least one Sub-Cat has more than one contributing account (the NULL group and a_eq both do, per G1/G3), so the map cannot be a 1:1 restatement of fn_subcat_market_value''s rows'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- DISTINCT-COLLAPSE (D1-D2) — item 1. Built to duplicate WITHOUT the keyword.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (D1) NULL-group same-account collapse: secx AND secu are TWO different
--      unclassified securities in the SAME account (a_inv) — exactly 1 row.
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id is null and account_id = :a_inv),
  1::bigint,
  '(D1) DISTINCT collapse, NULL group: secx + secu (2 different unclassified securities, SAME account a_inv) -> exactly 1 (NULL, a_inv) row, not 2 -- RED if the function omitted DISTINCT'
);
-- (D2) same-Sub-Cat same-account collapse: secq AND secq2, both Equity, SAME account.
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_eq and account_id = :a_inv),
  1::bigint,
  '(D2) DISTINCT collapse, classified group: secq + secq2 (2 different Equity-classified securities, SAME account a_inv) -> exactly 1 (a_eq, a_inv) row, not 2'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- GRANULARITY (G1-G3) — item 2, the complementary risk to D1/D2.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (G1) a_eq via TWO DIFFERENT accounts (a_inv, a_inv2) -> 2 rows, not collapsed
--      to 1 -- restates (I1) as a direct count for legibility.
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_eq),
  2::bigint,
  '(G1) granularity: a_eq contributor rows = EXACTLY 2 (a_inv, a_inv2) -- a function that grouped by sub_cat_id alone (losing account identity) would wrongly collapse this to 1'
);
-- (G2) a_cd (Cash/CD) via TWO DIFFERENT scopes/accounts (a_dep1 personal,
--      a_dep2 trust) -> 2 rows -- the L1 cash-substrate limit 076 documents as a
--      VALUE limit, here visible as ACCOUNT-level granularity instead. Queried
--      at 07-25 (post-closure) so a_close (excluded by then, see B2) does not
--      add a third row.
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_cd),
  array[:a_dep1, :a_dep2]::bigint[],
  '(G2) granularity: a_cd contributor set = EXACTLY {a_dep1, a_dep2} -- TWO scopes (personal/trust) reconciled by the shared global-currency classification, kept as TWO account rows, not merged into one'
);
-- (G3) the Unsorted group is ALSO per-account: secw (a_inv2) is a DIFFERENT
--      contributor row from secx/secu (a_inv), both under sub_cat_id IS NULL.
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id is null),
  array[:a_inv, :a_inv2]::bigint[],
  '(G3) granularity, NULL group: Unsorted contributor set = EXACTLY {a_inv, a_inv2} -- (D1) proved account-internal collapse; this proves the NULL group is NOT globally collapsed to one row regardless of account'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LIABILITY ROUTE (LR1-LR3b) — Architect's own JOINT-REVIEW-MANDATORY ground
--   (1)+(2): the `lut.users_id = acc.users_id` conjunct is "the SOLE tenant
--   discriminator on a join keyed by SHARED-VOCABULARY STRING LABELS", unlike
--   the id-keyed uac/ut joins elsewhere in this function, which are protected
--   twice (022's own write-time fence PLUS read-time RLS). Before this
--   section, NOTHING in this file exercised account_type='liability' at all --
--   a real per-Wave RLS gap on a fence the migration's own header names as
--   dangerous. a_liab/b_liab/d_liab were added to the fixture ABOVE
--   specifically to close it; (LR1-LR3b) are the assertions that exercise them.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (LR1) tenant A's liability account routes to A's OWN Liability Balances row.
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_lb and account_id = :a_liab),
  '(LR1) LIABILITY ROUTE: (a_lb, a_liab) is a contributor pair -- a_liab (account_type=liability) routes to A''s OWN Liability Balances row by NAME, not through the currency-asset junction'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'td'::uuid);
-- (LR2) missing-target degrade: tenant D's liability account has NO own
--       Liability Balances row -- the LEFT JOIN to `lut` degrades to a NULL
--       key, so the pair must land at (NULL, d_liab), never dropped.
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id is null and account_id = :d_liab),
  '(LR2) LIABILITY ROUTE, missing-target: D holds a liability account with NO own Liability Balances row -- (NULL, d_liab) is a contributor pair, proving the LEFT JOIN degrades rather than dropping the row or silently matching a DIFFERENT tenant''s same-named row'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (LR3a) A's call never returns B's liability account_id (b_liab), under ANY
--        sub_cat_id -- including A's OWN a_lb (the shared-vocabulary-label
--        risk Architect names: could a foreign account_id land under the
--        CALLER'S OWN Liability Balances sub_cat_id if the string-matched
--        join misidentified the owner?).
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id = :b_liab),
  '(LR3a) LIABILITY ROUTE isolation: A''s call never returns B''s liability account_id (b_liab) -- the `lut.users_id = acc.users_id` conjunct holds, verified rather than assumed (081''s own I1/I2 shape, re-proven here for account-identity rather than value)'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
-- (LR3b) reverse: B's call never returns A's liability account_id (a_liab).
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id = :a_liab),
  '(LR3b) LIABILITY ROUTE isolation (reverse): B''s call never returns A''s liability account_id (a_liab)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- REAL ESTATE (R1-R4) — presence/absence, no value to toggle here.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (R1) include_re=false: NO (a_re, a_inv) pair -- ABSENCE, not a zero-valued row
--      (there is no value here at all, only presence).
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, false) where sub_cat_id = :a_re),
  '(R1) p_include_real_estate=FALSE: the Real Estate Sub-Cat (a_re) has NO contributor row at all'
);
-- (R2) include_re=true: the SAME pair now appears.
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_re and account_id = :a_inv),
  '(R2) p_include_real_estate=TRUE: (a_re, a_inv) now appears -- (R1)''s absence is a genuine toggle, non-vacuous'
);
-- (R3) Alternatives/REIT is NOT swept by the flag, in EITHER state.
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, false) where sub_cat_id = :a_alt and account_id = :a_inv)
  and
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_alt and account_id = :a_inv),
  '(R3) Alternatives/REIT (a_alt, a_inv) present in BOTH states -- exact match on cat=''Real Estate'', a DIFFERENT cat is never touched by the flag'
);
-- (R4) the Unsorted group's account set is IDENTICAL in both states -- the flag
--      never touches sub_cat_id IS NULL rows.
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_subcat_contributors('2026-07-25'::date, false) where sub_cat_id is null),
  (select array_agg(account_id order by account_id) from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id is null),
  '(R4) Unsorted contributor set {a_inv, a_inv2} is IDENTICAL whether p_include_real_estate is false or true -- a NULL cat cannot be known to be Real Estate'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- CLOSURE BOUNDARY (B1-B2) — a_close, presence/absence not value.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (B1) at 07-10 (closed_at 07-15 is STRICTLY AFTER p_as_of): a_close is OPEN-AS-OF
--      and its real 500.00 cash classifies it into (a_cd, a_close).
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-10'::date, true) where sub_cat_id = :a_cd and account_id = :a_close),
  '(B1) closure boundary, reachable leg: at 07-10, closed_at (07-15) is STRICTLY AFTER p_as_of -> (a_cd, a_close) IS a contributor pair'
);
-- (B2) at 07-15 (=closed_at): a_close is excluded entirely.
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-15'::date, true) where account_id = :a_close),
  '(B2) closure boundary: at 07-15 (=closed_at), a_close contributes to NOTHING -- RED if the predicate excluded a still-open account (B1 would also fail) or failed to exclude at the boundary date'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- ZERO-CASH / PHANTOM-UNSORTED (E1-E2) — item 3.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
-- (E1) tenant C: one OPEN account, zero cash, zero holdings -> the EMPTY SET,
--      not a synthesized (NULL, c_dep) row.
select is(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true)),
  0::bigint,
  '(E1) empty portfolio -> EMPTY SET: tenant C''s one open zero-cash/zero-holdings account contributes NOTHING -- ZERO rows, not a manufactured (NULL, c_dep) row'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (E2) a_inv's own cash sweep is funded to net EXACTLY zero (checkpoint 1260.00
--      offsets 1365.00 of buys minus 105.00 sell-back) -- its cash leg must emit
--      NO row, so (a_cd, a_inv) must be ABSENT despite a_inv otherwise being a
--      heavy contributor via its securities.
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id = :a_cd and account_id = :a_inv),
  '(E2) a_inv''s net-zero cash sweep produces NO (a_cd, a_inv) row -- RED if the zero-cash filter (076''s `coalesce(balance,0)<>0`) were dropped along with the deleted valuation math it sits beside'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- SOLD-TO-ZERO POPULATION (P1) — secz contributes nothing.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (P1) a_inv's own distinct Sub-Cat contribution at include_re=false = EXACTLY
--      {NULL, a_eq, a_alt} -- 3, MEASURED via a REAL pg_prove run against
--      Architect's committed function (not reasoned on paper). Two wrong
--      drafts of this leg, in order: (1) "2", forgetting a_inv also holds
--      secalt/Alternatives-REIT, which is NOT swept by the flag (see R3); (2)
--      `count(distinct sub_cat_id)` — SQL's COUNT never counts a NULL, so that
--      construct silently drops the Unsorted group from ITS OWN count and
--      reports 2 even though 3 groups genuinely exist -- caught by pg_prove
--      reporting "have: 2 want: 3" against the live function, the exact
--      NULL-blindness class (N1)/(N2) exist to guard against, self-caught in
--      the guard's own sibling assertion. Fixed by counting the DISTINCT
--      GROUPS from a subquery (which materializes one row for NULL) rather
--      than COUNT(DISTINCT col) (which cannot). secz (bought then fully sold
--      before p_as_of) and secre (excluded by the flag) contribute NOTHING
--      extra; secq/secq2 already collapsed to 1 by (D2).
select is(
  (select count(*) from (
    select distinct sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, false) where account_id = :a_inv
  ) d),
  3::bigint,
  '(P1) a_inv''s distinct Sub-Cat contribution at include_re=false = EXACTLY 3 (Unsorted + Equity + Alternatives/REIT) -- fn_holdings_as_of''s quantity<>0 filter means the fully-sold secz emits ZERO rows, absent not phantom-zero; Real Estate is the only leg the flag removes. Counted via COUNT(*) over a DISTINCT subquery, NOT count(distinct sub_cat_id) -- the latter silently excludes the NULL/Unsorted group from its own count'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- PARITY (PAR1-PAR6) — BINDING CONDITION 1, the non-optional SELF-330 leg.
--   EXCEPT throughout, never NOT IN -- see the header box on the NULL trap.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (PAR1) forward, include_re=false: contributor sub_cat_id set has nothing
--        market_value's set lacks.
select is(
  (select count(*) from (
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, false)
    except
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, false)
  ) d),
  0::bigint,
  '(PAR1) ⭐ PARITY forward, include_re=false: contributor sub_cat_id set EXCEPT market_value sub_cat_id set = EMPTY (EXCEPT, NULL-safe, per the header box -- catches the Unsorted row like any other member)'
);
-- (PAR2) reverse, include_re=false.
select is(
  (select count(*) from (
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, false)
    except
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, false)
  ) d),
  0::bigint,
  '(PAR2) ⭐ PARITY reverse, include_re=false: market_value sub_cat_id set EXCEPT contributor sub_cat_id set = EMPTY'
);
-- (PAR3) forward, include_re=true.
select is(
  (select count(*) from (
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, true)
    except
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, true)
  ) d),
  0::bigint,
  '(PAR3) ⭐ PARITY forward, include_re=true: contributor sub_cat_id set EXCEPT market_value sub_cat_id set = EMPTY -- both flag states asserted, not just one'
);
-- (PAR4) reverse, include_re=true.
select is(
  (select count(*) from (
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, true)
    except
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, true)
  ) d),
  0::bigint,
  '(PAR4) ⭐ PARITY reverse, include_re=true: market_value sub_cat_id set EXCEPT contributor sub_cat_id set = EMPTY'
);
-- (PAR5) non-vacuous companion: both sets are demonstrably non-empty at
--        include_re=true -- (PAR1-4)'s emptiness is not two empty sets agreeing
--        trivially. count(*) > 0, NOT count(distinct sub_cat_id) > 0: the
--        latter is NULL-blind (same class as P1's own fix) and would read a
--        fixture whose ONLY row is the NULL/Unsorted one as vacuous -- fails
--        CLOSED here (a false RED, not a false GREEN), lower stakes than
--        (P1)'s own miscount but the same root, hardened for consistency
--        with the discipline this file's header now states.
select ok(
  (select count(*) from pfin.fn_subcat_contributors('2026-07-25'::date, true)) > 0
  and
  (select count(*) from pfin.fn_subcat_market_value('2026-07-25'::date, true)) > 0,
  '(PAR5) non-vacuous companion: both the contributor map and market_value return REAL, non-empty sub_cat_id sets for tenant A -- (PAR1-4) are not two empty sets agreeing by construction'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tc'::uuid);
-- (PAR6) CORROBORATING (not load-bearing): tenant C's parity also holds --
--        both functions agree on the EMPTY SET. Restates (E1) from the parity
--        angle; kept labelled as corroborating per DESIGN.md's discipline that a
--        probe kept for corroboration must say so in its own message.
select ok(
  not exists (
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, true)
    except
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, true)
  )
  and not exists (
    select sub_cat_id from pfin.fn_subcat_market_value('2026-07-25'::date, true)
    except
    select sub_cat_id from pfin.fn_subcat_contributors('2026-07-25'::date, true)
  ),
  '(PAR6) CORROBORATING, not load-bearing: tenant C''s empty portfolio parity-checks too -- both functions agree on the EMPTY SET; (E1)/(PAR1-4) are the load-bearing legs'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
-- (PAR7) CORROBORATING (Architect's own request): the NULL key is INDEPENDENTLY
--        present in BOTH functions' raw output for tenant A, asserted by
--        direct existence rather than through EXCEPT -- PAR1/PAR2 already
--        prove the two sets AGREE including on NULL, but agreement alone
--        cannot distinguish "both correctly show it" from "both wrongly omit
--        it" (two empty sets trivially agree too, per (PAR5)'s own point).
--        This closes that gap for the specific NULL key.
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where sub_cat_id is null)
  and
  exists (select 1 from pfin.fn_subcat_market_value('2026-07-25'::date, true) where sub_cat_id is null),
  '(PAR7) CORROBORATING: the Unsorted (NULL) key is directly present in BOTH fn_subcat_contributors AND fn_subcat_market_value for tenant A -- not merely "agreeing" per PAR1/PAR2, which two functions that both silently dropped it would also do'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- INSTRUMENT SELF-TEST (N1-N2) — proving the NOT IN trap is REAL, and that
--   EXCEPT (used throughout PAR1-6 above) does not step in it. Synthetic,
--   self-contained -- no dependency on either production function.
-- =====================================================================
-- (N1) the trap FIRES: a genuinely differing probe value (99) evaluated against
--      a target list containing NULL via NOT IN is silently excluded from the
--      "difference" result -- NOT IN reports NO divergence even though 99 is
--      plainly not in {1,2,NULL}.
select is(
  (select count(*) from (select unnest(array[99]) as v) probe
    where probe.v not in (select unnest(array[1,2,null]::int[]))),
  0::bigint,
  '(N1) INSTRUMENT: NOT IN against a target set containing NULL is BLIND -- probe value 99 (genuinely absent from {1,2,NULL}) is wrongly reported as "not different" (0 rows), because `99 <> NULL` is UNKNOWN and poisons the whole AND chain. This is the exact failure mode a parity check on the Unsorted (NULL) group must not use'
);
-- (N2) the SAME comparison via EXCEPT correctly reports the divergence.
select is(
  (select count(*) from (
    select unnest(array[99]) except select unnest(array[1,2,null]::int[])
  ) d),
  1::bigint,
  '(N2) INSTRUMENT: the SAME probe (99) via EXCEPT correctly reports 1 row of divergence -- EXCEPT is NULL-safe for row comparison, which is why (PAR1-PAR6) use it and not NOT IN'
);

-- =====================================================================
-- CORRUPT-THE-CONTROL (X1-X2) — the inherited-fence claim, MEASURED (076's own
--   discipline, carried here because this function is the SAME
--   JOINT-REVIEW-MANDATORY shape: a financial-calc-adjacent multi-tenant read
--   whose isolation is entirely INHERITED).
-- =====================================================================
savepoint sp_corrupt1;
-- (X1) account_select ALONE, corrupted open: A's contributor set is UNCHANGED --
--      B's (b_eq, b_inv) does NOT leak in, via the same defense-in-depth 076
--      measured (fn_holdings_as_of / fn_account_cash_as_of gate through
--      account_trans's / account_balance_checkpoint's OWN policies).
alter policy account_select on pfin.account using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  not exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id = :b_inv),
  '(X1) DEFENSE IN DEPTH, measured: with `account_select` alone broken OPEN, A''s contributor set still does NOT include b_inv -- account_trans_select / account_balance_checkpoint_select independently gate the value that would carry it in'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_corrupt1;

savepoint sp_corrupt2;
-- (X2) ⭐ ALL THREE relations corrupted together: account_select +
--      account_trans_select + account_balance_checkpoint_select. NOW b_inv
--      leaks into A's contributor set -- confirming isolation here really is
--      entirely INHERITED, the same three relations 076 identified.
alter policy account_select on pfin.account using (true);
alter policy account_trans_select on pfin.account_trans using (true);
alter policy account_balance_checkpoint_select on pfin.account_balance_checkpoint using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from pfin.fn_subcat_contributors('2026-07-25'::date, true) where account_id = :b_inv),
  '(X2) ⭐ CORRUPT-THE-CONTROL, load-bearing: with all three relations broken OPEN, b_inv NOW appears in A''s contributor set -- proving the tenant fence is entirely INHERITED, identifying the same specific three relations as 076 (X1/X2)'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_corrupt2;

-- =====================================================================
-- GRANTS (G1n-G2n) — named with an `n` suffix to avoid colliding with the G1-G3
--   granularity labels above.
-- =====================================================================
-- (G1n) anon zero-grant: no EXECUTE.
select set_config('role', 'anon', true);
select throws_ok(
  $$ select * from pfin.fn_subcat_contributors('2026-07-25'::date, true) $$,
  '42501', null,
  '(G1n) anon zero-grant: EXECUTE is revoked from public and not granted to anon -- anon cannot invoke fn_subcat_contributors at all'
);
select set_config('role', 'postgres', true);

-- (G2n) as_of predating all data: returns the EMPTY SET for a real tenant.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.fn_subcat_contributors('2020-01-01'::date, true)),
  0::bigint,
  '(G2n) as_of predating all data: A''s call at 2020-01-01 (before every seeded trans) returns the EMPTY SET -- no error, no synthesized row'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
