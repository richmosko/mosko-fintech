---
name: triage-a-multileg-bypass-leg-by-leg
description: A handed-over bypass finding listing N uncovered legs frames them as equivalent — measure each leg's READ-side reachability separately; usually most are inert or already fenced and one is live, and the live one is often reachable through the shipped UI, not through the bypass the finding names
metadata:
  type: feedback
---

**Rule: when a finding says "rules A/B/C/D are all uncovered on path X", do not accept the
enumeration's uniform framing. Measure each leg against the READ side separately** — the
consumer that would actually act on the bad write — and re-grade the finding by what the
survivors are.

**Why:** SELF-248 / PR #561. Backend handed over *"M1/M2/M4/E1 remain silently
mis-categorizable through the old `recategorize` action."* Measured leg by leg against
`084`'s `fn_gl_entries`:

- **M1** (`transaction_type <> 'standard'`) and **M4** (`split_count > 0`) — **inert**.
  Excluded by the P3 contra branch's own `where`, so the classification is never read. A
  fence over them would refuse a write that costs nothing.
- **M2** (`security_id IS NOT NULL`) — **already DB-fenced** by `084`'s
  `(security_id is not null) <> (cat = 'Trade')` biconditional.
- **M3** (journaled) — fenced by the migration under review.
- **E1** (`is_reverse = true`) — **neither.** P3's `where` has no `is_reverse` term and the
  upstream `txn` CTE has none either, so a classified reversal's contra resolves through the
  ordered CASE to Revenue/Expense/Equity.

Four "equivalent" legs collapsed to **one** live money defect. The finding's own framing
would have had F/CTO weighing a four-leg retrofit; the actual decision was a one-line
refusal. **Grading a bypass by how many gates it skips over-states it; grading it by what
the reads DO with the bad value is the real severity.**

**⚠ THE HALF THAT MADE IT WORSE, AND IT IS THE REUSABLE HALF: the live leg was reachable
through the shipped UI, not through the bypass the finding named.** `TransactionRow.svelte`
gates its row actions on `{#if !frozen}` only — the reversal tag beside it is display-only —
so the "Categorize" control renders on `is_reverse` rows and posts to the ungated action.
The finding was framed as "a path other than the endpoint could do this"; the measurement
was "a user can do this by clicking the button that is on the screen." **Always trace the
surviving leg to a rendered control before settling severity** — `grep` the component for
the field the leg keys on and read what the enclosing `{#if}` actually tests.

**⚠ AND THE CLASS THIS BELONGS TO: a ruled invariant implemented on the READ side with no
WRITE-side mechanism.** F/CTO had ruled *"`is_reverse` rows are EXCLUDED from the classify
queue and never classified by anyone."* The exclusion was built into the queue. Nothing
stopped a write. A companion measurement recorded at the same sitting — *"reversals carry no
annotation in the shipped flow"* — was **true of the reverse-and-replace flow and said
nothing about what a later form post could write**, and it read like coverage. **When a
ruling contains "never … by anyone", find the mechanism or report that there is none**; a
scope-limited measurement offered in its support is the thing most likely to be mistaken for
one. Same family as [[a-stated-invariant-stronger-than-the-contract]] and
`assertion-with-no-watcher` in the project index.

**How to apply:**
- For each enumerated leg, find the consumer and ask: is the bad value **read**? If the
  consumer's `where` excludes the row, the leg is inert — say so explicitly, because
  "uncovered" and "exploitable" are different claims and the difference is the whole
  remediation.
- Check whether a **sibling fence already covers** a leg before counting it. Two of four
  here were covered by fences authored years apart in different migrations.
- Trace the surviving leg to a **rendered control**, not to a theoretical path.
- Report the corrected shape in the same message as the original framing — name whose
  framing it was and that it was a good-faith enumeration, not a mistake. The upstream agent
  found the surface; the triage is my job, not theirs.
- Severity stays a **FLAG** when the defect is pre-existing, self-inflicted on the user's own
  data, and does not break a conservation law — even when it falsifies a ruling. Say that the
  PR under review **improves** the situation if it does; that is load-bearing for the scope call.

Related: [[hazard-mechanism-vs-reachability]] (both halves falsifiable, separately),
[[a-grep-over-comments-measures-intent-not-data]], [[shared-predicate-then-second-narrowing]].
