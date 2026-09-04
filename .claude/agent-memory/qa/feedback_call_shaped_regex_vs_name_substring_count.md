---
name: call-shaped-regex-vs-name-substring-count
description: Proving a function calls another EXACTLY ONCE by counting a name's textual occurrences in prosrc over-counts when a header/inline SQL comment also names the callee in prose; use a call-shaped regex (name immediately followed by an open paren) instead.
metadata:
  type: feedback
---

At SELF-268/105 (2026-09-04), proving `fn_nav_composition` calls
`fn_compute_tax_liability` exactly once (Sec P-16 — "one CTE, both readers",
because the planner MAY fold two identical STABLE calls but "may" is not a
control): a bare substring count —
`length(prosrc) - length(replace(prosrc,'fn_compute_tax_liability',''))`
divided by the name's length — measured **2**, not 1. The second hit was a
prose mention inside the function's OWN inline SQL comment ("...the clamp's
WHY lives in fn_compute_tax_liability's `comment on function`...") — `prosrc`
includes comment lines inside the `$$...$$` body verbatim, so a substring
count cannot tell a call from a citation.

Fix: `regexp_matches(prosrc, 'fn_compute_tax_liability\s*\(', 'g')` — the name
immediately followed by an open paren — measured **1**, correctly isolating
the real call. Verified both numbers on the same body before writing the leg,
and stated the discrepancy (2 vs 1) directly in the leg's own comment so the
choice of regex over substring reads as deliberate rather than coincidental.

**How to apply:** any "calls X exactly N times" pgTAP leg over `prosrc` needs
the call-shaped form, never a bare substring/count, the moment the function's
own header or inline comments are likely to name the callee in prose (which
this repo's migrations do constantly, by convention).
