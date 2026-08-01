-- ============================================================================
-- Migration: pfin.linked_source_sync_audit — widen the `source` CHECK to admit 'manual'
-- SELF-317 (manual "Sync now" trigger; ADR-037 amendment). Extends the Lock 13 mod #8
-- sync-mode discriminator: {webhook, scheduled_poll} → {webhook, scheduled_poll, manual}.
--
-- WHY: SELF-317 adds a user-initiated on-demand sync (POST /admission/manual-sync, a route
--   on the existing RT-27 admission surface). Its audit rows need a provenance label distinct
--   from the @daily cron (`scheduled_poll`) and the Plaid webhook (`webhook`). 'manual' is that
--   label (Sec condition C6a/C6b — F/CTO ratified C6b = ADD 'manual' to the CHECK).
--
-- Numbering: `047` — next after `046_fn_aggregation_has_stale_constituent.sql`. This migration
--   depends on `015_linked_source_fold.sql` (FOLD STEP 6), which created the table + the inline
--   unnamed `source` CHECK (auto-named `linked_source_sync_audit_source_check`). Order-dependent
--   on `015` only; no other migration touches this constraint.
--
-- POSTURE RATIONALE — no function authored (a plain CHECK-constraint widen). `set search_path=''`
--   is a FUNCTION directive and is N/A here (no function). SECURITY INVOKER/DEFINER is likewise
--   N/A. The DDL runs at migration time under the migration role; it authors no runtime privilege
--   surface.
--
-- CONTRACT
--   pfin.linked_source_sync_audit.source  text NOT NULL
--     CHECK (source IN ('webhook', 'scheduled_poll', 'manual'))   -- widened (+ 'manual')
--   • ADDITIVE widen: every previously-valid value ('webhook', 'scheduled_poll') stays valid, so
--     the ADD CONSTRAINT re-validation of existing rows always passes (no data migration).
--   • The table is an IMMUTABLE append-only audit-class table (Decision 2 / Lock 13 mod #8):
--     BEFORE UPDATE/DELETE/TRUNCATE triggers fence ALL roles incl. service_role. Those are DML
--     triggers — this ALTER TABLE is DDL and is NOT fenced by them (verified: DDL ≠ UPDATE/DELETE).
--   • service_role-ONLY / RLS default-deny (no `authenticated` policy, no GRANT to authenticated).
--     A CHECK widen touches no RLS policy, no table GRANT, and no aal2 clause → the `025` aal2
--     step-up backstop is N/A (this table is exclusion (ii): service_role-only / default-deny).
--
-- §10 3-axis cross-check (ADR-011 Decision 4 read verbatim before drafting; Path B — reference,
--   do not restate the catalogued list). This is a plain CHECK widen on an existing audit table:
--   (i) instance-numbering unchanged — adds NO catalogued §10 instance (no credential/admission/
--       network-exposure surface touched); ledger stays 3 (RT-22 + RT-26 + RT-27).
--   (ii) layer-attribution unchanged — no surface becomes an additional layer.
--   (iii) Decision 4 referenced, not restated.
--   Adjacent ledgers FLAT: RT-26 SUPABASE_SERVICE_ROLE_KEY allowlist stays 3; SECURITY DEFINER
--   allowlist stays 4 (no function authored); Decision-3 cross-tenant FK-bypass family unchanged
--   (15 labeled / 13 DDL-realized) — `external_connection_id` stays TEXT (NOT a pfin FK), the
--   widened column `source` is a plain enum-string, no FK-shaped column added. Sec pre-blessed
--   (CLEAN-WITH-CONDITIONS; C6b chosen).
-- ============================================================================

-- Drop the inline-unnamed CHECK from `015` (Postgres auto-named it `<table>_<column>_check`),
-- then re-add it NAMED + widened. `drop constraint if exists` keeps this idempotent on re-apply.
alter table pfin.linked_source_sync_audit
  drop constraint if exists linked_source_sync_audit_source_check;

alter table pfin.linked_source_sync_audit
  add constraint linked_source_sync_audit_source_check
  check (source in ('webhook', 'scheduled_poll', 'manual'));

comment on constraint linked_source_sync_audit_source_check on pfin.linked_source_sync_audit is
  'Sync-mode discriminator (Lock 13 mod #8), spanning all providers. webhook = Plaid webhook-driven; scheduled_poll = @daily cron (poll-only providers — SimpleFIN/SnapTrade — use this exclusively; Plaid uses both); manual = user-initiated on-demand "Sync now" (SELF-317, ADR-037 amendment; POST /admission/manual-sync — a route on the existing RT-27 admission surface). Widened {webhook, scheduled_poll} → +manual at 047; additive (no data migration). Named at 047 (was inline-unnamed at 015).';

-- Refresh the table comment: keep the 015 narrative verbatim except the two `source`-value spots,
-- now three-valued (webhook/scheduled_poll/manual).
comment on table pfin.linked_source_sync_audit is
  'Append-only multi-provider sync audit (ADR-011 Decision 8 / Lock 4 mod #3 + Decision 17 / Lock 13 mod #8, generalized plaid_sync_audit → linked_source per the R-14 fold A.5). Cross-language schema-as-contract for the webhook + scheduled-poll + manual write paths, discriminated by (provider, source). provider_event_id UNIQUE is the idempotency gate (generalizes plaid_webhook_id) — the webhook handler INSERTs ON CONFLICT (provider_event_id) DO NOTHING under SERIALIZABLE; poll + manual rows carry NULL (UNIQUE treats NULLs as distinct). source (webhook/scheduled_poll/manual) spans all providers: poll-only providers use scheduled_poll; Plaid uses both; manual = a user-initiated on-demand sync (SELF-317, ADR-037 amendment) via /admission/manual-sync. users_id records the code-resolved tenant per Decision 1 clause (d). service_role-ONLY: NOT granted to authenticated (audit of privileged writes; RLS enabled → default-deny for authenticated). Immutable audit-class (Decision 2): UPDATE + DELETE + TRUNCATE fenced for ALL roles. external_connection_id is TEXT external id, NOT a pfin FK → NOT a Decision-3 instance. C6 exposure-gated (ADR-023).';
