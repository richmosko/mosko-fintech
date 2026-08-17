---
name: ratified-name-is-not-a-built-table
description: A table named in ADR/SECURITY/ARCH may have no DDL at all — grep migrations before designing around it, and before believing an AC that joins it
metadata:
  type: feedback
---

A surface name carried in ADR-011, SECURITY SD/RT rows, and ARCH §8/§9 is a **ratified
intent**, not a built object. Verify against `supabase/migrations/*.sql` before treating it
as existing — and before diagnosing an AC that references it as "wrong."

**Why:** at SELF-324 the whole Lock-14 settings family (`planning_target`,
`cashflow_target`, `tax_bracket_schedule`, `tax_bracket_row`, `owner_identification`) was
carried by name across six artifacts and had **zero** DDL. Downstream ACs joined
`planning_target` in good faith. A `WORKFLOW.md` Phase-4 lessons line reading *"Lock 14
family also fully implemented … = 5 named tables"* is about **issue decomposition**, not
build — but it reads as a build claim, and that is how the belief propagated. Same root as
the schema-impossible-AC pattern: see [[schema-impossible-ac-traces-to-incumbent]].

**How to apply:** the cheap check is `grep -l '<name>' supabase/migrations/*.sql` — empty
means unbuilt, full stop. Do it at the START of any options pass on a named surface. Two
consequences follow that change the memo: (1) the shape you ratify is a **template** for
every unbuilt sibling, not a one-off; (2) a doc that asserts implementation is a finding to
bubble up, scoped honestly (decomposition-vs-build), not a false-claim accusation —
[[claim-about-the-world-vs-decision-about-what-we-do]].
