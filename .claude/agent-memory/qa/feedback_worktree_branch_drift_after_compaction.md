---
name: worktree-branch-drift-after-compaction
description: RECURRED TWICE, two more triggers — verify the worktree is actually on the expected branch/sha before trusting local file state at the start of ANY new task, not only after a compaction resume. It can have silently detached to main between assignments, AND when the branch is already claimed by a sibling worktree, editing can silently fall through to the MAIN REPO checkout instead.
metadata:
  type: feedback
---

⚠ **RECURRED a THIRD time (SELF-248, 2026-08-25) — a NEW failure shape.** At dispatch, my qa
worktree was detached at an unrelated old commit (a prior SELF-247 session's leftover), and
`feature/self-248-classify-backend` was already checked out in the BACKEND worktree — git refuses
the same branch checked out twice. Rather than resolve this (checkout `--detach
origin/<branch>` in my own worktree, which works fine even when a sibling holds the branch name),
I drafted and edited BOTH my new test file and a fix to an existing test file directly in the
**main repo's own checkout** (`/Users/mosko/Projects/mosko-fintech`, on branch `main`) without
noticing — every Read/Write/Edit call used an absolute path rooted at the main repo, not the
worktree, and nothing in the tool output flagged the mismatch. Ran an entire pg_prove verification
pass against the worktree mount before noticing my new file was silently ABSENT from the run's
file listing and an existing-file fix I'd made hadn't taken effect — the error message even still
showed the OLD (unfixed) content. **How to apply:** when a dispatch names a branch already held by
a sibling worktree, `git checkout --detach origin/<branch>` in YOUR OWN worktree still works (git
only blocks the same branch name checked out twice as a *named* branch, not a detached HEAD at the
same commit) — do this FIRST, before the first Read/Write/Edit of the assignment, and confirm with
`pwd`/an absolute-path sanity check that every tool call is anchored at the worktree path, not the
main repo. If you skip this and only discover the mismatch mid-verification: diff the suspect
file's content between the two locations at the last common ancestor commit to confirm no
independent drift, then copy (don't re-author) into the worktree, and revert the stray main-repo
changes so main stays a clean read anchor for F/CTO.

**RECURRED once before (SELF-243, same session as SELF-330, no compaction involved that time).** My qa
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
