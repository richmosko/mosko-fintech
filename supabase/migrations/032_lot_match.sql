-- ============================================================================
-- Migration: pfin.lot_match — append-only, immutable securities lot-matching
--   junction (which buy lot(s) a sell closes, and how much of each). M1-evt Slice B
--   (SELF-293) — the last M1-evt piece; realizes the Decision-3 forward-flagged
--   lot-matching buy-reference fence (`#14`).
-- Phase 6 Build Loop. F/CTO-ratified 2026-07-24 (all 5 Slice B decisions). Design
--   paper temp/self-293-slice-b-lot-match-design.md. ADR-031 Decision 7 M1-evt cond 4
--   + Decision 8 (the lot-match FK stands as a self-referential tenant-scoped D3
--   instance) + Sec Condition A (orthogonal to the Cat-carried open/close designation).
--
-- WHAT THIS DOES:
--   Creates pfin.lot_match — a MANY-TO-MANY junction over pfin.account_trans: a sell
--   trade closes portions of one-or-more buy lots (partial lots), and a buy lot is
--   closed across one-or-more sells. Realized APPEND-ONLY IMMUTABLE (mirror 004/031):
--   a re-match inserts a NEW match_seq batch (never an UPDATE); the "current" match
--   for a sell = the latest match_seq batch (DERIVED — read by M4-GL / the tax-compute
--   consumer). This append-only shape IS the lot-match reclassification-history
--   (self-versioning; see (4-B) below) — the accumulation of match_seq batches
--   preserves every matching ever asserted (ADR-011 Decision 2).
--
--   RATIFIED shape (5 Slice B decisions):
--     (1) WRITE-DORMANT (M2.5/029 pattern): the table + the #14 fence + the
--         immutability fences land NOW; the matching write/inference logic (FIFO/LIFO
--         auto-match or a specific-lot selection UI) + the INSERT grant land with the
--         consumer (M4-GL). Lot-matching is a POST-import inference (position inference
--         you lack at import) → land-anytime, no import imprint.
--     (2) Model (b): a many-to-many junction, append-only immutable (a 1:1 column
--         cannot express partial/multi-lot matching, which drives per-lot holding-
--         period ST/LT + realized-gain character).
--     (3) Decision-3 #14 fence (below): matched-TENANT (non-negotiable) + matched-
--         SECURITY (correctness), BEFORE INSERT (immutable → INSERT-only, like #2).
--     (4-B) SELF-VERSIONING — NO 031 change. See the (4-B) note below.
--
-- Numbering: 032 follows 031. Depends on 004/017 (account_trans — the sell/buy trans
--   the FKs reference + security_id/quantity the fence reads), 003 (account — the
--   users_id the fence chain-resolves), 006 (account_users rd_access-JOIN for the read
--   policy), and 001 (pfin schema). No downstream migration depends on 032.
--
-- ----------------------------------------------------------------------------
-- (4-B) SELF-VERSIONING — this SUPERSEDES the A2 "add-lot-match-column-to-031"
--   expectation (recorded in the 031 header comment + the A2 design paper). Rationale:
--   031 versions the 023 overlay's PER-TRANSACTION column state (sub_cat_id + metadata)
--   keyed on trans_id — but lot-match is a MANY-TO-MANY SET per sell, NOT a column, so
--   it cannot be a 031 per-txn snapshot column. Instead, the append-only lot_match
--   table + match_seq IS its own reclassification-history (ADR-011 Decision 2 self-
--   versioning; corrections = a new match_seq batch, every version preserved). So
--   pfin.fn_reclass_history_insert (031) is UNTOUCHED, and — unlike 031, whose DEFINER
--   capture existed only because history was a SIDE EFFECT of a 023 edit — lot_match
--   writes are DIRECT authenticated-INSERT under RLS (at M4-GL), like account_trans, so
--   NO DEFINER is needed. DEFINER allowlist STAYS 4.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO new SECURITY DEFINER (allowlist STAYS 4). Three functions are
--   authored, ALL SECURITY INVOKER:
--     - fn_lot_match_matched_tenant_security (the #14 fence) — reads the referenced
--       trans/account rows under the caller's RLS; needs no elevated privilege →
--       INVOKER. set search_path=''.
--     - fn_lot_match_block_mutation / _block_truncate (immutability) — touch nothing
--       (only raise); INVOKER, mirroring 004/031.
--   No updated_at trigger (immutable table — no UPDATE path). ZERO new DEFINER.
--   The DEFINER allowlist is UNCHANGED at 4 (fn_refresh_updated_at + fn_grant_creator_
--   access + fn_reclass_history_insert + the reserved general-audit-log helper).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) ZERO
--   catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence (RT-22), no
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26), no network-exposure/
--         config admission (RT-27) surface is touched — an append-only junction +
--         INVOKER fences, write-dormant, no service_role grant.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD: the #14 matched-tenant fence is a Decision-3 mechanism, NOT a
--   §10 catalogued instance.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +1 → provisional #14.
--   pfin.lot_match carries TWO FK-shaped columns, BOTH per-tenant references to
--   account_trans:
--     - sell_trans_id → account_trans(trans_id): the closing sell trade.
--     - buy_trans_id  → account_trans(trans_id): the buy lot being closed.
--   Neither is a "sole anchor" (unlike 023.trans_id) — a lot_match row references TWO
--   independent tenant-owned trades, and a PG FK is existence-only, so without a fence
--   a user could match their sell against ANOTHER tenant's buy — pulling that tenant's
--   cost basis into their realized-gain / tax computation (the exact chain attack
--   Decision 3 fences). REALIZED by fn_lot_match_matched_tenant_security (BEFORE INSERT
--   — INSERT-only because the table is append-only immutable, like the #2
--   replaces_trans_id fence on the immutable ledger).
--   COUNT: numbered **provisional #14**, covering BOTH FK columns via ONE matched-
--   tenant relationship (sell-tenant = buy-tenant) — analogous to the #1
--   reconciliation_event_trans two-FK-to-account_trans junction counted as one
--   instance. **Sec pins 1-vs-2 at joint-review; NOT overclaimed here.** Family delta
--   +1; folds into the ADR-011 Decision-3 BODY enumeration alongside #13 (029) at the
--   task-#8 fold-in. (#12 journal_group @ M2 stays reserved-unrealized.)
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 — pfin is [api]-exposed):
--   - RLS ENABLED. POLICY: lot_match_select ONLY — owner-only parent-chain α via
--     sell_trans_id → account_trans.account_id → account_users rd_access (the 023/031
--     read shape). Reading via the sell leg suffices: the #14 fence guarantees
--     sell-tenant = buy-tenant, so a row is only ever visible to its single owning
--     tenant. WRITE-DORMANT: NO insert/update/delete policy (writes default-denied at
--     BOTH the ACL layer — no write grant — and the RLS layer — no write policy). The
--     M4-GL matching-logic PR adds the INSERT grant + a wr_access WITH CHECK policy.
--   - GRANT: authenticated SELECT only. anon ZERO-grant (schema-usage denial).
--     service_role UNGRANTED.
--   - Ships with the paired QA two-tenant pgTAP battery (SECURITY §4.5): matched-tenant
--     BOTH directions (foreign sell × own buy, own sell × foreign buy) → RAISE;
--     matched-security (AAPL sell × MSFT buy) → RAISE; same-tenant same-security → OK;
--     append-only immutability all-roles; write-dormant grant-layer denial; NULL-safe
--     fail-closed. QA authors it; Sec sign-off gates.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.lot_match — append-only many-to-many securities lot-matching junction.
--     - id (bigint identity PK).
--     - sell_trans_id (bigint NOT NULL → account_trans(trans_id) ON DELETE RESTRICT):
--       the closing sell. Decision-3 #14 (matched-tenant, chain-resolved).
--     - buy_trans_id (bigint NOT NULL → account_trans(trans_id) ON DELETE RESTRICT):
--       the buy lot being closed. Decision-3 #14 (matched-tenant + matched-security).
--     - quantity_matched (numeric NOT NULL, >0, finite): shares of the buy lot closed
--       by this sell in this batch.
--     - match_seq (int NOT NULL): the append-only re-match batch marker per sell. A
--       correction inserts a NEW match_seq batch; "current" = max(match_seq) per
--       sell_trans_id (derived, read by M4-GL). UNIQUE (sell_trans_id, buy_trans_id,
--       match_seq) — one row per sell/buy pairing per batch.
--     - created_at (timestamptz NOT NULL).
--   fn_lot_match_matched_tenant_security() — BEFORE INSERT; SECURITY INVOKER; set
--     search_path=''; NULL-safe fail-closed. Chain-resolves both trans' tenant +
--     security; requires sell-tenant = buy-tenant (Decision-3 #14, non-negotiable) AND
--     sell.security_id = buy.security_id (correctness; also both must be securities
--     trades — a NULL security_id fails closed).
--   fn_lot_match_block_mutation() / _block_truncate() — SECURITY INVOKER immutability
--     fences (mirror 004/031); raise on UPDATE/DELETE (row) + TRUNCATE (statement) all
--     roles. INSERT unblocked (the M4-GL matching write path).
--   Security-load-bearing edges: matched-tenant fails-closed (no cross-tenant basis
--     leak); append-only immutability (all roles, via triggers not RLS); write-dormant
--     (no write path until M4-GL); self-versioning (match_seq) = the lot-match audit
--     trail (no 031 change; DEFINER stays 4).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.lot_match — append-only many-to-many securities lot-matching junction.
-- ----------------------------------------------------------------------------
create table if not exists pfin.lot_match (
  id                bigint generated always as identity primary key,
  sell_trans_id     bigint not null
                      references pfin.account_trans (trans_id) on delete restrict,
  buy_trans_id      bigint not null
                      references pfin.account_trans (trans_id) on delete restrict,
  quantity_matched  numeric not null
                      constraint lot_match_quantity_matched_valid
                        check (quantity_matched > 0
                               and quantity_matched <> 'NaN'::numeric
                               and quantity_matched <> 'Infinity'::numeric),
  match_seq         integer not null,
  created_at        timestamptz not null default now(),
  unique (sell_trans_id, buy_trans_id, match_seq)
);

comment on table pfin.lot_match is
  'Append-only, immutable securities lot-matching junction (M1-evt Slice B / SELF-293; '
  'ADR-031 Decision 7 cond 4 / Decision 8). Many-to-many: a sell closes portions of '
  'one-or-more buy lots (partial lots), a buy closes across one-or-more sells — drives '
  'per-lot holding-period (ST/LT) + realized-gain character at M4-GL. APPEND-ONLY '
  'immutable (004/031-mirror triple-fence): a re-match inserts a NEW match_seq batch, '
  'never an UPDATE; "current" match = max(match_seq) per sell_trans_id (derived, read '
  'by M4-GL). This self-versioning IS the lot-match reclass-history (ADR-011 Decision 2) '
  '— it SUPERSEDES the A2 add-lot-match-column-to-031 expectation (a many-to-many set '
  'is not a per-txn column); fn_reclass_history_insert is untouched, DEFINER allowlist '
  'stays 4 (lot_match writes are direct authenticated-INSERT, not a side-effect '
  'capture). WRITE-DORMANT: authenticated SELECT only (owner-only parent-chain α via '
  'sell_trans_id); the matching write/inference logic + INSERT grant land at M4-GL. '
  'Carries the Decision-3 #14 matched-tenant fence (+ matched-security correctness); '
  'provisional #14 covering both FKs — Sec pins 1-vs-2. anon zero-grant; service_role '
  'ungranted. §10 stays 3; DEFINER stays 4.';

comment on column pfin.lot_match.sell_trans_id is
  'FK → account_trans(trans_id) ON DELETE RESTRICT — the closing sell trade. Per-tenant '
  'reference; Decision-3 #14 (matched-tenant, chain-resolved via account_trans → '
  'account). Also the read anchor for the RLS parent-chain policy.';
comment on column pfin.lot_match.buy_trans_id is
  'FK → account_trans(trans_id) ON DELETE RESTRICT — the buy lot being closed. '
  'Per-tenant reference; Decision-3 #14 (must share sell''s tenant — else another '
  'tenant''s cost basis leaks into this tenant''s tax compute) AND sell''s security '
  '(can''t close AAPL with an MSFT sell).';
comment on column pfin.lot_match.match_seq is
  'Append-only re-match batch marker per sell_trans_id. A correction inserts a NEW '
  'match_seq batch (the table is immutable — no UPDATE); "current" match = '
  'max(match_seq) per sell (derived, M4-GL reads it). This IS the lot-match self-'
  'versioning history (ADR-011 Decision 2). UNIQUE (sell_trans_id, buy_trans_id, '
  'match_seq).';

alter table pfin.lot_match enable row level security;

-- ----------------------------------------------------------------------------
-- RLS read — owner-only parent-chain α via the sell leg (023/031 shape). WRITE-DORMANT:
-- NO write policy (deferred to the M4-GL matching-logic PR). Reading via sell_trans_id
-- suffices — the #14 fence guarantees sell-tenant = buy-tenant.
-- ----------------------------------------------------------------------------
drop policy if exists lot_match_select on pfin.lot_match;
create policy lot_match_select on pfin.lot_match
  for select to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = lot_match.sell_trans_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy lot_match_select on pfin.lot_match is
  'Parent-FK-chain SELECT policy (023/006 shape): rd_access-JOIN via sell_trans_id → '
  'account_trans.account_id → account_users. A user reads a lot-match only for a sell '
  'on an account they hold rd_access on; the #14 fence guarantees the buy leg shares '
  'the tenant, so the sell leg is a sufficient anchor. WRITE-DORMANT — no write policy '
  '(the M4-GL matching PR adds a wr_access WITH CHECK insert policy).';

-- ACL-before-RLS (PR #106): SELECT grant only (write-dormant). anon zero; service_role
-- ungranted. The M4-GL matching PR adds the INSERT grant with its write policy.
grant select on pfin.lot_match to authenticated;

create index if not exists lot_match_sell_trans_id_idx on pfin.lot_match (sell_trans_id);
create index if not exists lot_match_buy_trans_id_idx on pfin.lot_match (buy_trans_id);

-- ----------------------------------------------------------------------------
-- Immutability triple-fence (mirror 004/031). SECURITY INVOKER — touch nothing (only
-- raise); NOT DEFINER allowlist entries. Blocks UPDATE/DELETE (row, all roles incl.
-- service_role) + TRUNCATE (statement). INSERT unblocked (the M4-GL matching path).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_lot_match_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.lot_match is immutable (append-only; ADR-011 Decision 2 / M1-evt Slice B). % blocked — a re-match lands as a NEW match_seq batch, never an in-place edit.', tg_op;
end;
$$;

revoke execute on function pfin.fn_lot_match_block_mutation() from public;

comment on function pfin.fn_lot_match_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.lot_match (ADR-011 Decision 2; '
  'SELF-293 Slice B). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). '
  'raise (fail loud). Blocks UPDATE + DELETE all roles incl. service_role (bypasses RLS '
  'not triggers). INSERT unblocked. Corrections land as a new match_seq batch.';

create trigger lot_match_block_mutation
  before update or delete on pfin.lot_match
  for each row execute function pfin.fn_lot_match_block_mutation();

create or replace function pfin.fn_lot_match_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.lot_match is immutable (append-only; ADR-011 Decision 2 / M1-evt Slice B). TRUNCATE blocked — the lot-matching history cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_lot_match_block_truncate() from public;

comment on function pfin.fn_lot_match_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.lot_match (ADR-011 '
  'Decision 2; SELF-293 Slice B). SECURITY INVOKER (touches nothing). Closes the '
  'TRUNCATE bypass (row triggers do not fire on TRUNCATE) all roles regardless of grant. '
  'Message distinct from the row-level fence for QA test-matching.';

create trigger lot_match_block_truncate
  before truncate on pfin.lot_match
  for each statement execute function pfin.fn_lot_match_block_truncate();

revoke truncate on pfin.lot_match from public;

-- ----------------------------------------------------------------------------
-- Decision-3 #14 fence — matched-TENANT (non-negotiable) + matched-SECURITY
-- (correctness). BEFORE INSERT (append-only → INSERT-only, like #2). SECURITY INVOKER.
-- Chain-resolves both trans' owning tenant (trans_id → account_trans.account_id →
-- account.users_id) + security_id; requires sell-tenant = buy-tenant AND same security.
-- NULL-safe fail-closed (an unresolved/unreadable trans, or a NULL security_id on
-- either leg — i.e. a non-securities trade — raises).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_lot_match_matched_tenant_security()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sell_tenant   uuid;
  v_sell_security bigint;
  v_buy_tenant    uuid;
  v_buy_security  bigint;
begin
  -- Resolve the SELL leg's owning tenant + security (chain: trans → account).
  select acc.users_id, t.security_id
    into v_sell_tenant, v_sell_security
    from pfin.account_trans t
    join pfin.account acc on acc.account_id = t.account_id
   where t.trans_id = new.sell_trans_id;

  -- Resolve the BUY leg's owning tenant + security.
  select acc.users_id, t.security_id
    into v_buy_tenant, v_buy_security
    from pfin.account_trans t
    join pfin.account acc on acc.account_id = t.account_id
   where t.trans_id = new.buy_trans_id;

  -- NULL-SAFE FAIL-CLOSED: either leg unresolved/unreadable → raise.
  if v_sell_tenant is null or v_buy_tenant is null then
    raise exception
      'lot_match: cannot resolve sell (%) or buy (%) transaction tenant — fail-closed (ADR-011 Decision 3 #14; M1-evt Slice B / SELF-293)',
      new.sell_trans_id, new.buy_trans_id;
  end if;

  -- MATCHED-TENANT (Decision-3 #14, non-negotiable): a sell may only close a buy owned
  -- by the SAME tenant — else another tenant''s cost basis leaks into this tenant''s
  -- realized-gain / tax computation.
  if v_sell_tenant <> v_buy_tenant then
    raise exception
      'cross-tenant lot-match rejected: sell tenant % <> buy tenant % (ADR-011 Decision 3 #14 matched-tenant fence; M1-evt Slice B / SELF-293)',
      v_sell_tenant, v_buy_tenant;
  end if;

  -- MATCHED-SECURITY (correctness fold-in): a sell can only close a buy of the SAME
  -- security (can''t close AAPL with an MSFT sell). A NULL security_id on either leg
  -- means it is not a securities trade — fail closed.
  if v_sell_security is null or v_buy_security is null
     or v_sell_security <> v_buy_security then
    raise exception
      'lot-match security mismatch: sell security_id % and buy security_id % must be equal and non-null (a sell closes a buy of the same security; M1-evt Slice B / SELF-293)',
      v_sell_security, v_buy_security;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_lot_match_matched_tenant_security() from public;

comment on function pfin.fn_lot_match_matched_tenant_security() is
  'BEFORE INSERT Decision-3 #14 fence on pfin.lot_match (matched-TENANT non-negotiable '
  '+ matched-SECURITY correctness; M1-evt Slice B / SELF-293; ADR-031 Decision 7 cond 4 '
  '/ Decision 8). INSERT-only (the table is append-only immutable — like the #2 '
  'replaces_trans_id fence). Chain-resolves each leg''s owning tenant + security via '
  'trans_id → account_trans.account_id → account.users_id/security_id, then requires '
  'sell-tenant = buy-tenant (else another tenant''s basis leaks into this tenant''s tax '
  'compute — the chain attack Decision 3 fences) AND sell.security_id = buy.security_id '
  '(both non-null — a NULL security_id is a non-securities trade → fail closed). '
  'NULL-safe fail-closed. SECURITY INVOKER + set search_path='''' — not a DEFINER '
  'allowlist entry (stays 4). Covers BOTH FK columns via one matched-tenant '
  'relationship (provisional #14; Sec pins 1-vs-2 at joint-review). Sign-alignment '
  '(sell qty<0 / buy qty>0) is 030''s Trade-annotation job + the M4-GL matching logic, '
  'not this fence.';

create trigger lot_match_matched_tenant_security
  before insert on pfin.lot_match
  for each row execute function pfin.fn_lot_match_matched_tenant_security();
