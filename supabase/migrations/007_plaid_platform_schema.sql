-- ============================================================================
-- Migration: pfin Plaid platform schema — Vault-native credential store + audit
-- Phase 6 Build Loop (SELF-196 / V1-SHIP-BLOCK / sec-joint-review-mandatory).
-- Lands the Lock 4 (ADR-011 Decision 8) Plaid integration substrate under the
-- 2026-07-03 F/CTO-ratified Option 2 (Vault-native secret-per-token) amendment:
--   • pfin.plaid_items                — SD-03 credential store (Vault secret REFERENCE)
--   • pfin.decrypted_plaid_access_token — service_role-ONLY decrypt view (mod #1)
--                                        (in pfin, NOT vault — see AC-WORDING note)
--   • pfin.plaid_item_state_history   — SD-14 append-only 4-class credential-error audit (mod #4)
--   • pfin.plaid_sync_audit           — SD-19 append-only cross-language sync audit
--                                        + plaid_webhook_id UNIQUE idempotency gate (mod #3)
--
-- ----------------------------------------------------------------------------
-- RATIFY STATE (post-ratify cross-check hooks — v1 evolved across two ratify gates).
--   FORK-A (encryption mechanism) — RESOLVED. F/CTO ratified Option 2 (Vault-native
--     secret-per-token; drop the BYTEA column) on 2026-07-03 after Backend's clean-
--     apply smoke proved the originally-locked pgsodium path non-viable on the pinned
--     PG-17 stack (TWO measured blockers: (1) pgsodium available but NOT installed,
--     and the migration referenced pgsodium.* without `create extension`; (2) the
--     UUID-keyed pgsodium AEAD overload is execute-denied for BOTH service_role AND
--     postgres — owned by supabase_admin, granted only to pgsodium_keyholder). This
--     is a ONE-WAY DOOR: stored secret references bind to the Vault mechanism. The
--     ADR-011 Decision 8 / Lock 4 amendment lands in THIS PR (never deferred). Final
--     Sec joint-review + F/CTO final sign-off gate merge.
--   AC-WORDING deviations (capability-driven; product behavior identical; routed to
--     PM for the courtesy nod + Linear update):
--       • AC #2 "access_token_encrypted BYTEA NOT NULL" -> `access_token_secret_id
--         uuid NOT NULL` (a Vault secret reference). Ciphertext lives in vault.secrets,
--         not on the pfin row — RT-02 "token never surfaces in a client query" becomes
--         STRUCTURAL (the token is not on pfin.plaid_items at all).
--       • AC #3 "vault.decrypted_plaid_access_token" -> `pfin.decrypted_plaid_access_token`.
--         MEASURED: `has_schema_privilege('postgres','vault','CREATE')` = FALSE — a
--         migration (runs as postgres) CANNOT create objects in the platform-owned
--         vault schema. The view therefore lives in our owned pfin schema; the
--         service_role-only grant + the join give the identical security property.
--   FORK-B (account<->plaid_items linkage ALTER) — DEFERRED, unchanged (see DECISION 3).
--
-- Numbering: 007 follows 001..006. No ordering dependency on 004/005/006 (Plaid
-- substrate references neither account_trans nor reconciliation); depends on 001
-- (pfin schema + fn_refresh_updated_at), auth.users (users_id anchor), and the
-- platform-installed supabase_vault extension (vault.create_secret /
-- vault.decrypted_secrets). SELF-195 ("pgsodium/Vault key mgmt") was marked Done in
-- Linear but never implemented on disk — 007 creates all Plaid objects from scratch.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii)
--   layer-attribution — RT-22 (PDF-worker container infra-credential-presence) and
--   RT-26 (V1-web-app SUPABASE_SERVICE_ROLE_KEY code-layer allowlist CI grep fence)
--   are BOTH untouched: the service_role-only decrypt-view grant here is a DB-LAYER
--   ACL, NOT the code-layer allowlist (RT-26) and NOT the container-image fence
--   (RT-22). The service_role write paths that consume this schema (Plaid
--   /public_token/exchange + /item/remove routes, ADR-016 allowlist entries 2 + 3)
--   live in web-app source and are governed by RT-26 THERE, not by this migration.
--   The Option-2 mechanism swap (pgsodium -> Vault) does not add, remove, or
--   re-attribute any catalogued §10 instance. (iii) Decision 4 is linked, not restated.
--   NOTE (de-conflation guard): RT-02 (Plaid Item table RLS critical-severity test)
--   is a §4.5 RLS-catalog test, NOT a §10 catalogued instance — this migration is
--   the DB surface RT-02 verifies against; it does not touch the §10 ledger.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — this migration adds +0.
--   FK-shaped columns created here:
--   - pfin.plaid_items.users_id -> auth.users(id): SOLE tenant anchor (direct-owner,
--     mirrors pfin.account.users_id). No second anchor to mismatch -> NOT a Decision-3
--     instance. RLS keys on users_id = auth.uid().
--   - pfin.plaid_items.access_token_secret_id -> vault.secrets (uuid handle): NOT a
--     Decision-3 instance. vault.secrets is a platform-managed GLOBAL secret store,
--     NOT a pfin tenant-scoped table — there is no cross-tenant tenant-anchor to
--     match. Access is fenced by (a) plaid_items RLS gating which secret_id a caller
--     can even see + (b) the column being withheld from the authenticated GRANT +
--     (c) authenticated lacking SELECT on vault.decrypted_secrets (measured FALSE).
--     No pfin FK constraint is placed on it (see the table note) so it is not an FK
--     in the pfin isolation graph at all.
--   - pfin.plaid_item_state_history.item_id -> pfin.plaid_items(item_id): SOLE anchor
--     (no own users_id; scope derives via item_id -> plaid_items.users_id). NOT a
--     Decision-3 instance.
--   - pfin.plaid_sync_audit.users_id -> auth.users(id): resolved-tenant anchor written
--     by service_role code (Decision 1 clause (d)); sole anchor -> NOT an instance.
--   NET: family count UNCHANGED. (Grain note per the 2026-07-02 Decision-3 annotation:
--   canonical enumerated = 4; header "7" is operational-not-canonical. 007 adds none
--   under either grain.)
--   DEFERRED (FORK-B): pfin.account.plaid_item_id -> pfin.plaid_items WOULD be a NEW
--   Decision-3 instance (matched-tenant account.users_id == plaid_items.users_id). NOT
--   added here (outside the SELF-196 ACs; lands with the onboarding feature that uses
--   it, SELF-197+, carrying its matched-tenant fence + Sec joint-review + Decision-3
--   increment + QA cross-tenant test). This leaves 003's "linkage lands via ALTER in
--   the plaid_items migration" forward-pointer open — tracked here.
--
-- ----------------------------------------------------------------------------
-- DECISION 8 / LOCK 4 — verbatim anchor + Option-2 AMENDMENT (this PR).
--   Original locked mechanism (ADR-011 Decision 8 / Lock 4, Option C): "Supabase
--     Vault/pgsodium column-level encryption on plaid_items.access_token_encrypted
--     BYTEA + ... append-only plaid_item_state_history table."
--   AMENDMENT (2026-07-03, F/CTO-ratified; ADR-011 Decision 8 amendment authored this
--     PR): the crypto MECHANISM moves from "pgsodium column-level BYTEA + decrypt-view"
--     to "Vault-native secret-per-token (vault.create_secret) + a uuid reference column
--     + a decrypt VIEW that JOINs vault.decrypted_secrets to pfin.plaid_items." WHY:
--     the pinned Supabase stack cannot execute the UUID-keyed pgsodium AEAD for
--     service_role/postgres (Backend measured), and pgsodium is deprecated by Supabase
--     in favor of Vault. This is CAPABILITY-DRIVEN, not a scope change — product
--     behavior (encrypted at-rest token storage, decrypt only under service_role) is
--     IDENTICAL. Still within Lock 4's "Supabase Vault ... " arm; the "/pgsodium"
--     sub-clause + the BYTEA column shape are the amended parts.
--   Sec's 6 mods (mapping under Option 2):
--     mod #1 (V1-SHIP-BLOCK) "decrypt-view permission scoped to service_role only" ->
--       pfin.decrypted_plaid_access_token GRANT SELECT to service_role ONLY (REVOKE
--       from public/anon/authenticated). Tenant-gating baked into the VIEW SHAPE: it
--       joins vault.decrypted_secrets to plaid_items and exposes ONLY the per-Item
--       Plaid token keyed by (item_id, users_id) — never the raw whole-vault
--       vault.decrypted_secrets surface.
--     mod #3 (V1-SHIP-BLOCK) "webhook idempotency via plaid_webhook_id UNIQUE" ->
--       pfin.plaid_sync_audit.plaid_webhook_id UNIQUE (nullable; poll rows NULL).
--     mod #4 (advisory) "4-class credential-error enum per §2.4.4" ->
--       pfin.plaid_item_state_history.plaid_error_code CHECK IN the 4 classes.
--   Decision 1 (§6 privileged-context-write): all writes to these tables + all
--     vault.create_secret admission happen under service_role (no user JWT); tenant
--     correctness derives from code; plaid_sync_audit is the clause-(d) audit of the
--     tenant-resolution chain. Decision 2 (§7 immutable audit-class): state_history +
--     sync_audit are append-only (UPDATE/DELETE/TRUNCATE fenced for ALL roles).
--
-- POSTURE RATIONALE — NO SECURITY DEFINER function authored here.
--   The immutability fences are SECURITY INVOKER (read/write nothing; just raise) —
--   same posture as 004; they do NOT touch the 3-entry DEFINER allowlist (ADR-011
--   Decision 9). Option 2 adds NO function at all for the crypto path: Vault's
--   create_secret + decrypted_secrets are PLATFORM-owned (not our allowlist), and the
--   decrypt VIEW is not a function. The view runs with view-owner (postgres, definer)
--   semantics by PG default — postgres CAN SELECT vault.decrypted_secrets (measured
--   TRUE) so the join resolves; service_role also holds that SELECT directly. The
--   Sec-required retention backstop (fn_plaid_items_cleanup_vault_secret) is also
--   SECURITY INVOKER (+0 allowlist) — see the RETENTION BACKSTOP block for the
--   INVOKER-vs-DEFINER fail-closed tradeoff. DEFINER allowlist UNCHANGED at 3
--   (authored so far = 2).
--
-- CONTRACT
--   pfin.plaid_items — mutable credential-reference store. access_token_secret_id is a
--     Vault secret handle (uuid). ADMISSION (SELF-197 onboarding route, service_role):
--       secret_id := vault.create_secret(<plaid access token>, 'plaid_item_token_'||
--         <plaid_item_id>, <desc>);  then INSERT plaid_items(..., access_token_secret_id
--         = secret_id). authenticated holds column-level SELECT on NON-credential
--       columns only (access_token_secret_id withheld). No authenticated write.
--   pfin.decrypted_plaid_access_token — decrypt view (JOIN vault.decrypted_secrets to
--     plaid_items); columns (item_id, users_id, plaid_item_id, decrypted_access_token);
--     SELECT to service_role ONLY. Consumers filter `WHERE item_id = $1` and bind tenant
--     in code (Decision 1). Named pfin.* not vault.* (postgres lacks CREATE on vault).
--   pfin.plaid_item_state_history — append-only 4-class credential-error audit.
--   pfin.plaid_sync_audit — append-only cross-language sync audit; plaid_webhook_id
--     UNIQUE idempotency gate (ON CONFLICT (plaid_webhook_id) DO NOTHING under
--     SERIALIZABLE); service_role-only.
--   RETENTION (SD-03 bounded-Item-active-only, SECURITY §4.2 + §4.6) — two legs:
--     LOCAL secret hygiene = the AFTER DELETE ON pfin.plaid_items backstop trigger
--       fn_plaid_items_cleanup_vault_secret (007, SECURITY INVOKER, +0 allowlist):
--       deletes the backing vault.secrets row on ANY Item delete; closes the
--       auth.users ON DELETE CASCADE orphan by-construction (Sec AMBER-required). See
--       the RETENTION BACKSTOP block for the INVOKER fail-closed-on-auth-cascade nuance.
--     PLAID-side revoke = HARD-GATE deferred to SELF-197 /item/remove (non-droppable):
--       in one service_role transaction, read the token via
--       pfin.decrypted_plaid_access_token + revoke it at Plaid BEFORE deleting the row
--       (ordering: revoke needs the token) + emit plaid_sync_audit; the trigger then
--       removes the local secret.
--   Security-load-bearing edges: token stored only in vault.secrets (never on the pfin
--     row); decrypt view service_role-only + tenant-keyed by join (mod #1);
--     plaid_webhook_id UNIQUE (mod #3); append-only triple-fence on both audit tables;
--     set search_path = '' on every function.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.plaid_items — SD-03 credential-reference store (Lock 4 / Decision 8, Option 2).
-- MUTABLE (not audit-class): item_status transitions + token rotation (a new
-- vault.update_secret, same secret_id) are in-place UPDATEs by service_role, so NO
-- immutability fence — only the updated_at refresh.
-- ----------------------------------------------------------------------------
create table if not exists pfin.plaid_items (
  item_id                 bigint generated always as identity primary key,
  users_id                uuid not null default auth.uid()
                            references auth.users (id) on delete cascade,   -- SOLE tenant anchor (direct-owner)
  plaid_item_id           text not null unique,                            -- Plaid external Item ID (AC #2)
  access_token_secret_id  uuid not null,                                   -- Vault secret handle (Option 2; was BYTEA)
  plaid_institution_id    text,                                            -- Plaid institution identifier
  institution_name        text,                                           -- display name (non-credential)
  item_status             text not null default 'healthy'
                            check (item_status in (
                              'healthy',
                              'ITEM_LOGIN_REQUIRED',
                              'INSTITUTION_DOWN',
                              'INSTITUTION_GRANT_REVOKED',
                              'USER_GRANT_REVOKED')),                       -- current state (Decision 16 banner reads this direct)
  is_active               boolean not null default true,                   -- bounded-Item-active-only lifecycle (§4.6)
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table pfin.plaid_items is
  'SD-03 Plaid credential-reference store (ADR-011 Decision 8 / Lock 4, Option 2 Vault-native amendment 2026-07-03; SELF-196). access_token_secret_id is a uuid handle into the platform-managed vault.secrets (the ciphertext lives in Vault, NOT on this row — RT-02 "token never surfaces in a client query" is STRUCTURAL). Admission via vault.create_secret under service_role (SELF-197 onboarding). Decrypt ONLY via pfin.decrypted_plaid_access_token (service_role-only join view, Lock 4 mod #1). users_id = auth.uid() is the SOLE tenant anchor (direct-owner RLS; NOT a Decision-3 instance). access_token_secret_id is deliberately NOT a pfin FK (vault.secrets is a platform-managed global secret store, not part of the pfin isolation graph) and is WITHHELD from the authenticated GRANT. All writes are service_role (privileged-context-write, Decision 1); no authenticated write path. item_status is the current-state column the §2.4.4 re-auth banner + Decision-16 monthly_report live-staleness join read direct. MUTABLE — not audit-class; state transitions are audit-logged in pfin.plaid_item_state_history. RETENTION: the AFTER DELETE backstop trigger fn_plaid_items_cleanup_vault_secret deletes the backing vault.secrets row on any Item delete (SECURITY INVOKER; closes the auth.users cascade orphan — Sec AMBER-required); the Plaid-side revoke is the SELF-197 /item/remove hard-gate.';

alter table pfin.plaid_items enable row level security;

-- RLS: direct-owner. A user sees only their own Plaid Items.
-- NOTE (Decision 8 "inherits account_users.rd_access-JOIN shape" reconciliation):
-- plaid_items carries its OWN users_id (AC #2), so V1 RLS is direct-owner
-- users_id = auth.uid() (mirrors pfin.account). The rd_access-JOIN shape applies to
-- tables with NO own users_id (account_trans); it is a V2-sharing forward-compat
-- note here, not the V1 mechanism. No INSERT/UPDATE/DELETE policy — service_role
-- (RLS-bypassing) is the sole writer per the privileged-context-write discipline.
create policy plaid_items_select on pfin.plaid_items
  for select to authenticated using (users_id = auth.uid());

-- ACL-before-RLS (PR #106 gotcha) — COLUMN-LEVEL SELECT grant EXCLUDING the Vault
-- secret handle. Even with the handle, authenticated cannot read vault.decrypted_secrets
-- (measured FALSE) — this omission is defense-in-depth over that platform ACL.
grant select (item_id, users_id, plaid_item_id, plaid_institution_id,
              institution_name, item_status, is_active, created_at, updated_at)
  on pfin.plaid_items to authenticated;
-- Belt-and-suspenders: ensure the secret handle is not reachable via a broad grant.
revoke all (access_token_secret_id) on pfin.plaid_items from authenticated;

create index if not exists plaid_items_uid_idx on pfin.plaid_items (users_id);

create trigger plaid_items_set_updated_at
  before update on pfin.plaid_items
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- pfin.decrypted_plaid_access_token — service_role-ONLY decrypt view (Lock 4 mod #1).
--   Vault-native (Option 2): joins the platform vault.decrypted_secrets to plaid_items
--   so a service_role read returns the per-Item token keyed by (item_id, users_id),
--   NOT the raw whole-vault surface. Tenant-gating is baked into the view SHAPE (the
--   join to plaid_items), addressing Sec's decrypt-view exposure concern; the consumer
--   still binds tenant in code (Decision 1). Named pfin.* NOT vault.* because
--   has_schema_privilege('postgres','vault','CREATE') = FALSE (measured) — a migration
--   cannot create objects in the platform-owned vault schema. View runs with view-owner
--   (postgres, definer) semantics by PG default; postgres holds SELECT on
--   vault.decrypted_secrets (measured TRUE) so the join resolves.
-- ----------------------------------------------------------------------------
create or replace view pfin.decrypted_plaid_access_token as
  select
    pi.item_id,
    pi.users_id,
    pi.plaid_item_id,
    ds.decrypted_secret as decrypted_access_token
  from pfin.plaid_items pi
  join vault.decrypted_secrets ds on ds.id = pi.access_token_secret_id;

comment on view pfin.decrypted_plaid_access_token is
  'SD-03 decrypt view (ADR-011 Decision 8 / Lock 4 mod #1, Option 2 Vault-native amendment; SELF-196). Joins vault.decrypted_secrets to pfin.plaid_items, exposing ONLY the per-Item Plaid access token keyed by (item_id, users_id) — never the raw whole-vault decrypted_secrets surface (tenant-gating baked into the view shape per Sec). GRANT SELECT to service_role ONLY (Sec load-bearing catch: default decrypt perms would defeat RT-02). Consumed by the service_role Plaid /item/remove + scheduled-poll paths (ARCH §7.1 / SECURITY §4.2 allowlist entry 3); consumers filter WHERE item_id = $1 and bind tenant in code (Decision 1). Named pfin.* not vault.* — postgres lacks CREATE on the vault schema (measured); the service_role-only grant gives the identical security property.';

-- mod #1 — the load-bearing grant: service_role ONLY. Everyone else is denied.
revoke all on pfin.decrypted_plaid_access_token from public;
revoke all on pfin.decrypted_plaid_access_token from anon;
revoke all on pfin.decrypted_plaid_access_token from authenticated;
grant select on pfin.decrypted_plaid_access_token to service_role;

-- ----------------------------------------------------------------------------
-- RETENTION BACKSTOP (SD-03 bounded-Item-active-only) — Sec-required @ AMBER review.
--   Sec's decisive catch: pfin.plaid_items.users_id is ON DELETE CASCADE from
--   auth.users, so a USER deletion cascade-deletes plaid_items rows while their
--   vault.secrets rows do NOT (no FK) -> orphaned credential material, and the
--   SELF-197 /item/remove code path never fires on a cascade. So a DB-layer backstop
--   is required (code-only cleanup is single-layer with a known non-code bypass).
--
--   POSTURE = SECURITY INVOKER (allowlist stays 3 — no DEFINER entry added). MEASURED
--   ROLE FACTS (this is a correction to the AMBER finding's "fires on ALL paths and
--   cleans up" wording — verify before relying on it):
--     - service_role  : DELETE on vault.secrets = TRUE  -> /item/remove (SELF-197) +
--                        scheduled-poll + service_role admin deletes CLEAN UP here.
--     - postgres       : DELETE on vault.secrets = TRUE  -> psql/admin deletes clean up.
--     - supabase_auth_admin (OWNS auth.users; runs the GoTrue user-deletion cascade):
--                        DELETE on vault.secrets = FALSE. A user-defined AFTER DELETE
--                        trigger fires under the DELETING role, so on the auth-cascade
--                        path this INVOKER trigger raises permission-denied and the
--                        user-deletion transaction ABORTS. That is FAIL-CLOSED: the
--                        cascade cannot complete, so NO orphan is ever produced — but
--                        the user-deletion is BLOCKED (not auto-cleaned) until the
--                        Plaid Items are removed via /item/remove first.
--   This satisfies Sec's core invariant (no orphaned credential material BY
--   CONSTRUCTION — via cleanup-or-fail-closed) at allowlist +0, and is CONSISTENT with
--   the schema's existing posture: 004's account_trans ON DELETE RESTRICT + block-trigger
--   already make an auth.users deletion fail when audit rows exist. V1 has NO user-facing
--   deletion (SECURITY §4.6); admin user-deletion is rare + policy-unresolved (the open
--   user-deletion/GDPR-erasure follow-up).
--   SEC RULING (SELF-196): FAIL-CLOSED (this INVOKER shape, +0) is the CORRECT posture,
--   NOT a deferred question — the DEFINER auto-clean alternative would be a SECURITY
--   REGRESSION: deleting the local token while the Plaid Item stays live = an
--   UN-REVOCABLE grant. Sec would veto the DEFINER trade. So fail-closed BY DESIGN.
--   SAFETY IS STRUCTURAL (Sec framing — the load-bearing point): ANY exception raised
--   inside an AFTER DELETE trigger aborts the whole cascading statement, so NO MATTER
--   which error a deleting role hits, the cascade rolls back and NO ORPHAN is produced.
--   The has_table_privilege check + legible RAISE are a best-effort LEGIBILITY
--   optimization for roles that can resolve the name — they are NOT the safety mechanism
--   (delete the guard entirely and safety still holds: the DELETE itself would raise +
--   abort). Do not mistake the privilege-check branch for the safety guarantee.
--   Behaviour by deleting role (Backend-measured):
--     (i)   vault USAGE + vault.secrets DELETE (service_role /item/remove, postgres) ->
--           secret cleaned, no error.
--     (ii)  vault USAGE, no vault.secrets DELETE -> the legible insufficient_privilege
--           RAISE fires ("remove the Item via /item/remove first").
--     (iii) NO vault USAGE (supabase_auth_admin — the REAL GoTrue auth-cascade role;
--           has_schema_privilege('supabase_auth_admin','vault','usage')=FALSE, measured)
--           -> resolving 'vault.secrets' raises a raw "permission denied for schema vault"
--           AT the guard's name-resolution, BEFORE the custom RAISE.
--   (ii) and (iii) both abort the cascade -> no orphan by construction. We do NOT broaden
--   supabase_auth_admin's vault grant to prettify a rare admin-only path (Sec concurrence).
--   Intentional, not a bug.
--   GDPR-ERASURE FORWARD-NOTE: when user-facing deletion lands, the erasure routine MUST
--   enumerate the user's Items -> call /item/remove on each (revoke-at-Plaid +
--   service_role secret-delete) -> THEN delete auth.users. Run under service_role, that
--   sequence cleans up WITHOUT needing a DEFINER trigger — the GDPR follow-up must NOT
--   default to reaching for DEFINER (it would reintroduce the un-revocable-grant regression).
--
--   COMPLEMENTARY hard-gate (Plaid-side leg, DEFERRED to SELF-197, non-droppable):
--   this trigger owns LOCAL secret hygiene only. The /item/remove path still MUST, in
--   one service_role transaction, read the token via pfin.decrypted_plaid_access_token
--   + revoke it at Plaid BEFORE deleting the row (the trigger then removes the secret).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_plaid_items_cleanup_vault_secret()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Local secret hygiene: remove the backing Vault secret when its Item row is deleted
  -- (ANY path). SECURITY INVOKER -> runs as the deleting role. BY-DESIGN fail-closed
  -- (Sec-ruled, SELF-196). SAFETY IS STRUCTURAL: any exception inside an AFTER DELETE
  -- trigger aborts the cascade, so every branch below -> NO ORPHAN regardless of which
  -- error fires; the has_table_privilege check is a LEGIBILITY optimization, NOT the
  -- safety mechanism (remove it and safety still holds — the DELETE itself would raise).
  -- Behaviour by deleting role (all -> NO ORPHAN):
  --   (i)  role holds DELETE on vault.secrets (service_role /item/remove, postgres admin)
  --        -> the delete proceeds; secret cleaned.
  --   (ii) role has vault USAGE but not vault.secrets DELETE -> the IF is FALSE -> the
  --        legible insufficient_privilege RAISE below fires.
  --   (iii) role lacks vault USAGE entirely (e.g. supabase_auth_admin — the REAL GoTrue
  --        auth.users-cascade role; has_schema_privilege(...,'vault','usage')=FALSE,
  --        measured) -> resolving `vault.secrets` in the IF ITSELF raises a raw
  --        "permission denied for schema vault" BEFORE the custom RAISE. Still
  --        fail-closed (cascade aborts, no orphan) — just not the pretty message.
  -- Why fail-closed is CORRECT (all cases): auto-deleting the local token while the Item
  -- stays live at Plaid would leave an un-revocable grant (a security regression) — so
  -- deletion is forced through /item/remove (revoke-at-Plaid then delete). Not worth
  -- broadening supabase_auth_admin's vault grant to prettify a rare admin-only path.
  if not has_table_privilege(current_user, 'vault.secrets', 'DELETE') then
    raise exception
      'cannot delete pfin.plaid_items: Vault secret cleanup requires DELETE on vault.secrets (role % lacks it) — remove the Item via /item/remove first (revoke-at-Plaid then delete). This fail-closed guard prevents an orphaned, un-revocable Plaid credential (ADR-011 Decision 8 Option-2 amendment / SELF-196 Sec ruling).', current_user
      using errcode = 'insufficient_privilege';
  end if;
  -- NULL-safe (a NULL secret id simply matches no row).
  delete from vault.secrets where id = old.access_token_secret_id;
  return old;
end;
$$;

revoke execute on function pfin.fn_plaid_items_cleanup_vault_secret() from public;

comment on function pfin.fn_plaid_items_cleanup_vault_secret() is
  'AFTER DELETE ON pfin.plaid_items retention backstop (ADR-011 Decision 8 Option-2 amendment / SELF-196; Sec-ruled INVOKER). Deletes the backing vault.secrets row (access_token_secret_id) so a deleted Item never leaves orphaned credential material — closing the auth.users ON DELETE CASCADE bypass the SELF-197 /item/remove code path cannot see. SECURITY INVOKER (NOT a DEFINER allowlist entry; allowlist stays 3). Safety is STRUCTURAL — any exception in an AFTER DELETE trigger aborts the cascade, so every branch -> no orphan; the has_table_privilege check is a legibility optimization, not the safety mechanism. Behaviour by deleting role, all fail-closed -> no orphan: (i) holds DELETE on vault.secrets (service_role /item/remove, postgres admin) -> cleans up; (ii) has vault USAGE but no vault.secrets DELETE -> legible insufficient_privilege RAISE ("remove via /item/remove first"); (iii) lacks vault USAGE (e.g. supabase_auth_admin, the GoTrue auth.users-cascade role; measured no vault usage) -> raw "permission denied for schema vault" at the guard check, before the custom RAISE. Fail-closed is Sec-ruled CORRECT: auto-deleting the local token while the Item is still live at Plaid would leave an un-revocable grant (a security regression), so deletion is forced through /item/remove (revoke-then-delete). No orphan by construction (cleanup-or-fail-closed). set search_path = '''' (fully-qualified vault.secrets). EXECUTE revoked from PUBLIC. Complementary to the SELF-197 hard-gate that owns the Plaid-side revoke.';

create trigger plaid_items_cleanup_vault_secret
  after delete on pfin.plaid_items
  for each row execute function pfin.fn_plaid_items_cleanup_vault_secret();

-- ----------------------------------------------------------------------------
-- pfin.plaid_item_state_history — SD-14 append-only 4-class credential-error audit.
-- Records ItemUpdate/ERROR event-state classifications (Lock 4 mod #4). item_id is
-- the SOLE tenant anchor (no own users_id; scope derives via plaid_items). Immutable
-- audit-class (Decision 2): UPDATE + DELETE + TRUNCATE fenced for ALL roles.
-- ----------------------------------------------------------------------------
create table if not exists pfin.plaid_item_state_history (
  history_id        bigint generated always as identity primary key,
  item_id           bigint not null references pfin.plaid_items (item_id) on delete restrict,
  plaid_error_code  text not null
                      check (plaid_error_code in (
                        'ITEM_LOGIN_REQUIRED',
                        'INSTITUTION_DOWN',
                        'INSTITUTION_GRANT_REVOKED',
                        'USER_GRANT_REVOKED')),                             -- 4-class enum verbatim (mod #4)
  plaid_webhook_code text,                                                  -- raw Plaid webhook code (pre-classification), forensic
  detected_at       timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

comment on table pfin.plaid_item_state_history is
  'SD-14 append-only Plaid Item credential-error state-history audit (ADR-011 Decision 8 / Lock 4 mod #4; SELF-196). Records ItemUpdate/ERROR classifications into the 4-class credential-error set per §2.4.4 (ITEM_LOGIN_REQUIRED / INSTITUTION_DOWN / INSTITUTION_GRANT_REVOKED / USER_GRANT_REVOKED). Immutable audit-class (Decision 2): UPDATE + DELETE blocked for ALL roles (fn_plaid_state_history_block_mutation) + TRUNCATE blocked (fn_plaid_state_history_block_truncate) + REVOKE TRUNCATE. NO own users_id — tenant scope derives via item_id -> plaid_items.users_id (SOLE anchor; NOT a Decision-3 instance). Writes are service_role (privileged-context-write, Decision 1); authenticated holds SELECT (via the plaid_items join RLS below), never write.';

alter table pfin.plaid_item_state_history enable row level security;

-- RLS SELECT: a user sees state-history rows only for Plaid Items they own.
create policy plaid_item_state_history_select on pfin.plaid_item_state_history
  for select to authenticated
  using (exists (
    select 1 from pfin.plaid_items pi
    where pi.item_id = plaid_item_state_history.item_id
      and pi.users_id = auth.uid()
  ));
-- NO insert/update/delete policy: service_role (RLS-bypassing) is the sole writer;
-- UPDATE/DELETE additionally blocked for ALL roles by the immutability triggers.

grant select on pfin.plaid_item_state_history to authenticated;

create index if not exists plaid_item_state_history_item_idx
  on pfin.plaid_item_state_history (item_id);

create or replace function pfin.fn_plaid_state_history_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.plaid_item_state_history is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 4). % blocked.', tg_op;
end;
$$;

revoke execute on function pfin.fn_plaid_state_history_block_mutation() from public;

comment on function pfin.fn_plaid_state_history_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.plaid_item_state_history (ADR-011 Decision 2 / Lock 4). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (bypasses RLS but not triggers). INSERT unblocked.';

create trigger plaid_item_state_history_block_mutation
  before update or delete on pfin.plaid_item_state_history
  for each row execute function pfin.fn_plaid_state_history_block_mutation();

create or replace function pfin.fn_plaid_state_history_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.plaid_item_state_history is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 4). TRUNCATE blocked.';
end;
$$;

revoke execute on function pfin.fn_plaid_state_history_block_truncate() from public;

comment on function pfin.fn_plaid_state_history_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.plaid_item_state_history (ADR-011 Decision 2 / Lock 4). SECURITY INVOKER. raise exception. Row-level triggers do NOT fire on TRUNCATE, so this statement-level fence + the REVOKE TRUNCATE below close the audit-retention-wipe path for ALL roles. Distinct message for test-matching.';

create trigger plaid_item_state_history_block_truncate
  before truncate on pfin.plaid_item_state_history
  for each statement execute function pfin.fn_plaid_state_history_block_truncate();

revoke truncate on pfin.plaid_item_state_history from public;

-- ----------------------------------------------------------------------------
-- pfin.plaid_sync_audit — SD-19 append-only cross-language sync audit (Lock 13
-- mod #8 schema-as-contract) + the Lock 4 mod #3 plaid_webhook_id UNIQUE idempotency
-- gate. service_role-ONLY (audit of privileged-context writes; not client-facing).
-- Immutable audit-class (Decision 2). source ENUM discriminator (webhook vs poll).
-- ----------------------------------------------------------------------------
create table if not exists pfin.plaid_sync_audit (
  audit_id          bigint generated always as identity primary key,
  source            text not null
                      check (source in ('webhook', 'scheduled_poll')),     -- Lock 13 mod #8 discriminator
  users_id          uuid references auth.users (id) on delete set null,    -- resolved tenant (Decision 1 clause (d))
  plaid_item_id     text,                                                  -- Plaid external id (TEXT, not a pfin FK)
  plaid_webhook_id  text unique,                                           -- Lock 4 mod #3 idempotency gate (NULL for poll rows)
  webhook_type      text,                                                  -- Plaid webhook type/code, forensic
  detail            jsonb,                                                 -- tenant-resolution chain / event payload snapshot
  created_at        timestamptz not null default now()
);

comment on table pfin.plaid_sync_audit is
  'SD-19 append-only Plaid sync audit (ADR-011 Decision 8 / Lock 4 mod #3 + Decision 17 / Lock 13 mod #8; SELF-196). Cross-language schema-as-contract for the webhook (TS) + scheduled-poll (Python) write paths, discriminated by source. plaid_webhook_id UNIQUE is the Lock 4 mod #3 idempotency gate — the webhook handler INSERTs ON CONFLICT (plaid_webhook_id) DO NOTHING under SERIALIZABLE; poll rows carry NULL (UNIQUE treats NULLs as distinct). users_id records the code-resolved tenant per Decision 1 clause (d) (forensic-detectability of the tenant-resolution chain). service_role-ONLY: NOT granted to authenticated (audit of privileged writes; RLS enabled -> default-deny for authenticated). Immutable audit-class (Decision 2): UPDATE + DELETE + TRUNCATE fenced for ALL roles. plaid_item_id is TEXT external id (mirrors account_trans.plaid_transaction_id), NOT a pfin FK -> NOT a Decision-3 instance.';

alter table pfin.plaid_sync_audit enable row level security;
-- NO policy + NO grant to authenticated: default-deny. service_role (RLS-bypassing)
-- is the sole reader/writer. This is an internal audit log, not a user surface.

create index if not exists plaid_sync_audit_users_idx on pfin.plaid_sync_audit (users_id);
create index if not exists plaid_sync_audit_item_idx on pfin.plaid_sync_audit (plaid_item_id);

create or replace function pfin.fn_plaid_sync_audit_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.plaid_sync_audit is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 13). % blocked.', tg_op;
end;
$$;

revoke execute on function pfin.fn_plaid_sync_audit_block_mutation() from public;

comment on function pfin.fn_plaid_sync_audit_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.plaid_sync_audit (ADR-011 Decision 2 / Lock 13 mod #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role. INSERT (incl. ON CONFLICT DO NOTHING idempotent webhook writes) unblocked.';

create trigger plaid_sync_audit_block_mutation
  before update or delete on pfin.plaid_sync_audit
  for each row execute function pfin.fn_plaid_sync_audit_block_mutation();

create or replace function pfin.fn_plaid_sync_audit_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.plaid_sync_audit is immutable (append-only audit-class; ADR-011 Decision 2 / Lock 13). TRUNCATE blocked.';
end;
$$;

revoke execute on function pfin.fn_plaid_sync_audit_block_truncate() from public;

comment on function pfin.fn_plaid_sync_audit_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.plaid_sync_audit (ADR-011 Decision 2 / Lock 13). SECURITY INVOKER. raise exception. Statement-level fence + REVOKE TRUNCATE close the audit-retention-wipe path (row-level triggers do not fire on TRUNCATE). Distinct message for test-matching.';

create trigger plaid_sync_audit_block_truncate
  before truncate on pfin.plaid_sync_audit
  for each statement execute function pfin.fn_plaid_sync_audit_block_truncate();

revoke truncate on pfin.plaid_sync_audit from public;
