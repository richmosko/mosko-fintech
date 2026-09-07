---
name: strike-the-real-guard-before-trusting-a-mechanism-claim
description: A directive to restructure 115's savepoint-wrapped pgTAP legs (reasoned from pgTAP's internal results-table mechanics) was withdrawn after I struck the REAL guard in the REAL migration on a scratch clone and ran the UNMODIFIED battery through pg_prove — it caught the strike cleanly. SELF-355/115, 2026-09-06.
metadata:
  type: feedback
---

Team-lead directed a restructure of `115`'s four trailing savepoint-wrapped legs (14h-i..iv),
reasoning from pgTAP's internal results-table mechanics that `ROLLBACK TO SAVEPOINT` discards
a recorded result along with the fixture, so those legs "cannot fail by construction." Before
executing a non-trivial rewrite of committed-clean battery code on that premise, I ran the
gold-standard check instead: struck the REAL guard in the REAL `fn_finalize_monthly_report`
(115 migration L540-544) on a scratch clone via `create or replace function` with the guard's
`if` condition forced to `if false`, then ran the UNMODIFIED, already-committed
`115_fn_finalize_monthly_report_rls.sql` through the real consumer (`pg_prove`, not `psql`).
Result: `Failed test 50/51`, `no exception thrown`, `Result: FAIL` — the savepoint-wrapped legs
caught the strike cleanly, by name.

I also isolated the mechanism with three smaller repros (a bare `ok(false,...)` in a savepoint;
a `throws_like` failure mid-sequence of four trailing savepoints; a `throws_like` failure at
the VERY LAST savepoint position, matching 14h-iv's exact structural position) — all three
showed correct `Result: FAIL` with the right test number.

**Why the directive's mechanism claim was wrong:** an `ok()`/`throws_like()` call's TAP line
is the STATEMENT'S OWN RETURN VALUE — psql prints it the instant the `select` completes,
which is BEFORE the following `rollback to savepoint` runs. A rollback can't un-print already-
transmitted client output, and `pg_prove`'s TAP parser reads that raw stdout stream directly,
so pass/fail detection survives the rollback intact. What DOES roll back is a SEPARATE,
purely-cosmetic internal bookkeeping table pgTAP's `finish()` reads for its own self-check
comment ("Looks like you planned N tests but ran M") — that line has zero effect on `Result:`
or the `Failed tests:` list. [[feedback_pg_prove_aggregate_run_tap_artifact_unconfirmed]] already
had half of this (the drift-count arithmetic); this closes the other half (whether detection
itself survives) with a direct strike, not an inference.

**How to apply:** when a directive (mine, a teammate's, or my own hypothesis) claims a
mechanism about whether an assertion CAN or CANNOT catch a real regression, and the claim is
reasoned from how the tool is BELIEVED to work rather than from watching it fail on a real
strike — strike the real thing before accepting or executing on the claim, especially before
a non-trivial rewrite of already-green, already-reviewed test code. This is the same
verification-effort-vs-cost tradeoff [[feedback_verify_causal_mechanism_before_stating]] and
[[feedback_inversion_test_the_rationale_not_the_presence]] already cover, but the new instance
here is specifically: a plausible INTERNAL-MECHANICS argument about a testing framework is not
the same claim as an EFFECT measured against the real consumer, and the two can point opposite
directions. Team-lead withdrew the directive on this evidence and corrected their own
session-level memory note; the right move when this happens is to hold the change, present the
counter-evidence plainly (with the exact repro), and let the directive-issuer withdraw or
override — not to silently comply with a costly rewrite, and not to silently ignore the
directive either.
