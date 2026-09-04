---
name: nav-is-top-level-not-under-buildups
description: pfin.fn_nav_composition's returned JSONB has `nav` as a SIBLING key of `buildups`, not nested inside it — a first query nesting r->'buildups'->'nav' silently returns NULL rather than erroring, and reads as "nav broke" when it's a query-shape mistake.
metadata:
  type: feedback
---

Querying `pfin.fn_nav_composition(current_date)` for a SELF-268 re-confirm, my first attempt read `r->'buildups'->>'nav'` and got a blank/NULL result — looked exactly like a real regression (nav had gone missing). The function's own `comment on function` states the shape precisely: `{groups:[...], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, nav}` — `nav` is a top-level key alongside `buildups`, not inside it. Fixed by using `r->>'nav'` directly.

**Why:** JSONB path traversal into a missing key returns NULL rather than erroring, so a wrong nesting assumption is silently indistinguishable from "the value is actually absent" until you re-read the contract comment.

**How to apply:** before trusting any "value looks null/missing" result from a JSONB-composition function, re-read its `comment on function` CONTRACT block for the exact key nesting rather than assuming a plausible shape.
