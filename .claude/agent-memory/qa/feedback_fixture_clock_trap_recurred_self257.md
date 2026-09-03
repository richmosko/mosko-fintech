---
name: fixture-clock-trap-recurred-self257
description: The fixture-clock trap (created_at defaults to real wall-clock now(), not transaction_date) cost a full debugging round on SELF-257 despite being a NAMED standing trap in the dispatch brief — recurred because I picked an as_of BEFORE the real wall-clock date. Also documents 096's OWN distinct window trap (current-incomplete-month exclusion) discovered while fixing it.
metadata:
  type: feedback
---

SELF-257's dispatch brief named "fixture-clock (seed AND assert at the server's current_date)"
as a standing trap up front — and I still lost a full debugging round to it. Picked
`as_of = '2026-06-15'` for the shared fixture without checking it against the real wall-clock
date (2026-09-03 at the time). Every `account_trans` row's `created_at` defaulted to real
`now()` (~2026-09-03), and the reader's rule 6 (`created_at < (p_as_of + 1)`) silently excluded
EVERY seeded row because `2026-09-03 < 2026-06-16` is false. Every reader-composed function
returned the empty set for every leg — looked exactly like a real cross-tenant isolation bug
(zero rows is what you'd ALSO see if isolation were somehow inverted), and took several
`docker exec` probes (checking account_users grants, RLS policies, `auth.uid()`, direct table
visibility) before landing on the actual culprit: `and t.created_at < (b.d + 1)` in the reader's
own dumped `pg_get_functiondef`.

**The fix that actually works, not just "be careful": explicitly set `created_at` on every
`account_trans` INSERT to a literal tied to `transaction_date`, never relying on the column
default.** This makes every leg's expected result independent of when the battery is ever run —
the SAME discipline 093's own L15a/b/c legs already use, which I read earlier in the SAME
session and still didn't generalize to my OWN fixture until it broke.

**A SECOND, DISTINCT clock-adjacent trap found while fixing the first:** `pfin.fn_historical_
expenditures` (096) excludes the CURRENT INCOMPLETE MONTH relative to its own `p_as_of` — its
window's `ms_last` is the last COMPLETE prior month, and its `anchor` CTE computes
`ms_first = min(monthly.ms)` where `monthly` only contains items inside `[ms_floor, ms_last]`;
if NO item survives that filter, `ms_first` is NULL and `generate_series(NULL, ...)` emits
**zero rows total** — not just a missing month, the ENTIRE 60-row series vanishes. Seeding an
item dated in the SAME month as `p_as_of` (matching 093/094's own convention, where the current
partial month IS included) silently fails this OTHER surface's window rule. Fix: for 096-specific
legs, use a LATER `as_of` so the target month becomes a genuine complete prior month (e.g. query
at `d_asof + 1 month` when the fixture item is dated in `d_asof`'s own month).

**How to apply:** (1) never trust a chosen `as_of` against `created_at` defaults — pin
`created_at` explicitly, always, on every fixture row in every future §2.3-family battery.
(2) 096 and 093/094 do NOT share the same "which month counts" rule — 093/094 include the
current partial period, 096 does not. Don't reuse ONE `as_of` across both without checking each
function's own window semantics first.
