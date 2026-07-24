-- ============================================================================
-- Migration: pfin.account_trans_annotation_history — the append-only, immutable
--   reclassification-history audit-class table over the 023 mutable overlay's
--   GL-routing-relevant columns (sub_cat_id + metadata). M1-evt Slice A2 (SELF-293).
-- Phase 6 Build Loop — the 2nd slice of M1-evt (A1 = 030; A2 = THIS; B = lot-match
--   FK #14, deferred). F/CTO-ratified 2026-07-24 (all 5 A2 decisions). Design paper
--   temp/self-293-slice-a2-reclass-history-design.md. Realizes Sec Condition B by
--   BUILDING the audit trail (not deferring it) — F/CTO REOPENED the Amendment 1 §9
--   V2-deferral to V1 (the heavier-but-better path; decouples the audit story from
--   the C+ monthly-report freeze bet). ADR-011 Decision 2 audit-class discipline.
--
-- WHAT THIS DOES:
--   Creates pfin.account_trans_annotation_history — an APPEND-ONLY, IMMUTABLE
--   (004-mirror triple-fence) full-snapshot version table. Every routing-relevant
--   change to a 023 annotation (birth INSERT + each sub_cat_id/metadata edit) writes
--   ONE new version row with the COMPLETE routing state at that version. Written by
--   EXACTLY ONE new SECURITY DEFINER helper (the sole write path — authenticated has
--   NO direct INSERT grant, so history cannot be forged via PostgREST). Reads are
--   owner-only (parent-chain α, the 023/029 rd_access-JOIN shape).
--
--   RATIFIED shape (5 A2 decisions):
--     (1) DEFINER insert helper = allowlist 3→4 (disposition A). ONE bespoke
--         reclass-history DEFINER fn; the reserved SELF-201 general-audit-log slot
--         stays reserved (A2 does NOT deliver it). Everything else INVOKER.
--     (2) Snapshot columns: sub_cat_id (plain bigint — NO FK, audit-truthful even if
--         the taxonomy row is later deleted; keeps Decision-3 +0) + metadata jsonb.
--         NOT note. Lot-match column = add-later (Slice B), no speculative slot.
--     (3) Full-snapshot-new-version rows (complete routing state per row).
--     (4) version_seq monotonic int per trans_id; order by (trans_id, version_seq);
--         NO predecessor self-FK → Decision-3 +0 (the immutability fence makes a
--         predecessor link redundant).
--     (5) Capture on INSERT + UPDATE, only when sub_cat_id/metadata actually changed
--         (a note-only edit writes nothing). Birth rows backfilled for existing 023
--         rows (version_seq=1). Land-anytime (no import imprint — the history only
--         OBSERVES classification).
--
-- Numbering: 031 follows 030. Depends on 023 (account_trans_annotation — the overlay
--   this versions + the AFTER trigger's host + the backfill source), 004 (account_trans
--   — the trans_id anchor + the immutability-fence pattern mirrored), 003 (account —
--   the users_id the read policy chains to), 006 (account_users rd_access-JOIN), and
--   001 (pfin schema). No downstream migration depends on 031.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY DEFINER allowlist 3 → 4 (ONE new DEFINER entry).
--   *** This migration GROWS the DEFINER allowlist by 1 — a real one-way-door ledger
--   change, F/CTO-ratified (disposition A). State plainly, do NOT round to "stays 3." ***
--   - fn_reclass_history_insert (the capture helper) — SECURITY DEFINER,
--     set search_path=''. It is the AUTHORED 4th allowlist entry. DEFINER is
--     UNAVOIDABLE + necessary: a tamper-evident audit trail on API-exposed pfin must
--     be written ONLY by the system. authenticated holds NO direct INSERT grant on the
--     history table → an INVOKER trigger could not write (permission denied) and an
--     INVOKER+grant path would let a user POST forged history rows (defeating the
--     tamper-evidence that is the entire rationale for reopening this to V1). So the
--     capture runs as the table owner (DEFINER), the sole write path. It reads/writes
--     only pfin.account_trans_annotation_history (+ reads new.* from the trigger);
--     auth.uid() still resolves the caller (request GUC, privilege-independent) for
--     changed_by attribution.
--   - The DISTINCT reserved 3rd slot (the GENERAL same-transaction audit-log per
--     Decision 1 / Lock 4 mod #5 — per-state-change over account/account_trans/
--     reconciliation/Plaid, source-discriminated; SELF-201 Task #7) STAYS RESERVED-
--     UNAUTHORED. This helper does NOT realize it (those paths still emit no audit
--     rows after A2). So committed allowlist = 4 (fn_refresh_updated_at +
--     fn_grant_creator_access + fn_reclass_history_insert + the reserved general-audit
--     helper); AUTHORED in migrations = 3 (001 + 003 + 031).
--   - EVERYTHING ELSE IS INVOKER: the two immutability fences
--     (fn_reclass_history_block_mutation + _block_truncate) touch nothing (they only
--     raise) — exactly like 004/005; they are NOT allowlist entries. New DEFINER fn →
--     Sec joint-review-mandatory (already mandatory — D2 audit-class).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) ZERO
--   catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence (RT-22), no
--         code-layer SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26), no network-
--         exposure/config admission (RT-27) surface is touched.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD (SELF-187 precedent): the DEFINER-allowlist 3→4 growth is a
--   SEPARATE ledger from §10 — a new DEFINER entry is NOT a §10 catalogued instance.
--   §10 stays 3.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +0 (UNCHANGED;
--   12 labeled / 10 DDL-realized after 029). Reference columns:
--     - trans_id → pfin.account_trans(trans_id): SOLE tenant anchor (parent-chain α;
--       the history row has NO own users_id — tenancy via trans_id →
--       account_trans.account_id → account_users). No second anchor to mismatch →
--       NOT D3 (same class as 023.trans_id / 029.account_trans_id). Written only by
--       the DEFINER helper, which sets trans_id from the edited 023 row — no user-
--       controlled cross-tenant attach.
--     - sub_cat_id: a PLAIN BIGINT SNAPSHOT — NO FOREIGN KEY (audit-snapshot
--       semantics: record the value-as-of-then; stays valid if the taxonomy row is
--       later deleted). Not an FK → not a Decision-3 reference.
--     - version_seq: an integer; NO predecessor self-FK (the version chain is
--       (trans_id, version_seq) ordering — the immutability fence already prevents a
--       deleted-middle-version, so an explicit predecessor FK is redundant). No FK.
--   → No FK-shaped column joins the family. Decision 3 UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 — pfin is [api]-exposed):
--   - RLS ENABLED. POLICY: account_trans_annotation_history_select ONLY — parent-
--     chain rd_access-JOIN (trans_id → account_trans.account_id → account_users; the
--     023 ata_select read shape). NO write policy (the DEFINER helper, as table owner,
--     bypasses RLS; authenticated has no write path). NOT force-RLS (owner bypass is
--     required for the DEFINER insert).
--   - GRANT: authenticated SELECT only. NO insert/update/delete grant (writes are
--     DEFINER-only + immutability-fenced). anon ZERO-grant (schema-usage denial).
--     service_role UNGRANTED.
--   - Ships with the paired QA two-tenant pgTAP battery (SECURITY §4.5): append-only
--     immutability (UPDATE/DELETE/TRUNCATE blocked all roles), two-tenant read
--     isolation, the DEFINER-only-write assertion (authenticated direct INSERT fails
--     at the grant layer), version_seq monotonicity, the DISTINCT-FROM capture gate,
--     note-only-edit-writes-nothing, backfill-birth. QA authors it; Sec sign-off gates.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans_annotation_history — append-only, immutable full-snapshot
--     version table over the 023 overlay's routing columns.
--       - id (bigint identity PK).
--       - trans_id (bigint NOT NULL → account_trans(trans_id) ON DELETE RESTRICT):
--         the annotated txn; SOLE tenant anchor (parent-chain α); NOT D3.
--       - version_seq (int NOT NULL): monotonic per trans_id (1 = birth). UNIQUE
--         (trans_id, version_seq).
--       - sub_cat_id (bigint NULL): SNAPSHOT of the routing class at this version
--         (NO FK — audit-truthful).
--       - metadata (jsonb NULL): SNAPSHOT of the routing detail at this version.
--       - op (text NOT NULL CHECK IN ('insert','update')): birth vs change.
--       - captured_at (timestamptz NOT NULL): when this version's state was captured.
--       - changed_by (uuid NULL DEFAULT auth.uid()): the acting principal (tenant
--         uuid only — no PII); NULL for the migration backfill / non-session writes.
--   pfin.fn_reclass_history_insert() — AFTER INSERT OR UPDATE trigger on
--     account_trans_annotation; **SECURITY DEFINER** (the AUTHORED 4th allowlist
--     entry); set search_path=''. On UPDATE, returns without writing unless sub_cat_id
--     OR metadata IS DISTINCT FROM the old value (a note-only edit writes nothing).
--     Otherwise inserts one full-snapshot row with version_seq = max(existing)+1.
--   pfin.fn_reclass_history_block_mutation() / _block_truncate() — SECURITY INVOKER
--     immutability fences (mirror 004/005); raise on UPDATE/DELETE (row) + TRUNCATE
--     (statement) for ALL roles. INSERT unblocked (the DEFINER path).
--   Security-load-bearing edges: DEFINER-only write (no forgeable direct INSERT);
--     append-only immutability (all roles incl. service_role, via triggers not RLS);
--     parent-chain owner-only read; sub_cat_id snapshot (no FK) preserves audit truth.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.account_trans_annotation_history — append-only full-snapshot version table.
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_trans_annotation_history (
  id           bigint generated always as identity primary key,
  trans_id     bigint not null
                 references pfin.account_trans (trans_id) on delete restrict,
  version_seq  integer not null,
  sub_cat_id   bigint,                         -- SNAPSHOT, no FK (audit-truthful)
  metadata     jsonb,                          -- SNAPSHOT
  op           text not null check (op in ('insert', 'update')),
  captured_at  timestamptz not null default now(),
  changed_by   uuid default auth.uid(),        -- tenant uuid only; NULL for backfill
  unique (trans_id, version_seq)
);

