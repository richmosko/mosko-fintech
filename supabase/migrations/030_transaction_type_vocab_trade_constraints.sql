-- ============================================================================
-- Migration: M1-evt Slice A1 — event-class vocabulary refactor + Trade partition.
--   (1) widen pfin.account_trans.transaction_type to the lean fact-level set;
--   (2) add pfin.account_trans_annotation.metadata (jsonb) — the reason/action home;
--   (3) the combined Trade-constraint trigger on account_trans_annotation
--       (consistency + sign-alignment; Sec Condition A).
-- Phase 6 Build Loop — M1-evt of the Double-Entry GL track (Linear SELF-293).
--   F/CTO-ratified 2026-07-24 (all 5 M1-evt decisions). Design paper
--   temp/self-293-m1evt-design.md. Built to ADR-031 Amendment 1 (which SUPERSEDED
--   the design-v2 7-value sketch → lean {standard, acct_setup, basis_adjust,
--   corp_action}) + ADR-025 Amendment 1 (the six preserves) + ADR-031 Decision 7
--   Sec Condition A. THREE-SLICE decomposition (F/CTO): A1 = THIS (the import-
--   critical core); A2 = the reclassification-history audit-class table (REOPENED
--   per Sec Condition B — separate PR + Sec gate); B = the lot-match buy-reference
--   FK (Decision-3 #14, deferred to the lot-matching build).
--
-- WHAT THIS DOES (Slice A1):
--   (1) transaction_type CHECK widen {standard, acct_setup} → {standard, acct_setup,
--       basis_adjust, corp_action}. ADDITIVE (every existing row is standard|
--       acct_setup, both retained). This is DDL — the 004 immutability triple-fence
--       blocks ROW DML (UPDATE/DELETE/TRUNCATE), NOT ALTER TABLE — so the fence is
--       UNTOUCHED. basis_adjust/corp_action are stored FACTS now; their GL handling
--       lands later (basis_adjust → M3-basis; corp_action → M4-GL reads). A widened-
--       but-unhandled type is inert (amount=0/quantity=0 basis_adjust is ignored by
--       NAV; a split is a quantity restatement). F/CTO confirmed the incumbent
--       import HAS basis_adjust-type events → tag against the final vocab now
--       (settle-before-import, ADR-031 D9 / ADR-025 preserve-(d)).
--   (2) metadata jsonb NULL on account_trans_annotation (023) — carries
--       basis_adjust `metadata.reason ∈ {depreciation, return_of_capital, wash_sale}`
--       (Amendment 1 §6) + corp_action `metadata.action` (§5). Lives on the MUTABLE
--       overlay (Amendment 1 §8; 023 had none — jsonb metadata previously existed
--       only on pfin.asset/016). A plain jsonb value column: NOT an FK-shaped ref
--       (Decision 3 N/A), NOT a §10 surface.
--   (3) fn_account_trans_annotation_trade_constraints — the combined Trade fence
--       (Sec Condition A). See POSTURE + CONTRACT.
--
-- WHAT THIS IS NOT (Slice A1): NO lot-match buy-reference FK (Slice B, = Decision-3
--   #14, Sec pins). NO reclassification-history table (Slice A2). NO new function
--   with elevated privilege. NO RLS/GRANT change (the metadata column inherits 023's
--   existing full-CRUD posture; the CHECK-widen + trigger touch no grant).
--
-- Numbering: 030 follows 029 (account_trans_split). Depends on 004 (account_trans —
--   the transaction_type column widened + the security_id/quantity facts the trigger
--   reads), 009 (user_taxonomy — the cat/sub_cat the trigger resolves via sub_cat_id),
--   023 (account_trans_annotation — the metadata column added + the trigger's host),
--   012 (the inline transaction_type CHECK this widens), 017 (security_id/quantity on
--   account_trans), and 001 (pfin schema). No downstream migration depends on 030
--   landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — the SECURITY DEFINER allowlist STAYS 3 (ADR-011 Decision 9:
--   fn_refresh_updated_at + fn_grant_creator_access + the still-unauthored audit-log
--   helper). ONE new function is authored — NON-DEFINER:
--     - fn_account_trans_annotation_trade_constraints — SECURITY INVOKER,
--       set search_path = ''. Reads the frozen fact (account_trans.security_id/
--       quantity) + the class (user_taxonomy.cat/sub_cat) under the caller's RLS;
--       needs no elevated privilege → INVOKER → not an allowlist entry. Cross-tenant
--       sub_cat is ALREADY fenced by the shipped #10 matched-tenant fence (fires on
--       the same 023 write), so this fence carries NO cross-tenant dimension
--       (Decision-3-NEUTRAL, Sec Condition A). ZERO new SECURITY DEFINER in 030.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 3
--   (RT-22 + RT-26 + RT-27 per ADR-011 Decision 4 — RT-27 appended third at SELF-212,
--   2026-07-19; earlier headers reading "stays 2" predate that move).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22),
--         no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist surface (RT-26), and no
--         network-exposure/config surface (RT-27) is touched. A CHECK-widen + a jsonb
--         value column + an authenticated-tier INVOKER value-fence: no admission
--         channel, no credential surface, no privileged grant. Nothing becomes
--         "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD: the Trade fence is a value/consistency mechanism, NOT a §10
--   catalogued instance and NOT a Decision-3 instance (no cross-tenant dimension).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +0 (UNCHANGED).
--   This migration adds NO FK-shaped reference column:
--     - the transaction_type CHECK-widen is a value-domain constraint on an existing
--       column (no reference).
--     - metadata jsonb is a value column (no FOREIGN KEY, no INTEGER[]/array element,
--       no reference of any kind).
--     - the Trade-constraint trigger reads security_id/quantity + cat/sub_cat but
--       introduces no new reference column and no cross-tenant dimension — the
--       cross-tenant sub_cat_id is already fenced by the shipped #10 fence (Sec
--       Condition A: these fences are Decision-3-NEUTRAL). Family UNCHANGED
--       (12 labeled / 10 DDL-realized after 029). The DEFERRED lot-match buy-
--       reference FK (Slice B) will be the next instance (= #14, Sec pins — NOT #13,
--       which 029's split-sub_cat fence took first; see the ADR-025 line-766 fix in
--       this PR).
--
-- ----------------------------------------------------------------------------
-- ADR-025 AMENDMENT 1 — SIX PRESERVES (this migration REALIZES / conforms to them):
--   (a) transaction_type stays frozen-per-row on the immutable ledger — the 004
--       UPDATE/DELETE/TRUNCATE triple-fence is untouched (the widen is DDL).
--   (b) TEXT + CHECK (not enum/registry) — widened via a one-line additive CHECK
--       alter (ADR-022 code-coupled→CHECK).
--   (c) Fact-level-only vocabulary — the lean set {standard, acct_setup, basis_adjust,
--       corp_action} names only event kinds the source asserts; NO inferred value
--       (open/close designation) is a transaction_type value (open/close lives in the
--       Cat on the overlay, Amendment 1 §2).
--   (d) Settle-before-import — the vocabulary is fixed before the incumbent import.
--   (e) Reverse-and-replace + the #2 matched-account fence = the SOLE fact-correction
--       path (unchanged; this migration adds no fact-mutation path).
--   (f) SECURITY DEFINER allowlist stays 3 · §10 catalogued ledger stays 3.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans.transaction_type — CHECK widened to
--     ('standard','acct_setup','basis_adjust','corp_action'). Permanent per-row
--     (immutable table). standard = cash flows + trades (class from the Cat);
--     acct_setup/basis_adjust/corp_action = structural (NULL-cat; class from the
--     type). basis_adjust/corp_action GL handling is deferred (M3-basis / M4-GL).
--   pfin.account_trans_annotation.metadata (jsonb NULL) — the routing-detail home on
--     the mutable overlay: basis_adjust `reason` (§6) + corp_action `action` (§5).
--     Freely editable in V1 (Amendment 1 §9; the reclass-history freeze is Slice A2).
--   pfin.fn_account_trans_annotation_trade_constraints() — BEFORE INSERT OR UPDATE on
--     account_trans_annotation WHEN (new.sub_cat_id IS NOT NULL); SECURITY INVOKER;
--     set search_path=''; NULL-safe fail-closed. Resolves the frozen fact
--     (security_id, quantity) via new.trans_id → account_trans and the class
--     (cat, sub_cat) via new.sub_cat_id → user_taxonomy, then enforces:
--       (a) CONSISTENCY: security_id present  ⟺  cat = 'Trade'.
--       (b) SIGN-ALIGNMENT (cat='Trade' only): BTO/BTC ⟹ quantity > 0 (buy);
--           STC/STO ⟹ quantity < 0 (sell).
--     UPDATE path load-bearing: an overlay edit (e.g. BTO→STO on a frozen-quantity
--     row) re-validates against the frozen fact. Decision-3-neutral (no cross-tenant
--     dimension — #10 already fences a cross-tenant sub_cat). A NULL sub_cat_id
--     (Unsorted-pending → Suspense) is skipped by the WHEN clause. A sub_cat that is
--     not one of BTO/BTC/STC/STO on a Trade row is consistency-checked but not
--     sign-checked (sign-alignment is defined only for the four).
--   Security-load-bearing edges: NULL-safe fail-closed (a missing/unreadable fact or
--     class → raise, never a silent skip); INVOKER composes with RLS; the immutable
--     ledger fact is the integrity anchor (the UI is not the boundary — this trigger
--     is, per Amendment 1 §2(b)).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) Widen the transaction_type CHECK to the lean fact-level set (Amendment 1 §4).
-- ADDITIVE — existing standard|acct_setup rows are retained. DDL (not row DML) → the
-- 004 immutability fence is untouched. Idempotent: drop-if-exists the (012 auto-named)
-- constraint, re-add the widened one under the same canonical name.
-- ----------------------------------------------------------------------------
alter table pfin.account_trans
  drop constraint if exists account_trans_transaction_type_check;

