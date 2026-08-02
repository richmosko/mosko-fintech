-- ============================================================================
-- Migration: §2.1.6 investment MV-vs-cost-basis AUDIT-TRACE comments (SELF-227 AC#3).
--   COMMENT-ONLY. Re-issues `comment on function` for the four NAV-path read helpers to
--   append a PRD §2.1.6 + SELF-227 audit-trace citation recording, at the MV-aggregation
--   point, the §2.1.6 invariant: investment-account contributions to NAV use CURRENT MARKET
--   VALUE (eod_price × qty × fx), NEVER cost basis; cost basis is confined to 049's
--   cost_basis / unrealized_gl columns (+ future §2.2.x cost-basis-display surfaces).
--   Linear SELF-227 (V1.1 "Net worth full"; §2.1.6 investment MV-vs-cost-basis audit).
--   F/CTO-ratified 2026-08-02 (author this comment-only migration).
--
-- ----------------------------------------------------------------------------
-- WHY (the audit — already CLEAN; this migration lands the trace, not a fix): Backend
--   audited the NAV primitives and confirmed they ALREADY correctly use current market value
--   (eod_price × qty × fx) — never cost basis — for investment-account NAV contributions.
--   Cost basis is confined to account_trans.cost_basis → fn_gl_entries (035/037) → 049's
--   cost_basis / unrealized_gl columns ONLY. This migration changes NO logic — it is the
--   §2.1.6 AC#3 audit-trace citation, appended to each function's existing comment so the
--   MV-vs-cost-basis invariant is documented AT the aggregation point (obj_description).
--
-- ----------------------------------------------------------------------------
-- SHAPE — COMMENT-ONLY (zero DDL / zero body / zero signature / zero logic change):
--   Four `comment on function` statements ONLY. Each PRESERVES its function's existing
--   comment VERBATIM (the CONTRACT / POSTURE / DESIGN content) and APPENDS the §2.1.6 /
--   SELF-227 audit-trace citation (`comment on function` REPLACES, so the full prior text is
--   reproduced + the new trailing sentence). The literal string `SELF-227` appears in all
--   four comments (QA machine-asserts obj_description(...) like '%SELF-227%').
--     (1) pfin.fn_compute_nav(date, boolean)  — 2-arg impl  (050)
--     (2) pfin.fn_compute_nav(date)           — 1-arg wrapper (050)
--     (3) pfin.fn_account_unrealized_gl(date) — 049
--     (4) pfin.fn_nav_composition(date)       — 051
--   No `create`/`alter`/`drop` of any function; no grant/revoke change; no search_path change.
--   `set search_path = ''` is N/A for comment statements (kept out); house-style schema-guard
--   below is idempotent and touches nothing.
--
-- ----------------------------------------------------------------------------
-- Numbering: 052 follows 051. Comment-only over already-landed 049 / 050 / 051 functions —
--   order-independent; depends only on those three migrations having created the functions.
--   No downstream migration depends on 052.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO posture change. All four functions are SECURITY INVOKER (Lock 11
--   read-composition), UNCHANGED. This migration issues no `create or replace`, so it neither
--   adds nor alters any SECURITY DEFINER function. → DEFINER allowlist UNCHANGED at 4
--   (authored 3: fn_refresh_updated_at @001 + fn_grant_creator_access @003 +
--   fn_reclass_history_insert @031 + 1 reserved).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 052 introduces
--   ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: comment-only over authenticated-tier INVOKER READ functions — no
--         service_role grant, no credential, no admission/network-exposure/config surface.
--         RT-22 (PDF-worker container), RT-26 (SUPABASE_SERVICE_ROLE_KEY grep fence), RT-27
--         (app→worker admission network-exposure/config layer) untouched. Nothing four-layer.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 052 is not the anchor.
--   DE-CONFLATION GUARD: comment-only — adds NO FK-shaped reference column → Decision-3 family
--   UNCHANGED, no new instance.
--
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = 4 (unchanged; all four commented fns are INVOKER, no create/replace) ·
--   Decision-3 family = unchanged (15 labeled / 12 DDL-realized; no new FK-shaped column) ·
--   RT-26 allowlist = 4 (unchanged).
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW routing: this is a comment-only audit-trace over FINANCIAL-CALCULATION
--   functions — Sec joint-review follows (AC#3 lands the MV-vs-cost-basis invariant that Sec
--   verified in the audit). QA authors the pgTAP obj_description assertion in parallel
--   (disjoint file). No logic surface to verify — the invariant is documentary.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) fn_compute_nav(date, boolean) — 2-arg impl (050). Existing comment PRESERVED verbatim;
--     §2.1.6 / SELF-227 audit-trace APPENDED.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_compute_nav(date, boolean) is
  'SECURITY INVOKER uniform roll-forward net-worth read (ADR-027 §5 / Lock 11; SELF-322 / '
  'ADR-039). 019''s valuation VERBATIM + is_active scoping GATED on p_active_only. '
  'p_active_only=FALSE → byte-identical to 019 (ALL accounts — the book/as-of engine: 037 GL '
  'memo + historical trend). p_active_only=TRUE → CURRENT-STATE (active accounts only; the '
  '§2.1.1 headline via netWorth.ts) — SOUND ONLY at p_as_of=current_date (is_active is '
  'current-state, not temporal; filtering it into a past as_of rewrites history — see 050 '
  'TEMPORAL CONSTRAINT; §2.1.2 trajectory/nav_daily must use frozen precomputed checkpoints). '
  'securities leg filters via LEFT JOIN pfin.account on holdings.account_id; cash leg via '
  'pfin.account — both gate on is_active ONLY when p_active_only. Makes the ADR-038 foot-to-NAV '
  'invariant EXACT: Σ 049.current_market_value(active) = fn_compute_nav(as_of, true). INVOKER '
  '(cross-tenant → 0, fails closed); unpriced asset → NULL → dropped → 0, never NaN. set '
  'search_path=''''; NOT a DEFINER allowlist entry (stays 4); §10 ledger 3; Decision-3 unchanged. '
  'EXECUTE revoked from PUBLIC, granted to authenticated.'
  ' §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic '
  'change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × '
  'fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future '
  '§2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';

-- ----------------------------------------------------------------------------
-- (2) fn_compute_nav(date) — 1-arg wrapper (050). Existing comment PRESERVED verbatim;
--     §2.1.6 / SELF-227 audit-trace APPENDED.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_compute_nav(date) is
  'SECURITY INVOKER 1-arg wrapper (SELF-322 / ADR-039) — delegates to fn_compute_nav(p_as_of, '
  'false) = ALL accounts (the 019 semantic, unchanged). Signature-identical to 019 (CREATE OR '
  'REPLACE in place, NO DROP) so 037 fn_gl_entries'' Unrealized memo — a book-domain '
  'reconciliation that legitimately images all accounts — is UNTOUCHED. Callers needing '
  'current-state (active-only) net worth call the 2-arg with p_active_only => true (the §2.1.1 '
  'headline). set search_path=''''; INVOKER; DEFINER allowlist stays 4; §10 ledger 3; '
  'Decision-3 unchanged. EXECUTE revoked from PUBLIC, granted to authenticated.'
  ' §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic '
  'change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × '
  'fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future '
  '§2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';

