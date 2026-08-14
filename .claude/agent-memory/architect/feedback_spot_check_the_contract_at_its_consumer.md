---
name: spot-check-the-contract-at-its-consumer
description: Authoring a contract is not the same as watching it land — spot-check the consumer when an architecture-owned contract has one; and a predicate sound in isolation can be unsound as a stand-in for a broader question
metadata:
  type: feedback
---

**When an Architect-owned contract has a single consumer, read that consumer.** Designing
the contract to make a failure impossible does not make it impossible — it only moves
where the failure can occur.

**Why:** SELF-220, 2026-08-13. `069 fn_first_cron_checkpoint` returns three fields
**specifically because** collapsing them was the predictable failure: the imported-only
state (`NULL / false / true`) must not be confused with an empty store. I said so in the
DDL, in the handoff, and directly to the consumer, who confirmed the intent back to me
correctly.

**It was collapsed anyway** — one layer down, in a file I had no reason to open. The
chart rendered the entire imported series as stale, which is the exact defect the
ratified suppress-and-disclose disposition exists to prevent. Found by a five-minute
spot-check *after* the component had merged into the branch and the branch was frozen
for Sec review.

> **Authoring the contract is not the same as watching it land.**

## The defect class — worth more than the instance

The consumer had a correct narrow predicate, `isPreBoundaryPoint(p) = boundary !== null
&& p < boundary`, and used it as a stand-in for a broader question ("is this point in the
imported era"). The two **coincide in the common state and diverge exactly where the
boundary is NULL** — the state the three-field return existed to expose.

> **A predicate sound in isolation can be unsound as a stand-in for a broader question.**
> Its own answer was never wrong; what was wrong was what the call sites assumed it meant.

**The repair that worked — and generalises:** *name the broader question as its own
function* (`isImportedEraPoint = !has_cron_rows || isPreBoundaryPoint(...)`) and point
the call sites at it. **Do not widen the narrow predicate** — it has honest callers, and
widening it would make every one of them wrong in a new way.

## The test-selection principle

The consumer's suite was mixed-state-only and **structurally blind** to this: the mixed
state is precisely where the narrow and broad predicates agree.

> **The states that matter are the ones where two plausible implementations DIVERGE** —
> a test-selection principle, not a coverage-percentage one.

⚠ And the catching test must assert on **rendered output**, not on the helper's return: a
unit test of the helper passed throughout, because the helper was correct.

**How to apply:**
- Spot-check the consumer whenever a contract you authored ships against exactly one
  caller. Look for **which field the consumer branches on** — if it reads fewer fields
  than the contract returns, that is the collapse.
- ⚠ **A neighbouring function handling all states correctly makes the file look
  conformant on a skim.** Here `resolutionDisclosureFires` was right, which is part of
  why the gap survived.
- Report the property the fix must satisfy; do not patch a consumer's file.

Related: [[structural-fence-must-cover-the-same-class]] · [[watcher-not-fence-for-by-construction-properties]]