alter table pfin.account_trans
  add constraint account_trans_transaction_type_check
    check (transaction_type in
      ('standard', 'acct_setup', 'basis_adjust', 'corp_action'));

comment on constraint account_trans_transaction_type_check on pfin.account_trans is
  'Fact-level event-kind vocabulary (M1-evt Slice A1; ADR-031 Amendment 1 §4). '
  'Widened 012''s {standard, acct_setup} → {standard, acct_setup, basis_adjust, '
  'corp_action} (additive; existing rows retained). standard = cash flows + trades '
  '(class from the Cat); acct_setup/basis_adjust/corp_action = structural (NULL-cat; '
  'class from the type). basis_adjust/corp_action are stored FACTS now — GL handling '
  'is deferred (basis_adjust → M3-basis; corp_action → M4-GL). Fact-level-only '
  'invariant (ADR-025 Amendment 1 preserve-(c)): no inferred value (open/close) is '
  'ever a transaction_type value — open/close lives in the Cat on the overlay. '
  'Permanent per-row (account_trans is immutable, 004); further additive widening is '
  'a one-line CHECK alter (ADR-022).';

-- ----------------------------------------------------------------------------
-- (2) Add the metadata jsonb column to the 023 mutable overlay (Amendment 1 §5/§6/§8).
-- The routing-detail home: basis_adjust.reason + corp_action.action. Plain jsonb value
-- column — NOT an FK (Decision 3 N/A), NOT a §10 surface. Inherits 023's existing RLS +
-- full-CRUD grant (no new grant/policy). Additive nullable column (idempotent).
-- ----------------------------------------------------------------------------
alter table pfin.account_trans_annotation
  add column if not exists metadata jsonb;

