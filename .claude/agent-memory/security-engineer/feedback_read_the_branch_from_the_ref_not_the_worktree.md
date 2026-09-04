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

**⚠ I HIT BOTH HAZARDS ABOVE AGAIN, IN ONE REVIEW, WITH THIS MEMORY LOADED (SELF-250 / PR #572,
2026-08-26).** The zsh one produced two different wrong md5s for a blob that had never changed —
which briefly read as *"the migration moved after the frozen sha,"* the single most alarming thing
a Sec reviewer can conclude. The parked-worktree one was worse: I prefixed each command with
`cd <worktree>` and then used **bare paths** (`grep … DECISIONS.md`, `sed -n … supabase/migrations/084_…`),
so every read looked ref-scoped and none was. The `sec` worktree sat at `aab0911`, far behind
`main`, and **ADR-064 — the ADR one of the two joint-review triggers rests on — did not exist there
at all.** I re-measured everything from blobs before writing, and no finding changed; but a first
pass that is not evidence costs a whole review's worth of trust if it ships.

**The fence that actually holds, because the previous wording did not: NO BARE PATH IN A REVIEW,
EVER.** Not `cat`, not `grep`, not `sed`, not `ls`. Every read is `git cat-file blob <ref>:<path>`
or `git show "${REF}:<path>"`. `cd`-ing into a worktree does not scope a read to anything —
it only makes an unscoped read look deliberate.

**Two free tells, both one command:**
- **Grep the newest thing you know exists.** `grep -c 'ADR-0NN' <file>` for the most recent ADR, or
  `git log --oneline -1` in the worktree. A zero, or a HEAD you do not recognise, is a stale ref
  before you have built anything on it.
- **A brief's FROZEN sha can be behind the PR head.** `gh pr view <n> --json headRefOid` in the same
  turn as the verdict. On SELF-250 the brief froze `f4b5eac`; the head was `52094f8`, one commit
  further. Bound the delta before reacting: it was battery-only and additive (`plan(31)`→`plan(34)`,
  migration blob byte-identical), so the right move was **review at head, state the delta, reopen
  nothing** — see [[review-the-delivery-note-against-the-ref]].

Related: [[measure-the-fence-regex-not-its-comment]] — same shape one level down (measure the real
predicate at the real ref, not the description of it).

**A DIFF AGAINST A STALE BASE RETURNS A FALSE NEGATIVE ON "did it land?" (SELF-268 re-look).**
Checking whether supplied verbatim text had reached `DECISIONS.md`, I ran
`git diff <old-freeze-sha> <ref> -- DECISIONS.md | grep '<my sentence>'` and got **nothing** — and
was one step from reporting the obligation undischarged. The sentence was there, byte-exact. The
base sha predated `main` moving, so the ADR edit had arrived on the branch **through a merge of
main** rather than as a diff hunk against that base. **A grep over a DIFF asks "did this change
between these two refs"; a grep over `git show <ref>:<path>` asks "is this true at the ref".** For a
*did-it-land* question only the second is the right instrument, and the first fails in the
reassuring-to-me direction: it reports absence.

**How to apply:** for presence claims — a sentence, a fence, a leg, a grant — read the FILE AT THE
REF (`git show <ref>:<path>`). Reserve diffs for *what-changed* questions. If a diff must be used,
its base has to be an ancestor you chose deliberately, and say which.

**And the companion method, for an IN-PLACE edit to a body produced by anchored substitution:** a
diff of the edit cannot show a span it perturbed by accident, because the perturbation would look
like part of the intended change. Do **both** — read the body fresh from the ref for correctness,
and separately enumerate every **non-comment** line the edit touched
(`git diff A B -- <file> | grep -E '^[+-]' | grep -vE '^[+-][[:space:]]*--'`) as the perturbation
check. At SELF-268 that returned exactly two executable changes, which is what let every
body-dependent conclusion from the prior review carry forward instead of being re-derived. State the
result as a count of executable changes, never as "the edit looks small" — see
[[diff-filter-swallows-removed-comments]] for why the comment filter has to be explicit.
