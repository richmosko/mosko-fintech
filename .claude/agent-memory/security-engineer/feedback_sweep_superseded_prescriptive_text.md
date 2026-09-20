---
name: sweep-superseded-prescriptive-text
description: When a document supersedes its own earlier ruling, grep every instance of the superseded mechanism and classify each as RECORD or INSTRUCTION — the build-instruction list and the option text a decider reads are where a missed pointer does real damage.
metadata:
  type: feedback
---

**A later section that reverses an earlier one does not disarm it. Sweep the document for the superseded
mechanism and grade each hit as RECORD (correct to keep) or INSTRUCTION (must carry a forward pointer).**

**Why:** ADR-072 Amendment 5 ruled `set local role pfin_owner;` unexecutable at Decision F1 — and left five
prescriptive instances standing with no pointer, including the *"What the implementing PRs carry"* list (**the
build instruction** — an implementer working from it ships the unexecutable form and a one-leg strike instead of
four) and the **(A2) option text a decider reads to choose**, which also still granted the role a reach a later
decision had removed. Two bullets in the same document *were* correctly covered by one inline pointer, which is
the proof that the fix is cheap and that its absence elsewhere is an omission, not a convention.

**How to apply:**
- Grep the superseded phrase across the document's own region (bracket by `## ADR-` headers, never line
  numbers). Expect most hits to be legitimate: withdrawn-ruling narrative, keep-and-annotate history,
  quotations. **Say which ones you excluded and why** — an undifferentiated hit list reads as noise and gets
  dismissed wholesale.
- **Rank by blast radius, not by order of appearance.** The decision-of-record on the mechanism, the
  build-instruction list, and the option text presented for a decision outrank everything else.
- **Look for two defects in one line.** Option text tends to carry both the stale mechanism *and* a grant the
  later decision removed — and a grant sitting inside an option's own definition **pre-commits the choice in the
  very text that says the choice is open.** Flag that as assuming an un-given ratify.
- **Remedy is keep-and-annotate, one inline ⚠ pointer each — never a rewrite.** Cite line number *plus* anchor
  phrase so the fix survives a renumber. See [[read-the-whole-cell-before-diagnosing-doc-drift]] and
  [[conditional-rearmed-by-transcription]].
