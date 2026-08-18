---
name: feedback-scratch-db-perf-seed-must-be-rolled-back
description: Committed (not rolled back) synthetic perf-measurement rows into a shared scratch DB, then re-ran the full pgTAP suite in that SAME database — the leftover rows leaked into an unrelated migration's own inversion-control fixture ("corrupt RLS open, prove the leak is detected") and made it fail for a reason that had nothing to do with the code. Self-inflicted, caught by checking the failing test's actual "have" values against my own seed data before reporting a regression.
metadata:
  type: feedback
---

Needed a non-binding local perf number (AC5, SELF-220) and seeded ~72 synthetic
`pfin.nav_daily` rows for a throwaway tenant directly into the scratch DB
(`begin; insert ...; commit;` — deliberately committed, not wrapped in a battery
transaction, since I wanted the data to persist for a few `\timing` queries).
Cleaned nothing up afterward.

Later, re-running the FULL `supabase test db` suite against that SAME scratch
database (per team-lead's ask, to re-verify a migration after an unrelated
citation fix), two tests in `062_fn_nav_series_rls.sql` failed — its own
inversion-control legs, which deliberately break RLS open (`using (true)`)
inside a savepoint to PROVE the battery can detect a leaked cross-tenant row,
then roll back. My leftover tenant's rows were now ALSO visible under that
broken-open policy, and their values didn't match what 062's fixture expected
to see leak — a real, reproducible test failure that had nothing to do with
062, SELF-220, or any code change.

**Caught before reporting it as a regression** by comparing the failing
assertion's actual "have" values against my own seed data's `nav_value`s
(500000 + n*1500 for n in 0..71) — an exact match. Fixed by dropping and fully
rebuilding the scratch DB (not just deleting the rows) so there was zero doubt
about residual contamination, then re-ran clean.

**Why this matters beyond this one instance:** a scratch DB is disposable
per-SESSION, not disposable per-QUERY. Every battery file's OWN fixture is
self-contained (`begin`/`\ir`/`plan`/`rollback`) precisely so one file's data
can never bleed into another's — that discipline only holds if EVERYTHING
touching the shared database follows it. A committed, ad hoc seed for a
one-off purpose (a perf number, a manual spot-check) breaks that isolation for
every subsequent run against the same database, and the failure it causes
looks exactly like a real regression until traced back.

**How to apply:** any INSERT into a shared/reused scratch DB that isn't inside
a rolled-back test transaction is either (a) wrapped in its own
`begin;...rollback;` even when the immediate goal is a `\timing` read (rollback
doesn't undo the timing measurement, only the data), or (b) done in a
throwaway scratch DB used for NOTHING else and dropped immediately after, never
reused for a subsequent full-suite run. Never assume a scratch DB's disposable
reputation extends across an ad hoc detour taken mid-session for an unrelated
purpose. [[feedback_scratch_db_pgtap_harness_gotchas]] covers the harness-setup
gotchas; this is the adjacent lesson about what happens AFTER setup, once the
database starts accumulating session-specific state.

**RECURRED, second real instance (SELF-329, 2026-08-17), different failure
shape — worth carrying forward as still-live, not a one-off.** Deliberately
left a two-tenant fixture persisted in `scratch_self328` after a real-DB
Vitest integration test (SELF-238 AC9 — needed the data to survive an
out-of-process HTTP call, not just a same-session `\timing` read, so the
`begin/rollback` escape hatch didn't even apply). Two tasks later, an
UNRELATED battery's own idempotency re-run (077/080's `cross join (select
distinct users_id from user_taxonomy)` backfill logic — itself correct)
picked up the leftover tenants as "already provisioned" and inflated a
no-leak-total assertion (expected 2, got 4). Caught the same way: traced the
extra rows to my own leftover UUIDs before reporting it as a defect. Fixed by
a full drop-and-rebuild rather than a targeted DELETE — worth noting why the
targeted delete failed too: `account_balance_checkpoint` is
immutability-triggered (append-only audit-class), so even table-owner DELETEs
are blocked; a scratch DB with audit-class tables cannot be selectively
cleaned, only rebuilt. **The generalized rule this confirms: ANY reason a
scratch DB outlives one task — not just a perf detour, also a cross-process
integration test — creates the same hazard, and the fix is the same rebuild,
every time.**
