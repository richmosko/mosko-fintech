---
name: set-constraints-immediate-reproduces-the-commit-interleave
description: SET CONSTRAINTS ALL IMMEDIATE fires a DEFERRABLE trigger inside the still-open transaction, making a deferred-fence/commit-record race deterministic in two psql sessions instead of timing-dependent
metadata:
  type: reference
---

A hazard stated as *"the interleave between a transaction's deferred-trigger execution and its commit-record write"* sounds unreproducible from a shell. It is not.

`set constraints all immediate;` fires every already-queued **deferrable** trigger **right there**, inside the still-open transaction. Any lock that trigger takes is then **held** until COMMIT. That is exactly the state "T1 is past its deferred fence but has not written its commit record," and it is a state you can park a session in indefinitely.

The two-session shape (measured at SELF-259 / `101`, 2026-09-04):

- S1: `begin;` → the write → `set constraints all immediate;` → **stop**. Fence has fired and passed; parent-row lock held; uncommitted.
- S2: `begin;` → a write on a **different row** of the same set → `commit;` → its deferred fence blocks on S1's lock.
- Poll `pg_stat_activity` for `wait_event_type='Lock'`, then send S1 its `commit;`.
- S2 unblocks, re-reads the set in a **fresh READ COMMITTED statement snapshot**, sees S1's now-committed row, and raises.

⚠ **Why the naive staggered-`pg_sleep` version proves nothing.** If S1 commits before S2's fence runs, S2's set read *already* sees the committed row — READ COMMITTED gives every statement a fresh snapshot — so the test goes red with or without the lock. The lock only matters while the first writer is *between* its fence and its commit record, and `SET CONSTRAINTS ALL IMMEDIATE` is what lets you hold it there.

**Orchestration without `sleep`** (the Bash tool blocks foreground sleep): two FIFOs, one backgrounded `psql -a -f /tmp/fifo` each, `exec 3>` / `exec 4>` to write, and `until psql -Atc '<pg_stat_activity predicate>' | grep -qx 1; do :; done` as the rendezvous. Each poll iteration costs a connection (~30ms), which is the delay.

**Always run the control leg** — `create or replace` the fence with the lock statement struck, re-run the identical script, and show the corrupt commit. See [[feedback_watcher_not_fence_for_by_construction_properties]] and the standing rule that a green leg which cannot fail is not evidence.
