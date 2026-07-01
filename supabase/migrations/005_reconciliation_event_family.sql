-- ============================================================================
-- Migration: pfin.reconciliation_event family — statement-blessed reconciliation
-- Phase 6 Build Loop (SELF-188 / V1.0 Platform foundation).
-- Lands the Lock 9 (ADR-011 Decision 13) reconciliation substrate: the three
-- audit-class tables + append-only RLS + cross-tier immutability fences + the
-- Decision-3 matched-account fence on the join table.
--
-- Numbering: 005 follows 001 (foundation) / 002 (fn_mask) / 003 (account +
-- account_users) / 004 (account_trans immutable). This ordering is REQUIRED:
-- pfin.reconciliation_event_trans junctions pfin.account_trans (event_id,
-- account_trans_id) per Decision 13 / Lock 9, so account_trans (004) is the
-- prerequisite. (Confirms the 004 header's "reconciliation renumbers to 005".)
--
-- SCOPE — V1.0 = SCHEMA-FENCE-ONLY SUBSTRATE (F/CTO DP-1 = Substrate-only ratify).
--   This migration CREATES: reconciliation_event + reconciliation_event_trans +
--   holdings_checkpoint, each with append-only RLS + the immutability triple-fence
--   (row-level UPDATE/DELETE block + statement-level TRUNCATE block + REVOKE
--   TRUNCATE), plus the Decision-3 matched-account BEFORE INSERT fence on the join.
--
--   DEFERRED to the V1.3 reconciliation-usage wave (F/CTO-ratified) — each blocked
--   on a dependency not present at V1.0, NOT on any posture conflict:
--     (a) holdings_checkpoint FAN-OUT trigger (reconciliation_event INSERT -> per-
--         asset checkpoint rows, reads NEW.* per Lock 9 F/CTO correction #5) — its
--         DEFINER-vs-INVOKER write-lock posture (DP-4) is drilled with Sec then.
--     (b) COST-BASIS CASCADE (fires on account_trans INSERT; `SELECT ... FOR UPDATE`
--         concurrency row-lock on the prior holdings_checkpoint row during the
--         composition walk, then INSERTs new checkpoint rows per Lock 9 mod #2 —
--         this is append-only-COMPATIBLE, not a contradiction). Deferred because it
--         requires account_trans investment columns (symbol/quantity/cost-basis)
--         that 004 deferred, and there is no securities-master table yet.
--     (c) NAV read-time composition (fn_compute_nav) — requires the pfin.eod_price
--         table, which does not exist yet (NAV is a read-time lookup, no stored col).
--   Rationale for deferral is strictly MISSING DEPENDENCIES (no eod_price; deferred
--   account_trans investment columns; no securities-master), by-construction.
--
-- COLUMN SET — naming sweep + drops per Lock 9. NO `_cents` suffix anywhere (money =
--   NUMERIC(20,4); quantity = NUMERIC(28,8) per DP-3 ratify). NO `is_plug` BOOLEAN
--   (Sub-Cat is the discriminator) and NO `mode VARCHAR(4)` (not load-bearing) —
--   both dropped per Lock 9. NO `source_event_id` provenance FK on holdings_checkpoint
--   (F/CTO-accepted conscious deferral — see Decision 3 eval below).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii)
--   layer-attribution — no infra-credential-presence (RT-22) or service_role-
--   allowlist (RT-26) surface is touched (this is an RLS/immutability table set +
--   a matched-account trigger). (iii) Decision 4 is linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0 (stays 7).
--   FK-shaped columns in this migration:
--   - reconciliation_event.account_id -> pfin.account: SOLE tenant anchor (this table
--     carries NO own users_id; scope derives via account_id -> account_users.rd_access-
--     JOIN, Decision 7 / Lock 3). No second anchor to mismatch -> NOT a Decision-3
--     instance (same reasoning as 004's account_id).
--   - holdings_checkpoint.account_id -> pfin.account: likewise SOLE anchor -> NOT a
--     Decision-3 instance. (No source_event_id FK is added: a checkpoint->event link
--     would be a NEW cross-tenant FK-shaped column requiring matched-account -> would
--     push the family 7->8. F/CTO ratified deferring it; provenance lands at V1.3 with
--     its own matched-account fence if wanted. Family stays 7 by construction.)
--   - reconciliation_event_trans (event_id, account_trans_id): this IS the ALREADY-
--     CATALOGUED Decision-3 instance (Lock 9 mod #1 — matched-account: the linked
--     account_trans must share the linked reconciliation_event's account_id). This
--     migration IMPLEMENTS the catalogued instance; it does NOT add one (family count
--     UNCHANGED — Sec-pinned at 7). NOTE: RT-17 / SD-18 canonical call this the "first
--     instance" — that is stale Phase-4 ordinal numbering; the operative fact is that
--     it is a CATALOGUED member of the family being realized here, not a new addition.
--   Decision 3's "WITH CHECK" wording is shorthand: a single-row CHECK cannot subquery
--   the two referenced rows, so the correct mechanism is a BEFORE INSERT trigger
--   (Decision 3 explicitly allows a trigger where PG cannot express the constraint
--   declaratively). "Trigger" here is the canonical realization, NOT a deviation.
--
-- ----------------------------------------------------------------------------
-- DECISION 2 / DECISION 13 — verbatim anchors.
--   Decision 13 / Lock 9: "Per-transaction explicit reconciliation via
--     pfin.reconciliation_event_trans join table (replaces date-range derivation);
--     statement-blessed values on reconciliation_event (statement_balance +
--     statement_quantity); multi-dimension
--     reconciliation support (single trans linked to multiple events); NAV via
--     eod_price lookup at read time (no stored NAV column); naming sweep drops _cents
--     suffix; trigger logic fix on holdings_checkpoint; drop denormalized flags
--     (is_plug BOOLEAN — Sub-Cat is discriminator; mode VARCHAR(4) — not load-bearing)."
--   Decision 13 Sec V1-SHIP-BLOCK: append-only RLS + matched-account (Decision 3).
--   Decision 2 (§7 immutable + INSERT-new-version audit-class discipline): edits are
--     new rows, never in-place mutation — the tables are tamper-proof audit trail.
--
-- POSTURE RATIONALE — ALL functions are SECURITY INVOKER (NOT DEFINER).
--   Zero new SECURITY DEFINER functions: the V1 DEFINER allowlist is UNCHANGED at 3
--   (ADR-011 Decision 9 — fn_refresh_updated_at + audit-log helper + fn_grant_creator_
--   access; authored so far = 2). The immutability blocks read/write nothing (they just
--   raise). The matched-account check's read composes correctly with the enforcement
--   stack, and the fail-closed LAYER differs by role. Under authenticated at THIS
--   migration: 004 grants authenticated NO privilege on pfin.account_trans (default-deny
--   posture — RLS enabled, NO table-level GRANT until SELF-190/B5), so the SECURITY
--   INVOKER trigger's account_trans read raises `permission denied for table
--   account_trans` at the TABLE-ACL layer (the PR #106 grant-then-RLS gotcha: ACL is
--   checked BEFORE RLS) — it fails closed here, before ever reaching the NOT-EXISTS
--   branch. So an authenticated INSERT into reconciliation_event_trans is blocked by
--   ACL, which is correct: reconciliation LINK usage is SELF-190-gated by construction
--   and lands at V1.3 (this authenticated path is revisited in the SELF-190 battery when
--   account_trans SELECT opens). The NOT-EXISTS matched-account check is the AUTHORITATIVE
--   path that runs under service_role (RLS-bypassed + grants held) — which is exactly what
--   QA exercises via privileged INSERT (same posture as 004's fn_account_trans_matched_account).
--   The cross-tier immutability fence requires a TRIGGER, not just RLS-default-deny:
--   service_role BYPASSES RLS but NOT triggers. TRUNCATE additionally bypasses ROW-level
--   triggers (fires only STATEMENT-level BEFORE TRUNCATE), so a separate statement-level
--   fence + a defensive REVOKE TRUNCATE close the audit-retention-wipe path. The fence
--   covers UPDATE + DELETE + TRUNCATE across ALL roles on all three tables.
--   DRY note: the audit family shares two immutability trigger functions
--   (fn_reconciliation_family_block_mutation + _block_truncate) rather than 004's
--   per-table functions — three near-identical audit-class tables warrant it. Raise
--   messages embed tg_table_name + tg_op so they stay per-table-distinct for QA
--   test-matching. Both are SECURITY INVOKER (touch nothing; not allowlist entries).
--
-- CONTRACT
--   pfin.reconciliation_event — append-only audit-class. statement-blessed values
--     (statement_balance money / statement_quantity share-grain) anchored by an
--     explicit dimension discriminator ('balance' | 'quantity') + a dimension->column
--     population CHECK. NO own users_id (account_users.rd_access-JOIN tenancy).
--     INSERT-only; UPDATE + DELETE + TRUNCATE blocked for ALL roles.
--   pfin.reconciliation_event_trans — append-only join (event_id, account_trans_id);
--     multi-dimension: one trans linkable to multiple events. RLS via PARENT
--     reconciliation_event FK-chain (decoupled from account_trans policy state).
--     Decision-3 matched-account BEFORE INSERT fence. INSERT-only; UPD/DEL/TRUNCATE
--     blocked for ALL roles.
--   pfin.holdings_checkpoint — append-only per-asset position snapshot. SOLE anchor
--     account_id (account_users.rd_access-JOIN read). SELECT + immutability fence land
--     now; the INSERT write path (fan-out trigger) + its posture (DP-4) DEFER to V1.3
--     (no authenticated INSERT grant here). UPD/DEL/TRUNCATE blocked for ALL roles.
--   pfin.fn_reconciliation_family_block_mutation() — BEFORE UPDATE OR DELETE (row);raises.
--   pfin.fn_reconciliation_family_block_truncate() — BEFORE TRUNCATE (statement);raises.
--   pfin.fn_reconciliation_event_trans_matched_account() — BEFORE INSERT; NULL-safe
--     fail-closed; rejects cross-account links. set search_path = ''.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- Shared audit-family immutability fences (SECURITY INVOKER; touch nothing).
-- Declared first so the per-table triggers below can reference them.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_reconciliation_family_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise, NOT return null — return null would silently no-op the row and
  -- read as "succeeded"). Blocks UPDATE + DELETE for ALL roles; service_role bypasses
  -- RLS but NOT triggers, so this — not RLS-default-deny — closes the privileged-context
  -- immutability gap (ADR-011 Decision 2 / Decision 13 append-only V1-SHIP-BLOCK).
  raise exception
    'pfin.% is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 9). % blocked — reconciliation history is tamper-proof; correct via INSERT-new-version.',
    tg_table_name, tg_op;
end;
$$;

revoke execute on function pfin.fn_reconciliation_family_block_mutation() from public;

comment on function pfin.fn_reconciliation_family_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence shared across the reconciliation audit family (reconciliation_event + reconciliation_event_trans + holdings_checkpoint) per ADR-011 Decision 2 / Decision 13 (Lock 9 append-only V1-SHIP-BLOCK). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (which bypasses RLS but not triggers). Raise message embeds tg_table_name + tg_op so it is per-table-distinct for QA test-matching. INSERT is unblocked.';

create or replace function pfin.fn_reconciliation_family_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE (Postgres runs it through
  -- STATEMENT-level BEFORE TRUNCATE triggers only), so a role holding TRUNCATE could wipe
  -- the immutable ledger without tripping the row-level fence. This closes that path.
  raise exception
    'pfin.% is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 9). TRUNCATE blocked — the reconciliation audit trail cannot be wiped.',
    tg_table_name;
end;
$$;

revoke execute on function pfin.fn_reconciliation_family_block_truncate() from public;

comment on function pfin.fn_reconciliation_family_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence shared across the reconciliation audit family per ADR-011 Decision 2 / Decision 13 (Lock 9). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Closes the TRUNCATE bypass: row-level triggers do NOT fire on TRUNCATE, so this statement-level trigger fences the audit-retention-wipe path for ALL roles regardless of grant state. Message distinct from the row-level fence for test-matching.';

-- ----------------------------------------------------------------------------
-- pfin.reconciliation_event — statement-blessed reconciliation (SD-16, HIGH).
-- Append-only audit-class. NO own users_id (account_users.rd_access-JOIN tenancy).
-- ON DELETE RESTRICT: reconciliation history is immutable audit; an account with
-- reconciliation events cannot be hard-deleted (consistent with 004 posture).
-- DP-2 ratify: explicit `dimension` discriminator + dimension->column CHECK.
-- ----------------------------------------------------------------------------
create table if not exists pfin.reconciliation_event (
  event_id            bigint generated always as identity primary key,
  account_id          bigint not null references pfin.account (account_id) on delete restrict,
  reconciliation_date date not null,
  dimension           text not null check (dimension in ('balance', 'quantity')),
  symbol              text,                              -- populated for 'quantity' (per-asset); NULL for 'balance'
  statement_balance   numeric(20,4),                     -- money grain; populated for 'balance'
  statement_quantity  numeric(28,8),                     -- share/crypto grain (DP-3); populated for 'quantity'
  created_at          timestamptz not null default now(),-- IMMUTABLE post-INSERT (no UPDATE allowed at all)
  constraint reconciliation_event_dimension_shape check (
    (dimension = 'balance'
       and statement_balance is not null
       and statement_quantity is null
       and symbol is null)
    or
    (dimension = 'quantity'
       and statement_quantity is not null
       and symbol is not null
       and statement_balance is null)
  )
);

comment on table pfin.reconciliation_event is
  'Statement-blessed reconciliation event (SD-16 HIGH; ADR-011 Decision 13 / Lock 9; SELF-188). Append-only audit-class: UPDATE + DELETE + TRUNCATE blocked for ALL roles (fn_reconciliation_family_block_mutation + _block_truncate); corrections via INSERT-new-version (Decision 2). NO own users_id — tenant scope derives via account_id -> account_users.rd_access-JOIN (Decision 7 / Lock 3). Explicit dimension discriminator (balance | quantity) with a dimension->column population CHECK (DP-2): balance events carry statement_balance; quantity events carry statement_quantity + symbol (per-asset). Multi-dimension reconciliation (one trans linked to multiple events) is modeled by the reconciliation_event_trans join. NO is_plug / mode (dropped per Lock 9); NO _cents naming (money = NUMERIC(20,4), quantity = NUMERIC(28,8)). NAV is NOT stored — computed at read time via eod_price (DEFERRED, no eod_price table yet).';

alter table pfin.reconciliation_event enable row level security;

-- Append-only RLS: SELECT via rd_access-JOIN, INSERT via wr_access-JOIN. NO UPDATE/DELETE
-- policies (immutability enforced at policy AND trigger layer — defense in depth).
create policy reconciliation_event_select on pfin.reconciliation_event
  for select to authenticated
  using (exists (
    select 1 from pfin.account_users au
    where au.account_id = reconciliation_event.account_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));
create policy reconciliation_event_insert on pfin.reconciliation_event
  for insert to authenticated
  with check (exists (
    select 1 from pfin.account_users au
    where au.account_id = reconciliation_event.account_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on.
-- SELECT + INSERT only — append-only (no UPDATE/DELETE grant).
grant select, insert on pfin.reconciliation_event to authenticated;

create index if not exists reconciliation_event_account_id_idx
  on pfin.reconciliation_event (account_id);
create index if not exists reconciliation_event_account_date_idx
  on pfin.reconciliation_event (account_id, reconciliation_date);

create trigger reconciliation_event_block_mutation
  before update or delete on pfin.reconciliation_event
  for each row execute function pfin.fn_reconciliation_family_block_mutation();
create trigger reconciliation_event_block_truncate
  before truncate on pfin.reconciliation_event
  for each statement execute function pfin.fn_reconciliation_family_block_truncate();
revoke truncate on pfin.reconciliation_event from public;

-- ----------------------------------------------------------------------------
-- pfin.holdings_checkpoint — per-asset position snapshot (SD-17, medium).
-- Append-only. SOLE anchor account_id (account_users.rd_access-JOIN read).
-- SUBSTRATE ONLY at V1.0: SELECT policy + immutability fence land now; the INSERT
-- write path (fan-out trigger from reconciliation_event) + its DEFINER-vs-INVOKER
-- posture (DP-4) DEFER to the V1.3 reconciliation-usage wave — NO authenticated
-- INSERT grant/policy here (declining to prejudge DP-4). Inert (no writer) like
-- account_trans was pre-SELF-190.
-- ----------------------------------------------------------------------------
create table if not exists pfin.holdings_checkpoint (
  checkpoint_id bigint generated always as identity primary key,
  account_id    bigint not null references pfin.account (account_id) on delete restrict,
  symbol        text not null,                          -- per-asset (TEXT; securities-master FK deferred to V2)
  as_of_date    date not null,
  quantity      numeric(28,8) not null,                 -- share/crypto grain (DP-3)
  balance       numeric(20,4),                          -- per-asset money balance snapshot
  created_at    timestamptz not null default now()      -- IMMUTABLE post-INSERT
);

comment on table pfin.holdings_checkpoint is
  'Per-asset holdings/position snapshot at a reconciliation moment (SD-17 medium; ADR-011 Decision 13 / Lock 9; SELF-188). Append-only audit-class: UPDATE + DELETE + TRUNCATE blocked for ALL roles. SOLE tenant anchor account_id (NOT a Decision-3 instance; NO source_event_id provenance FK — declined to hold the family at 7). Read scope via account_id -> account_users.rd_access-JOIN. SUBSTRATE ONLY: SELECT + immutability fence land at V1.0; the fan-out INSERT write path (reconciliation_event trigger reading NEW.* per Lock 9 F/CTO correction #5) + the cost-basis cascade (SELECT ... FOR UPDATE row-lock then INSERT — append-only-compatible) DEFER to V1.3 (blocked on deferred account_trans investment columns + no securities-master + no eod_price for NAV). quantity = NUMERIC(28,8), balance = NUMERIC(20,4); NO _cents naming.';

alter table pfin.holdings_checkpoint enable row level security;

-- Append-only READ substrate: SELECT via rd_access-JOIN. NO INSERT/UPDATE/DELETE
-- policy — the writer (fan-out trigger) + its DP-4 posture land at V1.3.
create policy holdings_checkpoint_select on pfin.holdings_checkpoint
  for select to authenticated
  using (exists (
    select 1 from pfin.account_users au
    where au.account_id = holdings_checkpoint.account_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

-- SELECT-only GRANT (ACL-before-RLS). NO write grant in the V1.0 substrate.
grant select on pfin.holdings_checkpoint to authenticated;

create index if not exists holdings_checkpoint_account_id_idx
  on pfin.holdings_checkpoint (account_id);
create index if not exists holdings_checkpoint_account_asset_idx
  on pfin.holdings_checkpoint (account_id, as_of_date, symbol);

create trigger holdings_checkpoint_block_mutation
  before update or delete on pfin.holdings_checkpoint
  for each row execute function pfin.fn_reconciliation_family_block_mutation();
create trigger holdings_checkpoint_block_truncate
  before truncate on pfin.holdings_checkpoint
  for each statement execute function pfin.fn_reconciliation_family_block_truncate();
revoke truncate on pfin.holdings_checkpoint from public;

-- ----------------------------------------------------------------------------
-- pfin.reconciliation_event_trans — append-only join (SD-18, medium).
-- RLS via PARENT reconciliation_event FK-chain (Lock 12 pattern) — deliberately
-- decoupled from account_trans policy state (account_trans is default-deny-all
-- until SELF-190). Decision-3 matched-account fence on (event_id, account_trans_id).
-- ----------------------------------------------------------------------------
create table if not exists pfin.reconciliation_event_trans (
  id                bigint generated always as identity primary key,
  event_id          bigint not null references pfin.reconciliation_event (event_id) on delete restrict,
  account_trans_id  bigint not null references pfin.account_trans (trans_id) on delete restrict,
  created_at        timestamptz not null default now(),  -- IMMUTABLE post-INSERT
  unique (event_id, account_trans_id)
);

comment on table pfin.reconciliation_event_trans is
  'Reconciliation event <-> account_trans join (SD-18 medium; ADR-011 Decision 13 / Lock 9; SELF-188). Append-only: UPDATE + DELETE + TRUNCATE blocked for ALL roles. Multi-dimension reconciliation — one account_trans linkable to multiple events (e.g. balance_check + quantity_check_per_asset for a stock buy). RLS derives tenancy via the PARENT reconciliation_event FK-chain -> account_users.rd_access-JOIN (Lock 12 pattern), deliberately NOT via account_trans (which is default-deny-all until SELF-190) so this table is not coupled to that policy state. Decision-3 matched-account fence (Lock 9 mod #1 — ALREADY-CATALOGUED instance being implemented here; family stays 7): the linked account_trans must share the linked reconciliation_event.account_id, enforced by fn_reconciliation_event_trans_matched_account (a bare FK is RLS-silent and cannot subquery both rows).';

alter table pfin.reconciliation_event_trans enable row level security;

-- Append-only RLS via parent FK-chain. SELECT (parent rd_access) + INSERT (parent wr_access).
create policy reconciliation_event_trans_select on pfin.reconciliation_event_trans
  for select to authenticated
  using (exists (
    select 1
    from pfin.reconciliation_event re
    join pfin.account_users au on au.account_id = re.account_id
    where re.event_id = reconciliation_event_trans.event_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));
create policy reconciliation_event_trans_insert on pfin.reconciliation_event_trans
  for insert to authenticated
  with check (exists (
    select 1
    from pfin.reconciliation_event re
    join pfin.account_users au on au.account_id = re.account_id
    where re.event_id = reconciliation_event_trans.event_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

grant select, insert on pfin.reconciliation_event_trans to authenticated;

create index if not exists reconciliation_event_trans_event_id_idx
  on pfin.reconciliation_event_trans (event_id);
create index if not exists reconciliation_event_trans_account_trans_id_idx
  on pfin.reconciliation_event_trans (account_trans_id);

create trigger reconciliation_event_trans_block_mutation
  before update or delete on pfin.reconciliation_event_trans
  for each row execute function pfin.fn_reconciliation_family_block_mutation();
create trigger reconciliation_event_trans_block_truncate
  before truncate on pfin.reconciliation_event_trans
  for each statement execute function pfin.fn_reconciliation_family_block_truncate();
revoke truncate on pfin.reconciliation_event_trans from public;

-- ----------------------------------------------------------------------------
-- Decision-3 matched-account fence on reconciliation_event_trans (Lock 9 mod #1).
-- ALREADY-CATALOGUED instance (family stays 7) — this IMPLEMENTS it.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_reconciliation_event_trans_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- NULL-SAFE FAIL-CLOSED: require a SINGLE account to own BOTH the referenced event
  -- and the referenced transaction. If either row is missing OR (under RLS) unreadable,
  -- OR their account_ids differ, the join yields no row -> NOT EXISTS -> raise.
  -- (Never `(subquery) <> new...` — a missing row returns NULL, the IF is not taken,
  -- and the INSERT would leak a cross-account link.)
  if not exists (
    select 1
    from pfin.reconciliation_event re
    join pfin.account_trans t on t.account_id = re.account_id
    where re.event_id = new.event_id
      and t.trans_id = new.account_trans_id
  ) then
    raise exception
      'cross-account reconciliation link rejected: event_id % and account_trans_id % do not share an account_id (ADR-011 Decision 3 / Lock 9 mod #1 matched-account fence)',
      new.event_id, new.account_trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_reconciliation_event_trans_matched_account() from public;

comment on function pfin.fn_reconciliation_event_trans_matched_account() is
  'BEFORE INSERT matched-account fence on pfin.reconciliation_event_trans (ADR-011 Decision 3 / Lock 9 mod #1 — ALREADY-CATALOGUED family instance implemented here; family count +0, stays 7). Rejects cross-account links: the referenced account_trans must share the referenced reconciliation_event.account_id. NULL-safe fail-closed (NOT EXISTS -> raise). SECURITY INVOKER + set search_path = '''' — the fail-closed LAYER differs by role: under authenticated the account_trans read raises `permission denied for table account_trans` at the TABLE-ACL layer (004 grants authenticated no privilege on account_trans until SELF-190; ACL is checked before RLS per the PR #106 gotcha), so authenticated links fail closed BEFORE the NOT-EXISTS branch (correct; reconciliation LINK usage is V1.3, revisited in the SELF-190 battery); under service_role (RLS-bypassed + grants held) the NOT-EXISTS matched-account check is the authoritative path, so QA exercises the fence via privileged INSERT. Trigger (not a bare CHECK) because it subqueries two referenced rows — Decision 3 allows a trigger where PG cannot express the constraint declaratively.';

create trigger reconciliation_event_trans_matched_account
  before insert on pfin.reconciliation_event_trans
  for each row
  execute function pfin.fn_reconciliation_event_trans_matched_account();
