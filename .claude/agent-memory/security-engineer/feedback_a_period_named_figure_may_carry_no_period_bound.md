---
name: a-period-named-figure-may-carry-no-period-bound
description: A figure whose NAME asserts a period (YTD, MTD, quarterly, annual) may be implemented as a balance-as-of with no lower bound — check the body for the period floor, and check whether anything drains the accumulator
metadata:
  type: feedback
---

When a money figure's name asserts a **period** — "YTD Paid", "monthly spend", "quarterly
obligation" — verify the body actually carries a **lower** bound, not just the upper one. A
`balance as of p_as_of` composed from a checkpoint + `transaction_date <= p_as_of` roll-forward has
**only an upper bound**. It is cumulative since inception, and the period in the name is a claim the
code does not make.

**Why:** at SELF-267 (`102 fn_ytd_paid_per_jurisdiction`) I nearly signed off on a figure named
year-to-date that returns the designated tax-ledger's balance since account inception. The
balance-as-of shape was correctly F/CTO-ruled (sitting-log R8 rider, "NOT re-opened"), so the shape
was not the defect — the defect was that **nothing anywhere stated the consequence**. From tax year
2 onward the figure carries prior years' payments forward: overstates YTD Paid → understates Funds
Due → under-reserve, the silent direction. The `comment on function` answered *what a payment IS*
exhaustively (sign / refund / inbound transfer / correction / clamping / why-not-`is_tax_payment`)
and never answered *what the YEAR is* — which is [[feedback_enumeration_and_watcher_stop_one_short]]
at comment grain, and reads to the next reader as **asked and settled** in exactly the way ADR-062
Decision 2 warns a `false` on an out-of-scope row does.

**How to apply:**
- Read the body for the period FLOOR. `>= date_trunc('year', …)`, a `p_year` param, a
  `generate_series` start — if none is there, the name is wider than the function.
- Then ask the second question, which is the one that decides severity: **does anything drain the
  accumulator at the period boundary?** A cumulative ledger is harmless if a settle/close/transfer
  path zeroes it each period. Grep for one. At SELF-267 there was none, *and* a partial unique index
  (`one ledger per authority per user`) actively prevented the user from opening a fresh one per
  year — so the carry-forward was not merely possible, it was unavoidable.
- **Do not re-open a ruled shape.** If the shape is F/CTO-ruled, the finding is a
  **flag on the record, not a veto on the design**: require the consequence be stated in the
  `comment on function`, where the next reader looks. On a migration that is a **pre-merge-only**
  fix — a merged migration's comment can only be changed by emitting a new one, which is the same
  reason the PR was already rewriting `051`'s stale identity comment rather than deferring it.
- Bundle every comment/header-text finding into ONE pre-merge edit for the migration's owner
  (Architect). They share a fix window and splitting them costs a dispatch.
