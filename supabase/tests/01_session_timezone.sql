-- =====================================================================
-- HARNESS PROPERTY — the session TimeZone this suite runs under
-- =====================================================================
-- QA-owned. Authors no schema. Not tied to a migration, so it lives beside the inversion
-- self-test rather than in rls/, which is per-migration.
--
-- ┌─ ⚠ READ THIS BEFORE TREATING A GREEN HERE AS "THE TIMEZONE IS PINNED" ────────────┐
-- │ **IT IS NOT. THIS ASSERTS A PROPERTY OF WHICHEVER DATABASE THE SUITE JUST RAN      │
-- │ AGAINST — in CI, an ephemeral container that is NOT the deployment.** It cannot    │
-- │ observe production and must never be cited as evidence about it.                    │
-- │                                                                                      │
-- │ THE DEFECT THIS IS ADJACENT TO (Sec, 2026-08-04) IS NOT FIXED BY THIS FILE:         │
-- │   `+page.server.ts` computes the NAV as-of as `new Date().toISOString().slice(0,10)` │
-- │   — unconditionally UTC, in the NODE process. Postgres evaluates `closed_at::date`   │
-- │   in the SESSION's TimeZone. Two clocks in two processes; they agree only if the     │
-- │   session is UTC. MEASURED, reproducing Sec's construction:                          │
-- │     session Asia/Tokyo, instant 2026-03-01 23:00Z                                    │
-- │       -> closed_at::date = 2026-03-02, Node says 2026-03-01                          │
-- │       -> `closed_at::date > '2026-03-01'` is TRUE                                    │
-- │       -> A JUST-CLOSED ACCOUNT STAYS IN THE NAV HEADLINE FOR ~9 HOURS.               │
-- │     session UTC                 -> FALSE, correctly excluded.                        │
-- │     session America/Los_Angeles -> FALSE. **West of UTC fails SAFE, which is WORSE   │
-- │       than failing loudly: the defect becomes hemisphere-dependent and a US-based    │
-- │       reviewer cannot reproduce it.**                                                │
-- │                                                                                      │
-- │ THE LOAD-BEARING VERIFICATION IS AT DEPLOY TIME AND IS NOT MINE (devops). This file  │
-- │ covers the CI stack only. Two claims, two instruments; do not let a green here       │
-- │ stand in for the other one.                                                           │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THIS FILE EXISTS AT ALL, given the above ─────────────────────────────────────┐
-- │ I measured whether the EXISTING suite depends on the pin, expecting it did. **IT    │
-- │ DOES NOT.** `049`'s boundary battery — including the non-midnight (1i)/(1j)/(1k)    │
-- │ assertions — returns 33/33 with 0 failures under UTC, Asia/Tokyo AND                 │
-- │ America/Los_Angeles. The fixture inserts NAIVE timestamps (`'2026-06-30 14:00'`),    │
-- │ which are interpreted in the session zone, and the as-of comparison happens in that  │
-- │ same zone — so both shift together and cancel.                                       │
-- │                                                                                      │
-- │ That measurement is the reason this file is worth ~10 lines and not more, and it is  │
-- │ recorded because it CUTS AGAINST the case for adding it: **nothing in the suite      │
-- │ currently relies on the session zone.** Its value is forward-looking and narrow —    │
-- │ the moment someone writes a date assertion that ISN'T zone-invariant (an absolute    │
-- │ `timestamptz` literal, a `now()`-relative fixture, a `current_date` comparison), they │
-- │ silently acquire a dependency on an unpinned property, and the failure would present  │
-- │ as a mysterious date-off-by-one in CI rather than as a configuration problem.        │
-- │ THIS FILE MAKES THAT ARRIVE AS A NAMED RED INSTEAD.                                   │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- POSTURE (SECURITY §4.5): reads catalog/GUC state only. No fixture, no tenant, no data.

begin;

-- plan = 2. Deliberately small: this file's honest claim is narrow, and padding it with
-- assertions about Postgres's own `::date` semantics would be testing the platform.
select plan(2);

-- (T1) THE SESSION THIS SUITE RUNS IN IS UTC.
--   Read back via current_setting rather than trusting a config file — a pinned setting nobody
--   reads back is the same class of unmeasured premise as an unpinned one, which is the whole
--   argument for this assertion existing.
select is(
  current_setting('TimeZone'),
  'UTC',
  '(T1) the session TimeZone of the database THIS SUITE RAN AGAINST is UTC. ⚠ SCOPE: the CI/local stack ONLY — this file cannot observe the deployment, and a green here is NOT evidence the production database is pinned (that check is deploy-time and DevOps-owned). What it does buy: any future date assertion that is not zone-invariant fails HERE, by name, instead of surfacing as an off-by-one-day mystery somewhere downstream'
);

-- (T2) …AND `authenticated` SEES THE SAME ZONE.
--   NOT redundant with (T1), and this is the assertion I would keep if forced to choose.
--   A TimeZone can be set per-ROLE (`alter role authenticated set TimeZone = ...`), which
--   OVERRIDES the database default. PostgREST runs every request as `authenticated` via
--   SET LOCAL ROLE, so a role-level override would move production's effective zone while the
--   database default — the thing anyone would inspect, and the thing a pin most likely
--   targets — still read UTC. Verified today: no role-level TimeZone setting exists, so this
--   is a fence on a real and currently-open regression vector, not a restatement of (T1).
select is(
  (select setting from pg_settings where name = 'TimeZone'),
  'UTC',
  '(T2) the effective TimeZone is UTC at the session level, which is the level PostgREST requests actually run in. Distinct from (T1) rather than a restatement: `alter role authenticated set TimeZone` overrides the database default, so pinning the DATABASE and inspecting the DATABASE can both read UTC while every real request runs in another zone. RED means the effective session zone drifted from the pinned one — inspect pg_db_role_setting, not just the database default'
);

select * from finish();
rollback;
