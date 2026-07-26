-- ============================================================================
-- Migration: pfin — manual cash-entry write path + un-dorm account_trans_split writes
-- Phase 6 Build Loop (SELF-202 / §2.4.3.a Cash transaction entry). Re-derived to the
--   append-only model (F/CTO-ratified 2026-07-25): SKIP eliminated (no is_excluded
--   column — a Transfer is categorized as Transfer and Σ=0-offsets in the GL; hiding a
--   category is a report-view WHERE-filter, NOT stored data-layer state — see ADR-032);
--   manual entry = fn_create_manual_trans INVOKER RPC; split = un-dorm the 029 write
--   path per the locked child-lifecycle rule; edit = 004 reverse-and-replace (app-layer,
--   source_provider/provider_txn_id (+ import_hash) dedup rule — no DDL here).
--
-- WHAT THIS DOES (two parts, no new base table):
--   PART A — un-dorm pfin.account_trans_split writes (029 shipped SELECT-only / write-
--     dormant). Adds the wr_access-JOIN INSERT/UPDATE/DELETE policies (mirroring 023's
--     ata_* shape, INCLUDING the aal2 backstop conjunct) + grant insert,update,delete.
--     The Σ=parent deferred constraint trigger, the #13 matched-tenant sub_cat fence, and
--     the T-account view already exist in 029 — un-dorming ACTIVATES them on the write
--     path; this migration authors NO new function/table/column/view/trigger in Part A.
--   PART B — pfin.fn_create_manual_trans: SECURITY INVOKER write-composition RPC that
--     atomically INSERTs a manual cash account_trans row (004) + (when categorized/noted)
--     its 023 annotation, in ONE txn under the caller's RLS. The cash sibling of 013's
--     fn_create_manual_account.
--
-- ----------------------------------------------------------------------------
-- ⚠️ SCOPE NOTE (flagged for Sec joint-review) — the 029 SELECT aal2 gap is fixed here.
--   029 (migration 29) landed AFTER 025 (migration 25, the aal2 step-up backstop retrofit),
--   so 025 could NOT clause account_trans_split's SELECT policy, and 029 did not inline the
--   clause. Result: account_trans_split_select shipped UN-CLAUSED — a C3 standing-obligation
--   gap (ADR-029 / 025 Step 4): a sensitive tenant-owned pfin table, [api]-exposed (ADR-023),
--   readable at aal1 by a user who DECLARED totp/passkey (a stolen password reaches split
--   amounts/categories before TOTP step-up). Split lines partition an account_trans amount
--   that IS itself claused (006→025), so the leak severity is "how a protected total was
--   subdivided", but the posture is inconsistent. This migration CLOSES it: PART A ALTERs
--   account_trans_split_select to add the backstop conjunct AND authors all 3 new write
--   policies WITH the conjunct inline — so the whole table matches the 023 claused set.
--   Not a one-way door (ALTER POLICY is reversible; no data migration). It IS an aal2/C3
--   fence-surface change → Sec joint-review (routed alongside the un-dorm write path).
--
-- Numbering: 038 follows 037 (GL completion). Depends on 004 (account_trans immutable
--   ledger — the trans_id target + numeric(20,4) amount + is_reverse/replaces_trans_id),
--   006 (account_trans rd/wr_access-JOIN RLS this composes under), 017 (the cash-row shape:
--   security_id NULL + quantity 0 default satisfies check (quantity=0 OR security_id IS NOT
--   NULL)), 023 (account_trans_annotation — the category/note overlay + its #10 fence), 025
--   (the aal2 backstop clause this Part A mirrors), 029 (account_trans_split — the write-
--   dormant table Part A un-dorms), 030 (transaction_type='standard' vocab + its CHECK), 001
--   (pfin schema). No downstream migration depends on 038.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read VERBATIM before drafting.) This migration
--   introduces ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27
--   per ADR-011 Decision 4 — RT-27 appended third at SELF-212 / 2026-07-19).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 = PDF-
--         worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist surface
--         (RT-26 = web-app/worker SOURCE grep fence), and no app→worker credential-admission
--         network-exposure/config surface (RT-27 = the SELF-212 admission fence) is touched.
--         This is authenticated-tier RLS + an INVOKER RPC only — NO service_role grant, NO
--         service_role reach. Same layer-attribution as 025's authenticated-RLS cross-check.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 038 is not the §10
--         canonical anchor.
--   DE-CONFLATION GUARD: the aal2 backstop conjunct (Part A) is an ADR-029 C3 mechanism and
--   the #13 sub_cat fence (029, activated here) is a Decision-3 mechanism — NEITHER is a §10
--   catalogued instance (the same separation 025 / 023 / 029 drew).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family delta = +0.
--   Canonical family = 14 labeled / 12 DDL-realized (superseded 2026-07-24, SELF-295 fold-in;
--   read the ADR-011 Decision 3 body list live — I assert the SHAPE, not re-derive the number).
--   This migration adds NO FK-shaped reference column:
--     - PART A un-dorms writes on account_trans_split. Its FK-shaped columns were evaluated at
--       029: account_trans_id → account_trans = SOLE tenant anchor (NOT D3); sub_cat_id →
--       user_taxonomy = the ALREADY-CATALOGUED matched-tenant fence #13 (chain-resolved),
--       authored + realized at 029 by fn_account_trans_split_matched_sub_cat (BEFORE INSERT OR
--       UPDATE). Un-dorming the write path ACTIVATES #13 on the authenticated write; it does
--       NOT add a family instance. Family count UNCHANGED.
--     - PART B fn_create_manual_trans adds no column. Its p_sub_cat_id flows into an
--       account_trans_annotation INSERT, which is fenced by the EXISTING #10 chain-resolved
--       matched-tenant fence (023, fn_account_trans_annotation_matched_sub_cat) — a cross-
--       tenant Sub-Cat fails closed through the RPC (defense-in-depth). No new instance.
--   Family stays 14 labeled / 12 realized — verify against the ADR-011 D3 body at joint-review.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default); NOT SECURITY DEFINER.
--   The SECURITY DEFINER allowlist is UNCHANGED (4 labeled / 3 authored per ADR-011 Decision 9
--   — fn_refresh_updated_at @001 + fn_grant_creator_access @003 + fn_reclass_history_insert
--   @031; the general audit-log helper reserved-unauthored). ZERO new SECURITY DEFINER here.
--   - PART A authors NO function (CREATE/ALTER POLICY + GRANT only).
--   - PART B fn_create_manual_trans is SECURITY INVOKER + set search_path='' — the write
--     analogue of the Lock 11 read-composition helpers (mirrors 013). It needs NO elevation:
--     both INSERTs run as the caller, so account_trans_insert wr_access-JOIN (006), ata_insert
--     wr_access-JOIN (023), the #10 + 030-trade fences, the 014 NaN CHECK, and — critically —
--     the aal2 backstop on account_trans_insert (006→025) AND ata_insert (023→025) ALL
--     evaluate as the caller. So aal2 step-up is enforced through the RPC WITHOUT any in-
--     function aal-check (the INVOKER-RLS composition IS the enforcement). No service_role;
--     anon-key client + RLS + INVOKER suffices. EXECUTE revoked from PUBLIC, granted to
--     authenticated only.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans_split (existing table; 029) gains:
--     - account_trans_split_select — ALTERED to AND the aal2 backstop conjunct into the
--       existing rd_access-JOIN USING (closes the 029 C3 gap; mirrors 023 ata_select).
--     - account_trans_split_insert — FOR INSERT WITH CHECK (wr_access-JOIN via account_trans_id
--       → account_trans.account_id → account_users) AND aal2 backstop.
--     - account_trans_split_update — FOR UPDATE USING + WITH CHECK (both wr_access-JOIN AND
--       aal2) — both clauses block a cross-account re-parent (moving a child onto an account
--       the caller lacks wr_access on).
--     - account_trans_split_delete — FOR DELETE USING (wr_access-JOIN AND aal2) — enables the
--       REPLACE (delete-all + re-insert balanced set) and UNSPLIT (delete entire set) ops.
--     - GRANT insert, update, delete ON pfin.account_trans_split TO authenticated (ACL-before-
--       RLS). SELECT grant already held from 029.
--     LOCKED CHILD-LIFECYCLE RULE (F/CTO-ratified 2026-07-25; the "parent XOR children, never
--       both, never orphaned" guarantee): per parent the only COMMIT-surviving states are
--       {0 children → reader counts the parent} XOR {N children with Σ=parent.amount → reader
--       counts the children}. The 029 Σ=parent deferred constraint trigger (AFTER INSERT OR
--       UPDATE OR DELETE, collects BOTH new+old account_trans_id → re-validates on child DELETE
--       and re-parent) rejects any partial/unbalancing mutation at COMMIT. Valid write ops:
--       (1) CREATE a balanced set; (2) REPLACE atomically (delete-all + insert new balanced
--       set, one txn); (3) UNSPLIT (delete entire set → revert to parent-only). Orphan is
--       structurally impossible (account_trans_id NOT NULL + FK → immutable parent, ON DELETE
--       RESTRICT). Reader = the 035/037 split_count branch (already shipped): split_count>0 →
--       count children, else count parent — never both.
--   pfin.fn_create_manual_trans(p_account_id bigint, p_transaction_date date, p_amount numeric,
--       p_vendor text, p_description text, p_sub_cat_id bigint, p_note text) RETURNS bigint —
--     atomically INSERTs a manual cash account_trans row (transaction_type='standard';
--     security_id NULL + quantity 0 default → satisfies the 017 cash CHECK; source_provider /
--     provider_txn_id / import_hash NULL — manual origin; is_reverse false; replaces_trans_id NULL) and, WHEN
--     p_sub_cat_id or p_note is provided, its 023 annotation (category/note), RETURNING the new
--     trans_id. All fences evaluate as the caller (INVOKER). set search_path=''. Signature is an
--     API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023).
--   Security-load-bearing edges: aal2 backstop now covers ALL split verbs + both RPC INSERTs
--     (INVOKER-composed); wr_access gates every split write + the account_trans write; the #13 +
--     #10 matched-tenant fences fail closed cross-tenant; the Σ=parent deferred constraint is the
--     money-correctness invariant; the immutable ledger (004) is untouched (edits stay reverse-
--     and-replace; NO skip/exclusion column — ADR-032).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ============================================================================
-- PART A — un-dorm pfin.account_trans_split writes (029) + close the SELECT aal2 gap.
-- Mirrors the 023 ata_* shape (029 explicitly forward-referenced "the split-UI PR adds
-- the wr_access-JOIN write policies + write grants together"). The aal2 backstop conjunct
-- is AND-ed into every verb (the 025 claused-set shape); the wr_access-JOIN resolves
-- tenancy via account_trans_id → account_trans.account_id → account_users (the parent-FK-
-- chain — account_trans_split has no own users_id).
-- ============================================================================

-- SELECT — ALTER to close the 029 C3 gap (add the aal2 backstop to the existing rd_access
-- USING). ALTER POLICY REPLACES the USING (idempotent on double-apply).
alter policy account_trans_split_select on pfin.account_trans_split
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_split.account_trans_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_trans_split_select on pfin.account_trans_split is
  'Parent-FK-chain SELECT policy (023/006 shape): rd_access-JOIN via account_trans_id → '
  'account_trans.account_id → account_users, AND the ADR-029 aal2 step-up backstop conjunct '
  '(added at 038 — 029 shipped un-claused because it post-dated the 025 retrofit; C3 gap '
  'closed). A user reads a split child only for a transaction whose account they hold rd_access '
  'on, and (if they declared totp/passkey) only at aal2.';

-- INSERT — wr_access-JOIN WITH CHECK + aal2. A user creates a split child only on a
-- transaction whose account they hold wr_access on.
create policy account_trans_split_insert on pfin.account_trans_split
  for insert to authenticated
  with check (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_split.account_trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_trans_split_insert on pfin.account_trans_split is
  'Parent-FK-chain INSERT policy (mod #3 — writes key on wr_access): wr_access-JOIN WITH CHECK '
  'via account_trans_id → account_trans.account_id → account_users, AND the aal2 backstop. '
  'Un-dorms the 029 write-dormant table (SELF-202). The #13 matched-tenant sub_cat fence + the '
  'Σ=parent deferred constraint trigger (both 029) fire on this INSERT.';

-- UPDATE — wr_access-JOIN USING + WITH CHECK + aal2 (both clauses). USING gates which rows
-- may be updated; WITH CHECK gates the post-image — together they block a cross-account
-- re-parent (repointing account_trans_id onto an account the caller lacks wr_access on).
create policy account_trans_split_update on pfin.account_trans_split
  for update to authenticated
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_split.account_trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_split.account_trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_trans_split_update on pfin.account_trans_split is
  'Parent-FK-chain UPDATE policy: wr_access-JOIN USING + WITH CHECK + aal2 (both clauses). The '
  'per-line edit / re-categorize path. Both clauses key on wr_access via the account chain so a '
  'child cannot be re-parented onto an account the caller lacks wr_access on. The #13 matched-'
  'tenant sub_cat fence + the Σ=parent deferred constraint (both 029) re-validate on UPDATE.';

-- DELETE — wr_access-JOIN USING + aal2. Enables REPLACE (delete-all + re-insert) and UNSPLIT
-- (delete entire set → revert to parent-only). A partial delete that unbalances Σ is rejected
-- at COMMIT by the 029 deferred constraint trigger (which re-checks the old parent on DELETE).
create policy account_trans_split_delete on pfin.account_trans_split
  for delete to authenticated
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_split.account_trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_trans_split_delete on pfin.account_trans_split is
  'Parent-FK-chain DELETE policy: wr_access-JOIN USING + aal2. Enables REPLACE (delete-all + '
  're-insert a balanced set) and UNSPLIT (delete the entire set → revert to parent-only '
  'counting). A partial/unbalancing delete is rejected at COMMIT by the 029 Σ=parent deferred '
  'constraint trigger (it collects the old parent on DELETE and re-checks Σ=parent.amount).';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on. Adds
-- the write verbs to the SELECT grant 029 already made. anon zero-grant (no USAGE on pfin per
-- ADR-023 C2). service_role UNGRANTED (no service_role split writer in V1).
grant insert, update, delete on pfin.account_trans_split to authenticated;

-- ============================================================================
-- PART B — pfin.fn_create_manual_trans: the manual cash-entry write-composition RPC.
-- The cash sibling of 013's fn_create_manual_account. SECURITY INVOKER — atomic
-- account_trans INSERT + (conditional) 023 annotation INSERT, under the caller's RLS.
-- ============================================================================
create or replace function pfin.fn_create_manual_trans(
  p_account_id       bigint,
  p_transaction_date date,
  p_amount           numeric,
  p_vendor           text    default null,
  p_description      text    default null,
  p_sub_cat_id       bigint  default null,
  p_note             text    default null
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_trans_id bigint;
begin
  -- (1) The manual cash row on the immutable audit-class ledger (004 / 017 / 030).
  -- transaction_type='standard' (a cash flow — class comes from the Cat overlay, 030).
  -- CASH SHAPE: security_id is left NULL and quantity defaults to 0 (017), which satisfies
  -- the 017 CHECK (quantity = 0 OR security_id IS NOT NULL). source_provider /
  -- provider_txn_id / import_hash are NULL — a manual entry has no provider dedup identity
  -- (so it never collides with the 017 account_trans_provider_dedup_idx (source_provider,
  -- provider_txn_id) partial-unique index nor the 004 (account_id, import_hash) index, and a
  -- later provider sync won't dedup against it). is_reverse defaults false; replaces_trans_id NULL — this is an
  -- original, not a reverse-and-replace correction. amount finiteness: numeric(20,4) rejects
  -- ±Infinity at coercion + the 014 CHECK rejects NaN. account_trans carries no own users_id;
  -- tenant scope derives via account_id → account_users wr_access-JOIN (006), evaluated as
  -- the caller (INVOKER) — AND aal2-gated (006→025). A cross-tenant / no-wr_access
  -- p_account_id fails closed here.
  insert into pfin.account_trans
    (account_id, transaction_date, amount, vendor, description, transaction_type)
  values
    (p_account_id, p_transaction_date, p_amount, p_vendor, p_description, 'standard')
  returning trans_id into v_trans_id;

  -- (2) The category / note overlay on the 023 MUTABLE annotation (1:1, PK=trans_id).
  -- Only when the caller supplied a category or a note — an uncategorized entry is
  -- Unsorted-pending (no annotation row; the user categorizes later via a 023 UPDATE).
  -- The #10 chain-resolved matched-tenant fence + the 030 trade-constraints fence fire
  -- BEFORE INSERT WHEN sub_cat_id IS NOT NULL: a cross-tenant Sub-Cat, or a Trade-cat on a
  -- cash (security_id NULL) row, fails closed even through this RPC (defense-in-depth).
  -- ata_insert wr_access-JOIN (023, aal2-claused via 025) is satisfied in THIS same txn by
  -- the row (1) just created under the caller's wr_access.
  if p_sub_cat_id is not null or p_note is not null then
    insert into pfin.account_trans_annotation (trans_id, sub_cat_id, note)
    values (v_trans_id, p_sub_cat_id, p_note);
  end if;

  return v_trans_id;
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke (denies anon, which is in PUBLIC),
-- then grant to authenticated only. The manual-entry path is authenticated-tier.
revoke execute on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text) from public;
grant execute on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text) to authenticated;

comment on function pfin.fn_create_manual_trans(bigint, date, numeric, text, text, bigint, text) is
  'SECURITY INVOKER write-composition RPC (SELF-202 §2.4.3.a; ADR-032). Atomically creates a '
  'manual cash account_trans row (transaction_type=''standard''; cash shape security_id NULL + '
  'quantity 0 default → satisfies the 017 CHECK; source_provider/provider_txn_id/import_hash NULL — manual '
  'origin; is_reverse false; replaces_trans_id NULL) and, WHEN p_sub_cat_id or p_note is '
  'supplied, its 023 category/note annotation, in ONE transaction under the caller''s RLS, '
  'RETURNING the new trans_id. The cash sibling of 013''s fn_create_manual_account. All fences '
  'evaluate as the caller (INVOKER): account_trans_insert wr_access-JOIN (006) + ata_insert '
  'wr_access-JOIN (023) — BOTH aal2-backstop-claused (025), so aal2 step-up is enforced through '
  'the RPC with NO in-function aal-check; the #10 chain-resolved matched-tenant fence + the 030 '
  'trade-constraints fence (cross-tenant/Trade-on-cash Sub-Cat fails closed); the 014 NaN CHECK. '
  'NOT a DEFINER allowlist entry — needs no elevation (allowlist unchanged, 4 labeled / 3 '
  'authored). Needs NO service_role (anon-key client + RLS + INVOKER). set search_path='''' '
  'injection fence; all refs schema-qualified. EXECUTE revoked from PUBLIC, granted to '
  'authenticated only (anon denied). Adds no FK-shaped column — Decision 3 family unchanged. '
  'Edits are NOT handled here (fact edit = 004 reverse-and-replace, app-layer: on a provider-sourced '
  'row the source_provider/provider_txn_id (+ import_hash) stay on the ORIGINAL only, the reverse + '
  'replacement rows carry NULL — avoids the 017 account_trans_provider_dedup_idx collision; category/note '
  'edit = 023 UPDATE). NO skip/exclusion (ADR-032). '
  'Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023).';
