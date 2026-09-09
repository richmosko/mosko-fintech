---
name: c1-rotation-coupling-label-is-misattributed
description: The "ADR-023 condition C1" rotation-coupling label is wrong-ADR across ~6 artifacts; the coupling is ADR-019's C1 — re-attribute, never delete
metadata:
  type: project
---

The PostgREST/provider-sync **password rotation coupling** is labelled **"ADR-023
condition C1"** across the tree. **ADR-023's own enumerated C1 is a different
condition** — *"exposure-readiness artifact (per-table RLS + policy proof) reviewed
before exposure"* — and ADR-023's body contains no rotation-coupling text at all.

**Why:** the coupling's real home is almost certainly **ADR-019's Sec condition C1**.
ADR-019's login-role note says *"F/CTO ratified (b) connect as `authenticator` + Sec
conditions C1–C4"* but **only C2 is enumerated** in `DECISIONS.md`; the C1 text
survives only in `workers/provider-sync/.env.example` (*"Sec conditions C1/C3"* then
*"CONDITION C1 (rotation coupling — Sec-load-bearing)"*). So the defect is
**wrong-ADR attribution + an un-enumerated condition set**, NOT an invented label.
Raised at PR #671 / migration `116`; Architect's draft diagnosed it as
"label unsupported anywhere" and its remedy would have **deleted** a label that has a
real home. That claim also asserted *"no text in DECISIONS.md attaches the rotation
coupling to a condition labeled C1"* — false: ADR-041 does it three times.

**How to apply:** if asked to adjudicate or correct this, the answer is
**re-attribute to ADR-019 C1 + enumerate ADR-019's C1/C3/C4**, never delete. Two
correction vehicles in one file: `055`'s `--` header is edit-in-place, but its
`comment on role` is a **database object** and needs a comment-only follow-up
migration. `.env.example`'s bare `C1` is already correct under the re-attribution —
do not "fix" it. Verify the artifact list live before acting: my enumeration at
2026-09-08 corrected Architect's, which wrongly included BACKLOG §7.6 S5 (measured:
S5 carries no C1 label).

Related: [[feedback_verify_the_cited_source_subsection_not_the_headline]] ·
[[feedback_read_the_whole_cell_before_diagnosing_doc_drift]] ·
[[feedback_a_citation_has_four_axes]]
