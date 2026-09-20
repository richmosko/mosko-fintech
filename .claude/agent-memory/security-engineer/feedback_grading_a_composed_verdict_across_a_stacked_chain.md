---
name: grading-a-composed-verdict-across-a-stacked-chain
description: A close-gate verdict composes per-surface verdicts taken at different shas — that composition is a FRESH claim; grade it by induction over reviewed deltas, and never let "no unreviewed change entered" become "every blob has been read".
metadata:
  type: feedback
---

**The situation.** A milestone close-gate composes N per-surface verdicts, each scoped to the `main`
of its own read, into one PASS at a later sha. **That composition is a claim nobody has graded** —
each surface verdict was true at its own sha and says nothing about the tip.

**⚠ THE WRONG QUESTION, which I asked first (V1.5, 2026-09-07).** *"Are surface N's cleared files
unchanged since surface N's read?"* On a **stacked** chain (P2 → P3 → P5 → P8 → P4, each branched on
the last) later surfaces **legitimately** modify earlier ones. Six surfaces came back with large
changed-file sets and I was ready to report alarming churn — which would have been a finding about
the chain's own shape, not about risk.

**The right question: did any blob reach the final sha through a commit NOBODY reviewed?** Two
measurements answer it, and they are cheap:

1. `git diff --name-only <my-last-full-read-sha> <tip>` — what changed since the most recent read.
2. `git log --oneline --merges <that read's base>..<tip>` — which PRs landed in that window.

If (1) is contained in (2), and every PR in (2) is one I read, the composition holds **by induction
over a linear chain of reviewed deltas**, each link having been graded at its own frozen sha with
`merge-tree` CLEAN. State it in that form. An enumeration of "check PR #X and #Y" is both incomplete
and points at the wrong property.

**⚠ BOUND THE CLAIM — I graded DELTAS, not TREES.** The chain proves **no unreviewed CHANGE entered
during the wave**. It does **not** prove **every blob at the tip has been read** — the starting
point never was, and correctly so (pre-existing work outside the wave). *Those are different
sentences and only the first is supportable.* Put the first one in the record; the second is the
overclaim a close-gate reader will otherwise take away.

**⚠ THE INSTRUMENT TRAP, because it hit me here.** Building the cleared-file list into a shell
variable and passing it as a git pathspec — `git diff --name-only A B -- $files` — **silently
compares nothing in zsh** (no word-split; the newline-joined list becomes one pathspec that matches
nothing), and every surface reports **UNCHANGED**. I was one step from ratifying on a command that
never ran a comparison. Intersect instead:
`git diff --name-only A B | grep -Fx -f <(printf '%s\n' "$list")`. See
[[my-review-measurements-become-quoted-sources]] — a wrong question **and** a wrong instrument
together produce a confident wrong answer, and fixing only one of them still ships it.

**What "good" looks like in the verdict artifact itself, worth recognising rather than re-deriving.**
The V1.5 close-gate verdict earned its single-sha claim: it `cat-file -e`'d the battery file before
starting (the prior dispatch's STOP), and corroborated its carried-forward steps with a rebuilt
template's `content_sha256` match rather than resting on one `git diff --stat`. **A carry-forward
with a positive control is the shape to ask for.**

**And the residual to look for specifically: a cited leg that EXISTS but did not RUN.** A battery
that aborts mid-file (an EXPECTED-DIFFERENT-LOCALLY leg is the usual cause) leaves every later leg
unexecuted while `grep` still finds it. Reconcile the run's **Tests=N against the expected total** —
the delta is exactly the unexecuted legs, and it is how I found one. A verdict that marks such a
citation *"present by grep; not locally re-executed"* is behaving correctly; the discharge is to
cite the CI run that did execute it, carried across by an **executable-identity** argument (zero
executable lines changed between the CI sha and the verdict sha).

## ⚠ A FOLD FOLDED INTO A MERGE COMMIT (2026-09-17)
A PR head arrived as a **single merge commit** whose parents were the reviewed head and `main` — but which
**also carried three content folds**. **A blob-identity re-pin passes that while reviewing nothing**, because
the blobs differ for a declared reason and the diff-hash check is aimed at "did the merge introduce anything,"
not "what did this commit change."

**The distinction that matters: DECLARED vs HIDDEN.** Here the coordinator named it, so it cost one content
review of the delta. **Undeclared, it is the mechanism by which a change reaches `main` unreviewed** — and it
would survive every parent/hash check I habitually run.

**How to apply:**
- **Whenever a pin target is a MERGE commit, diff it against BOTH parents, not just `main`.**
  `git diff <reviewed-head> <merge>` is the one that exposes folds; `git diff <main-parent> <merge>` only shows
  what the branch adds. A non-empty first diff means content review, not a re-pin.
- **Re-derive the both-sides file's load-bearing content by COUNT, not by presence.** On that runbook the
  predicate appeared **twice** — once in the Step-0 gate and once in the post-redeploy re-verify — and a
  conflict resolution collapsing them to one would have silently removed the re-verification that makes the
  later step a gate rather than an instruction. **A presence check would have passed; a count check caught it.**
- Related: [[a-branch-cut-from-integration-carries-superseded-sibling-blobs]], [[read-the-branch-from-the-ref-not-the-worktree]].
