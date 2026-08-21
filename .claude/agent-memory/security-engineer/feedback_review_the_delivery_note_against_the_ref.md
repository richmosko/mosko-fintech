---
name: review-the-delivery-note-against-the-ref
description: A teammate's temp/ delivery note is a claim about WHICH TREE was measured — diff it against the reviewed ref; a v2 sitting uncommitted means the green run named a tree that is not the one being merged
metadata:
  type: feedback
---

At a merge-gate review, read the executing agent's `temp/` delivery note **and diff its artifacts
against the ref under review**. The note's test counts and "all green" claims are a claim about the
tree the author measured, which is not necessarily the tree being merged.

**Why:** on the ELEMENT PR (`feature/gl-element-column` @ `527a89c`) the branch carried QA's **v1**
of two battery files while `temp/qa-element-battery-delivery.md` was headed *"v2 — supersedes the
first delivery"* and reported its green run as a test count that only exists with v2's extra leg
present. The brief described the committed content accurately, so reviewing only the ref would have
reported clean and missed it entirely. Related: [[feedback_read_the_branch_from_the_ref_not_the_worktree]]
and [[feedback_temp_handoff_path_is_per_worktree]] — `temp/` is gitignored, so an undelivered v2
does not survive session close and must be disposed explicitly, never left "for later".

**How to apply:** when a PR pairs a migration with a battery, `diff` the branch file against the
same-named file in `temp/` before writing the verdict. Then **bound the gap rather than just
reporting it** — if the delta is purely additive, say so, because that is what lets the author's
green run transfer to the committed legs and keeps the finding a FLAG instead of a RED. Offer the
disposition as land-v2 / declare-v1-ratified / merge-and-lose-it, and name the third option's cost
out loud so it is a decision rather than an evaporation.

**Second lesson from the same review:** a pgTAP `plan N ran M` diagnostic on a file ending in
rolled-back `corrupt-the-control` legs is **not** "each rolled-back leg loses a count." `ok()`
writes `curr_test` as an ABSOLUTE value in an ordinary table, so a later leg's write simply
re-occupies the position a rolled-back predecessor lost. **Drift = the number of CONSECUTIVE
TRAILING rolled-back legs** — the ones with no subsequent `_set` to overwrite them. One tail leg ⇒
drift 1. I predicted N-2 from a sum model and was wrong; see
[[a-red-whose-message-names-the-wrong-defect]] — a header predicting the wrong number on the exact
diagnostic a reader uses to detect a missing leg will get that diagnostic dismissed.

⚠ **I first wrote that rule as "drift is ALWAYS 1, never the number of savepoints," and that
absolute is WRONG.** SELF-244's close-gate ends in **three consecutive** savepoint-wrapped legs and
drifts by **3** — each one's `_set` is undone by its own rollback before the next leg's `_set` runs.
Both files are consistent with the same mechanism; my generalization was fitted to a sample of one.
**Had I trusted it, I would have rejected a correct explanation as arithmetically impossible.** The
correction is the reusable half: *"always 1"* was a claim about the shape of the file I happened to
be reading, stated as a claim about the mechanism.

**The free discriminator, and it settles the question static analysis usually cannot.** "Bookkeeping
noise" and "three legs never ran" produce the identical `planned N but ran M` line — but `finish()`
sits AFTER those legs, and it **cannot emit anything unless execution reached it in a non-aborted
transaction.** So the diagnostic's own existence proves the legs executed; and `throws_like` /
`lives_ok` / `ok` each emit exactly one TAP result unconditionally, pass or fail. **The residual is
then NUMBERING, not execution** — if the printed `ok N` came from `curr_test` rather than a
rollback-exempt sequence, the tail legs would print duplicate numbers. Only the stream settles that,
and the cheapest decisive artifact is three values: `grep -c '^ok [0-9]'`, `grep -c '^not ok'`, and
**pg_prove's exit code** — which fails on both a count mismatch and duplicate test numbers, where a
bare `psql` exits 0 regardless. Ask for the exit code, not for a narrative.

**Companion static check that has to come first:** count the assertion call sites yourself and
compare to `plan(N)`. ⚠ Use the COMPLETE verb set — mine omitted `throws_like` and `set_eq` and came
up five short, which would have manufactured a finding. Include helper verbs from the shared
fixture, and read each helper's body to see how many TAP results it emits (one `select is(...)` = 1).
