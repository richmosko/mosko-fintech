-- ============================================================================
-- Migration: DROP the account-level asset Sub-Category surface (SELF-319).
-- Phase 6 Build Loop. Physically removes the `pfin.account.sub_cat_id` feature
-- now that its full UI + app surface is gone (v1.132, merged to main `8292123`;
-- the manual-account create path passes `p_sub_cat_id: null` and NO surface reads
-- account.sub_cat_id). This migration retires DEAD schema, not live behavior.
--
-- What this migration DROPS (all landed at 012 / 013):
--   (1) trigger  pfin.account.account_matched_sub_cat            (012)
--   (2) function pfin.fn_account_matched_sub_cat()               (012) — the
--       Decision-3 CANONICAL instance #5 matched-tenant fence.
--   (3) column   pfin.account.sub_cat_id → pfin.user_taxonomy(id) (012)
--   (4) param    p_sub_cat_id on pfin.fn_create_manual_account   (013) — a
--       SIGNATURE change (7-arg → 6-arg), so DROP FUNCTION + recreate (CREATE OR
--       REPLACE cannot remove a parameter). Behavior otherwise IDENTICAL.
--
-- What this migration DELIBERATELY does NOT touch (de-conflation guard):
--   - pfin.account_trans.transaction_type (012 AcctSetup discriminator) — KEPT;
--     the recreated fn_create_manual_account still writes transaction_type='acct_setup'.
--   - pfin.account_trans_annotation.sub_cat_id (023) + its history snapshot (031)
--     + pfin.account_trans_split.sub_cat_id (029) + pfin.fn_create_manual_trans's
--     OWN p_sub_cat_id param (038) — these are the TRANSACTION-level cashflow-class
--     routing (Decision-3 #10 / #13), a LIVE feature. A DIFFERENT `sub_cat_id`.
--     This migration is scoped to the ACCOUNT-level asset Sub-Cat ONLY.
--
-- Numbering: 048 follows 047 (sync_audit manual source). No downstream migration
-- depends on 048. Prerequisites 012 + 013 are on main.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — this is a NET-NEGATIVE / privilege-neutral drop.
--   - fn_account_matched_sub_cat was SECURITY INVOKER (never a DEFINER allowlist
--     entry) — its removal does NOT touch the 4-entry SECURITY DEFINER allowlist
--     (3 authored: fn_refresh_updated_at @001 + fn_grant_creator_access @003 +
--     fn_reclass_history_insert @031; the general audit-log helper still reserved/
--     unauthored per ADR-011 Decision 9). Allowlist stays 4.
--   - fn_create_manual_account is + stays SECURITY INVOKER; it is recreated INVOKER
--     with 6 args, `set search_path = ''`, EXECUTE revoked-from-PUBLIC + granted-to-
--     authenticated only. No elevation added; allowlist stays 4.
--   - Removing a matched-tenant fence REDUCES attack surface (one fewer trigger to
--     reason about); it does not open one — the column it guarded is gone. The write
--     paths that remain (account INSERT/UPDATE) are unchanged and RLS-fenced (003).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — INSTANCE #5 DROPPED at 048.
--   #5 (`account.sub_cat_id → user_taxonomy(id)`, realized at 012 as
--   fn_account_matched_sub_cat) is REMOVED here. Per the family ledger discipline
--   (ADR-011 Decision 3): labels are STABLE and NEVER renumbered/reused — so #5
--   stays the label #5 in the canonical enumeration, transitioning to a THIRD
--   status class: DROPPED (built-then-removed), distinct from DDL-realized and from
--   DDL-deferred (#3 + #4, never built). No other label moves; #6–#15 unchanged.
--   COUNT MOVE: 15 labeled (#1–#15) / 13 DDL-realized  →  15 labeled (#1–#15) /
--   12 DDL-realized. This is the FIRST-EVER drop of a realized instance in the
--   family — a precedent-setting ledger event → F/CTO-RATIFY + Sec-JOINT-REVIEW
--   MANDATORY. See ADR-011 D3 "Enumeration DROP resolution (SELF-319 / 048)" +
--   supabase/CLAUDE.md 3(b). Sec pins the #5-DROPPED numbering at joint-review.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
-- catalogued numbered list; Decision 4 read verbatim before drafting). This drop
-- introduces + removes ZERO catalogued §10 instances; the ledger stays at 3
-- (RT-22 + RT-26 + RT-27 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first / RT-26 second / RT-27 third — unchanged
--         (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence (RT-22 = PDF-worker
--         container Dockerfile), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         (RT-26), no network-exposure/config admission surface (RT-27) is touched —
--         this is authenticated-tier RLS/FK/column DROP work. The create path uses NO
--         service_role, so the RT-26 code-layer key allowlist is untouched (stays 4).
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DROP ORDER (dependency-safe):
--   trigger → function (the trigger's target) → column (the trigger's WHEN ref).
--   The trigger's WHEN (new.sub_cat_id IS NOT NULL) references the column, and the
--   trigger binds the function, so BOTH must go before the column can be dropped.
--   fn_create_manual_account: DROP the 7-arg signature (no DB object depends on it —
--   only the app RPC call site, updated in the paired Backend slice), then recreate
--   6-arg. All statements are idempotent (IF EXISTS / CREATE OR REPLACE).
--
-- DEPLOY-ORDERING NOTE (for the coordinated slice). The signature change makes
--   MIGRATION-FIRST the breaking direction (a 7-named-arg PostgREST call would 404 a
--   6-arg fn) and APP-CHANGE-FIRST the backward-compatible direction (6 named args
--   satisfy the 7-arg-with-DEFAULT fn while it still exists). Ship the Backend arg-drop
--   and 048 together; if any skew is possible, land the app change first. Local verify
--   (this migration alone, no app in the loop) is unaffected.
--
-- ----------------------------------------------------------------------------
-- CONTRACT (post-048)
--   pfin.account — no `sub_cat_id` column; no `account_matched_sub_cat` trigger.
--   pfin.fn_account_matched_sub_cat() — dropped (does not exist).
--   pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--     p_tax_treatment text, p_initial_value numeric, p_as_of_date date) RETURNS
--     bigint — SECURITY INVOKER, set search_path = ''. Body (one transaction):
--     INSERT pfin.account (users_id defaulted, NOT a param) RETURNING account_id →
--     INSERT pfin.account_trans (transaction_type='acct_setup', dated p_as_of_date,
--     amount p_initial_value) → RETURN account_id. EXECUTE revoked from PUBLIC,
--     granted to authenticated only. Identical to 013 MINUS the p_sub_cat_id param
--     and the account.sub_cat_id column reference.
--   Security-load-bearing edges (unchanged from 013): users_id un-forgeable (column
--     DEFAULT auth.uid(), not a param); account_insert WITH CHECK + account_trans_insert
--     wr_access-JOIN (006, satisfied by the same-txn fn_grant_creator_access creator-
--     grant row) evaluate as the caller and fail closed cross-tenant; atomic body
--     prevents orphan accounts on the immutable ledger; audit deferred (A2, SELF-201
--     Task #7). Adds NO FK-shaped column — Decision-3 family: #5 DROPPED (see above).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) Drop the trigger binding on pfin.account (references sub_cat_id in its WHEN).
-- ----------------------------------------------------------------------------
drop trigger if exists account_matched_sub_cat on pfin.account;

-- ----------------------------------------------------------------------------
-- (2) Drop the Decision-3 #5 matched-tenant fence function (now unbound).
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_account_matched_sub_cat();

-- ----------------------------------------------------------------------------
-- (3) Drop the column. The FK (→ user_taxonomy, ON DELETE RESTRICT) drops with it.
-- Column is empty/unused in every environment (no surface ever wrote a non-NULL
-- value post-v1.132; Plaid + manual paths both passed NULL) — the drop touches no
-- data. `if exists` for idempotency / re-apply safety.
-- ----------------------------------------------------------------------------
alter table pfin.account drop column if exists sub_cat_id;

-- ----------------------------------------------------------------------------
-- (4) Re-issue fn_create_manual_account WITHOUT p_sub_cat_id (signature change).
-- DROP the old 7-arg signature (CREATE OR REPLACE cannot remove a parameter), then
-- recreate 6-arg. No DB object depends on the function (only the app RPC call site,
-- dropped in the paired Backend slice), so the DROP is safe.
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_create_manual_account(text, text, text, text, numeric, date, bigint);

create or replace function pfin.fn_create_manual_account(
  p_name          text,
  p_account_type  text,
  p_scope         text,
  p_tax_treatment text,
  p_initial_value numeric,
  p_as_of_date    date
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_account_id bigint;
begin
  -- (1) Create the manual account. users_id is deliberately NOT a parameter — it
  -- defaults to auth.uid() (003), the un-forgeable creator linchpin fenced by
  -- account_insert WITH CHECK (users_id = auth.uid()). The AFTER INSERT trigger
  -- fn_grant_creator_access (003, DEFINER) seeds account_users(rd,wr=true) in THIS
  -- same transaction before statement (2) runs. is_active defaults true. The
  -- account-level Sub-Cat column + its matched-tenant fence are removed (048 /
  -- SELF-319) — accounts are not classified per-account.
  insert into pfin.account (name, account_type, scope, tax_treatment)
  values (p_name, p_account_type, p_scope, p_tax_treatment)
  returning account_id into v_account_id;

  -- (2) The AcctSetup opening-balance row on the immutable audit-class ledger
  -- (004 / 012). One row: transaction_type='acct_setup', dated to the user-supplied
  -- as-of date, carrying the initial value. account_trans carries no own users_id —
  -- tenant scope derives via account_id → account_users wr_access-JOIN (006),
  -- satisfied by the creator-grant row from statement (1) in this same transaction.
  insert into pfin.account_trans (account_id, transaction_date, amount, transaction_type)
  values (v_account_id, p_as_of_date, p_initial_value, 'acct_setup');

  -- AUDIT FORWARD-HOOK (A2 deferral — conscious documented deviation; ADR-026).
  -- The same-transaction audit-log (api/CLAUDE.md; Decision 1 / Lock 4 mod #5) is
  -- DEFERRED: the audit-log table + its DEFINER insert-helper (4th, reserved/unauthored
  -- allowlist entry) do not exist yet, so no V1 path emits audit rows. WHEN the
  -- audit-infra issue (SELF-201 Task #7) lands, insert the same-transaction audit
  -- row HERE (this body, same txn). The immutable acct_setup row above is the V1
  -- creation-provenance stand-in. F/CTO-ratified defer; mirrors 006 mod #1.

  return v_account_id;
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke it (denies anon, which is in
-- PUBLIC), then grant to authenticated only. The create path is authenticated-tier;
-- anon must not reach it.
revoke execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date) from public;
grant execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date) to authenticated;

comment on function pfin.fn_create_manual_account(text, text, text, text, numeric, date) is
  'SECURITY INVOKER write-composition RPC (SELF-201 §2.4.2; ADR-026; p_sub_cat_id param dropped at 048 / SELF-319). Atomically creates a manual account + its AcctSetup opening-balance account_trans row (transaction_type=''acct_setup'', dated p_as_of_date, amount p_initial_value) in ONE transaction under the caller''s RLS, RETURNING the new account_id. The write analogue of the Lock 11 INVOKER read-composition helpers. users_id is NOT a parameter (defaults to auth.uid() per 003 — un-forgeable). Fences evaluate as the caller: account_insert WITH CHECK + account_trans_insert wr_access-JOIN (006, satisfied by the same-txn fn_grant_creator_access creator-grant row). The account-level Sub-Cat surface (column + fn_account_matched_sub_cat matched-tenant fence, Decision-3 #5) is REMOVED at 048 — accounts are not classified per-account. NOT a DEFINER allowlist entry — needs no elevation; allowlist stays 4. Needs NO service_role (anon-key client + RLS + INVOKER). set search_path = '''' injection fence. EXECUTE revoked from PUBLIC, granted to authenticated only (anon denied). Same-transaction audit-log DEFERRED (A2; forward-hook in body; SELF-201 Task #7). Adds no FK-shaped column — Decision 3 family: #5 DROPPED at 048 (15 labeled / 12 DDL-realized). Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed) — the 7-arg signature is replaced by this 6-arg one.';
