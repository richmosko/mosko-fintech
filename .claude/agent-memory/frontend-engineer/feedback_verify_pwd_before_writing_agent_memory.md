---
name: feedback_verify_pwd_before_writing_agent_memory
description: Write/Edit tool calls to .claude/agent-memory/frontend-engineer/** can silently land in the wrong checkout when multiple worktrees share the same relative path — verify pwd first.
metadata:
  type: feedback
---

Mid-session on SELF-358/P6, I called `Write`/`Edit` on
`/Users/mosko/Projects/mosko-fintech/.claude/agent-memory/frontend-engineer/...` (the repo
ROOT checkout, on `main`) when I meant my worktree's copy at
`/Users/mosko/Projects/mosko-fintech/.claude/worktrees/frontend-engineer/.claude/agent-memory/frontend-engineer/...`.
Both paths exist (every worktree + the root checkout each has its own working copy of this
tracked directory), the calls succeeded silently, and the mistake was invisible for several
turns — `git status` inside my actual worktree kept showing only pre-existing pending changes
from a prior session, never my new file, because the new file was never there. Caught only when
a teammate's rebase task made me re-inspect the worktree's file contents closely.

**Correction (team-lead, same session):** this memory's own prescription above ("worktree, not
root") was WRONG on the standing rule — the ROOT checkout on `main`, left UNCOMMITTED, is where
agent memory belongs; team-lead sweeps it into chore PRs from there. A worktree's copy sits on a
feature branch and would either ride an unrelated ticket PR into `main` or be lost when the
branch is discarded. So: root checkout is correct, worktree is wrong — the opposite of what my
in-session confusion assumed. What stays true from the original incident: verify which checkout
`pwd`/the target path actually resolves to before writing, because both resolve silently with no
error either way.

**Why:** absolute paths typed from memory/habit don't get validated against which checkout is
intended — the root checkout and every worktree resolve the same relative suffix
(`.claude/agent-memory/frontend-engineer/...`) to a real, writable file, so there is no error to
catch a write landing in the wrong one in either direction.

**How to apply:** agent-memory Write/Edit calls target
`/Users/mosko/Projects/mosko-fintech/.claude/agent-memory/frontend-engineer/` (root checkout),
never the worktree's copy — regardless of which directory the rest of the session's work is
happening in. Before committing any ticket branch, confirm no agent-memory paths were staged
(`git log --oneline origin/main..HEAD -- .claude/agent-memory` empty, or `git status` shows none
staged). See also [[feedback_temp_handoff_files_need_a_shared_path]] — same root cause (per-
worktree paths that look identical across worktrees), different direction (that one is about
`temp/` not syncing across worktrees at all; this one is about a write landing in the wrong one
of two checkouts that both exist).
