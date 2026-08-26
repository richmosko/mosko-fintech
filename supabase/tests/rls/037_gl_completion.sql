-- =====================================================================
-- Per-Wave battery — M4-GL-write COMPLETION (SELF-301, the LAST GL migration): the four 037
--   components — (1) fn_gl_entries SELL realized-gain completion (Option A: one equity line;
--   matched_book = FIFO acquisition + pro-rata basis_adjust); (2) fn_journal_close_balance Σ=0-
--   at-close trigger (group_type-branched) + close snapshot; (3) close_book_value/closed_at
--   columns; (4) fn_account_trans_annotation_freeze_closed membership+classification freeze.
--   V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (money-flow + financial-calculation + close-enforcement
--   + freeze guard). Paired with the migration in the SAME PR (verify-paired-artifacts).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/037_gl_completion.sql
--   - pfin.fn_gl_entries(p_as_of date) create-or-replace — a matched sell posts Dr Cash / Cr
--       Position(current carried book) / one Realized-Gain equity line (proceeds − book);
--       unmatched sells keep the 035 Suspense floor (P8 gains a NOT EXISTS lot_match guard).
--       Balanced-by-construction; INVOKER; set search_path=''.
--   - pfin.fn_journal_close_balance() BEFORE UPDATE on pfin.journal (INVOKER): open→closed rejects
--       any future-dated leg (ALL group_types, hoisted first), enforces the group_type conservation
--       law (transfer→Σamount=0; transfer_in_kind→per-security Σqty=0; compound→NO Suspense residual
--       — the F/CTO hardening replacing the vacuous total-Σ), RAISE on imbalance, writes
--       close_book_value+closed_at; closed→open nulls both.
--   - pfin.journal.close_book_value numeric + closed_at timestamptz (write-once at close).
--   - journal_insert WITH CHECK gains `and status = 'open'` (Sec AMBER F1, F/CTO gate-now): a
--       journal is born open; status='closed' at insert is rejected (closing only via gated UPDATE).
--   - pfin.fn_account_trans_annotation_freeze_closed() BEFORE INSERT/UPDATE/DELETE on the 023
--       overlay (INVOKER): rejects any write where OLD.journal_id or NEW.journal_id is a CLOSED
--       journal (freezes membership + classification); reopen to edit; NULL-safe.
-- Prereqs on the 001→037 reset stack: 001 (pfin, auth.uid); 003 (account + creator-grant
--   rd=t/wr=t — the RLS chain fn_gl_entries + the close/freeze triggers compose under); 004/006
--   (account_trans immutable + rd/wr RLS); 016/017 (pfin.asset + security_id/quantity/cost_basis
--   + #7 global fence); 019 (fn_compute_nav — reused by the memo pair, unpriced → 0, nets 0);
--   023 (account_trans_annotation overlay + #10 sub_cat fence + ata full-CRUD wr_access policies);
--   028 (user_taxonomy.cat enum); 029/030 (split + transaction_type vocab); 032 (lot_match + #14
--   fence + immutability); 033 (pfin.journal + status/reopen + #12 journal fence); 034 (basis_adjust
--   shape + reason trigger); 036 (lot_match INSERT grant + wr_access — the sell's match is now writable);
--   084 (GL split — cashflow taxonomy rows now live in pfin.posting_prototype, no domain column).
--
-- ┌─ THE RATIFIED WORKED EXAMPLE (§037.1; the realized-gain correctness anchor) ───────────────┐
-- │ BUY 100@$10 (basis 1000) · return_of_capital basis_adjust (−$150 basis / +$150 cash) ·      │
-- │ depreciation basis_adjust (−$200 basis) · SELL 100@$12 (proceeds 1200), lot_match sell→buy. │
-- │   matched_acq = 100 × (1000/100) = 1000 (FIFO acquisition).                                  │
-- │   pro-rata basis_adjust = Σ(cost_basis) × matched_qty/total_bought = (−150 + −200) × 100/100 │
-- │                          = −350.                                                             │
-- │   matched_book = 1000 + (−350) = 650.                                                        │
-- │   realized_gain line = matched_book − proceeds = 650 − 1200 = −550 (Cr; a $550 GAIN).        │
-- │ Three sell legs: Dr Cash +1200 · Cr Position −650 · Cr Realized-Gain −550 → sum 0 (balanced- │
-- │ by-construction). And sec1's whole trade_position lifecycle nets to 0 on full liquidation:   │
-- │ +1000 (buy) −150 (RoC) −200 (dep) −650 (sell removal) = 0.                                    │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ THE 037 COMPOUND CLOSE LAW (F/CTO hardening — the old total-Σ was VACUOUS; QA Finding 2) ──┐
-- │ fn_gl_entries is balanced PER TRANSACTION (every source emits a real leg + equal-and-        │
-- │ opposite contra(s), all carrying that transaction's journal_id). Therefore Σ(amount_book)    │
-- │ over ANY journal_id subset = Σ of (each self-balanced transaction) = 0 — ALWAYS, for well-   │
-- │ formed data — the literal `compound → book Σ=0` gate could NEVER catch an imbalance. The     │
-- │ ratified fix REPLACES it with two REACHABLE, non-vacuous gates: (i) NO Suspense-residual — a  │
-- │ compound group with any leg routing to Suspense (unclassified / unmatched-sell / unarrived-   │
-- │ counter) → close REJECTED (4i); positive control = a fully-resolved compound closes (4e).     │
-- │ (ii) NO future-dated leg — hoisted to ALL group_types, fired FIRST: any leg dated after today │
-- │ → close REJECTED (4j; keeps close_book_value, computed at current_date, faithful). transfer   │
-- │ (Σamount) + transfer_in_kind (Σqty) keep RAW-leg conservation (4c/4d). All gates reachable.   │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ORDERING / ROLE MODEL ────────────────────────────────────────────────────────────────────┐
-- │ Fixture PRIVILEGED (postgres; users_id explicit — auth.uid() NULL under postgres); lot_match │
-- │ seeded privileged (the #14 fence fires + passes). Reads (Groups 0-3) + the close/freeze       │
-- │ writes (Groups 4-5) run UNDER authenticated A/B — the real INVOKER path (fn_gl_entries images │
-- │ only the caller's RLS-visible ledger; the triggers fire in the caller's context). Reads run   │
-- │ FIRST (before the Group 4/5 mutations). jFreeze is closed IN the fixture (its legs net to 0)  │
-- │ to set up Group 5's closed-journal state. Roles restored to postgres between blocks (PR #121).│
-- │ TRIGGER FIRE ORDER on account_trans_annotation (all BEFORE INS/UPD/DEL, alphabetical): _basis │
-- │ _adjust_reason < _freeze_closed < _matched_journal(#12) < _sub_cat(#10) — so freeze_closed    │
-- │ fires BEFORE #12/#10, i.e. a closed-journal write fails with the freeze message, not #12/#10. │
-- │ ⚠ SELF-248/092 UPDATE (2026-08-25): a fifth BEFORE trigger, _journaled_cat_fence, now sorts   │
-- │ BETWEEN _freeze_closed and _matched_journal — full order: _basis_adjust_reason < _freeze_     │
-- │ closed < _journaled_cat_fence < _matched_journal(#12) < _sub_cat(#10). Does not change any    │
-- │ assertion in THIS file: (5a)-(5d) all target jFreeze, which is CLOSED, so freeze_closed still │
-- │ fires and raises first, ahead of the new fence, on every write this file exercises against it.│
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED / INVERSION (each assertion names the REAL violation it catches):
--   (0a) cross-tenant read fails closed: B sees 0 of A's GL rows — RED if fn_gl_entries were
--        DEFINER / lost RLS composition (B would image A's realized gains).
--   (0b) non-vacuous isolation anchor: A sees its own realized_gain row (≥1) — makes 0a's 0 real.
--   (1a) realized_gain sum = −550 — RED if the gain double-counts RoC (matched_book stuck at
--        acquisition 1000 → −200) or mis-signs the pro-rata basis_adjust (+350 → +150 loss).
--   (1b) EXACTLY one realized_gain line, from sell1 — RED if a matched sell emitted 0 or >1 gain lines.
--   (1c) sell1 position-removal leg = −650 (Cr Position at current carried book = matched_book)
--        — RED if the removal used raw acquisition (−1000) or omitted the basis_adjust term.
--   (1d) sec1 trade_position lifecycle = 0 (full liquidation) — RED if buy/RoC/dep/removal don't
--        net (the position wouldn't zero on a full sell).
--   (2a) global Σ(amount_book) = 0 — RED if any matched-sell leg were dropped/sign-flipped.
--   (2b) Σ|amount_book| > 0 — non-vacuous (2a is a real cancellation, not empty-set 0).
--   (3a) unmatched sell2 Suspense = −700 — RED if an unmatched sell posted a realized gain
--        instead of parking (the 035 floor / P8 NOT EXISTS lot_match guard).
--   (3b) unmatched sell2 has ZERO realized_gain lines — RED if the sell_book path picked up a
--        sell with no lot_match rows.
--   (4a) BALANCED transfer close SUCCEEDS — RED if the conservation check over-blocked a balanced group.
--   (4b) close writes close_book_value + closed_at (both non-null) — RED if the snapshot writer dropped.
--   (4c) IMBALANCED transfer close RAISES (Σamount≠0) — RED if an imbalanced close slipped through.
--   (4d) IMBALANCED transfer_in_kind close RAISES (per-security Σqty≠0) — RED if the in-kind
--        conservation law were dropped/replaced by the value law.
--   (4e) FULLY-RESOLVED compound close SUCCEEDS (classified leg → no Suspense residual) — RED if
--        the compound no-Suspense-residual gate over-blocked a fully-resolved group. Control for 4i.
--   (4f) REOPEN (closed→open) NULLs close_book_value + closed_at — RED if reopen left a stale snapshot.
--   (4i) compound Suspense-residual close RAISES 'unresolved (Suspense) leg' — RED if the gate
--        reverted to the vacuous total-Σ (which never catches an imbalance). RESOLVES QA Finding 2.
--   (4j) future-dated close RAISES 'future-dated leg' (ALL group_types, hoisted first) — RED if a
--        period could close with future-dated entries (a stale close_book_value snapshot). (4a) is
--        the same-shape dated-through control that closes.
--   (4g) Sec F1: an authenticated insert of a journal with status='closed' is REJECTED at the
--        journal_insert WITH CHECK (`and status='open'`) — RED if the clause were dropped (a
--        born-closed journal bypasses the gated close's Σ=0 enforcement + snapshot).
--   (4h) F1 non-vacuous: a born-OPEN insert SUCCEEDS — proves 4g rejects on the closed status.
--   (5a) attach a leg to a CLOSED journal → REJECTED — RED if the freeze missed the NEW.journal_id direction.
--   (5b) detach (journal_id→NULL) a closed-journal leg → REJECTED — RED if the freeze missed OLD.journal_id.
--   (5c) DELETE a closed-journal leg's annotation → REJECTED — RED if the freeze missed the DELETE op.
--   (5d) reclassify (sub_cat edit) a closed-journal leg → REJECTED — RED if the guard froze only
--        membership (journal_id), not classification (the stronger ratified form).
--   (5e) after REOPEN: reclassify ALLOWED — RED if reopen didn't unfreeze (proves 5d is status-driven).
--   (5f) after REOPEN: detach ALLOWED — non-vacuous unfreeze control (both OLD/NEW directions).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 037 adds ZERO catalogued
--   §10 instances — an INVOKER read revision + two INVOKER triggers + two plain columns; all
--   authenticated-tier, no service_role grant/credential/admission surface). Decision-3 UNCHANGED
--   (no new FK — the freeze READS the existing 023.journal_id FK's target status; the snapshot is
--   two plain columns). SECURITY DEFINER allowlist UNCHANGED at 4 (both triggers INVOKER). This
--   battery introduces no catalogued instance; it is the pgTAP proof the GL project closes flat.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO
--   real account numbers / NO prod data. GLOBAL securities users_id NULL (016/017 #7). A owns a
--   rich GL-producing ledger (matched sell + unmatched sell + transfer/in-kind/compound journals +
--   a closed journal); B owns a minimal control leg. All seeds PRIVILEGED (users_id explicit);
--   reads/writes exercised ONLY under authenticated A/B. Rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 037's landed contract. The AUTHORITATIVE run is the 001→037
--   reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's clean-apply +
--   `supabase migration up`). The committed file does NOT self-apply the migration. NOTE: 037's
--   freeze_closed trigger required a paired FIXTURE FIX to 035_fn_gl_entries.sql (it attached an
--   annotation to a CLOSED journal, now illegal) — same PR; 035 plan(13) unchanged (fixture-only).
--   plan(26) (22 base + 2 Sec AMBER F1 born-closed pair + 2 F/CTO compound-hardening: 4i compound
--   Suspense-residual reject [resolves QA Finding 2] + 4j future-dated reject [037 N1, ALL group_types]).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(26);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- ---------------------------------------------------------------------
-- Taxonomy (A) — Transfer (tx_xfer: the compound-leg classification AND fz1's SEEDED value) +
-- a SECOND Transfer (tx_xfer2: since Sec's FLAG-1 follow-on, both (5d)/(5e)'s reclassify
-- targets — a value fz1 does NOT already hold, so those writes are genuine reclassifies, not
-- same-value no-ops; see the seed note below) + Revenue (tx_rev — SELF-248/092 + Sec FLAG-1:
-- defined but no longer referenced by any assertion in this file; kept rather than deleted to
-- keep that fix a minimal two-token retarget, not a fixture prune). Matched-tenant for the #10
-- sub_cat fence.
-- ---------------------------------------------------------------------
-- is_tax_payment added (SELF-245/091, boolean not null no default) — false throughout.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'Move', false)   returning id as tx_xfer \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Revenue',  'Salary', false) returning id as tx_rev  \gset

-- Sec FLAG-1 follow-on (PR #561, 2026-08-25): a SECOND Transfer prototype exists solely so
-- (5d)/(5e) can write a value fz1 does NOT already hold. fz1 is seeded tx_xfer at the
-- annotation insert below, so targeting tx_xfer there would make both legs SAME-VALUE writes
-- — and a same-value lives_ok at (5e) cannot fail: a transition-scoped guard
-- (WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id) would block every real reclassify and
-- (5e) would still pass, which is the exact state-vs-transition blindness Sec's (C'') rules
-- out. Transfer is the ONLY class a journaled non-security leg may legally hold post-092
-- (Revenue/Expense/Equity are the fence's forbidden set; Trade requires security_id), so a
-- genuine reclassify target REQUIRES a second Transfer row. Do not merge these two prototypes.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'Internal Move', false) returning id as tx_xfer2 \gset

-- ---------------------------------------------------------------------
-- Accounts. A: an investment (securities) + a cash (transfer/compound/freeze legs). B: minimal.
-- ---------------------------------------------------------------------
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-inv', 'investment', 'household', 'taxable') returning account_id as a_inv \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-cash', 'depository', 'household', 'taxable') returning account_id as a_cash \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-cash', 'depository', 'household', 'taxable') returning account_id as b_cash \gset

-- GLOBAL securities (users_id NULL). Unpriced (no eod_price) → fn_compute_nav values positions at
-- 0 in the memo pair, which nets 0 regardless — the Σ=0 invariant is untouched (035 posture).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZG37A', 'QA 37 Sec A') returning asset_id as sec1 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZG37B', 'QA 37 Sec B') returning asset_id as sec2 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'ZG37C', 'QA 37 Sec C') returning asset_id as sec3 \gset

-- ---------------------------------------------------------------------
-- GROUP 1 fixture — the ratified worked example (sec1, MATCHED). BUY 100@$10, RoC −150/+150 cash,
-- depreciation −200, SELL 100@$12; lot_match ties sell→buy (100 shares). Expected: gain −550.
-- ---------------------------------------------------------------------
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-01', -1000, 'vBUY1', 'buy sec1 100@10', 'standard', :sec1, 100, 1000) returning trans_id as buy1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-02', 150, 'vROC1', 'return of capital', 'basis_adjust', :sec1, 0, -150) returning trans_id as roc1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-03', 0, 'vDEP1', 'depreciation', 'basis_adjust', :sec1, 0, -200) returning trans_id as dep1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity)
  values (:a_inv, '2026-05-04', 1200, 'vSELL1', 'sell sec1 100@12', 'standard', :sec1, -100) returning trans_id as sell1 \gset
-- basis_adjust reason annotations (the 034 reason trigger fires + PASSES: RoC⟺amount≠0, dep⟺amount=0).
insert into pfin.account_trans_annotation (trans_id, metadata) values (:roc1, '{"reason":"return_of_capital"}'::jsonb);
insert into pfin.account_trans_annotation (trans_id, metadata) values (:dep1, '{"reason":"depreciation"}'::jsonb);
-- lot_match sell1→buy1 (036 write path; privileged seed — the #14 fence fires + passes: same tenant/security).
insert into pfin.lot_match (sell_trans_id, buy_trans_id, quantity_matched, match_seq) values (:sell1, :buy1, 100, 1);

-- ---------------------------------------------------------------------
-- GROUP 3 fixture — an UNMATCHED sell (sec2, NO lot_match). BUY 100@$5, SELL 100@$7 (proceeds 700).
-- ---------------------------------------------------------------------
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-05', -500, 'vBUY2', 'buy sec2 100@5', 'standard', :sec2, 100, 500) returning trans_id as buy2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity)
  values (:a_inv, '2026-05-06', 700, 'vSELL2', 'sell sec2 100@7 (unmatched)', 'standard', :sec2, -100) returning trans_id as sell2 \gset
-- (no lot_match for sell2 → park-if-unmatched floor)

-- ---------------------------------------------------------------------
-- GROUP 4 fixture — journals + legs for the Σ=0-close trigger, one per group_type conservation law.
-- ---------------------------------------------------------------------
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer',         'open', 'jT balanced')   returning journal_id as jt_bal   \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer',         'open', 'jT imbalanced') returning journal_id as jt_imbal \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer_in_kind', 'open', 'jK imbalanced') returning journal_id as jk_imbal \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'compound',         'open', 'jC balanced')   returning journal_id as jc_bal   \gset

-- transfer BALANCED legs (−300 + 300 = 0).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-07', -300, 'vXFO', 'xfer out') returning trans_id as xf_out \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-08',  300, 'vXFI', 'xfer in')  returning trans_id as xf_in \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:xf_out, :tx_xfer, :jt_bal);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:xf_in,  :tx_xfer, :jt_bal);
-- transfer IMBALANCED leg (Σamount = +300 ≠ 0).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-09', 300, 'vXFB', 'xfer unbalanced') returning trans_id as xf_bad \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:xf_bad, :tx_xfer, :jt_imbal);
-- transfer_in_kind IMBALANCED leg (a security with per-security Σqty = +5 ≠ 0).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:a_inv, '2026-05-10', -50, 'vIKB', 'in-kind unbalanced', 'standard', :sec3, 5, 50) returning trans_id as ik_bad \gset
insert into pfin.account_trans_annotation (trans_id, journal_id) values (:ik_bad, :jk_imbal);
-- compound FULLY-RESOLVED leg (a classified Transfer cash flow, journaled → routes to Journal
-- Clearing, NOT Suspense). ⚠ SELF-248 / 092 CORRECTION (2026-08-25): this fixture originally
-- classified comp1 as Revenue while journaled. That is EXACTLY the M3 defect state 092's
-- fn_account_trans_annotation_journaled_cat_fence exists to refuse (journal_id IS NOT NULL AND
-- resolved cat IN ('Revenue','Expense','Equity') — a journaled Revenue leg posts as income
-- instead of routing to Journal Clearing, double-counting a transfer). The write now RAISES at
-- INSERT, which aborted this file's ENTIRE fixture setup (caught by QA's 092 battery full-suite
-- regression run). Fixed by reclassifying comp1 as Transfer (tx_xfer) instead: Transfer is NOT
-- in the fence's forbidden set, still routes to 'Journal Clearing' (not Suspense) per 084's P3
-- CASE, and the compound group_type's Σ=0 conservation law is classification-agnostic (037's own
-- header note: every transaction self-balances regardless of which category its contra resolves
-- to) — so (4e)'s "fully-resolved, no Suspense residual → closes" intent is unchanged.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-11', 100, 'vCMP', 'compound transfer, journaled') returning trans_id as comp1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:comp1, :tx_xfer, :jc_bal);
-- compound with an UNRESOLVED (Suspense-routing) leg — an UNCLASSIFIED cash leg (sub_cat NULL →
-- flow_class NULL → P3 contra routes to Suspense). The 037 compound close law rejects a Suspense residual.
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'compound', 'open', 'jC suspense') returning journal_id as jc_susp \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-16', 100, 'vCSU', 'compound unclassified leg') returning trans_id as comp_susp \gset
insert into pfin.account_trans_annotation (trans_id, journal_id) values (:comp_susp, :jc_susp);  -- sub_cat NULL → images to Suspense
-- a journal with a FUTURE-DATED leg (037 N1 guard; ALL group_types). Balanced transfer (+300 / −300)
-- so the ONLY blocker is the future date — the dated-through control is (4a) (same shape, legs ≤ today).
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', 'jFuture') returning journal_id as jfut \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-17',  300, 'vFP', 'jFuture present leg') returning trans_id as fut_present \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2099-12-31', -300, 'vFF', 'jFuture future-dated leg') returning trans_id as fut_future \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:fut_present, :tx_xfer, :jfut);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:fut_future,  :tx_xfer, :jfut);

