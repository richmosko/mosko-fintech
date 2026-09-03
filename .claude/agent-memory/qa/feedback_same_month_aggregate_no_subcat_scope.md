---
name: same-month-aggregate-no-subcat-scope
description: fn_historical_expenditures (096) aggregates by MONTH and cat/is_tax_payment ONLY — it does not scope by sub_cat. A new fixture row added for an unrelated leg (a different function's created-ON-D proof) silently inflated an EARLIER leg's month total by exactly its own amount, caught only by re-running pg_prove, not by inspection.
metadata:
  type: feedback
---

Adding SELF-257's D19-distributive leg for `fn_cashflow_contributors` (099), I dated its fixture
item in June 2026 (same month as an EARLIER, unrelated leg's Groceries257 fixture). The new item
was classified 'Expense' but a DIFFERENT sub_cat (`CreatedOnD257`) — I assumed a different
sub_cat meant no interaction with the earlier leg's assertion. Wrong: `fn_historical_
expenditures`'s `qualifying` CTE filters on `i.cat = 'Expense' and pp.is_tax_payment = false`
only — no `sub_cat` scoping at all, because it's a WHOLE-HOUSEHOLD MONTHLY TOTAL, not a
per-Sub-Cat figure. The new item's -20 silently added to the SAME month's total another,
earlier-authored leg asserted an exact value for, producing "have: 100 want: 80" on the FIRST
pg_prove run after adding it — a real, measured regression in a leg I hadn't touched, caused by a
fixture addition three blocks away.

**How to apply:** before dating a NEW fixture row in any MONTH/YEAR that an EARLIER leg in the
SAME file already asserts an exact aggregate total for, check whether the function under test
scopes by the dimension you think isolates you (sub_cat, account, etc.) — for a whole-household
MONTHLY total like 096's, dating in a DIFFERENT month is the only isolation that actually works;
picking a "different Sub-Cat" is not a form of isolation for that specific function. Re-run
pg_prove after ANY new fixture row, even one that looks unrelated to every other assertion in the
file — this is exactly the failure mode a full re-run (not "I only added a leg near the bottom,
the earlier ones can't have changed") is for.

Related: [[feedback_new_fence_can_encode_old_bug_into_existing_fixtures]] — the same "a change
in one place breaks an assertion elsewhere, invisible without a real run" shape, different cause
(there: a NEW FENCE refusing an old fixture's write; here: an aggregate function's total silently
absorbing a new fixture row with no fence involved at all).
