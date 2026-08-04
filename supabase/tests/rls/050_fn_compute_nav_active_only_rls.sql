-- =====================================================================
-- Per-Wave battery — pfin.fn_compute_nav(p_as_of, p_active_only) + the 1-arg wrapper
--   (SELF-322 / 050; V1.1 "Net worth full"; ADR-039 Option C — parameterize is_active scoping;
--   fixes the §2.1.1 headline vs §2.1.5 composition scope gap that QA surfaced during the 049
--   battery). Paired with the migration in the SAME PR (verify-paired-artifacts discipline).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/050_fn_compute_nav_active_only.sql
--   (1) pfin.fn_compute_nav(p_as_of date, p_active_only boolean) — SECURITY INVOKER. 019's
--       uniform roll-forward valuation VERBATIM + is_active scoping GATED on p_active_only:
--       FALSE ⇒ byte-identical to 019 (ALL accounts); TRUE ⇒ current-state (active only). Both
--       legs gate (securities via LEFT JOIN pfin.account on holdings.account_id + coalesce
--       is_active fail-closed; cash via pfin.account).
--   (2) pfin.fn_compute_nav(p_as_of date) — SECURITY INVOKER 1-arg WRAPPER, delegates to
--       (p_as_of, false) = all-accounts. Signature-identical to 019 (CREATE OR REPLACE, NO DROP)
--       so 037 fn_gl_entries' Unrealized memo (a book-domain all-accounts reconciliation) is
--       UNTOUCHED.
--
-- CROSS-MIGRATION DEPENDENCY (same-PR): (A6) reconciles §2.1.5 via pfin.fn_account_unrealized_gl
--   (049). 049 + 050 ship in the SAME PR (049 was the surface that exposed SELF-322). CI applies
--   001→050 (incl. 049) on bring-up, so the fn exists at test time. RED-until-049+050-applied is
--   expected on any pre-050 stack.
--
-- Prereqs exercised (001→050 reset stack): 003 (pfin.account.is_active NOT NULL default true +
--   direct-owner RLS + fn_grant_creator_access DEFINER trigger); 004/006 (account_trans immutable
--   + rd/wr RLS); 016/017 (pfin.asset global-OR-owned + security_id/quantity/cost_basis); 019
--   (fn_holdings_as_of + eod_price D-first LOCF + account_balance_checkpoint roll-forward, the
--   engine 050 reproduces); 035/037 (fn_gl_entries — the memo whose 1-arg NAV dependency must stay
--   all-accounts); 049 (fn_account_unrealized_gl — the §2.1.5 composition). auth.uid() reads
--   request.jwt.claims (PG 17 stack).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (A) VALUE-BEARING INACTIVE scoping — the SELF-322 fix: a1/a2/a3 active + a4 INACTIVE          │
-- │     INVESTMENT holding securities (1500 sec + 0 cash). fn_compute_nav(as_of,TRUE) EXCLUDES    │
-- │     a4 (6500); (as_of,FALSE) + 1-arg INCLUDE it (8000). Exercises BOTH legs' is_active gating │
-- │     (a4 holds securities → the LEFT-JOIN security-leg gate is non-vacuous). RED if either leg │
-- │     failed to gate on p_active_only, or if the wrapper stopped delegating to false.           │
-- │ (A6) §2.1.1 == §2.1.5 RECONCILIATION (the SELF-322 CONSISTENCY AC): Σ 049.current_market_     │
-- │     value over A's ACTIVE accounts == fn_compute_nav(as_of, TRUE). The whole point of 050.    │
-- │ (A8) 037 MEMO UNCHANGED: fn_gl_entries(as_of) still balances Σ(amount_book)=0 with a4's       │
-- │     inactive holding present — the memo's 1-arg NAV stayed all-accounts (wrapper → false).    │
-- │ (L) LIABILITY R-7 sign: a liability-only tenant → fn_compute_nav NEGATIVE on BOTH true+false. │
-- │ (F) ALL-ACTIVE tenant → all THREE signatures AGREE (true == false == 1-arg) over a real       │
-- │     nonzero portfolio (active-only is a no-op when nothing is inactive).                       │
-- │ (Z) INVOKER cross-tenant FAILS CLOSED: a tenant owning NO accounts → 0 on ALL THREE sigs,     │
-- │     while the DB demonstrably holds value-bearing accounts (A's NAV>0) — the 0 is RLS          │
-- │     isolation, not an empty DB. RED (>0) if any signature were DEFINER / lost RLS.             │
-- │ (H) AS-OF unchanged on the FALSE path: fn_compute_nav(hist,false) LOCFs the historical price  │
-- │     (500) and DIFFERS from current (600) — the false path preserves 019's as-of behavior; the │
-- │     1-arg wrapper preserves it too.                                                            │
-- │ (U) UNPRICED asset → 0, never NaN/NULL (019 SUM-NULL fence preserved): an active investment    │
-- │     holding a security with NO eod_price contributes 0 (not NULL) on both true+false paths.    │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; two authenticated-tier INVOKER
--   READ functions — no service_role, no credential, no admission surface). Decision-3 family
--   UNCHANGED (no new FK-shaped column). SECURITY DEFINER allowlist UNCHANGED at 4 (both INVOKER).
--   This battery introduces no catalogued instance; it is the pgTAP proof the scoping is correct
--   and cross-tenant isolation is preserved across both signatures.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b() + fixed
--   literals for L/F/Z/H; NO PII / NO real account numbers / NO real Plaid tokens / NO prod data.
--   GLOBAL securities carry users_id NULL (016/017 #7). All seeds PRIVILEGED (role=postgres;
--   RLS+ACL bypassed) with users_id set EXPLICITLY; the fns are invoked ONLY under authenticated
--   tenant contexts. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121): `_rls` grants no USAGE to authenticated. Tenant UUIDs + account
--   ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant is called at
--   role=postgres and each block restores role=postgres before the next. The fns / pgTAP
--   is/ok/cmp_ok/isnt under authenticated is proven safe by the green 019/035/049 batteries.
--
-- ⟦WIRE-VALIDATE⟧ authored + smoke-verified GREEN via a transient apply+rollback of 049+050 against
--   the 001→048 landed local stack (NON-destructive; no `supabase db reset` — F/CTO local data
--   intact). Authoritative gate is CI pg_prove directory-mode after Backend's clean-apply. plan(23).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- plan = 27: BLOCK A 12 (A1..A8 + A9..A12, the pre-closure re-point detector) · L 2 · F 3 ·
-- Z 4 · H 4 · U 2. Recorded so a silent plan-edit is visible in review as an arithmetic change.
select plan(27);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta \gset
\set tl '00000000-0000-0000-0000-0000000f0050'
\set tf '00000000-0000-0000-0000-0000000f0051'
\set tz '00000000-0000-0000-0000-0000000f0052'
\set th '00000000-0000-0000-0000-0000000f0053'
\set tu '00000000-0000-0000-0000-0000000f0054'