-- ---------------------------------------------------------------------
-- GROUP 5 fixture — a CLOSED journal (jFreeze) with attached legs (attached while OPEN, then closed
-- privileged so the freeze guard is exercised on the authenticated paths under test) + one
-- unattached leg (the attach-to-closed probe). jFreeze is a balanced transfer so the close succeeds.
-- ---------------------------------------------------------------------
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', 'jFreeze') returning journal_id as jfreeze \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-12',  300, 'vFZ1', 'freeze leg 1') returning trans_id as fz1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-13', -300, 'vFZ2', 'freeze leg 2') returning trans_id as fz2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:a_cash, '2026-05-14',   50, 'vFZU', 'freeze unattached') returning trans_id as fz_unatt \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:fz1, :tx_xfer, :jfreeze);
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (:fz2, :tx_xfer, :jfreeze);
insert into pfin.account_trans_annotation (trans_id, journal_id) values (:fz_unatt, null);  -- unattached (has a row for the 5a repoint)
-- close jFreeze (privileged) — transfer Σamount = 300 − 300 = 0 → succeeds, sets the closed state.
update pfin.journal set status = 'closed' where journal_id = :jfreeze;

-- ---------------------------------------------------------------------
-- Tenant B minimal control leg (its own GL is non-empty; the cross-tenant boundary anchor).
-- ---------------------------------------------------------------------
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:b_cash, '2026-05-15', 500, 'vBREV', 'b revenue') returning trans_id as b_leg \gset

