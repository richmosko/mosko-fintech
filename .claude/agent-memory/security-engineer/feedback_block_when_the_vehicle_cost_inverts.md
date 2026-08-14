---
name: block-when-the-vehicle-cost-inverts
description: Block on a return-shape/DDL decision at the pre-merge gate when fixing it later costs a drop-and-recreate — and treat an assigned-but-never-read local as evidence of an intended-but-dropped output column
metadata:
  type: feedback
---

A finding that is only *disclosure-shaped* (not isolation- or privilege-shaped) can still justify
blocking **when the cost of acting on it inverts at merge.** In this repo `066` and `067` both record
that changing a function's return post-merge is a drop-and-recreate that takes the ACL and the catalog
comment with it, plus Sec re-review, plus F/CTO ratify, plus a re-granting migration. Free before,
expensive after. **State the blocking condition as "a RULING must be taken", not "the column must be
added"** — that keeps the decision with F/CTO where it belongs while still forcing it into the window
where it is cheap.

**Detection technique that found it:** an **assigned-but-never-read local** is evidence of an
intended-but-dropped output. At SELF-221, `071` declared `v_cur_cp` ("checkpoint that served the
current endpoint"), assigned it, and never used it — while returning the *anchor's* checkpoint. Grep
each declared local for a second occurrence; a `SELECT … INTO` with no reader is a dropped column, not
dead code to tidy.

**The framing that made it a real finding rather than a nit:** ask which side of an asymmetry carries
the ANOMALOUS case. Carry-forward on an anchor is expected and was disclosed; carry-forward on the
current endpoint means the cron has stopped and was not. **The disclosed one was the boring case.**
`062` calls `checkpoint_date` "THE DETECTABILITY MECHANISM"; `067` forwards it for that reason; ADR-013
is the non-silent-staleness framework — so dropping it on a financial surface is a live-state
disclosure gap, not a missing nicety.

Related: [[zero-value-sentinel-flips-meaning]] (the other silent-staleness route),
[[measure-the-fence-regex-not-its-comment]].
