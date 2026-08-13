---
name: diff-filter-strips-comment-lines
description: The idiomatic `grep '^[+-][^+-]'` diff filter silently drops every SQL/`--` comment change — on a comment-dense file it strips most of the payload
metadata:
  type: feedback
---

**Never use `grep -E '^[+-][^+-]'` (or `^+[^+]` / `^-[^-]`) to filter a diff of a
comment-dense file.** It is the idiomatic way to strip the `+++`/`---` file headers,
and on any file whose comments start with `--` it *also* strips every comment-line
change: a removed `-- foo` renders as `--- foo`, an added one as `+-- foo`, and the
`[^+-]` clause rejects the second character.

**Why:** SELF-218, 2026-08-12 — hit **twice in one session**, the second time within
minutes of writing up the first. Verifying a 98-line change to a pgTAP battery, the
filter reported **10 changed lines**. Caught only because 10 was implausible against
the author's description — not because anything complained. Re-measured: 68 added /
30 removed. Then, while reconciling a separate count, `grep -c '^-[^-]'` reported
**2** removed lines instead of 30. Same bug, same session, already known.

**How to apply:**
- Use `git diff --numstat` for authoritative added/removed counts, or `tail -n +3` to
  drop the two header lines positionally rather than by pattern.
- ⚠ The danger is not the wrong number — it is that the filter is used to certify
  *"the delta is confined to X."* A filter blind to comment changes will happily
  confirm that claim over a diff full of comment changes. **The instrument could not
  observe the property it was being used to observe.**
- Sanity-check any diff measurement against the change's *apparent* size before
  trusting it. An implausibly small count is the only signal this failure emits.
- Related count-scoping trap in the same turn: `git diff --no-index` **total output
  lines** (154) versus **changed lines** (68/30) read as a disagreement between two
  people until scoped. Both were right about different things — say what a count is
  over before treating a mismatch as an error.

Related: [[structural-fence-must-cover-the-same-class]]