-- =====================================================================
-- BLOCK A (authenticated A) — the realized-gain worked example + balance + park-if-unmatched.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (0b) non-vacuous isolation anchor: A sees its OWN realized_gain row (≥1) — makes 0a's 0 real.
select cmp_ok(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'realized_gain' and users_id = :'ta'::uuid),
  '>', 0::bigint,
  '(0b) non-vacuous: authenticated A sees its OWN realized_gain GL row (>0) — the anchor that makes the cross-tenant 0 in (0a) a REAL boundary denial');

-- (1a) realized-gain correctness: the single equity line = −550 (proceeds 1200 − matched_book 650).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'realized_gain'),
  -550::numeric,
  '(1a) realized-gain = −550 (Cr; a $550 gain): matched_book 650 (FIFO acq 1000 + pro-rata basis_adjust −350) − proceeds 1200. RED if the gain double-counts RoC (→ −200) or mis-signs the basis_adjust term (→ +150)');

-- (1b) EXACTLY one realized_gain line, from sell1.
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'realized_gain' and source_trans_id = :sell1),
  1::bigint,
  '(1b) EXACTLY one realized_gain line, deriving from the matched sell (sell1) — RED if a matched sell emitted 0 (parked) or >1 gain lines');

-- (1c) matched_book: the sell position-removal leg = −650 (Cr Position at current carried book).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'trade_position' and source_trans_id = :sell1),
  -650::numeric,
  '(1c) matched_book = 650: the sell position-removal leg = −650 (Cr Position at current carried book = FIFO acquisition + pro-rata basis_adjust). RED if the removal used raw acquisition (−1000) or omitted the basis_adjust term');