comment on table pfin.account_trans_annotation_history is
  'Append-only, immutable reclassification-history over the 023 overlay''s GL-routing '
  'columns (sub_cat_id + metadata). M1-evt Slice A2 / SELF-293; ADR-011 Decision 2 '
  'audit-class. F/CTO REOPENED the ADR-031 Amendment 1 §9 V2-deferral to V1 (Sec '
  'Condition B satisfied by building the audit trail). Every routing-relevant 023 '
  'change (birth INSERT + each sub_cat_id/metadata edit) writes ONE full-snapshot '
  'version row (version_seq monotonic per trans_id). SOLE writer = the DEFINER helper '
  'fn_reclass_history_insert (authenticated has NO direct INSERT grant → history is '
  'un-forgeable). 004-mirror immutability triple-fence (UPDATE/DELETE/TRUNCATE blocked '
  'all roles). Owner-only read (parent-chain α: trans_id → account_trans → '
  'account_users rd_access). NO own users_id (tenancy via the chain). sub_cat_id is a '
  'plain-bigint SNAPSHOT (no FK — audit-truthful if the taxonomy row is later deleted; '
  'Decision-3 +0). Lot-match column = add-later (Slice B). §10 stays 3; DEFINER '
  'allowlist 3→4 (this helper is the authored 4th; the general-audit-log slot stays '
  'reserved). anon zero-grant; service_role ungranted.';