comment on column pfin.account_trans_annotation.metadata is
  'Routing-detail jsonb on the mutable overlay (M1-evt Slice A1; ADR-031 Amendment 1 '
  '§5/§6/§8). Carries basis_adjust `reason` ∈ {depreciation, return_of_capital, '
  'wash_sale} (§6) + corp_action `action` (e.g. split / ticker_change, §5). SUPERSEDES '
  'the Decision-4 `reason text` column sketch (§8: reason is now metadata.reason). '
  'Freely editable in V1 (Amendment 1 §9 — the append-only reclassification-history '
  'freeze is Slice A2, reopened per Sec Condition B). Nullable; NULL = no routing '
  'detail. Plain jsonb value column: not an FK (Decision 3 N/A), no §10 surface; '
  'inherits the 023 RLS + full-CRUD grant (no new grant/policy).';

-- ----------------------------------------------------------------------------
-- (3) The combined Trade-constraint trigger (Sec Condition A — GREEN-with-conditions
-- 2026-07-23). ONE BEFORE INSERT OR UPDATE trigger on account_trans_annotation
-- enforcing BOTH (a) consistency and (b) sign-alignment. Cross-table: security_id/
-- quantity on the immutable ledger (004/017), cat/sub_cat on the overlay's taxonomy
-- (009 via sub_cat_id) — a single-table CHECK cannot span them, so a trigger.
-- SECURITY INVOKER (Decision-3-neutral; DEFINER allowlist stays 3).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_annotation_trade_constraints()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_has_txn      boolean;
  v_security_id  bigint;
  v_quantity     numeric;
  v_has_tax      boolean;
  v_cat          text;
  v_sub_cat      text;
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL (a NULL/Unsorted-pending
  -- cat is allowed → Suspense downstream; only categorized rows are Trade-checked).

  -- Resolve the FROZEN FACT (immutable ledger, 004/017).
  select true, t.security_id, t.quantity
    into v_has_txn, v_security_id, v_quantity
    from pfin.account_trans t
   where t.trans_id = new.trans_id;

  -- Resolve the CLASS (mutable overlay taxonomy, 009). cat is NOT NULL (009); a
  -- cross-tenant sub_cat_id is already rejected by the #10 matched-tenant fence
  -- (fires on the same write), so under INVOKER this read sees the caller's own row.
  select true, ut.cat, ut.sub_cat
    into v_has_tax, v_cat, v_sub_cat
    from pfin.user_taxonomy ut
   where ut.id = new.sub_cat_id;

  -- NULL-SAFE FAIL-CLOSED: a missing/unreadable transaction OR taxonomy row → raise
  -- (never a silent skip that would let an unvalidated Trade row through).
  if v_has_txn is null or v_has_tax is null then
    raise exception
      'Trade constraint: cannot resolve fact (trans_id %) or class (sub_cat_id %) — fail-closed (M1-evt / SELF-293)',
      new.trans_id, new.sub_cat_id;
  end if;

  -- (a) CONSISTENCY: security_id present  ⟺  cat = 'Trade'. (Biconditional via XOR;
  -- both operands are non-null booleans — v_cat is NOT NULL.)
  if (v_security_id is not null) <> (v_cat = 'Trade') then
    raise exception
      'Trade consistency violation (ADR-031 Amendment 1 s2a): security_id % and cat=% must satisfy (security_id present <=> cat=''Trade'') (M1-evt / SELF-293)',
      v_security_id, v_cat;
  end if;

  -- (b) SIGN-ALIGNMENT (cat='Trade' only): BTO/BTC ⟹ quantity > 0; STC/STO ⟹ < 0.
  -- quantity is NOT NULL (004 default 0), so the comparisons are NULL-safe. A Trade
  -- sub_cat outside the four is consistency-checked (above) but not sign-checked.
  if v_cat = 'Trade' then
    if v_sub_cat in ('BTO', 'BTC') and not (v_quantity > 0) then
      raise exception
        'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat % requires quantity > 0 (buy), got % (M1-evt / SELF-293)',
        v_sub_cat, v_quantity;
    elsif v_sub_cat in ('STC', 'STO') and not (v_quantity < 0) then
      raise exception
        'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat % requires quantity < 0 (sell), got % (M1-evt / SELF-293)',
        v_sub_cat, v_quantity;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_trade_constraints() from public;