-- (1d) sec1 trade_position lifecycle nets to 0 on full liquidation (buy +1000 − RoC 150 − dep 200 − removal 650).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'trade_position' and security_id = :sec1),
  0::numeric,
  '(1d) full liquidation: sec1 trade_position nets to 0 (+1000 buy − 150 RoC − 200 dep − 650 sell removal) — the position zeros when fully sold. RED if any leg dropped or mis-signed');

-- (2a) global trial balance: Σ(amount_book) = 0 over A's full GL (with the matched sell present).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  0::numeric,
  '(2a) global trial balance: SUM(amount_book) = 0 over A''s full GL — balanced-by-construction preserved with the matched sell. RED if a matched-sell leg were dropped/sign-flipped');

-- (2b) non-vacuous balance: real nonzero postings exist (2a is a cancellation, not empty-set 0).
select cmp_ok(
  (select coalesce(sum(abs(amount_book)), 0) from pfin.fn_gl_entries('2026-06-30'::date)),
  '>', 0::numeric,
  '(2b) non-vacuous balance: SUM(|amount_book|) > 0 — A''s GL has real nonzero postings, so (2a)''s Σ=0 is a genuine debit/credit cancellation');

-- (3a) park-if-unmatched floor: the unmatched sell2 parks its proceeds in Suspense (−700).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'suspense' and source_trans_id = :sell2),
  -700::numeric,
  '(3a) park-if-unmatched: the unmatched sell2 (no lot_match) parks Cr Suspense = −700 (the 035 floor / P8 NOT EXISTS lot_match guard). RED if an unmatched sell posted a realized gain instead of parking');

