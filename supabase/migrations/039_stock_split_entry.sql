-- ============================================================================
-- Migration: stock-split entry — the corp_action book-neutrality guard +
--   pfin.fn_create_stock_split, a SECURITY INVOKER write-composition RPC that records
--   a book-neutral stock split as ONE corp_action account_trans row (POSITION-LEVEL)
--   that restates quantity via 019's roll-forward while leaving book value untouched.
--   SELF-203 (§2.4.3 event entry, re-scoped to stock-split-only per ADR-033 Decision 2).
--   F/CTO-ratified 2026-07-26: OWD-1 → POSITION-LEVEL (option C; per-lot deferred — no
--   lot_parent_trans_id, no new Decision-3 instance); OWD-2 → SINGLE-ACCOUNT-per-call.
--   Design memo temp/039-stock-split-design.md.
--
-- WHAT THIS DOES:
--   (1) CHECK account_trans_corp_action_shape on pfin.account_trans — a corp_action row
--       is BOOK-NEUTRAL: coalesce(amount,0)=0 AND coalesce(cost_basis,0)=0. quantity is
--       UNCONSTRAINED (it carries the split's share delta). NULL-safe (cost_basis is
--       nullable/no-default, 017 — a book-neutral split leaves it NULL; without coalesce,
--       `cost_basis=0` is NULL and the CHECK would pass-by-NULL, a silent gap). This is
--       the ADR-033 Decision 2 binding book-neutrality AC. Role-agnostic table CHECK
--       (service_role bypasses RLS, not CHECKs). Mirrors 034's account_trans_basis_adjust_
--       shape. Consequence: "corp_action ⟹ book-neutral" becomes a V1 DB invariant —
--       substantive corp_actions (spin-off / cash-in-lieu, amount≠0 or cost_basis≠0) are
--       blocked here (consistent with ADR-033 deferring them; relaxing later is additive,
--       ADR-022). Safe to add: NO live corp_action row is non-book-neutral (audited — the
--       two test-suite corp_action inserts, 030 (1b) + 034 t_ca, are amount=0/cost_basis
--       NULL → pass; 035/037 insert no corp_action).
--   (2) pfin.fn_create_stock_split(p_account_id, p_security_id, p_ratio_num, p_ratio_den,
--       p_ex_date) — SECURITY INVOKER write-composition RPC (Lock 11; mirrors
--       fn_create_manual_trans/_account). Resolves the caller's position as-of ex-date via
--       fn_holdings_as_of (019), computes delta = position_qty × (ratio_num/ratio_den − 1),
--       and INSERTs ONE book-neutral corp_action account_trans row (amount=0, cost_basis
--       NULL, security_id set, quantity=delta, transaction_date=ex_date) + its 023
--       annotation (sub_cat_id NULL, metadata {action:'split', ratio_num, ratio_den,
--       ex_date}). Returns the new trans_id.
--
-- Numbering: 039 follows 038 (manual_trans + split write, SELF-202). Depends on 004
--   (account_trans immutable ledger — the INSERT target + the CHECK host; INSERT is NOT
--   blocked by the 004 UPDATE/DELETE/TRUNCATE triple-fence), 012 (transaction_type column
--   text NOT NULL DEFAULT 'standard' — set explicitly here), 017 (security_id / quantity
--   numeric(28,8) NOT NULL DEFAULT 0 / cost_basis nullable + the #7 security fence
--   fn_account_trans_security_asset the corp_action INSERT EXERCISES), 019 (fn_holdings_as_of
--   — the roll-forward position read), 023 (account_trans_annotation — the overlay INSERT),
--   030 (the corp_action vocab CHECK value + metadata jsonb column + the Trade biconditional
--   that WHEN-skips a NULL-cat row), 015 (account.linked_source_id — the source-of-truth
--   guard), 003 (pfin.account — ownership + the linked_source_id read), 001 (pfin schema).
--   No downstream migration depends on 039.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default, Lock 11); NOT SECURITY DEFINER. The
--   DEFINER allowlist STAYS 4 (3 authored — fn_refresh_updated_at @001, fn_grant_creator_
--   access @003, fn_reclass_history_insert @031 — + 1 reserved). fn_create_stock_split
--   composes ENTIRELY under the caller's RLS and needs NO elevated privilege:
--     - the account read (linked_source_id / existence) is direct-owner RLS (003);
--     - fn_holdings_as_of (019) is itself INVOKER → runs as the caller, caller-scoped;
--     - the account_trans INSERT is gated by the caller's account_trans_insert WITH CHECK
--       (wr_access-JOIN, 006) + the #7 security fence + the new corp_action-shape CHECK;
--     - the annotation INSERT is gated by the 023 write policy.
--   A cross-tenant caller sees no account / no holdings and cannot INSERT (RLS + #7 fence
--   fail closed). set search_path='' is the privesc fence. DEFINER would BREAK this (it
--   would let a caller restate another tenant's holdings) — INVOKER is load-bearing. The
--   CHECK is a role-agnostic table constraint (not a function) → no posture question.
--   → DEFINER allowlist UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) This migration
--   introduces ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: a table CHECK + a single authenticated-tier INVOKER RPC — no
--         infrastructure-credential-presence surface (RT-22 = PDF-worker container), no
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist surface (RT-26 = source grep
--         fence), no network-exposure/config admission surface (RT-27 = the app→worker
--         credential-admission endpoint). No service_role grant, no credential, no admission
--         channel. Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 039 is not the anchor.
--   DE-CONFLATION GUARD: the corp_action-shape CHECK is a value/book-neutrality invariant,
--   NOT a §10 catalogued instance and NOT a Decision-3 instance.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +0 (UNCHANGED). This
--   migration adds NO FK-shaped reference column:
--     - the corp_action-shape CHECK is a value-domain constraint on existing columns.
--     - fn_create_stock_split INSERTs a row carrying an EXISTING FK (account_trans.
--       security_id) → it EXERCISES the already-realized #7 fence (fn_account_trans_
--       security_asset, 017), it does not add a new one. POSITION-LEVEL granularity means
--       NO lot-linkage column (lot_parent_trans_id) is added → the per-lot new-Decision-3
--       instance the feasibility pass flagged is NOT incurred (per-lot deferred, F/CTO
--       2026-07-26). The linked_source_id read is a guard read, not a reference column.
--   Family count UNCHANGED. Verify the live labeled/DDL-realized count against ADR-011
--   Decision 3 at joint-review; 039 contributes none.
--
-- ----------------------------------------------------------------------------
-- SOURCE-OF-TRUTH GUARD (DB-level; flagged for CONTRACT — F/CTO OWD-2 rationale). Manual
--   split entry is ONLY for accounts the user is source-of-truth for. A Plaid/provider-
--   linked account's splits arrive via the reconciliation path (SELF-204), NOT manual
--   fan-in — else the manual restatement and the provider's eventual split report DOUBLE-
--   count. Enforcement level (Architect recommendation, ratify-delegated): DB-LEVEL guard
--   in the RPC — reject if pfin.account.linked_source_id IS NOT NULL. Rationale: house
--   discipline is "the UI is not the integrity boundary — the DB is" (ADR-031 Amendment 1
--   §2b; the 030 Trade trigger). The guard is one read on the already-resolved account and
--   is defense-in-depth beneath the app layer. App-layer SHOULD ALSO restrict (Frontend:
--   only source-of-truth accounts selectable; Backend Zod) for UX — but the DB guard is the
--   integrity boundary. This is a behavior → stated in the CONTRACT.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans (constraint account_trans_corp_action_shape) — CHECK: a corp_action
--     row is book-neutral (coalesce(amount,0)=0 AND coalesce(cost_basis,0)=0); quantity
--     unconstrained (the split delta). Role-agnostic. Blocks substantive corp_action in V1
--     (relax additively when a substantive-corp_action spec lands).
--   pfin.fn_create_stock_split(p_account_id bigint, p_security_id bigint, p_ratio_num
--     numeric, p_ratio_den numeric, p_ex_date date) RETURNS bigint (the new corp_action
--     trans_id) — SECURITY INVOKER, plpgsql, set search_path=''. Behavior:
--       (a) validate p_ratio_num > 0 AND p_ratio_den > 0 (else raise) — a positive rational
--           ratio; forward split num/den>1, reverse split num/den<1. Both book-neutral.
--       (b) resolve the account: read pfin.account (own row under RLS). NOT found → raise
--           (not owned/visible). SOURCE-OF-TRUTH GUARD: linked_source_id IS NOT NULL → raise
--           (provider-linked → splits via SELF-204 reconciliation, not manual entry).
--       (c) resolve the position: quantity from fn_holdings_as_of(p_ex_date) for
--           (p_account_id, p_security_id). No live position (0/none) → raise (nothing to
--           split).
--       (d) delta = position_qty × (p_ratio_num/p_ratio_den − 1). delta = 0 (ratio 1:1) →
--           raise (no-op). Fractional delta allowed (quantity is numeric(28,8)); cash-in-
--           lieu is OUT of scope (substantive → blocked by the shape CHECK; the SELF-204
--           path).
--       (e) INSERT ONE account_trans corp_action row: account_id, transaction_date=ex_date,
--           amount=0, transaction_type='corp_action', security_id=p_security_id,
--           quantity=delta, description='Stock split <num>:<den>'. → fires the #7 security
--           fence + the corp_action-shape CHECK. cost_basis left NULL (book-neutral).
--       (f) INSERT the 023 annotation: trans_id=new, sub_cat_id=NULL (structural, NULL-cat →
--           the 030 Trade biconditional WHEN-skips it), metadata=jsonb {action:'split',
--           ratio_num, ratio_den, ex_date}.
--       (g) RETURN the new trans_id.
--     Idempotency = app-layer confirm + reverse-and-replace (004); NO DB uniqueness guard
--     (it would block legit same-day corp actions and couple the ledger to overlay metadata).
--   Security-load-bearing edges: INVOKER (cross-tenant → no account/holdings, cannot INSERT
--     — RLS + #7 fence fail closed); the source-of-truth guard blocks double-restatement of a
--     provider-linked account; book-neutrality enforced by the CHECK (not the RPC alone — a
--     role-agnostic backstop). EXECUTE revoked from public, granted to authenticated only.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) corp_action book-neutrality CHECK (ADR-033 Decision 2 binding AC). NULL-safe.
--     Idempotent: drop-if-exists then add under the canonical name. Adds cleanly — no live
--     non-book-neutral corp_action row exists (audited).
-- ----------------------------------------------------------------------------
alter table pfin.account_trans
  drop constraint if exists account_trans_corp_action_shape;

