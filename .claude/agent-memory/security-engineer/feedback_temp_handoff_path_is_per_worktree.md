---
name: temp-handoff-path-is-per-worktree
description: When routing findings to temp/, give the ABSOLUTE worktree path and say it is per-worktree — the coordinator checking from the shared checkout sees an unchanged/absent file and reads it as "no work done"
metadata:
  type: feedback
---

`temp/` is **per-worktree and gitignored**. A findings file I write at
`…/mosko-fintech-worktrees/sec/temp/<topic>.md` is **invisible** from the shared checkout or any other
agent's worktree — there is no sync, and `git status` shows nothing.

**Why:** at SELF-229 round 2, team-lead opened a diagnostic ("your review notes file is unchanged since
the first verdict") as evidence that my re-review had not happened. The file had in fact been rewritten
with a full round-2 section minutes after the request. **Correction to my first reading of this
incident:** my verdict message was NOT lost — it had already arrived and the diagnostic simply crossed
it in flight. So the ONLY real defect was the wrongly-located file check, and it was doing all the work:
it made an ordinary async crossing look corroborated as "no work done." A location misread is
load-bearing precisely because it reads as independent confirmation of a timing artifact.

**How to apply:** whenever a hand-off cites `temp/`, give the **absolute** path AND one clause saying it
lives in my worktree and will not appear elsewhere. When a teammate reports my file as stale or missing,
**do not re-do the work** — measure it (`ls -l` mtime + `head`/`grep` for the newest section) and reply
with the mtime, size, and the marker string, then name the path mismatch as the likely cause. A stale-file
report is a location claim, not a content claim.

Corollary for the coordinator's obligation: a per-worktree overflow file is even less durable than the
"gitignored, no watcher" framing suggests — it is also **unreachable** to the party who owns placing it.
Prefer putting the load-bearing criterion **inline in the message** and treating `temp/` as evidence
backup only. Every criterion I expect someone to act on goes in the message text verbatim.

Related: [[read-the-branch-from-the-ref-not-the-worktree]] (the same worktree-vs-canonical-location
confusion, one layer down).
