---
name: ci-fenced-set-grep-must-not-be-tightened
description: The prescribed CI-fenced-RT grep returns one more label than there are fenced JOBS, because one RT is cited in a workflow comment — do not tighten the grep, and never reconcile the fenced set with the §10 catalogued set even when their job membership coincides.
metadata:
  type: project
---

**Standing constraint: `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` is the prescribed
measurement of the CI-fenced set and must be run AS WRITTEN. It returns labels cited in
workflow COMMENTS as well as labels that name fenced jobs. That is a feature.**

**Why:** measured 2026-08-17 on PR #485. The grep returned four labels; only three name jobs
that emit a check context. The fourth occurs once, in a **comment** recording a Sec condition on
a dependency pin (`web-tests.yml`, a `jose` ES256/JWK verify pin for the PDF-worker JWT surface).
So as *job* sets, the CI-fenced set and the **§10 catalogued set had identical membership** at
that moment.

**⚠ That coincidence is the hazard, and the tidying instinct is the attack.** Tighten the grep to
match job names only → both measurements return the same number → the two sets look like one set
→ someone "reconciles" them. **They must never be reconciled.** They carry **different change
triggers** — ledger changes are joint-review-mandatory; fence-boundary changes are an escalation
trigger. **Coincident membership at one moment is not identity.** Two coincidentally-equal
descriptions are indistinguishable from one description, which is how a real distinction gets
deleted as cleanup.

**How to apply:**
- Read both sets **live** every time — the §10 ledger from ADR-011 Decision 4 verbatim, the
  fenced set from the grep as written. **Never from this file**, including the "four" above.
- If a future reader reports the grep "returns a label with no job", that is **expected**, not a
  defect. Do not narrow the pattern, do not delete the comment, do not file it as drift.
- When the two sets coincide, **say so explicitly and say it must not be acted on**. Silence
  reads as agreement with whoever proposes the merge.
- A label cited in a comment is still load-bearing: it records why a dependency pin or config
  exists. Removing the comment to "clean up the grep" deletes the rationale.

See [[a-red-whose-message-names-the-wrong-defect]] for the sibling pattern — the repair a signal
invites is often the one that destroys the signal.