alter table pfin.account_trans
  add constraint account_trans_corp_action_shape
    check (transaction_type <> 'corp_action'
           or (coalesce(amount, 0) = 0 and coalesce(cost_basis, 0) = 0));

comment on constraint account_trans_corp_action_shape on pfin.account_trans is
  'A corp_action row is BOOK-NEUTRAL: coalesce(amount,0)=0 AND coalesce(cost_basis,0)=0 '
  '(ADR-033 Decision 2 binding AC; SELF-203). quantity is UNCONSTRAINED — it carries the '
  'stock-split share delta (fn_create_stock_split). NULL-safe: cost_basis is nullable/no-'
  'default (017), so a book-neutral split leaves it NULL; coalesce reads NULL as book-neutral '
  '(a naive `cost_basis=0` is NULL → passes-by-NULL, a silent gap) and still hard-rejects any '
  'nonzero. Role-agnostic table CHECK (service_role bypasses RLS, not CHECKs). Mirrors 034 '
  'account_trans_basis_adjust_shape. Makes "corp_action ⟹ book-neutral" a V1 DB invariant — '
  'substantive corp_actions (spin-off / cash-in-lieu; amount≠0 or cost_basis≠0) are blocked '
  'here (ADR-033 defers them; relaxing later is an additive CHECK alter, ADR-022). 035/037 P9 '
  'stays book-neutral-drop under this invariant.';