insert into auth.users (id) values (:'ta'), (:'tl'), (:'tf'), (:'tz'), (:'th'), (:'tu');

-- ---------------------------------------------------------------------
-- GLOBAL securities (users_id NULL → 016/017 #7 fence; readable by every tenant's INVOKER).
--   SECA: 150 @ 2026-06-01.  SECH: 100 @ 01-15 then 200 @ 07-15 (as-of LOCF trap).
--   SECU: NO eod_price (the unpriced-asset SUM-NULL fence).
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'NVSECA', 'NAV Sec A') returning asset_id as seca \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'NVSECH', 'NAV Sec H (as-of)') returning asset_id as sech \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'NVSECU', 'NAV Sec U (unpriced)') returning asset_id as secu \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:seca, '2026-06-01', 'market_feed', 150.0000),
  (:sech, '2026-01-15', 'market_feed', 100.0000),
  (:sech, '2026-07-15', 'market_feed', 200.0000);
-- NVSECU: intentionally NO eod_price row.

-- =====================================================================
-- TENANT A — 3 active (a1 inv, a2 dep, a3 liab) + a4 INACTIVE INVESTMENT holding securities.
--   NAV_active = a1(1500 sec + 2000 cash) + a2(5000) + a3(-2000) = 6500.
--   a4 (inactive) = 1500 sec + 0 cash.  NAV_all = 6500 + 1500 = 8000.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-1', 'investment', 'household', 'taxable') returning account_id as a1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a1, 3000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a1, '2026-06-05', -1000.0000, 10, :seca, 1000.0000, 'standard', 'buy-a1');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-dep-2', 'depository', 'household', 'taxable') returning account_id as a2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a2, 5000.0000, 'USD', '2026-06-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-liab-3', 'liability', 'household', 'taxable') returning account_id as a3 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a3, -2000.0000, 'USD', '2026-06-01', 'seed');

