---
name: draft-verify-revert-when-not-branch-owner
description: When authoring commit-ready text for another agent's branch, draft it locally in the backend worktree, typecheck/test it, then revert before handing off — never leave it committed or dirty.
metadata:
  type: feedback
---

When a task requires delivering commit-ready text to a teammate who owns the branch (e.g. frontend-engineer on a UI item that also needs a backend load-function change), and the backend engineer is instructed to stay detached and not commit on that item: draft the exact file changes in the backend worktree first, run the real verification (`npm run check` / `svelte-check`, relevant vitest files) against them, capture the verified final content, THEN `git checkout --` any modified tracked files and `rm` any new untracked ones to return the worktree to clean/detached before sending the text via SendMessage.

**Why:** the hand-off instruction said the text "must compile as sent" — sending unverified text risks the receiving agent committing something broken. But the same brief says "you do not commit on this item" and the worktree must stay clean for the branch owner. Drafting-then-reverting satisfies both: real verification happens, but no trace is left in a worktree/branch this agent doesn't own.

**How to apply:** any SELF-222-shaped task (backend delivers text, frontend/other-role commits) where compile-correctness matters. Flag the judgment call explicitly to team-lead in the hand-off ("Bubble up") in case the preferred convention is actually to hand over unverified text without touching the worktree at all — this hasn't been explicitly ratified either way.

See also [[reference_local_smoke_verify_idiom]].
