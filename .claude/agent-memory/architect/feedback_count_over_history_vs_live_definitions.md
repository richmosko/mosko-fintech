---
name: count-over-history-vs-live-definitions
description: A count over migration TEXT is not a count over LIVE catalog definitions — and a control specified from the wrong one goes red on correct code.
metadata:
  type: feedback
---

When a fix must reach "all N copies" of something, **measure N over the live
catalog, not over migration files.** A function defined in `019` and
`CREATE OR REPLACE`d in `049` → `050` → `056` → `059` has **one** live body and
**five** textual copies. Both numbers are correct; they answer different
questions, and only one of them is the fix's scope.

**Why:** at the `078` price-pick tie-break, Sec's joint-review record measured
**six** hash-identical kernel copies over migration text (019/049/050/056/059×2/076).
The set the fix had to reach was **three** — the rest were superseded and are
applied history, which must not be edited. Neither number was wrong; relaying
either one without its scope word would have produced a false disagreement, and
the memory index already warns that the "wrong" number gets *corrected rather
than scoped*.

The sharper half: **a derived control inherits the scope of the count it was
specified from.** Sec's proposed kernel-identity CI fence extracted the block
"from every migration containing the rank clause" and asserted one hash — a spec
written from the *historical* count. The moment the fix landed, that predicate
spanned two kernel generations and the fence would have gone **red on correct
code**. The fence had to be re-scoped to live definitions before it was built.

**How to apply:** before authoring a cross-copy fix, enumerate live definitions
by walking every `create or replace` (case-insensitively — `059` uses uppercase
and a `$function$` delimiter, so a lowercase-only grep finds nothing and reads as
"no definitions here"), keeping the last one per signature. Then state both
counts with their scope word in the report. Check any *paired* control — a CI
fence, a battery grep — for which count its predicate was written from.
Related: [[feedback-state-what-the-count-is-over]], [[feedback-structural-fence-must-cover-the-same-class]].