-- a4: investment CLOSED as of 2026-06-30, having held BOTH legs (10 NVSECA + cash).
--   ⚑ RE-SEEDED AT ADR-042 — was `is_active=false` while still holding both. That state is
--     unconstructible now (see 049's note); the wind-down below is what the close gate
--     actually requires, and it exercises BOTH zero-value legs rather than asserting around
--     them. Trigger-disabling to rebuild the old state is REFUSED.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv-closed-4', 'investment', 'household', 'taxable') returning account_id as a4 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a4, 1000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a4, '2026-06-05', -1000.0000, 10, :seca, 1000.0000, 'standard', 'buy-a4');
-- wind-down, both legs, all dated ON OR BEFORE the closing date:
--   sell the 10 back (holdings leg -> 0, cash -> 1000), then sweep the cash out (cash leg -> 0).
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:a4, '2026-06-20', 1000.0000, -10, :seca, 1000.0000, 'standard', 'sell-a4');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a4, '2026-06-30', -1000.0000, 0, 'sweep-a4');
-- The seed block runs at postgres with no tenant, so auth.uid() is NULL and 057's
-- writer refuses rather than letting absence become a value. Declare the writer, as
-- its own raise instructs. 'system:remediation' is the ONLY system actor 057 admits
-- (enumerated, not an open pattern, so a new system identity fails the CHECK).
select set_config('pfin.actor', 'system:remediation', true);
select set_config('pfin.reason_code', 'no_longer_used', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :a4;

-- =====================================================================
-- TENANT L — liability-only (R-7 sign): one ACTIVE liability, checkpoint -1500.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tl', 'l-liab-1', 'liability', 'household', 'taxable') returning account_id as l1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:l1, -1500.0000, 'USD', '2026-06-01', 'seed');

-- =====================================================================
-- TENANT F — all ACTIVE (all three signatures must agree).
--   f1 inv: checkpoint 2000; BUY 5 NVSECA cost_basis 500 amount -500 → 750 sec + 1500 cash = 2250.
--   f2 dep: 400.  NAV(any sig) = 2650.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'f-inv-1', 'investment', 'household', 'taxable') returning account_id as f1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:f1, 2000.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:f1, '2026-06-05', -500.0000, 5, :seca, 500.0000, 'standard', 'buy-f1');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tf', 'f-dep-2', 'depository', 'household', 'taxable') returning account_id as f2 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:f2, 400.0000, 'USD', '2026-06-01', 'seed');

-- =====================================================================
-- TENANT Z — owns NO accounts (the cross-tenant fail-closed probe).
-- =====================================================================
-- (no rows)

-- =====================================================================
-- TENANT H — as-of historical (false path). h1 inv: checkpoint 500 @ 01-01; BUY 1 NVSECH
--   cost_basis 100 amount -100 @ 01-20.  cash 400 both dates.
--   @2026-06-30: sec 1×100=100 → NAV 500.  @current: sec 1×200=200 → NAV 600.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'th', 'h-inv-1', 'investment', 'household', 'taxable') returning account_id as h1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:h1, 500.0000, 'USD', '2026-01-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:h1, '2026-01-20', -100.0000, 1, :sech, 100.0000, 'standard', 'buy-h1');

-- =====================================================================
-- TENANT U — unpriced-asset fence. u1 ACTIVE investment: checkpoint 300 cash + a holding of 5
--   NVSECU (NO eod_price). sec_mv term → NULL → dropped by SUM → 0. NAV = cash 300, never NaN/NULL.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tu', 'u-inv-1', 'investment', 'household', 'taxable') returning account_id as u1 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:u1, 300.0000, 'USD', '2026-06-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor)
  values (:u1, '2026-06-05', 0.0000, 5, :secu, 500.0000, 'standard', 'buy-u1');

