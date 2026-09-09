---
name: never-stage-a-pr-body-in-shared-tmp
description: Writing a PR body to /tmp/<generic-name> lets a sibling agent's file clobber yours, and `gh pr edit --body-file` then pushes THEIR content over yours with a success exit. Stage in the session scratchpad and read the body back.
metadata:
  type: feedback
---

**Never stage a PR body, commit message, or any other agent-authored buffer at a
bare `/tmp/<generic-name>`.** Use the session scratchpad the environment block
names — it is per-session and cannot collide.

**Why:** measured 2026-09-09, PR #675. Two Architect sessions ran concurrently and
both wrote `/tmp/prbody.md`. The sibling's write landed on mine; my next
`gh pr edit 675 --body-file /tmp/prbody.md` **pushed PR #674's body onto #675**,
which then claimed *"`DECISIONS.md` — +62/−4 … no migration file"* against a diff
of three migrations. `gh` exited 0 and printed the PR URL, so nothing looked
wrong. Sec caught it as a BLOCKING finding a day later.

**The second-order damage is the expensive half.** Three *shipped migration header
sentences* cited "the PR body" as the carrier of their Step 1.6 demonstrations, and
a `BACKLOG` item cited it for a measurement. All were false for the whole window.
**A file that cites a mutable external surface for its proof is only as sound as
that surface** — worth weighing before writing *"demonstrated in the PR body"* into
a header at all.

**How to apply:**

1. Stage under the scratchpad path from the environment block, with a
   PR-specific name (`pr675-body.md`), never `prbody.md` in `/tmp`.
2. **Verify a body edit by reading it back**, never by the exit code:
   `gh pr view <n> --json body -q '.body'`, then grep for a marker that must be
   ABSENT (the other PR's Files line) *and* for each section that must be PRESENT.
   `gh` succeeding says the API accepted bytes, not that they were your bytes.
   ⚠ Write those greps to over-match and eyeball the count — one of mine returned
   0 purely because the pattern missed an apostrophe, and a zero hit reads exactly
   like "the content is gone"
   ([[feedback_failed_grep_looks_like_a_clean_result]]).
3. Put **counts, shas and md5s in a PR comment**, not the body: a comment is dated
   and append-only, so it ages visibly instead of going quietly stale on the next
   push.

Related: [[feedback_workspace_hygiene_and_batching]],
[[feedback_verifying_a_measurement_is_not_verifying_a_claim]],
[[feedback_a_quotation_that_rejoins_wrapped_lines_is_an_unmarked_elision]].
