-- =====================================================================
-- Per-Wave battery — pin the NAV read-composition functions STABLE, closing
--   the DDL-vs-CONTRACT-text volatility divergence (Sec joint-review ruling
--   (4), PR #480 / SELF-237; V1-SHIP-BLOCK). Pure catalog-attribute battery:
--   `ALTER FUNCTION ... STABLE` changes pg_proc.provolatile ONLY — no body,
--   signature, grant or comment changes, so NO value-based assertion in this
--   file can discriminate whether the migration applied. Structural-only by
--   necessity, not by convenience (079''s own CONTRACT block states this).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/079_volatility_pin_stable.sql
--   `alter function ... stable` on FOUR signatures:
--     · pfin.fn_account_unrealized_gl(date)
--     · pfin.fn_compute_nav(date, boolean)
--     · pfin.fn_compute_nav(date)               -- the 1-arg wrapper (050)
--     · pfin.fn_nav_composition(date)
--
-- ┌─ WHY STRUCTURAL-ONLY, AND WHY IT ALSO WATCHES 078''s ORDERING ─────────┐
-- │ 079''s own CONTRACT: "No output of any of the four changes for any     │
-- │ input... The leg that discriminates is the structural one: assert      │
-- │ pg_proc.provolatile = 's' for each of the four signatures." A totals-  │
-- │ or value-based battery is LITERALLY INCAPABLE of catching a regression │
-- │ here — the fix is invisible to every query result by construction.     │
-- │ 079''s own header also names the fragility this leg is the ONLY watcher│
-- │ for: "CREATE OR REPLACE replaces the WHOLE definition including        │
-- │ volatility. Any future CREATE OR REPLACE of these four MUST carry      │
-- │ `stable` in its own body or re-ALTER afterwards." On the LIVE 001->079 │
-- │ stack (078 runs before 079, correctly ordered), (V1)-(V4) below reading│
-- │ 's' IS the proof that ordering held; a future re-ordering or a future  │
-- │ CREATE OR REPLACE that drops `stable` from its own body would both     │
-- │ read as (V1)-(V4) going RED, with no other leg in the house able to    │
-- │ see it.                                                                 │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised (on the 001->079 stack): 050 (fn_compute_nav 1-arg
--   wrapper, pure delegation to the 2-arg form); 059 (fn_account_unrealized_gl
--   / fn_compute_nav(date,boolean) / fn_nav_composition live definitions); 076
--   (fn_subcat_market_value, ALREADY `stable` since its own authoring —
--   exercised here as a companion, NOT one of the four this migration pins);
--   078 (this same branch — CREATE OR REPLACE on three of these five
--   functions; MUST run before 079 or it erases the pin, see above).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (four ALTERs changing a planner-
--   visibility attribute only — no credential surface, no code-layer fence,
--   no network/config surface; read ADR-011 Decision 4 live). Decision-3
--   family UNCHANGED — no table, column, FK or array touched. This battery
--   introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): no tenant/auth context needed. pg_proc.provolatile
--   is a role-agnostic catalog attribute, read at role=postgres. NO PII / NO
--   real account numbers / NO prod data / NO seed rows of any kind — this
--   battery reads pg_catalog only.
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->079 against a scratch DB (NON-destructive). plan(7): 4 pinned (V1-V4)
--   + 1 unaffected companion (V5) + 2 negative/scope-boundary controls
--   (NEG1-NEG2) = 7.
-- =====================================================================

begin;

select plan(7);

-- =====================================================================
-- PINNED (V1-V4) — pg_proc.provolatile = 's' (STABLE) for each of the four
--   signatures the migration names. fn_compute_nav has TWO catalog objects
--   sharing a proname; discriminated by pronargs, not by guesswork.
-- =====================================================================
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_account_unrealized_gl' and p.pronamespace = 'pfin'::regnamespace
      and p.pronargs = 1),
  's'::"char",
  '(V1) pfin.fn_account_unrealized_gl(date): pg_proc.provolatile = ''s'' (STABLE)'
);
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_compute_nav' and p.pronamespace = 'pfin'::regnamespace
      and p.pronargs = 2),
  's'::"char",
  '(V2) pfin.fn_compute_nav(date, boolean) [the 2-arg engine]: pg_proc.provolatile = ''s'' (STABLE)'
);
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_compute_nav' and p.pronamespace = 'pfin'::regnamespace
      and p.pronargs = 1),
  's'::"char",
  '(V3) pfin.fn_compute_nav(date) [the 1-arg wrapper, 050]: pg_proc.provolatile = ''s'' (STABLE) — the surface most existing callers (037''s fn_gl_entries Unrealized memo) actually reach'
);
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_nav_composition' and p.pronamespace = 'pfin'::regnamespace
      and p.pronargs = 1),
  's'::"char",
  '(V4) pfin.fn_nav_composition(date): pg_proc.provolatile = ''s'' (STABLE)'
);

-- =====================================================================
-- (V5) UNAFFECTED COMPANION — fn_subcat_market_value(date,boolean) has
--   declared `stable` inline since 076, and is CREATE-OR-REPLACEd again by
--   078 (this same branch) with `stable` still present in its own body. NOT
--   one of the four this migration ALTERs, but the ONLY watcher for a
--   regression where 078''s body loses its inline `stable` keyword — that
--   would NOT be caught by V1-V4 (a different function) or by 078''s own
--   battery (which asserts values, not volatility).
-- =====================================================================
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_subcat_market_value' and p.pronamespace = 'pfin'::regnamespace),
  's'::"char",
  '(V5) unaffected companion: pfin.fn_subcat_market_value(date,boolean) is STILL provolatile=''s'' after 078''s CREATE OR REPLACE (076''s own inline `stable`, not touched by 079 — this migration''s ALTER list is exactly four, not five) — the only watcher for 078 silently dropping its own inline keyword'
);

-- =====================================================================
-- NEGATIVE / SCOPE-BOUNDARY (NEG1-NEG2) — 079''s own header names these as
--   explicitly OUT OF SCOPE ("a PARTIAL closure would be worse than none...
--   recorded here as the named follow-up rather than absorbed silently").
--   Confirms the matcher above isn''t vacuously true for every function in
--   pfin, and documents the boundary this migration deliberately does not
--   cross.
-- =====================================================================
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_holdings_as_of' and p.pronamespace = 'pfin'::regnamespace),
  'v'::"char",
  '(NEG1) scope boundary, non-vacuous: pfin.fn_holdings_as_of(date) is STILL VOLATILE — 079''s header names it explicit out-of-scope (a VOLATILE callee inside a STABLE outer function is an interior seam this migration does not claim to close); proves (V1)-(V5) are not matching every function in pfin as ''s'''
);
select is(
  (select p.provolatile from pg_proc p
    where p.proname = 'fn_gl_entries' and p.pronamespace = 'pfin'::regnamespace),
  'v'::"char",
  '(NEG2) scope boundary: pfin.fn_gl_entries(date) is STILL VOLATILE — the GL engine (035/037), also named explicit out-of-scope in 079''s header (auditing/pinning it is "a larger claim than this migration''s review scope")'
);

select * from finish();
rollback;
