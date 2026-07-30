-- ============================================================================
-- Migration: pfin — SELF-206 §2.4.4.a Plaid webhook DB surface (Route Z-INVOKER)
--   (A) fn_plaid_webhook_resolve + fn_plaid_webhook_commit — the two-phase
--       privileged-context-write RPC pair the api/src webhook handler calls.
--   (B) pfin.linked_source.sync_cursor — the OWD-A A3 typed incremental-sync
--       cursor column (relocated out of provider_metadata jsonb).
-- Phase 6 Build Loop (SELF-206 / §2.4.4.a; ADR-037 Decision 2 SELF-206 row +
--   Decision 3 OWD-A A3 + Decision 6 build-step 4). Closes / composes RT-05
--   (signature-verify, app-layer) + ADR-011 Decision 1 (privileged-context-write)
--   + Decision 2 (immutable audit-class) + Decision 3 #15 (consumed, not added)
--   + Lock 11 (INVOKER composition). V1-SHIP-BLOCK · sec-joint-review-mandatory.
--
-- Numbering: 045 follows 044 (sync_audit stable linked_source_id, SELF-207).
--   The ADR-037 (2026-07-29 amendment) DEFERRED "OWD-A A3 typed sync-cursor
--   migration to SELF-206 at the next free number" — that is THIS file (045).
--   Depends on: 015 (linked_source + connection_status enum + linked_source_
--   state_history + linked_source_sync_audit + provider_event_id UNIQUE gate +
--   the service_role full-table grant that lets these INVOKER fns write under
--   service_role), 044 (linked_source_sync_audit.linked_source_id + the #15
--   fn_sync_audit_matched_linked_source BEFORE-INSERT fence this migration's
--   commit fn relies on). No downstream migration depends on 045.
--
-- HARD COUPLING (route to Backend): the api/src handler orchestrates the two
--   RPCs around an EXTERNAL worker /admission/sync call (Option A landing —
--   PLAID_SECRET is worker-only; the handler never fetches Plaid). The ORDERING
--   (resolve → external sync → commit-gate) is the C-X2 closure and is a
--   handler+RPC JOINT contract — see the C-X2 CLOSURE block below.
--
-- ----------------------------------------------------------------------------
-- provider_event_id SEMANTICS — id-gating is RESERVED for the STATE/ITEM path; the
--   TRANSACTIONS path is deduped by the /transactions/sync CURSOR, NOT the id-gate.
--   [SDK-verified with backend-self206; team-lead-steered reconciliation.]
--   WHY THE SPLIT: plaid@27's SyncUpdatesAvailableWebhook body is {webhook_type,
--   webhook_code, item_id, initial_update_complete, historical_update_complete,
--   environment} — NO per-event id / timestamp / count. In steady state (both booleans
--   true) EVERY transactions notification for an item is BYTE-IDENTICAL. The handler's
--   per-delivery id is 'plaid:<iat>:<request_body_sha256>' from the VERIFIED JWT — but
--   JWT `iat` is INTEGER SECONDS, so two SYNC_UPDATES_AVAILABLE for the same item within
--   the SAME wall-clock second collide (same iat + identical body → same id). Gating the
--   SYNC on that id would let the 2nd delivery be marked already_processed → a legit new
--   sync DROPPED → money-flow data loss (recovery would then fall back to the Plaid poll's
--   operational cadence — SELF-213/DevOps — instead of being closed here by construction).
--   The /transactions/sync CURSOR is the SEMANTICALLY-CORRECT dedup for transactions (it
--   self-dedups: advances only on real new data + fn_ingest_transactions ON CONFLICT), so
--   layering the id-gate on top adds a false-collision surface for zero correctness gain.
--   THE RULE (handler + RPC contract):
--     - TRANSACTIONS events (is_transactions_event=true): provider_event_id = NULL. The
--       sync decision is should_trigger_sync = is_transactions_event (NEVER gated by the
--       id). Every resolved transactions delivery fires a cursor-idempotent sync. The
--       audit row lands with NULL id (forensic; NULLs distinct in the UNIQUE index → no
--       collision, no dedup). Trade-off ACCEPTED: no exact-JWT-replay suppression on the
--       transactions path — bounded instead by RT-05 `iat` freshness (~5min) + the sync
--       being idempotent + cheap (incremental via the A3 cursor). Sec-confirm at review.
--     - STATE / ITEM events (is_transactions_event=false, no cursor): provider_event_id =
--       the per-delivery 'plaid:<iat>:<body_sha256>' (non-null; RPC-2 RAISEs on NULL —
--       AC2). RPC-1 already_processed suppresses an EXACT-JWT replay of a state event
--       (the handler short-circuits to 200); a re-signed Plaid retry (new iat) → new id →
--       not already_processed → re-processed (state writes are only-on-change → idempotent
--       no-op anyway). MUST NOT be hardened into a Plaid-retry dedup.
--   AC2 RECONCILIATION: "idempotency gate" is satisfied per-path — the CURSOR for
--   transactions, the provider_event_id UNIQUE gate for state events. Documented +
--   Sec-joint-review item.
--
-- ----------------------------------------------------------------------------
-- WHY AN RPC PAIR, NOT A CLIENT-SIDE TRANSACTION (the PostgREST transport limit).
--   The api/src handler talks to Postgres via supabase-js/PostgREST (service_role
--   client from supabase-admin.ts). PostgREST runs EACH .from()/.insert()/.rpc()
--   as its OWN transaction — it CANNOT hold a multi-statement BEGIN SERIALIZABLE
--   open across calls. The ARCH §3.1 blueprint's "BEGIN SERIALIZABLE … COMMIT"
--   spanning idempotency-gate + resolve + state-history + audit is therefore NOT
--   expressible over that transport (M10 doc-delta amends §3.1). Route Z-INVOKER:
--   move the atomic write body into ONE Postgres function (fn_plaid_webhook_commit)
--   whose plpgsql body IS one transaction — genuine all-or-nothing on the
--   immutable audit-class ledger. A separate read-only fn (fn_plaid_webhook_resolve)
--   is the side-effect-free pre-flight. This is the write analogue of the Lock 11
--   INVOKER read-composition helpers (fn_compute_nav / …) and the fn_create_manual_
--   account (ADR-026 / 013) INVOKER write-composition precedent.
--
-- ----------------------------------------------------------------------------
-- C-X2 CLOSURE — lost-sync hazard + why sync-FIRST / gate-at-COMPLETION closes it.
--   HAZARD (Sec C-X2): the AC5 transaction sync is an EXTERNAL HTTP call to the
--   worker, OUTSIDE any DB transaction. If the gate were claimed at RECEIPT (before
--   the sync) and the handler crashed after claim but before the sync completed,
--   Plaid's retry would hit ON CONFLICT DO NOTHING → "already seen" → the handler
--   would skip the sync → the transactions sync is SILENTLY LOST. The closure below is
--   SELF-CONTAINED — it does NOT rely on a poll backstop: Plaid's at-least-once webhook
--   retry + sync idempotency re-drive it. (A code-level Plaid poll DOES exist — poll.ts /
--   SELF-279, POLL_PROVIDERS includes 'plaid', PlaidAdapter.fetch* are real — but its
--   OPERATIONAL cadence / prod-tier activation is a deployment matter tracked at SELF-213;
--   the design is correct with or without it, so the closure does not depend on it.)
--   CLOSURE (the ordering this migration is shaped for): the gate/audit row is
--   written ONLY at COMPLETION (fn_plaid_webhook_commit), AFTER the handler has
--   confirmed the external sync dispatched. Every step before the gate is
--   individually idempotent:
--     - fn_plaid_webhook_resolve is READ-ONLY (a pure re-runnable SELECT);
--     - the sync itself is idempotent (Plaid /transactions/sync cursor is only
--       advanced on success + fn_ingest_transactions ON CONFLICT (source_provider,
--       provider_txn_id) DO NOTHING dedups — 017);
--     - the state flip + state_history append are only-on-change (a replay where
--       connection_status already equals the target is a no-op → NO duplicate rows).
--   So a crash anywhere before commit → no gate row → Plaid retries → resolve
--   re-reads → sync re-drives (cursor-idempotent) → commit lands the audit row. For the
--   TRANSACTIONS path the re-drive is unconditional (the sync decision is not id-gated —
--   see the SEMANTICS block; the cursor makes every re-drive a no-op-or-incremental), so
--   the closure rests on cursor-idempotency, NOT on the gate distinguishing deliveries.
--   Bounded cost: redundant but idempotent re-syncs (cheap, incremental via the A3 cursor)
--   until one delivery completes. RESIDUAL (honestly disclosed): a persistently-failing
--   sync on an item that then goes DORMANT is re-driven by the next webhook or the
--   code-level Plaid poll (poll.ts / SELF-279); the poll's OPERATIONAL cadence (cron /
--   prod-tier / live sources) is a deployment matter tracked at SELF-213 — no DB ordering
--   closes this tail without such a drain; documented + F/CTO-accepted for V1.0. Satisfies Sec C-X1 (200 only on full completion;
--   5xx on any partial failure → Plaid retries). NO new table, NO change to the immutable
--   audit-class, NO new ledger instance — see below.
--   The ordering/gate-semantic is a CODE+CONTRACT convention (reversible; no data
--   migration to change it later) — NOT a schema one-way door.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — BOTH functions are SECURITY INVOKER (Lock 11 default); NO
--   SECURITY DEFINER. **DEFINER allowlist STAYS 4** (4 labeled / 3 authored per
--   ADR-011 Decision 9 — fn_refresh_updated_at @001 + fn_grant_creator_access @003
--   + fn_reclass_history_insert @031; general audit-log helper still unauthored).
--   The SOLE caller is the api/src handler's service_role client (supabase-admin.ts,
--   the RT-26 allowlisted factory). A SECURITY INVOKER function invoked BY service_role
--   runs WITH service_role privileges + BYPASSRLS → every write the body needs
--   (INSERT state_history / UPDATE linked_source.connection_status / INSERT sync_audit)
--   is one service_role already holds via the 015 step-9 grants → all writes succeed
--   under INVOKER. No elevation is needed → DEFINER would be gratuitous (a Sec-veto
--   surface for nothing — the fn_create_manual_account / ADR-026 precedent). Tenant
--   correctness is bound IN THE FUNCTION by resolving users_id/source_id FROM the Item
--   id (never from caller-supplied keys) — ADR-011 Decision 1 privileged-context-write.
--   EXECUTE is granted to service_role ONLY (NOT authenticated/anon) — these are
--   webhook-internal fns; exposing resolve to authenticated would leak another
--   tenant's users_id given an Item id.
--
-- ----------------------------------------------------------------------------
-- AUDIT-LOG A2 (ADR-026 conscious deferral) — the sync_audit gate row IS the AC2
--   idempotency gate AND the AC6 sync-audit row (provider='plaid', source='webhook',
--   provider_event_id, detail = tenant-resolution chain + sync outcome). SELF-206 does
--   NOT emit the reserved GENERAL forensic same-transaction audit-log (that DEFINER
--   helper is still unauthored — SELF-201 Task #7); a forward-hook comment marks where
--   it would attach. Consistent with ADR-026's A2 deferral.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list; Decision 4 read VERBATIM before drafting).
--   ZERO catalogued §10 instances; ledger STAYS at 3 (RT-22 first / RT-26 second /
--   RT-27 third).
--   (i) instance-numbering — unchanged (not touched).
--   (ii) layer-attribution — this migration authors app-callable DB RPCs (service_role
--        EXECUTE grant = a DB-LAYER ACL) + a plain text column. It touches NO
--        infrastructure-credential-presence surface (RT-22 = PDF-worker container
--        credential audit), NO SUPABASE_SERVICE_ROLE_KEY CODE-LAYER allowlist grep
--        fence (RT-26 governs WHERE the service key is REFERENCED in web-app/worker
--        SOURCE — a DB EXECUTE grant is not a source reference; the handler's
--        service_role client is the ALREADY-catalogued RT-26 allowlist entry
--        supabase-admin.ts, and calling .rpc() from it adds no new reference →
--        RT-26 allowlist STAYS 4), and NO app→worker credential-admission network-
--        exposure surface (RT-27 = the private-bind admission endpoint). The worker
--        /admission/webhook-verification-key + /admission/sync routes Backend adds are
--        ROUTES on the EXISTING RT-27 listener (mirrors the SELF-212 /admission/
--        simplefin/claim + SELF-207 reauth-leg precedent), NOT new §10 instances —
--        annotated in the M10 doc-delta (temp/self-206-doc-deltas.md (c)), Sec co-sign.
--   (iii) Decision 4 is linked, not restated.
--   DE-CONFLATION GUARD: the #15 matched-tenant fence this migration's commit fn
--   relies on (044) and the audit-class immutability of linked_source_sync_audit (015)
--   are Decision-3 / Decision-2 mechanisms on SEPARATE ledgers — not §10 instances.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family +0 (stays 15 labeled
--   / 13 DDL-realized). This migration authors NO new FK-shaped reference column:
--     - fn_plaid_webhook_commit CONSUMES linked_source_sync_audit.linked_source_id
--       (the 044 #15 column) when it INSERTs the gate row — the existing #15 fence
--       fn_sync_audit_matched_linked_source fires BEFORE INSERT and validates the
--       linked_source_id is same-tenant as the row's users_id. Both are re-resolved
--       from the SAME linked_source row inside the fn, so they are matched by
--       construction; the #15 fence is the belt-and-suspenders backstop. It EXERCISES
--       #15, it does not ADD an instance.
--     - (B) linked_source.sync_cursor is `text`, NOT a reference → NOT a Decision-3
--       instance. linked_source.users_id remains the SOLE tenant anchor (direct-owner)
--       → D3-NEUTRAL per the ADR-037 Decision 4 governance note.
--   The canonical enumeration (ADR-011 Decision 3) is UNCHANGED. Verify the live count
--   against ADR-011 Decision 3 at joint-review.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   Two-tenant pgTAP battery (extends the SELF-206 webhook battery already scoped):
--     - AC8 tenant isolation: fn_plaid_webhook_commit fed tenant A's Item id can
--       NEVER write a row attributed to tenant B — tenant is resolved FROM the Item
--       id inside the fn, never from a caller key; a forged users_id in p_event is
--       ignored (the fn does not read it); the #15 fence fails closed on any mismatch.
--     - unknown/foreign Item id → fn_plaid_webhook_resolve returns resolved=false and
--       writes NOTHING (fail-closed, no cross-tenant write).
--     - STATE-event idempotency: two commits with the SAME (non-null) provider_event_id
--       → the second is a no-op (was_fresh=false), exactly one audit row; a NULL
--       provider_event_id on a STATE event (is_transactions_event=false) → RAISE (AC2).
--     - TRANSACTIONS-path dedup: a transactions event carries NULL provider_event_id →
--       commit does NOT raise; TWO distinct transactions notifications for the same item
--       (same byte-identical body) both fire a sync and both land an audit row (NULLs
--       distinct → no false-collision drop); resolve NEVER returns should_trigger_sync=false
--       for a resolved transactions event on account of the id-gate. (The cursor is the
--       dedup — verified by the worker/adapter cursor test, not this DB battery.)
--     - C-X2 replay: resolve is side-effect-free; a re-driven transactions event (no prior
--       gate) re-syncs; a STATE event whose exact-JWT delivery already committed →
--       already_processed=true (handler short-circuits).
--     - state transition: commit appends state_history + flips connection_status ONLY
--       on a real change; a same-status replay adds no row.
--     - (B) cursor: owner cannot read/write sync_cursor via the Data API (not in the
--       authenticated column grant); service_role reads/writes it; users_id sole
--       anchor (no cross-tenant surface).
--   Sec joint-review-mandatory (external-API webhook write path + RT-05 composition +
--   privileged-context-write + audit-class INSERT + the AC2 per-path idempotency
--   reconciliation: cursor for transactions / provider_event_id gate for state). Not a
--   vacuous green — the fixture must populate two tenants + a STATE-event duplicate-id
--   replay + a TRANSACTIONS pair with NULL ids + a foreign Item.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   (B) pfin.linked_source.sync_cursor text (NULLABLE) — the typed incremental-sync
--       cursor (Plaid /transactions/sync opaque cursor; SimpleFIN watermark). Read at
--       sync start + advanced on sync success by the service_role worker sync path.
--       Relocated out of provider_metadata jsonb (OWD-A A3). NOT granted to
--       authenticated (belt-and-suspenders REVOKE, mirrors credential_secret_id).
--       users_id sole anchor → D3-neutral. NULL = never-synced / pre-cursor.
--   (A1) pfin.fn_plaid_webhook_resolve(p_event jsonb)
--          RETURNS TABLE(resolved boolean, already_processed boolean,
--                        should_trigger_sync boolean, source_id bigint, users_id uuid)
--        SECURITY INVOKER, set search_path='', STABLE (read-only). Resolves tenant
--        FROM p_event->>'item_id' (privileged-context-write binding). already_processed =
--        a STATE-event exact-JWT-replay pre-check (NULL id → false). should_trigger_sync =
--        is_transactions_event (NOT id-gated). NO writes. Fail-closed: unknown Item →
--        resolved=false. service_role EXECUTE only.
--   (A2) pfin.fn_plaid_webhook_commit(p_event jsonb)
--          RETURNS TABLE(committed boolean, was_fresh boolean)
--        SECURITY INVOKER, set search_path='', VOLATILE. ONE atomic transaction:
--        re-resolve tenant from Item id (fail-closed RAISE if gone; RAISE on NULL
--        provider_event_id ONLY for a STATE event — transactions carry NULL) →
--        state_history append + connection_status flip ONLY-ON-CHANGE (from
--        p_event->>'status_class' + provider_error_code; NULL status_class → no state
--        write) → INSERT linked_source_sync_audit gate/audit row (provider='plaid',
--        source='webhook', provider_event_id ON CONFLICT DO NOTHING [NULLs distinct],
--        users_id + linked_source_id re-resolved → #15 fence validates). was_fresh =
--        row inserted. service_role EXECUTE only.
--   Security-load-bearing edges: tenant resolved from the Item id inside BOTH fns
--     (never a caller key); gate written only at completion (C-X2); AC2 per-path idempotency
--     (cursor for transactions / provider_event_id UNIQUE gate for state); #15 matched-tenant
--     fence on the sync_audit INSERT; only-on-change state writes; set search_path='' on both
--     fns; service_role-only EXECUTE; sync_cursor withheld from authenticated.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (B) OWD-A A3 — typed incremental-sync cursor column on pfin.linked_source.
--   Additive; mutable table (not audit-class) → plain ADD COLUMN. Cursor relocates
--   out of provider_metadata jsonb into a typed, inspectable column (silent jsonb-
--   cursor corruption is a real incremental-sync failure mode — ADR-037 OWD-A A3).
--   The service_role worker sync path reads it at sync start and advances it on a
--   successful /transactions/sync; api/src never touches it.
-- ----------------------------------------------------------------------------
alter table pfin.linked_source
  add column if not exists sync_cursor text;

comment on column pfin.linked_source.sync_cursor is
  'Typed incremental-sync cursor (OWD-A A3, ADR-037 Decision 3 / SELF-206 migration 045; relocated out of provider_metadata jsonb). Opaque per-provider watermark: Plaid /transactions/sync cursor; SimpleFIN poll watermark. Read at sync start + advanced ON SUCCESS by the service_role provider-sync worker path (api/src never touches it). NULLABLE (NULL = never-synced / pre-cursor). NOT granted to authenticated (operational, not user-facing; belt-and-suspenders REVOKE below mirrors credential_secret_id). users_id is the SOLE tenant anchor on linked_source → this column is a plain text scalar, NOT an FK → Decision-3-NEUTRAL (adds no matched-tenant instance) and NOT a §10 catalogued instance.';

-- Least-exposure: keep the cursor off the authenticated Data-API surface. The 015
-- column-level SELECT grant did not include this new column, so authenticated has no
-- SELECT on it by default; this REVOKE is defense-in-depth against a future broad grant.
revoke all (sync_cursor) on pfin.linked_source from authenticated;
-- service_role already holds `grant select, insert, update, delete on pfin.linked_source`
-- (015 step 9, full-table) → it reads/advances the cursor. No new grant needed.

-- ----------------------------------------------------------------------------
-- (A1) fn_plaid_webhook_resolve — READ-ONLY pre-flight (resolve + idempotency check).
--   The side-effect-free half of Route Z-INVOKER. The handler calls this FIRST to
--   decide: ack-and-drop (unknown Item), 200-immediately (already processed), or
--   trigger the external sync then commit. NO writes → trivially idempotent/replayable
--   (the C-X2 property that lets Plaid's retry re-drive safely).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_plaid_webhook_resolve(p_event jsonb)
returns table (
  resolved            boolean,
  already_processed   boolean,
  should_trigger_sync boolean,
  source_id           bigint,
  users_id            uuid
)
language plpgsql
security invoker
stable
set search_path = ''
as $$
declare
  v_item_id  text := p_event ->> 'item_id';
  v_event_id text := p_event ->> 'provider_event_id';
  v_is_txn   boolean := coalesce((p_event ->> 'is_transactions_event')::boolean, false);
  v_src      bigint;
  v_uid      uuid;
  v_seen     boolean;
begin
  -- Defensive input discipline: a webhook with no Item id cannot be tenant-resolved.
  if v_item_id is null then
    resolved := false; already_processed := false; should_trigger_sync := false;
    source_id := null; users_id := null;
    return next; return;
  end if;

  -- Tenant resolution FROM the Item id (ADR-011 Decision 1 privileged-context-write —
  -- NEVER a caller-supplied users_id). Unknown/foreign/removed Item → NOT FOUND → fail
  -- closed (resolved=false; the handler acks-and-drops; NO cross-tenant write anywhere).
  select ls.source_id, ls.users_id into v_src, v_uid
  from pfin.linked_source ls
  where ls.provider = 'plaid'
    and ls.external_connection_id = v_item_id;

  if not found then
    resolved := false; already_processed := false; should_trigger_sync := false;
    source_id := null; users_id := null;
    return next; return;
  end if;

  -- Idempotency PRE-CHECK — STATE-path only. The provider_event_id gate is RESERVED for
  -- the non-cursor STATE/ITEM path; TRANSACTIONS events carry a NULL provider_event_id and
  -- are deduped by the /transactions/sync CURSOR, NOT by this gate (see the header
  -- SEMANTICS block — a same-iat-second false-collision on the byte-identical transactions
  -- body would otherwise drop a legit new sync = money-flow data loss). A NULL id → v_seen
  -- false. For a STATE event, a present row ⟺ that exact signed delivery was fully
  -- processed (gate written at COMPLETION) → the handler short-circuits to 200.
  v_seen := (v_event_id is not null) and exists (
    select 1 from pfin.linked_source_sync_audit lsa
    where lsa.provider_event_id = v_event_id
  );

  resolved := true;
  already_processed := v_seen;
  -- The SYNC decision is DELIBERATELY NOT gated by the event-id: fire the external sync for
  -- ANY resolved transactions-class event. The cursor + fn_ingest ON CONFLICT are the
  -- transactions dedup; gating the sync on the id would risk the same-second false-collision
  -- above. (STATE events never sync → is_transactions_event=false → should_trigger_sync=false;
  -- their already_processed short-circuit is handled by the handler, not this flag.) C-X2:
  -- a crash before commit leaves no gate → the retry re-drives (resolve is side-effect-free;
  -- the sync is cursor-idempotent).
  should_trigger_sync := v_is_txn;
  source_id := v_src;
  users_id := v_uid;
  return next;
end;
$$;

revoke execute on function pfin.fn_plaid_webhook_resolve(jsonb) from public;
grant  execute on function pfin.fn_plaid_webhook_resolve(jsonb) to service_role;

comment on function pfin.fn_plaid_webhook_resolve(jsonb) is
  'SELF-206 Route Z-INVOKER pre-flight (READ-ONLY). Resolves (source_id, users_id) FROM p_event->>''item_id'' via pfin.linked_source WHERE provider=''plaid'' — the ADR-011 Decision 1 privileged-context-write tenant binding (NEVER a caller-supplied key). Returns resolved=false (fail-closed) for an unknown/foreign/removed Item so the handler acks-and-drops with no writes. already_processed = a linked_source_sync_audit row already exists for provider_event_id — the STATE-path replay short-circuit (gate written at COMPLETION so a present row ⟺ that signed delivery fully processed; NULL id → false). should_trigger_sync = p_event->>''is_transactions_event'' — DELIBERATELY NOT gated by the event-id: the transactions path is deduped by the /transactions/sync CURSOR, so gating the sync on the id (byte-identical steady-state body → same-iat-second collision risk) could drop a legit sync. The id-gate is RESERVED for the STATE path (transactions events carry NULL provider_event_id). SECURITY INVOKER + STABLE + set search_path='''' — no writes (the C-X2 property: a pure re-runnable SELECT, so Plaid''s at-least-once retry re-drives safely). EXECUTE granted to service_role ONLY (the supabase-admin.ts webhook client); NOT authenticated (would leak another tenant''s users_id given an Item id). DEFINER allowlist unchanged (INVOKER).';

-- ----------------------------------------------------------------------------
-- (A2) fn_plaid_webhook_commit — the ATOMIC write half of Route Z-INVOKER.
--   Called by the handler ONLY after the external sync (if any) is confirmed
--   dispatched (C-X2 sync-first / gate-at-completion). One plpgsql body = one
--   transaction → state flip + state_history append + gate/audit INSERT are genuinely
--   all-or-nothing (if the #15 fence raises, the state write rolls back too).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_plaid_webhook_commit(p_event jsonb)
returns table (
  committed  boolean,
  was_fresh  boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item_id     text := p_event ->> 'item_id';
  v_event_id    text := p_event ->> 'provider_event_id';
  v_is_txn      boolean := coalesce((p_event ->> 'is_transactions_event')::boolean, false);
  v_status      text := p_event ->> 'status_class';
  v_err_code    text := p_event ->> 'provider_error_code';
  v_event_type  text := p_event ->> 'event_type';
  v_src         bigint;
  v_uid         uuid;
  v_cur_status  text;
  v_rowcount    integer := 0;
begin
  -- STATE events REQUIRE a per-delivery idempotency key (AC2 for the non-cursor path); a
  -- NULL id on a state event → fail closed. TRANSACTIONS events MAY carry NULL — their
  -- dedup is the /transactions/sync CURSOR, not the id-gate (a NULL id keeps distinct
  -- steady-state transaction notifications from false-colliding on the UNIQUE index; NULLs
  -- are distinct in Postgres UNIQUE). This RAISE fires ONLY on a NULL key of a STATE event
  -- or a vanished tenant (below) — NEVER on a "duplicate logical event" (across re-signed
  -- Plaid retries a state event yields DISTINCT per-delivery ids + DISTINCT audit rows,
  -- forensically fine, append-only). See the header SEMANTICS block.
  if v_event_id is null and not v_is_txn then
    raise exception
      'fn_plaid_webhook_commit: provider_event_id is required for a STATE (non-transactions) webhook sync-audit row (AC2 idempotency gate; transactions events are cursor-deduped and carry NULL; ADR-011 Decision 2 / 015 linked_source_sync_audit.provider_event_id UNIQUE)';
  end if;

  -- Re-resolve tenant FROM the Item id — AUTHORITATIVE; never trusts caller tenant keys.
  -- Fail-closed if the Item vanished between resolve and commit (rare) → NO orphan/cross-
  -- tenant write; Plaid retries and resolve will then ack-and-drop.
  select ls.source_id, ls.users_id, ls.connection_status
    into v_src, v_uid, v_cur_status
  from pfin.linked_source ls
  where ls.provider = 'plaid'
    and ls.external_connection_id = v_item_id;

  if not found then
    raise exception
      'fn_plaid_webhook_commit: no pfin.linked_source for provider=plaid external_connection_id=% (fail-closed; the source was removed after resolve)', v_item_id;
  end if;

  -- STATE TRANSITION — ONLY ON A REAL CHANGE (idempotent replay-safe; the C-X2 property).
  -- A NULL status_class = a pure transactions event (no health change) → no state write.
  -- The linked_source_state_history / linked_source.connection_status CHECK constraints
  -- (015) reject any status_class outside the normalized 5-value enum → defense-in-depth
  -- even if the handler mis-normalizes.
  if v_status is not null and v_status is distinct from v_cur_status then
    insert into pfin.linked_source_state_history (source_id, status_class, provider_error_code)
      values (v_src, v_status, v_err_code);
    update pfin.linked_source
      set connection_status = v_status
      where source_id = v_src;
  end if;

  -- GATE / AUDIT ROW — the AC6 sync-audit row (+ AC2 idempotency gate for STATE events),
  -- written at COMPLETION (C-X2). ON CONFLICT (provider_event_id) DO NOTHING: for a STATE
  -- event this dedups an exact-JWT replay; for a TRANSACTIONS event v_event_id is NULL and
  -- NULLs are DISTINCT in the UNIQUE index → the row ALWAYS inserts (no false-collision,
  -- was_fresh=true — the handler ignores was_fresh for transactions; the cursor is that
  -- path's dedup). linked_source_id re-resolved (the 044 #15 fn_sync_audit_matched_linked_
  -- source BEFORE-INSERT fence validates it is same-tenant as users_id). detail records the
  -- tenant-resolution chain + the handler-supplied sync outcome (Decision 1 same-transaction
  -- audit discipline).
  -- FORWARD-HOOK (ADR-026 A2): the reserved GENERAL forensic audit-log row would attach
  -- here in the same transaction once its DEFINER helper is authored (SELF-201 Task #7);
  -- SELF-206 emits only this sync-audit row, not the general log.
  insert into pfin.linked_source_sync_audit
    (provider, source, users_id, external_connection_id, provider_event_id,
     event_type, detail, linked_source_id)
  values
    ('plaid', 'webhook', v_uid, v_item_id, v_event_id,
     v_event_type,
     jsonb_build_object(
       'tenant_resolution', jsonb_build_object(
         'item_id', v_item_id, 'resolved_source_id', v_src, 'resolved_users_id', v_uid),
       'status_class', v_status,
       'provider_error_code', v_err_code,
       'sync_outcome', p_event -> 'sync_outcome'),
     v_src)
  on conflict (provider_event_id) do nothing;

  get diagnostics v_rowcount = row_count;
  committed := true;
  was_fresh := (v_rowcount > 0);
  return next;
end;
$$;

revoke execute on function pfin.fn_plaid_webhook_commit(jsonb) from public;
grant  execute on function pfin.fn_plaid_webhook_commit(jsonb) to service_role;

comment on function pfin.fn_plaid_webhook_commit(jsonb) is
  'SELF-206 Route Z-INVOKER atomic commit (WRITES). One plpgsql transaction: re-resolve (source_id, users_id) FROM p_event->>''item_id'' (authoritative; NEVER a caller key; fail-closed RAISE if the Item was removed) → state_history append + connection_status flip ONLY-ON-CHANGE (status_class + provider_error_code; NULL status_class = pure transactions event → no state write; the 015 CHECK enum is the defense-in-depth backstop) → INSERT the linked_source_sync_audit gate/audit row (provider=''plaid'', source=''webhook'', provider_event_id ON CONFLICT DO NOTHING; linked_source_id re-resolved → the 044 #15 matched-tenant fence validates same-tenant). AC2 idempotency is PER-PATH: STATE events carry a non-null per-delivery provider_event_id and the UNIQUE gate dedups exact-JWT replays; TRANSACTIONS events carry NULL (NULLs distinct → always insert) and are deduped by the /transactions/sync CURSOR, NOT the gate (avoids the same-iat-second false-collision on the byte-identical transactions body dropping a legit sync). Returns was_fresh = whether the row was freshly inserted (meaningful for STATE events; always true for transactions). Called by the handler ONLY after the external worker sync is confirmed dispatched (C-X2 sync-first / gate-at-completion; self-contained — Plaid''s at-least-once retry + sync idempotency re-drive it, no reliance on the code-level Plaid poll in poll.ts/SELF-279; the dormant-item-persistent-failure tail is re-driven by the next webhook or that poll, whose operational cadence is tracked at SELF-213). provider_event_id NULL RAISEs ONLY for a STATE event (transactions may be NULL). SECURITY INVOKER + set search_path='''' — runs with service_role privileges (BYPASSRLS) via the supabase-admin.ts caller; DEFINER allowlist unchanged (INVOKER). EXECUTE granted to service_role ONLY. ADR-026 A2: emits this sync-audit row, NOT the reserved general forensic log (forward-hook only).';
