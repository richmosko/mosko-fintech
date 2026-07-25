-- ============================================================================
-- Migration: M3-basis — the basis_adjust ROW-SHAPE constraint. Two parts:
--   (1) a single-table CHECK on pfin.account_trans (the reason-independent ledger
--       shape: a basis_adjust row carries quantity=0, a security_id, and a cost_basis);
--   (2) a cross-table SECURITY INVOKER trigger on pfin.account_trans_annotation (the
--       reason-domain + reason↔amount consistency on the mutable overlay).
-- Phase 6 Build Loop — M3-basis of the Double-Entry GL track (Linear SELF-296).
--   F/CTO-ratified 2026-07-25 (A-i reason-on-overlay · B-i coupled shape · C · D).
--   Design paper temp/self-296-m3-basis-design.md. Built to ADR-031 Decision 4
--   (Theme D basis_adjust) + Amendment 1 items 5/6/8 (the RATIFIED shape — NOT the
--   design-v2 sketch; see AMENDMENT-1 RECONCILIATION below).
--
-- WHAT THIS DOES:
--   (1) CHECK account_trans_basis_adjust_shape on pfin.account_trans:
--         transaction_type <> 'basis_adjust'
--         OR (quantity = 0 AND security_id IS NOT NULL AND cost_basis IS NOT NULL)
--       The reason-INDEPENDENT ledger shape of a basis_adjust event (a dated book
--       adjustment on one security, moving no shares, carrying a cost_basis delta).
--       Role-agnostic (a table CHECK — service_role bypasses RLS, not CHECKs), so it
--       fires under the 017 service_role ingest path too.
--   (2) fn_account_trans_annotation_basis_adjust_reason() — a BEFORE INSERT OR UPDATE
--       trigger on account_trans_annotation (a structural clone of 030's Trade-
--       constraint trigger): when the annotated txn is basis_adjust and a reason is
--       present on the overlay, enforce the reason-domain + reason↔amount consistency.
--
-- WHAT THIS IS NOT: this migration ADDS NO column, NO FK, NO vocabulary value. The
--   `basis_adjust` transaction_type value AND the `metadata` jsonb column were BOTH
--   already landed at 030 (M1-evt Slice A1) — 034 adds only the row-SHAPE constraint
--   over the existing columns. NO new function with elevated privilege. NO RLS/GRANT
--   change (the overlay trigger inherits 023's existing posture; the CHECK touches no
--   grant). The basis roll-forward / accumulated-depreciation / recapture COMPUTE at
--   M4-GL (deferred — see M4-GL CONTRACT below), like M2 (033) deferred Σ=0.
--
-- ----------------------------------------------------------------------------
-- AMENDMENT-1 RECONCILIATION (design to the RATIFIED shape, NOT the design-v2 sketch):
--   The design-v2 Theme-D sketch showed `reason text CHECK(... corporate_action)` as a
--   column ON account_trans with 4 values. ADR-031 Amendment 1 SUPERSEDED that:
--     - item 8: `reason text` column → `metadata.reason` jsonb, and `metadata` lives on
--       the MUTABLE 023 overlay (landed at 030). So reason is INTERPRETATION (A-i
--       ratified): the PRIMARY facts (cost_basis delta + amount) are already immutable
--       on the ledger and fully determine the economics; reason is the interpretive
--       LABEL, anchored to those frozen facts by trigger (2). Audit trail for reason
--       edits = the 031 reclassification-history.
--     - items 5/6: `corporate_action` promoted OUT to the `corp_action` event type →
--       the reason set is {depreciation, return_of_capital, wash_sale} — 3 VALUES, not 4.
--
-- Numbering: 034 follows 033 (M2 journal). Depends on 004 (account_trans — the CHECK
--   target + the immutable-ledger facts trigger (2) reads: transaction_type/amount/
--   quantity/security_id/cost_basis), 017 (the quantity/security_id/cost_basis columns
--   + their NaN/qty CHECKs this shape composes with), 023 (account_trans_annotation —
--   the trigger host), 030 (the basis_adjust vocab value + the metadata jsonb column
--   this constrains; the Trade-constraint trigger cloned here), and 001 (pfin schema).
--   No downstream migration depends on 034 landing first (M4-GL consumes it at read).
--
-- ----------------------------------------------------------------------------
-- 017-COMPAT NOTE (the natural reviewer worry — pre-empted): 017's
--   `account_trans_qty_requires_security` CHECK is ONE-DIRECTIONAL —
--   `quantity = 0 OR security_id IS NOT NULL`. A basis_adjust row (quantity=0 WITH a
--   security_id present) SATISFIES it cleanly via the `quantity = 0` disjunct — no
--   collision, nothing to relax. And 017's ONLY cost_basis constraint is the NaN-fence
--   (`account_trans_cost_basis_finite`, `cost_basis <> 'NaN'`) — there is NO `>= 0`
--   CHECK, so a NEGATIVE basis_adjust delta (depreciation reduces basis) is already
--   permitted. Both verified against 017 verbatim.
--
-- ----------------------------------------------------------------------------
-- cost_basis DUAL-MEANING (the role-widening, Decision C — semantic, no DDL conflict):
--   cost_basis is now transaction_type-dependent — on a `standard` trade it is the
--   ACQUISITION cost (017's original meaning); on a `basis_adjust` row it is the SIGNED
--   DELTA to basis (can be negative — depreciation). Same column, two readings keyed on
--   transaction_type. 017's comment is not edited (append-only migration discipline);
--   the dual-meaning is documented here + carried in M4-GL's roll-forward. The NAV path
--   (019 fn_compute_nav / fn_holdings_as_of) values on eod_price, NOT cost_basis, so NAV
--   is UNAFFECTED; the book-value GL (M4-GL) is the new cost_basis consumer.
--
-- ----------------------------------------------------------------------------
-- M4-GL CONTRACT (the DEFERRED computations — Decision D; documented here, authored at
--   M4-GL, read-only): effective_cost_basis(security) = original acquisition cost +
--   Σ(basis_adjust.cost_basis deltas); accumulated_depreciation = derived (filter
--   metadata.reason='depreciation', sum the deltas — no separate column); recapture =
--   min(gain, accumulated_depreciation); at sale gain/loss = proceeds −
--   effective_cost_basis → Equity/Retained Earnings. Contra imputation by reason:
--   depreciation → Dr Depreciation-Expense / Cr book-value reduction; return_of_capital
--   → cash leg + basis reduction, no income contra. 034 only guarantees basis_adjust
--   rows are well-shaped for that read; the roll-forward/recapture QA lands with M4-GL.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) ZERO catalogued
--   §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence (RT-22), no code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26), no network-exposure/config
--         admission (RT-27) surface is touched — a table CHECK + an authenticated-tier
--         INVOKER value-fence; no service_role grant, no credential, no admission channel.
--         Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 034 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: both constraints are value/consistency mechanisms, NOT §10
--   catalogued instances and NOT Decision-3 instances (no cross-tenant dimension).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +0 (UNCHANGED, 14 labeled
--   / 12 DDL-realized). This migration adds NO FK-shaped reference column:
--     - the CHECK is a value-domain constraint on existing columns (no reference).
--     - the trigger reads transaction_type/amount (004) + metadata.reason (023) — no new
--       reference column, no cross-tenant dimension. security_id is already fenced by the
--       #7 global-OR-matched-tenant fence (017); the cross-tenant sub_cat_id (if the same
--       annotation row carries one) is already fenced by #10 (023). VALUE/TENANCY-NEUTRAL.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default); NO new SECURITY DEFINER. The
--   allowlist STAYS 4 (ADR-011 Decision 9 + Amendment 2026-07-24: fn_refresh_updated_at +
--   fn_grant_creator_access + fn_reclass_history_insert + the reserved audit-log helper).
--   ONE function is authored:
--     - fn_account_trans_annotation_basis_adjust_reason — SECURITY INVOKER, set
--       search_path=''. Reads the frozen fact (account_trans.transaction_type/amount) +
--       the overlay metadata under the caller's RLS; no elevation → INVOKER → not an
--       allowlist entry. (The CHECK is not a function.) ZERO new SECURITY DEFINER in 034.
--   004-IMMUTABILITY NOTE: the CHECK is an INSERT-time validation on account_trans; it
--   does NOT touch the 004 UPDATE/DELETE/TRUNCATE triple-fence (adding a CHECK is DDL,
--   which does not fire the row-DML block-mutation trigger; the table is empty/greenfield).
--   004 immutability is UNWEAKENED — Sec confirms at joint-review.
--
-- ----------------------------------------------------------------------------
-- ADDITIVE GUARD R3 (flagged for Sec/F-CTO — reason is a basis_adjust-ONLY concept):
--   trigger (2) also rejects a `metadata.reason` present on a NON-basis_adjust row
--   (a stray depreciation/RoC/wash_sale label on a standard/corp_action txn is
--   nonsensical and would confuse M4-GL). This is the one-directional analog of 030's
--   Trade biconditional (reason present ⟹ transaction_type='basis_adjust'; NOT the
--   reverse — a basis_adjust may carry NO reason yet, a pending/Suspense state). It is
--   slightly BEYOND the literal B-i brief (which named only the domain + amount checks);
--   included as the natural completeness guard. It keys on the `reason` jsonb key
--   specifically, so it does NOT touch corp_action `metadata.action` rows. Sec/F-CTO may
--   drop R3 for a minimal scope — it is isolated to one IF branch.
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS: the basis_adjust row-shape convention (quantity=0 / security present /
--   cost_basis=signed delta / amount=0-except-RoC / reason∈{3}) imprints on the incumbent
--   import backfill (settle-before-import, ADR-031 D9 — 030 confirmed the import HAS
--   basis_adjust events). Reversible while greenfield/empty; bakes in once basis data
--   lands. The reason-on-overlay posture (A-i) is the ratified Amendment 1 item 8 shape.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   CHECK account_trans_basis_adjust_shape on pfin.account_trans — a basis_adjust row
--     carries quantity=0 AND security_id IS NOT NULL AND cost_basis IS NOT NULL;
--     non-basis_adjust rows unconstrained. Role-agnostic; INSERT-time; 004-immutability
--     untouched. (amount is NOT constrained here — the amount=0-except-RoC rule couples to
--     the mutable reason and lives in trigger (2).)
--   pfin.fn_account_trans_annotation_basis_adjust_reason() — BEFORE INSERT OR UPDATE on
--     account_trans_annotation WHEN (new.metadata IS NOT NULL); SECURITY INVOKER; set
--     search_path=''; NULL-safe fail-closed. Resolves transaction_type + amount via
--     new.trans_id → account_trans, reads v_reason = new.metadata->>'reason', and enforces:
--       R1 (domain): basis_adjust AND reason present ⟹ reason ∈ {depreciation,
--           return_of_capital, wash_sale}.
--       R2 (reason↔amount): basis_adjust AND reason present ⟹ (reason='return_of_capital'
--           ⟺ amount <> 0). RoC carries cash; depreciation/wash_sale move no cash. The
--           FROZEN amount (004) anchors the mutable reason — you cannot relabel a no-cash
--           event as RoC (amount frozen at 0), nor a cash event as depreciation.
--       R3 (basis_adjust-only, additive guard): reason present ⟹ transaction_type=
--           'basis_adjust'.
--     UPDATE path load-bearing: editing metadata.reason re-validates against the frozen
--     amount on every overlay edit (mirrors 030's BTO→STO re-validation).
--   Security-load-bearing edges: NULL-safe fail-closed (a missing/unreadable txn → raise,
--     never a silent skip); INVOKER composes with RLS; the immutable ledger fact
--     (transaction_type/amount) is the integrity anchor for the mutable reason; the CHECK
--     is role-agnostic (fires under service_role ingest). NO cross-tenant dimension
--     (Decision-3-neutral); NO new DEFINER (allowlist stays 4).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) Single-table CHECK — the reason-INDEPENDENT basis_adjust ledger shape. Role-
-- agnostic (fires under the 017 service_role ingest path too). Adding a CHECK is DDL —
-- the 004 block-mutation trigger fires on row UPDATE/DELETE, not ALTER TABLE — and the
-- table is empty/greenfield, so 004 immutability is untouched. Idempotent add
-- (pg_constraint guard — PG has no ADD CONSTRAINT IF NOT EXISTS; 017 pattern).
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint
    where conname = 'account_trans_basis_adjust_shape'
      and conrelid = 'pfin.account_trans'::regclass) then
    alter table pfin.account_trans
      add constraint account_trans_basis_adjust_shape
      check (
        transaction_type <> 'basis_adjust'
        or (quantity = 0 and security_id is not null and cost_basis is not null)
      );
  end if;
