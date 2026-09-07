---
name: reference-pg-visible-in-snapshot-poisoning-dblink-and-trigger-exceptions
description: pg_visible_in_snapshot(row.xmin, pg_current_snapshot()) is UNSOUND for "written in this transaction" — RULED by Sec 2026-09-05, FIXED via pg_xact_status at 72c3e5c (111) and re-aimed on 113. Two vectors I measured (dblink, a caught trigger exception) were the SAME real defect, not separate limitations. Load before authoring any same-transaction visibility leg.
metadata:
  type: reference
---

⚠⚠ **RESOLVED 2026-09-06.** The fix landed and is verified: `pfin.fn_emit_audit_log`
(111) now uses `pg_xact_status(r.xmin::text::xid8) = 'in progress'`, resolved in ONE
statement together with `users_id` (72c3e5c; QA sha 57f3952, 34/34 green, inversion-strike
confirmed the required counter-advance leg has teeth). 113's own message wording was
re-aimed to name the current primitive (30be987 / later 355-db-qa shas). This file's "How
to apply" section below is kept for the NEXT time this class of bug shows up somewhere
else in the codebase — item 4's "should be treated as suspect" now reads as CLOSED for
111/113 specifically, still standing as a general caution for any other same-transaction
visibility check.

⚠⚠ **CORRECTED 2026-09-05 (Sec ruling, relayed by team-lead) — READ THIS FIRST.** What
this file originally called "two independent harness-poisoning findings" is ONE real,
general defect in C2's predicate itself, not a dblink/throws_like-specific test artifact.
Sec's mechanism: a transaction's own xid is NEVER listed in its own snapshot's `xip`
(in-progress) array — Postgres doesn't special-case "is this me" inside
`pg_visible_in_snapshot`, only inside real MVCC visibility checks, which this function
does not use. Snapshot `xmax` is effectively `latestCompletedXid + 1`, cluster-wide, not
transaction-local. So the SECOND any xid — belonging to ANYONE, not just this session —
completes (commits OR aborts) after our row's xid was consumed and before we check
visibility, `xmax` advances past our row's xid, and since our row's xid is not in `xip`,
`pg_visible_in_snapshot` misreports it as "already committed" (visible) rather than "still
running" (ours). This is real on a NON-IDLE production database: an aborted writing
subtransaction (the exact shape below), a genuinely different session's ordinary COMMIT,
or a dblink'd commit ALL trigger it identically. **The two "findings" below are two
vectors into this one bug, not two separate quirks.**

--- Original entry, mechanism-accurate, diagnosis-corrected by the box above ---

Any `fn_emit_audit_log`-shaped C2 mechanism (Sec's PR #636, 111_audit_log.sql) checks
"was this row written in THIS transaction" via `pg_visible_in_snapshot(row.xmin::text::xid8,
pg_current_snapshot())`, not `xmin = pg_current_xact_id()` — the latter is required because
a real INSERT wrapped in `begin ... exception when unique_violation ... end` (a
subtransaction, e.g. `fn_open_monthly_report_draft`, 113) gets a SUBTRANSACTION xid, not the
top-level one, on EVERY successful call, not just a colliding one.

**Finding 1 — dblink.** Opening a dblink connection to the SAME database mid-transaction,
even fully closed/disconnected afterward, corrupts `pg_current_snapshot()` for the REST of
that transaction: before, it reports `xmin:xmin:` (empty range); after, `xmin:xmin+N:` with
an EMPTY `xip_list` — any xid in that gap, INCLUDING the calling transaction's own, misreads
as already-committed/visible. Measured directly, reproduced minimally.

**Finding 2 — a caught trigger exception, independent of dblink.** A `throws_like()`-wrapped
statement that reaches a real `BEFORE UPDATE`/`DELETE` trigger which RAISEs (exactly what an
immutability-trigger leg needs to prove the trigger fires) leaves the SAME transaction unable
to correctly attest a LATER plain top-level write as "written here" — `pg_visible_in_snapshot`
reads it as already-visible/committed even though it is a bare top-level INSERT with no
savepoint of its own. Minimal 13-line repro (a scratch table + a raising BEFORE trigger + one
`throws_like('update ...')` + a later bare INSERT + a `pg_visible_in_snapshot` check).
CONFIRMED NOT the cause: `throws_like` alone with no real trigger-write (25-iteration burst);
a bare `savepoint`/real-write/`rollback to savepoint` cycle alone or repeated 8x in the exact
shape of a rollback-absence leg; GRANT/REVOKE DDL alone. Bisect by truncating the real file at
successive leg boundaries (`head -n <line>` + append a diagnostic
`pg_current_xact_id()`/`pg_current_snapshot()`/`pg_visible_in_snapshot` block + `rollback;`) —
narrows fast, don't try to guess a synthetic minimal repro first.

**How to apply, if this class of bug shows up somewhere else:**
1. Do NOT try to reorder legs to dodge it — that was only ever a mitigation while the
   predicate was believed sound with a harness-specific gap. Fix the predicate.
2. When you need to prove a row was written via a SUBTRANSACTION specifically (not just that
   an emit succeeded), don't reuse the product's own visibility mechanism to verify itself —
   use a plain xid8 inequality instead: `row.xmin::text::xid8 <> pg_current_xact_id()`. See
   113's (4c) leg — this stays correct regardless of what any C2-style expression becomes.
3. **REQUIRED leg for ANY same-transaction-visibility mechanism, whatever expression it uses
   (Sec's own words, verbatim shape):** advance the cluster's completed-xid counter BETWEEN
   the write and the check, and assert the check still succeeds. The faithful proxy is an
   ABORTED WRITING subtransaction (savepoint; a real write; `rollback to savepoint`) run
   AFTER the row you'll check but BEFORE you check it. Pair it with a MATCHED NEGATIVE
   CONTROL: the same shape with NO write inside the aborted subtransaction (confirmed in
   isolation: burns no xid, does not move the snapshot gap). Without this T1(write)/T2(no-write)
   pair, a new expression is validated only on an IDLE database, exactly the gap that let the
   original one ship broken. See 111's leg 7d.
4. `pg_xact_status(xid) = 'in progress'` is the FIX, but it is ALSO true for another
   session's own in-progress transaction — what discriminates is that the subject row's
   tenant AND its transaction status must be resolved in ONE statement, by THIS
   transaction's own MVCC read (see 111's leg 7g, the structural one-statement-invariant
   pin, and the standing comment-stripped/case-insensitive `prosrc` rule it established).

Related: [[feedback_scratch_db_pgtap_harness_gotchas]] · [[feedback_postgres_roles_are_cluster_level_not_per_db]]