-- ----------------------------------------------------------------------------
-- (2) fn_create_stock_split — SECURITY INVOKER write-composition RPC (Lock 11). Records a
--     POSITION-LEVEL book-neutral stock split (one corp_action row + its 023 annotation).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_create_stock_split(
  p_account_id  bigint,
  p_security_id bigint,
  p_ratio_num   numeric,
  p_ratio_den   numeric,
  p_ex_date     date
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_linked_source_id bigint;
  v_position_qty     numeric;
  v_delta            numeric;
  v_new_trans_id     bigint;
begin
  -- (a) Validate the ratio: a positive rational. Forward split num/den>1 (delta>0);
  --     reverse split num/den<1 (delta<0, position shrinks but stays >0). Both book-neutral.
  if p_ratio_num is null or p_ratio_den is null
     or p_ratio_num <= 0 or p_ratio_den <= 0 then
    raise exception
      'stock split: ratio must be a positive rational (got %:%) (SELF-203)',
      p_ratio_num, p_ratio_den;
  end if;

  -- (b) Resolve the account under the caller's RLS (direct-owner). NOT found → not owned /
  --     not visible → fail closed. SOURCE-OF-TRUTH GUARD: a provider-linked account's splits
  --     arrive via SELF-204 reconciliation, never manual fan-in (else double-restatement).
  select a.linked_source_id
    into v_linked_source_id
    from pfin.account a
   where a.account_id = p_account_id;

  -- Use the FOUND special variable (reliably false on a no-row SELECT INTO). A multi-target
  -- INTO would set a boolean flag to NULL on no-match, making `if not <flag>` dead (QA 039
  -- battery finding) — FOUND is the correct primitive.
  if not found then
    raise exception
      'stock split: account % not found or not visible under current RLS — fail closed (SELF-203)',
      p_account_id;
  end if;

  if v_linked_source_id is not null then
    raise exception
      'stock split: account % is provider-linked (linked_source_id %) — a linked account''s splits arrive via reconciliation (SELF-204), not manual entry, to avoid double restatement (SELF-203)',
      p_account_id, v_linked_source_id;
  end if;

  -- (c) Resolve the position as-of ex-date (INVOKER roll-forward, caller-scoped). No live
  --     position → nothing to split → fail closed.
  select h.quantity
    into v_position_qty
    from pfin.fn_holdings_as_of(p_ex_date) h
   where h.account_id = p_account_id
     and h.asset_id   = p_security_id;

  if v_position_qty is null or v_position_qty = 0 then
    raise exception
      'stock split: no live position for security % in account % as of % — nothing to split (SELF-203)',
      p_security_id, p_account_id, p_ex_date;
  end if;

  -- (d) delta = position_qty × (ratio − 1). A 1:1 ratio is a no-op → reject.
  v_delta := v_position_qty * ((p_ratio_num / p_ratio_den) - 1);

  if v_delta = 0 then
    raise exception
      'stock split: ratio %:% yields a zero delta on % shares — no-op (SELF-203)',
      p_ratio_num, p_ratio_den, v_position_qty;
  end if;

  -- (e) INSERT the book-neutral corp_action fact (amount=0, cost_basis NULL, quantity=delta).
  --     Fires the #7 security fence (fn_account_trans_security_asset, 017) + the
  --     account_trans_corp_action_shape CHECK; passes the caller's account_trans_insert RLS.
  insert into pfin.account_trans
    (account_id, transaction_date, amount, transaction_type, security_id, quantity, description)
  values
    (p_account_id, p_ex_date, 0, 'corp_action', p_security_id, v_delta,
     'Stock split ' || p_ratio_num::text || ':' || p_ratio_den::text)
  returning trans_id into v_new_trans_id;

  -- (f) INSERT the 023 overlay annotation. sub_cat_id NULL (structural, NULL-cat → the 030
  --     Trade biconditional WHEN (new.sub_cat_id IS NOT NULL) skips it). metadata carries the
  --     split provenance (ADR-031 Amendment 1 — corp_action detail on the mutable overlay).
  insert into pfin.account_trans_annotation (trans_id, sub_cat_id, metadata)
  values (
    v_new_trans_id,
    null,
    jsonb_build_object(
      'action',    'split',
      'ratio_num', p_ratio_num,
      'ratio_den', p_ratio_den,
      'ex_date',   p_ex_date
    )
  );

  -- (g) Return the new corp_action trans_id (Backend uses it for confirmation / reversal).
  return v_new_trans_id;
end;
$$;

revoke execute on function pfin.fn_create_stock_split(bigint, bigint, numeric, numeric, date) from public;
grant execute on function pfin.fn_create_stock_split(bigint, bigint, numeric, numeric, date) to authenticated;

comment on function pfin.fn_create_stock_split(bigint, bigint, numeric, numeric, date) is
  'SECURITY INVOKER write-composition RPC recording a POSITION-LEVEL book-neutral stock '
  'split (SELF-203; ADR-033 Decision 2; Lock 11 — mirrors fn_create_manual_trans). Resolves '
  'the caller''s position as-of p_ex_date via fn_holdings_as_of (019), computes delta = '
  'position_qty × (ratio_num/ratio_den − 1), and INSERTs ONE corp_action account_trans row '
  '(amount=0, cost_basis NULL, security_id set, quantity=delta, transaction_date=ex_date) + '
  'its 023 annotation (sub_cat_id NULL, metadata {action:split, ratio_num, ratio_den, '
  'ex_date}). Returns the new trans_id. The quantity delta restates holdings via 019''s roll-'
  'forward; the row is book-neutral so fn_gl_entries emits ZERO rows for it (P1/P2 skip, P9 '
  'evaluates to 0 & drops). SINGLE-ACCOUNT per call (OWD-2); POSITION-LEVEL (OWD-1 → C, per-'
  'lot deferred — no lot-linkage FK, no new Decision-3). SOURCE-OF-TRUTH GUARD: rejects a '
  'provider-linked account (linked_source_id NOT NULL) — those splits arrive via SELF-204 '
  'reconciliation (no double-restatement). Validates a positive-rational ratio; rejects a '
  'no-op (delta=0) and an empty position; fractional delta allowed (cash-in-lieu OUT of scope '
  '— substantive, blocked by the shape CHECK). INVOKER: account read direct-owner, '
  'fn_holdings_as_of caller-scoped, INSERTs gated by account_trans_insert wr_access + the #7 '
  'security fence + the corp_action-shape CHECK (cross-tenant fails closed). Idempotency = '
  'app-layer confirm + reverse-and-replace (004); NO DB uniqueness guard. set search_path='''' '
  '— NOT a DEFINER allowlist entry (INVOKER; allowlist stays 4). §10 stays 3; Decision-3 '
  'unchanged (exercises the existing #7 fence, adds no FK column). EXECUTE authenticated only.';
