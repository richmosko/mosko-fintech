-- =====================================================================
-- Per-Wave battery — pfin.linked_source_sync_audit.source CHECK widen admits 'manual'
--   (SELF-317 "Sync now" trigger; ADR-037 amendment; V1-SHIP-BLOCK; Sec joint-review item C6a/C6b)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/047_sync_audit_manual_source.sql
--   - Drops the inline-unnamed `source` CHECK from 015 and re-adds it NAMED + widened:
--       linked_source_sync_audit_source_check  CHECK (source IN ('webhook','scheduled_poll','manual'))
--   - ADDITIVE widen {webhook, scheduled_poll} -> +manual. No function, no RLS/GRANT change.
-- Prereqs exercised (all on main): 015 — linked_source_sync_audit (service_role-only, append-only;
--   the immutability trigger linked_source_sync_audit_block_mutation raises on UPDATE/DELETE for ALL
--   roles). 044 — the fn_sync_audit_matched_linked_source BEFORE INSERT fence (Decision-3 #15),
--   LENIENT on a NULL linked_source_id (these rows carry NULL → the fence is a no-op here).
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (1) 'manual' is now an ACCEPTED source value (the whole point of 047).                         │
-- │       RED on any pre-047 stack (the 015 CHECK admitted only {webhook, scheduled_poll}) — the    │
-- │       WIRE-VALIDATE teeth: a green (1) is proof the migration actually applied.                 │
-- │ (2) a BOGUS source value is REJECTED with SQLSTATE 23514 (check_violation) — the CHECK still    │
-- │       fences the column (the widen did not drop the constraint).                                │
-- │ (3) …and the rejection is THIS constraint by name (linked_source_sync_audit_source_check) — not │
-- │       an incidental failure elsewhere. Pins the constraint identity (Architect-flagged pairing).│
-- │ (4) a NEAR-MISS ('scheduled' — a typo of scheduled_poll) is ALSO rejected 23514 → the CHECK is  │
-- │       an exact-set membership test, not a prefix/substring match (non-vacuous (2) companion).   │
-- │ (5) 'webhook' STILL accepted — the widen was additive (no regression of the pre-047 values).    │
-- │ (6) 'scheduled_poll' STILL accepted — additive (the @daily cron's provenance value is intact).  │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; a plain CHECK widen on an existing
--   service_role-only audit table adds no catalogued instance — per the 047 header §10 3-axis, Path
--   B). Decision-3 family UNCHANGED (source is a plain enum-string, not an FK-shaped column). RT-26
--   allowlist stays 3; SECURITY DEFINER allowlist stays 4 (no function authored). Sec pre-blessed
--   CLEAN-WITH-CONDITIONS (C6b = ADD 'manual' to the CHECK).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY. No tenant/auth context needed — the CHECK is role-agnostic
--   DDL, exercised by direct INSERTs at the migration/postgres role. Rows carry NULL users_id (the FK
--   is ON DELETE SET NULL, nullable → no auth.users seed required) and NULL linked_source_id (the 044
--   fence is lenient-on-null) so the ONLY gate under test is the `source` CHECK. NO PII / NO real
--   account numbers / NO credentials / NO prod data.
--
-- IMMUTABILITY / ROLLBACK DISCIPLINE (Architect-flagged): the table's immutability trigger fences
--   DELETE/UPDATE for ALL roles, so cleanup-by-DELETE is impossible — this battery uses ROLLBACK-
--   wrapped INSERTs ONLY (begin…rollback). Accepted rows persist within the txn (harmless) and are
--   discarded at rollback; rejected INSERTs are caught by pgTAP's per-assertion savepoint. INSERT is
--   NOT fenced by the immutability trigger (BEFORE UPDATE/DELETE/TRUNCATE only) → all inserts are legal.
--
-- ⟦WIRE-VALIDATE⟧ authored against 047's firmed contract; the authoritative run is the 001->047 reset
--   stack. RED-until-047-applied on (1) is EXPECTED on any pre-047 stack (the widen absent).
-- =====================================================================

begin;

select plan(6);

-- (1) 'manual' is ACCEPTED (RED pre-047). users_id + linked_source_id NULL → only the source CHECK gates.
select lives_ok(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('plaid', 'manual') $$,
  '(1) source=''manual'' is accepted by the widened CHECK (the 047 point; RED on any pre-047 stack whose 015 CHECK admitted only {webhook, scheduled_poll})'
);

-- (2) a bogus value is REJECTED with 23514 (check_violation) — the column is still fenced.
select throws_ok(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('plaid', 'bogus_source') $$,
  '23514',
  null,
  '(2) a bogus source value is rejected with SQLSTATE 23514 (check_violation) — the widen did not drop the CHECK'
);

-- (3) …and the raise names THIS constraint (pins the identity; Architect-flagged pairing).
select throws_like(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('plaid', 'bogus_source') $$,
  '%linked_source_sync_audit_source_check%',
  '(3) the rejection is the named constraint linked_source_sync_audit_source_check (not an incidental failure elsewhere)'
);

-- (4) a NEAR-MISS ('scheduled', a typo of scheduled_poll) is ALSO rejected 23514 → exact-set membership,
--     not a prefix/substring match (non-vacuous companion to (2)).
select throws_ok(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('plaid', 'scheduled') $$,
  '23514',
  null,
  '(4) a near-miss ''scheduled'' (typo of scheduled_poll) is rejected 23514 → the CHECK is exact-set membership, not a prefix match'
);

-- (5) 'webhook' STILL accepted — additive widen, no regression of the pre-047 values.
select lives_ok(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('plaid', 'webhook') $$,
  '(5) source=''webhook'' still accepted — the widen was additive (pre-047 value preserved)'
);

-- (6) 'scheduled_poll' STILL accepted — additive (the @daily cron provenance value intact).
select lives_ok(
  $$ insert into pfin.linked_source_sync_audit (provider, source) values ('simplefin', 'scheduled_poll') $$,
  '(6) source=''scheduled_poll'' still accepted — additive (the cron''s provenance value preserved)'
);

select * from finish();
rollback;
