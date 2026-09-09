---
name: 055-one-line-exception-precedent
description: F/CTO granted a ONE-LINE exception to the applied-migration edit-in-place rule for 055's raise warning (2026-09-09, PR #675) — the ground is ADR-021 greenfield, and the precedent is bounded to that single line.
metadata:
  type: project
---

**F/CTO granted a one-line exception to `apply-migration` Step 1.6's closing
constraint** (*"editing an applied migration's SQL is out under every framing"*)
for `055_pfin_etl_role.sql`'s re-apply-guard `raise warning` — BACKLOG §7.36 item 6
AC (2), ruled 2026-09-09, landed on `feature/117-c1-relabel-055-warning` / PR #675.

**Why:** the object Step 1.6 protects is a **prior approval of DEPLOYED STATE**.
Under [[project_multiuser_general_software_scope]]'s ADR-021 greenfield posture no
deployed state exists — `055` has never been applied to a production database and
replays **verbatim at first deploy** — so the wrong operator instruction would reach
the operator it is aimed at rather than nobody. Sec's supporting measurements (no CI
migration-checksum fence; the `DO` block has no DB representation; re-application is
idempotent) establish **replay safety**, which is necessary but not sufficient —
Step 1.6 (B) condition 2 is about voiding an approval, not replay.

**How to apply:**
- **The precedent is one line wide.** A second executable-line edit to an applied
  migration needs its **own** F/CTO ruling; do not cite this as a general licence,
  and do not let *"the instruction was wrong"* become a reusable framing.
- **The ground is the greenfield premise, so it expires.** Once anything is deployed
  to production, this reasoning is dead and Step 1.6's closing constraint is absolute
  again.
- **Vehicle triage is unchanged** and still follows where the text lives: catalog
  comment → new comment-only migration (the `052` shape); file-header `--` block →
  edit in place under the three conditions; executable SQL → neither, absent a ruling.
- **Sec joint-review is part of the exception**, not optional after it.
- ⚠ Sec round-4 **N9** corrects a gloss in the §7.36 item 6 booking: condition 1 is
  the **replay-equivalence** one, condition 2 the voiding-a-prior-approval one — the
  booking swaps them. Conclusion unaffected; do not inherit the swap.

Related: [[feedback_push_with_flagged_defect_over_holding]],
[[reference_role_comment_is_a_shared_cluster_catalog]].
