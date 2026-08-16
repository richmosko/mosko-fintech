---
name: stale-worktree-listing-misreads-the-tree
description: A bare `ls` in a per-agent worktree reads whatever ref that worktree is parked at, not current main — use `git ls-tree origin/main` for next-free numbers and existence checks
metadata:
  type: reference
---

**In this repo every agent has its own worktree, parked detached at whatever ref it was last
left on. So a filesystem listing answers a question about THAT REF, not about `main`.** For any
claim about what exists in the project — next-free migration number, whether a file has landed,
whether a citation resolves — read the ref explicitly:

```
git fetch --quiet origin
git ls-tree origin/main supabase/migrations/ --name-only | tail -3
```

**Why: twice in one session, two different agents, two different consequences.**

1. **Mine, authoring `073` (2026-08-14).** `main` moved **twice** during the item
   (`c3c1547` → `4270495`). My local listing was behind, so `ls supabase/migrations/` would have
   handed me a next-free number derived from a stale tree. Caught by taking the number from
   `git ls-tree origin/main` instead. A migration number is a **one-way door once merged** — a
   collision is a rename plus every reference to it.
2. **Sec's, reviewing the same branch.** Their worktree was parked at `d0f66eb`; a bare `ls`
   there **made my `072` citations look fabricated** — the files I cited genuinely were not in
   that worktree. They re-read from `origin/main` before sending, so the finding was never
   filed. **The failure mode here is not a wrong number, it is a false accusation against a
   teammate**, and the only thing standing between the two is remembering which ref you are
   standing on.

**How to apply:**
- Treat `ls` in a worktree as a question about a ref you must name. If you cannot name it, run
  `git rev-parse HEAD` first.
- **Before verifying anyone's citations, `git fetch` and read from `origin/main`** — "the file
  isn't there" is a claim about a ref, and the most likely explanation is that yours is old.
- ⚠ Both instances were caught by the same habit — re-reading from the authoritative ref before
  acting — and neither would have been caught by more care applied to the wrong instrument.

Related: [[instrument-cannot-observe-the-property]] · [[relay-from-the-tree-not-the-report]]
