---
name: fence-must-fail-closed-on-own-dependency
description: A permission/hook fence must fail closed if its own parser or tool dependency is missing or errors — not just when its match pattern doesn't fire.
metadata:
  type: feedback
---

When building a Claude Code `PreToolUse` hook (or any mechanical fence) that shells out to a helper tool (e.g. `jq`) to parse its input, add an explicit preflight that fails closed (deny/block) if that tool is unavailable — don't let a missing dependency silently degrade into "the check didn't run, so nothing was blocked."

**Why:** Building the `supabase db reset` guard (PR #463), my first hook version did `cmd=$(jq -r '.tool_input.command // empty')` with no preflight. Sec caught it: if `jq` were ever absent or errored, `cmd` resolves to empty, the `grep` condition is false, the script exits 0, and the banned command **runs**. Sec's framing: "the guard's entire value is that it fails closed, so a silent single point of failure in its parser is the one defect that matters more than any regex hole" — and it's precisely the kind of defect that goes unnoticed for a long time, because the dependency (`jq`) is present on the dev machine right up until the day it isn't (a fresh container, a stripped-down CI runner, a different agent's environment).

**How to apply:** Any fence hook that depends on an external binary to interpret its input needs `command -v <tool> >/dev/null 2>&1 || exit 2` (exit 2 = PreToolUse blocking error) as its first line, before anything else runs. Apply the same fail-closed treatment to a parse that comes back empty/malformed when the call plainly should have produced content — an empty `tool_input.command` on a real Bash call is itself suspicious and should deny, not silently pass. Verify this by actually breaking the dependency (strip `PATH` to a directory that doesn't contain the tool) and confirming the fence denies, rather than reasoning about it — see [[verify-relayed-reviewer-text-before-applying]] for the same test-don't-trust discipline applied to a different failure surface.
