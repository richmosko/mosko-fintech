---
name: clearance-conditions-must-absorb-my-own-recommendations
description: Clearance conditions written for the branch as-it-stands go stale the moment I recommend changes in the same review — reconcile the predicate against my own routed work before sending, and prefer reviewing my recommendations in-PR over deferring them.
metadata:
  type: feedback
---

**Rule: a clearance predicate and my own recommendations in the same review must be
reconciled before the message is sent.** If I write "the final diff must be comment-only"
and then recommend two non-comment fixes, the conditions contradict the routing from the
moment they leave my hands, and a coordinator has to spend a round trip discovering it.

**Why:** happened on `072` (2026-08-14). Conditions were written against the branch as it
stood at review time; the recommendations were written for the branch as it *would* stand.
Both correct in isolation, jointly impossible. Team-lead caught it and had to ask A-or-B.

**Second instance — a VENUE clearance, and it went stale the same way.** Ruling the `054` h14
disposition I wrote *"scratch DB as the sanctioned venue: agreed, no objection"* while requiring a
half-specific annotation telling readers to diagnose which conjunct went red. Both fine alone,
jointly incomplete: **roles are CLUSTER-level (`pg_authid` is a SHARED catalog)**, so a scratch
*database* in the same cluster inherits `pfin_etl`'s retained password and cannot clear h14's
password half at all. My clearance named a venue that does not verify the thing my own annotation
sent people to verify. **A venue clearance is a predicate too — check it against every assertion it
is being applied to, not against the batteries that prompted it.** The tell I missed: h14 reads a
*cluster* object while `053/062/063/064` read *database* objects, so one venue ruling could never
cover both. ⚠ And the reassuring half is the load-bearing one — **CI is already a fresh cluster on
every PR**, so h14 is verified there and merely expected-different locally. Say that explicitly:
**an assertion believed to be unverifiable is an assertion someone eventually deletes.**

**How to apply:**
- Before sending: re-read my own findings section and ask *"does the diff I just described
  as acceptable contain the changes I just asked for?"*
- For any **venue** clearance (scratch DB / local stack / CI), ask what SCOPE each assertion reads —
  cluster-level (`pg_authid`, roles, tablespaces) vs database-level — and name the venue per scope.
  Then name where the assertion IS verified, not only where it isn't.
- Phrase conditions over the **file whose integrity actually matters** (here: "the migration
  blob is comment-only") rather than over the whole diff, which sweeps in the test-surface
  changes I requested.
- **Prefer reviewing my own recommendations in-PR over deferring them.** Two reasons that
  outrank the tidiness of a small diff: (i) it is how I get to **bound the shape** of a
  change I asked for, instead of approving it unseen later — on `072` the LEAK1 predicate
  `= <foreign value>` → `<> <own value>` needed an explicit `is not null and …` so it could
  not pass vacuously on an empty result, which I could only impose while it was in scope;
  (ii) a deferred follow-up PR is a promise with no watcher — see
  [[assertion-with-no-watcher]] in the project index.
- When a fix removes the condition a nearby caveat documents, **say so** — otherwise the
  file ships a live warning for a problem the same commit resolved.
- Any test-count change (`plan(N)`) requires a fresh run through a **TAP-aware consumer**;
  bare `psql` exits 0 on a plan mismatch and makes the new count vacuous.
