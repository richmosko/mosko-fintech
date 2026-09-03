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

**⚠ THE SAME SHAPE ARRIVES AS A CITATION FLAG, AND THERE THE INFLATED SCOPE PICKS THE WRONG FIX.**
SELF-343 / `095`: a relayed flag read *"items 5/6 and the EDIT-3 replacement all cite item 2's
ownership note"* and offered two remediations — (a) MOVE the paragraph so every citation becomes
true, or (b) amend the citations. I enumerated instead of accepting:
`git show <sha>:<file> | grep -n -i 'item [0-9]'` returned five sites, of which **exactly one was
wrong**. Item 6 cited item 1 and cited it correctly; "item 5" and "the EDIT-3 replacement" were the
same occurrence counted twice. **At the reported scope of three, option (a) looks proportionate; at
the measured scope of one, (a) is a structural edit to fix a one-word defect** — and (a) was also
wrong on the merits, because the note being cited is the executability rider on an instruction that
lives in item 1, so relocating it would have left item 1's own instruction uncaveated. *Never
relocate a control to make prose about it true* — same family as the "never demote a control to make
its prose true" line at [[enumeration-and-watcher-stop-one-short]]. **Fix by CONTENT-name, not by
ordinal**, when the list has recently grown; a bare ordinal is true today and re-stales on the next
insertion.

**⚠ AND: do not read a precise distinction as a slip.** In the same exchange I offered Architect an
"optional" note that their paragraph said TABLE ownership in one clause and DATABASE ownership in
another. Both were deliberate and correct — the DDL tests table ownership; the missing harness step
transfers database ownership. Two distinct objects. **Before flagging an apparent inconsistency in
someone's text, ask whether they are holding a finer distinction than I am**, and say "I do not
require the change" only after that check rather than as a hedge that lets a wrong note ship anyway.

**⚠ AND THE OLDEST VARIANT: a routed finding may already be RECORDED — grep the tree before ruling it
novel, because the provenance decides the remediation.** SELF-257 routed *"neither the D3
matched-tenant fences nor the FKs fire under `session_replication_role = replica`"*, reproduced live
with a control. Real, correctly bounded — and **already reproduced and ruled on a month earlier**:
`054_nav_daily.sql`'s header records the same live reproduction; `054_nav_daily_rls.sql`'s
KNOWN-LIMIT box generalizes it (*"INHERENT to trigger-based immutability under an owner identity …
applies identically to 004/account_trans and every Lock 10 mod #8 table"*) **and already answered the
battery question** (*"a test claiming 'the fence holds under `session_replication_role=replica`'
would be permanently and honestly RED against something triggers cannot provide"*); `057`'s trigger
comment uses it as live rationale (*"a policy survives … `session_replication_role = replica`; a
trigger does not"*); `055` shapes `pfin_etl` around it. The genuinely new part was narrow — **FKs**
and the D3 fences specifically (measured: on `pfin`, all 70 user triggers AND all 144 internal RI
triggers are `tgenabled='O'`, so FK enforcement is in scope too).
**Two consequences, both of which change the answer:**
(i) **The gap is not the mechanism, it is the LAYER where the general claim lives** — four migrations
carry it, the ADR that claims defense-in-depth does not. That makes the fix a *consolidation into the
ADR*, not a new finding, and drafting it as news would record a discovery date a month late.
(ii) **A question the tree has already ruled on should be answered by citing that ruling, not
re-derived** — I nearly re-derived the "no battery leg" answer from scratch when QA had written it
verbatim. Grep `supabase/migrations/` and `supabase/tests/` for the mechanism's name **before**
composing a ruling on it.

**How to apply:**
- Before ruling a routed finding novel, `grep -rn "<mechanism>" supabase/ DECISIONS.md docs/` — and
  when it is already recorded, say so plainly, credit the genuinely new extension, and re-home the
  remediation at whatever layer is actually missing it.
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
