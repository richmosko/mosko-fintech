---
name: diff-filter-swallows-removed-comments
description: A deleted SQL `--` comment renders in a diff as `---`, so a `grep -v '^---'` file-header filter is blind to every removed comment line; and "comment-only" is the wrong predicate for files carrying catalog comments — assert zero executable lines changed instead.
metadata:
  type: feedback
---

Two defects in the way I measure "is this diff comment-only", both found on the `072` review
(2026-08-14), both of which made a claim I had already sent partly vacuous.

**1. `grep -vE '^(\+\+\+|---)'` cannot see removed comment lines.** A deleted SQL comment
`--  foo` renders as `---  foo`, which the `---` file-header exclusion swallows. The filter
can only ever observe ADDITIONS. I reported a delta as *"empty in both directions"* when the
removal direction had not been measured at all — the instrument could not observe the
property. **Exclude only the literal header forms:** `grep -vE '^(--- a/|\+\+\+ b/)'`.

**2. "Comment-only" is the wrong predicate for a migration.** SQL files carry
`comment on function '…'` string literals that ship into **`pg_description`** — live,
database-visible text that is not a `--` line. A `^--`-shaped filter reports zero changes
there and is **wrong about where the text lives**: it would wave through a rewritten catalog
comment as "no change". Architect supplied the better predicate and it is now mine:

> **assert ZERO EXECUTABLE LINES CHANGED in either direction** — no `create` / `drop` /
> `grant` / `revoke` / `returns` / `select` — and account for the string-literal delta
> POSITIVELY, by naming which intended change it is.

**Why it matters:** clearance conditions get written as a predicate a coordinator will
freeze against, so a predicate that cannot fail is worse than no predicate. Both defects
produced *correct conclusions on this branch* — which is exactly why they would have
survived unnoticed.

**How to apply:** before sending any condition of the form "the diff must be X", write the
command that would falsify it and check the command can actually return a hit. Related:
[[clearance-conditions-must-absorb-my-own-recommendations]] and the project-level
*instrument cannot observe the property* memory.

**⚠ SECOND INSTANCE, and it is MY INSTRUMENT, not a teammate's — 2026-09-18, twice in one turn.** Reviewing a SQL migration, I built `git diff | grep -vE '^(\+\+\+|---)'` and then `awk '!/^--- /'` to display a comment-only delta. **In a file whose comments start with `--`, a REMOVED comment line renders in the diff as `---   …` — which matches the `--- a/path` HEADER pattern.** Both filters discarded every removed line and showed me a one-sided diff; I walked into this while checking for exactly this class.

**What saved it:** the visible `-` count disagreed with `--stat`. Not the filter — the disagreement.

**What to do:** strip the diff header **POSITIONALLY** (`git diff -U0 … | tail -n +5`), never by matching `^---`. And when a display filter and `--stat` disagree, the filter is wrong until proven otherwise. ⚠ **Grade the counting filter separately from the display filter** — mine survived (a removed line beginning `---` can only be a comment in SQL, since no executable statement starts with `--`, so nothing executable could hide), but that is an argument I had to make, not something to assume. Related: [[feedback_my_review_measurements_become_quoted_sources]].
