-- ============================================================================
-- Migration: pfin service_role privileged-write grants (Decision 1 completion)
-- Phase 6 Build Loop (SELF-196 companion / V1-SHIP-BLOCK / sec-joint-review).
-- Completes the ADR-011 Decision 1 privileged-context-write pattern at the DB-ACL
-- layer: grants `service_role` the schema USAGE + least-privilege per-table writes
-- it needs to be the "sole privileged writer" the design already ratified.
--
-- WHY (Backend-measured on the pinned stack, SELF-196 re-verify):
--   `has_schema_privilege('service_role','pfin','usage') = FALSE`; the pfin schema
--   ACL is {postgres=UC, authenticated=U}. `service_role` is BYPASSRLS=true but ACL
--   is checked INDEPENDENTLY of RLS — bypassing RLS does NOT bypass schema USAGE or
--   table GRANTs. So today `service_role` can reach NO pfin object: it can't read the
--   007 decrypt view (making 007's `grant select on pfin.decrypted_plaid_access_token
--   to service_role` INERT), can't write plaid_items, can't INSERT account_trans.
--   The Decision-1 "writes execute under service_role" pattern is non-functional
--   pfin-wide. This migration closes that gap.
--
-- Numbering: 008 follows 007 — it grants on tables created in 003 (account,
-- account_trans deps), 004 (account_trans), and 007 (plaid_items + state_history +
-- sync_audit + decrypt view), so it MUST run after them. Pure GRANTs — no schema
-- DDL, no functions, no policies.
--
-- ----------------------------------------------------------------------------
-- ROLE-OF-RECORD SCOPE NOTE (read before extending).
--   Two questions were entangled in Backend's find; this migration resolves ONE:
--     (1) service_role DB-ACL reachability (USAGE + table grants) — RESOLVED HERE.
--         Needed under BOTH viable transports (Option A PostgREST-exposed and Option B
--         direct-pg), so it is safe to fold now regardless of the transport ratify.
--     (2) the pfin Data-API EXPOSURE / transport — RESOLVED: F/CTO RATIFIED Option A
--         (expose pfin to the Data API + supabase-js/PostgREST + native RLS) on
--         2026-07-03 per ADR-023. The companion `supabase/config.toml` edit adds "pfin"
--         to `[api] schemas` in THIS PR.
--   COUPLING (legible link): once `[api] schemas` includes "pfin", every pfin relation
--   is internet-facing — and THESE grants (service_role writes) + the per-table RLS are
--   exactly the two-layer fence that exposure relies on (outer: anon holds zero pfin
--   grants; inner: RLS users_id=auth.uid()/JOIN). The config edit and this migration are
--   a single coupled change; neither is correct alone. Sec C6 (ADR-023): the §4.5
--   two-tenant RLS battery is now EXPOSURE-gating for every future pfin table.
--
-- POSTURE — pure GRANTs; least-privilege; NO function authored.
--   DEFINER allowlist UNCHANGED at 3 (grants are not functions). Grants are scoped to
--   the tables that actually have a service_role write path (Decision 1 privileged
--   contexts: Plaid onboarding/webhook/poll + workers), NOT a blanket `GRANT … ON ALL
--   TABLES`. Immutable audit-class tables get select+insert only (UPDATE/DELETE stay
--   blocked for ALL roles by their triggers — service_role bypasses RLS but not
--   triggers, so append-only holds even with INSERT granted).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii) layer-
--   attribution — RT-26 is the code-layer `SUPABASE_SERVICE_ROLE_KEY` allowlist grep
--   fence on web-app SOURCE (governs WHERE the service key is used in code); it is NOT
--   this DB-layer ACL grant. Broadening service_role's DB reach does not add, remove,
--   or re-attribute a catalogued instance — but it IS a privileged-surface posture
--   change (Sec-blessing-required at joint-review). RT-22 (container fence) untouched.
--   (iii) Decision 4 linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — +0.
--   No FK-shaped columns introduced (grants only). Family count UNCHANGED. Tenant
--   isolation for service_role writes derives from CODE (Decision 1 clause (c) explicit
--   users_id binding), not RLS (service_role bypasses RLS by design); the DB-layer
--   Decision-3 matched-tenant fences already authored (e.g. 004's replaces_trans_id)
--   still apply to service_role INSERTs (triggers fire regardless of role).
--
-- CONTRACT — service_role gains:
--   USAGE on schema pfin; and per-table (least-privilege, by Decision-1 write path):
--     - plaid_items                  : SELECT, INSERT, UPDATE, DELETE (onboard insert /
--                                      status+token-rotation update / /item/remove delete)
--     - plaid_item_state_history     : SELECT, INSERT (append-only)
--     - plaid_sync_audit             : SELECT, INSERT (append-only)
--     - account_trans                : SELECT, INSERT (Plaid transaction sync; immutable)
--     - account                      : SELECT (Plaid Item -> account mapping/read)
--   account INSERT/UPDATE by service_role is DEFERRED to SELF-197's confirmation of
--   whether Plaid onboarding creates pfin.account rows under service_role vs the
--   in-session authenticated user (RT-26 allowlist entry 2 is service_role for the
--   credential admission; account-row creation role is a SELF-197 design detail).
--   Grants are additive to the existing authenticated grants (003/004/006/007).
-- ============================================================================

grant usage on schema pfin to service_role;

-- plaid_items — full lifecycle under service_role (Decision 1 privileged writer).
grant select, insert, update, delete on pfin.plaid_items to service_role;

-- Append-only audit-class: select + insert only (UPDATE/DELETE remain trigger-blocked
-- for ALL roles incl. service_role — append-only holds by-construction).
grant select, insert on pfin.plaid_item_state_history to service_role;
grant select, insert on pfin.plaid_sync_audit to service_role;

-- account_trans — Plaid transaction sync inserts (immutable; no update/delete grant).
grant select, insert on pfin.account_trans to service_role;

-- account — read for Plaid Item -> account mapping. Write deferred to SELF-197 (see CONTRACT).
grant select on pfin.account to service_role;

-- ----------------------------------------------------------------------------
-- SEC CONDITIONS (Option A ratify, SELF-196) — enforced/asserted here.
--   C2 (anon outer fence): the `grant usage … to service_role` above brings NO anon
--       grant along; anon holds ZERO privileges on every pfin relation (measured), and
--       nothing here changes that. anon is denied at the schema-usage layer.
--   C3 (token handle never client-facing): 008 adds NO whole-table grant to
--       `authenticated` on plaid_items — 007's column-scoped authenticated SELECT
--       (access_token_secret_id EXCLUDED) stands. Belt-and-suspenders re-assertion so
--       no later broad grant can silently re-expose the handle:
revoke all (access_token_secret_id) on pfin.plaid_items from authenticated;
--   C4 (decrypt view stays locked): 008 does NOT touch pfin.decrypted_plaid_access_token;
--       its service_role-only grant + REVOKE anon/authenticated (007) hold unchanged.
--   C5 (authenticated write surface unchanged): 008 grants authenticated NOTHING.
--       authenticated's existing WITH-CHECK user-write surfaces stay exactly as-built
--       (account INSERT/UPDATE; account_trans INSERT; reconciliation_event +
--       reconciliation_event_trans INSERT — all users_id=auth.uid()/JOIN WITH CHECK).
--       (Correction to the C5 phrasing "none currently in pfin": there ARE 4 such
--       user-write tables; all are WITH-CHECK-fenced, which is the intended
--       RLS-default-trust design and safe under Data-API exposure.)
-- ----------------------------------------------------------------------------
