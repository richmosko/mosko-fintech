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

**⚠ THE MIRROR FAILURE, and it bites the opposite claim (SELF-221 / `072`, 2026-08-14).**
The inverse filter — `grep -vE '^[+-]\s*--'`, used to prove *"this change is
comment-only"* — is blind in the other direction: **a `comment on …` catalog comment
is a SQL string literal, so its lines start with `  '…'`, not `--`.** Verifying the
072 freeze I ran exactly that check expecting 0 and got **4 added / 3 removed**. The
lines were all comment TEXT, so a naive reading says the filter over-reported — but
the honest finding is the reverse: **had the diff touched only the catalog comment,
the filter would have reported 0 and I would have certified "comment-only" over text
that ships into `pg_description` and is read at `\d+` by someone with no repo.**

That distinction is exactly `apply-migration` Step 1.6's A/B split — text WITH a
database representation versus text without — and the filter cannot see it. Assert
the positive property instead: **zero executable lines changed** (`grep -icE
'create|drop|grant|revoke|returns|select|…'` over the changed lines, want 0), which
is a claim about what the diff *does* rather than about what it looks like.

Related: [[structural-fence-must-cover-the-same-class]] · [[replacement-control-name-the-losing-side]]
