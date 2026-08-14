---
name: verify-the-bytes-you-commit
description: Copy first, then verify the copy, then commit — verifying a teammate's source file and copying it later leaves a window for a concurrent author, and the commit message then describes bytes you never checked
metadata:
  type: feedback
---

**When committing a file a teammate authored, the order must be: COPY → VERIFY THE COPY
→ COMMIT.** Verifying the source and copying afterwards leaves a window in which the
author can write to it, and the commit then contains bytes nobody checked.

**Why:** SELF-221, 2026-08-13. I ran verification greps against QA's worktree file and
saw `plan(33)`. Several tool calls later I `cp`'d and committed it. **In between, QA
added a fourth leg.** The commit contains `plan(34)` — and the message I wrote says
`(30 → 33)`, *"Verified before commit: plan(33)"*, and *"NOT included: the optional
January/February leg"*, all three false of the commit they describe.

> **I verified one version and committed another, then described the one I had READ
> rather than the bytes I had SHIPPED.**

**The content was fine** — the extra leg was wanted and correct. **The record was wrong**,
which is the part that survives.

**How to apply:**
- **Copy into your own tree FIRST.** Every subsequent check then measures the exact
  bytes `git commit` will take. There is no window.
- ⚠ **The window scales with the number of tool calls between check and copy**, and it
  is invisible: a concurrent author has no idea you are mid-verification, and nothing
  in the copy announces that it moved.
- ⚠ **This is likeliest exactly when things are going well** — a responsive teammate
  improving a file while you review it is the good case, and it is the one that bites.
- **If the sha has already been reported externally, do NOT amend to fix the message**
  ([[incoming-message-is-not-newer-state]] and the ADR-052 rule: a ref is pinned at
  first external measurement). Carry the correction into the PR body, where readers
  actually look, and say plainly that the message misstates its own contents.

Related: [[path-beats-paste-for-reviewable-artifacts]] · [[spot-check-the-contract-at-its-consumer]]
