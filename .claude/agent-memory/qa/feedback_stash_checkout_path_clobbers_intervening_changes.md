---
name: stash-checkout-path-clobbers-intervening-changes
description: git checkout stash@{0} -- <path> replaces the file with the STASH's version wholesale, silently reverting any changes a teammate landed on that path between the stash and the restore.
metadata:
  type: feedback
---

`git checkout stash@{0} -- <path>` (or `stash@{0}^3` for the untracked-files commit) does not
merge — it checks out the FULL file content as it existed when stashed. If the target tree moved
(e.g. a teammate committed to a shared file after the stash was taken, and you'd merged their
branch into your scratch state), this silently reverts their intervening work on that exact path
while looking like a clean restore.

**Why:** during SELF-229 QA-battery verification, I stashed my WIP, merged frontend's branch for
a scratch test run, then restored my own edits via `git checkout stash@{0} -- <path>` for two
files frontend also owned/extended (`NavHistoryChart.dom.test.ts`,
`NavCompositionTable.dom.test.ts`). One of the two had a stashed version based on plain
`origin/main` (pre-dating frontend's SELF-229 commits) — the checkout silently deleted their
"SELF-229 D1 stale-data-marker" describe block along with their two tests. Caught only because I
diffed my final file against frontend's LIVE worktree file before sending it, and the diff showed
`-` lines I hadn't written. Sent nothing broken, but it was one `diff` away from clobbering a
teammate's landed work in a hand-off.

**How to apply:** after restoring ANY file from a stash into a tree that moved since the stash was
taken — via `checkout stash@{...} -- <path>`, `stash pop`, or `stash apply` — diff the restored
file against the CURRENT target (the teammate's live worktree, or `origin/<branch>`), not just
against your own prior version. A clean merge that started before a teammate's commit landed is
not proof the restore preserved that commit's content on a shared path. See also
[[feedback_never_write_into_a_teammates_worktree]] (same family: verify from the tree, not from
what you assume a git op did) and [[feedback_rediff_source_before_reverify]].
