---
name: adr063-numbers-protocols-as-items
description: ADR-063 numbers its four process protocols as items inside ONE "### Decision" block — "ADR-063 Decision 3" is a malformed pointer; verify a citation's SHAPE, not just that the ADR is real
metadata:
  type: reference
---

**ADR-063 has a single `### Decision` heading containing four bolded numbered items**
(1 pre-flight recalibration · 2 seam inventory · 3 default-and-notify · 4 walk-before-Sec).
There is no `### Decision 3` heading. So **"ADR-063 Decision 3" is not a well-formed pointer** —
the correct form is *"ADR-063's default-and-notify protocol (Decision item 3)"*.

⚠ **I shipped the malformed form into a merged migration header (`099` line 203), and team-lead
used it too.** It is the "right content, wrong pointer" half of ADR-011 Decision 4's
inherited-citation drift class: the content it names is real and correct, so the citation passes
every spot-check that asks *"does this ruling exist and say that?"*

**The reusable rule: an ADR's internal structure is not uniform across the file, so verify the
SHAPE of the anchor you cite, not merely that the ADR and the ruling are real.** Some ADRs use
`### Decision N` headings (ADR-011); others use one `### Decision` block with numbered items
(ADR-063); others are terse-pattern with no decision headings at all (ADR-064/065). Before
writing `ADR-0NN Decision N`, grep the ADR for `^### Decision` and check.

**Also worth knowing when citing ADR-063 item 3:** default-and-notify has **three** conditions
(downstream of an F/CTO ruling · reversible without a data migration · resolvable from
measurement rather than product judgement) and a reversal window that closes at a **named event**,
not a duration. Failing any one condition routes to F/CTO instead.

Related: [[feedback_fix_the_citation_not_the_referent]] · [[feedback_name_anchor_adr_citations]].
