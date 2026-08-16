---
name: worktree-branch-drift-after-compaction
description: After a context-compaction resume, verify the worktree is actually on the expected branch/sha before trusting local file state — it can have silently detached to main.
metadata:
  type: feedback
---

Mid-session, my qa worktree silently detached from the shared feature branch onto `main` (mechanism unclear — no checkout visible in my own turn, likely happened before a context-compaction resume). I spent a full turn "fixing" a 39-svelte-check-error ripple and re-authoring test coverage that was already committed and green on the real branch tip — pure wasted work, because I trusted my own worktree's `git status`/file contents instead of checking what branch/sha it was actually on.

**Why:** A resumed conversation (post-compaction) inherits a summary of what *should* be true, not a live re-read of git state. The worktree's uncommitted local edits survive a branch checkout silently (no conflict, no warning), so a detached-to-main worktree with WIP files layered on top looks completely normal from `git status` alone — nothing flags the branch mismatch unless you check `git log -1` / `git worktree list` against what the OTHER agents' worktrees are actually on.

**How to apply:** At the start of any resumed session (especially post-compaction) and before delivering anything as "verified," check `git log --oneline -1` in the working worktree AND cross-check it against a sibling worktree's branch/sha (`git worktree list` from the repo root, or `git log -1 <shared-branch-name>`). If they don't match, diff the working tree's non-owned files against the real branch tip file-by-file before assuming any local reconstruction is needed — it may already be redundant. This generalizes [[feedback_which_ref_the_probe_was_aimed_at]] and [[feedback_rediff_source_before_reverify]]: the ref that needs checking isn't just "what am I about to verify against" but "what branch is my own worktree even standing on."
