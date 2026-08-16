---
name: handed-off-diff-verify-base-not-just-content
description: A teammate's diff/patch handoff can be stale relative to the CURRENT shared tree even when its content is correct — trace its base blob to a commit before trusting `git apply` will land it safely.
metadata:
  type: feedback
---

When a teammate hands off a diff (a `.diff` file in `temp/`, not a live commit) against a
shared-branch file, its CONTENT can be exactly right while its BASE is stale — authored against
an earlier commit than the file's current tip, because other agents landed work on that same path
in the meantime. The diff still "looks fine" on read-through; only `git apply --check` (or tracing
the diff's `index aaa..bbb` blob hash back to a commit via `git ls-tree <commit> -- <path>`)
reveals it won't apply cleanly.

**Why:** during SELF-229's staleness-root ruling, backend handed off
`temp/self229-staleness-rework.diff` touching 8 files. I verified the SHAPE was correct (tri-state
`is_stale`, distinct `UNKNOWN_STALENESS` constant) by reading the diff directly — good instinct —
but almost stopped there. Running `git apply --check` per-file showed 6 of 8 failed against the
branch's current tip; tracing `navComposition.ts`'s base blob (`0527dda`) to a commit found it
predated the composition per-leaf join (e7b8da9) AND my own already-delivered, already-committed
battery (143d183) entirely. A naive full-file copy or blind patch on those 6 files would have
silently reverted landed, tested, committed work — the exact clobber class in
[[feedback_stash_checkout_path_clobbers_intervening_changes]], this time arriving from a
teammate's own handoff rather than my own git op.

**How to apply:** before recommending — or delivering alongside — ANY handed-off diff/patch
touching a shared file, run `git apply --check --include=<path> <diff>` per file, not just once
for the whole diff (a multi-file diff is atomic; one bad hunk masks whether the others are fine).
On failure, trace the diff's stated base blob hash to the commit it belongs to
(`git ls-tree <sha> -- <path> | awk '{print $3}'` across the file's `git log --oneline -- <path>`)
to see HOW stale it is and what landed in the gap — that tells you whether hand-reconciliation is
a small drift (one intervening docs commit) or a large one (a whole feature landed since). Report
the finding as "N of M files apply clean; here's what's missing from the stale base" — not a bare
"looks correct" after reading content alone.
