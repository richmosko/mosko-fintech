-- ============================================================================
-- Migration: pfin.linked_source_connection_state — SECURITY INVOKER read view
-- Phase 6 Build Loop (SELF-207 / §2.4.4.b connection-state view + reactive re-auth
-- + persistent banner; ADR-037 reconciled onto the provider-agnostic linked_source
-- substrate; OWD-A A3 = last-sync DERIVED, no scalar; R2 = curated INVOKER view).
-- The single owner-scoped read the connection-state endpoint + the provider-blind
-- re-auth banner (+ later SELF-208 staleness) consume: per connected source, its
-- normalized current health + latest state transition + last successful sync.
-- Latest-per-source composition matching the shipped account_balance_checkpoint_latest
-- / holdings_checkpoint_latest INVOKER "_latest"-view precedent (019 / 018).
--
-- Numbering: 043 follows 042_fn_land_linked_accounts (head at authoring). Depends on:
-- 015 (linked_source + connection_status enum + linked_source_state_history + its
-- authenticated SELECT grant/RLS + the column-level linked_source SELECT grant that
-- includes connection_status/institution_name/is_active/provider), 040 (the
-- linked_source_sync_history owner-semantics view this derives last-sync from), 025
-- (the aal2 backstop clause on linked_source's authenticated policy — inherited as the
-- driving-table gate, see below). NOTE (bookkeeping): ADR-037 Decision 6 / the amendment
-- named 043 the deferred sync-cursor column (OWD-A A3); F/CTO re-sequenced the cursor to
-- SELF-206/the sync path (it is read/written by the incremental-sync machinery, NOT by
-- this view), so 043 is the connection-state view and the typed-cursor migration takes a
-- later number when SELF-206 builds. One-line ADR-037 doc-sync flagged to team-lead.
-- No downstream migration depends on 043.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER view (default per ADR-011 Lock 11); no DEFINER.
--   A view, not a function — the INVOKER/DEFINER *function* question does not arise; the
--   SECURITY DEFINER allowlist is UNCHANGED at 4. security_invoker = true means the view
--   composes under the CALLER's RLS on every base object it reads, so isolation is the
--   existing owner-scoped RLS, not a new mechanism:
--     - pfin.linked_source: linked_source_select (users_id = auth.uid()) + the 025 aal2
--       backstop clause on that policy. This is the DRIVING TABLE (the FROM), so it gates
--       the whole view: at aal1 with mfa_policy in (totp,passkey) the caller's sources are
--       RLS-INVISIBLE → the view returns zero rows (fail-closed; the same aal2 gate QA
--       verified fences 042's #6 path). The view needs NO aal2 clause of its own (views
--       carry no RLS policy; the gate is inherited from the base table under INVOKER).
--       The column-level SELECT grant (015) already exposes connection_status /
--       institution_name / is_active / provider to authenticated (credential_secret_id
--       is REVOKEd — not read here).
--     - pfin.linked_source_state_history: linked_source_state_history_select (JOIN-scoped
--       to owned sources) + its authenticated SELECT grant (015).
--     - pfin.linked_source_sync_history (040): an OWNER-SEMANTICS (security_invoker=false)
--       view that self-scopes on `WHERE users_id = auth.uid()`. auth.uid() reads the
--       request JWT, so it resolves to the CALLER even through the owner-semantics view —
--       owner-safe. Reading it from this INVOKER view requires the caller to hold SELECT
--       on it (granted, 040); the 040 view supplies the derived last-sync WITHOUT this
--       view ever touching the service_role-only linked_source_sync_audit base table.
--   No service_role, no credential surface, no new fence — a pure owner-scoped read.
--
-- ----------------------------------------------------------------------------
-- COLUMN PROJECTION (Sec-relevant — mirrors the ADR-034 040-view projection discipline).
--   EXPOSED (all owner-safe): linked_source_id (= account.linked_source_id, the caller's
--   OWN connection id), provider, institution_name, connection_status (normalized 5-value
--   current health), status_class (normalized 5-value; latest state_history transition;
--   NULL if no history), last_successful_sync_at (derived), is_active. (status_detected_at
--   omitted for minimalism — additive later if the banner needs a "since" timestamp.)
--   DELIBERATELY EXCLUDED: provider_error_code (raw provider-native forensic code —
--   excluded per the ADR-034 raw-forensic-exclusion posture; the normalized status_class
--   is the user-facing signal), external_connection_id (provider-internal id),
--   credential_secret_id (the Vault handle — not in the caller's grant at all). Sec
--   confirms the projection at the reauth-path joint-review.
--
-- ----------------------------------------------------------------------------
-- "last_successful_sync_at" DEFINITION (pinned; F/CTO-ratified MAX(created_at) over
--   SUCCESSFUL syncs).
--   = MAX(created_at) over the caller's linked_source_sync_history (040) rows for the
--   source WHERE transactions_inserted IS NOT NULL. RATIONALE (capability-verified against
--   workers/provider-sync/src/cli/poll.ts AuditDetail): the audit detail is
--   `{ ok: boolean, result?: SyncResult }` — `result` is ABSENT on a failed sync, so
--   `detail->'result'->>'transactionsInserted'` (the 040 view's transactions_inserted) is
--   NULL on failure and NON-NULL (an int, possibly 0) on a sync that produced an ingest
--   result. So `transactions_inserted IS NOT NULL` = "the sync produced a result" — a
--   faithful "successful" proxy DERIVED FROM THE EXISTING 040 PROJECTION (no reopening of
--   its Sec-verified allowlist). NULL last_successful_sync_at = never-successfully-synced.
--   ALTERNATIVE (flagged, not chosen): stricter `ok = true` semantics (excluding partial
--   syncs that ingested some rows but had per-account failures) would require projecting
--   the `ok` key from the 040 view → REOPENS the ADR-034 projection → Sec re-review.
--   V1 uses the result-produced definition; Backend/QA confirm at build that a failed
--   sync writes NULL transactions_inserted (it does per the optional `result?`).
--
-- ----------------------------------------------------------------------------
-- RE-AUTH AFFORDANCE CONTRACT (for Backend/Frontend — read off this view).
--   Show the re-auth affordance / banner when
--     connection_status IN ('login_required','revoked','disconnected').
--   'institution_down' is transient/provider-side (NOT a re-auth trigger); 'healthy' is
--   the nominal state. The banner is provider-blind (reads connection_status only); the
--   reauth() ACTION dispatches per adapter (ProviderSyncAdapter.reauth — spec published
--   separately: Plaid update-mode / SimpleFIN re-claim).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list; Decision 4 read verbatim before drafting).
--   ZERO catalogued §10 instances; ledger stays at 3 (RT-22 first / RT-26 second /
--   RT-27 third). (i) instance-numbering unchanged. (ii) layer-attribution — an
--   authenticated-tier INVOKER read view; no infra-credential-presence (RT-22), no
--   SUPABASE_SERVICE_ROLE_KEY code-layer allowlist (RT-26 — the view uses NO service_role;
--   it reads the 040 owner-semantics view, whose service_role-only base access is the
--   040 mechanism, not a new one), and no app->worker admission surface (RT-27). (iii)
--   Decision 4 linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family +0 (stays 14 labeled /
--   12 DDL-realized). This migration authors NO table and NO FK-shaped column — it is a
--   read view over existing owner-scoped surfaces. linked_source_id in the projection is
--   the caller's OWN source id (owner-safe, = account.linked_source_id), not a new FK.
--   The canonical enumeration (ADR-011 Decision 3) is UNCHANGED.
--
-- SECURITY DEFINER allowlist — UNCHANGED at 4 (no function authored).
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   Two-tenant pgTAP battery over the connection-state read:
--     - owner reads own connections' state (one row per own linked_source);
--     - cross-tenant: tenant A sees ZERO of tenant B's connections (RLS via INVOKER);
--     - aal2 gate: an aal1 caller with mfa_policy in (totp,passkey) reads ZERO rows
--       (linked_source driving-table 025 clause);
--     - status_class is the MOST-RECENT state_history transition per source
--       (not an older one);
--     - last_successful_sync_at excludes FAILED syncs (a failed-sync audit row with NULL
--       transactions_inserted does not advance it) and reflects the latest successful one;
--     - a source with no history / no successful sync yields NULL status/last-sync, not a
--       dropped row (LEFT JOINs).
--   Sec joint-review rides the SELF-207 reauth-path review (projection confirmation).
--   Not a vacuous green — the fixture must populate two tenants + a failed-sync audit row.
--
-- CONTRACT
--   pfin.linked_source_connection_state (security_invoker = true) — one row per caller-owned
--   pfin.linked_source. Columns: linked_source_id bigint · provider text · institution_name
--   text · connection_status text (healthy|login_required|institution_down|revoked|
--   disconnected) · status_class text (latest state_history transition; same domain; NULL if
--   no history) · last_successful_sync_at timestamptz (NULL if never) · is_active boolean.
--   GRANT SELECT to authenticated. Owner-scoped by inherited RLS (INVOKER); aal2-gated via
--   the linked_source driving table. Last-sync is derived by composing over the 040
--   OWNER-SEMANTICS view (linked_source_sync_history) — NOT the service_role-only
--   linked_source_sync_audit base table — so NO base-table grant to authenticated is
--   introduced (the 040 security_barrier owner-semantics protection is inherited).
-- ============================================================================

create schema if not exists pfin;

create or replace view pfin.linked_source_connection_state
  with (security_invoker = true) as
select
  ls.source_id                as linked_source_id,
  ls.provider,
  ls.institution_name,
  ls.connection_status,
  sh.status_class,
  ss.last_successful_sync_at,
  ls.is_active
from pfin.linked_source ls
-- Latest state transition per source (DISTINCT-ON-equivalent via LATERAL LIMIT 1). Only
-- status_class is projected; detected_at is used solely to order "latest".
left join lateral (
  select h.status_class
  from pfin.linked_source_state_history h
  where h.source_id = ls.source_id
  order by h.detected_at desc, h.history_id desc
  limit 1
) sh on true
-- Derived last SUCCESSFUL sync per source, from the 040 owner-semantics view. "Successful"
-- = a sync that produced an ingest result (transactions_inserted IS NOT NULL); failed syncs
-- carry no `result` (poll.ts AuditDetail.result?) → NULL → excluded. See header definition.
left join (
  select sy.linked_source_id,
         max(sy.created_at) as last_successful_sync_at
  from pfin.linked_source_sync_history sy
  where sy.transactions_inserted is not null
  group by sy.linked_source_id
) ss on ss.linked_source_id = ls.source_id;

grant select on pfin.linked_source_connection_state to authenticated;

comment on view pfin.linked_source_connection_state is
  'SECURITY INVOKER connection-state read view (SELF-207 §2.4.4.b; ADR-037; R2). One owner-scoped row per caller-owned pfin.linked_source: connection_status (normalized 5-value current health) + status_class (latest linked_source_state_history transition) + last_successful_sync_at (DERIVED — MAX(created_at) over the 040 OWNER-SEMANTICS linked_source_sync_history view WHERE transactions_inserted IS NOT NULL; OWD-A A3, no scalar; NOT the service_role-only sync_audit base table, so no base grant to authenticated) + provider/institution_name/is_active. Matches the account_balance_checkpoint_latest / holdings_checkpoint_latest INVOKER _latest-view precedent. Owner isolation is inherited RLS (security_invoker=true): linked_source_select + the 025 aal2 clause on the linked_source driving table gate the whole view (aal1 → zero rows, fail-closed); state_history_select + the 040 view''s own auth.uid() self-scope cover the joins. Projection EXCLUDES provider_error_code (raw forensic), external_connection_id (provider-internal), credential_secret_id (Vault handle, not in grant) per the ADR-034 projection discipline. Re-auth affordance rule: show when connection_status IN (login_required,revoked,disconnected). Authors no function (DEFINER allowlist stays 4), no FK column (Decision-3 unchanged), no §10 instance (stays 3). Consumed by the connection-state endpoint + the provider-blind re-auth banner + later SELF-208 staleness.';
