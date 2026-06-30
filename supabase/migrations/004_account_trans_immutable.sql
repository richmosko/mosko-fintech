-- ============================================================================
-- Migration: pfin.account_trans — immutable transaction ledger (audit-class)
-- Phase 6 Build Loop (SELF-189 / Wave 1 B4 / V1.0 Platform foundation).
-- Lands the Lock 10 (Decision 14) immutability fence + the Decision-3 second
-- instance (replaces_trans_id matched-account) + the Lock 15 mod #1 created_at.
--
-- Numbering: 004 follows 001 (foundation) / 002 (fn_mask) / 003 (account +
-- account_users). account_trans MUST precede the reconciliation_event family
-- (SELF-188 → 005): per Decision 13 / Lock 9, pfin.reconciliation_event_trans
-- (event_id, account_trans_id) JUNCTIONS account_trans, so account_trans is the
-- prerequisite. (This corrects the milestone's stated "003 reconciliation · 004
-- account_trans" order; reconciliation renumbers to 005.)
--
-- SCOPE — V1.0 = SCHEMA FENCE ONLY. This migration creates the immutable table
-- + the two triggers + the dedup indexes. Reverse-and-replace *usage* (app-layer
-- chaining) lands at V1.3 (§2.3 Cash flow). The rd_access/wr_access-JOIN RLS
-- policies (Lock 3 / Decision 7) land at SELF-190 (B5); this migration enables
-- RLS with NO policies (default-deny-all) — the table is fenced-but-inaccessible
-- to authenticated until SELF-190, which is correct (no usage until then).
--
-- COLUMN SET — DP-6 minimal V1.0 cash-core (build-what-V1-needs). Investment
-- fields (symbol/quantity/price), AcctSetup event-detail (split ratio/ex-date;
-- transfer-in-kind source/dest/position/cost-basis-carry), and sub_cat_id
-- (FK → user_taxonomy, not yet created) are DEFERRED to later migrations when
-- their surfaces land; the wide-vs-companion-detail-table shape is resolved then.
-- Reconciliation state is NOT a mutable column here — it lives in the append-only
-- reconciliation_event_trans link (SELF-188); "edit"/"delete" are realized via
-- reverse-and-replace (append-only), never in-place mutation. No mutable
-- reconciled_flag / skip_flag columns (they would violate immutability).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii)
--   layer-attribution — no infra-credential-presence (RT-22) or service_role-
--   allowlist (RT-26) surface touched. (iii) Decision 4 linked, not restated.
--   NOTE (de-conflation guard): the cross-tier immutability trigger is a
--   Decision-2 AUDIT-CLASS mechanism, NOT a §10 catalogued instance — it does not
--   touch the §10 ledger, the same way the SELF-187 DEFINER-allowlist 2→3 was a
--   separate ledger from §10.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0.
--   The only FK-shaped columns are account_id + replaces_trans_id.
--   - account_id → pfin.account: account_trans carries NO own users_id; its tenant
--     scope derives via account_id → account_users.rd_access-JOIN (Decision 7 /
--     Lock 3). account_id is therefore the SOLE tenant anchor — there is no second
--     anchor to mismatch — so it is NOT a Decision-3 matched-tenant instance.
--   - replaces_trans_id (self-FK) IS the catalogued Decision-3 SECOND instance
--     (Lock 10 mod #2): matched-ACCOUNT validation rejecting cross-account
--     replacement. This migration IMPLEMENTS it; it does not add a new instance
--     (family count UNCHANGED — Sec-pinned at 7).
--   Decision 3's "WITH CHECK" wording is shorthand: a single-row CHECK cannot
--   subquery the referenced row, so the correct mechanism here is a BEFORE INSERT
--   trigger (Decision 3 explicitly allows a trigger for cases PG cannot express
--   declaratively). "Trigger" here is the canonical realization, NOT a deviation.
--
-- ----------------------------------------------------------------------------
-- DECISION 2 / DECISION 14 / LOCK 15 — verbatim anchors.
--   Decision 14 / Lock 10: "account_trans rows immutable post-INSERT; edits via
--     reverse-and-replace pattern (is_reverse BOOLEAN + replaces_trans_id FK
--     self-reference; matched-account WITH CHECK per Decision 3). RLS-default-deny
--     on UPDATE + DB-trigger blocking UPDATE across both authenticated AND
--     service_role (Lock 10 mod #8 pattern)."
--   Decision 2 (§7 immutable + INSERT-new-version audit-class discipline): edits
--     are new rows, never in-place mutation.
--   Lock 15 mod #1 (V1-SHIP-BLOCK): "re-introduces account_trans.created_at
--     TIMESTAMPTZ NOT NULL DEFAULT NOW() IMMUTABLE post-INSERT (inherits Lock 10
--     mod #8 trigger pattern)."
--
-- POSTURE RATIONALE — both triggers are SECURITY INVOKER (NOT DEFINER).
--   Neither needs elevated privilege; keeping them INVOKER means they do NOT touch
--   the 3-entry SECURITY DEFINER allowlist (ADR-011 Decision 9 — fn_refresh_updated_at
--   + audit-log helper + fn_grant_creator_access). The immutability block reads/writes
--   nothing (just raises). The matched-account check's read composes correctly with
--   RLS: under authenticated it is rd_access-JOIN-scoped (SELF-190+), so a user can
--   only validate against transactions in an account they can see (cross-account =
--   invisible = rejected, which is the desired fence); under service_role the read is
--   RLS-bypassed and authoritative. At THIS migration (default-deny-all) only
--   RLS-bypassed/privileged sessions can INSERT, under which the matched-account read
--   sees all rows and is authoritative — so QA exercises it via privileged INSERT.
--   The cross-tier immutability fence specifically requires a TRIGGER, not just
--   RLS-default-deny: service_role BYPASSES RLS but NOT triggers, so the trigger is
--   what closes the privileged-context UPDATE/DELETE gap. TRUNCATE additionally
--   bypasses ROW-level triggers (it fires only STATEMENT-level BEFORE TRUNCATE
--   triggers), so a separate statement-level fence (fn_account_trans_block_truncate)
--   + a defensive REVOKE TRUNCATE close the audit-retention-wipe path. The fence now
--   covers UPDATE + DELETE + TRUNCATE across all roles.
--
-- CONTRACT
--   pfin.account_trans — append-only audit-class ledger. INSERT-only mutation
--     (incl. reverse rows is_reverse=true). UPDATE + DELETE + TRUNCATE blocked for
--     ALL roles (raise exception — fail LOUD).
--   pfin.fn_account_trans_block_mutation() — BEFORE UPDATE OR DELETE (row-level); raises.
--   pfin.fn_account_trans_block_truncate() — BEFORE TRUNCATE (statement-level); raises.
--     Required because row-level triggers do NOT fire on TRUNCATE; plus a defensive
--     REVOKE TRUNCATE … FROM PUBLIC. Distinct raise message for test-matching.
--   pfin.fn_account_trans_matched_account() — BEFORE INSERT WHEN replaces_trans_id
--     IS NOT NULL; NULL-safe fail-closed (NOT EXISTS → raise); rejects cross-account
--     replacement. set search_path = ''.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.account_trans — immutable transaction ledger (DP-2 minimal cash-core).
-- ON DELETE RESTRICT on account_id: transactions are immutable audit history, so
-- an account with transactions cannot be hard-deleted (consistent with the
-- immutability posture; V1 soft-deletes accounts via is_active anyway).
-- NOTE (flagged follow-up — cross-cutting deletion policy, out of SELF-189 scope):
-- account.users_id → auth.users is ON DELETE CASCADE (003); with this RESTRICT +
-- the DELETE-block trigger, deleting an auth.users row that owns accounts WITH
-- transactions will fail. The user-deletion / GDPR-vs-immutable-audit path needs a
-- deliberate cross-cutting decision (e.g. privileged trigger-disable in a
-- maintenance transaction, or anonymize-not-delete). Not resolved here.
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_trans (
  trans_id            bigint generated always as identity primary key,
  account_id          bigint not null references pfin.account (account_id) on delete restrict,
  transaction_date    date not null,
  amount              numeric(20,4) not null,
  vendor              text,
  description         text,
  is_reverse          boolean not null default false,
  replaces_trans_id   bigint references pfin.account_trans (trans_id),  -- self-FK; matched-account fenced below (Decision-3 2nd)
  plaid_transaction_id text,                                            -- Plaid external id (dedup primary); NOT a pfin FK
  import_hash         text,                                             -- content-hash (dedup secondary); NOT a pfin FK
  created_at          timestamptz not null default now()               -- IMMUTABLE post-INSERT (Lock 15 mod #1)
);

comment on table pfin.account_trans is
  'Immutable audit-class transaction ledger (ADR-011 Decision 14 / Lock 10; SELF-189). Append-only: UPDATE + DELETE blocked for ALL roles (authenticated + service_role) by fn_account_trans_block_mutation, and TRUNCATE blocked by the statement-level fn_account_trans_block_truncate (row-level triggers do NOT fire on TRUNCATE); edits via reverse-and-replace (is_reverse + replaces_trans_id). NO own users_id — tenant scope derives via account_id → account_users.rd_access-JOIN (Decision 7 / Lock 3). NO mutable reconciled_flag/skip_flag (reconciliation state lives in the append-only reconciliation_event_trans link, SELF-188). DP-2 minimal cash-core; investment + AcctSetup-event-detail + sub_cat_id deferred to later migrations. RLS enabled with NO policies here (default-deny-all); rd_access/wr_access-JOIN policies land at SELF-190.';

-- Indexes: RLS-JOIN column + the two Decision-8 dedup partial-unique indexes.
create index if not exists account_trans_account_id_idx on pfin.account_trans (account_id);
create unique index if not exists account_trans_plaid_dedup_idx
  on pfin.account_trans (account_id, plaid_transaction_id) where plaid_transaction_id is not null;
create unique index if not exists account_trans_hash_dedup_idx
  on pfin.account_trans (account_id, import_hash) where import_hash is not null;

-- RLS: fence-only / default-deny-all. NO policies here (Lock 3 JOIN policies → SELF-190).
alter table pfin.account_trans enable row level security;

-- ----------------------------------------------------------------------------
-- Surface 1 — immutability block (cross-tier; the privileged-context fence).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise exception, NOT return null — return null would silently no-op
  -- the row and read as "succeeded"). Blocks UPDATE + DELETE for ALL roles; service_role
  -- bypasses RLS but NOT triggers, so this — not RLS-default-deny — closes the
  -- privileged-context immutability gap (ADR-011 Decision 2 / Decision 14 / Lock 10 mod #8).
  raise exception
    'pfin.account_trans is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 10). % blocked — edit via reverse-and-replace (INSERT is_reverse=true).', tg_op;
end;
$$;

revoke execute on function pfin.fn_account_trans_block_mutation() from public;

comment on function pfin.fn_account_trans_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.account_trans (ADR-011 Decision 2 / Decision 14 / Lock 10 mod #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (which bypasses RLS but not triggers) — this is the privileged-context immutability fence that RLS-default-deny alone cannot provide. INSERT (incl. reverse rows) is unblocked.';

create trigger account_trans_block_mutation
  before update or delete on pfin.account_trans
  for each row execute function pfin.fn_account_trans_block_mutation();

-- TRUNCATE bypasses ROW-level triggers — Postgres runs it through STATEMENT-level
-- BEFORE TRUNCATE triggers only — so a role holding TRUNCATE could wipe the entire
-- immutable ledger without tripping the row-level fence (a Decision-2 audit-retention
-- bypass). Statement-level fence (covers it regardless of grant state) + a defensive
-- REVOKE TRUNCATE below (belt-and-suspenders).
create or replace function pfin.fn_account_trans_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_trans is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 10). TRUNCATE blocked — the immutable ledger cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_account_trans_block_truncate() from public;

comment on function pfin.fn_account_trans_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.account_trans (ADR-011 Decision 2 / Lock 10). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so this statement-level trigger fences the audit-retention-wipe path for ALL roles regardless of grant state. Message is distinct from the row-level fence for test-matching.';

create trigger account_trans_block_truncate
  before truncate on pfin.account_trans
  for each statement execute function pfin.fn_account_trans_block_truncate();

-- Defense-in-depth: PUBLIC holds no TRUNCATE by default, but revoke explicitly so a
-- broad platform/default grant can't reintroduce it. The statement-level trigger above
-- is the regardless-of-grant guarantee.
revoke truncate on pfin.account_trans from public;

-- ----------------------------------------------------------------------------
-- Surface 2 — matched-account fence on replaces_trans_id (Decision-3 2nd instance).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.replaces_trans_id IS NOT NULL.
  -- NULL-SAFE FAIL-CLOSED: a missing OR (under RLS) unreadable referenced row yields
  -- NOT EXISTS → raise. (Never `(subquery) <> new.account_id` — that returns NULL on a
  -- missing row, the IF is not taken, and the INSERT would leak.)
  if not exists (
    select 1 from pfin.account_trans
    where trans_id = new.replaces_trans_id
      and account_id = new.account_id
  ) then
    raise exception
      'cross-account reverse-and-replace rejected: replaces_trans_id % is not a transaction in account_id % (ADR-011 Decision 3 second instance / Lock 10 mod #2 matched-account fence)',
      new.replaces_trans_id, new.account_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_matched_account() from public;

comment on function pfin.fn_account_trans_matched_account() is
  'BEFORE INSERT matched-account fence on pfin.account_trans.replaces_trans_id (ADR-011 Decision 3 second instance / Lock 10 mod #2). Rejects cross-account reverse-and-replace: the replaced transaction must share the inserting row''s account_id. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the read composes with RLS (rd_access-JOIN-scoped under authenticated at SELF-190+; RLS-bypassed/authoritative under service_role). Trigger (not a bare CHECK) because the validation subqueries the referenced row — Decision 3 allows a trigger where PG cannot express the constraint declaratively. Implements the catalogued 2nd instance; family count +0.';

create trigger account_trans_matched_account
  before insert on pfin.account_trans
  for each row
  when (new.replaces_trans_id is not null)
  execute function pfin.fn_account_trans_matched_account();
