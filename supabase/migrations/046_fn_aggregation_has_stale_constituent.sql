-- ============================================================================
-- Migration: pfin.fn_aggregation_has_stale_constituent — staleness-detection primitive
-- Phase 6 Build Loop (SELF-208 / §2.4.4.c non-silent staleness markers framework — the
-- last V1.0 §2.4 Onboarding feature). Realizes the ADR-013 Decision 1 "aggregation data is
-- never silently presented as fresh when a contributing connection is unhealthy" commitment
-- as a reusable read primitive. Consumes SELF-207's connection-state model (043 view).
-- Extends RT-13 (D1 staleness-surface tracking) — a newly-realized staleness surface.
--
-- Numbering: 046 follows 045_plaid_webhook_apply (head at authoring). Depends on:
--   043 (pfin.linked_source_connection_state — the SECURITY INVOKER connection-state view
--   this composes over; supplies per-owned-source connection_status + status_class +
--   institution_name + provider + is_active, already owner-scoped and aal2-gated via the
--   linked_source driving table). No downstream migration depends on 046.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT SECURITY DEFINER.
--   Pure read-composition over the 043 INVOKER view (fn_compute_nav / fn_compute_tax_liability
--   / fn_render_monthly_report read-path family). Runs as the calling user: isolation is the
--   INHERITED RLS on linked_source (linked_source_select = users_id = auth.uid()) + the 025
--   aal2 backstop clause on that driving table. auth.uid() reads the request JWT, so the
--   function resolves to the CALLER's own sources only — it CANNOT read another tenant's
--   connection state (RT-13: requesting-tenant-scoped credential-state resolution — satisfied
--   structurally by INVOKER + auth.uid() scope, no new mechanism). NO service_role, NO
--   credential surface, NO elevated privilege. The DEFINER allowlist is UNCHANGED at 4.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_aggregation_has_stale_constituent() RETURNS TABLE(is_stale boolean, stale_items jsonb)
--   Exactly ONE row (aggregate shape — see ROW-VS-SET below). For the calling user:
--     - is_stale    = TRUE iff the caller owns ≥1 ACTIVE linked_source whose connection_status
--                     <> 'healthy'. FALSE (with stale_items = '[]') when all active sources are
--                     healthy OR the caller has no sources OR the aal2 gate zeroes the 043 view.
--     - stale_items = jsonb ARRAY of the stale sources, one object each:
--                       { linked_source_id, institution_name, provider,
--                         connection_status, status_class }
--                     Ordered by institution_name, linked_source_id. '[]'::jsonb when none.
--
--   SECURITY-LOAD-BEARING EDGES
--   • Owner scope + aal2 gate are INHERITED from the 043 view (INVOKER) → linked_source RLS
--     (linked_source_select + 025 aal2 clause). At aal1 with mfa_policy in (totp,passkey) the
--     043 view returns zero rows, so this fn returns is_stale=FALSE / stale_items='[]'
--     (fail-closed: no cross-tenant leak, no staleness asserted for an un-stepped-up caller).
--   • UNAUTHENTICATED (role anon) caller → DENIED with 42501 (permission denied for schema
--     pfin) at the pfin schema-USAGE fence — anon holds no USAGE on schema pfin, so execution
--     is refused at the OUTER schema boundary and never reaches the function's EXECUTE grant.
--     Fail-closed and STRONGER than an empty result (denied before any body runs; no leak).
--     (QA F15 asserts the 42501.) This is DISTINCT from the empty-row shape below.
--   • AUTHENTICATED-with-no-sub caller (a JWT whose auth.uid() resolves NULL) → reaches the
--     body but the 043 view's linked_source RLS (users_id = auth.uid() = NULL) matches no rows,
--     so the fn returns is_stale=FALSE / stale_items='[]' (the empty-row shape). Fail-closed:
--     no rows, no leak. (QA F16/F17 assert this.) The empty-row shape is the AUTHENTICATED-
--     no-sub case — NOT the anon case, which is denied at the schema fence per the bullet above.
--   • connection_status is NOT NULL (015 default 'healthy' + CHECK) so `<> 'healthy'` is total;
--     stated as `is distinct from 'healthy'` for defense-in-depth (a future NULL/unknown health
--     counts as stale — D1 never-silently-fresh; no behavior change today since NOT NULL holds).
--
--   ROW-VS-SET — returns ONE aggregate row (boolean + array), NOT a set of stale rows.
--     Rationale: the NAV surface (SELF-211) makes a SINGLE call and wants a single
--     is_stale flag + the accompanying list in one round-trip, with an UNAMBIGUOUS empty case
--     (is_stale=FALSE, stale_items='[]') — no client-side "did zero rows mean healthy or mean
--     the fn errored?" ambiguity. Server-side jsonb_agg keeps the badge wiring to one read.
--
--   IS_ACTIVE SCOPING — scopes to linked_source.is_active = TRUE (connection-level lifecycle
--     gate, 015 §4.6 bounded-source-active-only). Basis: the NAV aggregation's constituent set
--     is active-only (api/src/lib/server/queries/netWorth.ts filters is_active=TRUE per the
--     api/CLAUDE.md NAV/current-state contract). An inactive (suspended) source feeds NOTHING
--     into the displayed number, so flagging it would be a FALSE POSITIVE ("NAV stale" for a
--     source the user intentionally suspended, un-fixable by re-auth). NOT a D1 violation: D1
--     governs honesty of the number the user SEES; an inactive source's data is not in that
--     number, so its health is irrelevant to the number's freshness. See ADR-013-D1-FORWARD
--     and the reconciliation note for the alternative (flag-all-non-healthy) + one-line
--     reversal. Known conservative approximation: scopes on linked_source.is_active (the whole
--     connection's suspend gate), not on a per-account "has ≥1 active contributing account"
--     join — erring toward mark-stale is D1-safe; a tighter join is a possible V1.1+ refinement.
--
--   ADR-013-D1-FORWARD (illustrative-not-exhaustive surface set): the §2.4.4 surface list is
--     ILLUSTRATIVE, not exhaustive; this framework applies to EVERY aggregation consuming
--     Plaid-sourced data. V1.0 wires the NAV surface (§2.1.1); ramp at V1.1+ (§2.1.2 / §2.1.5
--     / §2.2.2 / §2.3.2 / §2.3.4 / §2.6) reuses this same primitive — no per-surface re-author.
--
--   PER-STATUS AFFORDANCE (handoff to Frontend) — stale_items carries per-item connection_status
--     so the badge renders a PER-STATUS affordance WITHOUT re-querying: show a "Re-authenticate"
--     link when connection_status IN ('login_required','revoked','disconnected') (REAUTH set —
--     re-auth fixes it); show an informational "institution temporarily unavailable" when
--     connection_status = 'institution_down' (transient provider-side outage — re-auth CANNOT
--     fix it). provider is carried so the reauth() action dispatches per adapter (Plaid
--     update-mode / SimpleFIN re-claim). status_class (latest state_history transition; may be
--     NULL) is CONTEXT, NOT the affordance driver — key the affordance on connection_status.
--     institution_down is INCLUDED in stale_items (marked, per D1) — it is stale-but-not-reauth.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the catalogued
--   numbered list; Decision 4 read verbatim before drafting). ZERO catalogued §10 instances;
--   ledger stays at 3 (RT-22 first / RT-26 second / RT-27 third). (i) instance-numbering
--   unchanged. (ii) layer-attribution — an authenticated-tier INVOKER read primitive; no
--   infra-credential-presence (RT-22), no SUPABASE_SERVICE_ROLE_KEY code-layer allowlist
--   (RT-26 — uses NO service_role), no app→worker credential-admission surface (RT-27). (iii)
--   Decision 4 linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family +0 (stays 15 labeled /
--   13 DDL-realized). Authors NO table and NO FK-shaped reference column. linked_source_id in
--   the projection is the caller's OWN source id (owner-safe, surfaced from the 043 view), not
--   a new cross-tenant reference. The canonical enumeration (ADR-011 Decision 3) is UNCHANGED.
--
-- SECURITY DEFINER allowlist — UNCHANGED at 4 (this function is INVOKER). RT-26 stays 4.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   Two-tenant pgTAP battery over the primitive:
--     - fixture: tenant A and tenant B each own a HEALTHY source + a NON-HEALTHY source
--       (mix login_required + institution_down so per-status carry is exercised);
--     - cross-tenant read-isolation: as tenant A, the fn NEVER returns any of B's stale items
--       (assert every stale_items[].linked_source_id is owned by A);
--     - is_stale=TRUE + stale_items contains A's non-healthy ACTIVE source(s) only;
--     - an INACTIVE non-healthy source is EXCLUDED (is_active scoping) — this row proves the
--       constituent-set alignment, not a vacuous green;
--     - all-healthy caller → is_stale=FALSE, stale_items='[]'::jsonb (not NULL, not dropped);
--     - aal2 gate: an aal1 caller with mfa_policy in (totp,passkey) → is_stale=FALSE / '[]'
--       (043 driving-table 025 clause zeroes the view);
--     - per-item connection_status is the authoritative current-health value (drives the badge).
--   Sec joint-review: surface:plaid + a new fn reading Plaid-sourced connection state across
--   the tenant boundary → RT-13 review (requesting-tenant-scoped credential-state resolution).
--   Not a vacuous green — the fixture must populate two tenants + active/inactive + mixed status.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_aggregation_has_stale_constituent()
returns table (is_stale boolean, stale_items jsonb)
language sql
stable
security invoker
set search_path = ''
as $$
  with stale as (
    select
      cs.linked_source_id,
      cs.institution_name,
      cs.provider,
      cs.connection_status,
      cs.status_class
    from pfin.linked_source_connection_state cs
    where cs.is_active
      and cs.connection_status is distinct from 'healthy'
  )
  select
    exists (select 1 from stale) as is_stale,
    coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'linked_source_id',  s.linked_source_id,
                   'institution_name',  s.institution_name,
                   'provider',          s.provider,
                   'connection_status', s.connection_status,
                   'status_class',      s.status_class
                 )
                 order by s.institution_name, s.linked_source_id
               )
        from stale s
      ),
      '[]'::jsonb
    ) as stale_items;