-- (3b) the unmatched sell2 has ZERO realized_gain lines (it parks, it does not complete).
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where entry_class = 'realized_gain' and source_trans_id = :sell2),
  0::bigint,
  '(3b) park-if-unmatched: the unmatched sell2 emits ZERO realized_gain lines — RED if the sell_book path picked up a sell with no lot_match rows');

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B (authenticated B) — cross-tenant read fails closed (the isolation proof).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (0a) cross-tenant read fails closed: B calling fn_gl_entries sees 0 of A's GL rows (INVOKER + RLS).
select is(
  (select count(*) from pfin.fn_gl_entries('2026-06-30'::date) where users_id = :'ta'::uuid),
  0::bigint,
  '(0a) cross-tenant read FAILS CLOSED: tenant B calling fn_gl_entries sees 0 rows owned by A — INVOKER composes ENTIRELY under B''s RLS. RED (>0) if the fn were SECURITY DEFINER / lost RLS composition');

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK C (authenticated A) — the Σ=0-at-close trigger (group_type-branched) + snapshot + reopen.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (4a) BALANCED transfer close SUCCEEDS (Σamount = −300 + 300 = 0).
select lives_ok(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jt_bal),
  '(4a) close balanced transfer: A closes jT-balanced (Σamount = 0) → journal_close_balance ADMITS the close. RED if the conservation check over-blocked a balanced group');

