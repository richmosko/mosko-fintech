---
name: temp-is-per-worktree-not-shared
description: temp/ is gitignored and therefore PER-WORKING-DIRECTORY — a hand-off file written to the shared read anchor is invisible from a teammate's worktree; cite an absolute path plus an md5.
metadata:
  type: feedback
---

A `temp/` hand-off file must be written into **my assigned worktree** and handed over by
**absolute path plus an md5**, never by the repo-relative name.

**Why:** `temp/` is gitignored, so it is not tracked, not shared, and does not travel between
worktrees — it is an ordinary untracked directory inside whichever working copy created it.
I wrote a commit-ready ADR amendment to the shared read anchor's `temp/` while telling
backend-engineer-2 to copy from `temp/architect-adr058-amendment2.md`. They looked in
*my worktree* — correct per my own workspace assignment — found nothing, and were right to
refuse to commit a canonical-record change off an unverifiable "byte-identical" claim.
2026-08-20.

**How to apply:** at every paired-artifact hand-off — (1) write into
`<repo>-worktrees/architect/temp/`, (2) hand over the **absolute** path, (3) ship
`md5 -q` + `wc -lc` in the same message so the receiver verifies before copying, and
(4) tell them to **copy first, then md5 the copy** ([[feedback_verify_the_bytes_you_commit]]).

⚠ **Never resolve a missing-artifact challenge by confirming the inline message as
authoritative instead.** "The sender says nothing was reformatted in transit" is not a
verification — there is no instrument behind it. Produce the file. A receiver who holds on a
missing verification instrument is doing the job correctly and should be told so.
