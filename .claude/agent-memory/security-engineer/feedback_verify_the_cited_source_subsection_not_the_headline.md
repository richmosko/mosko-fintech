---
name: verify-the-cited-source-subsection-not-the-headline
description: When a figure traces to a cited external authority, read the cited section's EXCLUSION subsections and the same document's other occurrences of the number — the falsifier lives there, not in the headline sentence.
metadata:
  type: feedback
---

When a money figure or a rule about a money figure cites an external authority, verifying the
headline sentence is not verifying the claim. **Read the cited section's whole text, including its
"the following shall not apply" subsections — that is where the falsifier lives.**

**Why:** SELF-260 / `103` seeded the CA §17043 1% surtax and asserted, in four sites and as an
instruction to the user, that its $1,000,000 floor "moves with filing status (it is $500,000 for
married/RDP filing separately)." R&TC **§17043(a)** reads as a flat $1,000,000 — consistent with
the claim if you stop there. **§17043(c)(2)** then expressly disapplies "the provisions of Section
17041, relating to filing status and recomputation of the income tax brackets," and (c)(3)
disapplies §17045 (joint returns). The statute does not merely omit a status split; it switches
off the mechanism that could produce one — and the same subsection makes the threshold
un-indexed. A reader who confirmed (a) would have ratified the error.

**The drift vector is a plausible sibling number in the SAME document.** `$1,000,000 ($500,000
for married filing separately)` really does appear in the FTB 2025 Form 540 booklet — at the
Schedule CA line 8 **home-mortgage-interest acquisition-debt limit**, a different provision.
That is why the claim survived every spot-check: a grep for the number succeeds. **Grep the
number, then read what the hit is ABOUT.** Related: [[feedback_false_composite_citation]] — two
real facts wrongly paired.

**How to apply:**
1. `curl` the primary PDF/statute and `pdftotext -layout` it, never a WebFetch summary (Architect
   measured WebFetch returning confidently-wrong prior-year tables from the correct PDF).
2. Read the cited *subsection*, then its neighbours — especially any `(c) The following shall not
   apply`.
3. When a number appears more than once in a source, confirm the hit you cite is the provision you
   mean.
4. Check whether the popular name is current: the same TY2025 booklet renamed "Mental Health
   Services Tax" → "Behavioral Health Services Tax," and the seed shipped the superseded name for
   the exact year it seeded. Statute number unchanged; popular name not.
5. **The direction that costs is a claim shipped as a user INSTRUCTION.** A wrong constant is one
   defect; a wrong instruction to change a constant recruits the user into producing it.
6. If the file faithfully implements a *ruling*, the ruling carries the same defect — escalate to
   correct both, or the next surface inherits it. See
   [[feedback_read_decisions_from_the_pr_branch_when_the_pr_edits_it]].
