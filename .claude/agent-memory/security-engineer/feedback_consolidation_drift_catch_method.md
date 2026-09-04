---
name: consolidation-drift-catch-method
description: Auditing a consolidation (sitting log, ADR, ruling) against my own findings file — a quote attributed to me may be LAUNDERED from a teammate's file, and a re-aimed AXIS silently deletes the gap I found.
metadata:
  type: feedback
---

**Rule: when a consolidated artifact cites me, my own file is only half the check. Grep the
SIBLING findings files too, and check whether the consolidation kept my finding's AXIS.**

**Why:** V1.4 pre-flight sitting log (`5d59a4a`), drift-catch against `sec-findings.md`. Two
failure modes appeared that reading my file alone could not have produced.

---

### 1. A quote attributed to me that I never wrote — laundered through a teammate

The log read: *"a GL design Sec calls **'its own tax-complex mini-design'**"*. The phrase appears
**zero** times in my file. It originates at `pm-findings.md:103`, where PM attributed it to Sec;
the log copied PM's sentence verbatim and inherited the false attribution intact.

**Why this defeats every ordinary check.** A verbatim-quote check against the log passes (it
faithfully copies PM). A verbatim-quote check against PM passes (PM's file really says it). Only
a search of **my** file falsifies it — and only if I think to search for the absence rather than
verify the presence of the quotes I recognise. It is the mirror image of
[[my-review-measurements-become-quoted-sources]]: there my real words got the wrong pointer;
here a pointer to me got words that were never mine.

**How to apply:** at any consolidation review, extract **every** string in quote marks attributed
to me and `grep` it against my own file. A miss is not "close paraphrase" — it is a fabricated
attribution, and it will be quoted onward as my position. Then `git grep` the phrase across the
sibling findings files to name where it actually came from, so the correction repairs the source
and not just the copy.

**Cheap grep:** `git grep -n "<phrase>" <ref> -- docs/records/` over the whole records dir, not
just my file. The origin file is usually one hop away.

---

### 2. A re-aimed AXIS deletes the gap

My §9.1 found a gap between **headline and foot** (two surfaces that had footed exact by
construction, now differing because an exclusion lands in one and not the other). The log's rider
restated it as a gap between **headline/foot and chart** — collapsing my two disagreeing surfaces
onto one side. That is not a paraphrase: it *presupposes* the thing I found to be false, and it
produced an internal contradiction in the ruling's own body ("the two live surfaces that share one
composed value") against its own rider ("an identity this ruling deliberately breaks").

**The tell:** my finding named an A-vs-B gap; the restatement names an (A,B)-vs-C gap. Whenever a
consolidation regroups the operands of a difference, **re-derive the arithmetic from the tree**,
not from either text. Here: `netWorth.ts` calls `fn_compute_nav`; `051`'s foot builds over its own
leaf set; the exclusion lands in `051` only ⇒ they cannot agree. Two greps settled it.

Same family as [[two-functions-two-partitions-axis-mismatch]] — diff the member sets before
accepting the arithmetic — but arriving through *prose about* a finding rather than through code.

---

### 3. The general shape of this review

Findings sort into four buckets, and only the middle two are worth a long sentence:

- **Force preserved** (veto stayed veto, note stayed note, retraction honoured) — usually clean;
  say so explicitly, an unchecked axis reads as unexamined.
- **Conditions silently dropped** — the common one. A ruling adopts my conclusion and drops the
  `comment on column` / the second half of a two-part mechanic / the two other defects in a
  three-defect finding. Nothing reads as wrong; the control just is not there.
- **Axis or attachment moved** — the dangerous one (§1 and §2 above).
- **Never carried at all** — check my own §5/F-item list against the ruling numbers. An open
  question that was on my list and is on no agenda item leaves the sitting **unowned**, and
  nobody notices because no ruling contradicts it.

**How to apply:** enumerate my findings' ids FIRST from my own file, then walk the consolidation
looking for each one. Walking the consolidation and checking what it cites finds only the drift
in what it chose to mention — never the omissions, which is where the unowned money questions sit.
