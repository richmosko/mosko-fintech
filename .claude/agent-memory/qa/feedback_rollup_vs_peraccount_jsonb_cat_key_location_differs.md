---
name: rollup-vs-peraccount-jsonb-cat-key-location-differs
description: fn_cashflow_cross_account_rollup's jsonb sections carry `cat` on the SECTION object; fn_cashflow_per_account's sections carry `cat` only on each ROW object (section_key groups multiple cats). Writing `s ->> 'cat'` for both is a real bug that silently NULLs one side of a parity EXCEPT check.
metadata:
  type: feedback
---

Drafting 099's P2 parity legs (contributor map vs `fn_cashflow_per_account`), I copied the P1
legs' `(s ->> 'cat'), (row ->> 'sub_cat')` shape verbatim from the P1 (rollup) legs. It's WRONG for
P2: `fn_cashflow_cross_account_rollup`'s sections are one-per-cat (`{"cat":"Expense","rows":[...]}`
— section object itself carries `cat`), but `fn_cashflow_per_account`'s sections are one-per
**section_key** (`income`/`other_cash_flows`/`expenses` — `other_cash_flows` spans BOTH Transfer
and Equity), so `cat` only exists on each individual ROW object there, not the section.

`s ->> 'cat'` against a per_account section object silently returns NULL (no error — jsonb `->>`
on a missing key is just NULL) rather than failing loudly, so the parity EXCEPT legs came back
"have: 6 want: 0" on BOTH directions — looked like a total non-overlap, not an obviously-wrong-key
bug, and required an actual side-by-side raw-query debug session (not just re-reading the SQL) to
spot: the CONTRIBUTOR side printed real `(cat, sub_cat)` pairs, the PER_ACCOUNT side printed
`(NULL, sub_cat)` for every row.

**How to apply:** never assume two "same family" jsonb-returning functions share a shape just
because they're siblings in the same migration arc — check where each ACTUALLY nests `cat`
(section-level vs row-level) before writing a cross-function parity leg, by reading the real
`jsonb_build_object` calls in both migration files, not by pattern-matching the previous leg's
query shape. [[reference_postgrest_two_tenant_vitest_pattern]] (a related "check every field
before reusing a working pattern" lesson, different surface).
