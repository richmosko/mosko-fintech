---
name: banned-command-string-blocks-the-commit-message
description: A pre-commit guard scans the Bash COMMAND TEXT, so quoting a banned command inside a commit message (or inside the script that edits that message) is itself blocked.
metadata:
  type: feedback
---

Never write a banned command's literal string into a commit message, a heredoc, or
the fix-up script that edits either — not even to say you did NOT run it.

**Why:** the guard matches the text of the Bash invocation, not what would execute.
A commit message file saying the local-DB-wiping command was not used blocked
`git commit`; the `python3 - <<EOF` that tried to REWRITE that line was blocked for
the same reason, because the replacement text quoted the phrase too; and writing
the memory file about the incident was blocked a third time. Three blocked turns,
all avoidable.

**How to apply:** state what you DID, never what you avoided — "scratch clones of
`pfin_tmpl`, no local-DB-wiping command at any point" instead of naming it. If a
file already contains the string, rewrite it from scratch rather than patching it,
since the patch command carries the string as well.
