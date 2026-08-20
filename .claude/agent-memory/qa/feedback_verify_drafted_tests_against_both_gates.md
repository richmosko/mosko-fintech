---
name: verify-drafted-tests-against-both-gates
description: Commit-ready test content authored for a teammate to commit must be verified with BOTH vitest run AND npm run check before hand-off, not vitest alone.
metadata:
  type: feedback
---

When authoring commit-ready test text I can't commit myself (QA's tool boundary — Frontend/Backend
own the branch commits), verifying it with `vitest run` on a temporary copy is NOT sufficient
before delivering it. `vitest run` doesn't typecheck; `npm run check` (svelte-check) does, and the
two catch different classes of defect.

**Incident (SELF-241, 2026-08-20):** drafted a `+page.svelte` DOM test for the AC6 back-link leg,
verified it with `vitest run` on a temp copy (3/3 passed), delivered it. Frontend committed it
verbatim. Team-lead's re-verdict ask made me run `npm run check` for the first time against the
committed file — 3 real typecheck errors: the fixture's `data` prop only had the two fields this
page's own loader returns, missing the three fields the root `+layout.server.ts` merges into every
route's `PageData` type (`userEmail`/`pendingClassificationCount`/`connectionHealth`). Vitest never
saw this because it doesn't typecheck component props at all. This would have failed CI.

**Why:** vitest's `render()` in a `.dom.test.ts` runs the compiled component against whatever prop
object you pass — it has no visibility into whether that object satisfies the component's declared
prop TYPE. Only `svelte-check`/`tsc` enforces that. A test file can pass every runtime assertion
while being a compile error.

**How to apply:** before handing off ANY drafted-but-uncommitted test file (not just for
SvelteKit routes — anywhere prop/param types are involved), run BOTH gates against a temporary
copy in the worktree: `vitest run <file>` for behavior, `npm run check` for the whole tree for
types. Restore the worktree (`git checkout --` or `rm`) immediately after, confirm `git status`
clean, before reporting. Doing only the first gate is a process gap that reads as "verified" but
isn't — see [[feedback_run_before_deliver_when_migration_is_committed]] for the parallel discipline
on the migration side (verify before deliver, not verify-shaped-like-verify).
