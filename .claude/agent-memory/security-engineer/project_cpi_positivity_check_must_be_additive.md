---
name: cpi-positivity-check-must-be-additive
description: The recorded pfin.cpi_u_index positivity-CHECK follow-up must ADD to cpi_u_index_value_finite, never replace it — NaN > 0 is TRUE in Postgres, so a replacement silently re-admits NaN into a financial figure
metadata:
  type: project
---

The open follow-up to add a positivity CHECK on `pfin.cpi_u_index.cpi_value` **must be additive to the
existing `cpi_u_index_value_finite` constraint, never a replacement.** Raised as a Sec flag at the
SELF-218 / migration `067` joint-review (2026-08-12); not yet placed in a tracked artifact at that
time — confirm it landed somewhere durable before relying on this.

**Why:** `053` fences finiteness only (`cpi_value <> 'NaN' and <> 'Infinity' and <> '-Infinity'`), and
`067`'s deflator guards with `cpi_value <= 0`. In PostgreSQL numeric ordering **NaN compares greater
than every non-NaN value**, so `NaN <= 0` is FALSE and `NaN > 0` is TRUE. The two fences are
complementary and *neither alone is sufficient*: a positivity CHECK written as `check (cpi_value > 0)`
that supersedes the finiteness constraint re-admits NaN, which then sails through `067`'s guard and
renders as `nav_inflation_adjusted = NaN` — a financial figure, not a NULL. The migration header's own
parallel instruction (keep the zero-CPI QA leg after the CHECK lands rather than retiring it as
unreachable) is the same shape of hazard.

**How to apply:** if a migration touching `pfin.cpi_u_index` constraints reaches review, check the
finiteness constraint survives by name. Four conditions given to team-lead 2026-08-12 for whatever
vehicle carries the fix: (1) the guard predicate must be **finite AND strictly positive** on both CPI
legs — `Infinity > 0` is TRUE too, and an infinite denominator fabricates a `0` adjusted figure while
an infinite numerator fabricates `Infinity`, so neither `<= 0` nor `> 0` suffices alone; (2) additive,
never a replacement; (3) a `create or replace` **preserves the catalog comment**, which is the hazard
not the reassurance — the DIVISION SAFETY paragraph must be re-issued or it describes a guard the
function no longer has; (4) once finiteness holds, a NaN print is un-seedable, so the QA leg must drop
the constraint inside a savepoint (the corrupt-the-control idiom the 067 battery already uses on
`nav_daily_select`) or it cannot exist at all.

Sec position on sequencing: the hardening is **no-later-than-mandatory**, not same-PR-mandatory — it
is independently correct today and better landing earlier. More generally on this codebase: a
numeric-comparison guard is never a NaN guard — see [[measure-the-fence-regex-not-its-comment]] for
the same claimed-coverage-vs-actual-coverage failure class.
