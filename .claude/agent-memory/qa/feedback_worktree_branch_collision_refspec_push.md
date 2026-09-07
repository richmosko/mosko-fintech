---
name: worktree-branch-collision-refspec-push
description: When directed to check out a branch that's already checked out in ANOTHER agent's worktree (git refuses — a branch can only be checked out in one worktree at a time), check out a differently-named local branch tracking the same remote ref, commit there, and push via an explicit refspec (local:remote) to land the commit on the intended remote branch name — without ever touching the other worktree.
metadata:
  type: feedback
---

Team-lead directed authoring new commits on `feature/self-358` (P6's branch) from my own (QA)
worktree. `git checkout -B feature/self-358 origin/feature/self-358` failed: `fatal: 'feature/
self-358' is already used by worktree at '.../frontend-engineer'` — that branch was checked out
in Frontend's worktree (agent stopped, but the worktree/branch binding persists regardless of
whether the agent is running).

**Fix, safe and used successfully (SELF-362 P10, 2026-09-06):**
```
git checkout -b self358-qa-work origin/feature/self-358   # any local name NOT already in use
# ... make commits normally on self358-qa-work ...
git push origin self358-qa-work:feature/self-358          # refspec: local-name:remote-name
```
This lands the commits on `origin/feature/self-358` exactly as if checked out under that name
locally, without ever touching Frontend's worktree, and matches
[[feedback_never_write_into_a_teammates_worktree]]'s standing rule — a worktree branch lock is the
same class of hazard as writing into the directory itself, just enforced by git rather than by
convention. Frontend's local worktree is now BEHIND the remote by whatever was pushed this way;
that's their `git pull` to do next session, not something to fix from here.

**How to apply:** whenever dispatched to commit onto a branch name and `git checkout` refuses
citing "already used by worktree at ...", don't force it (`git worktree remove`/`--force` on
someone else's worktree is destructive and out of scope) — use a scratch local branch name plus
an explicit push refspec instead. Report the local-name detail in the hand-off so the coordinator
isn't confused later about why `git branch` in this worktree doesn't show the branch you pushed to.
