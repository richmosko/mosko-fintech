---
name: pg-prove-scope-full-tests-tree-not-rls-only
description: When "run the full suite" means the merge-gate green run, point pg_prove at /tests, not /tests/rls — the RLS-only scope silently excludes 00_rls_inversion_self_test.sql, the harness's own teeth check, and two other non-RLS files.
metadata:
  type: feedback
---

Ran a "full suite" pass against `qa_scratch_084` scoped to `/tests/rls/` (Files=74).
Architect's own run scoped to `/tests/` came back Files=77 — the 3 missing files:
`supabase/tests/sd15_fn_mask_acct_number.sql`, `supabase/tests/01_session_timezone.sql`,
and **`supabase/tests/00_rls_inversion_self_test.sql`**.

**Why the missing one matters specifically:** `00_rls_inversion_self_test.sql` is the
harness's own teeth check — the file that proves pg_prove can go RED at all. A "full
suite green" run whose purpose is "prove the batteries are green" is the textbook
vacuous-green shape (DESIGN.md's own warning) when it silently excludes the one file
that verifies the green is meaningful. No harm this time (Architect's own tree-wide run
caught it and all three passed), but the gap was structural, not a one-off typo.

**How to apply:** when asked for "the full suite" / "one green run" as a merge-gate
check, point pg_prove at `/tests` (the whole directory), not `/tests/rls`. The RLS
subdirectory is the natural scope for a per-file battery fix-and-verify loop, but it is
the WRONG scope for the final combined run that stands in for CI's gate.

Related: [[feedback_scratch_db_pgtap_harness_gotchas]] — same harness, another
scope-boundary lesson. Also: a leftover `qa_scratch_084` on the cluster after a
"reverted" round is the same failure shape as this — state that should have been torn
down but wasn't, discovered by someone else's re-run rather than my own close-out
check. Always actually `drop database` the scratch before reporting a round closed,
not just revert the worktree.

⚠ **RECURRED, 085/element PR (2026-08-19):** ran multiple "full suite" verification
passes scoped to `-r /tests/rls` (75 files) throughout the element-PR battery work,
reported "75 files, 1666 tests, everything green" as if it were the complete gate —
Architect caught it again, same three missing files, same reasoning. Having the memory
written down did not prevent the repeat: I never re-consulted it at the point of typing
the `docker run ... pg_prove ... -r /tests/rls` command, because the command "looked
right" from the previous session's own habit of scoping to `rls/` during iteration and
I never re-elevated to the full-tree scope for what I was calling my "final" run. **The
concrete fix, not just the reminder: when a run is being reported as THE verification
(not a per-file iterate-and-fix loop), the pg_prove invocation's `-r` argument must
literally read `/tests`, and that string should be typed from this memory file, not
recalled.** Independently re-ran the full `/tests` scope after Architect's correction
and confirmed `00_rls_inversion_self_test.sql` passes (2/2) — the harness was honest
this whole time, but I had no direct evidence of that until the rescoped run.
