-- ============================================================================
-- Migration: pfin.linked_source — R-14 credential-store fold (plaid_items →
--            universal provider-agnostic linked_source) + account link columns.
-- Phase 6 Build Loop (ADR-027 ingest/valuation substrate, migration 015 of 015–021;
--   design CLOSED + Sec-cleared 2026-07-14: temp/015-architect-design-spec.md PART A
--   + temp/015-ingest-substrate-design.md §16 + temp/015-sec-review.md).
--   JOINT-REVIEW-MANDATORY (credential-class SD-03 + new Decision-3 instance).
--
-- WHAT THIS DOES (the R-14 / OWD-C fold — F/CTO-ratified drop-and-recreate):
--   plaid_items is EMPTY (Plaid never launched), so 015 DROPs the 4 empty Plaid
--   objects and CREATEs a single legible generalized credential store. Every
--   Sec-negotiated 007 property is preserved on the generalized table:
--     • pfin.linked_source              — SD-03 universal credential-reference store
--                                         (generalizes plaid_items; Vault handle
--                                          WITHHELD from authenticated — RT-02 structural)
--     • pfin.decrypted_source_credential — service_role-ONLY decrypt view
--                                          (generalizes decrypted_plaid_access_token)
--     • pfin.fn_linked_source_cleanup_vault_secret — AFTER DELETE retention backstop
--                                          (generalizes fn_plaid_items_cleanup_vault_secret;
--                                           A.3 credential-less gate refinement)
--     • pfin.linked_source_state_history — append-only credential-error audit
--                                          (generalizes plaid_item_state_history;
--                                           normalized status_class + raw provider code, A.4)
--     • pfin.linked_source_sync_audit    — append-only multi-provider sync audit
--                                          (generalizes plaid_sync_audit; A.5 fold-now)
--   + pfin.account link columns (linked_source_id + provider_account_id +
--     backfill_cutover_date + currency) and the matched-tenant fence for the FK.
--
-- Numbering: 015 follows 014 (account_trans NaN CHECK). Depends on 001 (pfin schema +
--   fn_refresh_updated_at), 003 (pfin.account — the ALTER target + FK tenant anchor),
--   auth.users (users_id anchor), and the platform supabase_vault extension
--   (vault.create_secret / vault.decrypted_secrets / vault.secrets). It DROPs objects
--   created at 007 + their 008 grants (which vanish with the tables). No migration
--   after 007 references the dropped Plaid objects (012/013/014 do not). config.toml
--   already exposes pfin to [api] schemas (ADR-023) — linked_source is internet-facing
--   the moment it is granted, so C6 exposure-gating binds (see GRANTS + SEC block).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list). Read Decision 4 verbatim before drafting. This
--   migration introduces ZERO catalogued §10 instances; the ledger STAYS at 2
--   (RT-22 + RT-26 per ADR-011 Decision 4).
--   (i) Instance-numbering: RT-22 first, RT-26 second — unchanged (not touched).
--   (ii) Layer-attribution: the linked_source decrypt-view service_role-ONLY GRANT and
--        the service_role write grants below are DB-LAYER ACLs — NOT the RT-26 code-layer
--        SUPABASE_SERVICE_ROLE_KEY allowlist grep fence (that governs WHERE the service
--        key is used in web-app/worker SOURCE), and NOT the RT-22 PDF-worker container
--        infra-credential fence. Identical reasoning to 007 lines 46–60 / 008 lines
--        49–57 / 012 lines 33–47. The service_role CODE consumers (future provider-sync
--        routes, FMP ETL) live in web-app/worker source and are governed by RT-26 THERE,
--        not by this migration. The mechanism generalization (plaid → provider-agnostic)
--        adds/removes/re-attributes no catalogued §10 instance.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD: the Decision-3 matched-tenant trigger (fn_account_matched_
--   linked_source) and the immutability fences on the two audit tables are NOT §10
--   catalogued instances — they are Decision-3 / Decision-2 mechanisms on separate
--   ledgers (the same way SELF-187's DEFINER-allowlist 2→3 was separate from §10).
--   RT-02 (credential-table RLS critical-severity test) is a §4.5 RLS-catalog test, NOT
--   a §10 catalogued instance — this migration is the DB surface RT-02 verifies against.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO SECURITY DEFINER function authored here. DEFINER allowlist
--   STAYS 3 (canonical: fn_refresh_updated_at + the still-unauthored audit-log helper +
--   fn_grant_creator_access; authored-so-far = 2). Every function this migration
--   authors is SECURITY INVOKER:
--     • fn_linked_source_cleanup_vault_secret — retention backstop; INVOKER +0, the
--       exact 007 fail-closed-on-auth-cascade tradeoff (see the RETENTION block).
--     • fn_linked_source_state_history_block_mutation / _block_truncate — immutability
--       fences (touch nothing; just raise) — 007/004 posture.
--     • fn_linked_source_sync_audit_block_mutation / _block_truncate — same.
--     • fn_account_matched_linked_source — Decision-3 matched-tenant fence; INVOKER,
--       mirrors 012 fn_account_matched_sub_cat exactly (the read composes with RLS).
--   The decrypt VIEW is not a function; Vault's create_secret/decrypted_secrets are
--   PLATFORM-owned (not our allowlist). No crypto-path function is authored (Vault-native).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — this migration adds +1
--   (canonical family 5 → 6; the 015 slice of the batch's 5 → 10 design delta).
--   CANONICAL INSTANCE #6: pfin.account.linked_source_id → pfin.linked_source(source_id).
--     BOTH sides are per-user (account.users_id and linked_source.users_id), so a bare
--     PG FK (existence-only, silent on RLS) would let a user link their account to
--     ANOTHER tenant's source — the exact chain attack Decision 3 fences. This REALIZES
--     007's deferred FORK-B (account.plaid_item_id → plaid_items), never in the canonical
--     baseline → correct +1. Fenced by fn_account_matched_linked_source (BEFORE INSERT OR
--     UPDATE, INVOKER, NULL-safe fail-closed) — mirrors 012 instance #5 exactly.
--   NOT Decision-3 (the other new FK-shaped / reference columns here):
--     • linked_source.users_id → auth.users : SOLE tenant anchor (direct-owner; mirrors
--       account.users_id / plaid_items.users_id) — no second anchor to mismatch.
--     • linked_source.credential_secret_id → vault.secrets : platform-managed GLOBAL
--       secret store, NOT a pfin tenant-scoped table; no pfin FK constraint placed on it;
--       WITHHELD from the authenticated grant. Not in the pfin isolation graph. (007 posture.)
--     • linked_source_state_history.source_id → linked_source : SOLE anchor (no own
--       users_id; scope derives via source_id → linked_source.users_id).
--     • linked_source_sync_audit.users_id → auth.users : resolved-tenant sole anchor
--       (Decision 1 clause (d)); ON DELETE SET NULL.
--     • account.provider_account_id (text) / account.currency (text) /
--       account.backfill_cutover_date (date) : not FKs → NOT D3.
--   Realization mechanism = BEFORE INSERT OR UPDATE trigger (a single-row CHECK cannot
--   subquery the referenced row; Decision 3 permits a trigger where PG cannot express the
--   constraint declaratively). Sec numbering sign-off at joint-review. Family additions
--   #7–#10 land at 017/020/021 (per temp/015-architect-design-spec.md PART C).
--
-- ----------------------------------------------------------------------------
-- LOCK 4 / DECISION 8 anchor + generalization (this PR authors the ADR-011 Lock 4 +
--   ADR-023 + ADR-016 + ADR-027 amendments same-PR — ADR-015 same-PR-never-defer).
--   The 2026-07-03 Option-2 Vault-native mechanism (007) is UNCHANGED in every security
--   property; only the TABLE generalizes plaid_items → provider-agnostic linked_source.
--   Plaid becomes one `provider` value. Property preservation, generalized:
--     access_token_secret_id → credential_secret_id uuid (NULLABLE — manual/import carry
--       none) WITHHELD from authenticated (RT-02 structural); decrypted_plaid_access_token
--       → decrypted_source_credential (service_role-only JOIN view); plaid_item_state_
--       history → linked_source_state_history (append-only triple-fence); plaid_item_id/
--       item_status/sync-cursor → external_connection_id / connection_status /
--       provider_metadata jsonb; users_id sole anchor / direct-owner RLS (NOT Decision-3).
--   NOT a data one-way-door (empty table). The load-bearing part is the ADR amendments
--   landing this PR. Detail: temp/015-architect-design-spec.md PART A.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.linked_source — mutable credential-reference store. credential_secret_id is a
--     Vault secret handle (uuid, NULLABLE). ADMISSION (provider onboarding, service_role):
--       secret_id := vault.create_secret(<provider credential>, <label>, <desc>);
--       INSERT linked_source(..., provider = <kind>, credential_secret_id = secret_id).
--     authenticated holds column-level SELECT on NON-credential columns only
--     (credential_secret_id withheld). No authenticated write (service_role sole writer,
--     Decision 1 privileged-context-write). RLS direct-owner (users_id = auth.uid()).
--   pfin.decrypted_source_credential — decrypt view (JOIN vault.decrypted_secrets to
--     linked_source); columns (source_id, users_id, provider, external_connection_id,
--     decrypted_credential); SELECT to service_role ONLY (Sec merge-block 5). INNER JOIN
--     naturally excludes credential-less sources. Consumers filter WHERE source_id = $1
--     and bind tenant in code (Decision 1). Named pfin.* (postgres lacks CREATE on vault).
--   pfin.linked_source_state_history — append-only credential-error audit; normalized
--     status_class (provider-agnostic CHECK) + raw provider_error_code (forensic,
--     unconstrained). source_id SOLE anchor. Immutable audit-class (Decision 2).
--   pfin.linked_source_sync_audit — append-only multi-provider sync audit; provider
--     discriminator + source (webhook/scheduled_poll) + provider_event_id UNIQUE
--     idempotency gate (generalizes plaid_webhook_id). service_role-only. Immutable.
--   pfin.account (ALTERs) — linked_source_id (matched-tenant fenced) + provider_account_id
--     + backfill_cutover_date + currency (default 'USD').
--   pfin.fn_account_matched_linked_source() — BEFORE INSERT OR UPDATE ON pfin.account
--     WHEN (new.linked_source_id IS NOT NULL); INVOKER; set search_path = ''; NULL-safe
--     fail-closed (NOT EXISTS → raise); rejects a linked_source whose users_id !=
--     account.users_id. Decision-3 canonical instance #6.
--   RETENTION (SD-03 bounded-source-active-only) — the AFTER DELETE backstop trigger
--     fn_linked_source_cleanup_vault_secret (INVOKER, +0) deletes the backing
--     vault.secrets row on any credentialed source delete (A.3: gated on
--     credential_secret_id IS NOT NULL; credential-less manual/import deletes are clean
--     no-ops); closes the auth.users cascade orphan by-construction. Provider-side revoke
--     (revoke-then-delete) is the provider-sync build hard-gate (SELF-197+).
--   Security-load-bearing edges: credential stored only in vault.secrets (never on the
--     pfin row); decrypt view service_role-only + tenant-keyed by join; provider_event_id
--     UNIQUE; append-only triple-fence on both audit tables; matched-tenant fail-closed +
--     NULL-safe + INVOKER RLS composition; set search_path = '' on every function.
--   GRANTS ARE C6-GATED (ADR-023): every new pfin table here is internet-facing under the
--     Data API the moment it is granted — the SECURITY §4.5 two-tenant RLS battery (QA,
--     same-PR) must prove cross-tenant read+write fail closed before merge (Sec
--     merge-block 7). Grants land here; QA's battery + Sec sign-off gate V1-SHIP-BLOCK.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;
-- service_role schema USAGE persists from 008 (grant usage on schema pfin to service_role).

-- ----------------------------------------------------------------------------
-- FOLD STEP 1 — DROP the 4 empty Plaid objects (R-14 / OWD-C drop-and-recreate).
--   Dependency order: decrypt view → state_history (FK → plaid_items) → sync_audit
--   (independent) → plaid_items. Safe because EMPTY (greenfield; Plaid parked). The 008
--   service_role grants on these tables vanish with the tables. DROP TABLE cascades to a
--   table's own triggers/indexes/grants but NOT to the trigger FUNCTIONS (separate schema
--   objects) → drop those explicitly. fn_refresh_updated_at (001, shared) is NOT dropped.
-- ----------------------------------------------------------------------------
drop view  if exists pfin.decrypted_plaid_access_token;
drop table if exists pfin.plaid_item_state_history;
drop table if exists pfin.plaid_sync_audit;
drop table if exists pfin.plaid_items;
drop function if exists pfin.fn_plaid_items_cleanup_vault_secret();
drop function if exists pfin.fn_plaid_state_history_block_mutation();
drop function if exists pfin.fn_plaid_state_history_block_truncate();
drop function if exists pfin.fn_plaid_sync_audit_block_mutation();
drop function if exists pfin.fn_plaid_sync_audit_block_truncate();

-- ----------------------------------------------------------------------------
-- FOLD STEP 2 — pfin.linked_source — SD-03 universal credential-reference store.
--   Generalizes plaid_items (Lock 4 / Decision 8, Option-2 Vault-native). MUTABLE (not
--   audit-class): connection_status transitions + credential rotation (a new
--   vault.update_secret, same secret_id) are in-place UPDATEs by service_role — NO
--   immutability fence, only the updated_at refresh.
-- ----------------------------------------------------------------------------
create table if not exists pfin.linked_source (
  source_id               bigint generated always as identity primary key,
  users_id                uuid not null default auth.uid()
                            references auth.users (id) on delete cascade,   -- SOLE tenant anchor (direct-owner)
  provider                text not null
                            check (provider in (
                              'plaid', 'snaptrade', 'simplefin',
                              'teller', 'manual', 'import')),                -- kind discriminator (additive per ADR-022)
  external_connection_id  text,                                             -- generalizes plaid_item_id (Plaid Item / SnapTrade connection / SimpleFIN access-url id)
  credential_secret_id    uuid,                                             -- Vault secret handle; NULLABLE (manual/import carry none)
  provider_metadata       jsonb,                                            -- sync-cursor / item_status / provider specifics (non-credential)
  connection_status       text not null default 'healthy'
                            check (connection_status in (
                              'healthy', 'login_required', 'institution_down',
                              'revoked', 'disconnected')),                  -- normalized current health (re-auth banner reads direct; A.4)
  institution_id          text,                                             -- provider institution identifier (generalizes plaid_institution_id)
  institution_name        text,                                             -- display name (non-credential)
  is_active               boolean not null default true,                    -- bounded-source-active-only lifecycle (§4.6)
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table pfin.linked_source is
  'SD-03 universal provider-agnostic credential-reference store (ADR-011 Decision 8 / Lock 4, generalized plaid_items → linked_source per the R-14 fold / ADR-027; 2026-07-03 Vault-native mechanism unchanged). One row per connected source of ANY provider (provider discriminator: plaid/snaptrade/simplefin/teller/manual/import). credential_secret_id is a uuid handle into the platform-managed vault.secrets (ciphertext lives in Vault, NOT on this row — RT-02 "credential never surfaces in a client query" is STRUCTURAL); NULLABLE — manual/import sources carry none. Admission via vault.create_secret under service_role. Decrypt ONLY via pfin.decrypted_source_credential (service_role-only join view, Sec merge-block 5). users_id = auth.uid() is the SOLE tenant anchor (direct-owner RLS; NOT a Decision-3 instance). credential_secret_id is deliberately NOT a pfin FK (vault.secrets is a platform-managed global secret store, not part of the pfin isolation graph) and is WITHHELD from the authenticated GRANT. All writes are service_role (privileged-context-write, Decision 1); no authenticated write path. connection_status is the normalized current-health column the per-provider re-auth banner + monthly_report live-staleness join read direct; error-event transitions are audited in pfin.linked_source_state_history. MUTABLE — not audit-class. RETENTION: the AFTER DELETE backstop fn_linked_source_cleanup_vault_secret deletes the backing vault.secrets row on any credentialed source delete (INVOKER; closes the auth.users cascade orphan); credential-less deletes are clean no-ops (A.3 gate); provider-side revoke is the provider-sync build hard-gate. C6 exposure-gated (ADR-023).';

alter table pfin.linked_source enable row level security;

-- RLS: direct-owner. A user sees only their own sources.
create policy linked_source_select on pfin.linked_source
  for select to authenticated using (users_id = auth.uid());
-- NO insert/update/delete policy: service_role (RLS-bypassing) is the sole writer per
-- the privileged-context-write discipline (Decision 1).

-- ACL-before-RLS (PR #106 gotcha) — COLUMN-LEVEL SELECT grant EXCLUDING the Vault
-- credential handle. Even with the handle, authenticated cannot read vault.decrypted_secrets
-- (measured FALSE) — this omission is defense-in-depth over that platform ACL.
grant select (source_id, users_id, provider, external_connection_id, provider_metadata,
              connection_status, institution_id, institution_name, is_active,
              created_at, updated_at)
  on pfin.linked_source to authenticated;
-- Belt-and-suspenders (C3): ensure the credential handle is not reachable via a broad grant.
revoke all (credential_secret_id) on pfin.linked_source from authenticated;

create index if not exists linked_source_uid_idx on pfin.linked_source (users_id);
-- Idempotency / dedup: at most one live external connection per (provider, external id).
create unique index if not exists linked_source_provider_conn_uidx
  on pfin.linked_source (provider, external_connection_id)
  where external_connection_id is not null;

create trigger linked_source_set_updated_at
  before update on pfin.linked_source
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- FOLD STEP 3 — pfin.decrypted_source_credential — service_role-ONLY decrypt view.
--   Generalizes decrypted_plaid_access_token. Joins the platform vault.decrypted_secrets
--   to linked_source so a service_role read returns the per-source credential keyed by
--   (source_id, users_id, provider), NOT the raw whole-vault surface. Tenant-gating baked
--   into the view SHAPE (the join); the consumer still binds tenant in code (Decision 1).
--   Named pfin.* NOT vault.* because has_schema_privilege('postgres','vault','CREATE') =
--   FALSE (measured, 007) — a migration cannot create objects in the platform-owned vault
--   schema. View runs with view-owner (postgres, definer) semantics by PG default;
--   postgres holds SELECT on vault.decrypted_secrets (measured TRUE) so the join resolves.
--   INNER JOIN naturally excludes credential-less (credential_secret_id IS NULL) sources.
--   NOT security_invoker (must run as owner to resolve the vault join; locked down by the
--   service_role-only grant) — distinct from the RLS-backed reader views in 018/019.
-- ----------------------------------------------------------------------------
create or replace view pfin.decrypted_source_credential as
  select
    ls.source_id,
    ls.users_id,
    ls.provider,
    ls.external_connection_id,
    ds.decrypted_secret as decrypted_credential
  from pfin.linked_source ls
  join vault.decrypted_secrets ds on ds.id = ls.credential_secret_id;

comment on view pfin.decrypted_source_credential is
  'SD-03 decrypt view (ADR-011 Decision 8 / Lock 4 mod #1, generalized decrypted_plaid_access_token → linked_source per the R-14 fold; 2026-07-03 Vault-native). Joins vault.decrypted_secrets to pfin.linked_source, exposing ONLY the per-source credential keyed by (source_id, users_id, provider) — never the raw whole-vault decrypted_secrets surface (tenant-gating baked into the view shape per Sec). INNER JOIN excludes credential-less (manual/import) sources by construction. GRANT SELECT to service_role ONLY (Sec merge-block 5; default decrypt perms would defeat RT-02). Consumed by the service_role provider revoke + scheduled-poll paths; consumers filter WHERE source_id = $1 and bind tenant in code (Decision 1). Named pfin.* not vault.* — postgres lacks CREATE on the vault schema (measured); the service_role-only grant gives the identical security property. Not security_invoker (owner-semantics required to resolve the vault join).';

-- Sec merge-block 5 — the load-bearing grant: service_role ONLY. Everyone else denied.
revoke all on pfin.decrypted_source_credential from public;
revoke all on pfin.decrypted_source_credential from anon;
revoke all on pfin.decrypted_source_credential from authenticated;
grant select on pfin.decrypted_source_credential to service_role;

-- ----------------------------------------------------------------------------
-- FOLD STEP 4 — RETENTION BACKSTOP (SD-03 bounded-source-active-only).
--   Generalizes fn_plaid_items_cleanup_vault_secret. POSTURE = SECURITY INVOKER
--   (allowlist stays 3 — no DEFINER entry added). Same fail-closed-on-auth-cascade
--   structural safety as 007: linked_source.users_id is ON DELETE CASCADE from auth.users,
--   so a user deletion cascade-deletes source rows while their vault.secrets rows do NOT
--   (no FK) → orphaned credential material, and the provider /remove code never fires on a
--   cascade. This DB-layer backstop closes that by-construction.
--
--   A.3 FOLD REFINEMENT (Sec VETTED SAFE, review #1): 007's plaid_items ALWAYS had a
--   credential, so its guard was unconditional. linked_source has credential-LESS sources
--   (manual/import, credential_secret_id IS NULL). Gate the privilege-check + delete on
--   `old.credential_secret_id IS NOT NULL`. This preserves the exact 007 fail-closed-on-
--   auth-cascade property for CREDENTIALED rows (secret non-null → guard fires →
--   supabase_auth_admin lacks vault usage → cascade aborts → no orphan) AND removes a
--   SPURIOUS block for credential-less sources (no vault row exists → clean no-op is
--   correct). An orphan can only exist if credential_secret_id was non-null, and that path
--   still hits the full 007 guard.
--
--   SAFETY IS STRUCTURAL (007 framing): any exception raised inside an AFTER DELETE
--   trigger aborts the whole cascading statement, so the has_table_privilege check + RAISE
--   are a LEGIBILITY optimization for name-resolvable roles, NOT the safety mechanism.
--   Fail-closed is Sec-ruled CORRECT (SELF-196): the DEFINER auto-clean alternative would
--   be a security regression (deleting the local credential while the source stays live at
--   the provider = an un-revocable grant); deletion is forced through the provider
--   revoke-then-delete path. Behaviour by deleting role (all credentialed paths →
--   NO ORPHAN): (i) role holds DELETE on vault.secrets (service_role, postgres) → secret
--   cleaned; (ii) vault USAGE but no vault.secrets DELETE → legible insufficient_privilege
--   RAISE; (iii) no vault USAGE (supabase_auth_admin GoTrue cascade role) → raw
--   permission-denied at name-resolution, before the custom RAISE. (ii)+(iii) abort the
--   cascade → no orphan.
--   FORWARD-NOTES CARRIED FROM 007 (ADR-023 line 93 carve-out — retention limb RE-REALIZED
--   per credential table, NOT inherited): GDPR/user-deletion erasure MUST enumerate the
--   user's sources → provider revoke-then-delete each under service_role → THEN delete
--   auth.users; it must NOT default to a DEFINER trigger (reintroduces the un-revocable-
--   grant regression). The provider-side revoke ordering (read credential via the decrypt
--   view → revoke at provider BEFORE deleting the row) is the provider-sync build hard-gate.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_linked_source_cleanup_vault_secret()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- A.3 gate: credential-less (manual/import) sources have no Vault secret → clean no-op.
  if old.credential_secret_id is not null then
    -- Credentialed source: preserve the exact 007 fail-closed-on-auth-cascade guard.
    -- SAFETY IS STRUCTURAL: any exception in an AFTER DELETE trigger aborts the cascade,
    -- so every branch → NO ORPHAN; the has_table_privilege check is a legibility
    -- optimization, NOT the safety mechanism (remove it and safety still holds).
    if not has_table_privilege(current_user, 'vault.secrets', 'DELETE') then
      raise exception
        'cannot delete pfin.linked_source: Vault secret cleanup requires DELETE on vault.secrets (role % lacks it) — remove the source via its provider revoke-then-delete path first. This fail-closed guard prevents an orphaned, un-revocable credential (ADR-011 Decision 8 Option-2 amendment generalized / R-14 fold).', current_user
        using errcode = 'insufficient_privilege';
    end if;
    delete from vault.secrets where id = old.credential_secret_id;
  end if;
  return old;
end;
$$;

revoke execute on function pfin.fn_linked_source_cleanup_vault_secret() from public;

comment on function pfin.fn_linked_source_cleanup_vault_secret() is
  'AFTER DELETE ON pfin.linked_source retention backstop (ADR-011 Decision 8 Option-2 amendment, generalized fn_plaid_items_cleanup_vault_secret → linked_source per the R-14 fold; ADR-023 line 93 retention-limb carve-out — RE-REALIZED per credential table, not inherited). Deletes the backing vault.secrets row (credential_secret_id) so a deleted source never leaves orphaned credential material — closing the auth.users ON DELETE CASCADE bypass the provider /remove code cannot see. A.3 gate: the guard + delete run only when old.credential_secret_id IS NOT NULL (credential-less manual/import deletes are clean no-ops; Sec VETTED SAFE — an orphan can only exist for a credentialed row, which still hits the full guard). SECURITY INVOKER (NOT a DEFINER allowlist entry; allowlist stays 3). Safety is STRUCTURAL — any exception in an AFTER DELETE trigger aborts the cascade, so every credentialed branch → no orphan; the has_table_privilege check is a legibility optimization, not the safety mechanism. Fail-closed is Sec-ruled CORRECT: auto-deleting the local credential while the source is still live at the provider would leave an un-revocable grant, so deletion is forced through provider revoke-then-delete. GDPR-erasure must NOT default to DEFINER (reintroduces the un-revocable-grant regression). set search_path = '''' (fully-qualified vault.secrets). EXECUTE revoked from PUBLIC.';

create trigger linked_source_cleanup_vault_secret
  after delete on pfin.linked_source
  for each row execute function pfin.fn_linked_source_cleanup_vault_secret();

-- ----------------------------------------------------------------------------
-- FOLD STEP 5 — pfin.linked_source_state_history — append-only credential-error audit.
--   Generalizes plaid_item_state_history. A.4 resolved (open-choice b): a NORMALIZED
--   status_class column (provider-agnostic CHECK — what the re-auth banner + monthly_report
--   staleness join read) PLUS a raw provider_error_code (CHECK-unconstrained forensic code).
--   New provider = zero DDL. source_id is the SOLE tenant anchor (no own users_id; scope
--   derives via linked_source). Immutable audit-class (Decision 2): UPDATE + DELETE +
--   TRUNCATE fenced for ALL roles.
-- ----------------------------------------------------------------------------
create table if not exists pfin.linked_source_state_history (
  history_id           bigint generated always as identity primary key,
  source_id            bigint not null references pfin.linked_source (source_id) on delete restrict,
  status_class         text not null
                         check (status_class in (
                           'healthy', 'login_required', 'institution_down',
                           'revoked', 'disconnected')),                     -- normalized provider-agnostic class (A.4)
  provider_error_code  text,                                               -- raw provider-native code, forensic, CHECK-unconstrained
  detected_at          timestamptz not null default now(),
  created_at           timestamptz not null default now()
);

comment on table pfin.linked_source_state_history is
  'Append-only credential-error state-history audit (ADR-011 Decision 8 / Lock 4 mod #4, generalized plaid_item_state_history → linked_source per the R-14 fold). A.4 shape: normalized provider-agnostic status_class (healthy/login_required/institution_down/revoked/disconnected — the load-bearing consumer contract for the re-auth banner + monthly_report staleness join) + raw provider_error_code (forensic, CHECK-unconstrained; new provider = zero DDL). Immutable audit-class (Decision 2): UPDATE + DELETE blocked for ALL roles (fn_linked_source_state_history_block_mutation) + TRUNCATE blocked (fn_linked_source_state_history_block_truncate) + REVOKE TRUNCATE. NO own users_id — tenant scope derives via source_id → linked_source.users_id (SOLE anchor; NOT a Decision-3 instance). Writes are service_role (privileged-context-write, Decision 1); authenticated holds SELECT via the linked_source join RLS, never write. C6 exposure-gated (ADR-023).';

alter table pfin.linked_source_state_history enable row level security;

-- RLS SELECT: a user sees state-history rows only for sources they own.
create policy linked_source_state_history_select on pfin.linked_source_state_history
  for select to authenticated
  using (exists (
    select 1 from pfin.linked_source ls
    where ls.source_id = linked_source_state_history.source_id
      and ls.users_id = auth.uid()
  ));
-- NO insert/update/delete policy: service_role sole writer; UPDATE/DELETE additionally
-- blocked for ALL roles by the immutability triggers.

grant select on pfin.linked_source_state_history to authenticated;

create index if not exists linked_source_state_history_source_idx
  on pfin.linked_source_state_history (source_id);

create or replace function pfin.fn_linked_source_state_history_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.linked_source_state_history is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 4). % blocked.', tg_op;
end;
$$;

revoke execute on function pfin.fn_linked_source_state_history_block_mutation() from public;

comment on function pfin.fn_linked_source_state_history_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.linked_source_state_history (ADR-011 Decision 2 / Lock 4). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (bypasses RLS but not triggers). INSERT unblocked.';

create trigger linked_source_state_history_block_mutation
  before update or delete on pfin.linked_source_state_history
  for each row execute function pfin.fn_linked_source_state_history_block_mutation();

create or replace function pfin.fn_linked_source_state_history_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.linked_source_state_history is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 4). TRUNCATE blocked.';
end;
$$;

revoke execute on function pfin.fn_linked_source_state_history_block_truncate() from public;

comment on function pfin.fn_linked_source_state_history_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.linked_source_state_history (ADR-011 Decision 2 / Lock 4). SECURITY INVOKER. raise exception. Row-level triggers do NOT fire on TRUNCATE, so this statement-level fence + the REVOKE TRUNCATE below close the audit-retention-wipe path for ALL roles. Distinct message for test-matching.';

create trigger linked_source_state_history_block_truncate
  before truncate on pfin.linked_source_state_history
  for each statement execute function pfin.fn_linked_source_state_history_block_truncate();

revoke truncate on pfin.linked_source_state_history from public;

-- ----------------------------------------------------------------------------
-- FOLD STEP 6 — pfin.linked_source_sync_audit — append-only multi-provider sync audit.
--   Generalizes plaid_sync_audit (A.5 fold-now, F/CTO-ratified + Sec GREEN review #7).
--   Adds a provider discriminator; generalizes plaid_webhook_id → provider_event_id UNIQUE
--   idempotency gate. source (webhook/scheduled_poll) spans all providers: poll-only
--   providers (SimpleFIN/SnapTrade) use scheduled_poll; Plaid uses both. service_role-ONLY
--   (audit of privileged-context writes; not client-facing). Immutable audit-class
--   (Decision 2). No FK to linked_source (external_connection_id is TEXT).
-- ----------------------------------------------------------------------------
create table if not exists pfin.linked_source_sync_audit (
  audit_id                bigint generated always as identity primary key,
  provider                text not null
                            check (provider in (
                              'plaid', 'snaptrade', 'simplefin',
                              'teller', 'manual', 'import')),                -- A.5 provider discriminator
  source                  text not null
                            check (source in ('webhook', 'scheduled_poll')), -- sync mode (Lock 13 mod #8); spans all providers
  users_id                uuid references auth.users (id) on delete set null, -- resolved tenant (Decision 1 clause (d))
  external_connection_id  text,                                             -- provider external id (TEXT, not a pfin FK)
  provider_event_id       text unique,                                      -- generalizes plaid_webhook_id UNIQUE idempotency gate (NULL for poll rows)
  event_type              text,                                             -- provider event type/code, forensic
  detail                  jsonb,                                            -- tenant-resolution chain / event payload snapshot
  created_at              timestamptz not null default now()
);

comment on table pfin.linked_source_sync_audit is
  'Append-only multi-provider sync audit (ADR-011 Decision 8 / Lock 4 mod #3 + Decision 17 / Lock 13 mod #8, generalized plaid_sync_audit → linked_source per the R-14 fold A.5). Cross-language schema-as-contract for the webhook + scheduled-poll write paths, discriminated by (provider, source). provider_event_id UNIQUE is the idempotency gate (generalizes plaid_webhook_id) — the webhook handler INSERTs ON CONFLICT (provider_event_id) DO NOTHING under SERIALIZABLE; poll rows carry NULL (UNIQUE treats NULLs as distinct). source (webhook/scheduled_poll) spans all providers: poll-only providers use scheduled_poll; Plaid uses both. users_id records the code-resolved tenant per Decision 1 clause (d). service_role-ONLY: NOT granted to authenticated (audit of privileged writes; RLS enabled → default-deny for authenticated). Immutable audit-class (Decision 2): UPDATE + DELETE + TRUNCATE fenced for ALL roles. external_connection_id is TEXT external id, NOT a pfin FK → NOT a Decision-3 instance. C6 exposure-gated (ADR-023).';

alter table pfin.linked_source_sync_audit enable row level security;
-- NO policy + NO grant to authenticated: default-deny. service_role (RLS-bypassing) is
-- the sole reader/writer. This is an internal audit log, not a user surface.

create index if not exists linked_source_sync_audit_users_idx on pfin.linked_source_sync_audit (users_id);
create index if not exists linked_source_sync_audit_conn_idx on pfin.linked_source_sync_audit (external_connection_id);

create or replace function pfin.fn_linked_source_sync_audit_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.linked_source_sync_audit is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 13). % blocked.', tg_op;
end;
$$;

revoke execute on function pfin.fn_linked_source_sync_audit_block_mutation() from public;

comment on function pfin.fn_linked_source_sync_audit_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.linked_source_sync_audit (ADR-011 Decision 2 / Lock 13 mod #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role. INSERT (incl. ON CONFLICT DO NOTHING idempotent webhook writes) unblocked.';

create trigger linked_source_sync_audit_block_mutation
  before update or delete on pfin.linked_source_sync_audit
  for each row execute function pfin.fn_linked_source_sync_audit_block_mutation();

create or replace function pfin.fn_linked_source_sync_audit_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.linked_source_sync_audit is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 13). TRUNCATE blocked.';
end;
$$;

revoke execute on function pfin.fn_linked_source_sync_audit_block_truncate() from public;

comment on function pfin.fn_linked_source_sync_audit_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.linked_source_sync_audit (ADR-011 Decision 2 / Lock 13). SECURITY INVOKER. raise exception. Statement-level fence + REVOKE TRUNCATE close the audit-retention-wipe path (row-level triggers do not fire on TRUNCATE). Distinct message for test-matching.';

create trigger linked_source_sync_audit_block_truncate
  before truncate on pfin.linked_source_sync_audit
  for each statement execute function pfin.fn_linked_source_sync_audit_block_truncate();

revoke truncate on pfin.linked_source_sync_audit from public;

-- ----------------------------------------------------------------------------
-- STEP 7 — pfin.account link columns (idempotent ADDs).
--   linked_source_id (matched-tenant fenced, D3 #6) + provider_account_id (provider's
--   native account id) + backfill_cutover_date (per-account import ≤ / aggregator >
--   arbiter, R-3/R-8) + currency (per-account denomination; default 'USD'). ADD COLUMN
--   is DDL; account is mutable (not audit-class) so no immutability concern.
-- ----------------------------------------------------------------------------
alter table pfin.account
  add column if not exists linked_source_id bigint
    references pfin.linked_source (source_id) on delete restrict;

comment on column pfin.account.linked_source_id is
  'Nullable FK → pfin.linked_source(source_id) (R-14 fold / ADR-027; realizes 007''s deferred FORK-B). NULL = manual/unlinked account. Decision-3 CANONICAL instance #6 (both sides per-user) — matched-tenant fenced by fn_account_matched_linked_source (BEFORE INSERT OR UPDATE; users_id must match). ON DELETE RESTRICT (fail-loud; mirrors account.sub_cat_id).';

alter table pfin.account
  add column if not exists provider_account_id text;

comment on column pfin.account.provider_account_id is
  'Provider-native account identifier (R-14 fold). TEXT external id (Plaid account_id / SnapTrade account / SimpleFIN account id) — not a pfin FK → NOT a Decision-3 instance.';

alter table pfin.account
  add column if not exists backfill_cutover_date date;

comment on column pfin.account.backfill_cutover_date is
  'Per-account import-vs-aggregator arbiter (R-3/R-8 / ADR-027 amendment (d)): transactions dated ≤ cutover come from spreadsheet import, > cutover from the aggregator; manual is orthogonal (source_provider=''manual''). NULL = no cutover set. Not a FK → NOT a Decision-3 instance.';

alter table pfin.account
  add column if not exists currency text not null default 'USD';

comment on column pfin.account.currency is
  'Per-account denomination currency code (R-16 uniform cash-as-asset FX). Default ''USD''. Feeds the fn_compute_nav cash-leg FX multiplier. TEXT code → NOT a Decision-3 instance.';

-- ----------------------------------------------------------------------------
-- STEP 8 — Decision-3 canonical instance #6: matched-tenant fence on
--   account.linked_source_id. Mirrors 012 fn_account_matched_sub_cat EXACTLY:
--   BEFORE INSERT OR UPDATE, SECURITY INVOKER, set search_path = '', WHEN (col IS NOT
--   NULL), NULL-safe fail-closed (NOT EXISTS → raise; never `<>`). The read composes with
--   RLS (under authenticated, linked_source_select scopes to auth.uid() → a cross-tenant
--   source is INVISIBLE → NOT EXISTS → raise; under service_role RLS-bypassed/authoritative).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_matched_linked_source()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.linked_source_id IS NOT NULL.
  -- NULL-SAFE FAIL-CLOSED: a missing OR (under RLS) unreadable source row yields
  -- NOT EXISTS → raise. (Never `(subquery) <> new.users_id` — that returns NULL on a
  -- missing row, the IF is not taken, and the write would leak.)
  if not exists (
    select 1 from pfin.linked_source
    where source_id = new.linked_source_id
      and users_id = new.users_id
  ) then
    raise exception
      'cross-tenant linked_source rejected: linked_source_id % is not a source owned by users_id % (ADR-011 Decision 3 canonical instance #6 / matched-tenant fence)',
      new.linked_source_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_matched_linked_source() from public;

comment on function pfin.fn_account_matched_linked_source() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account.linked_source_id (ADR-011 Decision 3 canonical instance #6 / R-14 fold; realizes 007''s deferred FORK-B). Rejects linking an account to another tenant''s source: the referenced linked_source row must share the account''s users_id. NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER + set search_path = '''' — the read composes with RLS (linked_source_select scopes to auth.uid() under authenticated; RLS-bypassed/authoritative under service_role). Covers UPDATE (re-link path), not just INSERT. Trigger (not a bare CHECK) because it subqueries the referenced row — Decision 3 permits a trigger where PG cannot express the constraint declaratively. Not a DEFINER allowlist entry (INVOKER). Mirrors 012 fn_account_matched_sub_cat.';

create trigger account_matched_linked_source
  before insert or update on pfin.account
  for each row
  when (new.linked_source_id is not null)
  execute function pfin.fn_account_matched_linked_source();

-- ----------------------------------------------------------------------------
-- STEP 9 — service_role write grants (008-analog, generalized to linked_source).
--   The three dropped Plaid tables carried 008 least-privilege service_role grants; these
--   re-establish the same posture on the generalized tables (Decision 1 privileged writer).
--   Immutable audit-class tables get select+insert only (UPDATE/DELETE stay trigger-blocked
--   for ALL roles incl. service_role — append-only holds even with INSERT granted).
--   C6-GATED (Sec merge-block 7 / ADR-023): these grants make the tables writable under the
--   Data-API service_role transport; the QA two-tenant RLS battery (same-PR) must prove
--   cross-tenant read+write fail closed before V1-SHIP-BLOCK merge. account_trans/account
--   service_role grants from 008 are untouched (those tables are not dropped).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on pfin.linked_source to service_role;
grant select, insert on pfin.linked_source_state_history to service_role;
grant select, insert on pfin.linked_source_sync_audit to service_role;

-- ----------------------------------------------------------------------------
-- SEC CONDITIONS (ADR-023 C-series, carried onto the generalized tables) — asserted here.
--   C2 (anon outer fence): nothing here grants anon anything; anon holds ZERO privileges
--       on every pfin relation (schema-usage layer denies it). Unchanged.
--   C3 (credential handle never client-facing): the column-scoped authenticated SELECT
--       above EXCLUDES credential_secret_id + the belt-and-suspenders REVOKE re-asserts it.
--   C4 (decrypt view stays locked): decrypted_source_credential is service_role-only
--       (REVOKE public/anon/authenticated + grant service_role) — Sec merge-block 5.
--   C6 (exposure-gating, standing): every new table here (linked_source, state_history,
--       sync_audit) needs the SECURITY §4.5 two-tenant RLS battery proving cross-tenant
--       read+write fail closed BEFORE merge (QA authors same-PR; Sec merge-block 7).
-- ----------------------------------------------------------------------------