-- =====================================================================
-- BLOCK A — value-bearing inactive scoping + reconciliation + 037 memo intact.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (A1) active-only EXCLUDES the value-bearing inactive a4.
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  6500.0000::numeric,
  '(A1) fn_compute_nav(as_of, TRUE) = 6500 — EXCLUDES the value-bearing INACTIVE a4 (both its 1500 securities and its cash). The SELF-322 fix.');
-- (A2) all-accounts INCLUDES a4.
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  6500.0000::numeric,
  '(A2) fn_compute_nav(as_of, FALSE) = 6500 — the all-accounts path. ⚑ WAS 8000, which INCLUDED the inactive-and-value-bearing a4. a4 is now wound down to zero before closing, because ADR-042 makes closed-while-holding-value unconstructible, so it contributes 0 to BOTH paths. RED if the false path gated closure');
-- (A3) 1-arg wrapper = all-accounts (the 037 memo path).
select is(
  pfin.fn_compute_nav('2026-06-30'::date),
  6500.0000::numeric,
  '(A3) fn_compute_nav(as_of) 1-arg = 6500 — the wrapper delegates to (as_of, false) = all-accounts. RED if the wrapper filtered closure (would break the 037 memo)');
-- (A4) ⚑ INVERTED AT ADR-042 — this is the assertion whose ARGUMENT reversed, not just its
--   expected value, so it is inverted rather than re-tuned.
--   It asserted TRUE ≠ FALSE, and that was only ever satisfiable because a4 was inactive
--   WHILE HOLDING VALUE. ADR-042's standing zero-value invariant makes that state
--   unconstructible: past its closing date a closed account holds zero (legs 1+2 at
--   closed_at, leg 3 plus the transfer-in fence after it), so it contributes zero to BOTH
--   paths. `p_active_only` is therefore a PROVABLE NO-OP ON VALUE.
--   ⚠ THIS IS THE DETECTOR, and it is why the assertion is kept rather than deleted. When
--     059 re-points the predicate, the correct form is AS-OF
--     (`closed_at is null or closed_at > p_as_of`) and the naive form is CURRENT-STATE
--     (`closed_at is null`). Under V1 the two are behaviourally identical, so choosing wrong
--     leaves NO FOOTPRINT — BACKLOG §7.7's V2-grantee entry records exactly that hazard.
--     This equality goes RED under the current-state form at any as-of BEFORE a closure.
--     Deleting (A4) as "no longer meaningful" would remove the only thing that catches it.
--   The four dependencies that keep this true, per ADR-042's symmetric rule — weaken any one
--   and p_active_only becomes load-bearing again: the gate's three legs; the transfer-in
--   fence; the position-neutrality of the two exempted tables (029 Σ=parent,
--   004 immutability); and the 059 re-point being as-of rather than current-state.
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  pfin.fn_compute_nav('2026-06-30'::date, false),
  '(A4) EQUIVALENCE AT A POST-CLOSURE AS-OF: TRUE = FALSE here — a closed account holds zero past its closing date, so p_active_only cannot change the answer. ⚠ ITS "or if 059 re-points to current-state" CLAIM WAS STRUCK 2026-08-04 AS FALSE: measured, this assertion passes unchanged under the naive current-state predicate, because at a post-closure date BOTH forms exclude a4 and it is worth zero anyway. The re-point detector is (A9)/(A11). This assertion proves the post-closure half only');
-- (A5) wrapper delegation proven directly: 1-arg == 2-arg(false).
select is(
  pfin.fn_compute_nav('2026-06-30'::date),
  pfin.fn_compute_nav('2026-06-30'::date, false),
  '(A5) wrapper delegation: 1-arg ≡ 2-arg(false) exactly — the "default false" semantic lives in the wrapper (NO-DEFAULT NOTE), so every legacy 1-arg caller is unchanged');
