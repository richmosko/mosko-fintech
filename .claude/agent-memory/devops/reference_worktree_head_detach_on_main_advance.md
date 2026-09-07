---
name: worktree-head-detach-on-main-advance
description: A per-agent worktree's HEAD can be detached from your branch by a coordinator checkout run in that worktree (never by main advancing on its own); confirm your branch is current before committing, not just at initial checkout.
metadata:
  type: reference
---

Observed on SELF-348 (A4 item 4c, 2026-09-05): created `feature/self-348-devops`
from `origin/main` with `git checkout -b ... origin/main`, confirmed attached
(`git status --short --branch` showed the branch name). Read several files, did
work, then committed — `git commit` reported **"detached HEAD"**, landing the
commit on a detached ref instead of the branch. `git log` showed the detached
HEAD's parent was a **later** main tip (`a696d32`, the SELF-350/#630 merge) than
the branch ref itself (`b0335bd`, the pre-merge tip the branch was cut from).

**Actual cause (corrected by team-lead 2026-09-05 — do not trust the earlier
guess in this file's history):** a **shared-repo merge on `main` never detaches
a sibling worktree's HEAD by itself.** The detach happened because the
coordinator (team-lead) ran `git checkout --detach main` **directly in this
worktree** while parking branches after the #630 merge — an explicit checkout
in that worktree, not passive ref churn from elsewhere. My initial write-up
guessed "shared-ref churn from another worktree advancing main" as the
mechanism; that guess was wrong and specifically not to be repeated.

**Recovery (used successfully, no data lost):** the commit still exists on the
detached HEAD; move the branch pointer to it and reattach —
```
git branch -f <branch-name> <detached-HEAD-sha>
git checkout <branch-name>
git status --short --branch   # confirm attached, not "(no branch)"
```
Then push normally. The resulting branch is fine even if it's based on a LATER
main tip than originally intended — in this case that was actually beneficial
(picked up merged sibling work).

**How to apply:** in any dispatch involving a per-agent worktree, re-check
`git branch --show-current` (or `git status --short --branch`) immediately
before committing, not just right after `git checkout -b` — especially if a
coordinator or another agent could plausibly have touched this worktree
mid-task (e.g. "parking branches" after a merge). A commit succeeding is not
proof it landed on the intended branch; the commit's own output line
("detached HEAD" vs a branch name) is the tell. The thing to suspect is a
checkout run IN THIS WORKTREE by someone else, not main moving on its own. See
also [[reference_agent_worktrees]] and
[[feedback_git_add_does_not_scope_a_commit]] for the broader shared-worktree
hazard family.