end $$;

comment on constraint account_trans_basis_adjust_shape on pfin.account_trans is
  'basis_adjust ROW-SHAPE (reason-independent; M3-basis / SELF-296; ADR-031 Decision 4 / '
  'Amendment 1 §6). A transaction_type=''basis_adjust'' row is a dated BOOK adjustment on '
  'one security moving no shares: quantity=0 (no share movement) AND security_id IS NOT '
  'NULL (the adjusted asset) AND cost_basis IS NOT NULL (the SIGNED delta — can be '
  'NEGATIVE for depreciation; 017 has no >=0 CHECK). Non-basis_adjust rows unconstrained. '
  'Composes cleanly with 017''s one-directional account_trans_qty_requires_security '
  '(quantity=0 satisfies it) + the cost_basis NaN-fence. Role-agnostic table CHECK '
  '(service_role bypasses RLS, not CHECKs) — fires under the 017 ingest path. INSERT-time; '
  'the 004 UPDATE/DELETE/TRUNCATE triple-fence is untouched. NOTE: the amount=0-except-'
  'return_of_capital rule couples to the mutable metadata.reason and lives in the overlay '
  'trigger (fn_account_trans_annotation_basis_adjust_reason), NOT here.';

-- ----------------------------------------------------------------------------
-- (2) Cross-table INVOKER trigger — the reason-domain + reason↔amount consistency on the
-- mutable 023 overlay (a structural clone of 030's fn_account_trans_annotation_trade_
-- constraints). Facts (transaction_type/amount) on the immutable ledger (004), reason on
-- the overlay (023 metadata) — a single-table CHECK cannot span them, so a trigger.
-- SECURITY INVOKER + set search_path=''. NULL-safe fail-closed. Decision-3-neutral.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_annotation_basis_adjust_reason()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_has_txn   boolean;
  v_txn_type  text;
  v_amount    numeric;
  v_reason    text;
