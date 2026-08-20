---
name: late-annotation-next-touch-rider
description: A REF/CONSUMER-style annotation added to a file AFTER the commit it describes cannot be committed alone — it necessarily lives in a LATER commit than the ref it names, so it needs a caveat saying so, or it should ride the next natural edit instead of justifying a commit of its own.
metadata:
  type: feedback
---

085/element PR (2026-08-19/20): pasted a raw TAP tail into `085_taxonomy_element_rls.sql`'s
own header, labeled `REF <sha>`, to give Sec a from-a-run-not-an-argument observation. Two
things went wrong, both instructive:

1. **The label's sha was already stale by the time it landed** — the file itself changed (a
   text fix to the very leg the tail quotes) between when the tail was captured and when the
   annotation would commit, so "REF <sha>" inside the corrected file was provenance for bytes
   the file no longer had.
2. **Team-lead's ruling on the re-issue (Architect relayed): don't re-issue at all.** The
   deciding reason, not the one I expected: *any* annotation naming a sha necessarily lives in
   a commit AFTER that sha (you can't commit evidence about a commit in the same commit), so
   the annotation would need its own caveat explaining that it postdates what it describes —
   "evidence that has to argue for itself is weaker than evidence with no label at all." A
   compliant PR body already carried the ref + consumer; the in-file copy was for durability,
   not for satisfying the requirement, so it wasn't worth a commit of its own.

**The pattern that resolved it: book it as a NEXT-TOUCH RIDER.** Don't force a commit to land
a nice-to-have annotation. Ride it onto the next edit that touches the same file for a real
reason. When it lands, three clauses, not two: **REF** (the sha the run actually exercised),
**CONSUMER** (the exact tool + image tag — `pg_prove` containerized, never bare `psql`), and
**a note that the annotation postdates the run it describes** — that third clause is what
makes a late label honest instead of merely accurate.

**How to apply:** before embedding a "here's proof, REF <sha>" comment inside a file, ask
whether the comment's own commit will be AFTER that sha (it always will, since you can't
cite a commit from inside itself). If so, either (a) do it in the SAME commit that produces
the sha being cited (only possible for a self-consistent claim, e.g. "this file's own plan
count is N" — checkable from the file alone), or (b) don't force a standalone commit for it —
queue it as a rider on the next edit, with the postdates-the-run caveat. Never paste a run's
output into a file whose own content differs from what produced that output, even if the
label names the right sha, without saying the label came later.

**Fourth clause, added after Architect pressed on intent vs. placement:** the pasted tail
happened to truncate description text with `...` before the point where old and new wording
diverged, which meant the stale-label risk above never actually materialized in the shipped
file. Architect asked directly whether that truncation was deliberate (paste the SHAPE, elide
the prose on purpose, because prose goes stale) or incidental (elided for width/readability,
safety a side effect). Honest answer, checked against my own authoring reasoning rather than
asserted after the fact: **it was incidental** — the descriptions in this codebase's house
style run to 100+ words each, and I truncated for readability inside a comment block, not
because I had reasoned about staleness at the time. The safety was luck, not design. **So the
rider's fourth clause is a real addition, not a restatement:** paste a run's SHAPE only —
plan line, `ok` sequence, trailing `#`/diagnostic comment, `Result: PASS` — and elide
description text ON PURPOSE, every time, because a description pasted into the file it
describes goes stale the instant that description is next edited. Don't rely on truncating
for space to also happen to save you.

Related: [[feedback_scratch_db_pgtap_harness_gotchas]] (same PR, same file — the BLOCK C
mechanism this tail was documenting). This project already has a standing "ADR-058 two-word
rider" owed via the same next-touch mechanism — same pattern, landed cleanly there per
Architect.
