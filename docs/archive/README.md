# docs/archive — frozen artifact snapshots

This directory holds frozen point-in-time snapshots of project artifacts taken at version boundaries. Snapshots are **read-only historical references** — do not edit them.

## Current snapshots

### `PRD-v1.18-source.md`

Frozen copy of `PRD.md` as of WORKFLOW.md v1.18 (2026-05-18, after PRD §8 lock landed in PR #25), taken at kickoff of Phase 1 Step 3.5 (PRD editorial rewrite).

## Why this snapshot exists

The Phase 1 Step 3.5 editorial rewrite (Phase 1 Step 3.5 / PR #25 → PR #N) restructures `PRD.md` for scannability without altering locked substance. The rewrite shifts line numbers throughout `PRD.md`.

`WORKFLOW.md` changelog entries dated on or before 2026-05-18 and `DECISIONS.md` ADRs ADR-002 / ADR-004 / ADR-008 carry `PRD.md:NNN` line-anchored cross-references. Those references were correct at the time they were written and are preserved verbatim per project immutability conventions (DECISIONS.md head: "entries are immutable once accepted").

`PRD-v1.18-source.md` is the resolution target for those historical `PRD.md:NNN` references. Read `PRD.md:47` (in any pre-2026-05-18 entry) as "line 47 of `docs/archive/PRD-v1.18-source.md`."

## Forward convention

From Phase 1 Step 3.5 onward, new cross-references to `PRD.md` use **section-anchor form** (`PRD.md §N.M.K`), not line-anchor form. Section anchors are stable across future PRD edits.

## Carve-out — Q4 = α retargeting

Phase 1 Step 3.5 Q4 was ratified as **α — retarget line-anchored refs to section-anchor at rewrite time**. As each section of `PRD.md` is rewritten, the corresponding rewrite PR sweeps `WORKFLOW.md` + `DECISIONS.md` for `PRD.md:NNN` references that point into the rewritten section, and updates them to `PRD.md §N.M.K` form.

**This retargeting is treated as a presentation-pointer update, not an ADR substance amendment.** The locked decisions, reasoning, and consequences in ADR-002 / ADR-004 / ADR-008 are not changed by retargeting — only the pointer form is updated to remain resolvable against the rewritten `PRD.md`. The immutability convention in DECISIONS.md ("supersede via a new entry rather than rewriting an old one") applies to ADR substance, not to mechanical reference resolution.

`PRD-v1.18-source.md` continues to exist as the historical resolution target for any pre-Phase-1-Step-3.5 reference that was missed by the retargeting sweep, and as the authoritative record of what was locked at the Phase 1 Step 3 closeout.
