---
name: reconcile-against-diff-not-worktree
description: A teammate's "delivered to temp/, not yet committed" work can leave their own worktree file unchanged — read their .diff, not their tracked tree, before reconciling or you'll duplicate their fix.
metadata:
  type: feedback
---

Reconciling against Backend's split delivery (ADR-058), I read `classify.server.test.ts` straight
from Backend's worktree to see their flagged mechanical fix (a stale 3-level `.eq()` stub). The
worktree copy still showed the OLD 3-level chain and the OLD stale doc-comment — their fix was
NOT reflected there. Checking `temp/backend-split-delivery.diff` instead showed the actual fix
already applied (chain dropped to 2 levels, one doc-comment updated).

**Why this happens:** this project's protocol has non-branch-owning agents deliver a `.diff` (or
full file text) to `temp/` for the branch owner (here, Architect) to apply and commit. An agent
can generate that diff without leaving their own local worktree in the patched state — the diff
*is* the delivery; the worktree is not guaranteed to match it.

**How to apply:** when a teammate's message says "delivered, flagged for you to finish" and points
at a file, do not `Read` that file from their worktree and trust it as current. Find and read
their `.diff` (or the exact text they pasted) instead. Reading the worktree risks (a) missing
their actual fix entirely and duplicating it, or (b) building your patch against a base that
doesn't match what will actually land. This generalizes [[feedback_handed_off_diff_verify_base_not_just_content]]
(verify a diff's base blob) to a prior, cheaper failure mode: verify you're reading the diff at
all, not the possibly-stale tree it was generated from.