-- (4b) the close wrote the snapshot: close_book_value + closed_at are BOTH set.
select ok(
  (select close_book_value is not null and closed_at is not null from pfin.journal where journal_id = :jt_bal),
  '(4b) close snapshot: after the balanced close, close_book_value AND closed_at are both non-null (write-once at close). RED if the snapshot writer were dropped');

-- (4c) IMBALANCED transfer close RAISES (Σamount = +300 ≠ 0).
select throws_like(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jt_imbal),
  '%do not net to zero%',
  '(4c) close imbalanced transfer FAILS CLOSED: jT-imbalanced (Σamount = +300) RAISES ''transfer legs do not net to zero''. RED if an imbalanced close slipped through');

-- (4d) IMBALANCED transfer_in_kind close RAISES (per-security Σqty = +5 ≠ 0).
select throws_like(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jk_imbal),
  '%does not conserve quantity%',
  '(4d) close imbalanced in-kind FAILS CLOSED: jK-imbalanced (per-security Σqty = +5) RAISES ''does not conserve quantity''. RED if the in-kind conservation law were dropped or replaced by the value law');

-- (4e) FULLY-RESOLVED compound close SUCCEEDS (no Suspense residual — the 037 compound law). A
--      classified-and-journaled Transfer leg routes to Journal Clearing, not Suspense → the group
--      closes. Positive control for (4i). (Was Revenue pre-092 correction — see comp1's fixture note.)
select lives_ok(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jc_bal),
  '(4e) close fully-resolved compound: A closes jC-balanced (a classified Transfer leg → Journal Clearing, no Suspense residual) → ADMITS. RED if the compound no-Suspense-residual gate over-blocked a fully-resolved group');

