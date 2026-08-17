---
name: feedback_temp_handoff_files_need_a_shared_path
description: A teammate's "full diff at temp/some-file.diff" reference is only useful if that path is one you can actually read — per-worktree temp/ is gitignored and never syncs; the main checkout's temp/ (or pasting inline) does.
metadata:
  type: feedback
---

On SELF-229, backend twice referenced `temp/self229-backend.diff` as the commit-ready
diff location, but it didn't exist in either their worktree's `temp/` or mine — they'd
written it to the MAIN checkout's `temp/` (`/Users/mosko/Projects/mosko-fintech/temp/`,
not either worktree's copy). Cost two round-trip messages before team-lead found the
absolute path and backend confirmed + apologized.

**Why:** `temp/` is gitignored (deliberately — it's a scratch/handoff buffer, not tracked
state), which means it is ALSO per-worktree: nothing written to one worktree's `temp/`
propagates to a sibling worktree or the main checkout via git, ever. A teammate's
"check `temp/<file>`" instruction is ambiguous unless it also says WHICH checkout — and
the natural assumption (their own worktree, or mine) is wrong exactly when they used the
main checkout instead.

**How to apply:** when a teammate references a `temp/` handoff file for something I need
to act on (not just read for context), and I can't find it in my own worktree, check the
main checkout's `temp/` (`~/Projects/mosko-fintech/temp/`) before asking them to resend —
that's apparently where at least one teammate defaults to writing. If it's still not
there, ask for the content pasted inline in the message rather than another path — inline
is unambiguous and doesn't depend on which of N checkouts anyone is using.
