---
name: feedback-verify-against-commit-not-head-when-disputing-history
description: When a teammate disputes what an earlier commit contained, diff that SHA directly (git show <sha>:path) — diffing their delivery against the current worktree/HEAD only proves HEAD is right now, which is true whether or not the disputed earlier commit was right.
metadata:
  type: feedback
---

On SELF-242 (2026-08-20), frontend-engineer sent a "correction" claiming commit `b3f9227` already had their cause-neutral copy fix, based on diffing their latest delivery against my worktree — which by then had already absorbed a LATER commit (`e846765`) applying that exact fix. The diff came back empty, so they concluded the earlier commit must have had it too. It hadn't: `git show b3f9227:path | grep "Not removed"` showed the OLD copy; `git show e846765:path` showed the fix; `git diff b3f9227 e846765 -- path` showed a real, non-empty diff.

**Why:** "diff my delivery against the current tree" only tests the tree's CURRENT state (HEAD), which trivially matches once the fix has landed via ANY commit — it cannot distinguish "commit N had this" from "commit N+1 added this and N didn't." A worktree/HEAD comparison is state-at-a-point, not history.

**How to apply:** when a teammate disputes which commit introduced/contained a specific change (or claims something "was already there"), verify with `git show <the-disputed-sha>:<path>` (or `git diff <shaA> <shaB> -- <path>`) — never by diffing against the current worktree or HEAD, which conflates "true now" with "true then." This is the same class of error as [[feedback_which_ref_the_probe_was_aimed_at]] in the shared team memory (a control string passing on the wrong ref) — here the "wrong ref" is HEAD standing in for a specific historical commit. Re-litigate politely but with the exact evidence (the `git show`/`git diff` output) rather than just asserting the correction is wrong.
