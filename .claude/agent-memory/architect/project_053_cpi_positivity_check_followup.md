---
name: 053-cpi-positivity-check-followup
description: The cpi_value positivity CHECK now has a tracked home in BACKLOG §7.14 with Sec's four binding conditions — read it there, not here
metadata:
  type: project
---

**`pfin.cpi_u_index.cpi_value` (migration `053`) is fenced finiteness-only**, so a
poisoned `0` / negative print reaches the deflator. `067` guards internally (both CPI
legs strictly positive, else NULL); the base table holds no fence of its own.

**⚠ CANONICAL HOME: `BACKLOG.md` §7.14** — "SELF-217 / SELF-218 build-day follow-ups",
landed in PR #446, carrying Sec's **four binding conditions**. **Read it there.** This
note is a pointer, not a copy: two homes drift and hand the reader two versions.

**Why the pointer exists at all** — two things a future reader will otherwise get wrong,
and one is a correction to what I originally recorded:

- **⚠ `> 0` ALONE IS NOT ENOUGH, and my first framing of this was too narrow.** I flagged
  only NaN; Sec established the predicate must be **finite AND strictly positive**,
  because in Postgres numeric ordering **both `NaN > 0` AND `Infinity > 0` are TRUE.**
  A positivity CHECK written as a replacement would re-admit *both*.
- **The CHECK must be ADDITIVE** to `cpi_u_index_value_finite`, which survives by name.
  Never a replacement.

**Also worth carrying, because it is the inverse of a fact easy to file as reassurance:**
Sec's condition 3 requires the same PR to `create or replace` `067`'s guard with an
explicit NaN clause **and re-issue its `comment on`** — precisely *because* create-or-
replace **preserves** comments, so `067`'s DIVISION SAFETY paragraph would otherwise
describe a guard the function no longer has. **The same property that makes
create-or-replace safe for ACLs makes it a staleness hazard for comments** — see
[[prove-derived-text-against-its-source]] and the safety-proof-is-a-hazard-notice shape.

**How to apply:** if this comes up, go to §7.14 first and treat its four conditions as
binding; joint-review is mandatory when it lands (a financial-correctness constraint on
the divisor of an inflation-adjusted figure).
