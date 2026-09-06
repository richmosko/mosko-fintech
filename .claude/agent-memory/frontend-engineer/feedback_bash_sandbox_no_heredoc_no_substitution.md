---
name: feedback-bash-sandbox-no-heredoc-no-substitution
description: Standing rule — no heredocs, no $(...) command substitution, no shell loops/eval in Bash calls; each one prompts F/CTO for manual approval
metadata:
  type: feedback
---

Never use a Bash command the sandbox can't statically analyze: heredocs (`<<EOF`), `$(...)` command substitution, `for`/`while`/`until` loops, `eval`. Each one triggers a manual F/CTO approval prompt regardless of directory or content.

**Why:** F/CTO directive 2026-09-06 — F/CTO runs the whole synthetic team unattended. Every one of these prompts blocks not just me but the entire roster until F/CTO returns to approve it. This is a correctness rule, not a style preference (see [[feedback_approval_prompts_are_a_blocking_cost]] in the shared MEMORY.md index).

**How to apply, concretely:**
- **Commit messages:** write the message to a file with the Write tool, then `git commit -F <file>` (or `git commit --only <paths> -F <file>`) — never `-m`, never a heredoc piped into `-F -`. This supersedes my own earlier practice in this session of using `-F -` with a heredoc body; that pattern must stop going forward.
- **No `$(...)`:** run the inner command as its own Bash call, read its output, then use that value literally in the next call — never nest command substitution inline.
- **No inline shell loops:** `npm run check`, `npx vitest run <paths>` etc. as plain single invocations, not wrapped in a `for`/`while` loop even when iterating over multiple files/paths — pass them as separate arguments or run them as separate Bash calls instead.
- **File I/O:** use Read/Write/Edit tools, not `cat`/`sed`/`tee`/`echo >`.
- **Still fine:** simple `cmd && cmd`, or a pipe to `grep`, with no substitution or heredoc inside.