comment on column pfin.account_trans_annotation_history.trans_id is
  'FK → account_trans(trans_id) ON DELETE RESTRICT. The annotated txn; SOLE tenant '
  'anchor (parent-chain α — no own users_id; tenancy via trans_id → '
  'account_trans.account_id → account_users). NOT a cross-tenant reference → Decision '
  '3 N/A. Set by the DEFINER helper from the edited 023 row.';
comment on column pfin.account_trans_annotation_history.sub_cat_id is
  'SNAPSHOT of the routing class (023.sub_cat_id) at this version. PLAIN BIGINT — NO '
  'FK, by design: an audit snapshot records the value-as-of-then and must stay valid '
  'even if the referenced user_taxonomy row is later deleted. Not a Decision-3 '
  'reference.';
comment on column pfin.account_trans_annotation_history.version_seq is
  'Monotonic version number per trans_id (1 = birth). UNIQUE (trans_id, version_seq) '
  'is the version chain — NO predecessor self-FK (the immutability fence already '
  'prevents a deleted-middle-version, so an explicit link is redundant; Decision-3 +0).';

alter table pfin.account_trans_annotation_history enable row level security;

-- ----------------------------------------------------------------------------
-- RLS read — owner-only parent-chain α (the 023 ata_select shape). NO write policy
-- (the DEFINER helper, as table owner, bypasses RLS; authenticated has no write
-- path). RLS is NOT forced (owner bypass is required for the DEFINER insert).
-- ----------------------------------------------------------------------------
drop policy if exists account_trans_annotation_history_select on pfin.account_trans_annotation_history;
create policy account_trans_annotation_history_select on pfin.account_trans_annotation_history
  for select to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_annotation_history.trans_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy account_trans_annotation_history_select on pfin.account_trans_annotation_history is
  'Parent-FK-chain SELECT policy (023/006 shape): rd_access-JOIN via trans_id → '
  'account_trans.account_id → account_users. A user reads history only for a '
  'transaction whose account they hold rd_access on. Read-only surface — no write '
  'policy (writes are DEFINER-only + immutability-fenced).';

