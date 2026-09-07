---
name: feedback-shared-memory-file-concurrent-write-race
description: MEMORY.md is shared across every session running this role — a dedup/prune pass got silently clobbered mid-session by a concurrent "qa" session writing an older, undeduped snapshot back. 2026-09-06.
metadata:
  type: feedback
---

Pruned MEMORY.md from ~29KB (over its ~24.4KB read limit, with the file's own header
already flagging duplicate entries) down to ~16KB in one pass, added new entries, and
moved on to other work. Came back later in the SAME session to add two more entries and
found the file back at ~29KB, containing the OLD, undeduped, pre-prune content — my prune
pass and everything added after it was gone. No error, no conflict signal — it just silently
reverted. The only plausible explanation: another session running this same "qa" role wrote
to the identical file path around the same time, using a stale in-memory copy as its base
and overwriting mine.

Recurred at the cross-checkout boundary too: the MAIN checkout's `.claude/agent-memory/qa/`
(the durable home per team-lead's ruling — agent memory does not ride a feature branch) had
ALSO diverged independently by the time this was checked — a different new entry
(`feedback_returning_clause_needs_select_on_every_returned_column`) had landed there that
this worktree's copy never saw, and main's own copy was ALSO still undeduped. Two
independent copies of the same file, both actively being written by different sessions, is
the actual topology — not one shared file with an occasional race.

**How to apply:** this file has no locking and no merge — a plain overwrite. Do not assume
a completed prune/dedup pass on MEMORY.md stays completed across a session boundary or a
long gap; re-check its size (`wc -c`) before trusting it, especially after resuming from a
hold or a compaction. When reconciling two diverged copies (e.g. worktree vs. main
checkout), diff them first and merge by ADDING each side's unique entries rather than
picking one side wholesale — a wholesale overwrite in either direction destroys real work
from the other session. There is no way to detect or recover content lost to an overwrite
that already happened; the best available response is to redo your own known-good content
and flag the race in the handoff, not to chase what was lost.
