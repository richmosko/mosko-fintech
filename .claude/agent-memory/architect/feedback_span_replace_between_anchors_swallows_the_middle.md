---
name: span-replace-between-anchors-swallows-the-middle
description: Replacing s[index(A):index(B)] deletes everything between A and B, not just the block you meant — and the tell is the line count moving the WRONG WAY.
metadata:
  type: feedback
---

When replacing a block by slicing between two anchors — `s[:s.index(START)] + new + s[s.index(END):]`
— **everything between START and END is deleted**, including blocks you did not know were there.
Enumerate what sits in the span before cutting it; anchor on the block's own end, never on the
next-sibling heading.

**Why:** measured 2026-08-22. Re-encoding a `D-2` decision item, I anchored on the `D2` heading
and the `D4` heading — and **`D3` sat between them.** The entire D-3 block (a ruled decision, its
sub-rulings, a drafting-ready spec table, a provenance note and a vehicle call) was destroyed in
one edit, in a **gitignored `temp/` file with no history and no backup**. Recovery was only
possible because the authored text was still in the conversation transcript.

**How to apply:** two cheap habits, both of which would have prevented it —
1. **Predict the line-count delta before the edit and check it after.** I replaced ~6 lines with
   ~50 and the file went **804 → 788**. A count moving the *wrong direction* is a deletion you
   did not intend; that discrepancy is what caught this, and it is the only thing that did.
2. **`grep -c` a distinctive string from each neighbouring block after any span replace** — one
   command, and it converts "probably fine" into a measurement.

⚠ **Report the deletion, and record the restoration in the artifact itself.** A silent
reconstruction leaves a reader who noticed the gap doubting their memory — the same reasoning
behind the repo's visible-supersession rule. Related: [[feedback_verify_the_bytes_you_commit]],
[[feedback_diff_of_two_outputs_proves_nothing_until_nonempty]].