-- ACL-before-RLS (PR #106): SELECT grant only. NO write grant (writes are DEFINER-
-- only; the DEFINER helper runs as the table owner and bypasses grants). anon zero;
-- service_role ungranted.
grant select on pfin.account_trans_annotation_history to authenticated;

create index if not exists account_trans_annotation_history_trans_id_idx
  on pfin.account_trans_annotation_history (trans_id);

-- ----------------------------------------------------------------------------
-- Immutability triple-fence (mirror 004/005). SECURITY INVOKER — the fences touch
-- nothing (they only raise); they are NOT DEFINER allowlist entries. INSERT is
-- unblocked (the DEFINER capture helper's path). Blocks UPDATE/DELETE (row, all
-- roles incl. service_role which bypasses RLS but not triggers) + TRUNCATE (stmt).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_reclass_history_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_trans_annotation_history is immutable (append-only audit-class; ADR-011 Decision 2 / M1-evt Slice A2). % blocked — reclassification history is tamper-proof (corrections land as a NEW version row via the 023 edit path).', tg_op;
end;
$$;

revoke execute on function pfin.fn_reclass_history_block_mutation() from public;

comment on function pfin.fn_reclass_history_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.account_trans_annotation_history '
  '(ADR-011 Decision 2; SELF-293). SECURITY INVOKER (touches nothing; not a DEFINER '
  'allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles '
  'incl. service_role (bypasses RLS but not triggers). INSERT unblocked (the DEFINER '
  'capture path). Corrections land as a new version row, never an in-place edit.';

create trigger account_trans_annotation_history_block_mutation
  before update or delete on pfin.account_trans_annotation_history
  for each row execute function pfin.fn_reclass_history_block_mutation();

create or replace function pfin.fn_reclass_history_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_trans_annotation_history is immutable (append-only audit-class; ADR-011 Decision 2 / M1-evt Slice A2). TRUNCATE blocked — the reclassification audit trail cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_reclass_history_block_truncate() from public;

comment on function pfin.fn_reclass_history_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on '
  'pfin.account_trans_annotation_history (ADR-011 Decision 2; SELF-293). SECURITY '
  'INVOKER (touches nothing; not a DEFINER allowlist entry). Closes the TRUNCATE '
  'bypass (row-level triggers do not fire on TRUNCATE) for ALL roles regardless of '
  'grant state. Message distinct from the row-level fence for QA test-matching.';

create trigger account_trans_annotation_history_block_truncate
  before truncate on pfin.account_trans_annotation_history
  for each statement execute function pfin.fn_reclass_history_block_truncate();

-- Defense-in-depth: explicit REVOKE TRUNCATE (belt-and-suspenders; the statement
-- trigger is the regardless-of-grant guarantee). Mirrors 004.
revoke truncate on pfin.account_trans_annotation_history from public;

