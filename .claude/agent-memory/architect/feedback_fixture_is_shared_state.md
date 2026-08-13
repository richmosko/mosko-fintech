---
name: fixture-is-shared-state
description: A per-leg fixture edit in a pgTAP battery is a global edit — adding a row for one assertion can silently void a different assertion's premise
metadata:
  type: feedback
---

In a pgTAP battery, the fixture block is **shared state**. Adding or moving a row to
serve one leg can silently change what a different leg is testing, several hundred
lines away, without failing anything.

**Why:** measured twice on SELF-218's `067` battery, 2026-08-12.
- QA's first draft seeded a non-publication checkpoint at `2025-08-01`. That predates
  the cross-tenant canary window, so `062`'s lower-bound clamp would have given
  tenant A something to carry **into** a window whose entire premise is *"A holds
  nothing here"* — voiding the isolation legs while they stayed green. QA caught it
  themselves mid-fix and moved it to `2025-12-01`.
- Separately, eight legs were red because the fixture placed checkpoints mid-month
  when `062` only emits a period-end at-or-before the tenant's **max** checkpoint.
  Three fixture edits fixed all eight with **zero assertion-logic changes** — which is
  the tell that the defect was in shared state, not in any assertion.

**How to apply:**
- When reviewing a battery, re-derive **every** leg against the fixture, not just the
  legs whose expectations changed. Assertion diffs do not reveal fixture-coupling.
- A fix set that is "all fixture, no assertion logic" is a signal the whole file's
  legs need re-deriving, not a signal the change was small.
- Fixture rows deserve an inline comment naming **which legs depend on them and
  why** — `067`'s battery now does this, including a ⚠ on the checkpoint whose date
  is load-bearing for a leg in a different section.
- The same argument is why a same-value or single-tenant fixture is not a test: it
  passes under a broken predicate. Vary the value that the fence is supposed to
  discriminate on.
