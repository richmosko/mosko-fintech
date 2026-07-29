-- ============================================================================
-- Migration: pfin.linked_source_sync_audit.linked_source_id — stable source key +
--            040 sync-history view re-join (SELF-207 orthogonality fix; F/CTO option b)
-- Phase 6 Build Loop (SELF-207 / §2.4.4.b). Decouples sync-history identity from the
-- MUTABLE (provider, external_connection_id) digest so a SimpleFIN re-auth (which mints a
-- new Access URL → new digest via the shipped in-place vault.update_secret re-admission)
-- no longer orphans a connection's pre-reauth sync history from the 040
-- linked_source_sync_history view. Adds a stable linked_source_id to the (immutable)
-- sync-audit table, backfills it, fences it (Decision-3 #15), and re-joins the 040 view
-- on it instead of the digest. Architect-caught schema-orthogonality; F/CTO ratified
-- option (b) 2026-07-29.
--
-- Numbering: 044 follows 043_linked_source_connection_state. 042=SELF-199 RPC,
-- 043=connection-state view, 044=this. (The deferred OWD-A A3 typed sync-cursor migration
-- takes a later number at SELF-206.) Depends on: 015 (linked_source_sync_audit + its
-- immutability triggers + linked_source), 040 (the linked_source_sync_history view this
-- re-joins). Lands SAME-PR with SELF-207 + the Backend worker-writer companion (see the
-- HARD COUPLING note). No downstream migration depends on 044.
--
-- ----------------------------------------------------------------------------
-- WHY A PLAIN bigint COLUMN, NOT A DECLARED FK (the immutable-table conflict).
--   linked_source_sync_audit is IMMUTABLE audit-class: linked_source_sync_audit_block_mutation
--   fires BEFORE UPDATE OR DELETE and raises for ALL roles incl. service_role (015). A
--   DECLARED FK linked_source_id -> linked_source(source_id) is therefore UNBUILDABLE without
--   breaking connection-removal:
--     - ON DELETE CASCADE  -> tries to DELETE audit rows on source removal -> block_mutation
--       raises -> the linked_source delete FAILS (removal broken).
--     - ON DELETE SET NULL -> tries to UPDATE audit rows -> block_mutation raises -> removal FAILS.
--     - ON DELETE RESTRICT -> a source with ANY audit row can NEVER be deleted (audit rows are
--       never deletable) -> removal PERMANENTLY blocked.
--   So this is a PLAIN bigint reference column (no FK constraint) whose referential correctness
--   + tenant-matching are enforced at write time by the Decision-3 #15 trigger below (this is
--   already how the Decision-3 family is realized project-wide — matched-tenant TRIGGERS, not
--   declared FKs; e.g. #6 fn_account_matched_linked_source). Connection removal keeps its
--   current behavior: it simply leaves the audit rows with a now-dangling linked_source_id,
--   which the 040 view's INNER join excludes (exactly as the digest-orphan is excluded today).
--
-- ----------------------------------------------------------------------------
-- NULLABLE (not NOT NULL) + LENIENT fence — backfill totality + deploy-ordering safety.
--   The column is NULLABLE, for two reasons:
--     (1) Backfill cannot be total: audit rows whose source was REMOVED (linked_source row
--         gone) have no live digest match -> they stay NULL (correctly excluded from the
--         owner view, same as today's digest-orphans).
--     (2) Deploy ordering: the migration applies to the DB before the updated worker
--         redeploys. A STRICT "require non-null on INSERT" fence would REJECT the OLD worker's
--         sync-audit inserts during the deploy window -> sync breaks. So the fence is LENIENT:
--         it validates matched-tenant WHEN linked_source_id IS NOT NULL (the Decision-3
--         requirement — a NULL is a completeness gap, not a cross-tenant-FK-bypass, so no
--         Decision-3 threat), and TOLERATES NULL (old-worker/transition rows orphan from the
--         view until the companion ships, never breaking sync).
--   NULL semantics: linked_source_id IS NULL == "pre-companion / removed-source" row; excluded
--   from the id-joined 040 view (owner-safe, correct).
--   >>> HARD COUPLING (route to Backend): the sync WRITERS (poll worker writeAudit + the
--       SELF-206 webhook path) MUST populate linked_source_id going forward (they know the
--       source_id). QA verifies the worker populates it. RECOMMENDED FOLLOW-UP (separate
--       later migration, once the companion is confirmed deployed + a "no NULL linked_source_id
--       in recent rows" check passes): TIGHTEN the fence to require-non-null on INSERT. Not done
--       here to keep this migration deploy-safe.
--
-- ----------------------------------------------------------------------------
-- BACKFILL requires transiently DISABLING the immutability trigger (documented, migration-scoped).
--   Backfilling linked_source_id on existing rows is an UPDATE, which block_mutation blocks for
--   all roles. The migration (running as the table owner, in ONE transaction) DISABLES
--   linked_source_sync_audit_block_mutation, runs the derived-column backfill, then RE-ENABLES it.
--   SAFE: one-time, migration-scoped, adds a DERIVED column value (no audit-data semantics
--   changed), re-enabled in the same transaction (a failure rolls back the DISABLE too — Supabase
--   migrations are transactional). The append-only guarantee for runtime roles (authenticated +
--   service_role) is UNCHANGED after this migration. Backfill matches on
--   (provider, external_connection_id, users_id) — safe NOW because NO reauth has mutated any
--   digest yet (every current digest still matches its source); the users_id predicate is
--   belt-and-suspenders (the digest is globally partial-unique per provider, so it already
--   identifies one source) so a corrupt cross-tenant digest would leave the row NULL, not
--   mis-attribute it. The Decision-3 #15 fence does NOT fire on this UPDATE (it is BEFORE INSERT).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — the fence fn is SECURITY INVOKER (NOT DEFINER); allowlist stays 4.
--   fn_sync_audit_matched_linked_source mirrors #6 fn_account_matched_linked_source: it reads
--   pfin.linked_source and raises on a cross-tenant/nonexistent reference; it needs no elevation.
--   Under service_role (the sync-audit writer) RLS is bypassed, so the EXISTS is authoritative
--   over all sources -> it validates the TRUE owner. set search_path = '' is the injection fence.
--   Not a DEFINER allowlist entry (INVOKER) -> DEFINER allowlist UNCHANGED at 4.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the numbered
--   list; Decision 4 read verbatim before drafting).
--   ZERO catalogued §10 instances; ledger stays at 3 (RT-22 first / RT-26 second / RT-27 third).
--   (i) instance-numbering unchanged. (ii) layer-attribution — this adds a column + an INVOKER
--   trigger + a view re-join on a service_role-only table; it touches NO infra-credential-presence
--   (RT-22), NO SUPABASE_SERVICE_ROLE_KEY code-layer allowlist (RT-26 — no web-app source, no new
--   service_role key reference), and NO app->worker admission surface (RT-27). The transient
--   trigger-disable is a migration-time schema op, not a §10 surface. (iii) Decision 4 linked,
--   not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family +1 (14 -> 15 labeled;
--   12 -> 13 DDL-realized). NEW CANONICAL INSTANCE #15:
--     pfin.linked_source_sync_audit.linked_source_id -> pfin.linked_source(source_id).
--     BOTH sides are per-user (sync_audit.users_id is the resolved-tenant anchor; linked_source
--     .users_id is the direct owner), so a bare reference (existence-only) would let a worker bug
--     bind an audit row to ANOTHER tenant's source — the exact chain attack Decision 3 fences.
--     Fenced by fn_sync_audit_matched_linked_source (BEFORE INSERT, INVOKER, NULL-safe fail-closed,
--     lenient-on-null per above) — mirrors #6 (015) / #5 (012). Sec joint-review-mandatory
--     (Decision-3 extension). Verify the live count against ADR-011 Decision 3 at joint-review.
--   NOT Decision-3 (unchanged): sync_audit.users_id -> auth.users (resolved-tenant SOLE anchor);
--     external_connection_id (text, not a reference).
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   Two-tenant pgTAP battery:
--     - THE POINT: owner's sync-history SURVIVES a SimpleFIN reauth digest-mutation — after
--       linked_source.external_connection_id is changed, the owner's pre-reauth rows still appear
--       in the 040 view (id-join) and last_successful_sync_at (043) does NOT reset;
--     - Decision-3 #15: a sync_audit INSERT with a cross-tenant linked_source_id fails closed
--       (the fence); a same-tenant linked_source_id passes; a NULL linked_source_id inserts
--       (lenient) but is excluded from the owner view;
--     - backfill correctness: existing resolvable rows get linked_source_id = their source; a
--       removed-source (orphan) row stays NULL and is excluded from the view;
--     - the 040 view stays owner-scoped: tenant A sees ZERO of tenant B's sync rows after the
--       re-join (both-sides users_id = auth.uid() preserved);
--     - immutability intact AFTER the migration: a runtime UPDATE/DELETE on sync_audit still
--       fails (block_mutation re-enabled).
--   Sec joint-review-mandatory (Decision-3 #15 + the 040-view join change / owner-scope re-review).
--   Not a vacuous green — fixture must populate two tenants + simulate a digest mutation.
--
-- CONTRACT
--   pfin.linked_source_sync_audit gains linked_source_id bigint (NULLABLE, plain reference —
--     no declared FK; matched-tenant-fenced). Backfilled from (provider, external_connection_id,
--     users_id). Index sync_audit_linked_source_idx on (linked_source_id).
--   pfin.fn_sync_audit_matched_linked_source() RETURNS trigger — INVOKER, set search_path = '',
--     BEFORE INSERT: raise if linked_source_id IS NOT NULL AND no same-(users_id) linked_source
--     with that source_id exists (Decision-3 #15). EXECUTE revoked from PUBLIC.
--   pfin.linked_source_sync_history (040) view re-created: IDENTICAL projection + owner-semantics
--     (security_barrier = true, security_invoker = false) + both-sides owner-scope; the ONLY change
--     is the join key (provider, external_connection_id) -> source_id = linked_source_id.
-- ============================================================================

create schema if not exists pfin;

-- (1) Stable source key on the immutable sync-audit table (plain bigint; no declared FK).
alter table pfin.linked_source_sync_audit
  add column if not exists linked_source_id bigint;

comment on column pfin.linked_source_sync_audit.linked_source_id is
  'Stable connection key (SELF-207 / 044; F/CTO option b). References pfin.linked_source(source_id) as a PLAIN bigint (NO declared FK — a declared FK is unbuildable against this immutable table without breaking connection-removal: every ON DELETE action would delete/update immutable rows or restrict the source delete). Referential correctness + tenant-matching enforced at write by fn_sync_audit_matched_linked_source (Decision-3 #15). Decouples sync-history identity from the MUTABLE (provider, external_connection_id) digest so a SimpleFIN reauth digest-mutation no longer orphans pre-reauth history from the 040 view. NULLABLE: pre-companion / removed-source rows are NULL (excluded from the id-joined 040 view). Sync WRITERS populate it going forward.';

create index if not exists sync_audit_linked_source_idx
  on pfin.linked_source_sync_audit (linked_source_id);

-- (2) Backfill existing rows (transiently disable the immutability trigger — see header).
--     Safe NOW: no reauth has mutated any digest, so every current digest still matches its source.
alter table pfin.linked_source_sync_audit
  disable trigger linked_source_sync_audit_block_mutation;

update pfin.linked_source_sync_audit lsa
set linked_source_id = ls.source_id
from pfin.linked_source ls
where ls.provider = lsa.provider
  and ls.external_connection_id = lsa.external_connection_id
  and ls.users_id = lsa.users_id
  and lsa.linked_source_id is null;

alter table pfin.linked_source_sync_audit
  enable trigger linked_source_sync_audit_block_mutation;

-- (3) Decision-3 #15 matched-tenant fence (BEFORE INSERT; lenient-on-null; INVOKER).
create or replace function pfin.fn_sync_audit_matched_linked_source()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Validate ONLY when a source is referenced. A NULL is a completeness gap (pre-companion /
  -- transition), not a cross-tenant-FK-bypass, so it carries no Decision-3 threat and is tolerated
  -- (deploy-safety — the old worker keeps writing during the deploy window). When present, the
  -- referenced source MUST be same-tenant as the audit row's resolved users_id. NULL-safe
  -- fail-closed: a cross-tenant / nonexistent source (or a NULL users_id) -> NOT EXISTS -> raise.
  if new.linked_source_id is not null
     and not exists (
       select 1 from pfin.linked_source ls
       where ls.source_id = new.linked_source_id
         and ls.users_id  = new.users_id
     ) then
    raise exception
      'pfin.linked_source_sync_audit.linked_source_id % is not a same-tenant source for users_id % (Decision-3 #15 matched-tenant fence)',
      new.linked_source_id, new.users_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_sync_audit_matched_linked_source() from public;

comment on function pfin.fn_sync_audit_matched_linked_source() is
  'BEFORE INSERT matched-tenant fence on pfin.linked_source_sync_audit.linked_source_id (ADR-011 Decision 3 canonical instance #15; SELF-207 / 044). Rejects binding an audit row to another tenant''s source: when linked_source_id IS NOT NULL, the referenced linked_source must share the row''s resolved users_id. Lenient-on-null (a NULL is a completeness gap, not a cross-tenant bypass — deploy-safety during the worker-companion rollout; a follow-up migration may tighten to require-non-null once the companion is confirmed). NULL-safe fail-closed (NOT EXISTS -> raise). SECURITY INVOKER + set search_path = '''' — authoritative under service_role (BYPASSRLS) so it validates the true owner. Mirrors #6 fn_account_matched_linked_source / #5 fn_account_matched_sub_cat. Not a DEFINER allowlist entry (INVOKER); allowlist stays 4. INSERT is the only live mutation path (UPDATE/DELETE blocked by the immutability trigger).';

create trigger linked_source_sync_audit_matched_source
  before insert on pfin.linked_source_sync_audit
  for each row execute function pfin.fn_sync_audit_matched_linked_source();

-- (4) Re-join the 040 sync-history view on the STABLE linked_source_id (was: the mutable digest).
--     IDENTICAL projection + owner-semantics + both-sides owner-scope; ONLY the join key changes.
create or replace view pfin.linked_source_sync_history
  with (security_barrier = true, security_invoker = false) as
  select
    ls.source_id      as linked_source_id,
    lsa.provider,
    lsa.source,
    lsa.created_at,
    (lsa.detail -> 'result' ->> 'transactionsInserted')::int as transactions_inserted,
    (lsa.detail -> 'result' ->> 'transactionsSkipped')::int  as transactions_skipped
  from pfin.linked_source_sync_audit lsa
  join pfin.linked_source ls
    on ls.source_id = lsa.linked_source_id       -- STABLE key (044); was (provider, external_connection_id)
   and ls.users_id = auth.uid()                  -- owner-scoped join (fail-closed, cannot widen) — PRESERVED
  where lsa.users_id = auth.uid();               -- owner-scope on the audit side — PRESERVED

grant select on pfin.linked_source_sync_history to authenticated;

comment on view pfin.linked_source_sync_history is
  'OWNER-SEMANTICS security_barrier view (security_invoker=false): the base linked_source_sync_audit is service_role-only; this is the sole authenticated read path. Per-connection sync history (ADR-034; SELF-204). Projection UNCHANGED (Sec-verified allowlist: linked_source_id, provider, source, created_at, transactions_inserted, transactions_skipped — never detail / detail->result / event_type / external_connection_id / provider_event_id / errlist / error / ok / syncedAt). Owner-scope UNCHANGED: both-sides users_id = auth.uid() (fail-closed, cannot widen; INNER join excludes an unresolvable connection). CHANGE (044): the audit->source join is now on the STABLE linked_source_id, NOT the mutable (provider, external_connection_id) digest — so a SimpleFIN reauth (new Access URL -> new digest) no longer orphans pre-reauth history; a removed-source (NULL linked_source_id) row is excluded, same as before. Consumed by SELF-204 SyncHistoryTable + the 043 connection-state view''s last_successful_sync_at.';
