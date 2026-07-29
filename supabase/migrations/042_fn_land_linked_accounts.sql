-- ============================================================================
-- Migration: pfin.fn_land_linked_accounts — SECURITY INVOKER write-composition RPC
-- Phase 6 Build Loop (SELF-199 / §2.4.1.d per-account attribute capture; ADR-037
-- reconciled onto the provider-agnostic linked_source substrate). Lands the atomic
-- multi-row persist path SELF-199 needs: ONE call that INSERTs one pfin.account row
-- per SELECTED provider account from the adapter's AccountRef[], each carrying the
-- user-set attributes (name / scope / tax_treatment / account_type) + its
-- linked_source_id + provider_account_id, in ONE transaction under the caller's RLS.
-- The multi-row provider-linked analogue of the 013 fn_create_manual_account
-- single-account write-composition RPC (ADR-026 pattern); the "landAccounts" consumer
-- the 021 partial-UNIQUE arbiter anticipates.
--
-- Numbering: 042 follows 041_taxonomy_default_and_provisioning (head at authoring).
-- SELF-199 is greenlit FIRST of the remaining §2.4 issues, so this RPC takes 042;
-- the ADR-037 SELF-207 typed sync-cursor migration (OWD-A A3) consequently shifts
-- 042 -> 043 (migrations are append-only sequential; lowest-number-lands-first).
-- ADR-037's Decision 3/4/6 + Cross-references name the cursor migration "042" — a
-- one-line doc-sync to "043" is flagged to team-lead (does NOT change the ADR's
-- ledger claims). Depends on: 003 (pfin.account + account_insert RLS WITH CHECK +
-- fn_grant_creator_access DEFINER creator-grant trigger + account_users), 015 (the
-- linked_source_id + provider_account_id ALTER columns + fn_account_matched_linked_source
-- Decision-3 #6 fence + the linked_source table), 021 (account_linked_source_provider_uidx
-- partial-UNIQUE dedup index = the ON CONFLICT arbiter), 025 (the aal2 step-up backstop
-- clause already AND-ed into pfin.account's authenticated policies). No downstream
-- migration depends on 042.
--
-- ----------------------------------------------------------------------------
-- ATOMICITY FORCING FUNCTION (why an RPC, not N supabase-js .insert() calls).
--   locals.supabase runs each .insert() as its OWN PostgREST transaction, so landing
--   N selected accounts across N client calls is NOT atomic — a mid-way failure leaves
--   a partial account set, and app-level compensation is structurally blocked:
--   authenticated has NO DELETE grant/policy on pfin.account (003 — soft-delete only
--   via is_active), so partially-landed rows cannot be reversed by the client. A single
--   INVOKER RPC whose body is one transaction is the correct all-or-nothing shape
--   (Option A2, F/CTO-ratified — over A1 direct multi-INSERT). Mirrors 013's atomicity
--   argument, extended from 1 row to N.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (NOT DEFINER); DEFINER allowlist stays 4.
--   The function needs NO elevated privilege — every write it composes is one the
--   caller is already entitled to make, and RLS validates each as the caller:
--     - account INSERT: account_insert WITH CHECK (users_id = auth.uid()); users_id is
--       NOT a parameter — it defaults to auth.uid() (003), the un-forgeable creator
--       linchpin. A caller cannot land an account under another tenant's users_id.
--     - the AFTER INSERT fn_grant_creator_access (003, DEFINER) seeds the
--       account_users(rd,wr=true) creator-grant row per landed account in THIS same
--       transaction (fires per-row, so each of the N accounts is granted).
--     - linked_source_id: fn_account_matched_linked_source (015, BEFORE INSERT OR
--       UPDATE, Decision-3 #6) fails closed on a cross-tenant p_linked_source_id even
--       routed through this RPC (defense-in-depth) — it validates the referenced
--       linked_source's owner == the row's users_id (= auth.uid()).
--     - aal2 step-up: because this RPC is INVOKER it inherits the 025 backstop clause
--       on BOTH pfin.account AND pfin.linked_source. FENCE ORDER (linked path): the
--       clause fires FIRST at the #6 fence — pfin.linked_source's SELECT policy carries
--       the 025 aal2 clause, so a caller at aal1 with mfa_policy in (totp,passkey) sees
--       their OWN source as RLS-INVISIBLE, and fn_account_matched_linked_source (015),
--       which does a NOT EXISTS against linked_source, raises BEFORE the account INSERT
--       WITH CHECK is ever evaluated. The account_insert WITH CHECK aal2 clause is the
--       BACKSTOP, not the first gate, on the provider-linked path. Either way the aal1
--       call fails closed. Nothing to add here (no new table; the clause is inherited,
--       not re-authored). [Fence order QA-verified — SELF-199 two-tenant battery.]
--   Because no elevation is used, this is NOT a new SECURITY DEFINER allowlist entry
--   (ADR-011 Decision 9 — allowlist stays 4: fn_refresh_updated_at + fn_grant_creator_
--   access + fn_reclass_history_insert + the still-reserved-unauthored audit-log helper).
--   set search_path = '' is the injection fence; all refs schema-qualified; column
--   DEFAULTs (auth.uid(), now()) resolve at definition-time OID, unaffected by the
--   empty search_path. LANDING NEEDS NO service_role: anon-key client + RLS + INVOKER
--   suffices (mirrors 013; Sec to re-confirm at joint-review).
--
-- ----------------------------------------------------------------------------
-- TABLE-RETURNING WRITE — #variable_conflict use_column (capability-verify lesson).
--   This is the FIRST TABLE-returning write RPC (013 fn_create_manual_account RETURNS
--   bigint — a scalar with no OUT-column names, so it never hit this). RETURNS TABLE
--   (account_id, provider_account_id) creates implicit OUT *variables* whose names
--   COLLIDE with the same-named pfin.account columns referenced in the INSERT — most
--   sharply in the ON CONFLICT target `(linked_source_id, provider_account_id)`, where
--   a conflict-target column CANNOT be table-qualified. Under plpgsql's default
--   `#variable_conflict error` that ambiguity aborts EVERY call ("column reference
--   \"provider_account_id\" is ambiguous"). The fix is the compiler directive
--   `#variable_conflict use_column` as the first line of the body (before `declare`):
--   it resolves the ambiguous names to the COLUMNS, which is correct here — this
--   function reads no OUT variable by name (RETURN QUERY maps the query result to the
--   TABLE output POSITIONALLY, not by OUT-var assignment), so preferring columns is
--   safe and total. It PRESERVES the API contract: the OUT param names account_id /
--   provider_account_id (the PostgREST response columns) are unchanged — the fix
--   deliberately does NOT rename them (renaming would break the /rpc response shape +
--   downstream TS). LESSON FOR THE NEXT TABLE-returning write RPC: add
--   `#variable_conflict use_column` whenever a RETURNS TABLE column name matches a
--   written-table column referenced in an unqualifiable position (ON CONFLICT target,
--   etc.). Verify-at-first-apply (clean-apply smoke under the real role) is what
--   surfaced this — it does not reproduce in static review.
--
-- ----------------------------------------------------------------------------
-- DEDUP / ON CONFLICT — reuses the 021 partial-UNIQUE arbiter (idempotent re-land).
--   Each landed row is provider-linked (linked_source_id is always NON-NULL — it is
--   the required p_linked_source_id param), so every row is IN the 021 partial index
--   account_linked_source_provider_uidx (linked_source_id, provider_account_id) WHERE
--   linked_source_id IS NOT NULL. ON CONFLICT DO UPDATE SET is_active = true honors the
--   021 reconciliation-model commitment: a re-land of the same (source, provider account)
--   REACTIVATES the canonical row (recovering a soft-deleted account), NEVER a 2nd row.
--   DO UPDATE (not DO NOTHING) is chosen so RETURNING yields the account_id for
--   already-existing rows too (the caller gets the id for every selected account, whether
--   freshly inserted or reactivated). The re-land deliberately does NOT overwrite the
--   user's stored attributes (name/scope/tax_treatment/account_type) — attribute EDITS
--   are a separate account_update path, not a landing side-effect (kept clean; flagged
--   to team-lead as a design choice, not an omission).
--   provider_account_id is guarded NON-NULL below: a NULL dedup key would be treated as
--   distinct by the partial index (insert-always) → silent duplicates on re-land; adapter
--   AccountRefs always carry it, and the guard makes the invariant fail-closed, not implicit.
--
-- ----------------------------------------------------------------------------
-- INPUT SHAPE — p_accounts jsonb array (PostgREST-friendly; malformed → fail-closed).
--   p_accounts = [ { "provider_account_id": text, "name": text, "scope": text,
--                    "tax_treatment": text, "account_type": text }, ... ].
--   A missing/typo key resolves to NULL via ->>, which the pfin.account NOT NULL
--   constraints (name/account_type/scope/tax_treatment) + the account_type/tax_treatment
--   CHECK constraints (003) reject — the whole transaction aborts (fail-closed; no
--   partial landing). Unselected accounts are simply never present in p_accounts →
--   never persisted (SELF-199 AC: the V1 share decision is authoritative). currency is
--   left to the pfin.account default ('USD', 015) — not in the SELF-199 attribute set;
--   an optional per-account currency key can be added additively later without a
--   breaking signature change.
--
-- ----------------------------------------------------------------------------
-- API-SURFACE NOTE (mild one-way door). pfin is API-exposed (ADR-023 [api] schemas)
--   and this function is EXECUTE-granted to authenticated, so it is callable via
--   PostgREST at /rpc/fn_land_linked_accounts. Its parameter names + types (and the
--   p_accounts object key names) are an API contract — renaming/retyping later is a
--   breaking change for the call site (adding a new DEFAULTed param / optional object
--   key is additive-safe). anon is denied: REVOKE EXECUTE FROM PUBLIC + GRANT EXECUTE
--   TO authenticated only.
--
-- ----------------------------------------------------------------------------
-- AUDIT-LOG A2 DEFERRAL (conscious documented deviation; consistent with 013 / ADR-026).
--   The general same-transaction audit-log helper is the reserved-but-UNAUTHORED 4th
--   SECURITY DEFINER allowlist slot (SELF-201 Task #7). This RPC ships audit-less
--   (A2-lite), exactly as 013 fn_create_manual_account did: no V1 path emits audit rows
--   yet, and bootstrapping cross-cutting audit infra as a side-effect of the account-
--   landing form is out of scope. Provenance is already covered for provider-landed
--   accounts by the append-only pfin.linked_source_sync_audit (015) + the immutable
--   account_trans ledger downstream. A FORWARD-HOOK marks where the same-transaction
--   audit row lands when the infra arrives (Decision 1 / Lock 4 mod #5). NOTE FOR
--   RATIFY: the A2 build pitch mentioned a "built-in audit-log"; the recommendation
--   here is DEFER to SELF-201 Task #7 (consistent with the 013 precedent) — if F/CTO
--   intended audit-now, the reserved-slot DEFINER helper is authored instead (Sec
--   joint-review-mandatory; allowlist stays 4 as it fills the reserved slot). Flagged.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list; Decision 4 read verbatim before drafting).
--   ZERO catalogued §10 instances; ledger stays at 3 (RT-22 first / RT-26 second /
--   RT-27 third per ADR-011 Decision 4). (i) instance-numbering unchanged. (ii)
--   layer-attribution — authenticated-tier INVOKER write-composition; no infra-
--   credential-presence (RT-22), no SUPABASE_SERVICE_ROLE_KEY code-layer allowlist
--   (RT-26 — the landing path uses NO service_role), and no app->worker admission
--   network-exposure surface (RT-27) is touched. (iii) Decision 4 linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family +0 (stays 14 labeled
--   / 12 DDL-realized). This migration adds NO new FK-shaped column. It PASSES
--   p_linked_source_id THROUGH into the account INSERT, where the already-catalogued
--   canonical instance #6 fence (015's fn_account_matched_linked_source, BEFORE INSERT
--   OR UPDATE matched-tenant trigger) validates it fails-closed cross-tenant. The RPC
--   EXERCISES #6, it does not create a new instance. provider_account_id is TEXT (a
--   provider-native id, NOT a pfin FK) → NOT a Decision-3 instance (015 STEP 7 /
--   021 attribution). The canonical enumeration (ADR-011 Decision 3) is UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   The two-tenant pgTAP battery extends to the provider-linked multi-account landing:
--     - owner lands own selected accounts (one row per object; users_id = auth.uid());
--     - a re-land of the same (linked_source_id, provider_account_id) reactivates via
--       is_active — NO 2nd row (021 arbiter exercised through this RPC);
--     - cross-tenant p_linked_source_id fails closed (the #6 fence, exercised);
--     - a caller cannot land an account visible to another tenant (account_insert
--       WITH CHECK + users_id DEFAULT);
--     - malformed p_accounts (missing NOT NULL key / bad account_type / bad
--       tax_treatment / null provider_account_id) aborts the whole call (fail-closed,
--       no partial landing).
--   Sec joint-review-mandatory (money-adjacent account creation INVOKER RPC + the
--   Decision-3 #6-fence exercise). Not a vacuous green — the fixture must populate two tenants.
--
-- CONTRACT
--   pfin.fn_land_linked_accounts(p_linked_source_id bigint, p_accounts jsonb)
--     RETURNS TABLE(account_id bigint, provider_account_id text) —
--     LANGUAGE plpgsql, SECURITY INVOKER, set search_path = ''. VOLATILE (writes).
--     Body opens with `#variable_conflict use_column` — MANDATORY for this TABLE-
--     returning write RPC (the OUT-column names collide with the pfin.account columns
--     in the unqualifiable ON CONFLICT target; see the TABLE-RETURNING WRITE note above).
--   Body (one transaction): for each element of p_accounts, INSERT pfin.account
--     (users_id defaulted, NOT a param; name/account_type/scope/tax_treatment from the
--     object; linked_source_id = p_linked_source_id; provider_account_id from the object)
--     ON CONFLICT (linked_source_id, provider_account_id) WHERE linked_source_id IS NOT
--     NULL DO UPDATE SET is_active = true, RETURNING (account_id, provider_account_id)
--     appended to the result set. EXECUTE revoked from PUBLIC; granted to authenticated.
--   Security-load-bearing edges: users_id un-forgeable (column DEFAULT, not a param);
--     all fences evaluate as the caller and fail closed cross-tenant (account_insert
--     WITH CHECK, fn_account_matched_linked_source #6, inherited 025 aal2 clause);
--     atomic body prevents partial landing on the immutable-adjacent account entity;
--     provider_account_id guarded non-null so dedup cannot be silently bypassed; audit
--     deferred (A2-lite; forward-hook in body).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_land_linked_accounts(
  p_linked_source_id bigint,
  p_accounts         jsonb
)
returns table (account_id bigint, provider_account_id text)
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_acct jsonb;
begin
  -- Fail-closed input-shape guard: p_accounts must be a JSON array. A non-array (or
  -- NULL) is a malformed call — abort before any write (no partial landing).
  if p_accounts is null or jsonb_typeof(p_accounts) <> 'array' then
    raise exception 'p_accounts must be a non-null JSON array of account objects'
      using errcode = '22023';  -- invalid_parameter_value
  end if;

  for v_acct in select value from jsonb_array_elements(p_accounts) as t(value)
  loop
    -- Guard the dedup key: provider_account_id must be present. A NULL key would be
    -- treated as distinct by the 021 partial index (insert-always) → silent duplicates
    -- on re-land. Adapter AccountRefs always carry it; make the invariant fail-closed.
    if v_acct ->> 'provider_account_id' is null then
      raise exception 'each p_accounts element must carry a non-null provider_account_id'
        using errcode = '22023';
    end if;

    -- One pfin.account row per selected provider account. users_id is deliberately NOT
    -- set — it defaults to auth.uid() (003), the un-forgeable creator linchpin fenced by
    -- account_insert WITH CHECK. The AFTER INSERT fn_grant_creator_access (003, DEFINER)
    -- seeds account_users(rd,wr=true) per row in THIS same transaction. linked_source_id
    -- is fenced by fn_account_matched_linked_source (015, Decision-3 #6) — a cross-tenant
    -- p_linked_source_id fails closed even through this RPC. Missing NOT NULL keys resolve
    -- to NULL via ->> and are rejected by the pfin.account NOT NULL + CHECK constraints,
    -- aborting the whole transaction (fail-closed). is_active defaults true.
    -- ON CONFLICT reactivates the canonical row (021 reconciliation model — never a 2nd
    -- row; recovers a soft-deleted account); attribute edits are a separate update path,
    -- so a re-land does NOT overwrite stored attributes.
    return query
    insert into pfin.account (
      name, account_type, scope, tax_treatment,
      linked_source_id, provider_account_id
    )
    values (
      v_acct ->> 'name',
      v_acct ->> 'account_type',
      v_acct ->> 'scope',
      v_acct ->> 'tax_treatment',
      p_linked_source_id,
      v_acct ->> 'provider_account_id'
    )
    on conflict (linked_source_id, provider_account_id) where linked_source_id is not null
    do update set is_active = true
    returning pfin.account.account_id, pfin.account.provider_account_id;

    -- AUDIT FORWARD-HOOK (A2-lite deferral — conscious documented deviation; mirrors 013).
    -- WHEN the audit-infra issue (SELF-201 Task #7) lands, insert the same-transaction
    -- audit row HERE (this body, same txn; Decision 1 / Lock 4 mod #5). The append-only
    -- linked_source_sync_audit (015) + the immutable account_trans ledger are the V1
    -- provenance stand-ins for provider-landed accounts.
  end loop;
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke it (denies anon, which is in
-- PUBLIC), then grant to authenticated only. Landing is authenticated-tier; anon must
-- not reach it.
revoke execute on function pfin.fn_land_linked_accounts(bigint, jsonb) from public;
grant execute on function pfin.fn_land_linked_accounts(bigint, jsonb) to authenticated;

comment on function pfin.fn_land_linked_accounts(bigint, jsonb) is
  'SECURITY INVOKER write-composition RPC (SELF-199 §2.4.1.d; ADR-037; A2 F/CTO-ratified). Atomically lands one pfin.account row per SELECTED provider account from the adapter''s AccountRef[] (passed as p_accounts jsonb array of {provider_account_id,name,scope,tax_treatment,account_type}), each carrying linked_source_id = p_linked_source_id, in ONE transaction under the caller''s RLS, RETURNING (account_id, provider_account_id) per landed account. Multi-row provider-linked analogue of 013 fn_create_manual_account (ADR-026 pattern). users_id is NOT a parameter (defaults to auth.uid() per 003 — un-forgeable). All fences evaluate as the caller: account_insert WITH CHECK, the same-txn fn_grant_creator_access creator-grant per row (003 DEFINER trigger), fn_account_matched_linked_source (015, Decision-3 #6 — cross-tenant p_linked_source_id fails closed), and the inherited 025 aal2 step-up clause on both account and linked_source (on the linked path an aal1 caller fails closed at the #6 fence FIRST — linked_source is aal2-invisible so the NOT EXISTS raises — with account_insert WITH CHECK as backstop). ON CONFLICT (linked_source_id, provider_account_id) WHERE linked_source_id IS NOT NULL DO UPDATE SET is_active = true reuses the 021 dedup arbiter: a re-land reactivates the canonical row, never a 2nd row, and does not overwrite stored attributes. provider_account_id guarded non-null (dedup key). Malformed input fails closed (NOT NULL + CHECK constraints abort the txn; non-array p_accounts raises). NOT a DEFINER allowlist entry — needs no elevation; allowlist stays 4. Needs NO service_role (anon-key client + RLS + INVOKER). set search_path = '''' injection fence. EXECUTE revoked from PUBLIC, granted to authenticated only (anon denied). Same-transaction audit-log DEFERRED (A2-lite; forward-hook in body; SELF-201 Task #7). Adds no FK-shaped column — Decision-3 family unchanged (exercises #6); §10 ledger unchanged at 3. Signature + p_accounts object keys are an API contract (PostgREST /rpc; pfin is [api]-exposed).';
