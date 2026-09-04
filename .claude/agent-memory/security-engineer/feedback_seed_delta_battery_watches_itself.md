---
name: seed-delta-battery-watches-itself
description: A seed-delta battery that REPLAYS the migration's statements observes itself, not the migration — and its zero-affected idempotency legs are vacuous against the exact miss the migration's own header names. Ask which half CAN be observed directly.
metadata:
  type: feedback
---

**When reviewing a data-migration (seed-delta) battery, split the surface into the half that must be
replayed and the half that can be observed directly — then check the direct half is actually
observed. Assume it is not.**

**Why:** worked instance, SELF-263 / migration `100` (2026-09-03). A seed delta corrects values on
a `*_default` table AND backfills the same corrections into the per-user mirror. A pgTAP battery
**cannot** re-run an applied migration for tenants it creates afterwards, so the per-user half is
necessarily proved by **replaying verbatim copies** of the migration's statements against the
battery's own fixture. That is unavoidable and fine — but it means those legs observe **the
battery**, not the migration: the fixture and the replay share one string list, so a `(cat, sub_cat)`
that resolves to no real row passes identically.

**The trap that looks like coverage:** the "re-apply the statement, assert ZERO rows affected"
idempotency leg. It runs against the REAL migrated table, so it *feels* like the direct observation.
It is not. **Zero-affected is satisfied both by "the row was corrected" and by "the guard never
matched anything"** — and a typo'd key produces zero in the real apply *and* zero in the replay.
Vacuous on precisely the silent-miss the migration's own header names as its accepted cost.

**How to apply:**

- **Ask which relations existed BEFORE the battery's transaction opened.** Global / default /
  registry tables are already in post-migration state when the battery runs — those CAN be pinned
  positively, with no fixture and no replay. Per-tenant tables cannot. Require the positive legs on
  the first set; accept replay on the second and say so as an explicit non-objection.
- **The default table is the one that matters going forward** — it is what every future signup
  inherits through provisioning. Verify the app's provisioning column list actually copies the
  corrected columns (`grep` the constant), then judge the missing watcher against *that* blast
  radius, not against the fixture tenant's.
- **Read the migration header for a promised watcher.** `100`'s said *"The watcher is QA's paired
  battery asserting the POST state row by row."* **A stated control that is not built is a finding
  in its own right**, independent of whether the values happen to be right today — and it is the
  cleanest way to state the severity without overclaiming.
- **Separate "coverage gap" from "live defect" and measure both.** I set-compared the migration's
  25-row VALUES list against the seed (post-rename) and got 25/25 resolving — so I could report
  AMBER on the missing watcher while stating plainly that the miss has not happened. Without that
  measurement the finding reads as an accusation.
- **Name the inversion.** Strike statement (N) from the migration on a scratch clone: the proposed
  new legs must red **while the existing fixture legs stay green**. That divergence IS the finding,
  demonstrated. Any proposed leg that cannot be red-ed this way is not the leg.
- **Never accept the tempting repair** — replacing a pinned expectation with a live
  `select count(*)` off the same table. ADR-057 names that tautology explicitly; it can never red
  again.

Related: [[an-enumeration-and-its-watcher-both-stop-one-short]],
[[corrupt-the-control-canary-boundary-tie]], [[a-shared-predicate-covers-only-that-predicate]],
[[applied-vs-demonstrated-discharge]], [[a-red-whose-message-names-the-wrong-defect]].
