---
name: agent-worktree-location
description: Agent worktrees live at <repo>/.claude/worktrees/<agent> — RELOCATED 2026-09-06 from ~/Projects/mosko-fintech-worktrees/<agent>; the move happens live and breaks any absolute path held in a brief or script.
metadata:
  type: reference
---

**Current location:** `/Users/mosko/Projects/mosko-fintech/.claude/worktrees/<agent>`
(mine: `.../architect`). Confirm with `git worktree list` rather than assuming — that
command is the only thing that stayed true across the move.

**Relocated 2026-09-06** from `~/Projects/mosko-fintech-worktrees/<agent>`.

⚠ **The move happened MID-TASK, between two commands in the same session**, with no
notice. The symptom is a `cd` failing with *"no such file or directory"*, which reads
exactly like a destroyed worktree — the compound command then runs from the wrong
directory and every path-relative step fails after it.

**What actually happens to your work:** the tree moves **intact**, including
uncommitted changes. Nothing is lost *by the move*. What is lost is any edit inside the
command that failed on the `cd` — that command never ran.

**How to apply:**
- On any *"no such file or directory"* for a worktree path: run `git worktree list`
  before concluding anything. **Do not assume deletion**; check for relocation first,
  and check the working tree for surviving modifications (`git status --short`) before
  re-doing work.
- Prefer `cd <path> && …` as the **first** step of a compound command so a stale path
  fails loudly instead of silently running the rest elsewhere.
- ⚠ Never hardcode the worktree path in a brief to another agent — pass the branch and
  let them resolve the path. A path in a dispatch is a claim about the filesystem that
  ages the way a sha does.
- The new location is **inside the repo**, so it is subject to the repo's own ignore
  rules and tooling in a way the old external path was not.

⚠ **The stash stack is shared across all worktrees and other sessions may push or pop
concurrently.** Never bare `git stash` / `git stash pop`. Prefer a temporary WIP commit;
if you must stash, `git stash push -u -m "<unique-tag>"`, capture the SHA from
`git stash list --format='%H %gs'`, restore with `git stash apply <sha>`, then drop it
by re-finding its index by tag.
