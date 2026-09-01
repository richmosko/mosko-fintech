---
name: rows-frame-satisfies-the-count-across-a-gap
description: A ROWS window frame counts ROWS, so a "12 constituents present" guard passes across a calendar gap and yields a silently-short average; RANGE over an integer month ordinal is the fix.
metadata:
  type: reference
---

`count(*) over (order by x rows between 11 preceding and current row) = 12` is
**not** a check that twelve consecutive periods are present. It counts rows. Across
a gap it happily spans fifteen calendar months and still returns 12 — so the guard
fires green and the "12-month average" is a wrong number wearing a correct name.

**Measured (096, 2026-08-30):** month ordinals 1..11 then 25. At ordinal 25 the
ROWS frame counted **12**; a `RANGE between 11 preceding and current row` over the
same ordinal counted **1**, so the guard NULLed the row. Same data, opposite verdict.

**Use RANGE over an INTEGER period ordinal** (`year*12 + month`), not ROWS and not a
`range ... interval '11 months' preceding` on dates — an interval offset is subject
to Postgres' end-of-month clamping (Jan 31 minus 11 months lands on Feb 28), so a
frame edge can move for calendar reasons. Integer arithmetic cannot.

⚠ **Density and the frame are two fences over one hazard, not one fence twice.**
Emitting a dense grid makes the gap not happen; RANGE makes a gap *detectable* if it
ever does. Dropping either because "the other covers it" removes a watcher — see
[[feedback_structural_fence_must_cover_the_same_class]].

Related: [[feedback_watcher_not_fence_for_by_construction_properties]] ·
[[feedback_inversion_test_the_rationale_not_the_presence]] (the ordinal-25 probe
above IS that inversion — the rationale was proven, not asserted).