$$;

comment on function pfin.fn_aggregation_has_stale_constituent() is
  'SECURITY INVOKER staleness-detection primitive (SELF-208 §2.4.4.c; ADR-013 D1 non-silent staleness framework; RT-13). Returns ONE aggregate row (is_stale boolean, stale_items jsonb) for the calling user: is_stale = TRUE iff the caller owns >=1 ACTIVE linked_source whose connection_status <> ''healthy''; stale_items = jsonb array of {linked_source_id, institution_name, provider, connection_status, status_class} for those sources (''[]'' when none). Composes over the 043 pfin.linked_source_connection_state INVOKER view (Lock 11 read-composition) — owner isolation + the 025 aal2 gate are INHERITED via linked_source RLS (auth.uid() scope; RT-13 requesting-tenant-scoped credential-state resolution satisfied structurally). Scopes to is_active=TRUE to match the NAV constituent contract (netWorth.ts is_active filter) — an inactive/suspended source feeds nothing into the number so flagging it would be a false positive (NOT a D1 violation: D1 governs the honesty of the number the user sees). D1-FORWARD: the §2.4.4 surface list is illustrative-not-exhaustive; this framework applies to every aggregation consuming Plaid-sourced data — V1.0 wires NAV (§2.1.1), ramp at V1.1+ (§2.1.2/§2.1.5/§2.2.2/§2.3.2/§2.3.4/§2.6). Per-status affordance (Frontend): key on connection_status — Re-authenticate for IN (login_required,revoked,disconnected), informational for institution_down (marked-but-not-reauth); provider dispatches reauth() per adapter; status_class is context not driver. Authors no function with DEFINER (allowlist stays 4), no FK column (Decision-3 unchanged 15/13), no service_role (RT-26 stays 4), no catalogued §10 instance (stays 3).';
