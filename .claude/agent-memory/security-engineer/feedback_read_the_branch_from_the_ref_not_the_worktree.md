---
name: read-the-branch-from-the-ref-not-the-worktree
description: A parked review worktree is often several merges behind origin/main — probe file existence with git ls-tree/git show against the named ref, or a valid citation reads as a fabricated one.
metadata:
  type: feedback
---

**⚠ `grep -n` ON A PIPED STREAM NUMBERS THE STREAM, NOT THE FILE — and the result is a
self-consistent wrong citation.** Reviewing `081` I read via
`git show … | sed -n '/^create or replace function/,$p' | grep -n …` and reported "081:99-103".
The real file location was **253**; my numbers were function-body-relative offsets presented as
file citations. Caught twice in one review by the file's author. **This is worse than a typo
because every number in the message is internally coherent** — it survives spot-checking and
only fails when someone opens the file.

**Convention, now explicit: QUOTE THE SENTENCE; treat the number as advisory.** The sentence
anchor is the thing actually verified against and it held exactly both times. This is the same
rule I already carry for ADR citations (*cite by name, never by line number*) — I had scoped it
to `DECISIONS.md` and it applies to every file. If a number is wanted, take it from an
**unfiltered read of the whole file**, never from a `sed`/`awk`/`head` slice.

When reviewing a branch read-only from a parked worktree, **every existence probe must name the
ref** — `git ls-tree --name-only origin/main <path>`, `git show <ref>:<path>`, `git grep <ref> --
<path>` — never a bare `ls` or `grep` of the checkout.

**Why:** measured on the `073_fn_nav_reference_dates` review (2026-08-14). The `sec` worktree was
parked detached at `d0f66eb`, two merges behind `origin/main` at `4270495`. A bare
`ls supabase/migrations/` topped out at `071`, which made the reviewed migration's repeated
citations to *"072's v_base"* look like references to a migration that does not exist — i.e. a
fabricated-citation finding, the most damaging class to raise wrongly. `git ls-tree origin/main`
showed `072_fn_nav_delta_panel_real_percent.sql` present; every citation was correct. The wrong
probe would have cost the author a defence against an invented defect.

**How to apply:** at the start of any review, record the three refs explicitly — worktree HEAD,
`origin/main`, review ref — and treat the worktree HEAD as **not** the baseline. Extract the
branch's files with `git show <review-ref>:<path>` rather than checking the branch out (the
authoring agent owns it). Any "file X does not exist" or "citation Y has no referent" claim is
**ref-scoped** and must state which ref it was measured at, per
[[which-ref-the-probe-was-aimed-at]] — a control string passes on the wrong ref too, and an
absence proves even less than a presence.

**Ask for a confirm request to be anchored to a HEAD SHA, not to a description of contents.** At the
2026-08-15 db-reset-guard review I was asked to "confirm the reworked set"; measured
(`gh pr view <n> --json headRefOid` + `git log origin/<branch>`), the head was the **same commit** I had
already reviewed — the fix dispatch and my findings had crossed, so nothing had landed. Two lessons, and
the second is the one I got wrong: (1) always re-read the head sha in the same turn as the verdict, and
report the sha, not "unchanged since last time"; (2) **a dispatch in flight is authored-not-landed, a
timing fact — NOT a false report.** I framed it as "the second time a report described changes the tree
did not contain," which was unfair to the relayer and had to be retracted alongside their own retraction.
Measure hard, infer gently: state what the sha is, and let the cause be theirs to explain.

**⚠ TWO MECHANICAL HAZARDS IN THE EXTRACTION COMMAND ITSELF, both measured on the 2026-08-19 rename
review, both of which produce plausible-looking wrong output rather than an error.**

- **`git show "$B:path"` MISBEHAVES IN ZSH.** zsh applies history-style modifiers to *unbraced*
  parameters (`$B:h`, `$B:s/…/…/`), so `"$B:supabase/…"` is not the ref-path expression you wrote.
  It emitted `bad substitution` once and — worse — **twice returned a commit diff instead of the
  file's contents**, which reads as real output and nearly became a finding about the wrong bytes.
  **Always `git show "${B}:path"` with braces**, or a fully single-quoted literal `ref:path`.
- **NEVER `git checkout <ref> -- .` TO READ A BRANCH.** I did this in the `sec` worktree and it is
  a mutating command in a role whose Bash is read-only. It staged **99 paths** (an index anyone
  committing there would take whole — `commit` is not scoped by `add`) and **destroyed an
  unstaged edit** to a file in that worktree, unrecoverably. There was never a need: every
  measurement in that review came from `git show <ref>:<path>` / `git grep <ref> -- <paths>`, which
  read objects and touch nothing. **If a probe wants a checkout, the probe is wrong.** And having
  taken it, do not take a second mutating command to "undo" it — report the state and ask.

Related: [[measure-the-fence-regex-not-its-comment]] — same shape one level down (measure the real
predicate at the real ref, not the description of it).
