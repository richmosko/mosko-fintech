---
name: tax-ledger-rollover-has-no-safe-drain
description: The V1 tax-authority-ledger rollover (close, clear, re-designate) has no executable first step and no NAV-safe drain — 058 refuses to close a funded account, and emptying by transfer puts the money straight back into the NAV leaf set
metadata:
  type: project
---

`102` designates one account per tax authority as that authority's ledger; the
designated ledgers leave `fn_nav_composition`'s §2.1.5 leaf set, so payments do not
inflate NAV. The V1 rollover was ruled (E19 as corrected, 2026-09-04) to be **close the
old ledger → clear its designation → designate a fresh one**, because clearing alone
returns the ledger to the leaf set *immediately* (live read, not a latch; `102`'s battery
proves the reversion at L3i/L3j) and NAV rises by every payment ever made to that
authority.

Two things that ruling does not close, both measured:

1. **Step 1 is refused by the database on exactly the accounts it is about.** `058`'s
   close gate leg 2 of 3 raises `account closure blocked: account % holds a non-zero cash
   balance`. A designated ledger's balance IS the accumulated payments, so it cannot be
   closed until it is drained. I put this precondition in the `102` comment (commit
   `6b973bf`) rather than ship a first step the DB rejects.
2. **There is no NAV-safe drain.** Emptying the ledger by transferring the cash to another
   owned account lands it on a leaf that IS in the leaf set — NAV rises by the same amount
   as clearing would. The only drain preserving the invariant is one that removes the cash
   without landing it on another owned leaf (an ordinary Expense-class manual row).
   Sec's C1 wording says "empty **or** close", which reads as two equivalent options; under
   `058`, close ⊃ empty, and only one kind of empty is correct.

**Why:** the whole point of `102` is the §9.1 / PM A-9 double-count. The ONE rollover path
V1 ships re-enters it silently, in the NAV-overstating direction.

**How to apply:** the settle/drain affordance is a booked product call — route to PM, not
to schema. If anyone proposes a year-boundary rollover UI, the first question is which
drain it performs. Related: [[nav-definition-flip-is-a-oneway-door]].
