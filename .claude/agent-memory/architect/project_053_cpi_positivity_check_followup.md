---
name: 053-cpi-positivity-check-followup
description: SHIPPED at 095 (SELF-343) — cpi_u_index_value_positive_finite is additive to cpi_u_index_value_finite; the residual open item is two catalog comments 095 falsified, owned by team-lead
metadata:
  type: project
---

**STATUS 2026-08-29: SHIPPED.** Migration `095_cpi_u_index_positivity_and_deflator_guard.sql`
(SELF-343, branch `feature/self-343`) discharged BACKLOG §7.14's first entry — Sec's four
binding conditions, all four. Sec review returned AMBER; both AMBER items landed in the
same file. ⚠ **Grep the migrations before believing any later note that says this is
unbuilt** — the §7.14 entry itself is not self-updating.

What shipped, in the shape that matters if you touch this family again:

- **`cpi_u_index_value_positive_finite`** on `pfin.cpi_u_index.cpi_value`:
  `> 0 AND <> 'NaN' AND <> 'Infinity'`. **A bare `> 0` re-admits NaN and +Infinity** —
  numeric ordering puts both ABOVE every finite value. `-Infinity` needs no clause; it
  sorts below and `> 0` rejects it.
- **ADDITIVE.** `cpi_u_index_value_finite` survives by name. The overlap is deliberate:
  three read surfaces (`067` / `071` / `073`) justify their own `> 0` guards by naming the
  FINITENESS constraint, so dropping it as redundant would silently unsound all three.
  ⚠ And the older name sorts first, so it is the one that REPORTS —
  see [[check-violation-reported-in-constraint-name-order]].
- **`067`'s deflator guard** gained explicit NaN and +Infinity clauses on both CPI legs,
  and its `comment on function` was re-issued in the same migration. **create-or-replace
  preserves BOTH the ACL and the comment** — the first is why no grant is re-issued, the
  second is why the comment MUST be.

**⚠ RESIDUAL, OWNED BY TEAM-LEAD (do not re-raise as new):** `095` falsifies the stated
premise of two live catalog comments — on `pfin.fn_nav_delta_panel` (live text issued by
**`072`**, which drop-and-recreates it, NOT `071`) and on `pfin.fn_nav_reference_dates`
(`073`). Both still say *"053 bars NaN and the infinities but NOT zero or negative
values."* Their conclusions stay true; only the premise moved. Ruled **book-not-fold**;
team-lead writes the BACKLOG §7 entry, with Sec's F2 addition folding `064`/`066` file-header
prose into the same booking. Recorded in `095`'s own header as the tracked-bytes half.

**How to apply:** any future change to EITHER finiteness CHECK in this family inherits
condition (2) verbatim — additive, survives by name, never a replacement. That widening
names `054`'s `nav_daily_value_finite` too, which is what makes `071`'s `v_a_nav > 0`
complete. Joint-review is mandatory: it is a financial-correctness constraint on the
divisor of an inflation-adjusted figure.
