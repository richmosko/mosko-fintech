---
name: account-trans-write-surface-auto-routes-to-sec
description: ADR-064 D5 — any change to a pfin.account_trans write surface (incl. reverse-and-replace) auto-routes to Sec as D2-mandatory, never opt-in; the rationale has a home, the enforcement trigger does not
metadata:
  type: project
---

Any change to a **`pfin.account_trans` write surface** — explicitly including
`reverseAndReplaceTrans` and the reverse-and-replace family — **auto-routes to Sec joint review as
ADR-011 Decision 2 mandatory.** It is never offered as a courtesy/opt-in review.

**Why:** at PR #567 (SELF-340, 2026-08-26) team-lead offered the reverse-and-replace fix as a
*"courtesy review offer, not a mandated gate."* `pfin.account_trans` is an immutable,
INSERT-new-version audit-class table, which is squarely inside D2's joint-review-mandatory set — the
review was owed, not optional. I took it and found a veto-grade defect (securities-row edits
silently destroying the position; see
[[an-unblocking-fix-unmasks-every-input-class]]). Had I declined the "courtesy", it would have
shipped. Team-lead recorded the mis-scope and F/CTO adopted the correction.

**How to apply:** if a dispatch frames an `account_trans` write-path change as optional, **say so and
take it** — the framing is the error, not the work. State the D2 basis in the first line of the
reply rather than at the end, so the correction lands with the verdict.

**Repo home: [ADR-064](../../../DECISIONS.md) Decision 5** (landed on the PR #567 branch, 2026-08-26).
Its wording is worth reusing: *"'Already fenced' describes the fences that exist; it says nothing
about the write the change newly composes. The trigger is the SURFACE, not the layer, and not the
author's assessment of risk."*

⚠ **The RATIONALE has a home; the TRIGGER does not — do not read ADR-064 as closure.** The ADR's own
Consequences say an ADR is the wrong instrument (*"DECISIONS.md answers why the rule exists; it is
not read at the moment the mistake is made"*) and route the enforcement half onward: it needs to sit
in the **agent role definitions' Sec joint-review trigger lists**, and ideally a PR-template or a CI
check keyed on the write-surface paths. My own role brief already carries the D2 trigger, so the
residual gap is dispatcher-side. **At the next `WORKFLOW.md` / role-definition touch, check whether
the trigger landed** (team-lead or Architect holds that pen, not me) and re-raise if not.

**Outcome, for calibration:** F/CTO first ruled HOLD (design before refusal), then ratified the
A+C-deferred package at ADR-064; the resumed PR reviewed GREEN at `aa9c670`. The veto cost one design
cycle and produced a materially better result than option A alone would have — the design pass found
the hazard **wider than my veto stated** (three fact-kinds, not "trades"; and the reversal is
`cost_basis`-blind, so holdings and the GL diverge in *opposite* directions while the trial balance
still sums to zero). **Vetoing on an incompletely-characterised hazard was still right** — I had the
mechanism and the reachability; the full blast radius came from the design pass the veto forced.