-- (A6) §2.1.1 == §2.1.5 reconciliation (the SELF-322 CONSISTENCY AC).
select is(
  (select coalesce(sum(current_market_value), 0) from pfin.fn_account_unrealized_gl('2026-06-30')),
  pfin.fn_compute_nav('2026-06-30'::date, true),
  '(A6) §2.1.1 == §2.1.5: Σ 049.current_market_value over A''s ACTIVE accounts (6500) == fn_compute_nav(as_of, TRUE) — the headline NAV and the per-account composition reconcile for a tenant holding a value-bearing INACTIVE account. The whole point of 050');
-- (A7) ⚑ INVERTED AT ADR-042 — the NUMERIC form of (A4), kept because it localises the failure.
--   It tied the delta to a4's securities-leg contribution (1500), which existed only while a4
--   was inactive AND still holding. Wound down before closing, a4 contributes 0 to both paths.
--   Kept rather than folded into (A4): (A4) says "the two agree", this says "and the gap is
--   exactly zero" — under a wrong 059 re-point the delta becomes a NUMBER, which names how
--   much value moved rather than only that something did.
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false) - pfin.fn_compute_nav('2026-06-30'::date, true),
  0.0000::numeric,
  '(A7) false − true = 0 AT A POST-CLOSURE AS-OF: the two scopes agree exactly, because a closed account holds zero past its closing date and contributes nothing to either. ⚠ THIS DOES NOT DETECT A WRONG 059 RE-POINT and must not be read as doing so — measured: under the naive current-state predicate this assertion still passes. The detector is (A9)/(A11) at PRE-closure dates. What this one adds is the post-closure half of the invariant: value cannot leak into a closed account after the fact');
-- (A8) 037 memo unchanged: fn_gl_entries still balances with an inactive holding present.
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  0::numeric,
  '(A8) 037 memo UNCHANGED: fn_gl_entries(as_of) Σ(amount_book) = 0 — the Unrealized memo''s 1-arg NAV dependency stayed all-accounts (wrapper→false), so the trial balance still zeroes with a4''s closed-account holding imaged');

-- =====================================================================
-- (A9)–(A12) ⭐⭐ THE PRE-CLOSURE DETECTOR — the assertions that catch a wrong 059 re-point.
--
-- ⚑ MEASURED FIRST, AND THE MEASUREMENT IS WHY THIS BLOCK EXISTS: (A4) and (A7) carry prose
--   calling themselves the detector. **THEY ARE NOT, AND IT IS MEASURED.** Both assert at
--   2026-06-30, a POST-closure as-of, where a closed account is excluded under BOTH predicate
--   forms and contributes zero either way. Re-pointing 059 to the naive current-state form
--   (`closed_at is null`, both functions) and running the suite: **049, 050 AND 051 all pass,
--   zero failures.** A whole battery agreed with the defect its own comments described.
--   >> A CLAIM THAT AN ASSERTION DETECTS SOMETHING IS ITSELF AN ASSERTION, and that one had
--      never been run. Same shape as DESIGN.md's `a caveat is a claim`, applied to a test's
--      self-description rather than to a hedge. <<
--
-- MEASURED FIXTURE BEHAVIOUR (tenant A, a4 closed 2026-06-30), correct vs naive re-point:
--
--     as_of     | correct: true / false / 049 cards | naive: true / false / cards
--   ------------+-----------------------------------+-----------------------------
--   2026-06-10  |     8000 / 8000 / 4               |   6500 / 8000 / 3   <- DIVERGES
--   2026-06-25  |     7500 / 7500 / 4               |   6500 / 7500 / 3   <- DIVERGES
--   2026-06-30  |     6500 / 6500 / 3               |   6500 / 6500 / 3     identical
--   2026-07-15  |     6500 / 6500 / 3               |   6500 / 6500 / 3     identical
--
--   The post-closure rows are why the old assertions could not see it. The pre-closure rows
--   are the detector, and the divergence is 1500 and 1000 — a NUMBER, not merely a mismatch.
--
-- ⚑⚑ TWO DATES, BECAUSE 059 HAS TWO PREDICATES AND ONE DATE GUARDS ONLY ONE OF THEM.
--   The securities leg gates on `acc2` (LEFT JOIN via holdings); the cash leg gates on `acc`.
--   A re-point flipping ONE is a realistic edit — different lines, different subqueries — and
--   a single as-of catches it only if that date happens to exercise that leg. a4's wind-down
--   separates them by construction:
--     2026-06-10 — a4 holds 10 NVSECA (1500) and ZERO cash      -> SECURITIES leg
--     2026-06-25 — a4 sold on 06-20: 1000 cash, ZERO securities -> CASH leg
--   So (A9) and (A11) are not one assertion at two dates; they guard two predicates.
-- =====================================================================

