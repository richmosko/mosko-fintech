---
name: reference-worktree-path-moved
description: Per-agent git worktrees now live under .claude/worktrees/<agent>, not the old sibling-directory convention — verify with `git worktree list` before trusting a remembered path.
metadata:
  type: reference
---

Per-agent git worktrees for mosko-fintech are at
`/Users/mosko/Projects/mosko-fintech/.claude/worktrees/<agent>` (e.g.
`.claude/worktrees/devops`), NOT the older sibling-directory convention
`~/Projects/mosko-fintech-worktrees/<agent>`.

**Why this matters:** mid-session on 2026-09-06, `cd
/Users/mosko/Projects/mosko-fintech-worktrees/devops` started failing with
"no such file or directory" — the directory had been reorganized to the
`.claude/worktrees/` layout since the session started. The branch and its
commits were NOT lost (worktrees share the same underlying `.git` object
store), but the path itself moved.

**How to apply:** before trusting any remembered worktree path, run `git
worktree list` from the main repo root — it enumerates every live worktree
with its current path and checked-out branch. Do this at the start of a
session and again if a `cd` into a previously-good worktree path
unexpectedly fails; don't assume data loss from a missing path alone —
check the branch's log first (`git log --oneline -1 <branch>` from any
worktree, since refs are shared).
