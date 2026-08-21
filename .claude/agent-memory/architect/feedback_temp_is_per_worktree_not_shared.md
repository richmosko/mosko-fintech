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

⚠ **The SESSION-CLOSE SWEEP INHERITS THIS BLINDNESS, and it has been failing
silently.** `.gitignore` ignores `temp/`, so **every worktree carries its own**.
A coordinator sweeping *their* `temp/` sees an empty directory and reports
"`temp/` swept" — while each agent's worktree keeps its own pile. Measured at
SELF-330 close: my worktree held **29 files, oldest nine days old**, from `066`,
ADR-047, ADR-052, ADR-055 and ADR-058 rounds — every one of those sessions
presumably also closed with a "swept" line.

**How to apply:** when the coordinator asks you to confirm a `temp/` discharge,
**confirm and delete in your OWN worktree** — they cannot see or remove yours
unless they reach in by absolute path. And when handing a finding to `temp/`,
give the **absolute** path so the file is reachable at all. The obligation is
discharged **per-worktree, never centrally**.

This is the same shape as the two-controls-one-conclusion pattern: the check
runs, passes, and was never looking at the thing it was meant to observe.
