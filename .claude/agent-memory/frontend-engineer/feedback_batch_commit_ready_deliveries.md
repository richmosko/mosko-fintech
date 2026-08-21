---
name: batch-commit-ready-deliveries
description: Deliver commit-ready path+md5 handoffs as ONE batch after all edits are done, never piecemeal as each file/pass finishes
metadata:
  type: feedback
---

Deliver commit-ready `path + md5` text to a non-committing teammate (Architect as sole committer, per the worktree/branch-ownership convention) in ONE consolidated message covering every changed file, sent only once every file is in its final state for that unit of work — never one file at a time as each finishes, and never a file mid-revision.

**Why:** on SELF-330, I sent three separate deliveries as I completed each editing pass (initial type-tightening, then a follow-up precision pass after a teammate's verbatim clarification arrived). Architect read the tree between two of my sends and found a file's live content no longer matched the md5 I'd sent minutes earlier — I was still editing it. The whole point of an md5 in a handoff is that it names something stable between send and read; a "here's file A, more coming" delivery breaks that invariant even when each individual send was true at the moment it was sent.

**How to apply:** when a task touches multiple files and involves more than one edit pass (e.g. an initial implementation, then incorporating a teammate's follow-up correction), hold ALL commit-ready output until every file is finished — do not send an interim delivery just because one file settled first. If new information arrives mid-task that requires re-editing an already-sent file, treat the whole batch as still-in-progress and re-send everything together once it's stable again, explicitly noting which files changed since the last (informal) mention. Only exception: genuinely independent deliverables with no shared review/commit boundary — those can ship separately since there's no single "done" moment to wait for.
