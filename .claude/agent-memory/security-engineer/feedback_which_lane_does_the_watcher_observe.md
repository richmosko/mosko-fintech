---
name: which-lane-does-the-watcher-observe
description: A pgTAP leg runs against a CI-built database and cannot see production; an operator runbook step is not mechanical. Ask which LANE a proposed watcher observes before accepting it as the control.
metadata:
  type: feedback
---

**Before accepting any watcher, ask: which lane does it observe — CI, the production box, or a human?**
Three times in one workstream a control was placed in a lane that structurally cannot see the thing it watches:
- `119`'s pgTAP battery asserts a `comment on role` that **lands in CI because CI applies as superuser**, while
  the production lane skips it — green forever, divergent forever.
- The D9 co-ownership check was specified as a post-bootstrap assertion but proposed as a CI leg.
- `(iv‴)`'s decrypt-view existence check was moved from an in-migration raise to "runbook verify + standing
  pgTAP leg" — **the runbook step is a human, and the pgTAP leg is CI. Neither observes the production box.**

**Why it keeps happening:** a pgTAP leg *feels* mechanical and durable, so it reads as the strongest available
watcher. Its lane is the invisible part. And a runbook "verify" line reads like an assertion when it is an
instruction to a person who may be tired, mid-incident, or skipping ahead.

**How to apply:**
- **The production-observable slot is usually the provisioning/post-step script itself.** A `do $$ … raise
  exception … $$` appended to the same supervised session is mechanical, runs on the real database, and fires at
  the only moment the property can be wrong. Ask for that first; it is normally one block, not a redesign.
- Then assign the others their real, smaller jobs and **say so explicitly so they are not counted twice**: the
  runbook line is a human double-check; the pgTAP leg is a **regression watcher on the DEFINITION** in CI.
- ⚠ **Accept "move the check out of the migration" when an in-migration raise would fail every CORRECT run** —
  a leg that fails on correct input is worse than no leg, because it gets disabled on first contact. That is a
  legitimate objection to my own condition and I have adopted it twice. **But the replacement still has to land
  in a lane that can observe the property.** See [[assertion-with-no-watcher]] and
  [[a-guarantee-moves-only-if-the-same-file-runs]].
