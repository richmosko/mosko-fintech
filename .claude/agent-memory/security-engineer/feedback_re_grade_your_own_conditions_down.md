---
name: re-grade-your-own-conditions-down
description: When a later measurement narrows a condition you already issued, downgrade it explicitly in the same voice you raised it — and grade a new surface by what the CALLER CAN CHOOSE, not by what the path can do.
metadata:
  type: feedback
---

**A condition I issued is a claim, and new measurement can falsify its RATIONALE while leaving the condition
sensible. Say which happened. Keeping a condition at its original severity to look consistent is the failure.**

**Why:** I made the 40-hex validation of `MIGRATOR_EXPECT_SHA` **blocking**, arguing the value was
attacker-controlled text reaching a log line an operator reads. A later read measured `workflow_dispatch: {}`
with **no inputs** and the value sourced from `$GITHUB_SHA` — always 40 hex, never caller-supplied. **The
condition still earns its keep as defence-in-depth against a future input; the log-forgery ARGUMENT was wrong
about the current path.** In the same read, my fail-open finding survived but **its exposure moved**: the skip is
unreachable from the workflow (the variable is always set there) and reachable only from the **manual**
`ssh … fire` — the path most likely to be run in an emergency and least likely to be read carefully. **A
narrowed finding aimed at the right path is worth more than a broad one aimed at the wrong path.**

**How to apply:**
- **Grade a new surface by what the CALLER CAN CHOOSE, not by what the path CAN DO.** "Anyone can fire production
  on demand" sounded severe; measured, the caller chooses only a **ref**, the image holds only **merged** code, a
  wrong ref **fails closed on the sha mismatch**, and the verb is idempotent. The residual was one missing
  **approval gate**, not a capability — so the fix is an Environment with a required reviewer, not a veto.
- **Distinguish "the capability is wrong" from "the gate in front of it is missing."** Most widenings are the
  second, and saying so gets a cheap native fix instead of an argument.
- ⚠ **Gate a widening BEFORE the pending change that makes it dangerous.** Here a TODO rebuild-from-ref step
  would later let a dispatcher choose which ref is built and applied. Adding the approval afterwards leaves a
  window; adding it now costs one key.
- ⛔ **Refuse "build a safer probe path instead."** A probe that is not the real path proves nothing about the
  real path — see [[applied-vs-demonstrated-discharge]] and the vacuous-green fires that "proved transport"
  while delivering nothing.