begin
  -- Trigger WHEN clause guarantees new.metadata IS NOT NULL.
  v_reason := new.metadata ->> 'reason';

  -- Resolve the FROZEN FACT (immutable ledger, 004). NULL-safe fail-closed below.
  select true, t.transaction_type, t.amount
    into v_has_txn, v_txn_type, v_amount
    from pfin.account_trans t
   where t.trans_id = new.trans_id;

  if v_has_txn is null then
    raise exception
      'basis_adjust reason: cannot resolve fact (trans_id %) — fail-closed (M3-basis / SELF-296)',
      new.trans_id;
  end if;

  -- R3 (additive guard): a `reason` present on a NON-basis_adjust row is misplaced
  -- (reason is a basis_adjust-only concept). One-directional (a basis_adjust may carry
  -- NO reason yet — pending/Suspense). Keys on the `reason` jsonb key only (does not
  -- touch corp_action metadata.action).
  if v_reason is not null and v_txn_type <> 'basis_adjust' then
    raise exception
      'misplaced reason: metadata.reason=% is only valid on a basis_adjust row, not transaction_type=% (M3-basis / SELF-296)',
      v_reason, v_txn_type;
  end if;

  -- R1 + R2 apply only to a basis_adjust row that carries a reason.
  if v_txn_type = 'basis_adjust' and v_reason is not null then
    -- R1 (domain): reason ∈ {depreciation, return_of_capital, wash_sale} (Amendment 1 §6;
    -- corporate_action is the corp_action event type, §5 — NOT a reason).
    if v_reason not in ('depreciation', 'return_of_capital', 'wash_sale') then
      raise exception
        'basis_adjust reason % not in {depreciation, return_of_capital, wash_sale} (ADR-031 Amendment 1 s6; M3-basis / SELF-296)',
        v_reason;
    end if;

    -- R2 (reason↔amount consistency): return_of_capital carries cash (amount <> 0);
    -- depreciation/wash_sale move no cash (amount = 0). amount is NOT NULL (004) so the
    -- comparison is NULL-safe. The FROZEN amount anchors the mutable reason.
    if (v_reason = 'return_of_capital') <> (v_amount <> 0) then
      raise exception
        'basis_adjust reason↔amount mismatch: reason=% requires %, got amount=% (return_of_capital ⟺ amount<>0; M3-basis / SELF-296)',
        v_reason,
        case when v_reason = 'return_of_capital' then 'amount<>0 (cash returned)'
             else 'amount=0 (no cash)' end,
        v_amount;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_basis_adjust_reason() from public;

