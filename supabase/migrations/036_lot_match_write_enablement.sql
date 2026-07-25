-- ============================================================================
-- Migration: pfin.lot_match — WRITE-ENABLEMENT. Opens the fenced INSERT path on the
--   append-only lot_match junction: the INSERT grant + the wr_access WITH CHECK policy
--   (the RLS write companion to the already-realized 032 Decision-3 #14 fence).
--   M4-GL-write (Linear SELF-300) — the focused write-enablement half of the M4-GL
--   deferred-write counterpart; the GL-completion half lands at 037 (see below).
-- Phase 6 Build Loop — Double-Entry GL track. F/CTO-ratified 2026-07-24: basis method =
--   FIFO/specific-lot (locked one-way door); split-by-dependency (036 = write-enablement;
--   037 = GL-completion bundle); matching INFERENCE = Backend/worker, NOT DB scope.
--   Design memo temp/m4-gl-write-design.md. Source: ADR-031 Decision 7 M1-evt cond 4 /
--   Decision 8 (the lot-match FK #14) + the 032 CONTRACT deferring the INSERT grant/policy
--   to M4-GL.
--
-- Numbering: 036 follows 035 (fn_gl_entries). Depends on 032 (pfin.lot_match — the table,
--   the immutability triple-fence, the #14 matched-tenant/security BEFORE INSERT fence,
--   and the lot_match_select read policy — ALL landed at 032), 004/017 (account_trans —
--   the sell/buy trans the fence chain-resolves), 003 (account — the users_id the chain
--   resolves), 006 (account_users rd/wr_access-JOIN — the parent-chain the write policy
--   anchors on), 001 (pfin schema). No downstream migration depends on 036 landing first
--   (037 consumes lot_match at read; Backend populates it via this write path).
--
-- POSTURE RATIONALE — NO new function; NO new SECURITY DEFINER (allowlist UNCHANGED at 4
--   = 3 authored + 1 reserved). This migration is purely declarative: a table-level
--   INSERT GRANT + one RLS INSERT policy (wr_access WITH CHECK). No new SQL function is
--   authored — lot_match writes are DIRECT authenticated-INSERT under RLS (032 CONTRACT),
--   so no DEFINER capture is needed. The security composition on an INSERT is:
--     (1) ACL   — grant insert to authenticated (this migration);
--     (2) RLS   — lot_match_insert WITH CHECK: caller holds wr_access on the SELL leg's
--                 account (parent-chain, the write companion to 032's SELECT policy);
--     (3) TRIGGER — the 032 #14 fence fn_lot_match_matched_tenant_security (BEFORE INSERT,
--                 INVOKER) fires on EVERY insert: sell-tenant = buy-tenant (non-negotiable)
--                 AND sell.security_id = buy.security_id (correctness), NULL-safe fail-closed;
--     (4) IMMUTABILITY — 032's fn_lot_match_block_mutation/_block_truncate keep UPDATE/
--                 DELETE/TRUNCATE blocked all roles; a correction is a NEW match_seq batch.
--   Anchoring the RLS write on the SELL leg suffices (matches 032's SELECT-anchors-on-sell
--   reasoning): the #14 fence guarantees the buy leg shares the tenant, so the sell leg is
--   the sufficient authorization anchor.
--
-- ----------------------------------------------------------------------------
-- SEC N1 WORDING (exercisable ≠ newly-realized): the Decision-3 #14 fence
--   (fn_lot_match_matched_tenant_security) was ALREADY DDL-REALIZED at 032 and fires on
--   every INSERT today. 036 does NOT add, renumber, or re-realize #14 — it adds the INSERT
--   grant + wr_access WITH CHECK policy that make the #14-fenced write path EXERCISABLE.
--   The wr_access policy enforces the SAME sell-leg parent-chain ownership as the existing
--   lot_match_select read policy (belt-and-suspenders with the #14 trigger) → it is the RLS
--   WRITE companion to the already-counted #14 relationship, NOT a new numbered instance.
--   (032's file-header CONTRACT is left as-is per append-only migration discipline — the
--   034/017 precedent; the DB-level table comment is refreshed HERE via a new comment-on,
--   the append-only-correct way to update the wording.)
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — COUNT UNCHANGED. #14 (the lot_match
--   sell/buy matched-tenant + matched-security fence) is a SETTLED SINGLE instance, realized
--   at 032 and Sec-pinned (canonical ADR-011 Decision 3, folded at SELF-295 2026-07-24;
--   re-pinned at the 036 joint-review). 036 makes it exercisable, adds no FK-shaped column,
--   adds no new fence. The single #14 covers BOTH FK columns (sell_trans_id + buy_trans_id)
--   via ONE matched-tenant relationship — ONE instance, disposition confirmed. Family delta
--   from 036 = 0.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 036 introduces
--   ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: the INSERT grant + wr_access policy are AUTHENTICATED-TIER
--         (no service_role grant, no credential, no admission channel, no network-exposure/
--         config surface). No infrastructure-credential-presence (RT-22 = PDF-worker
--         container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26), no
--         admission surface (RT-27) is touched. Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 036 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the wr_access WITH CHECK policy is a Decision-3 write-companion /
--   RLS mechanism, NOT a §10 catalogued instance.
--
-- ----------------------------------------------------------------------------
-- 037-DEFERRAL LIST (M4-GL-write GL-completion bundle — mirrors the 035→036 deferral
--   pattern, now 036→037; authored at 037, joint-review-mandatory, lands once lot_match is
--   non-vacuously populatable by Backend matching):
--   (1) fn_gl_entries create-or-replace — security SELL realized-gain / position-basis-
--       removal reading lot_match (FIFO/specific-lot per-lot basis; recapture =
--       min(gain, accumulated_depreciation)); park-if-unmatched (an unmatched sell stays
--       in Suspense until its lot_match rows exist).
--   (2) fn_gl_entries — corp_action GL posting (currently Suspense-parked at 035).
--   (3) fn_gl_entries — basis_adjust wash_sale P&L (currently Suspense-parked at 035).
--   (4) Σ=0-at-close enforcement trigger on pfin.journal status→'closed' (033 M4-GL
--       CONTRACT) — INVOKER; invokes fn_gl_entries per group_type conservation law;
--       CO-LANDS with the completed engine (compound-with-sells correctness depends on (1)).
--   (5) closed_at / book-value close-snapshot column (033 B-ii, additive ALTER) —
--       snapshot deterministically at close, never re-valued (Decision 7 M2 cond 7).
--   NOT deferred to 037: the FIFO/specific-lot matching INFERENCE + selection UI — that is
--   Backend/worker territory (direct authenticated-INSERT through THIS migration's write
--   path), not DB DDL.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = unchanged (4: 3 authored — fn_refresh_updated_at @001, fn_grant_creator_
--   access @003, fn_reclass_history_insert @031 — + 1 reserved; no new function here) ·
--   Decision-3 family count = unchanged (#14 exercisable, not new; no new FK column).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   No new object types. This migration adds, to the existing 032 pfin.lot_match:
--     - GRANT INSERT ON pfin.lot_match TO authenticated (the ACL half of the write path;
--       anon/service_role remain ungranted).
--     - POLICY lot_match_insert (FOR INSERT TO authenticated WITH CHECK): the caller must
--       hold wr_access on the SELL leg's account, resolved via the parent chain
--       sell_trans_id → account_trans.account_id → account_users (au.users_id = auth.uid()
--       AND au.wr_access). The RLS write companion to the 032 #14 fence.
--     - refreshed comment on table pfin.lot_match (WRITE-DORMANT → WRITE-ENABLED wording;
--       Sec N1).
--   Security-load-bearing edges: the INSERT is gated by ACL (grant) + RLS (wr_access on the
--   sell leg) + the 032 #14 trigger (buy-leg tenant/security match, fail-closed) +
--   immutability (no UPDATE/DELETE/TRUNCATE). A cross-tenant caller cannot INSERT: the
--   WITH CHECK fails (no wr_access on a foreign sell leg) and the #14 fence independently
--   rejects a foreign buy leg — defence in depth. No DEFINER; no new §10 surface.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- (1) ACL — open the INSERT grant (ACL-before-RLS, PR #106). SELECT was granted at 032;
--     INSERT lands here. anon zero-grant / service_role ungranted are UNCHANGED (a write
--     is authenticated-tier only). UPDATE/DELETE/TRUNCATE remain ungranted + trigger-fenced.
-- ----------------------------------------------------------------------------
grant insert on pfin.lot_match to authenticated;

-- ----------------------------------------------------------------------------
-- (2) RLS write policy — wr_access WITH CHECK on the SELL-leg parent chain. The write
--     companion to 032's lot_match_select (which used rd_access); INSERT requires wr_access.
--     Anchoring on the sell leg suffices — the 032 #14 fence guarantees sell-tenant =
--     buy-tenant, so the buy leg needs no separate RLS anchor (its tenant/security match is
--     the trigger's job). NULL / cross-tenant sell → NOT EXISTS → WITH CHECK fails closed.
-- ----------------------------------------------------------------------------
drop policy if exists lot_match_insert on pfin.lot_match;
create policy lot_match_insert on pfin.lot_match
  for insert to authenticated
  with check (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = lot_match.sell_trans_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

comment on policy lot_match_insert on pfin.lot_match is
  'Parent-FK-chain INSERT policy (the wr_access WRITE companion to lot_match_select, 032): '
  'wr_access-JOIN via sell_trans_id → account_trans.account_id → account_users. A caller may '
  'insert a lot-match only for a sell on an account they hold wr_access on. The 032 #14 fence '
  '(fn_lot_match_matched_tenant_security, BEFORE INSERT) independently guarantees the buy leg '
  'shares the sell''s tenant AND security (fail-closed), so the sell leg is the sufficient RLS '
  'anchor — defence in depth, not redundancy. NOT a new Decision-3 instance (the RLS write '
  'realization of the already-realized #14 relationship; count unchanged — the settled single '
  '#14, disposition Sec-confirmed). '
  'M4-GL-write / SELF-300.';

-- ----------------------------------------------------------------------------
-- (3) Refreshed table comment — Sec N1 wording (WRITE-DORMANT → WRITE-ENABLED). 032's
--     file-header CONTRACT is untouched (append-only discipline); this new comment-on is the
--     append-only-correct way to update the DB-level wording.
-- ----------------------------------------------------------------------------
comment on table pfin.lot_match is
  'Append-only, immutable securities lot-matching junction (M1-evt Slice B / SELF-293; '
  'ADR-031 Decision 7 cond 4 / Decision 8). Many-to-many: a sell closes portions of '
  'one-or-more buy lots (partial lots), a buy closes across one-or-more sells — drives '
  'per-lot holding-period (ST/LT) + realized-gain character at M4-GL (FIFO/specific-lot, '
  'F/CTO-locked 2026-07-24). APPEND-ONLY immutable (004/031-mirror triple-fence): a re-match '
  'inserts a NEW match_seq batch, never an UPDATE; "current" match = max(match_seq) per '
  'sell_trans_id (derived, read by 037''s fn_gl_entries completion). This self-versioning IS '
  'the lot-match reclass-history (ADR-011 Decision 2). fn_reclass_history_insert is untouched, '
  'DEFINER allowlist stays 4 (lot_match writes are direct authenticated-INSERT, not a '
  'side-effect capture). WRITE-ENABLED at 036 (M4-GL-write / SELF-300): authenticated SELECT '
  '(owner-only parent-chain α via sell_trans_id) + INSERT (lot_match_insert wr_access WITH '
  'CHECK, the write companion to the #14 fence). The matching INFERENCE (FIFO/specific-lot) is '
  'Backend/worker, NOT DB. The #14 fence (fn_lot_match_matched_tenant_security) was DDL-REALIZED '
  'at 032 and fires on every INSERT; 036 makes it EXERCISABLE (adds the grant/policy) — it did '
  'not newly realize it (Sec N1). The settled single #14 covers both FKs — ONE instance, '
  'Sec-confirmed. anon '
  'zero-grant; service_role ungranted. §10 stays 3; DEFINER stays 4; Decision-3 count unchanged.';
