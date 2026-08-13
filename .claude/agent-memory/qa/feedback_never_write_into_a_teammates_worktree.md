---
name: feedback-never-write-into-a-teammates-worktree
description: Even a temporary, self-removed copy into another agent's worktree is a boundary violation — it collided with Backend's own live integration run mid-flight and paused their work. Verify against a teammate's code by reading their path, never by writing into it, even briefly.
metadata:
  type: feedback
---

Wanted to verify a new pytest file actually ran against Backend's real
`pfin_back_etl` module before handing it off, so I copied the file into
Backend's own worktree (`mosko-fintech-worktrees/backend`), ran it, and removed
the copy afterward — reasoning that "temporary and self-cleaned" made it safe.
It was not: the file appeared and vanished mid-way through Backend's own
in-progress integration run and paused their work. Team-lead corrected this
immediately: "another agent's worktree is never a write target."

**Why "temporary" and "removed" don't make it safe:** a teammate's worktree is
their live workspace, not a read-only reference — they may have a test runner
watching it, an editor open on it, or their own run in flight at any moment
I can't observe from outside. My tidiness (cleaning up after myself) only
prevented a durable trace; it did nothing to prevent the disruption while
the file existed. [[feedback_full_text_not_path_pointer_to_non_authoring_role]]
already established that I should read a teammate's committed work from their
path rather than asking for a paste — this generalizes the same principle to
verification: read FROM their path (or ask them to run something), never
WRITE into it, not even a scratch file, not even briefly.

**How to apply:** to verify code against a teammate's in-progress module,
either (a) copy THEIR module/interface into MY OWN worktree to test against
a frozen snapshot, or (b) ask the teammate directly to run my test file
against their live tree and report the result — never place a file inside
a worktree I do not own, regardless of duration or cleanup discipline. If a
verification genuinely requires a shared live environment (e.g. a package
that must be installed via `uv sync`/`pip install`), that is itself a signal
to hand the run to whoever owns that environment rather than reaching into it.
