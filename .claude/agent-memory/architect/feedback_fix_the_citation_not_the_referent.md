---
name: fix-the-citation-not-the-referent
description: When a cross-reference points at the wrong item, fix the REFERENCE — relocating the referent to make the prose true silently moves a control out from under the thing that needed it
metadata:
  type: feedback
---

**A wrong cross-reference is repaired at the pointer, never by moving what it points at.
And repair it by CONTENT, not by ordinal.**

**Why.** At `095` (2026-08-29) Sec's item 5 cited *"item 2's table-ownership caveat"*; the
rider was in item 1. I offered two fixes and listed **relocate the paragraph into item 2**
first. Sec ruled the other way and gave the reason I had missed: item 1 contains its own
drop-a-constraint instruction, so the ownership rider is what makes that instruction
*executable*. Moving it would have **made the prose true by removing a control from the
place that needed it** — a silent behavioural change dressed as a citation fix. The ruled
repair names the rider by content (*"the TABLE-OWNERSHIP ⚠ in item 1"*), which also cannot
go stale if the block is ever reordered — the same reason this project cites §7.7 entries
by title and not by `F#`.

**Same session, my own error in the other direction:** I reported *"items 5 and 6 both"*
mis-cited. Only item 5 did, on one line — item 6 cited item 1 correctly, and item 5's
*other* reference (*"item 2's idiom"*) was also correct. **I bounded the claim by where I
noticed the problem rather than by where I checked for it**, inflating one line into two
items. The inverse of [[adding-vs-qualifying-verification-asymmetry]]: don't bound your
own finding by your noticing either.

**How to apply.**
- Before "fix" a citation by moving its target, ask what ELSE stands where the target sits.
  If anything reads it in place, the pointer is the thing to edit.
- Prefer a content-anchored reference over an ordinal one in any list that can grow or
  reorder.
- State the scope of a citation finding as *"one line at `:NNN`"*, having grepped the
  neighbours — not as *"items X and Y"* because those are the two you happened to read.

Related: [[self-authored-label-hardens-into-fact]] · [[name-anchor-adr-citations]] ·
[[a-rationale-home-is-not-an-enforcement-home]]
