---
name: monthly-report-snapshot-vs-recompute-owd
description: ⚠ ONE-WAY DOOR — PRD §2.6.4 freezes RENDERED VALUES while Lock 11 locks read-time recomposition; four of six report sections CANNOT be recomputed as-of, because Lock 14 settings carry no edit history.
metadata:
  type: project
---

**The V1.5 monthly report is specified as a frozen artifact and architected as a read-time recomposition, and on this schema those cannot be reconciled.** Raised as Seam S-1 at the V1.5 pre-flight (2026-09-04, baseline `b90b846`); ruling owed from F/CTO.

PRD §2.6.4 φ-1 verbatim: *"later views of the 'April 2026 report' show the values that rendered the day April 2026 was generated"*; its snapshot commitment is **"rendered-value level, not source-data-level."** ADR-011 Decision 15 / Lock 11 (2026-05) locked **read-time composition** and named a join set including `pfin.nav` — **a table that does not exist**; the tree carries `nav_daily` + `fn_compute_nav`/`fn_nav_composition`.

**Why recomposition structurally fails, four ways — none is a preference:**

1. **Asset Allocation.** `% / $ Target` and `$ ReAlloc` read `planning_target` (`074`). ADR-011 Decision 18 / Lock 14: *"UPSERT-in-place … **no edit-history rows** (settings NOT audit-class)"* — reaffirmed at the 2026-08-16 family-size amendment. A `%Target` edited today rewrites every historical report. **There is no as-of read because there is no history to read.**
2. **Estimated Taxes.** `fn_compute_tax_liability` (`104`) resolves the current-year schedule else the latest prior year, off `tax_bracket_schedule`/`_row` (`101`) — also Lock 14, also no history. `basis_year` shifts underneath the reader.
3. **§2.1.5 tax lines.** `105` subtracts two envelopes from `104`. ADR-067 Decision 3: *"the tax state for a past date is not recoverable, so a back-fill would be a fabrication with the shape of a measurement (Sec veto)."* **Recomposing a past month's tax lines from today's designations reaches exactly that vetoed artifact by another route.**
4. **Labels.** `082` renamed the Cat `Equity` → `Marketable Securities`; a pre-`082` month recomposed today renders the new label.

⚠ **Lock 15's dual-column filter DOES reproduce `account_trans` as-of, so Cash Flow and the gross half of Account Holdings recompose faithfully. The failure is partial — which is why it will not announce itself.**

**Why one-way door:** once reports ship and are archived, changing the answer means either admitting they were never frozen, or a migration manufacturing values whose settings history was never recorded.

**How to apply:** lean was **freeze the rendered payload on the header at finalization** (`rendered_payload JSONB` + a `payload_schema_version SMALLINT` — the column `nav_daily` conspicuously lacks and pays for). ⚠ **This does not touch Lock 14's no-JSONB fence, which governs the SETTINGS store**; the `101` amendment already draws that line for `p_rows jsonb`. Losing side: the payload shape becomes a permanent compatibility surface. Also: P2's drafted AC asserted *"historical reports immutable post-final per Lock 11 mod #2"* — mod #2's immutability is a property of the **row**, and nothing freezes the **values** that assertion is invoked to guarantee. See [[reference_lock_join_lists_are_dated_artifacts]], [[project_prd_predates_gl_recalibration]], [[reference_nav_definition_flip_is_a_oneway_door]].
