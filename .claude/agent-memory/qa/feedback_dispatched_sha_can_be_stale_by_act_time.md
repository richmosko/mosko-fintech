---
name: feedback-dispatched-sha-can-be-stale-by-act-time
description: team-lead named 158a644 for feature/self-355-db; by the time the rebase actually ran, origin had already moved to 924085d (Sec FLAG-7, required new guards). Re-read the ref before acting, not just before verifying. 2026-09-06.
metadata:
  type: feedback
---

Dispatch named `origin/feature/self-355-db @ 158a644` as the rebase target for 113's
message re-aim and the 115 snapshot legs. Ran `git log --oneline -1 origin/feature/self-355-db`
before rebasing (standard premise-check) and found the branch already at `924085d` — one
commit past the named sha, landed after the dispatch was written: "115 asserts the payload
path resolved and the child cardinality — FLAG-7," adding required guards (14h's four
restructuring shapes) that the dispatch's own pairing-list spec did not yet know about.

Rebased onto the CURRENT tip (924085d), not the stale named sha — the alternative
(rebasing onto 158a644 as literally instructed) would have shipped a battery that never
saw FLAG-7's guards at all, silently under-covering the migration that had already landed
on origin. Flagged the discrepancy in the handoff rather than silently substituting.
Recurred once more the same day: team-lead's follow-up named 924085d, and by the time the
rebase ran origin had moved again to 12ccd2f (a comment-only close-out of FLAG-7, adding a
14i disclosure item) — same discipline, same result: re-read, act on the current tip,
report what actually landed.

**How to apply:** [[feedback_reread_the_ref_before_dispatching]] already covers re-reading
before DISPATCHING; this is the same discipline applied at the OTHER end — re-read
immediately before ACTING on a dispatch too, even one that names a specific sha, since the
gap between "team-lead wrote the message" and "you run the command" is enough time for
origin to move. A named sha in a dispatch is the sha AS OF WRITING, not a promise it still
matches HEAD — treat it as a lower bound and verify the real tip before rebasing onto it.
