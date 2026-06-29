-- ============================================================================
-- Migration: pfin.account + pfin.account_users + fn_grant_creator_access
-- Phase 6 Build Loop (SELF-187 / V1.0 Platform foundation). Lands Lock 1
-- (Decision 5 RLS baseline) account entity + Lock 2 (Decision 6) V1-dormant
-- account_users ACL scaffolding + Lock 3 (Decision 7) creator-grant trigger.
--
-- Numbering: 003 follows 001_pfin_foundation (schema + fn_refresh_updated_at)
-- and 002_fn_mask_acct_number (SD-15 masking primitive). This is the FIRST
-- base-table migration, so per the Decision 10 greenfield amendment it is where
-- the `users_id = auth.uid()` RLS policies + paired table-level GRANTs first land
-- (001 documented the convention only). DP-1 ratify: account + account_users +
-- the creator-grant trigger are ONE migration (tight mutually-referential unit —
-- FK + AFTER INSERT trigger + the Lock-3 rd_access-JOIN target). Bundled per the
-- F/CTO DP-1 = bundle ratify. `pfin.account`'s column set is the DP-6 = B minimal
-- V1 set (build-what-V1-needs; account is NOT under the Decision-6 preserve-as-
-- built mandate — that applies to account_users only).
--
-- Order within file (dependency-correct): schema -> pfin.account (+RLS/GRANTs)
-- -> pfin.account_users (+RLS/GRANTs; FK to account) -> fn_grant_creator_access
-- (inserts into account_users, which now exists) -> REVOKE EXECUTE FROM PUBLIC
-- -> AFTER INSERT trigger on account -> BEFORE UPDATE updated_at triggers.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   This migration introduces ZERO catalogued §10 instances; the ledger stays
--   at 2 (RT-22 + RT-26 per ADR-011 Decision 4). (i) Instance-numbering: RT-22
--   first, RT-26 second — unchanged. (ii) Layer-attribution: no infra-credential-
--   presence (RT-22) or service_role-allowlist (RT-26) surface is touched — this
--   is an RLS/ACL table set + a DEFINER trigger. (iii) Verbatim-vs-paraphrase:
--   Decision 4 is linked, not restated. NOTE: the SECURITY DEFINER allowlist
--   (2 -> 3 this migration; see below) is a SEPARATE ledger from the §10
--   catalogued-instance ledger — the allowlist change is NOT a §10 change.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION.
--   account_users.account_id is an FK-shaped column crossing the isolation
--   boundary, so Decision 3 is evaluated explicitly. CONCLUSION: account_users is
--   NOT a new Decision-3 matched-tenant instance; the family count is UNCHANGED.
--   The standard matched-tenant invariant (account.users_id == account_users.users_id)
--   is exactly the constraint V2 sharing must VIOLATE (granting user U access to an
--   account U does not own), so it is intentionally NOT applied as a permanent CHECK.
--   V1 isolation is instead provided by: (a) RLS on account_users.users_id = auth.uid();
--   (b) the DEFINER trigger being the SOLE writer in V1-dormant (only same-tenant
--   creator-grant rows exist by construction); (c) the Lock-3-mod-1 column-level
--   UPDATE restriction that fences the cross-tenant re-tenant pivot — DEFERRED to B5
--   (HARD-GATE: it MUST land in the same PR that first grants any authenticated write
--   on account_users, never after). Sec concurrence GREEN (pre-authoring).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — fn_grant_creator_access is SECURITY DEFINER.
--   Locked at ADR-011 Decision 7 / Lock 3 mod #2 (V1-SHIP-BLOCK): "elevate
--   fn_grant_creator_access() to SECURITY DEFINER + verify it fires under V1 RLS."
--   This makes the V1 SECURITY DEFINER allowlist = 3 entries (fn_refresh_updated_at
--   + the audit-log insert helper + fn_grant_creator_access); see the Decision 9
--   SELF-187 amendment annotation. (Authored DEFINER fns so far = 2:
--   fn_refresh_updated_at @ 001 + fn_grant_creator_access @ 003; the audit-log
--   helper is still unauthored.)
--   Why DEFINER (not INVOKER): the trigger writes the bootstrap creator-grant row
--   into the V1-DORMANT account_users table. Under INVOKER it would require granting
--   `authenticated` a direct INSERT on account_users — opening a user-facing write
--   path to the dormant ACL table (a Decision-3-adjacent exposure, and a Sec VETO if
--   combined with an UPDATE grant absent the Lock-3-mod-1 restriction). DEFINER keeps
--   account_users WRITE-LOCKED to this single system trigger: authenticated holds
--   SELECT only (for the Lock-3 rd_access-JOIN read path). The body touches exactly
--   one table (pfin.account_users), fully-qualified, with a fixed-shape insert and no
--   dynamic SQL — least-privilege blast radius.
--   `set search_path = ''` is the privesc fence (search-path injection / CVE-class):
--   all references resolve from pg_catalog or are schema-qualified.
--   ISOLATION LINCHPIN: the whole argument rests on NEW.users_id being un-forgeable.
--   That is guaranteed by pfin.account's INSERT RLS WITH CHECK (users_id = auth.uid())
--   + DEFAULT auth.uid() below — an authenticated inserter cannot set another tenant's
--   users_id on an account, so the trigger can only ever grant the true creator.
--
-- CONTRACT
--   pfin.fn_grant_creator_access() RETURNS trigger — LANGUAGE plpgsql,
--   SECURITY DEFINER, set search_path = ''. AFTER INSERT ON pfin.account FOR EACH ROW.
--   - Inserts exactly one row into pfin.account_users:
--       (account_id, users_id, rd_access, wr_access) = (NEW.account_id, NEW.users_id, true, true)
--     granting the account creator full read+write access. Grantee is NEW.users_id
--     (the row's own tenant anchor) — NEVER auth.uid()/user-controllable input.
--   - REVOKE EXECUTE FROM PUBLIC (trigger-context invocation only).
--   - Security-load-bearing edges: SECURITY DEFINER + set search_path = '' +
--     fixed-shape insert + the pfin.account INSERT RLS linchpin above.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.account — core account entity (DP-6 = B minimal V1 column set).
-- ----------------------------------------------------------------------------
create table if not exists pfin.account (
  account_id     bigint generated always as identity primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  name           text not null,
  account_type   text not null
                   check (account_type in (
                     'depository', 'investment', 'retirement', 'crypto',
                     'manual_other', 'real_estate', 'liability')),
  scope          text not null,                       -- free-text user-defined ownership label (ADR-004 Decision B)
  tax_treatment  text not null
                   check (tax_treatment in ('taxable', 'tax_deferred', 'tax_free')),
  acct_number    text,                                -- nullable; masked-render via pfin.fn_mask_acct_number (SD-15 / Lock 5)
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table pfin.account is
  'Core account entity (ADR-011 Decision 5 / Lock 1; SELF-187). DP-6 = B minimal V1 column set. acct_number stored full, rendered masked-only via pfin.fn_mask_acct_number (SD-15 / Lock 5 / Decision 9 — masked-only enforcement is app-layer + Phase-6 PR-review fence, NOT a DB boundary). The Plaid-item linkage column (SD-03) is DEFERRED — it lands via ALTER in the plaid_items migration (avoids a forward-reference to a not-yet-created table); manual accounts carry no Plaid linkage (§2.4.2). scope is a free-text user-defined ownership label (ADR-004 Decision B) — a user-data attribute, NOT a tenant-isolation boundary. RLS isolation anchor is users_id = auth.uid().';

alter table pfin.account enable row level security;

-- RLS: directly tenant-owned. The INSERT WITH CHECK is the fn_grant_creator_access linchpin.
create policy account_select on pfin.account
  for select to authenticated using (users_id = auth.uid());
create policy account_insert on pfin.account
  for insert to authenticated with check (users_id = auth.uid());
create policy account_update on pfin.account
  for update to authenticated using (users_id = auth.uid()) with check (users_id = auth.uid());
-- No DELETE policy/grant: V1 uses the is_active soft-delete (§2.4.2); hard-delete path deferred.

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on.
grant select, insert, update on pfin.account to authenticated;

-- RLS-predicate index (users_id = auth.uid() is hit on every account query).
create index if not exists account_uid_idx on pfin.account (users_id);

create trigger account_set_updated_at
  before update on pfin.account
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- pfin.account_users — V1-dormant per-account ACL (Decision 6 / Lock 2;
-- preserve-as-built). Lock 3 rd_access-JOIN is the account_trans read-path
-- mechanism (later migration). V1 exposes no sharing/invitation UI.
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_users (
  id          bigint generated always as identity primary key,
  account_id  bigint not null references pfin.account (account_id) on delete cascade,
  users_id    uuid not null references auth.users (id) on delete cascade,
  rd_access   boolean not null default false,
  wr_access   boolean not null default false,
  nickname    text,                                   -- per-grantee label; Lock-3-mod-1 column-UPDATE-allowed set (B5)
  notes       text,                                   -- per-grantee notes; Lock-3-mod-1 column-UPDATE-allowed set (B5)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (account_id, users_id)
);

comment on table pfin.account_users is
  'V1-DORMANT per-account ACL scaffolding (ADR-011 Decision 6 / Lock 2; preserve-as-built). Lock 3 (Decision 7) rd_access-JOIN is the account_trans read-path isolation mechanism. V1 exposes NO sharing/invitation UI. WRITE-LOCKED in V1: authenticated holds SELECT only; the DEFINER fn_grant_creator_access trigger is the sole writer. NOT a Decision-3 matched-tenant instance (the matched-tenant invariant is what V2 sharing must violate). HARD-GATE: authenticated INSERT/UPDATE/DELETE are intentionally ungranted until B5; the Lock-3-mod-1 column-level UPDATE restriction (REVOKE UPDATE; GRANT UPDATE (nickname, notes)) MUST land in the SAME PR that first grants any authenticated write here, never after.';

alter table pfin.account_users enable row level security;

-- RLS: SELECT only in V1-dormant. A user sees only ACL rows where they are the grantee.
create policy account_users_select on pfin.account_users
  for select to authenticated using (users_id = auth.uid());
-- NO insert/update/delete policy in V1: the DEFINER trigger is the sole writer (see HARD-GATE).

-- SELECT-only GRANT (ACL-before-RLS). NO insert/update/delete grant in V1-dormant.
grant select on pfin.account_users to authenticated;

-- RLS-predicate index (users_id = auth.uid()); the unique(account_id, users_id) index
-- already serves account_id-leading lookups for the Lock-3 rd_access-JOIN.
create index if not exists account_users_uid_idx on pfin.account_users (users_id);

create trigger account_users_set_updated_at
  before update on pfin.account_users
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- fn_grant_creator_access — SECURITY DEFINER creator-grant trigger.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_grant_creator_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into pfin.account_users (account_id, users_id, rd_access, wr_access)
  values (new.account_id, new.users_id, true, true);
  return new;
end;
$$;

revoke execute on function pfin.fn_grant_creator_access() from public;

comment on function pfin.fn_grant_creator_access() is
  'AFTER INSERT ON pfin.account creator-grant trigger (ADR-011 Decision 6 / Lock 2 + Decision 7 / Lock 3 mod #2). SECURITY DEFINER — 3rd V1 allowlist entry (see Decision 9 SELF-187 amendment); DEFINER keeps account_users write-locked to this trigger (authenticated holds SELECT only) rather than granting authenticated a direct INSERT on the dormant ACL table. Inserts (NEW.account_id, NEW.users_id, true, true): grantee is NEW.users_id (the row tenant anchor), NEVER auth.uid()/user-input. Isolation linchpin: pfin.account INSERT RLS WITH CHECK (users_id = auth.uid()) makes NEW.users_id un-forgeable. set search_path = '''' is the privesc fence; fully-qualified refs; no dynamic SQL. EXECUTE revoked from PUBLIC (trigger-context only).';

create trigger account_grant_creator_access
  after insert on pfin.account
  for each row execute function pfin.fn_grant_creator_access();