-- (4f) REOPEN (closed→open) NULLs the snapshot. Reopen jT-balanced, then assert both columns NULL.
update pfin.journal set status = 'open' where journal_id = :jt_bal;
select ok(
  (select close_book_value is null and closed_at is null from pfin.journal where journal_id = :jt_bal),
  '(4f) reopen nulls the snapshot: after reopen (closed→open), close_book_value AND closed_at are both NULL (never re-value a standing snapshot). RED if reopen left a stale snapshot');

-- (4g) Sec F1 — a journal cannot be BORN CLOSED. The journal_insert WITH CHECK gained `and status
--      = 'open'`, so an insert with status='closed' is REJECTED: a journal is born open; the ONLY
--      path to closed is the gated open→closed UPDATE (4a), which runs the Σ=0 enforcement +
--      snapshot. Without this a born-closed journal would bypass the close check + snapshot entirely.
select throws_like(
  $$ insert into pfin.journal (group_type, status, description) values ('transfer', 'closed', 'born-closed') $$,
  '%violates row-level security policy%',
  '(4g) F1 born-closed REJECTED: an authenticated insert of a journal with status=''closed'' is rejected by journal_insert WITH CHECK (status must be ''open'' at insert) — a journal cannot skip the gated close. RED if the `and status=''open''` clause were dropped (a born-closed journal bypasses the Σ=0 close check + snapshot)');

-- (4h) F1 non-vacuous control: a born-OPEN insert (default status) SUCCEEDS — the rejection is
--      status-driven, not a blanket insert block.
select lives_ok(
  $$ insert into pfin.journal (group_type, description) values ('transfer', 'born-open') $$,
  '(4h) F1 non-vacuous: a born-OPEN journal insert (status defaults ''open'') SUCCEEDS — proves (4g) rejects on the closed status specifically, not on a broken insert path');

-- (4i) compound no-Suspense-residual gate (037 F/CTO hardening; RESOLVES the old vacuous total-Σ):
--      a compound group with an UNRESOLVED (Suspense-routing) leg → close REJECTED. jC-suspense's
--      unclassified leg images to a Suspense posting. (4e) fully-resolved compound is the positive control.
select throws_like(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jc_susp),
  '%unresolved (Suspense) leg%',
  '(4i) compound Suspense-residual FAILS CLOSED: a compound group with an unclassified/unmatched (Suspense-routing) leg RAISES ''unresolved (Suspense) leg'' — a compound group may only close once every leg is classified/matched. RED if the gate reverted to the vacuous total-Σ (which never catches an imbalance — every leg self-balances within its own journal_id)');

-- (4j) 037 N1 future-dated guard (ALL group_types; fires ahead of the conservation branch): a journal
--      with a leg transaction_date > today → close REJECTED. jFuture is a BALANCED transfer whose only
--      blocker is the future-dated leg; (4a) (same shape, all legs dated-through) is the control that closes.
select throws_like(
  format($$ update pfin.journal set status = 'closed' where journal_id = %s $$, :jfut),
  '%future-dated leg%',
  '(4j) future-dated close FAILS CLOSED: a journal with a leg dated after today RAISES ''future-dated leg'' (the hoisted ALL-group_types guard, fired ahead of the conservation branch). jFuture is otherwise balanced (Σamount=0), so the ONLY blocker is the future date; (4a) proves the same-shape dated-through transfer closes. RED if a period could close with future-dated entries (a stale close_book_value snapshot)');

select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK D (authenticated A) — the membership+classification freeze guard (against jFreeze, CLOSED).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (5a) ATTACH a leg to a CLOSED journal → REJECTED (NEW.journal_id closed). Repoint the unattached leg.
select throws_like(
  format($$ update pfin.account_trans_annotation set journal_id = %s where trans_id = %s $$, :jfreeze, :fz_unatt),
  '%reopen it first%',
  '(5a) freeze ATTACH: attaching a leg to a CLOSED journal (NEW.journal_id = jFreeze) is REJECTED (freeze fires ahead of #12). RED if the freeze missed the NEW.journal_id direction');

-- (5b) DETACH (journal_id→NULL) a closed-journal leg → REJECTED (OLD.journal_id closed).
select throws_like(
  format($$ update pfin.account_trans_annotation set journal_id = null where trans_id = %s $$, :fz1),
  '%reopen it first%',
  '(5b) freeze DETACH: detaching a CLOSED-journal leg (journal_id → NULL; OLD.journal_id = jFreeze) is REJECTED. RED if the freeze missed the OLD.journal_id direction (the WHEN-skip path would have leaked)');

-- (5c) DELETE a closed-journal leg's annotation → REJECTED (OLD.journal_id closed; the DELETE op).
select throws_like(
  format($$ delete from pfin.account_trans_annotation where trans_id = %s $$, :fz2),
  '%reopen it first%',
  '(5c) freeze DELETE: deleting a CLOSED-journal leg''s annotation (OLD.journal_id = jFreeze) is REJECTED. RED if the freeze missed the DELETE op');

