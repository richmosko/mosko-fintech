---
name: reference-agent-worktree-path
description: My git worktree lives at <repo>/.claude/worktrees/frontend-engineer, not under ~/Projects/mosko-fintech-worktrees/
metadata:
  type: reference
---

My workspace is `/Users/mosko/Projects/mosko-fintech/.claude/worktrees/frontend-engineer` (inside the repo). F/CTO directive 2026-09-06: every agent worktree was moved from `~/Projects/mosko-fintech-worktrees/<agent>` to `<repo>/.claude/worktrees/<agent>` via `git worktree move`, because a path outside the repo's working directory tripped an approval prompt on every command. The old path no longer exists.

**Why:** F/CTO runs the team unattended; a command needing manual approval stalls the whole roster, not just me (see [[feedback_bash_sandbox_no_heredoc_no_substitution]]).

**How to apply:** At the start of a session, confirm `pwd` resolves under `.claude/worktrees/frontend-engineer` before running anything. If a stale absolute path (old worktrees location) surfaces anywhere — in my own prior output, a doc, a script — treat it as wrong and correct it, don't propagate it. `node_modules` moved with the worktree; if `npm run check`/vitest misbehave on absolute-path assumptions after a future move, `npm ci` once.