comment on function pfin.fn_account_trans_annotation_trade_constraints() is
  'Combined Trade-constraint fence on pfin.account_trans_annotation (Sec Condition A; '
  'ADR-031 Amendment 1 §2; M1-evt Slice A1 / SELF-293). BEFORE INSERT OR UPDATE WHEN '
  '(new.sub_cat_id IS NOT NULL). Resolves the FROZEN FACT (security_id, quantity) via '
  'trans_id → account_trans (004/017) + the CLASS (cat, sub_cat) via sub_cat_id → '
  'user_taxonomy (009), then enforces BOTH: (a) CONSISTENCY — security_id present <=> '
  'cat=''Trade'' (a securities row must be a Trade; a Trade must carry a security_id); '
  '(b) SIGN-ALIGNMENT — BTO/BTC ⟹ quantity>0 (buy), STC/STO ⟹ quantity<0 (sell). '
  'Cross-table (facts on the immutable ledger, class on the overlay) → a trigger, not '
  'a single-table CHECK. UPDATE path load-bearing: re-validates on every overlay edit '
  '(BTO→STO on a frozen-quantity row). NULL-safe fail-closed (missing fact/class → '
  'raise). SECURITY INVOKER + set search_path='''' — Decision-3-NEUTRAL (no cross-'
  'tenant dimension; #10 already fences a cross-tenant sub_cat); NOT a DEFINER '
  'allowlist entry (stays 3). The UI is not the integrity boundary — this trigger is '
  '(Amendment 1 §2b). A NULL sub_cat (Suspense-pending) is WHEN-skipped; a non-'
  'BTO/BTC/STC/STO Trade sub_cat is consistency-checked but not sign-checked.';

create trigger account_trans_annotation_trade_constraints
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.sub_cat_id is not null)
  execute function pfin.fn_account_trans_annotation_trade_constraints();
