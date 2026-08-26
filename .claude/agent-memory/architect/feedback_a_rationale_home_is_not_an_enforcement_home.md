---
name: a-rationale-home-is-not-an-enforcement-home
description: Recording a routing rule or convention in DECISIONS.md answers why it exists but is never read at the moment the mistake is made; name the enforcement home separately or the ADR becomes the rot it was written to prevent.
metadata:
  type: feedback
---

When asked to give a convention a "durable home", **do not accept an ADR as the whole answer.**
An ADR answers *why the rule exists*, for someone already asking. It is not open on the screen
of the person about to break it.

**Why:** ADR-064 Decision 5 (2026-08-26) records that any change to a `pfin.account_trans` write
surface is Sec-joint-review-mandatory. The counter-example that forced it: the vetoed PR's own body
reasoned, carefully and in good faith, *"Sec look is courtesy, not mandated on its face (app-layer
fix on an already-fenced path)"* — and that PR would have destroyed positions. **"Already fenced"
describes the fences that exist and says nothing about the write a change newly composes.**
Team-lead offered ADR-vs-`WORKFLOW.md` as the choice; both are rationale homes.

**How to apply:** answer in two parts and say so explicitly —
1. **Rationale home** — the ADR, with the counter-example that generated the rule. This is what
   stops the rule being re-litigated.
2. **Enforcement home** — where the *router* and the *builder* actually look at the moment of use:
   the Sec joint-review trigger lists in `.claude/agents/*.md`, a PR template, a CI check keyed on
   the surface's paths. Often **not writable by Architect**, so it is a routed obligation, not a
   discharged one — say **"not discharged"** in the hand-off or it reads as done.

**The tell that you are about to file rot:** the convention's trigger is a *surface* (these paths,
this table) but the only record is prose describing *judgment* (when to consider it). A surface
trigger can be mechanised; if nobody mechanises it, say that plainly rather than letting the ADR
imply coverage. Related: [[feedback_assertion_with_no_watcher]] ·
[[feedback_watcher_not_fence_for_by_construction_properties]] ·
[[reference_suspense_branch_absorbs_the_divergence]] (the fence-after-the-write corollary).
