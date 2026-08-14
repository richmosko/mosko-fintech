---
name: verify-spatial-reading-against-locked-spec
description: When a UX functional spec's spatial wording is ambiguous, cross-check against the locked product spec's own stated semantics before designing — self-consistency reasoning alone is not enough
metadata:
  type: feedback
  ---

When UX's functional spec uses spatial language that's ambiguous ("left-anchored", "flush against," etc.) for a
chart/layout element, don't resolve it purely by constructing a self-consistent reading of UX's own text. Check
it against the **locked product spec's** stated semantics for that surface first (e.g. PRD §2.1.2's own
definition of the chart window) — that's the higher-authority source and the one the ambiguous phrase is
actually describing.

**Why:** On SELF-220 (NAV-over-time chart, sparse-history density indicator), UX's spec said the partial line is
"left-anchored" while the frame "calibrates against the eventual full window." I constructed a self-consistent
reading (frame anchored at tracking-start, extending 60mo *forward*, hatch on the right) that was internally
coherent but backwards — PRD §2.1.2 already defines this chart's window as **rolling/trailing, right edge always
= today**. UX's "left-anchored" meant "the line's own earliest point never precedes real tracking-start," not
"the line sits at the frame's left edge." A reading that's internally consistent with the ambiguous source text
can still be wrong if it isn't checked against the locked spec the source text is operating inside of. Correctly
flagging the ambiguity back rather than guessing silently (per [[flag-gaps-dont-fill-them]]) did surface it before
Frontend built the wrong thing — but the flag itself carried the wrong resolution, costing a round trip.

**How to apply:** Before committing a spatial/layout interpretation to a written spec, especially for chart
axes/windows/timelines, check the surface's own locked PRD section for an explicit direction/anchor definition.
For mosko-fintech specifically: NAV-over-time and similar trend charts are **rolling/trailing windows — right
edge is always "today"** (PRD §2.1.2) — this is the default orientation for any future chart work on this
surface unless a spec explicitly says otherwise.
