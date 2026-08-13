---
name: 053-cpi-positivity-check-followup
description: pfin.cpi_u_index.cpi_value has no positivity CHECK — zero/negative prints are admissible and 067 only routes around it; needs its own migration
metadata:
  type: project
---

`pfin.cpi_u_index.cpi_value` (migration `053`) is fenced by
`cpi_u_index_value_finite`, which bars **NaN and ±Infinity only**. It does **not**
bar zero or negative values, and the column is `NOT NULL`, so a poisoned `0` or
negative print is admissible today.

**Why:** surfaced 2026-08-12 while authoring `067`
(`fn_nav_series_inflation_adjusted`), whose deflator divides by the point-period
CPI level. An unguarded ratio would raise `division by zero` on a `0` print —
violating SELF-218's never-throw AC through a path no existing fence closes — and a
negative print would silently flip the sign of a net-worth figure, which is worse
than an error.

**How to apply:**
- `067` **routes around it**, it does not fix it: the ratio is computed only when
  both CPI legs are strictly positive, else `nav_inflation_adjusted` is NULL. That
  guard is correct with or without the CHECK.
- The authoritative repair is a `cpi_value > 0` CHECK on `053`. **It cannot be done
  by editing the merged file** (that is SQL, not a `--` header comment — see the
  apply-migration Step 1.6 vehicle rule) and it touches a table the ETL writes, so
  it needs its own migration and its own review.
- ⚠ When that CHECK lands, **keep** the paired QA leg that asserts a zero print
  yields NULL rather than a raise. It becomes unreachable-by-construction, which is
  a reason to keep it — deleting it is how the guard silently stops being tested if
  the CHECK is ever relaxed. This instruction is also written into `067`'s header.
- **Verify before acting:** grep `053` and any later migration for a positivity
  constraint on `cpi_value` — this may have landed since. As of 2026-08-12 it had
  not, and it had no tracked home beyond `067`'s header and a commit message.

Related: [[fixture-is-shared-state]]
