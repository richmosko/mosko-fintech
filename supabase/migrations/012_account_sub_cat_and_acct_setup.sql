-- ============================================================================
-- Migration: pfin.account.sub_cat_id FK + AcctSetup discriminator on account_trans
-- Phase 6 Build Loop (SELF-201 / §2.4.2 manual non-Plaid account onboarding).
-- Lands the schema foundation SELF-201 consumes:
--   (1) pfin.account.sub_cat_id → pfin.user_taxonomy(id) — the matched-tenant FK
--       that 004 + 009 deferred (009 FORWARD-POINTER). Decision-3 CANONICAL
--       instance #5 (the deferred enumeration pass; see below + ADR-025).
--   (2) pfin.account_trans.transaction_type — AcctSetup discriminator (Option B,
--       F/CTO-ratified one-way-door; ADR-025).
--   (3) is_active reconciliation — NO DDL (AC-vs-as-built correction; see below).
--
-- Numbering: 012 follows 011 (tax_character registry). Depends on 003 (pfin.account
-- + account RLS/GRANTs) and 009 (pfin.user_taxonomy — the FK target) already
-- landed; and 004 (pfin.account_trans immutable ledger) for component (2). All
-- three prerequisites are on main. No downstream migration depends on 012 landing
-- before it.
--
-- ----------------------------------------------------------------------------
-- AC-vs-AS-BUILT CORRECTION (SELF-201 AC #3 — is_active, mirrors the 009 header's
-- AC-vs-convention reconciliation so the trace is truthful):
--   SELF-201 AC #3 literally names `pfin.account.inactive BOOLEAN DEFAULT FALSE`
--   plus a `WHERE inactive = FALSE` current-state filter. But 003 already ships
--   `is_active boolean not null default true` — OPPOSITE POLARITY, SAME SEMANTICS,
--   already present, and already the documented soft-delete anchor (003 comment:
--   "V1 soft-deletes accounts via is_active"). RECONCILED: reuse account.is_active;
--   current-state / net-worth aggregation filters `WHERE is_active = TRUE`. NO new
--   `inactive` column and NO DDL for it in 012 — a second inverted-polarity boolean
--   would be a redundant, drift-prone duplicate. The AC's `inactive` naming predates
--   the 003 greenfield convention. This is a backend-contract note; the migration
--   emits no is_active DDL.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference Decision 4; do NOT restate the
-- catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 2 (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i) Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii) Layer-attribution: no infrastructure-credential-presence (RT-22 =
--        PDF-worker container Dockerfile) or code-layer SUPABASE_SERVICE_ROLE_KEY
--        allowlist (RT-26) surface is touched — this is authenticated-tier
--        RLS/FK/column work. 008's service_role DB-ACL posture is untouched (no
--        new service_role grant here; sub_cat writes ride the existing account
--        INSERT/UPDATE grants under authenticated).
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD: the Decision-3 matched-tenant trigger (below) and the
--   immutable-table transaction_type column are NOT §10 catalogued instances —
--   the same way the SELF-187 DEFINER-allowlist 2→3 was a separate ledger from §10.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — CANONICAL INSTANCE #5 (enumeration pass).
--   pfin.account.sub_cat_id → pfin.user_taxonomy(id) is a GENUINE matched-tenant
--   instance: BOTH sides are per-user (account.users_id and user_taxonomy.users_id),
--   so a PG FK (existence-only, silent on RLS) would let a user tag their account
--   with ANOTHER tenant's Sub-Cat — the exact chain attack Decision 3 fences.
--   ENUMERATION-PASS NOTE (F/CTO-ratified 2026-07-05): this discharges the deferred
--   Architect enumeration pass that ADR-011 Decision 3's count-grain annotation
--   (2026-07-02) called for. Canonical Decision-3 enumeration extends 4 → 5:
--     #1 Lock 9 mod #1  — reconciliation_event_trans (event_id, account_trans_id)
--     #2 Lock 10 mod #2 — account_trans.replaces_trans_id self-FK (realized @ 004)
--     #3 Lock 11 mod #9 — monthly_report.included_reconciliation_event_ids INTEGER[]
--     #4 Lock 12        — monthly_report_account_snapshot.account_id
--     #5 (THIS)         — account.sub_cat_id → user_taxonomy(id)  [ADR-025 / 012]
--   This #5 SUPERSEDES the contaminated operational "7 → 8" downstream references
--   (the "7" was a Lock-14-settings-family-of-5 conflation per the count-grain
--   annotation, never a canonical enumeration). Sec signs off the numbering at
--   joint-review. Realization mechanism = BEFORE INSERT OR UPDATE trigger (a
--   single-row CHECK cannot subquery the referenced row; Decision 3 explicitly
--   permits a trigger where PG cannot express the constraint declaratively).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — fn_account_matched_sub_cat is SECURITY INVOKER (NOT DEFINER).
--   Mirrors fn_account_trans_matched_account (004). Needs no elevated privilege, so
--   it does NOT touch the 3-entry SECURITY DEFINER allowlist (ADR-011 Decision 9 —
--   fn_refresh_updated_at + fn_grant_creator_access + the still-unauthored audit-log
--   helper); allowlist stays 3. The read composes correctly with RLS: under
--   `authenticated`, user_taxonomy_select (users_id = auth.uid()) scopes the read to
--   the caller's own taxonomy — a cross-tenant sub_cat_id is INVISIBLE → NOT EXISTS
--   → raise (the desired fence); under service_role the read is RLS-bypassed and
--   authoritative. Unlike 004 (account_trans was default-deny-all, exercised only via
--   privileged INSERT), pfin.account INSERT/UPDATE is ALREADY granted to authenticated
--   (003), so QA exercises this fence directly at the authenticated tier.
--   Covers UPDATE too (not just INSERT): SELF-236 (§2.2.1.c per-manual-account Sub-Cat
--   reassignment) is an UPDATE path, so a reassignment cannot pivot to another tenant's
--   Sub-Cat. (This extends beyond fn_account_trans_matched_account, which is INSERT-only
--   because account_trans is immutable.) NULL-safe fail-closed; set search_path = ''.
--   DOMAIN NOTE: matched-domain (user_taxonomy.domain = 'asset') is NOT enforced in
--   the trigger for V1 — left to the app-layer Sub-Cat dropdown filter. Rationale:
--   account_type includes 'liability', and whether liabilities tag against the 'asset'
--   domain taxonomy is a net-worth-modeling question we do not bake into a DB trigger
--   under uncertainty. The matched-TENANT check is non-negotiable + DB-enforced; the
--   matched-DOMAIN check is a value-correctness constraint left flexible in V1 (a
--   one-line `and domain = 'asset'` addition later if desired).
--
-- ----------------------------------------------------------------------------
-- ACCTSETUP DISCRIMINATOR (Option B — F/CTO-ratified 2026-07-05; ONE-WAY DOOR; ADR-025).
--   pfin.account_trans is immutable (UPDATE/DELETE/TRUNCATE blocked for all roles,
--   004), so the discriminator value is PERMANENT per-row and the vocabulary is
--   load-bearing for the deferred 004 investment/event-detail expansion — hence a
--   one-way door (F/CTO's call). Option B chosen: `transaction_type text not null
--   default 'standard' check (transaction_type in ('standard','acct_setup'))`.
--   Names the event class (generalizes to the deferred expansion via a one-line
--   CHECK alter) rather than a boolean-per-class that sprawls; sits exactly where
--   ADR-022's rule points (closed, code-coupled set → TEXT+CHECK, not enum, not
--   table); ADR-024 gives the clean promote-to-registry path IF a value ever needs
--   per-value metadata (none today — routing lives in code). NO speculative values
--   (no 'transfer'/'split'/'dividend' — add at the surface that needs them).
--   ORTHOGONALITY: is_reverse (004) stays its own boolean — reversal is a modifier
--   on any event class, not an event class (a reversed AcctSetup row is
--   is_reverse=true, transaction_type='acct_setup'). The AcctSetup row SELF-201
--   creates carries transaction_date = user bootstrap-date, amount = initial value,
--   transaction_type = 'acct_setup'.
--   DDL SAFETY on the immutable table: ALTER TABLE ADD COLUMN is DDL, not a row
--   UPDATE — the block-mutation trigger fires on UPDATE/DELETE row ops, not DDL.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account.sub_cat_id — nullable bigint FK → pfin.user_taxonomy(id) ON DELETE
--     RESTRICT. NULL = untagged / Unsorted-pending (Plaid-synced accounts carry none;
--     SELF-200 auto-Unsorted may assign after insert). Matched-tenant fenced by
--     fn_account_matched_sub_cat.
--   pfin.fn_account_matched_sub_cat() — BEFORE INSERT OR UPDATE ON pfin.account
--     WHEN (new.sub_cat_id IS NOT NULL); SECURITY INVOKER; set search_path = '';
--     NULL-safe fail-closed (NOT EXISTS → raise); rejects a sub_cat_id whose
--     user_taxonomy.users_id != account.users_id.
--   pfin.account_trans.transaction_type — text NOT NULL DEFAULT 'standard'
--     CHECK IN ('standard','acct_setup'). Permanent per-row (immutable table).
--   Security-load-bearing edges: matched-tenant fail-closed + NULL-safe + INVOKER
--     RLS composition + the immutable-table permanence of transaction_type.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- Component (1): pfin.account.sub_cat_id → pfin.user_taxonomy(id).
-- Nullable (NULL = untagged/Unsorted-pending); ON DELETE RESTRICT (fail-loud,
-- mirrors account_trans.account_id; user_taxonomy is V1-write-dormant so no delete
-- path exists in V1 anyway). Rides the existing account SELECT/INSERT/UPDATE RLS +
-- GRANTs (003) — no new policy/grant needed.
-- ----------------------------------------------------------------------------
alter table pfin.account
  add column if not exists sub_cat_id bigint
    references pfin.user_taxonomy (id) on delete restrict;

comment on column pfin.account.sub_cat_id is
  'Nullable FK → pfin.user_taxonomy(id) (SELF-201 §2.4.2; ADR-025). The manual-account form (AC#1) captures a Sub-Cat assignment; NULL = untagged/Unsorted-pending (Plaid-synced accounts carry none; SELF-200 auto-Unsorted may assign after insert). Decision-3 CANONICAL instance #5 (both sides per-user) — matched-tenant fenced by fn_account_matched_sub_cat (BEFORE INSERT OR UPDATE; users_id must match). ON DELETE RESTRICT. Matched-DOMAIN (user_taxonomy.domain=''asset'') is app-layer in V1, not trigger-enforced (liability-tagging ambiguity).';

-- Optional supporting index for sub_cat_id lookups / the trigger''s existence probe
-- is not required for correctness (the probe hits user_taxonomy''s PK); accounts are
-- low-cardinality per tenant. No index added (add later if profiling warrants).

create or replace function pfin.fn_account_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL.
  -- NULL-SAFE FAIL-CLOSED: a missing OR (under RLS) unreadable taxonomy row yields
  -- NOT EXISTS → raise. (Never `(subquery) <> new.users_id` — that returns NULL on a
  -- missing row, the IF is not taken, and the write would leak.)
  if not exists (
    select 1 from pfin.user_taxonomy
    where id = new.sub_cat_id
      and users_id = new.users_id
  ) then
    raise exception
      'cross-tenant Sub-Cat rejected: sub_cat_id % is not a taxonomy row owned by users_id % (ADR-011 Decision 3 canonical instance #5 / matched-tenant fence)',
      new.sub_cat_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_matched_sub_cat() from public;

comment on function pfin.fn_account_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account.sub_cat_id (ADR-011 Decision 3 canonical instance #5 / ADR-025; SELF-201). Rejects tagging an account with another tenant''s Sub-Cat: the referenced user_taxonomy row must share the account''s users_id. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the read composes with RLS (user_taxonomy_select scopes to auth.uid() under authenticated; RLS-bypassed/authoritative under service_role). Covers UPDATE (SELF-236 reassignment path), not just INSERT. Trigger (not a bare CHECK) because it subqueries the referenced row — Decision 3 permits a trigger where PG cannot express the constraint declaratively. Not a DEFINER allowlist entry (INVOKER).';

create trigger account_matched_sub_cat
  before insert or update on pfin.account
  for each row
  when (new.sub_cat_id is not null)
  execute function pfin.fn_account_matched_sub_cat();

-- ----------------------------------------------------------------------------
-- Component (2): AcctSetup discriminator on pfin.account_trans (Option B; ADR-025).
-- ADD COLUMN on the immutable ledger is DDL (not a row mutation) — the 004
-- block-mutation trigger does not fire on ALTER TABLE. Existing rows (none in
-- greenfield) default to 'standard'. Value is permanent per-row (immutable table).
-- ----------------------------------------------------------------------------
alter table pfin.account_trans
  add column if not exists transaction_type text not null default 'standard'
    check (transaction_type in ('standard', 'acct_setup'));

comment on column pfin.account_trans.transaction_type is
  'Event-class discriminator (Option B, F/CTO-ratified one-way-door; ADR-025; SELF-201 AC#2). text NOT NULL DEFAULT ''standard'' CHECK IN (''standard'',''acct_setup''). ''acct_setup'' flags the single bootstrap opening-balance row a manual account creates (transaction_date = user bootstrap-date, amount = initial value). PERMANENT per-row: account_trans is immutable (004), so the value cannot be edited post-INSERT and the vocabulary is load-bearing for the deferred 004 event-detail expansion. Expansion = one-line CHECK alter (ADR-022 code-coupled→CHECK rule); promote-to-registry path via ADR-024 if a value ever needs per-value metadata (none today). Orthogonal to is_reverse (reversal is a modifier, not an event class).';
