# ADR-054 amendment — queued items (NOT the A9 PR)

Two supersessions to fold in when the ADR-054 amendment is written. Both are already
stated in `107`'s header; the amendment is where they become canon rather than a
migration's observation.

## 1. Decision 3's leaf source is superseded (E7)

ADR-054 Decision 3 names `051` / `fn_nav_composition` as the function that "already
emits per-account leaf values". True on 2026-08-12. `102` and then `105` replaced that
function so it now **anti-joins out every tax-authority-designated ledger**, while
`pfin.nav_daily.nav_value` keeps its GROSS definition and still includes them
(ADR-067 Decision 3, permanently).

    Sum(fn_nav_composition leaves) = nav_daily.nav_value − Sum(designated ledger balances)

So the ratified source would make the AC-6 reconciliation **false by construction**
for any user who has designated a ledger, and true for everyone else — presenting as a
data bug rather than a source-selection bug. **The correct source is `049`
`fn_account_unrealized_gl(as_of).current_market_value`**, the single leaf substrate
`fn_nav_composition` itself composes on, whose sum IS `fn_compute_nav(as_of, true)`
exactly (ADR-038 / ADR-039).

⚠ **Amend, do not rewrite.** Decision 3's sentence is a dated record and was true of
its date. The amendment sits beneath it and names the two later migrations that moved
the referent.

⚠ **Why the wave's own coherence check missed it, which is the reusable half:** the
AC carried an explicit post-V1.4 coherence note checking A9 against `105`, and that
check was **sound** — it checked the **definition** axis ("A9 never renders, so it
cannot drift from 105's NAV definition"). The **leaf-set** axis is a different axis. A
coherence note that names the right later artifact still only covers the axis its
author was thinking about.

## 2. Decision 2 bullet 3 gets a carve-out

Decision 2's third bullet reads that the two series "should be able to fail
independently — a component-capture bug must not be able to corrupt or **block** the
scalar NAV checkpoint."

**The "block" clause is SUPERSEDED for the WRITE TRANSACTION by AC 2**, which requires
the leaves to be written in the same transaction as the scalar row. Same transaction
means a leaf-side raise **does** roll back that tenant's scalar checkpoint for that
day, and that is accepted rather than worked around: same-transaction is what makes
Σ(leaves) = scalar true **by construction**, which is the property AC 6 asks QA to
watch. Split the transaction and the reconciliation stops being a property.

**The clause SURVIVES for the SURFACE**, which is what Decision 2's three bullets are
actually arguing about — they are all arguments against widening `054`'s table. A
sibling table can be dropped, re-shaped, or have its writer removed without touching
`054`'s DDL; a column on `054` could not fail independently in any sense, because it
would be the same row.

**The residual is real and should not be argued away in the amendment:** a leaf-side
raise loses that tenant-day's scalar checkpoint. `107` minimises the ways the leaf side
can raise — five paths, four of which are fences that MUST raise — but does not and
must not reduce them to zero.
