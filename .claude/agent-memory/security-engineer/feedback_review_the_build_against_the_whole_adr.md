---
name: review-the-build-against-the-whole-adr
description: Grading an implementation against "the decision it implements" structurally cannot see a requirement sitting in a sibling decision of the same ADR — a multi-decision ADR can be internally unreconciled, and the gap only surfaces when it finally produces a symptom.
metadata:
  type: feedback
---

**When reviewing a build that implements Decision N of a multi-decision ADR, read EVERY decision in that ADR and
ask which ones constrain this build. "It implements D2 and D3" is a scope claim, not a coverage claim.**

**Why:** the ADR-072 migrator trigger was built under Decisions 2+3 and I ran those joint reviews. **Decision 5(1)
of the same ADR already ratified the missing requirement, called it load-bearing, and named the exact symptom:**
*"Load-bearing sequencing on a new migration: rebuild the `migrator` image → run the Scheduled Task → then deploy
the app. Applying on a stale image would push a migration set that does not include the new file."* The build
shipped without it and without a fence. Four months later three production fires applied **nothing** and reported
success honestly — a vacuous green — and that is the only reason the gap was found. **The prediction and the
incident were one sentence apart the whole time.**

**How to apply:**
- At every build review, **enumerate the ADR's decisions and mark which constrain this change.** A sibling
  decision that constrains it is in scope even if the PR does not cite it.
- **The failure class to name is "ratified, load-bearing, no implementing artifact, no fence."** When one is
  found, the finding is not just the clause — it is that nobody has asked whether OTHER clauses are in the same
  state. Ask for a clause-by-clause IMPLEMENTED / UNIMPLEMENTED / N-A walk with the artifact named for each
  "implemented"; the ones that have not yet produced a symptom are invisible by definition.
- ⚠ **Own this one when it happens.** It is a review-method defect, not an authoring defect — the ADR said the
  right thing. Saying so is what stops the team hardening the wrong process.
- Related: [[a-described-control-is-not-a-built-one]] (prose vs artifact within one PR) — this is the same
  defect across a four-month gap, and [[assertion-with-no-watcher]].
