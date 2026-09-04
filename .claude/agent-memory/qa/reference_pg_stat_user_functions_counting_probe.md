---
name: pg-stat-user-functions-counting-probe
description: Session-level track_functions='all' + pg_stat_user_functions.calls delta + pg_stat_force_next_flush() as an independent counting probe for "callee evaluated N times per caller call" claims — survives a rolled-back wrapping transaction. Used SELF-268 re-confirm (2026-09-04) to verify N-1's MATERIALIZED fix independently of the migration's own EXPLAIN/pg_stat measurement.
metadata:
  type: reference
---

To independently verify a claim like "fn_A is evaluated exactly once per fn_B call" (e.g. a `materialized` CTE claim) without trusting the author's own measurement:

```sql
set track_functions = 'all';   -- session-level; works even if the cluster default is 'none'
-- baseline read of pg_stat_user_functions.calls for the target funcid
begin;
  -- set RLS claims, call the caller function
rollback;                      -- fine — pg_stat counters are NOT transactional, survive rollback
select pg_stat_force_next_flush();   -- forces the stats collector to flush immediately (no async lag)
-- re-read pg_stat_user_functions.calls for the same funcid, take the delta
```

Ran this twice in a row (two separate begin/rollback blocks) to confirm the delta is exactly +1 each time, not just "some 1 total" — a single before/after pair could coincidentally show 1 for an unrelated reason. Get the funcid via `select oid from pg_proc where proname = '...'`.

This is a DIFFERENT method from the migration author's own EXPLAIN-plan-based measurement — using two independent measurement techniques against the same claim is the point (a wrong first measurement doesn't reproduce itself the same wrong way in a second method).

See also [[feedback_language_sql_body_has_no_pg_depend_edges]] for a related "the obvious catalog check is vacuous, use a different signal" lesson from a prior QA round.
