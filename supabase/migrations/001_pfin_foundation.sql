-- ============================================================================
-- Migration: pfin foundation — schema + fn_refresh_updated_at DEFINER helper
-- Phase 5 Step 4 close-gate (SELF-186). Greenfield foundational migration:
-- creates the `pfin` schema and the `updated_at` trigger helper that downstream
-- base-table migrations attach. Authored under ADR-011 (Lock 6 / Lock 11 / D9).
--
-- Numbering: 001 is the FOUNDATIONAL migration — it is ordered before 002 and
-- every later base-table migration. Both 001 and 002 begin with the same
-- idempotent `create schema if not exists pfin` so each file is self-sufficient
-- on a fresh `supabase db reset` regardless of which ran first; lexical order
-- (001 < 002) is the applied order. 001 is GREENFIELD — there is no incumbent
-- `tenant_id` DDL to rename. The `tenant_id` -> `users_id` rename (Lock 6 /
-- ADR-011 Decision 10) was resolved at the artifact-design layer in the Step 4
-- close PR; 001 INSTANTIATES the `users_id = auth.uid()` convention by-construction
-- (documented below), it does not rename built DDL. See ADR-011 Decision 10
-- amendment annotation (greenfield reconciliation).
--
-- V1 RLS PREDICATE CONVENTION (Lock 6 / Lock 11 — documented-convention-only here).
--   The locked V1 multi-tenant isolation primitive is Postgres RLS keyed on
--   `users_id = auth.uid()` (ADR-011 Decision 10 column name + Lock 11
--   RLS-default-trust). `users_id` is the ONLY tenant-isolation predicate column
--   across all V1 user-data tables; it anchors to `auth.users(id)`. 001 creates
--   NO base tables and therefore NO RLS policies — this header documents the
--   convention so every base-table migration inherits it; the first base-table
--   migration is where the `users_id = auth.uid()` policies actually land + carry
--   their paired table-level GRANTs (supabase/CLAUDE.md gotcha: ACL-before-RLS).
--
-- POSTURE RATIONALE — fn_refresh_updated_at is SECURITY DEFINER (LOCKED allowlist).
--   `fn_refresh_updated_at` is ONE OF THE TWO V1 SECURITY DEFINER allowlist entries
--   (ADR-011 Decision 9: allowlist is exactly 2 — `fn_refresh_updated_at` + the
--   audit-log insert helper; the audit helper lands with its base table in a later
--   migration, NOT here). This posture is LOCKED at Decision 9 — Sec joint-review
--   CONFIRMS the implementation matches the locked posture; it does not relitigate
--   whether the function should be DEFINER. Why DEFINER is the locked choice:
--     - It is a BEFORE UPDATE trigger helper attached across many pfin tables
--       (e.g. Lock 14 settings tables `updated_at` UPDATE-refresh, mod #9). DEFINER
--       pins execution to the function owner regardless of which role's UPDATE fires
--       the trigger (authenticated user vs service_role), so the timestamp refresh
--       fires uniformly + deterministically and cannot be subverted by an invoking
--       role lacking some incidental privilege.
--     - The body touches NO tables — only the NEW pseudo-record + `now()`. So the
--       elevated-privilege blast radius is effectively nil (least-privilege body):
--       DEFINER grants no table-reach beyond what the trigger already had.
--   Why `set search_path = ''` is MANDATORY (the single security-load-bearing edge).
--     For ANY SECURITY DEFINER function, an attacker who can influence `search_path`
--     could shadow an unqualified function/operator/object reference with a hostile
--     object in a schema they control — executing it with the DEFINER's elevated
--     privileges (search-path privesc, CVE-class). `set search_path = ''` forces all
--     references to resolve from `pg_catalog` only (always implicitly present) or be
--     schema-qualified, removing the attack surface. The body references only `now()`
--     (pg_catalog) + the NEW record, so '' is both safe and complete here. This is
--     the highest-value line in the file — verify it is present and exactly `''`.
--
-- CONTRACT
--   pfin.fn_refresh_updated_at() RETURNS trigger — LANGUAGE plpgsql, SECURITY DEFINER,
--   `set search_path = ''`.
--   - Intended as a BEFORE UPDATE … FOR EACH ROW trigger on any pfin table that
--     carries an `updated_at` column. Sets NEW.updated_at := now() and returns NEW.
--   - Pre-req on the attaching table: an `updated_at` column (TIMESTAMPTZ). The
--     base-table migration owns the trigger ATTACHMENT (`create trigger … execute
--     function pfin.fn_refresh_updated_at()`); 001 owns only the helper definition.
--   - Security-load-bearing edge: `set search_path = ''` (the DEFINER privesc fence).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_refresh_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function pfin.fn_refresh_updated_at() is
  'BEFORE UPDATE updated_at trigger helper (ADR-011 Decision 9 — 1 of the 2 V1 SECURITY DEFINER allowlist entries; the other is the audit-log insert helper). Sets NEW.updated_at := now() and returns NEW; attach as BEFORE UPDATE FOR EACH ROW on any pfin table carrying an updated_at column (e.g. Lock 14 settings tables, mod #9). SECURITY DEFINER + set search_path = '''' is the locked posture: DEFINER pins execution context across invoking roles; search_path = '''' is the privesc fence (body touches no tables — only NEW + pg_catalog now()). Posture LOCKED at Decision 9 — Sec confirms, does not relitigate.';
