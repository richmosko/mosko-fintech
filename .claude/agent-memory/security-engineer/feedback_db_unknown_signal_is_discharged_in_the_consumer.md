---
name: db-unknown-signal-is-discharged-in-the-consumer
description: A DB-layer NULL-as-UNKNOWN signal (LEFT join over a differently-fenced relation) is fail-closed only if the consumer's fold tests it BEFORE its membership test — read the shipped sibling fold, which usually resolves unknown to FALSE.
metadata:
  type: feedback
---

When a migration defends a fail-open by emitting an **UNKNOWN signal** rather than by
filtering (e.g. `LEFT join` to a relation fenced by a *different* predicate, so a
non-visible row yields `NULL` instead of vanishing), the DB half is only the *carrier*.
**The property is discharged in the consumer.** Rule the shape OK, then immediately
open the shipped sibling fold and check the ORDER of its tests.

**Why:** measured at `099_fn_cashflow_contributors` (SELF-258). The LEFT join keeps an
invisible contributor PRESENT with `account_name IS NULL` — correct, and strictly better
than `086`, which drops it. But the fold the migration header points at as "already built
and ratified" is `subCatIsStale` (`api/src/lib/server/queries/nonReAllocation.ts`), which
answers `false` for any account_id not in `staleAccountIds` — and that Set is built by
`resolveStaleAccountIds` (`navComposition.ts`) from an **RLS-scoped** read of
`pfin.account`, so an account invisible to the caller can never be a member. Written by
analogy — which is exactly what "the path is already built" invites — the new fold turns
the DB's UNKNOWN straight back into FRESH: the same three-states-into-two collapse the
ruling rejected, one layer down. The join is honest; the pipeline is not.

**How to apply:**
- Two separable rulings. *Is the signal the right shape?* (usually yes — a second
  boolean column can disagree with the first). *Is anything folding it?* — a separate,
  usually-unmet condition. Say both; do not let the first imply the second.
- The catch criterion is **ordering**, not presence: the `x === null → UNKNOWN` branch
  must run **before** the `set.has(x)` membership test, structurally mirroring whatever
  short-circuit a prior review already required (here, `staleAccountIds === null`).
  A guard placed only inside the loop is the same defect this project already ate once.
- Grep the sibling consumer whose gap the new surface fixes: it usually still HAS the
  gap, dormant on the same revival condition. That is a BACKLOG note, not scope creep.
- The signal's unambiguity is a **schema invariant with no watcher** (here
  `pfin.account.name` NOT NULL). `col_not_null` is already an idiom in the pgTAP
  battery family — one cheap leg. Grade its failure DIRECTION before choosing severity:
  losing the invariant here reads visible-but-unnamed as UNKNOWN, which is fail-CLOSED,
  so it is a flag, not a veto.

Related: [[verify-the-stated-correctness-mechanism]] ·
[[shared-predicate-then-second-narrowing]] · [[zero-value-sentinel-flips-meaning]] ·
[[a-red-whose-message-names-the-wrong-defect]]
