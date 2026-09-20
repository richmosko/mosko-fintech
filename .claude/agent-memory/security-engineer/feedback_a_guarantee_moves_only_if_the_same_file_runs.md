---
name: a-guarantee-moves-only-if-the-same-file-runs
description: When a fail-closed guard is degraded to a notice-and-skip because "the guarantee moves to another invocation of the same file," check that the OTHER LANE actually runs that file — otherwise the migration applies, records a ledger row, reports success and does nothing forever.
metadata:
  type: feedback
---

**A guard may degrade to skip ONLY for a file the other lane is GUARANTEED to run. Demand the file list.**
The argument "the guarantee moves to a different *invocation of the same file*, not to a different artifact" is
sound — and it is sound **per file**. Applied to a set, it silently covers files the other lane never touches.

**Why:** Amendment 5 proposed degrading `comment on role`'s guard to `raise notice` + skip across `118` **and**
`119`. For `118` it holds: the supervised pre-step runs `118`'s file. `119` is not in the pre-step's list, so
its guard would skip its **only** effect — the migration applies, writes a `schema_migrations` row, **reports
success and does nothing, forever** — and `119` was the watched first-fire vehicle, so the fire would have
proved transport over a no-op. Its pgTAP battery could not catch it: the battery runs in CI, where the applier
is superuser and the comment lands. **The watcher was in the wrong lane.**

**How to apply:**
- Read the guard **as authored** before agreeing to degrade it. `119`'s existing guard `raise exception`s 42501
  with a hint naming the supervised pass — a control that halts by construction. **Never demote a control to
  make a procedure true**; move the file to the lane that can run it instead.
- Ask **what this file's only effect is.** A file whose entire payload is guarded becomes a success-reporting
  no-op, which is worse than a failure — see [[applied-vs-demonstrated-discharge]] and
  [[probe-that-only-asserts-failure-goes-vacuous]].
- If any skip ships, it is `RAISE WARNING`, never `notice` — and check the same document is not simultaneously
  ruling a sibling silent-`notice` branch **blocking**, which is the inconsistency tell.
- Ask **which lane the watcher observes.** A CI battery run under a superuser applier cannot see a production
  skip. Related: [[a-red-whose-message-names-the-wrong-defect]].