-- (5d) RECLASSIFY (sub_cat edit; journal_id unchanged) a closed-journal leg → REJECTED (the stronger
--   guard). ⚠ Sec FLAG-1 (2026-08-25, PR #561 AMBER): retargeted from tx_rev to tx_xfer2 (a
--   SECOND Transfer prototype — see the taxonomy seed note). Pre-fix this leg passed only
--   because _freeze_closed happens to sort before _journaled_cat_fence in Postgres's
--   BEFORE-trigger NAME order — a coincidence 092's own header states is explicitly NOT
--   load-bearing. Transfer is NOT in the new fence's forbidden set, so the freeze is now the
--   ONLY possible rejection regardless of trigger order — the assertion no longer depends on an
--   ordering fact its own migration disclaims. Frozen + Transfer still raises (freeze is
--   classification-blind: it keys on journal status, not the classification value), and (5d)/(5e)
--   return to differing in exactly one variable (open vs closed) rather than also differing in
--   classification target. ⚠ Sec FLAG-1 follow-on (same date, same AMBER round): the FIRST pass
--   of this fix used tx_xfer, fz1's OWN seeded value — a SAME-VALUE write. (5d) survives that
--   (a BEFORE trigger fires regardless of whether the value changed, so it still discriminates
--   a membership-only guard), but its sibling (5e) does not (see (5e)'s note) — retargeted both
--   to tx_xfer2 together so the pair shares one genuine-reclassify value.
select throws_like(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :tx_xfer2, :fz1),
  '%reopen it first%',
  '(5d) freeze RECLASSIFY (the STRONGER ratified form): re-categorizing a CLOSED-journal leg (sub_cat edit, journal_id unchanged; OLD.journal_id = jFreeze) is REJECTED — a re-derived close Σ depends on classification too. RED if the guard froze only membership (journal_id), not classification. Uses tx_xfer (not tx_rev) so the rejection is freeze-driven regardless of trigger name order (Sec FLAG-1) (target tx_xfer2 — a value fz1 does not already hold, so the write is a REAL reclassify; see the taxonomy seed note)');

-- Reopen jFreeze (status→open) — nulls the snapshot AND lifts the freeze.
update pfin.journal set status = 'open' where journal_id = :jfreeze;

-- (5e) after REOPEN: reclassify now ALLOWED (freeze no-op → #10 fires + PASSES, sub_cat is A's
--   taxonomy). ⚠ SELF-248/092 CORRECTION (2026-08-25): the ORIGINAL target here was tx_rev
--   (Revenue), matching (5d)'s then-target to isolate open-vs-closed as the only variable. That
--   is no longer reachable: fz1's journal_id is STILL jFreeze (now merely REOPENED, not
--   detached), so a Revenue reclassify while journal_id remains non-null is the M3 defect state
--   092's fn_account_trans_annotation_journaled_cat_fence refuses UNCONDITIONALLY — open or
--   closed makes no difference to that fence. Retargeted (first pass) to tx_xfer (Transfer, not
--   in the fence's forbidden set) to preserve this leg's actual intent: proving 5d's rejection
--   was close-status-driven (the freeze), not a blanket reclassify block.
--   ⚠ Sec FLAG-1 follow-on (2026-08-25, SAME PR #561 AMBER round, second pass): tx_xfer is fz1's
--   OWN seeded classification (the annotation insert below), so that first pass made this a
--   SAME-VALUE write — and a same-value lives_ok here CANNOT FAIL: a transition-scoped guard
--   (WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id) would block every REAL reclassify while
--   still passing THIS assertion untouched, which is exactly the state-vs-transition blindness
--   Sec's (C'') rules out elsewhere in this fence family. Retargeted to tx_xfer2 (a SECOND
--   Transfer prototype, see the taxonomy seed note) — a value fz1 does not already hold, so this
--   is now a genuine reclassify. (5d) is ALSO tx_xfer2 (was tx_rev, then tx_xfer, across this
--   same AMBER round). (5d)/(5e) once again differ in exactly one variable — open vs closed —
--   nothing else, and (5e) can now actually fail if the freeze regresses.
select lives_ok(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :tx_xfer2, :fz1),
  '(5e) unfreeze RECLASSIFY: after REOPEN, re-categorizing the same leg (to Transfer) is ALLOWED (freeze lifted; #10 matched-tenant passes; 092''s journaled-cat fence passes since Transfer is not in its forbidden set). Proves 5d is close-status-driven, not a blanket block (target tx_xfer2 — a value fz1 does not already hold, so the write is a REAL reclassify; see the taxonomy seed note)');

-- (5f) after REOPEN: detach now ALLOWED (both OLD/NEW open → freeze no-op; #12 WHEN-skips on NULL).
select lives_ok(
  format($$ update pfin.account_trans_annotation set journal_id = null where trans_id = %s $$, :fz2),
  '(5f) unfreeze DETACH: after REOPEN, detaching the same leg is ALLOWED — non-vacuous unfreeze control (both OLD/NEW directions lifted)');

select set_config('role', 'postgres', true);

select * from finish();
rollback;
