-- ============================================================================
-- Migration: pfin.fn_create_manual_account — SECURITY INVOKER write-composition RPC
-- Phase 6 Build Loop (SELF-201 / §2.4.2 manual non-Plaid account onboarding).
-- Lands the atomic create path SELF-201 AC#2 needs: one call that INSERTs the
-- account + its AcctSetup opening-balance account_trans row in ONE transaction,
-- under the caller's RLS context. RETURNS the new account_id. Establishes the
-- write-composition-under-INVOKER pattern (the write analogue of the Lock 11
-- read-composition helpers fn_compute_nav / fn_compute_tax_liability /
-- fn_render_monthly_report). ADR-026.
--
-- Numbering: 013 follows 012 (account.sub_cat_id + account_trans.transaction_type).
-- Prerequisites, all on main (PR #141 for 012): 003 (pfin.account + account_insert
-- RLS WITH CHECK + fn_grant_creator_access DEFINER trigger + account_users), 004
-- (pfin.account_trans immutable ledger), 006 (account_trans rd/wr_access-JOIN RLS +
-- GRANT select,insert), 012 (transaction_type discriminator + sub_cat_id FK +
-- fn_account_matched_sub_cat matched-tenant trigger). No downstream migration
-- depends on 013.
--
-- ----------------------------------------------------------------------------
-- ATOMICITY FORCING FUNCTION (why an RPC, not two supabase-js calls).
--   locals.supabase runs each .insert() as its OWN PostgREST transaction, so
--   account + account_trans across two client calls is NOT atomic — a mid-way
--   failure orphans the account. And app-level compensation is structurally
--   blocked: authenticated has NO DELETE grant/policy on pfin.account (003 —
--   soft-delete only via is_active), so an orphan account cannot be reversed by
--   the client. A single INVOKER RPC whose body is one transaction is the correct
--   all-or-nothing shape on the immutable audit-class ledger (Option A; Options B
--   sequential-inserts + C DEFINER/trigger-synthesis rejected — see ADR-026).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (NOT DEFINER); DEFINER allowlist stays 3.
--   The function needs NO elevated privilege — every write it composes is one the
--   caller is already entitled to make, and RLS validates each as the caller:
--     - account INSERT: account_insert WITH CHECK (users_id = auth.uid()); users_id
--       is NOT a parameter — it defaults to auth.uid() (003), the un-forgeable
--       creator linchpin. A caller cannot create an account for another tenant.
--     - the AFTER INSERT fn_grant_creator_access (003, DEFINER) seeds the
--       account_users(rd,wr=true) creator-grant row in THIS same transaction,
--       BEFORE the account_trans statement runs.
--     - account_trans INSERT: account_trans_insert WITH CHECK wr_access-JOIN (006)
--       — satisfied by that creator-grant row; cross-account writes fail closed.
--     - sub_cat_id: fn_account_matched_sub_cat (012, BEFORE INSERT) fails closed on
--       a cross-tenant p_sub_cat_id even routed through this RPC (defense-in-depth).
--   Because no elevation is used, this is NOT a new SECURITY DEFINER allowlist entry
--   (ADR-011 Decision 9 — allowlist stays 3: fn_refresh_updated_at + fn_grant_creator_
--   access + the still-unauthored audit-log helper). set search_path = '' is the
--   injection fence; all refs schema-qualified; column DEFAULTs (auth.uid(), now())
--   resolve at definition-time OID, unaffected by the empty search_path.
--   CREATE PATH NEEDS NO service_role: anon-key client + RLS + INVOKER suffices
--   (Backend confirmed; Sec to re-confirm at joint-review).
--
-- ----------------------------------------------------------------------------
-- API-SURFACE NOTE (mild one-way door). pfin is API-exposed (ADR-023 [api] schemas)
--   and this function is EXECUTE-granted to authenticated, so it is callable via
--   PostgREST at /rpc/fn_create_manual_account. Its parameter names + types are
--   therefore an API contract — renaming/retyping a param later is a breaking change
--   for the call site (adding a new DEFAULTed param is additive-safe). Signature is
--   fixed deliberately to match the Backend call site (temp/self-201-backend-plan.md
--   §1-A). anon is denied: REVOKE EXECUTE FROM PUBLIC (which includes anon) + GRANT
--   EXECUTE TO authenticated only.
--
-- ----------------------------------------------------------------------------
-- AUDIT-LOG A2 DEFERRAL (conscious documented deviation; ADR-026; F/CTO-ratified).
--   api/CLAUDE.md mandates a same-transaction audit-log per state change, but the
--   audit-log table + its DEFINER insert-helper (the 3rd, still-UNAUTHORED DEFINER
--   allowlist entry) do NOT exist at 013 — NO V1 path emits audit rows yet
--   (account/account_trans/reconciliation all already ship without it). The audit
--   insert is DEFERRED to the dedicated audit-infra issue (SELF-201 Task #7) rather
--   than bootstrapping cross-cutting audit infra as a side-effect of the first
--   manual-account form. A FORWARD-HOOK comment marks where the same-transaction
--   audit row lands when the infra arrives (Decision 1 / Lock 4 mod #5). The
--   immutable acct_setup row already provides V1 creation provenance. Mirrors the
--   006 mod #1 documented-forward-fence deferral shape. Sec concurrence at joint-review.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference Decision 4; do NOT restate the list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii)
--   layer-attribution — authenticated-tier INVOKER write-composition; no infra-
--   credential-presence (RT-22) or SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26)
--   surface touched; the create path uses NO service_role (RT-26 code-layer key
--   allowlist untouched). (iii) Decision 4 linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0 (stays 5).
--   013 adds NO new FK-shaped column. It PASSES p_sub_cat_id THROUGH into the account
--   INSERT, where the already-catalogued canonical instance #5 fence (012's
--   fn_account_matched_sub_cat) validates it. No new matched-tenant obligation; the
--   canonical enumeration (ADR-011 Decision 3, 5 instances) is unchanged.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--     p_tax_treatment text, p_initial_value numeric, p_as_of_date date,
--     p_sub_cat_id bigint DEFAULT NULL) RETURNS bigint —
--     LANGUAGE plpgsql, SECURITY INVOKER, set search_path = ''. VOLATILE (writes).
--   Body (one transaction): INSERT pfin.account (users_id defaulted, NOT a param)
--     RETURNING account_id → INSERT pfin.account_trans (transaction_type='acct_setup',
--     transaction_date=p_as_of_date, amount=p_initial_value) → RETURN account_id.
--   EXECUTE revoked from PUBLIC; granted to authenticated only.
--   Security-load-bearing edges: users_id un-forgeable (column DEFAULT, not a param);
--     all three RLS fences (account_insert / account_trans_insert wr_access-JOIN /
--     fn_account_matched_sub_cat) evaluate as the caller and fail closed cross-tenant;
--     atomic body prevents orphan accounts on the immutable ledger; audit deferred (A2).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_create_manual_account(
  p_name          text,
  p_account_type  text,
  p_scope         text,
  p_tax_treatment text,
  p_initial_value numeric,
  p_as_of_date    date,
  p_sub_cat_id    bigint default null
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
  -- same transaction before statement (2) runs. p_sub_cat_id is fenced by
  -- fn_account_matched_sub_cat (012, BEFORE INSERT) — a cross-tenant Sub-Cat fails
  -- closed even through this RPC (defense-in-depth). is_active defaults true.
  insert into pfin.account (name, account_type, scope, tax_treatment, sub_cat_id)
  values (p_name, p_account_type, p_scope, p_tax_treatment, p_sub_cat_id)
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
  -- DEFERRED: the audit-log table + its DEFINER insert-helper (3rd, UNAUTHORED
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
revoke execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, bigint) from public;
grant execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, bigint) to authenticated;

comment on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, bigint) is
  'SECURITY INVOKER write-composition RPC (SELF-201 §2.4.2; ADR-026). Atomically creates a manual account + its AcctSetup opening-balance account_trans row (transaction_type=''acct_setup'', dated p_as_of_date, amount p_initial_value) in ONE transaction under the caller''s RLS, RETURNING the new account_id. The write analogue of the Lock 11 INVOKER read-composition helpers. users_id is NOT a parameter (defaults to auth.uid() per 003 — un-forgeable). All fences evaluate as the caller: account_insert WITH CHECK, account_trans_insert wr_access-JOIN (006, satisfied by the same-txn fn_grant_creator_access creator-grant row), and fn_account_matched_sub_cat (012, cross-tenant p_sub_cat_id fails closed). NOT a DEFINER allowlist entry — needs no elevation; allowlist stays 3. Needs NO service_role (anon-key client + RLS + INVOKER). set search_path = '''' injection fence. EXECUTE revoked from PUBLIC, granted to authenticated only (anon denied). Same-transaction audit-log DEFERRED (A2; forward-hook in body; SELF-201 Task #7). Adds no FK-shaped column — Decision 3 family unchanged at 5. Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed).';