-- ----------------------------------------------------------------------------
-- fn_reclass_history_insert — the AUTHORED 4th SECURITY DEFINER allowlist entry
-- (F/CTO-ratified 3→4). The SOLE write path into the history table. AFTER INSERT OR
-- UPDATE on account_trans_annotation. On UPDATE, writes nothing unless sub_cat_id OR
-- metadata changed (a note-only edit is not routing-relevant). DEFINER because
-- authenticated has NO direct INSERT grant on the history table (un-forgeable): the
-- capture must run as the table owner. set search_path='' (injection fence).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_reclass_history_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_next integer;
begin
  -- Capture gate: on UPDATE, only a routing-relevant change (sub_cat_id or metadata)
  -- is versioned; a note-only edit writes nothing. INSERT (birth) always captures.
  if tg_op = 'UPDATE'
     and new.sub_cat_id is not distinct from old.sub_cat_id
     and new.metadata   is not distinct from old.metadata then
    return null;  -- AFTER trigger; return ignored.
  end if;

  -- Monotonic version_seq per trans_id (DEFINER → reads all rows; the UNIQUE
  -- (trans_id, version_seq) constraint fail-safes any concurrent-edit race).
  select coalesce(max(h.version_seq), 0) + 1
    into v_next
    from pfin.account_trans_annotation_history h
   where h.trans_id = new.trans_id;

  insert into pfin.account_trans_annotation_history
    (trans_id, version_seq, sub_cat_id, metadata, op, captured_at, changed_by)
  values
    (new.trans_id, v_next, new.sub_cat_id, new.metadata, lower(tg_op), now(), auth.uid());

  return null;  -- AFTER trigger; return ignored.
end;
$$;

revoke execute on function pfin.fn_reclass_history_insert() from public;

comment on function pfin.fn_reclass_history_insert() is
  'AFTER INSERT OR UPDATE capture helper for pfin.account_trans_annotation_history '
  '(M1-evt Slice A2 / SELF-293). *** The AUTHORED 4th SECURITY DEFINER allowlist entry '
  '(F/CTO-ratified allowlist 3→4, disposition A). *** SECURITY DEFINER + set '
  'search_path='''' — DEFINER is necessary + unavoidable: a tamper-evident audit trail '
  'on API-exposed pfin must be written ONLY by the system. authenticated holds NO '
  'direct INSERT grant on the history table, so this owner-context helper is the SOLE '
  'write path (an INVOKER trigger could not write; an INVOKER+grant path would let a '
  'user POST forged history). Distinct from the reserved general same-transaction '
  'audit-log slot (Lock 4 mod #5 / SELF-201 Task #7) — that stays reserved. Capture '
  'gate: UPDATE writes nothing unless sub_cat_id/metadata IS DISTINCT FROM old (a '
  'note-only edit is skipped); INSERT always captures the birth version. version_seq = '
  'max(existing per trans_id)+1 (UNIQUE fail-safes concurrent-edit races). changed_by = '
  'auth.uid() (resolves the caller even under DEFINER — request GUC; NULL for the '
  'migration backfill). Not §10 (a DEFINER-allowlist change is a separate ledger). The '
  'immutability fences remain INVOKER — this is the ONLY DEFINER in Slice A2.';

create trigger account_trans_annotation_capture_history
  after insert or update on pfin.account_trans_annotation
  for each row execute function pfin.fn_reclass_history_insert();

-- ----------------------------------------------------------------------------
-- Backfill birth rows (version_seq = 1) for any PRE-EXISTING 023 annotations (the
-- trigger only fires on new writes). Land-anytime: the history OBSERVES classification
-- and does not imprint on import. captured_at = the annotation's created_at (its birth
-- time); changed_by NULL (historical actor unknown). Idempotent via NOT EXISTS. 023 is
-- greenfield-empty today → likely zero rows; this is a completeness safety, not an
-- import dependency. Runs under the admin migration connection (bypasses RLS/grants).
-- ----------------------------------------------------------------------------
insert into pfin.account_trans_annotation_history
  (trans_id, version_seq, sub_cat_id, metadata, op, captured_at, changed_by)
select a.trans_id, 1, a.sub_cat_id, a.metadata, 'insert', a.created_at, null
  from pfin.account_trans_annotation a
 where not exists (
   select 1 from pfin.account_trans_annotation_history h where h.trans_id = a.trans_id
 );
