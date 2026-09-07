---
name: same-transaction-predicate-must-not-use-a-cluster-wide-counter
description: A "was this row written in MY transaction" test must not depend on latestCompletedXid or snapshot xmax; pg_visible_in_snapshot fails non-deterministically under concurrency, pg_xact_status is the primitive that expresses the property.
metadata:
  type: feedback
---

When binding an audit/annotation write to a subject row written **in the same
transaction**, the predicate must not depend on any **cluster-wide counter**.
Two candidate shapes fail in opposite directions:

- `xmin = pg_current_xact_id()` — **blind to subtransactions.** A plpgsql
  `begin … exception …` block opens a subtransaction with its own xid, so a row
  written inside one has `xmin` = the SUBxid while `pg_current_xact_id_if_assigned()`
  returns the TOP-level xid. Refuses the real path; passes every test whose INSERT
  is not wrapped in a handler.
- `not pg_visible_in_snapshot(xmin::xid8, pg_current_snapshot())` — **sensitive to
  unrelated transactions.** Our own xid is NEVER in our own snapshot's `xip`, so the
  moment `latestCompletedXid` advances past it, `xmax` rises above our xid and our
  own write reads as "visible" = "not written here."

**`pg_xact_status(xmin::text::xid8) = 'in progress'` is correct** because it tests
`TransactionIdIsCurrentTransactionId` first, which is true for the current
transaction **and all of its subtransactions** — literally the property wanted.

**Why:** SELF-345 / `111_audit_log.sql` (2026-09-05). Measured matrix, both forms:

| case | pg_xact_status | pg_visible_in_snapshot form |
|---|---|---|
| plain top-level write | in progress ✓ | true ✓ |
| write in sub-block exiting NORMALLY (sub-commit) | in progress ✓ | true ✓ |
| explicit SAVEPOINT/RELEASE; nested RELEASE | in progress ✓ | true ✓ |
| row re-read after ANY aborted **writing** subxact | in progress ✓ | **false ✗** |
| write AFTER a prior aborted writing subxact | in progress ✓ | **false ✗** |
| earlier committed txn | committed ✓ | false ✓ |
| FrozenTransactionId | committed ✓ | — |

⚠ The discriminator for the poisoning is **whether the aborted subxact consumed an
xid** — a non-writing abort leaves the snapshot untouched, which is why it looks
intermittent. And `latestCompletedXid` is CLUSTER-WIDE: **any** concurrent commit
does the same, so the defect is a non-deterministic rollback of the whole
transaction on a busy database. Every battery passed because a scratch DB is idle.

**How to apply:**
- Soundness rests on an **unstated statement-level invariant**: `'in progress'` is
  also true of another session's transaction. What excludes it is that the row was
  resolved by **this transaction's own MVCC read, in the same statement**. Splitting,
  caching, or passing the row in breaks the coupling **silently**. That invariant
  needs a structural watcher — no behavioural leg can see it, because splitting the
  read is correct on an idle DB.
- Required leg whatever the expression: advance `latestCompletedXid` **between the
  write and the emit** and assert the emit still succeeds. An **aborted writing
  subtransaction is a faithful proxy** (no second connection, no dblink), with a
  **non-writing abort as the matched control** — the pair identifies the cause as
  xid consumption rather than as exceptions.
- Clog retention: `pg_xact_status` raises beyond it, which aborts — but only on the
  **refusal** side, never the accept side, since a just-written xid cannot be that
  old. Frozen xmin reads `committed` cleanly.

Related: [[feedback_execute_acl_stakes_invert_on_definer]] ·
[[feedback_a_definer_grant_hands_back_the_channel]]
