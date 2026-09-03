---
name: self258-cashflow-contributor-map
description: 099 fn_cashflow_contributors design — the §2.3 staleness map carries NO verdict, and the §2.3.3 per-row indicator is structurally degenerate
metadata:
  type: project
---

SELF-258 AC4 asked for per-row staleness indicators on the §2.3.2 rollup and §2.3.3
drill-down. Drafted `099 pfin.fn_cashflow_contributors(p_as_of date)` as the exact `086`
analogue: DISTINCT `(cat, sub_cat, sub_cat_id, account_id, account_name)` composed on `093`'s
reader, **no staleness column**.

**Why:** the "single-sourced staleness predicate" requirement is satisfied by ZERO copies, not
by an extraction. `046` stays the sole home of the rule; `099` contains no staleness token at
all. The resolution path was already built — `099` → `resolveStaleAccountIds()` (exported from
`navComposition.ts` at SELF-330) → the Kleene-OR tri-state fold in `nonReAllocation.ts`. An
extraction is right when TWO producers must agree on one rule; here there is one.
`086` SHAPE 3 (rejected: DB-side per-Sub-Cat `is_stale`) is binding, and a per-row **stale-name
array** is the same defect in different clothes — an empty array cannot distinguish "none
stale" from "unresolved".

**How to apply:** when a new surface wants staleness, the default is a contributor map plus the
existing app-layer fold — not a new DB primitive that decides. Check whether the resolver
already exists before designing a hop.

**Measured finding → RULED. The §2.3.3 per-row indicator is DEGENERATE and is now OFF.**
`093` rule 2 stamps split children with the split PARENT's `account_id`, and `094` filters to a
single account — so every drill-down row has the SAME single contributor and the badge is
provably constant. Team-lead ruled the §2.3.3 per-row indicator OFF (default-and-notify,
ADR-063 D3, 2026-09-03, F/CTO-reversible at PR review); per-row renders on §2.3.2 only and the
drill-down keeps its section badge. The ruling lives in 099's header AND catalog comment,
because the consequence is a CONSUMER CONTRACT: §2.3.3 not calling the map per-row is the
ruling, not unfinished wiring.

**SHIPPED:** committed `35857d0` on `feature/self-258` (parent `8440a24`), blob md5
`78e469289a4e25484a586c30d1afe5d8`, 603 lines, one file. ⚠ At commit time that branch was
**local-only — not on origin** across all three of its commits, so origin-anchored checks read
as "never done". Sec joint-review + QA pairing were still owed.

⚠ **A ruling can falsify your own earlier header prose.** R3(b) closed with "recorded for the
AC, not decided here"; the ruling made the file assert a question was open while recording its
answer. When a routed question comes back decided, re-grep the draft for every sentence that
said it was open — including the catalog comment's opening, which had advertised §2.3.3 and
would have cost a migration to fix after merge.

Related: [[reference_account_trans_and_account_are_fenced_differently]] (the LEFT-join
fail-open and the third taxonomy state, both found while verifying this).