comment on function pfin.fn_account_trans_annotation_basis_adjust_reason() is
  'basis_adjust reason fence on pfin.account_trans_annotation (M3-basis / SELF-296; '
  'ADR-031 Decision 4 / Amendment 1 §5/§6/§8; structural clone of 030''s Trade-constraint '
  'trigger). BEFORE INSERT OR UPDATE WHEN (new.metadata IS NOT NULL). Resolves the FROZEN '
  'FACT (transaction_type, amount) via trans_id → account_trans (004), reads reason = '
  'metadata->>''reason'', and enforces: R1 domain (basis_adjust+reason ⟹ reason ∈ '
  '{depreciation, return_of_capital, wash_sale}); R2 reason↔amount (basis_adjust+reason ⟹ '
  'return_of_capital ⟺ amount<>0 — RoC carries cash, depreciation/wash_sale move none; the '
  'frozen amount anchors the mutable reason); R3 additive guard (reason present ⟹ '
  'transaction_type=basis_adjust — a stray reason on a non-basis_adjust row is rejected; '
  'one-directional, a basis_adjust may carry no reason yet). Cross-table (fact on the '
  'immutable ledger, reason on the overlay) → a trigger, not a single-table CHECK. UPDATE '
  'path load-bearing: re-validates on every overlay edit (mirrors 030 BTO→STO). NULL-safe '
  'fail-closed (missing/unreadable txn → raise). SECURITY INVOKER + set search_path='''' — '
  'Decision-3-NEUTRAL (no cross-tenant dimension); NOT a DEFINER allowlist entry (stays 4). '
  'reason is INTERPRETATION on the mutable overlay (A-i / Amendment 1 item 8) — its edit '
  'audit trail is the 031 reclass-history. R3 is an additive completeness guard (Sec/F-CTO '
  'may drop for minimal scope).';

create trigger account_trans_annotation_basis_adjust_reason
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.metadata is not null)
  execute function pfin.fn_account_trans_annotation_basis_adjust_reason();
