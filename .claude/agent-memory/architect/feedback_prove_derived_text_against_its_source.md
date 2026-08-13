---
name: prove-derived-text-against-its-source
description: Rebuild a regenerated block from its source plus named substitutions so fidelity is true by construction; and a period inside quotation marks claims the sentence ended there
metadata:
  type: feedback
---

Two mechanical techniques for text that must faithfully derive from a source —
regenerated catalog comments, and quotations inside ADRs and briefs.

## 1. RECONSTRUCT, don't edit toward

When regenerating a block from a source (e.g. a `comment on` re-issued from the
migration that first authored it), **rebuild it programmatically from the source plus
N named substitutions**, each asserted to match **exactly once** before applying.

> Because the file is rebuilt *from* the source rather than edited *toward* it,
> "byte-identical outside the substitution spans" is **true by construction**, not by
> inspection — **there is no third region to have missed.**

This is strictly stronger than a containment proof, and it has a second benefit:
**it needs no byte counts at all**, which removes a whole failure class (below).

**Why:** migration `068`, 2026-08-12. First pass used a containment proof citing
unchanged prefix/suffix byte counts. Sec independently measured **different numbers
and both were correct** — Sec counted the **rendered catalog string**, the file counted
**SQL source text including per-line quote wrappers**. Two scopes, one unlabelled
number, and the disagreement looked like an error in one of them.

- ⚠ **A count without its scope invites reconciliation of two things that were never
  the same measurement.** The best fix was not to label the scope but to **restructure
  the proof so no count was needed.**
- ⚠ **Character-level diffing is the wrong instrument here.** It fragmented two logical
  substitutions into 22 micro-regions by matching incidental substrings ("the ", "and ")
  inside replaced text. Technically accurate, useless — a region count characterises
  only what changed.

## 2. A period inside the quotation marks claims the sentence ended there

**Why:** Sec caught ADR-053 quoting `054` as *"…MUST set the GUC first."* where the
source reads *"…MUST set the GUC first, **in the same transaction**."* Every quoted word
was real, which is what makes this class survive a verbatim check — and the dropped
clause was the load-bearing one for that very ADR.

**How to apply:**
- **Terminal punctuation inside the marks is a completeness claim.** Partial quotation
  with no closing period is honest; the same words with a period are not.
- Checked against the two neighbouring quotes in the same passage: one genuinely ended
  where quoted, one was partial without a terminal period. **Both sound.** The
  discriminator separates them cleanly and is cheap enough for any verbatim sweep.
- ⚠ **Check the neighbours, not just the flagged line.** Fixing one instance of a class
  and leaving its sibling is this project's most repeated failure — see
  [[structural-fence-must-cover-the-same-class]].

Related: [[watcher-not-fence-for-by-construction-properties]] · [[diff-filter-strips-comment-lines]]
