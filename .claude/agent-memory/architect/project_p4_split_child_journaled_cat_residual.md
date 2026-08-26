---
name: p4-split-child-journaled-cat-residual
description: The AC10 journaled-cat fence (092) covers the P3 grain only; 084's P4 split-child branch carries the identical defect and is structurally out of the trigger's reach
metadata:
  type: project
---

`092`'s `fn_account_trans_annotation_journaled_cat_fence` enforces
`journal_id IS NOT NULL ⇒ posting_prototype.cat NOT IN ('Revenue','Expense','Equity')`
on `pfin.account_trans_annotation`. **It cannot cover the split-child grain.**

`084`'s **P4** branch (084:889-911) runs the *same* ordered CASE over each
`account_trans_split` child's `cat` while taking `journal_id` from the **parent**
(`t.journal_id`). So a journaled parent whose children are classified
Revenue/Expense/Equity reproduces the identical money defect — and the trigger
never fires, because (a) the child's category lives on `account_trans_split`, not
on the annotation, and (b) a split parent's own annotation normally carries
`sub_cat_id IS NULL` (M4 refuses classifying it), so the fence's WHEN gate is not
even satisfied.

**Why:** Sec's C‴ ruling scoped the fence to the annotation table; the P4 grain was
not in the ruling. **RULED at the PR #561 Sec joint review (2026-08-25): BOOK, do
not extend** — extending the annotation trigger was explicitly rejected as the
worse security outcome. **Booked as SELF-339** (Platform V1.x, joint-review:sec)
with a HARD GATE: closes before ANY app path becomes able to write
`account_trans_annotation.journal_id` (zero app write sites exist today — greppable).

**How to apply:** do not let "the AC10 fence shipped" be read as "journaled legs are
fenced", and do not re-raise this as an unowned finding — it is owned at SELF-339.
The ruled shape is **TWO fences, not one** (per D-8 C″'s both-reachability-orders
reasoning): one on `pfin.account_trans_split` (child classify while parent
journaled) AND one on `account_trans_annotation.journal_id` scanning the child set
(parent journal-attach while children classified) — closing only the first
reproduces the exact one-order blindness C″ exists to prevent. Battery covers both
orders; the residual note also gets mirrored onto the `029` split-child fence's
catalog text at that PR. Routes through Sec (its own D-8-shaped ruling).

Related: [[gl-taxonomy-split-ratified]].
