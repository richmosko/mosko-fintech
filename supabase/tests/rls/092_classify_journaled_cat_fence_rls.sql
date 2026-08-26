-- =====================================================================
-- Per-Wave battery — SELF-248 classify backend: the M3 journaled-cat DB fence
--   (Sec D-8, reading (C), reformulated (C')(C'')(C''') — sitting item 15) +
--   AC3 Lock-10 legs + the AC10-condition-(3) existing-fence-through-new-write-path
--   leg + fn_suggest_subcat_for_vendor (AC7/AC8).
-- FINALIZED against the committed 092 migration blob. sha
--   c70f56dcf1f6559060be37b0f27b80ba1b4fe36f, file
--   supabase/migrations/092_classify_journaled_cat_fence_and_vendor_suggest.sql,
--   md5 903a3cb14b68c8c1b6f9e77d13f56acb (independently re-hashed by QA against
--   the committed blob at reconciliation, not taken from a report).
-- =====================================================================
-- BINDS TO MIGRATION:
--   supabase/migrations/092_classify_journaled_cat_fence_and_vendor_suggest.sql
--   (Architect, SELF-248; Sec D-8 reading (C), reformulated (C')(C'')(C''')).
--   - pfin.fn_account_trans_annotation_journaled_cat_fence() + trigger
--       account_trans_annotation_journaled_cat_fence — NEW function + NEW trigger
--       (NOT an edit to 084's fn_account_trans_annotation_trade_constraints — Sec's
--       PLACEMENT ruling (C'''): that function was already re-targeted once by a
--       catalog-measured fan-out (084) and carries a pg_description-shipped
--       COMMENT). BEFORE INSERT OR UPDATE on pfin.account_trans_annotation, WHEN
--       (new.sub_cat_id IS NOT NULL AND new.journal_id IS NOT NULL) — a STATE
--       predicate on NEW valid on BOTH ops (Sec (C''): a transition-scoped WHEN
--       referencing OLD cannot be written on an INSERT OR UPDATE trigger at all,
--       and would leave classify-then-attach open). Invariant (Sec (C')):
--       journal_id IS NOT NULL => resolved posting_prototype.cat NOT IN
--       ('Revenue','Expense','Equity') — the exact fall-through set of
--       084:869-872's ordered CASE. SECURITY INVOKER; set search_path='';
--       NULL-safe fail-closed (unresolvable/not-currently-visible prototype ->
--       raise, Sec condition 1). RAISE MESSAGES (both P0001, no explicit
--       SQLSTATE — DISTINGUISH BY PREFIX, not SQLSTATE, per the migration's own
--       "FIRING ORDER" note that several sibling fences also raise P0001):
--         defect state:      'journaled-leg classification rejected: ...'
--         unresolvable proto: 'journaled-leg classification fence: cannot resolve
--                              class ...'
--       FIRING ORDER (stated in the migration as explicitly NOT load-bearing —
--       every sibling fence is fail-closed so any order refuses the same writes):
--       ..._freeze_closed < ..._journaled_cat_fence < ..._matched_journal <
--       ..._matched_sub_cat < ..._trade_constraints (Postgres BEFORE-trigger NAME
--       order). This file's isolation blocks (CC/NS/M5) disable specific triggers
--       to attribute a raise to ONE fence; no leg asserts the order itself.
--   - pfin.fn_suggest_subcat_for_vendor(p_vendor text) RETURNS bigint — SECURITY
--       INVOKER, STABLE, set search_path=''; EXECUTE granted to authenticated
--       only (not PUBLIC). No tenant parameter — an account_users rd_access
--       conjunct (deliberately redundant with 006's RLS; the join key is a
--       SHARED-VOCABULARY vendor STRING, so the redundancy is what keeps an RLS
--       regression failing CLOSED rather than open on this specific join — this
--       file's V4 leg binds to the BEHAVIOR, not to the conjunct's presence, per
--       team-lead's routing: Sec rules on the conjunct itself at review).
--       Matching: exact, case-insensitive, on BOTH sides trimmed
--       (lower(btrim(...))) — nothing further (no internal-whitespace/punctuation
--       normalization). NULL when p_vendor is NULL or blank-after-trim, and NULL
--       when there is no matching history. Recency = MOST RECENTLY EDITED
--       annotation (ann.updated_at, which fn_refresh_updated_at refreshes on ANY
--       update — a note edit or journal attach moves it too, not only a
--       reclassification), NOT account_trans.transaction_date. Ties on
--       updated_at break by ann.trans_id DESC (deterministic).
--   - the classify endpoint's Lock-10 posture: annotation writes never touch
--       pfin.account_trans (004's immutable ledger is untouched by design — the
--       overlay IS the reversible layer). 092 adds no table/column/policy/grant.
-- Prereqs exercised (on the 001->091 reset stack): 001 (pfin, fn_refresh_updated_at),
--   003 (account + creator-grant rd=t/wr=t), 004 (account_trans immutable ledger +
--   fn_account_trans_block_mutation — the Lock-10 fence this file re-confirms, not
--   re-authors), 006 (account_trans rd/wr_access-JOIN RLS), 016/017 (pfin.asset +
--   security_id/quantity facts — the Trade in-kind control), 023 (account_trans_
--   annotation host + #10 matched_sub_cat), 030 (trade_constraints — the 084:1233
--   biconditional forcing Trade on a security leg), 033 (pfin.journal + journal_id +
--   #12 matched_journal), 037 (freeze_closed — journals stay OPEN throughout this
--   file so it never interferes), 084 (posting_prototype — the vocabulary the fence
--   resolves; the P3 CASE the invariant is derived from).
--
-- ┌─ WHY BOTH ORDERS, EXPLICITLY (Sec's own wording — the whole point of (C'')) ───────────┐
-- │ A WHEN clause on BEFORE INSERT OR UPDATE cannot reference OLD. A transition-scoped     │
-- │ guard (e.g. "WHEN journal_id changed") would therefore have to be written as a STATE   │
-- │ check anyway on INSERT, but if authored to key off OLD.sub_cat_id IS DISTINCT FROM     │
-- │ NEW.sub_cat_id (the WRONG shape Sec's (C'') rules out) it leaves classify-then-attach   │
-- │ OPEN: that order changes ONLY journal_id, never sub_cat_id, so a transition-scoped      │
-- │ guard never fires and the defect state is reached silently. A battery that tests only   │
-- │ attach-then-classify cannot distinguish the correct STATE-predicate fence from the      │
-- │ incorrect transition-scoped one — both would pass. BLOCK D tests BOTH orders for        │
-- │ exactly this reason (Sec condition 3, verbatim).                                        │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY BLOCK CC (corrupt-the-control) IS NOT DECORATIVE ─────────────────────────────────┐
-- │ Several OTHER triggers on this table also raise P0001 (#10 matched_sub_cat, #12         │
-- │ matched_journal, 030 trade_constraints, 037 freeze_closed). A RAISE in BLOCK D proves    │
-- │ SOMETHING rejected the write; it does not by itself prove the NEW fence is what did.     │
-- │ BLOCK CC disables ONLY the new trigger and retries the identical transition (same fixture│
-- │ rows, same statement shape) -> COMMITS. That is the inversion: strike the fence, the two │
-- │ legs go from RED (raise) to GREEN (commit), so BLOCK D's raises are attributable to THIS │
-- │ fence, not a sibling. (Sec condition 3's "corrupt-the-control pair on the fence itself".) │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (D1a)/(D2a)/(D3a) NON-VACUOUS: the first half of each two-step transition (the classify-
--     alone or attach-alone step) COMMITS -> proves the SECOND half's raise (D1b/D2b/D3b) is
--     the fence catching the COMBINED state, not a mis-shaped fixture.
--   (D1b) classify-then-attach, Expense: RED if the fence used a transition-scoped WHEN
--     (Sec's exact hazard) -> the defect state (journaled + Revenue/Expense/Equity) would
--     land silently on this order.
--   (D2b) attach-then-classify, Revenue: RED if the fence's invariant were absent/narrowed.
--   (D3b) attach-then-classify, Equity: RED if the invariant covered only Revenue/Expense
--     (a 2-of-3 fence would leave Equity open — the exact fall-through set has three members).
--   (CC1)/(CC2) with the fence DISABLED, the identical D1/D2 transitions COMMIT -> proves
--     D1b/D2b's raises are attributable to THIS fence (not #10/#12/030/037).
--   (NS1) NULL-safe fail-closed, ISOLATED (every sibling BEFORE trigger disabled): a REAL,
--     EXISTING posting_prototype row that is RLS-INVISIBLE to the caller (B's own, under A's
--     session — not merely a nonexistent id, which the FK would ALSO close and which is
--     reachable trivially under any role including postgres) + a valid journal_id RAISES the
--     new fence's OWN guard -> RED if the fence silently skipped an unresolvable-under-RLS
--     prototype (a NULL <> comparison leak). This is the one leg only an authenticated
--     two-tenant RLS fixture can exercise — unreachable as postgres (RLS does not apply).
--   (CTRL1) Transfer-classified leg attaches to a journal -> COMMITS: RED if the invariant
--     were mis-written as "refuse non-Transfer" (which the fall-through-set framing already
--     rules out) or over-broadened to catch Transfer.
--   (CTRL2) Trade-classified in-kind leg (security_id set, forced cat=Trade by 084:1233)
--     attaches to a journal -> COMMITS: RED if a naive "refuse non-Transfer" shape had been
--     used instead (Sec's explicit warning — it would refuse every in-kind transfer leg).
--   (L1) classify leaves the pfin.account_trans row BYTE-IDENTICAL (row_to_json compared
--     before/after, not error-absence) -> RED if a classify write ever touched the immutable
--     ledger (Lock 10 violated silently).
--   (L2) a direct UPDATE on pfin.account_trans still RAISES (004's fn_account_trans_block_
--     mutation, RE-CONFIRMED not re-authored) -> RED if 092 disturbed the immutability fence.
--   (M5) the #10 matched_sub_cat fence, ISOLATED from the new trigger, still REJECTS a
--     cross-tenant sub_cat_id on the NEW combined (sub_cat_id + journal_id in one write)
--     path -> RED if the combined write somehow bypassed #10 (a regression the old
--     single-column write path could not have exercised).
--   (V1) most-recent-by-ANNOTATION-updated_at wins over the transaction with the later
--     transaction_date -> RED if the function ordered by transaction_date instead (the AC's
--     explicit non-obvious ruling).
--   (V2) case-insensitive + trimmed EXACT match -> RED if matching were case-sensitive or
--     whitespace-sensitive.
--   (V2b) a non-exact (substring) vendor does NOT match -> NULL: RED if matching degraded to
--     a fuzzy/ILIKE-wildcard match instead of exact (the non-vacuous discriminator for V2).
--   (V3) NULL on no matching vendor history -> RED if the function raised or returned a
--     wrong default instead of NULL (the lazy-classify UI depends on NULL = no suggestion).
--   (V3b) NULL on a whitespace-only p_vendor -> RED if the blank-after-trim guard were
--     dropped and a blank query matched every blank-vendor row instead of returning NULL.
--   (V3c) NULL on a NULL p_vendor -> RED if the function raised instead of returning NULL
--     on the absent-argument case (a plausible caller shape from an unclassified UI field).
--   (V-tie) a genuine tie on updated_at breaks deterministically by trans_id DESC -> RED if
--     ties were nondeterministic (order-dependent CI flake) or broke the wrong direction.
--   (V4) tenancy: B's call with A's exact vendor string resolves to B's OWN history (not
--     NULL, not A's) -> RED if the function's RLS composition leaked A's annotation history
--     to B, or if the leg were vacuous (B having no history of its own).
--
-- §10 / DECISION 3: this fence introduces ZERO new §10 catalogued instances (no infra-
--   credential / service_role / admission-layer surface — an authenticated-tier INVOKER
--   value-class trigger only) and ZERO new Decision-3 family members (no new FK-shaped
--   column — it resolves the ALREADY-fenced sub_cat_id [#10] and journal_id [#12] FKs into
--   their classes; it is a value-invariant over two pre-fenced references, not a new
--   cross-tenant reference). Read ADR-011 Decision 3 / Decision 4 live at joint-review — this
--   file states no count.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO prod data. A owns an investment account (cash + one security
--   leg) + Expense/Revenue/Equity/Transfer/Trade posting_prototype rows + two OPEN journals;
--   B owns a depository account + one Expense prototype (the #10 cross-tenant referent) + its
--   OWN vendor-classified history (the V4 tenancy referent). All in a rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against the re-derived ACs (Linear SELF-248) + Sec's D-8 verbatim
--   conditions (docs/records/v13-preflight/sec-v13-d7-d8.md), then FINALIZED against the
--   committed 092 blob (sha c70f56d, md5 903a3cb14b68c8c1b6f9e77d13f56acb, independently
--   re-hashed). The authoritative run is the 001->092 reset stack on a scratch DB (Backend
--   clean-apply shape; `supabase db reset` remains banned). CI (pg_prove directory-mode,
--   db-tests.yml) is the green gate. plan(23).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(23);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-alpha (investment; 003 creator-grant seeds rd=t/wr=t): 7 cash legs
--    (one per BLOCK-D/CC/NS/CTRL1/L/M5 fixture row) + 1 securities leg (the Trade
--    in-kind control) + 2 vendor-history cash legs ('acme corp' recency pair) + 1
--    vendor case/trim leg + 2 vendor tie-break legs ('Tie Vendor' pair). No B-owned
--    leg is needed: M5's cross-tenant probe uses A's OWN leg (leg_m5) classified
--    with B's (cross-tenant) posting_prototype, not a B-owned trans_id.
--  - B owns acct-beta (depository): its OWN 'acme corp' vendor history (the V4
--    tenancy referent — B has real history under the SAME vendor string A does, to
--    prove V4 isn't a vacuous "B has nothing").
--  - posting_prototype: A owns Expense/Rent, Revenue/Salary, Equity/OwnerContribution,
--    Transfer/Transfer, Trade/BTO (qty>0 sign-aligned per 030), Expense/Groceries +
--    Expense/Dining (vendor-history sub_cats). B owns Expense/Rent (the #10 / NS1
--    cross-tenant referent) + Expense/Groceries (B's own vendor-history sub_cat).
--  - journal: A owns jA (compound, open — the classify/attach fixture target) + jTR
--    (transfer_in_kind, open — the Trade in-kind control's realistic group_type).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GSX', 'Global Sec X') returning asset_id as g_asset \gset

-- A's cash legs (one per fixture use).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-01', -10, 'vD1', 'D1 classify-then-attach') returning trans_id as leg_d1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-02', -10, 'vD2', 'D2 attach-then-classify') returning trans_id as leg_d2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-03', -10, 'vD3', 'D3 attach-then-classify Equity') returning trans_id as leg_d3 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-04', -10, 'vNS', 'NS null-safe isolation') returning trans_id as leg_ns \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-05', -10, 'vCTRL1', 'CTRL1 transfer control') returning trans_id as leg_ctrl1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-06', -10, 'vL1', 'L1 byte-identical') returning trans_id as leg_l1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-07', -10, 'vL2', 'L2 direct UPDATE') returning trans_id as leg_l2 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-08', -10, 'vM5', 'M5 cross-tenant combined write') returning trans_id as leg_m5 \gset

-- A's securities leg (Trade in-kind control): security_id set, quantity>0 (BTO sign-aligned).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-04-09', -500, 'vCTRL2', 'CTRL2 trade in-kind control', :g_asset, 5)
  returning trans_id as leg_ctrl2 \gset

-- Vendor-history fixture. txn_old (EARLIER transaction_date) gets the LATER updated_at;
-- txn_new (LATER transaction_date) gets the EARLIER updated_at — the discriminating shape
-- for V1 (recency by ANNOTATION.updated_at, not transaction_date). updated_at is settable
-- on INSERT (fn_refresh_updated_at is a BEFORE UPDATE trigger only — it does not touch
-- INSERT's explicit column value), so no sleep/wall-clock dependency.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-01-05', -20, 'Acme Corp', 'vendor recency old-txn') returning trans_id as v_old \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-06-05', -20, 'Acme Corp', 'vendor recency new-txn') returning trans_id as v_new \gset
-- V2/V2b case+trim fixture (distinct vendor string; independent of the recency pair).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-11', -30, 'Whole Foods', 'vendor case/trim match') returning trans_id as v_case \gset

-- B's OWN 'acme corp' vendor history (V4 tenancy referent — B has REAL matching-vendor
-- history, so B's own result proves RLS isolation resolves to B's row, not merely "B has
-- nothing" or a leak of A's row).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-05-01', -20, 'Acme Corp', 'beta vendor history') returning trans_id as v_b \gset

-- V-tie fixture: two A txns sharing a vendor, annotated with the IDENTICAL updated_at
-- literal (a genuine tie) — v_tie_b is inserted SECOND so it holds the higher trans_id,
-- the deterministic tie-break per the function's ORDER BY ann.updated_at desc, ann.trans_id
-- desc.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-01', -15, 'Tie Vendor', 'tie fixture a') returning trans_id as v_tie_a \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-01', -15, 'Tie Vendor', 'tie fixture b') returning trans_id as v_tie_b \gset

-- posting_prototype (A). is_tax_payment NOT NULL no DEFAULT (091) -> false throughout.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Rent', false) returning id as a_exp \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Revenue', 'Salary', false) returning id as a_rev \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Equity', 'OwnerContribution', false) returning id as a_eq \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'Transfer', false) returning id as a_transfer \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Trade', 'BTO', false) returning id as a_bto \gset
-- vendor-history sub_cats (A) — Groceries used for the recency pair + case/trim leg.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Groceries', false) returning id as a_grocery \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Dining', false) returning id as a_dining \gset

-- posting_prototype (B) — Expense/Rent is the #10 cross-tenant referent; Groceries is
-- B's own vendor-history sub_cat.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'Rent', false) returning id as b_exp \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'Groceries', false) returning id as b_grocery \gset

-- journals (A). users_id explicit — auth.uid() is NULL under postgres.
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'compound', 'open', 'jA') returning journal_id as j_a \gset
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer_in_kind', 'open', 'jTR') returning journal_id as j_tr \gset

-- =====================================================================
-- BLOCK D (authenticated A) — the AC10 core invariant, BOTH ORDERS, three cats.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (D1a) NON-VACUOUS: classify leg_d1 with Expense (journal_id still NULL) -> COMMITS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :leg_d1, :a_exp),
  '(D1a) NON-VACUOUS: classify (Expense, no journal yet) COMMITS -> the second step (D1b) below is the fence catching the COMBINED state, not a malformed fixture'
);
-- (D1b) classify-then-attach: UPDATE journal_id -> RAISE (sub_cat_id already Expense;
--   only journal_id changes on this write — the order a transition-scoped OLD.sub_cat_id
--   guard would MISS, per Sec's exact hazard).
select throws_like(
  format($$ update pfin.account_trans_annotation set journal_id = %s where trans_id = %s $$, :j_a, :leg_d1),
  'journaled-leg classification rejected:%',
  '(D1b) M3 journaled-cat fence, CLASSIFY-THEN-ATTACH order: attaching an already-Expense-classified leg to a journal RAISES the DEFECT-STATE message -> the STATE predicate (new.sub_cat_id IS NOT NULL AND new.journal_id IS NOT NULL) fires on the journal_id-only UPDATE; a transition-scoped OLD.sub_cat_id-changed guard would have missed this order entirely (Sec C double-prime)'
);

-- (D2a) NON-VACUOUS: attach leg_d2 to jA (sub_cat_id still NULL) -> COMMITS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_d2, :j_a),
  '(D2a) NON-VACUOUS: attach (journal jA, no classification yet) COMMITS -> the second step (D2b) below is the fence catching the COMBINED state'
);
-- (D2b) attach-then-classify: UPDATE sub_cat_id to Revenue -> RAISE.
select throws_like(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_rev, :leg_d2),
  'journaled-leg classification rejected:%',
  '(D2b) M3 journaled-cat fence, ATTACH-THEN-CLASSIFY order: classifying an already-journaled leg as Revenue RAISES the DEFECT-STATE message -> journal_id IS NOT NULL and resolved cat=Revenue is exactly the 084:869-872 fall-through set'
);

-- (D3a) NON-VACUOUS: attach leg_d3 to jA -> COMMITS.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, journal_id) values (%s, %s) $$, :leg_d3, :j_a),
  '(D3a) NON-VACUOUS: attach (journal jA, no classification yet) COMMITS'
);
-- (D3b) attach-then-classify, THIRD cat (Equity): the fall-through set has THREE members —
--   RED if the invariant only covered Revenue/Expense (a 2-of-3 fence).
select throws_like(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_eq, :leg_d3),
  'journaled-leg classification rejected:%',
  '(D3b) M3 journaled-cat fence, THIRD cat coverage: classifying an already-journaled leg as Equity RAISES the DEFECT-STATE message -> the invariant covers all three fall-through members (Revenue/Expense/Equity), not just two'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK CC (corrupt-the-control) — disable ONLY the new trigger; retry the IDENTICAL
--   D1/D2 transitions on the SAME fixture rows -> COMMITS. Proves D1b/D2b's raises are
--   attributable to THIS fence, not #10 / #12 / 030 / 037 (Sec condition 3).
-- =====================================================================
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_journaled_cat_fence;

select _rls.set_tenant(:'ta'::uuid);

-- (CC1) fence DISABLED: retry leg_d1's journal_id attach (Expense already set) -> COMMITS.
select lives_ok(
  format($$ update pfin.account_trans_annotation set journal_id = %s where trans_id = %s $$, :j_a, :leg_d1),
  '(CC1) CORRUPT-THE-CONTROL: with the M3 fence trigger DISABLED, the IDENTICAL classify-then-attach transition (leg_d1, Expense + jA) that RAISED at (D1b) now COMMITS -> D1b''s raise is attributable to THIS fence, not a sibling trigger'
);
-- (CC2) fence DISABLED: retry leg_d2's classify to Revenue (journal already attached) -> COMMITS.
select lives_ok(
  format($$ update pfin.account_trans_annotation set sub_cat_id = %s where trans_id = %s $$, :a_rev, :leg_d2),
  '(CC2) CORRUPT-THE-CONTROL: with the M3 fence trigger DISABLED, the IDENTICAL attach-then-classify transition (leg_d2, jA + Revenue) that RAISED at (D2b) now COMMITS -> D2b''s raise is attributable to THIS fence, not a sibling trigger'
);
select set_config('role', 'postgres', true);

alter table pfin.account_trans_annotation enable trigger account_trans_annotation_journaled_cat_fence;

-- =====================================================================
-- BLOCK NS (NULL-safe fail-closed, ISOLATED) — every SIBLING BEFORE trigger disabled so
--   the new fence's OWN guard is the sole possible source of a raise (mirrors the 030
--   (7b) / 023 LEG-F isolation technique).
-- =====================================================================
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_matched_sub_cat;
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_trade_constraints;
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_matched_journal;
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_freeze_closed;

select _rls.set_tenant(:'ta'::uuid);

-- (NS1) an EXISTING posting_prototype row that is RLS-INVISIBLE to A (B's OWN b_exp — not
--   a nonexistent id: under postgres, RLS does not apply, so this specific "resolved-but-
--   RLS-hidden" branch cannot be exercised as superuser; a nonexistent id is FK-closed and
--   trivially unresolvable under ANY role, which is a weaker proof) + a VALID journal_id,
--   with every sibling fence disabled -> the new fence's OWN NULL-safe guard RAISES.
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (%s, %s, %s) $$, :leg_ns, :b_exp, :j_a),
  'journaled-leg classification fence: cannot resolve class%',
  '(NS1) M3 fence NULL-safe fail-closed, ISOLATED: B''s OWN posting_prototype row (b_exp), RLS-INVISIBLE to A, referenced as sub_cat_id + a valid journal_id RAISES the new fence''s OWN unresolvable-class guard with every sibling trigger disabled -> a not-currently-visible prototype row fails closed (never a silent NULL <> skip). This leg needs an authenticated two-tenant RLS fixture -- unreachable as postgres, which bypasses RLS entirely'
);
select set_config('role', 'postgres', true);

alter table pfin.account_trans_annotation enable trigger account_trans_annotation_matched_sub_cat;
alter table pfin.account_trans_annotation enable trigger account_trans_annotation_trade_constraints;
alter table pfin.account_trans_annotation enable trigger account_trans_annotation_matched_journal;
alter table pfin.account_trans_annotation enable trigger account_trans_annotation_freeze_closed;

-- =====================================================================
-- BLOCK CTRL (lives_ok controls — Sec's explicit non-vacuous pair) — a Transfer-classified
--   leg and a Trade-classified in-kind leg both attach to a journal WITHOUT raising.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (CTRL1) Transfer-classified leg attaches -> COMMITS. RED if the invariant had been
--   mis-shaped as "refuse non-Transfer" narrowed the wrong direction, or over-broadened.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (%s, %s, %s) $$, :leg_ctrl1, :a_transfer, :j_a),
  '(CTRL1) control: a Transfer-classified leg attaches to a journal in ONE combined write -> COMMITS (Transfer is NOT in the Revenue/Expense/Equity fall-through set)'
);

-- (CTRL2) Trade-classified in-kind leg (security_id set, cat forced to Trade by the
--   084:1233 biconditional) attaches to a transfer_in_kind journal -> COMMITS. This is the
--   control Sec named explicitly: a naive "refuse non-Transfer cat when journal_id IS NOT
--   NULL" formulation would refuse every in-kind transfer leg, because in-kind legs are
--   ALWAYS cat=Trade, never cat=Transfer.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (%s, %s, %s) $$, :leg_ctrl2, :a_bto, :j_tr),
  '(CTRL2) control: a Trade-classified in-kind leg (security_id set, cat=Trade forced by the 084:1233 biconditional) attaches to a transfer_in_kind journal -> COMMITS. Proves the fence is NOT the naive "refuse non-Transfer" shape Sec explicitly warned against'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK L (AC3 — Lock 10 legs) — a classify write never touches pfin.account_trans, and
--   a direct UPDATE on the immutable ledger still raises (004, re-confirmed not re-authored).
-- =====================================================================
-- (L1) capture a full-row fingerprint of leg_l1's account_trans row BEFORE classifying it.
select row_to_json(t)::text as before_row from pfin.account_trans t where trans_id = :leg_l1 \gset

select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :leg_l1, :a_exp),
  '(L1-setup) classify leg_l1 (Expense) -> COMMITS (the overlay write itself)'
);
select set_config('role', 'postgres', true);

-- (L1) the account_trans row is BYTE-IDENTICAL after the classify write (column values
--   compared, not error-absence) -> Lock 10 not violated because the ledger row was never
--   written, exactly as AC3 requires.
select is(
  (select row_to_json(t)::text from pfin.account_trans t where trans_id = :leg_l1),
  :'before_row',
  '(L1) AC3 Lock-10: pfin.account_trans row for leg_l1 is BYTE-IDENTICAL before/after the classify write (row_to_json full-column compare) -> the annotation overlay never touches the immutable ledger'
);

-- (L2) a direct UPDATE attempt on pfin.account_trans still RAISES (004's
--   fn_account_trans_block_mutation, RE-CONFIRMED here, not re-authored by 092).
select throws_like(
  format($$ update pfin.account_trans set amount = -999 where trans_id = %s $$, :leg_l2),
  '%account_trans is immutable%',
  '(L2) AC3 Lock-10: a direct UPDATE attempt on pfin.account_trans RAISES (004''s pre-existing fn_account_trans_block_mutation) -> the immutability fence is UNDISTURBED by 092''s classify write path'
);

-- =====================================================================
-- BLOCK M5 (AC10 condition-3 — matched-sub_cat fence through the NEW combined write path)
--   #10 (fn_account_trans_annotation_matched_sub_cat), ISOLATED from the new M3 fence, still
--   rejects a cross-tenant sub_cat_id when sub_cat_id + journal_id are set in ONE write —
--   the combined write shape 092 introduces that the pre-092 single-column write path could
--   not exercise.
-- =====================================================================
alter table pfin.account_trans_annotation disable trigger account_trans_annotation_journaled_cat_fence;

select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id) values (%s, %s, %s) $$, :leg_m5, :b_exp, :j_a),
  '%is not a posting prototype owned by and visible to the tenant of trans_id%',
  '(M5) AC10 condition-3: A attaches its own leg to its own journal WHILE classifying with B''s (cross-tenant) posting_prototype in ONE combined write -> the PRE-EXISTING #10 matched_sub_cat fence (084-re-targeted message) STILL REJECTS (isolated from the new M3 fence, which is disabled here) -> #10 is undisturbed by the new combined write path 092 introduces'
);
select set_config('role', 'postgres', true);

alter table pfin.account_trans_annotation enable trigger account_trans_annotation_journaled_cat_fence;

-- =====================================================================
-- BLOCK V (AC7/AC8 — fn_suggest_subcat_for_vendor)
-- =====================================================================
-- Vendor-history annotations. updated_at is settable on INSERT (fn_refresh_updated_at is a
-- BEFORE UPDATE trigger only) -> deterministic recency ordering, no wall-clock dependency.
-- v_old (transaction_date 2026-01-05, EARLIER) gets the LATER updated_at (2026-06-01).
-- v_new (transaction_date 2026-06-05, LATER) gets the EARLIER updated_at (2026-01-01).
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, updated_at)
  values (:v_old, :a_grocery, '2026-06-01T00:00:00Z');
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, updated_at)
  values (:v_new, :a_dining, '2026-01-01T00:00:00Z');
-- case/trim fixture: vendor stored as 'Whole Foods'.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:v_case, :a_grocery);
-- B's own 'acme corp' history (the V4 tenancy referent).
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:v_b, :b_grocery);
-- V-tie fixture: v_tie_a and v_tie_b annotated with the IDENTICAL updated_at literal (a
-- genuine tie) -> the function's ann.trans_id desc tie-break must pick v_tie_b (a_dining),
-- the higher trans_id.
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, updated_at)
  values (:v_tie_a, :a_grocery, '2026-03-15T12:00:00Z');
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, updated_at)
  values (:v_tie_b, :a_dining, '2026-03-15T12:00:00Z');

select _rls.set_tenant(:'ta'::uuid);

-- (V1) recency by ANNOTATION.updated_at, not transaction_date: v_old's annotation
--   (a_grocery) has the LATER updated_at despite the EARLIER transaction_date -> WINS.
select is(
  (select pfin.fn_suggest_subcat_for_vendor('Acme Corp')),
  :a_grocery::bigint,
  '(V1) fn_suggest_subcat_for_vendor orders by ANNOTATION.updated_at: v_old''s annotation (later updated_at, earlier transaction_date) wins over v_new''s (earlier updated_at, later transaction_date) -> recency is annotation-based, not transaction-date-based'
);

-- (V2) case-insensitive + trimmed EXACT match: query with different case + surrounding
--   whitespace than the stored 'Whole Foods' vendor string.
select is(
  (select pfin.fn_suggest_subcat_for_vendor('  whole FOODS  ')),
  :a_grocery::bigint,
  '(V2) case-insensitive + trimmed EXACT match: querying "  whole FOODS  " matches the stored vendor "Whole Foods" -> the ruled-default normalization (trim + lower)'
);

-- (V2b) NON-VACUOUS discriminator for V2: a non-exact (substring) vendor does NOT match ->
--   NULL. RED if matching degraded to ILIKE/fuzzy instead of exact.
select is(
  (select pfin.fn_suggest_subcat_for_vendor('Whole Foods Market')),
  null::bigint,
  '(V2b) NON-VACUOUS: "Whole Foods Market" (a superstring of the stored "Whole Foods") does NOT match -> NULL, proving V2 is an EXACT match (trimmed + case-insensitive), not a fuzzy/substring one'
);

-- (V3) NULL on no matching vendor history at all.
select is(
  (select pfin.fn_suggest_subcat_for_vendor('Nonexistent Vendor Zyxwvut')),
  null::bigint,
  '(V3) NULL on no history: a vendor string with zero prior annotated transactions returns NULL (never raises, never a wrong default)'
);

-- (V3b) NULL on a whitespace-only p_vendor: RED if the blank-after-trim guard were dropped
-- and a blank query matched every blank-vendor row instead of returning NULL.
select is(
  (select pfin.fn_suggest_subcat_for_vendor('    ')),
  null::bigint,
  '(V3b) NULL on blank-after-trim p_vendor: a whitespace-only query returns NULL (the btrim(p_vendor) <> '''' guard), never matching every blank-vendor row'
);

-- (V3c) NULL on a NULL p_vendor (never raises on the absent-argument shape).
select is(
  (select pfin.fn_suggest_subcat_for_vendor(null)),
  null::bigint,
  '(V3c) NULL on NULL p_vendor: the function returns NULL rather than raising on a NULL argument'
);

-- (V-tie) deterministic tie-break: v_tie_a and v_tie_b share the IDENTICAL updated_at ->
-- the function resolves to v_tie_b's sub_cat (a_dining), the HIGHER trans_id (ann.trans_id
-- desc, the function's own documented tie-break).
select is(
  (select pfin.fn_suggest_subcat_for_vendor('Tie Vendor')),
  :a_dining::bigint,
  '(V-tie) deterministic tie-break: a genuine tie on ann.updated_at resolves to the HIGHER ann.trans_id (v_tie_b / a_dining), matching the function''s documented ORDER BY ann.updated_at desc, ann.trans_id desc'
);
select set_config('role', 'postgres', true);

-- (V4) tenancy: under B, the SAME exact vendor string ('Acme Corp') that resolves for A
--   returns NULL for B — B HAS its own real 'Acme Corp' history (v_b/b_grocery, seeded
--   above), so this is NOT "B has nothing"; RLS on the account_trans_annotation /
--   account_trans join must still resolve to B's OWN row, never A's.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select pfin.fn_suggest_subcat_for_vendor('Acme Corp')),
  :b_grocery::bigint,
  '(V4) tenancy: B''s call for "Acme Corp" resolves to B''S OWN annotation (b_grocery) — never A''s (a_grocery) — proving the function''s RLS composition (no tenant parameter) isolates per-tenant vendor history correctly, not merely returning NULL because B has nothing'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