-- ----------------------------------------------------------------------------
-- (3) fn_account_unrealized_gl(date) — 049. Existing comment PRESERVED verbatim;
--     §2.1.6 / SELF-227 audit-trace APPENDED.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_account_unrealized_gl(date) is
  'SECURITY INVOKER per-account unrealized-G/L aggregation primitive (V1.1 "Net worth full"; '
  'PRD §2.1.5.a / SELF-224; shared with §2.2 asset-allocation V1.2; Lock 11 read-composition — '
  'clones the fn_compute_nav / fn_gl_entries posture). One row per non-inactive account visible '
  'to the caller. DESIGN C (account-total, symmetric; ADR-038, F/CTO 2026-08-02). '
  'current_market_value (ALL types, uniform) = securities MV [Σ(fn_holdings_as_of qty × '
  'best-available eod_price[D-first LOCF] × fx→USD)] + cash [roll-forward balance × fx→USD] = '
  'the account''s fn_compute_nav contribution → Σ over ACTIVE accounts = fn_compute_nav OVER '
  'ACTIVE ACCOUNTS ONLY (049 filters is_active per PRD §2.4.2; fn_compute_nav/019 does not — '
  'they diverge only on a value-bearing inactive account; that 019 scope gap is tracked as '
  'SELF-322, 049''s is_active filter is correct). (securities & cash '
  'disjoint per the 017 CHECK — counted once). INVESTMENT-class (account_type ∈ investment/'
  'retirement/crypto, 003 CHECK): cost_basis = securities carried book [Σ(fn_gl_entries '
  '`trade_position` × fx→USD) — acquisition + basis_adjust − FIFO/specific-lot matched-sell '
  'removal; single basis truth == GL == tax == reports; unmatched sells leave basis on the '
  'books per 037 Suspense floor] + the SAME roll-forward cash term as mv (the shared cash '
  'figure → cancels; NOT fn_gl_entries asset_liability, a pure-ledger Σ that diverges when a '
  'checkpoint exists). REDEFINITION: cost_basis is the ACCOUNT-TOTAL BOOK (securities book + '
  'cash face), not AC#2-literal securities-only. unrealized_gl = current_market_value − '
  'cost_basis = securities MV − securities book (pure securities G/L; cash cancels exactly). '
  'NON-INVESTMENT (depository/manual_other/real_estate/liability): cost_basis = unrealized_gl = '
  'NULL (NOT 0 — concept-does-not-apply discriminator; a zero-everything investment account '
  'returns 0/0/0). AS-OF (Lock 15 Decision 19; server-derived-only per Lock 15 mod #2, V1.1 '
  'consumers pass CURRENT_DATE): the composed fns thread p_as_of → historical eod_price + '
  'account_trans / lot_match ≤ as_of. INVOKER → cross-tenant caller sees no rows (fails closed); '
  'unpriced asset → NULL term → dropped → 0, never NaN. Per-lot decomposition is an additive '
  'future helper (buy side already per-lot; removal detail preserved in immutable lot_match), '
  'reconcilable by construction — the GL-derived basis path does not foreclose lot-level UI (V2). '
  'set search_path=''''; NOT a DEFINER allowlist entry (INVOKER) — allowlist stays 4; §10 ledger '
  'stays 3; Decision-3 unchanged (no new FK column). Sec joint-review-mandatory (financial calc + '
  'multi-tenant); RLS verification → SELF-228 two-tenant battery.'
  ' §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic '
  'change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × '
  'fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (this function''s '
  'own investment-class output columns) + future §2.2.x cost-basis-display surfaces. '
  'PRD §2.1.6 / SELF-227.';

-- ----------------------------------------------------------------------------
-- (4) fn_nav_composition(date) — 051. Existing comment PRESERVED verbatim;
--     §2.1.6 / SELF-227 audit-trace APPENDED.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_nav_composition(date) is
  'SECURITY INVOKER §2.1.5 NAV-composition aggregation (V1.1 "Net worth full"; PRD §2.1.5 / '
  'SELF-225; Lock 11 read-composition). Returns the composition tree as JSONB: '
  '{groups:[{category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}], '
  'subtotal}], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, '
  'nav}. COMPOSES ON 049 fn_account_unrealized_gl (single leaf substrate — per active account '
  'current_market_value + unrealized_gl, naturally signed) joined to pfin.account for name + '
  'account_type; 049 already filters is_active (AC#6: the real column is is_active, not the AC-prose '
  '"inactive"). groups[] in canonical category order (depository/investment/retirement/crypto/'
  'manual_other → real_estate → liability; §2.1.5/AC#2), empty categories omitted; accounts[] by '
  'account_id; leaf unrealized_gl NULL for non-investment (049, AC#3). DEBT SIGN (D-1): liability '
  'leaves + subtotal carry 049''s natural negative sign; buildups.debt = −(liability subtotal) = '
  'positive magnitude so AC#4 nav = gross_total − debt reads literally. TAX PLACEHOLDERS = Option A '
  'V1.1 (AC#5): realized/unrealized_tax_liab = 0::numeric, V1.4 ramp. FOOT-TO-NAV EXACT (ADR-038/'
  '039): nav = total_non_re + real_estate + Σ liability_signed = Σ 049(active) = '
  'fn_compute_nav(p_as_of, true) BY CONSTRUCTION (single-substrate natural summation; no separate '
  'fn_compute_nav call). p_scope DROPPED (pfin.scope type does not exist; scope is a free-text '
  'ADR-004 label — per-scope reporting is V2+, PRD §2.1.7); p_users_id DROPPED (INVOKER + RLS scope '
  'by auth.uid()). AS-OF via 049 threading (Lock 15; V1.1 consumers pass CURRENT_DATE). INVOKER → '
  'cross-tenant caller sees no rows → empty groups / nav 0 (fails closed). set search_path=''''; NOT '
  'a DEFINER allowlist entry (stays 4); §10 ledger stays 3; Decision-3 unchanged (no new FK column). '
  'Sec joint-review-mandatory (financial calc + multi-tenant); RLS verification → SELF-225 '
  'two-tenant battery.'
  ' §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic '
  'change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × '
  'fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future '
  '§2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';
