---
name: a-gate-on-a-status-already-ruled-unreliable
description: When a fix proposes gating on a signal an earlier decision already ruled untrustworthy, the gate does not make the signal reliable — it puts a green light in front of the defect. Assert the OUTCOME the gate is a proxy for.
metadata:
  type: feedback
---

**Before accepting "add a poll/gate in front of X", ask whether the project has ALREADY ruled that signal
unreliable — and if it has, the gate inherits the unreliability plus a green light.**

**Why:** ADR-072 Decision 3 rules fail-closed lives in the Scheduled Task's own exit status and **never** in
Coolify's deployment status, because Coolify marks a deployment FINISHED *before* its post-deploy command and
swallows that command's failure. After a stale-image incident, the proposed fix was to add a **deployment-status
poll in FRONT** of the task poll. **That polls the very status Decision 3 ruled untrustworthy:** if it reports
FINISHED while the new image is not serving, the task runs against old content and reports success — the same
incident, now with a gate that blessed it.

**How to apply:**
- **Assert the OUTCOME, not the STATUS.** Name the property the gate is a proxy for and check that directly.
  Here: *"the container about to run carries the migration set from the merged sha"* — bake the triggering sha
  into the image (`LABEL` or a marker file) and have the caller compare. Directly observable, fails closed, and
  it would have caught every prior occurrence.
- **A precondition and a success criterion are different roles, and the distinction drifts.** If a status poll
  is kept as a precondition, its success must never be read as evidence the work succeeded — and that must be
  written **in the same sentence that adds the poll**, because the next reader sees two polls and simplifies to
  one.
- ⚠ **Check whether the thing you need to observe is observable at all before requiring it.** Here the Dockerfile
  carried no label, build-arg or marker for the migration set — the assertion had to be *created*, not merely
  wired. A requirement to "verify X" is not actionable until something emits X.
- Related: [[which-lane-does-the-watcher-observe]], [[a-check-chained-to-its-action-is-decoration]].

**And the companion lesson about my own alarm:** I had pre-positioned that a guard raising while the fire
reported SUCCEEDED *"means the chain is broken."* It did not — the guard never ran, because the image predated
the content. **A symptom consistent with a mechanism failure is not evidence of one.** State the alternative
explanations when pre-positioning, or the team spends its measurement budget on the hypothesis you named.
