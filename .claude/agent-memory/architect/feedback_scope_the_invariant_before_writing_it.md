---
name: scope-the-invariant-before-writing-it
description: An invariant asserted over "every row" is usually falsified by the surface's own documented edge cases — check it against the NULL-cause rows before writing it, in ADRs, ACs, contracts and catalog comments alike
metadata:
  type: feedback
---

**Before writing any "X and Y always agree / are always equal / are NULL together" claim,
apply it by hand to each of the surface's own documented edge cases — starting with the rows
that already have a NULL cause.** That is where these claims break, and they break in the
direction that costs the most to fix.

**Why:** twice in two consecutive items, on the same class.

1. **`072`, shipped defect (mine).** The catalog comment and header said the real-terms percent
   is *"NULL **exactly where**"* the dollar column is NULL. The migration's **own** item-14 case
   falsifies it: on a non-positive deflated base the dollar column is PRESENT and the percent is
   NULL. The code and the battery were both correct — only the prose was wrong. Sec's AMBER found
   two sites; a re-grep of my own text found a third. Cost: two review round trips and, had it
   merged, a comment-amendment migration.
2. **SELF-223, caught in draft.** PM proposed *"the prior-YE row's two cells are equal by
   construction."* False on the CPI-unresolvable row — nominal stands, real goes NULL, one cell is
   a figure and one is blank. Scoped to *"whenever `cpi_unavailable` is false"* it is true and
   valuable. Cost: one message.

**The asymmetry is the whole point: the same defect costs one message in a draft and a migration
after merge.** So the check belongs at drafting time, not at review time.

**How to apply:**
- **The failure is not wrong behaviour — it is misdirection.** A future corrector reads the
  unconditional claim, finds a row where it does not hold, and goes hunting in the column that is
  working correctly. That is worse than no claim at all.
- Prefer the **one-way implication** where that is what is true (*"NULL wherever…, and
  ADDITIONALLY NULL when…"*) over the biconditional that reads more elegantly.
- When a genuine biconditional holds only over part of the domain, **say which part** and, if a
  test asserts it, scope the test's fixture to match — then say in the comment why the scope is
  load-bearing, or a later consistency sweep will "fix" the scope away.
- Applies identically to ADR text, PRD acceptance criteria, `comment on` catalog text and pgTAP
  assertion descriptions. The vehicle differs; the defect does not.

Related: [[prove-derived-text-against-its-source]] ·
[[replacement-control-name-the-losing-side]] · [[pgtap-isnt-passes-on-null]]
