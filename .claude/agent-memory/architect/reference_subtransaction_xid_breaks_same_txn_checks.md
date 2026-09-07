---
name: subtransaction-xid-breaks-same-txn-checks
description: Testing "was this row written by MY transaction" — xmin equality breaks on subtransactions, pg_visible_in_snapshot breaks on ANY aborted subtransaction; use pg_xact_status.
metadata:
  type: reference
---

To assert *"this row was written by the current transaction"*, the obvious expression
is wrong:

```sql
-- ✗ WRONG
xmin = pg_current_xact_id_if_assigned()::xid
```

**Why:** a plpgsql `begin … exception when … end` block opens a **subtransaction**,
which gets its **own xid**. `pg_current_xact_id_if_assigned()` returns the
**top-level** xid. Measured on PG 17, 2026-09-05: top `1664121`, row `xmin`
`1664122`, equality **FALSE** — for a row the transaction genuinely inserted.

```sql
-- ✗ ALSO WRONG — poisoned by ANY aborted subtransaction earlier in the transaction
not pg_visible_in_snapshot(xmin::text::xid8, pg_current_snapshot())
```

**This was my first fix and it is also wrong — and I diagnosed it wrongly twice.**
I called the cause "aborted subtransactions"; that is the *symptom*.

**The real cause: it depends on `latestCompletedXid`, which is CLUSTER-WIDE.** Our own
xid is never in our own snapshot's `xip`, so as soon as `xmax` rises past our xid, our
own write reads as visible and the attestation flips FALSE. **An ordinary COMMIT FROM A
SECOND SESSION between the write and the check is enough — no exception, no trigger, no
dblink.** An aborted subtransaction of our own reaches it only when it **consumed an
xid** (a *writing* subxact takes one and aborting completes it; a **non-writing** abort
leaves the snapshot untouched). **That matched pair is the discriminator, and it is what
proves the diagnosis** — Sec found it, I did not.

⚠ **Why it survived review: the failure is NON-DETERMINISTIC, and a scratch DB is
idle.** Every battery passed. And because the check sat inside the writing transaction,
a refusal rolled back **the whole operation**, not just the audited row.

```sql
-- ✓ CORRECT — reads the commit log directly; immune to both failures
pg_xact_status(xmin::text::xid8) = 'in progress'
```

Measured across **seven** cases: own top-level, own subtransaction, own write with a
caught exception before it, with a caught trigger exception after it, with a caught
`unique_violation` after it → all `'in progress'` ✓; earlier committed transaction, and
earlier committed transaction read after a caught exception → `'committed'` ✓ (refused).

**Two properties worth knowing, both measured, not assumed:** `pg_xact_status` has **no
ACL entry**, so EXECUTE is PUBLIC — it works from an ordinary role and does **not**
depend on a `SECURITY DEFINER` posture. And a **frozen `xmin` reads `'committed'`
cleanly** (tested on FrozenTransactionId), so an ancient row is refused rather than
erroring; only beyond clog retention does it raise, which aborts — fail-closed.

**⚠⚠ THE REUSABLE HALF — the disqualifier, which outlives every candidate:** an
expression answering *"did MY transaction write this row"* **must not depend on
`latestCompletedXid`, on snapshot `xmax`, or on any other cluster-wide counter.** The
two wrong shapes fail in **opposite** directions — xid equality is blind to
subtransactions, visibility is sensitive to unrelated transactions — and only the
second is non-deterministic.

**The leg that makes any candidate falsifiable** (require it, whatever expression
lands): advance `latestCompletedXid` between the write and the check and assert the
check still passes. **An aborted WRITING subtransaction is a faithful proxy** — no
second connection needed — with a **non-writing abort as its matched negative
control**. Stronger form if the harness allows: a real second session committing.

**How to apply:**
- ⚠ **This defect is invisible to an ordinary battery.** A leg whose INSERT is *not*
  wrapped in an exception block passes against the wrong implementation while the
  real product path is refused. **Require the success leg to route through the actual
  function**, not a bare INSERT. (`113`'s INSERT is inside a `unique_violation`
  handler — that is the shape that bit.)
- Also reject the ordered form `xmin::text::xid8 >= pg_current_xact_id_if_assigned()`:
  it *accepts* a row committed by a **concurrent** transaction holding a higher xid.
- ⚠ **A rule written into a comment is the weak form of this fix.** The constraint that
  would have documented the snapshot form's hazard — *"do not catch an exception
  between the write and the emit"* — was **both unenforced and FALSE**, since the
  poisoning also happens when the catch precedes the write. When a landmine can be
  removed by changing the expression, remove it; do not document it.
- Keep `pg_current_xact_id_if_assigned() IS NULL` as a **separate** fail-closed
  check — NULL means the transaction wrote nothing, so there is no privileged write
  for an audit row to annotate.
- ⚠ **Bounded assumption to state, not hide:** `xid::text::xid8` reconstructs the
  64-bit id with **no epoch**, so the comparison is sound only within one xid epoch.
  Postgres exposes no epoch-preserving `xid → xid8` conversion.

Related: [[a-definer-helper-taking-a-classification-parameter-is-a-forgery-channel]],
[[create-or-replace-resets-volatility]].
