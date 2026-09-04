---
name: count-function-evaluations-with-track-functions
description: How to MEASURE how many times Postgres actually evaluates a function per call (track_functions + pg_stat_user_functions), why a set-search_path function is countable at all, and the two traps (stats flush interval, template staleness after editing a numbered migration).
metadata:
  type: reference
---

To turn "the planner MAY evaluate this N times" into a measurement, use the stats
collector, not EXPLAIN — a scalar function call in a target list has no plan node
and no rowcount, so `EXPLAIN (ANALYZE, VERBOSE)` cannot show its evaluation count.

Recipe (measured 2026-09-04, SELF-268 `105`, PG17 local stack):

```
set track_functions = 'all';   -- 'pl' misses language sql; SUSET, so connect as
                               -- supabase_admin (postgres is NOT superuser locally
                               -- and pg_stat_reset() raises permission denied)
select pg_stat_reset();
select <the one call under test>;
select pg_sleep(2);            -- see trap 1
select pg_stat_clear_snapshot();
select p.proname, s.calls from pg_stat_user_functions s
  join pg_proc p on p.oid = s.funcid where p.proname in (...);
```

**Why the callee is countable at all:** Postgres refuses to inline a `language sql`
function that carries a `SET` clause (`proconfig` non-null). Every `pfin.fn_*` here
has an empty-search_path SET, so each is a real call at runtime and the counter sees
it. An inlinable SQL function would vanish from `pg_stat_user_functions` entirely
and this instrument would silently report nothing — check `proconfig` before
trusting a zero.

**Trap 1 — the stats flush interval.** A backend accumulates function stats and
reports them on a >=1s interval, so reading immediately after the call under-reports
(measured: two outer calls in a row read back as `calls = 1` for the outer function
and `4` for the callee — a snapshot of the FIRST call only). Settle with `pg_sleep`
before reading, and sanity-check that the OUTER function's count equals the number
of times you actually called it.

**Trap 2 — editing an already-numbered migration makes `pfin_tmpl` stale.**
`scripts/db-template-clone.sh` hashes the whole migrations tree and REFUSES to
clone on a mismatch. So: clone FIRST (a green fence also proves the template's copy
is byte-identical to the frozen one), then edit, then re-apply the edited file onto
that clone with `psql -f` as `postgres` (the role `db-template-build.sh` applies
migrations as). A second clone after the edit needs `createdb -T pfin_tmpl` by hand
plus a manual replay of the per-database settings (`TimeZone`) the script replays.

**The finding this produced:** a CTE referenced exactly once is INLINED, so every
dereference of its column re-evaluates the function inside it — 4 evaluations per
call, fixed to 1 by `tax as materialized (...)`. A `prosrc`-regex "called exactly
once" battery leg pins the SOURCE TEXT and is blind to this; see
[[feedback_a_grep_hit_in_a_comment_is_not_a_call_site]] for the neighbouring error.
