---
name: freshly-seeded-rows-are-invisible-to-a-past-as-of
description: A value-bearing smoke on any §2.3 / Lock-15 as-of surface returns ALL ZEROS if you pick a historical p_as_of — rule 6's created_at half excludes rows you just INSERTed, and the empty result is indistinguishable from a broken function
metadata:
  type: reference
---

Rule 6 (ADR-011 Decision 19 as amended; housed in `pfin.fn_cashflow_items`) is
**dual-column**: `transaction_date <= D AND created_at < (D + 1)`. A row you seed
in a smoke test carries `created_at = now()`, so **any `p_as_of` earlier than
today excludes it**, no matter what `transaction_date` you gave it.

**Why this bites specifically.** The natural seed is historical dates — Feb
transactions, `p_as_of = '2026-05-15'` — so the quarter flags are interesting.
That combination returns the **ordinary empty document**: three sections, empty
row lists, zero totals, `unclassified.count_ytd = 0`. That is *byte-identical* to
what a non-owned account, a nonexistent account, a NULL argument, and a genuinely
broken composition all return. Measured 2026-08-28 while smoking `094`: I read it
as "the function isn't composing" before recognising it as rule 6 working.

**How to run the leg instead:** seed historical `transaction_date`s but call with
`p_as_of = current_date`. The period flags still resolve (Feb rows land in `in_q1`
of the current year), and the quarters that have not started still arrive NULL, so
you keep the em-dash leg. Run the *past*-`p_as_of` call as a **separate** leg and
label it what it is — a rule-6 assertion, not a shaping assertion.

**Why it matters beyond the smoke:** this is the exact shape of the defect
Decision 19's amendment names — *"no value assertion catches it; the totals are
internally consistent, they are simply computed over a row set missing one day."*
The QA leg that catches it must assert a row created **ON** the as-of date is
**INCLUDED**. A battery that only seeds-then-reads-at-a-past-date has the bug's
own blind spot built into its fixture.

Related: [[timestamptz-vs-date-excludes-the-as-of-day]] ·
[[scratch-db-full-chain-recipe]] ·
[[a-diff-of-two-outputs-proves-nothing-until-both-are-non-empty]] — the same
family: an empty result that reads as a clean one.
