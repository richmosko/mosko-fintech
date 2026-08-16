---
name: claude-settings-activation-semantics
description: Project .claude/settings.json permission rules AND PreToolUse hooks both load at SessionStart only — editing the file mid-session does not bind live in that session, for either mechanism.
metadata:
  type: reference
---

When building or testing a permission-deny rule or a hook in `.claude/settings.json` (or `.claude/settings.local.json`), do not expect it to take effect in the same session where you made the edit — for either `permissions.deny`/`allow`/`ask` rules or `hooks.PreToolUse`/etc. Both are read at SessionStart and are not hot-reloaded mid-session in this environment.

Measured directly while building the `supabase db reset` guard (PR #463): edited `.claude/settings.json` mid-session to add both a permission-deny rule and a `PreToolUse` hook, then attempted the exact banned command (and a compound-command form that only the hook, not the permission rule, could catch) in the same session — neither layer fired. This was diagnostic, not just "nothing happened": the compound-command probe (`cd /tmp && supabase db reset --help`) doesn't match any permission-deny pattern (none start with `cd`), so if the hook alone were live it would still have denied that command regardless of permission-rule state. It didn't, which rules out "hooks bind live, permissions don't" as an explanation and confirms neither layer bound in-session.

**How to apply:** Never claim a permission rule or hook is "live" or "active" based on same-session testing after editing `.claude/settings.json`. Pipe-test the hook script's logic directly (synthesize the stdin JSON payload it would receive and run the script against it) to prove the *logic* is correct — that's real evidence. But proving the *harness actually invokes it and honors the output* requires a fresh session started after the edit is on disk. State this distinction explicitly in any fence PR: "mergeable" (logic verified) and "active" (harness-confirmed live) are different claims, and only a fresh-session test earns the second one.