-- (A9) ⭐ SECURITIES-LEG DETECTOR, at a pre-closure as-of.
select is(
  pfin.fn_compute_nav('2026-06-10'::date, true),
  pfin.fn_compute_nav('2026-06-10'::date, false),
  '(A9) ⭐ PRE-CLOSURE EQUIVALENCE, SECURITIES LEG: at 2026-06-10 — before a4''s closing date, when it held 1500 in securities and no cash — TRUE = FALSE, because a4 was OPEN as of that date and the as-of predicate includes it in BOTH scopes. Under a current-state re-point it is excluded from the active scope at EVERY date, TRUE reads 6500 against FALSE''s 8000, and this goes RED by 1500. THIS IS THE ASSERTION THAT CATCHES A WRONG 059 RE-POINT; (A4) at a post-closure date cannot, which was measured rather than assumed');

-- (A10) NON-VACUITY of (A9) — without it the equivalence could hold because a4 was worth
--   NOTHING before closure, which is exactly what a careless re-seed would produce.
select is(
  pfin.fn_compute_nav('2026-06-10'::date, true) - pfin.fn_compute_nav('2026-06-30'::date, true),
  1500.0000::numeric,
  '(A10) THE DETECTOR IS NON-VACUOUS: the active-scope NAV falls by exactly 1500 between the pre-closure as-of and the closing date — a4''s real securities position, present on one side of its closure and gone on the other. At 0, (A9) would be comparing a closed account that never carried value and would prove nothing. RED at 0 means the fixture stopped exercising what (A9) detects');

-- (A11) ⭐ CASH-LEG DETECTOR — the SAME property at a date where a4 is cash-only.
select is(
  pfin.fn_compute_nav('2026-06-25'::date, true),
  pfin.fn_compute_nav('2026-06-25'::date, false),
  '(A11) ⭐ PRE-CLOSURE EQUIVALENCE, CASH LEG: at 2026-06-25 a4 has sold its securities (06-20) and holds 1000 in cash and nothing else, so this exercises the cash leg''s `acc` predicate where (A9) exercises the securities leg''s `acc2`. They are separate lines in separate subqueries of 059 and a re-point can flip one without the other; a single as-of leaves whichever leg it does not exercise unguarded. Naive re-point: 6500 against 7500, RED by 1000');

-- (A12) …and the two legs are genuinely separate in the fixture, rather than both non-zero at
--   both dates — otherwise (A9)/(A11) would be one assertion written twice.
select is(
  pfin.fn_compute_nav('2026-06-25'::date, true) - pfin.fn_compute_nav('2026-06-30'::date, true),
  1000.0000::numeric,
  '(A12) CASH-LEG NON-VACUITY, AND LEG SEPARATION: a4''s contribution at 2026-06-25 is 1000 — swept cash, securities already sold — against 1500 of pure securities at 2026-06-10. The two detector dates carry DIFFERENT amounts from DIFFERENT legs, which is what makes them two guards rather than one guard twice. RED if the wind-down dates move and both dates collapse onto the same leg');
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK L — liability R-7 sign on both paths.
-- =====================================================================
select _rls.set_tenant(:'tl'::uuid);
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  -1500.0000::numeric,
  '(L1) liability R-7 sign (active path): fn_compute_nav(as_of, TRUE) = -1500 (owed balance naturally negative — no account_type branch / no abs)');
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  -1500.0000::numeric,
  '(L2) liability R-7 sign (all-accounts path): fn_compute_nav(as_of, FALSE) = -1500 — the sign is preserved uniformly on both signatures');
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK F — all-active tenant: all three signatures agree.
-- =====================================================================
select _rls.set_tenant(:'tf'::uuid);
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  pfin.fn_compute_nav('2026-06-30'::date, false),
  '(F1) all-active tenant: TRUE ≡ FALSE — active-only is a NO-OP when nothing is inactive (no spurious exclusion)');
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  pfin.fn_compute_nav('2026-06-30'::date),
  '(F2) all-active tenant: FALSE ≡ 1-arg — chains with (F1) to true ≡ false ≡ 1-arg');
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  2650.0000::numeric,
  '(F3) all-active NAV = 2650 (f1 2250 + f2 400) — the three-way agreement is over a REAL nonzero portfolio, not a vacuous 0');
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK Z — INVOKER cross-tenant fails closed: no accounts → 0 on all three sigs.
-- =====================================================================
select _rls.set_tenant(:'tz'::uuid);
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  0::numeric,
  '(Z1) INVOKER fail-closed: a tenant owning NO accounts → fn_compute_nav(as_of, TRUE) = 0 (RLS composes under Z; A''s/F''s/L''s accounts are invisible)');
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  0::numeric,
  '(Z2) INVOKER fail-closed: Z → fn_compute_nav(as_of, FALSE) = 0 — the all-accounts path is still RLS-scoped to the caller');
