---
name: prosrc-presence-checks-are-vacuous-because-the-comments-are-good
description: A structural catalog assertion over pg_proc.prosrc must strip comments, count executable occurrences, and match case-insensitively — presence checks pass on prose, and the legacy-primitive case goes GREEN not RED.
metadata:
  type: feedback
---

`pg_proc.prosrc` preserves in-body comments verbatim. So a structural assertion of
the form `prosrc ~ 'some_primitive'` is a claim about **text**, not about
**executable behaviour** — and in a well-documented function it is vacuous in BOTH
directions.

**Why:** SELF-345 / `111_audit_log.sql` (2026-09-05), measured in one function body:

- `pg_visible_in_snapshot` — raw **3**, comment-stripped **0** (the superseded
  primitive survives only in the comments explaining why it was abandoned)
- `pg_xact_status` — raw **5**, comment-stripped **1**
- `from pfin.monthly_report` — raw **2**, comment-stripped **1** (the invariant
  comment quotes the very statement it protects)

⚠ **The dangerous direction is the legacy one: a leg asserting the SUPERSEDED
primitive goes GREEN**, certifying that the body uses something it does not contain
at all. A red gets investigated; **a green gets trusted**, and it ships as evidence
that the battery was checked. The re-aimed direction is vacuous too — a check for
the CURRENT primitive passes even if the executable body uses something else.

⚠ **It is vacuous precisely BECAUSE the comments are good.** The better the
explanatory prose, the more reliably a presence check passes on it — an unwelcome
cost of documentation discipline, charged to the thing that discipline protects.

**How to apply, for any `prosrc`-based assertion or CI fence:**
1. **Strip `--` comments first**, then assert. (Block comments and string literals
   remain a residual — name it; mis-stripping over-flags, which is fail-loud.)
2. **Count EXECUTABLE occurrences, and assert an exact count** where the property is
   "not split in two." Presence (`>= 1`) cannot express it. `<> N` is fail-closed in
   both directions; `>= N` is not.
3. **Match case-insensitively (`~*` / `'gi'`).** SQL is case-insensitive: a split
   read whose second statement is written `FROM` scores 1 under `'g'` and **passes
   on a broken body** (measured). This is a *regression* watcher — the regression
   arrives in a form it cannot see **because nobody is trying**, which is worse than
   an evasion.
4. **NULL `prosrc` is a silent pass.** `regexp_replace(NULL,…)` is NULL and
   `NULL ~ '…'` excludes the row. PG14+ `BEGIN ATOMIC` SQL bodies carry NULL
   `prosrc`. Either flag NULL as its own violation class or scan
   `coalesce(prosrc, pg_get_functiondef(oid))`.
5. **Inversion-prove it on a matched pair of clean bases** — strike the property on
   a copy and require RED, apply the correct body and require silent. A structural
   leg asserted only against correct code cannot be distinguished from one that
   cannot fail at all.

Related: [[feedback_measure_the_fence_regex_not_its_comment]] ·
[[feedback_a_grep_over_comments_measures_intent_not_data]] ·
[[feedback_probe_that_only_asserts_failure_goes_vacuous]]
