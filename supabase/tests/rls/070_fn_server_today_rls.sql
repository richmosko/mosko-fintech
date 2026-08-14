-- =====================================================================
-- Per-Wave battery — pfin.fn_server_today() — ADR-044 R2, the database-derived
--   as-of date (SELF-221; migration 070). SECURITY INVOKER, reads NO relation,
--   no tenant surface. Paired with the migration in the SAME PR.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/070_fn_server_today.sql, commit
--   14600bd. Every leg below is one line of that migration's own QA
--   TEST-PAIRING block (items 1-5) — no drift from what that block specifies.
--
--   Contract as landed: pfin.fn_server_today() RETURNS date — SECURITY
--   INVOKER · STABLE · set search_path = ''. `select current_date;` — one
--   statement, deliberately. R2's guarantee (both sides of ONE comparison use
--   the SAME day) rests entirely on STABLE's per-transaction freeze, NOT on
--   any zone trick — a future "improvement" that hard-pins a zone inside this
--   function would BREAK R2 by making the function and its caller disagree.
--   That inversion is exactly what leg (3) below exists to catch.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per migration-header QA TEST-PAIRING item ────┐
-- │ (1)  RET  returns a `date`, non-NULL.                                              │
-- │ (2)  STB  SAME-TRANSACTION STABILITY: two calls in one transaction agree —         │
-- │          R2's guarantee in its testable form, asserted directly rather than        │
-- │          trusted from the STABLE marker.                                           │
-- │ (3)  ZN   AGREES WITH THE SESSION'S OWN current_date, under BOTH of two extreme    │
-- │          session TimeZones. ⚠ NOT "same output across zones" — current_date        │
-- │          legitimately DIFFERS by zone, by design (ADR-044: R2 shares one           │
-- │          derivation, it does not escape the zone). The property under test is      │
-- │          that this function never drifts from a bare current_date call, in         │
-- │          EITHER zone — pinning that a future edit doesn't sneak in a hardcoded      │
-- │          zone or a cached/derived value.                                           │
-- │ (4)  PST1 catalog posture, read declaratively: prosecdef false (INVOKER),          │
-- │          provolatile 's' (STABLE), search_path pinned empty.                       │
-- │ (5)  A   ACL: authenticated yes, PUBLIC no.                                        │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ `supabase db reset` is PROHIBITED — destroys F/CTO's active local test data.
--   Scratch database only, pg_prove via `supabase test db`, never bare psql.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 7 : 1 non-null (RET) + 1 same-txn stability (STB) + 2 zone-agreement
-- (ZN, two extreme TimeZones) + 1 catalog posture (PST1) + 2 ACL (authenticated
-- + PUBLIC).
select plan(7);

-- =====================================================================
-- (1) RET — returns a `date`, non-NULL. No tenant context needed (reads no
--   relation) but exercised as `authenticated` anyway, matching how every real
--   caller reaches it.
-- =====================================================================
select _rls.set_tenant(_rls.tenant_a());
select ok(
  (select pfin.fn_server_today() is not null),
  '(RET1) fn_server_today() returns a non-NULL date'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (2) STB — SAME-TRANSACTION STABILITY. Two calls inside this one transaction
--   must agree — the mechanism (STABLE freezes current_date for the
--   transaction's duration) behind R2's whole guarantee.
-- =====================================================================
select _rls.set_tenant(_rls.tenant_a());
select is(
  (select pfin.fn_server_today()), (select pfin.fn_server_today()),
  '(STB1) ⭐ two calls in ONE transaction return the SAME value — this IS R2''s guarantee, asserted directly rather than trusted from the STABLE marker'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (3) ZN — AGREES WITH THE SESSION'S OWN current_date, under two extreme
--   session TimeZones (Kiritimati UTC+14 / Midway UTC-11). NOT a
--   byte-identical-across-zones claim — current_date is EXPECTED to differ
--   between these two runs if the wall-clock instant straddles a day
--   boundary in one zone but not the other. What must hold in EITHER zone is
--   that fn_server_today() tracks a bare `select current_date` in the SAME
--   session — never a cached, hardcoded, or independently-derived value.
-- =====================================================================
set local TimeZone = 'Pacific/Kiritimati';
select _rls.set_tenant(_rls.tenant_a());
select is(
  (select pfin.fn_server_today()), (select current_date),
  '(ZN1) under Pacific/Kiritimati (UTC+14): fn_server_today() = current_date in this SAME session — tracks the live clock, does not escape or hardcode a zone'
);
select set_config('role', 'postgres', true);

set local TimeZone = 'Pacific/Midway';
select _rls.set_tenant(_rls.tenant_a());
select is(
  (select pfin.fn_server_today()), (select current_date),
  '(ZN2) ⭐ …and the SAME agreement holds under Pacific/Midway (UTC-11), the opposite extreme — proving the tracking is zone-GENERAL, not a coincidence of one zone. This is the non-vacuity companion to (ZN1)'
);
select set_config('role', 'postgres', true);
reset TimeZone;

-- =====================================================================
-- (4) PST1 — CATALOG POSTURE, read declaratively.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_server_today'),
  array['false','s','search_path=""'],
  '(PST1) POSTURE, read DECLARATIVELY from the catalog: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty. A DEFINER swap would detach this function from the caller''s session, breaking R2''s whole basis, while leaving every other leg green'
);

-- =====================================================================
-- (5) A — ACL.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_server_today()', 'execute'),
  '(A1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_server_today()', 'execute'),
  '(A2) LOAD-BEARING: PUBLIC does NOT — `create function` grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and silent on removal'
);

select * from finish();
rollback;
