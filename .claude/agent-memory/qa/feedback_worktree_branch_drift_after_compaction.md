---
name: worktree-branch-drift-after-compaction
description: RECURRED ONCE, different trigger — verify the worktree is actually on the expected branch/sha before trusting local file state at the start of ANY new task, not only after a compaction resume. It can have silently detached to main between assignments too.
metadata:
  type: feedback
---

⚠ **RECURRED (SELF-243, same session as SELF-330, no compaction involved this time).** My qa
worktree was still detached at a commit that predated SELF-330's merge when the SELF-243
assignment landed — caught it before doing real work this time (by noticing a branch diff didn't
match what I expected), not after. The trigger generalizes past "post-compaction resume": **a
worktree can go stale simply because a prior item merged to main and nobody re-synced it before
the next assignment started.** Team-lead's "same worktree, stay detached" instruction is correct
and should be followed — it does NOT mean "trust the sha it's already on." Fixed by `git stash`
(any local uncommitted deliverables), `git fetch origin main`, `git checkout origin/main`
(detached), confirm redundant local content against the new tree, drop the stash.

**Standing habit this establishes:** check `git log --oneline -1` in the working worktree against
the shared branch's actual tip **at the start of every new assignment**, not only after a
compaction resume — the two triggers are different mechanisms (context loss vs. a merge nobody
told this worktree about) but the same failure shape and the same fix.

Mid-session, my qa worktree silently detached from the shared feature branch onto `main` (mechanism unclear — no checkout visible in my own turn, likely happened before a context-compaction resume). I spent a full turn "fixing" a 39-svelte-check-error ripple and re-authoring test coverage that was already committed and green on the real branch tip — pure wasted work, because I trusted my own worktree's `git status`/file contents instead of checking what branch/sha it was actually on.

**Why:** A resumed conversation (post-compaction) inherits a summary of what *should* be true, not a live re-read of git state. The worktree's uncommitted local edits survive a branch checkout silently (no conflict, no warning), so a detached-to-main worktree with WIP files layered on top looks completely normal from `git status` alone — nothing flags the branch mismatch unless you check `git log -1` / `git worktree list` against what the OTHER agents' worktrees are actually on.

**How to apply:** At the start of any resumed session (especially post-compaction) and before delivering anything as "verified," check `git log --oneline -1` in the working worktree AND cross-check it against a sibling worktree's branch/sha (`git worktree list` from the repo root, or `git log -1 <shared-branch-name>`). If they don't match, diff the working tree's non-owned files against the real branch tip file-by-file before assuming any local reconstruction is needed — it may already be redundant. This generalizes [[feedback_which_ref_the_probe_was_aimed_at]] and [[feedback_rediff_source_before_reverify]]: the ref that needs checking isn't just "what am I about to verify against" but "what branch is my own worktree even standing on."
