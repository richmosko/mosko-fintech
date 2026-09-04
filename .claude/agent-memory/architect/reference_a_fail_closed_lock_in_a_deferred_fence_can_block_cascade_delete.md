---
name: fail-closed-lock-in-a-deferred-fence-can-block-cascade-delete
description: Adding "lock the parent row, RAISE if it does not resolve" to a deferred child fence makes deleting the parent impossible, because ON DELETE CASCADE has already removed the parent by the time the fence fires at COMMIT
metadata:
  type: reference
---

A deferred `CONSTRAINT TRIGGER` on a child table that is asked to **lock its parent row first and refuse if the parent does not resolve** will, written naively, make **deleting the parent impossible**.

**Why.** `on delete cascade` removes the child rows when the parent goes. The fence is `DEFERRABLE INITIALLY DEFERRED`, so it fires at **COMMIT** — by which point the parent row is already gone in this transaction's own view. `select … from parent where id = <old.parent_id> for update` returns **zero rows**, and a fail-closed RAISE there rejects a perfectly legal DELETE.

**The fix is statement ORDER, not a carve-out.** Take the lock first (it must precede the set read, or the serialization is worthless), but judge the *empty set* before judging the *empty lock*:

1. lock the parent `for update`, into a local — do not test it yet
2. read the child set
3. `if v_row_count = 0 then return null;` ← this return carries the cascade-delete path
4. only then: set non-empty **and** parent did not resolve → RAISE

That transaction is still serialized: its own `DELETE` on the parent holds an exclusive lock on the very row step 1 tried to take.

**What step 4 is actually for.** Under RLS it is unreachable while the matched-tenant fence holds — a visible child row implies a matched-tenant, therefore visible, parent. So it is not a fence against a caller; it is the **observer for the matched-tenant fence's absence**, converting "the set read silently narrows" into a loud failure. Say that in the comment, or the next reader reads it as a live guarantee. Cf. [[feedback_watcher_not_fence_for_by_construction_properties]].

**Measured at SELF-259 / `101`, 2026-09-04.** Sec's F-1 asked only for "lock first, RAISE on zero rows"; taken literally it would have shipped a schedule that could never be deleted. The regression check that caught it — delete a fully-populated parent and assert the DELETE succeeds — costs one line and is not implied by any fence-leg test.