select is(
  pfin.fn_compute_nav('2026-06-30'::date),
  0::numeric,
  '(Z3) INVOKER fail-closed: Z → fn_compute_nav(as_of) 1-arg = 0 — the wrapper inherits INVOKER + RLS');
select set_config('role', 'postgres', true);
-- (Z4) non-vacuous isolation companion: the DB DOES hold value-bearing accounts (A''s NAV>0), so
--      Z''s zeros are RLS isolation, not an empty database.
select _rls.set_tenant(:'ta'::uuid);
select cmp_ok(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  '>', 0::numeric,
  '(Z4) non-vacuous: under A, fn_compute_nav(as_of, FALSE) > 0 — the DB demonstrably has value-bearing accounts, so Z''s 0s (Z1..Z3) are a cross-tenant BOUNDARY denial, not an empty DB');
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK H — as-of unchanged on the FALSE path (019 behavior preserved).
-- =====================================================================
select _rls.set_tenant(:'th'::uuid);
select is(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  500.0000::numeric,
  '(H1) as-of FALSE path @ 2026-06-30 = 500 (NVSECH LOCF price 100 @ 01-15 × 1 + cash 400) — historical price, not the latest');
select is(
  pfin.fn_compute_nav(current_date, false),
  600.0000::numeric,
  '(H2) as-of FALSE path @ current_date = 600 (NVSECH price 200 @ 07-15 × 1 + cash 400)');
select isnt(
  pfin.fn_compute_nav('2026-06-30'::date, false),
  pfin.fn_compute_nav(current_date, false),
  '(H3) the FALSE path threads p_as_of: hist (500) ≠ current (600) — 050 preserves 019''s as-of LOCF behavior on the all-accounts path');
select is(
  pfin.fn_compute_nav('2026-06-30'::date),
  500.0000::numeric,
  '(H4) the 1-arg wrapper preserves as-of too: fn_compute_nav(2026-06-30) = 500 ≡ FALSE-path historical (037 memo''s as-of reconciliation intact)');
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK U — unpriced asset → 0, never NaN/NULL (019 SUM-NULL fence preserved on both paths).
-- =====================================================================
select _rls.set_tenant(:'tu'::uuid);
select is(
  pfin.fn_compute_nav('2026-06-30'::date, true),
  300.0000::numeric,
  '(U1) unpriced fence (active path): fn_compute_nav(as_of, TRUE) = 300 (cash only) — the 5 NVSECU shares have NO eod_price → NULL price term → dropped by SUM → 0 ("needs valuation"). RED (or NULL/NaN) if the unpriced holding poisoned the sum');
select ok(
  pfin.fn_compute_nav('2026-06-30'::date, false) is not null,
  '(U2) unpriced fence: fn_compute_nav(as_of, FALSE) IS NOT NULL — both legs COALESCE to 0, so an unpriced asset never yields NULL/NaN (a NULL would poison every downstream net-worth read)');
select set_config('role', 'postgres', true);

select * from finish();
rollback;
