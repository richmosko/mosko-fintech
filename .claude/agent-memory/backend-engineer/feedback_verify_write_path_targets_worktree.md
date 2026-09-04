---
name: feedback_verify_write_path_targets_worktree
description: Write/Edit calls use absolute paths that default to the main repo checkout unless explicitly rooted in the assigned worktree — verify before the first Write of a dispatch.
metadata:
  type: feedback
---

When dispatched to work in a per-agent worktree (`~/Projects/mosko-fintech-worktrees/<agent>`, per [[reference_agent_worktrees]]), `Bash` `cd` into the worktree does NOT change where `Write`/`Edit` land — those tools take an absolute `file_path` argument, and it is easy to default to the familiar main-repo path (`/Users/mosko/Projects/mosko-fintech/...`) out of habit, especially when reads earlier in the same turn used that path (e.g. reading `CLAUDE.md`, `DECISIONS.md`, `docs/records/...` from main, which is correct — those are read-only reference reads).

**Why this matters:** authoring a whole feature's worth of files in the main checkout instead of the worktree means (a) the main checkout — the shared read-anchor other agents/F-CTO treat as clean `main` — now carries uncommitted work, (b) `vitest`/`svelte-check` run from the worktree silently see NONE of it (zero-collection, not an error), producing a false "all green" on an empty diff, and (c) the eventual `git commit` in the worktree has nothing to commit until the mistake is caught.

**How to apply:** before the FIRST `Write` of a dispatch that specifies a worktree, state (or mentally confirm) the absolute path prefix you intend to use for every subsequent `Write`/`Edit`, and make it the worktree's path, not the main checkout's. If the mistake is caught after the fact: `cp` each authored/modified file from the main-checkout path to the matching worktree path, then in the main checkout `git checkout -- <modified files>` + `rm` the accidentally-created new files, and verify with `git status --short` that only pre-existing OTHER agents' unrelated changes remain — never touch those. Re-run tests from the worktree only after the copy, since a same-directory `vitest run` from the wrong root won't error, it'll just under-count.

Caught and corrected in-session at the SELF-259 AC6 tax-brackets endpoint dispatch (2026-09-03) before any commit — no main-checkout contamination reached git history, but the false-green risk (vitest reporting 0 new test files with no error) was real and is exactly the failure shape [[feedback_worktree_symlinked_node_modules_zero_collection]] already warns about, from a different root cause (wrong directory vs. symlink issue).
