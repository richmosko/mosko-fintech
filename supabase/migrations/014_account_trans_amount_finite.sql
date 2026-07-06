-- ============================================================================
-- Migration: pfin.account_trans.amount — reject NaN (DB-layer defense-in-depth)
-- Phase 6 Build Loop (SELF-201 / Sec Lock-14 FLAG remediation on the 013 RPC).
-- Adds a CHECK constraint rejecting the numeric special value 'NaN' on the
-- immutable audit-class ledger's money column. Companion to 013 (same PR/branch).
--
-- Numbering: 014 follows 013 (fn_create_manual_account). Depends only on 004
-- (pfin.account_trans exists; amount numeric(20,4)). ALTER-only; no function, no
-- RLS, no new column, no FK.
--
-- ----------------------------------------------------------------------------
-- WHY (Sec FLAG — app-layer Zod is bypassable on an API-exposed write path).
--   013's fn_create_manual_account is EXECUTE-granted to authenticated and pfin is
--   API-exposed (ADR-023 [api] schemas), so it is callable directly via PostgREST
--   at /rpc/fn_create_manual_account. Backend's Lock-14 numeric-sanitization battery
--   (Zod, app-layer) rejects NaN/Inf/currency-string BEFORE the RPC — but a direct
--   PostgREST call (or any future caller) BYPASSES the app layer entirely. The
--   authoritative fence for a value invariant on an internet-facing write path must
--   live at the DB layer. This is the defense-in-depth counterpart to the app-layer
--   Zod battery, not a replacement for it (both layers stand).
--   IMMUTABILITY raises the stakes: account_trans is append-only (004 block triggers,
--   all roles). A NaN amount that reaches the ledger can NEVER be UPDATEd out — only
--   reverse-and-replaced — and NaN poisons every downstream aggregation (a single NaN
--   in a SUM makes NAV/current-state NaN). Rejecting it at write time is the correct
--   conservative posture for an immutable money ledger.
--
-- ----------------------------------------------------------------------------
-- SCOPE — NaN ONLY (empirically verified; the Infinity vector is already fenced).
--   Postgres numeric supports three non-finite special values: 'NaN', 'Infinity',
--   '-Infinity'. VERIFIED against the local stack (PG 17, account_trans.amount is
--   numeric(20,4)):
--     - 'NaN'::numeric(20,4)       → STORABLE (NaN is exempt from precision/scale) →
--       THIS IS THE GAP this migration closes.
--     - 'Infinity'::numeric(20,4)  → ERROR "numeric field overflow: A field with
--       precision 20, scale 4 cannot hold an infinite value" → the TYPED column
--       already rejects ±Infinity at coercion, BEFORE any CHECK. No Infinity guard
--       is added — it would be dead code. (If amount's type ever loosens to bare
--       `numeric`, revisit: ±Infinity would then become storable and this CHECK
--       should extend to `amount <> 'Infinity' and amount <> '-Infinity'`.)
--   CHECK SEMANTICS (verified): Postgres numeric orders NaN as EQUAL to itself and
--   GREATER than all finite values, so `amount <> 'NaN'::numeric` is:
--     - a finite amount (e.g. 100.0000): 100 <> NaN → TRUE  → row passes.
--     - NaN:                              NaN <> NaN → FALSE → row rejected.
--   (Note `amount = amount` does NOT catch NaN here — unlike IEEE float, numeric
--   NaN = NaN is TRUE — so the explicit `<> 'NaN'` idiom is required.)
--
-- ----------------------------------------------------------------------------
-- PLACEMENT DECISION (Architect's call per the task): companion migration 014, NOT
--   an inline ALTER in 013. Rationale: single-purpose migration files (project
--   convention); the CHECK is a TABLE-LEVEL invariant protecting EVERY write path to
--   account_trans.amount (the 013 RPC, service_role Plaid sync, reverse-and-replace,
--   any future path) — not RPC-specific — so it reads truthfully as a table-integrity
--   migration with its own Sec-flag-provenance header, and 013 stays a clean
--   function-only migration. Lands in the SAME PR/branch as 013 (per the task).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference Decision 4; do NOT restate the list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26). (i) numbering
--   RT-22 first / RT-26 second — unchanged. (ii) layer-attribution — a table CHECK
--   constraint on a money column; no infra-credential-presence (RT-22) or
--   SUPABASE_SERVICE_ROLE_KEY allowlist (RT-26) surface touched. (iii) Decision 4
--   linked, not restated.
--
-- DECISION 3 / DEFINER allowlist — no change. No FK-shaped column (family stays 5);
--   no function authored (SECURITY DEFINER allowlist stays 3).
--
-- CONTRACT
--   pfin.account_trans gains CHECK constraint account_trans_amount_finite:
--     check (amount <> 'NaN'::numeric) — rejects NaN for ALL roles at write time
--     (a table constraint is role-agnostic; service_role bypasses RLS but NOT CHECK
--     constraints). Idempotent add (pg_constraint guard — PG has no ADD CONSTRAINT
--     IF NOT EXISTS). Validates existing rows (greenfield: none non-finite).
-- ============================================================================

create schema if not exists pfin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'account_trans_amount_finite'
      and conrelid = 'pfin.account_trans'::regclass
  ) then
    alter table pfin.account_trans
      add constraint account_trans_amount_finite
      check (amount <> 'NaN'::numeric);
  end if;
end $$;

comment on constraint account_trans_amount_finite on pfin.account_trans is
  'DB-layer defense-in-depth: rejects the numeric special value NaN on the immutable ledger''s money column (SELF-201 Sec Lock-14 FLAG remediation; ADR-026 amendment). The 013 fn_create_manual_account RPC is API-exposed (ADR-023), so app-layer Zod is bypassable via a direct PostgREST /rpc call — this CHECK is the authoritative value fence, role-agnostic (service_role bypasses RLS but not CHECK constraints). NaN-only: numeric(20,4) already rejects ±Infinity at coercion (precision overflow, verified), so no Infinity guard is needed unless the column type loosens to bare numeric. `<> ''NaN''` (not `= amount`) because numeric NaN = NaN is TRUE. Immutability makes write-time rejection load-bearing: a NaN row can never be UPDATEd out and poisons every SUM/NAV aggregation.';
