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

**Third instance — the same scope error inside a REMEDIATION, not a clearance (2026-08-17,
`feature/cash-seed-and-kernel-gates`).** A venue rule reached me as *"revert the grant, **or
retire the DB**"* for a `GRANT supabase_admin TO postgres` run "on scratch_077". The second
branch is **ineffective by construction** — `pg_auth_members` is a shared catalog, so
`drop database` leaves the grant fully live, and taking that branch would have **closed the
item while the escalation persisted**. Measured: `set role supabase_admin` from `postgres`
yielded `current_user=supabase_admin, rolsuper=t`, and `grep -rni "grant supabase_admin"`
over the tree returned nothing — an unreviewed superuser path in no artifact. **A disjunctive
remediation is two claims; a scope error in either branch is a way to mark the finding fixed
while it is not.** Also: the REVOKE order is load-bearing — clean `... GRANTED BY
supabase_admin` duplicates FIRST, then revoke the `supabase_admin` membership, or the role
loses the rights needed to do the first.

**⚠ My step 2 was NOT EXECUTABLE as written — a claim separate from the ordering being right.**
I reasoned *"postgres needs the rights the membership confers to revoke a supabase_admin-granted
membership"* (**true for step 1**, which is why it must run first) and carried it into step 2
unchecked. Revoking a **SUPERUSER** role's membership requires the **SUPERUSER ATTRIBUTE**, not
membership: `pg_authid.rolsuper` is an attribute and is **never inherited through
`pg_auth_members`**. The only path was `SET ROLE supabase_admin` — the escalation used once, in
one session, to close itself (ruled acceptable: privilege-equivalent to the `supabase_admin`
login that also exists, and self-extinguishing). **When prescribing an ordered command sequence,
ORDERING correctness and per-step EXECUTABILITY are two different claims — check both.** The
attribute-vs-privilege discriminator is the same one I apply at `prosecdef`.

**Fourth lesson, same close-out: PROBE the residual, do not hedge it.** I was about to write that
the REVOKE only reduced *accidental* exposure, since `054`'s header records `pg_hba trust` on
`127.0.0.1/32` and `supabase_admin` is `rolcanlogin=t`. **Measured instead: a `supabase_admin`
connection on that path demands a password** (`fe_sendauth: no password supplied`). The
remediation was stronger than my draft. **An overstated residual gets budgeted against exactly
like an understated one** — run the probe before writing either.

**Closure evidence for an empirically-established finding = the same instrument, inverted.**
`set role supabase_admin` returned `supabase_admin | rolsuper=t` before and
`ERROR: permission denied to set role` after. Accept nothing weaker for a finding that was
found by probe.

**⚠ THE INVERSE FAILURE — springing a NEW condition after clearance was scoped. Do not ratchet.**
At SELF-328 I offered two remediation options and wrote *"choose on legibility, not on strength —
both close the hole completely."* QA chose B. B's leg then had no in-file golden proof that it
bites, which by my own FENCE1b standard is a gap — **but I could have required it when I offered
the option and did not.** Ruled it a FLAG with the exact fixture shape attached, not a condition,
and said in the message why. **A review that keeps growing conditions teaches that satisfying them
does not end it.** When an option I authorised turns out to need one more thing, the cost of that
lands on me: state it as a recommendation, hand over the shape so adoption is free, and let the
clearance stand. Conditions ratchet only when the new finding is a DEFECT, never when it is a
standard I forgot to apply to my own menu.

**⚠ A DISPOSITION CAN RE-PURPOSE MY CONDITIONS WITHOUT TOUCHING THEIR TEXT.** At SELF-325
I raised the unrepairable global registry and routed the scope call to F/CTO, who ruled
*accept the posture, with C1 + C2 as the V1 controls.* My C1/C2 were authored as the
cheapest fixes for one finding; that ruling silently promoted them into **the compensating
controls a ratified one-way door now rests on** — a heavier job than the one they were
written for, and their text says nothing about it. Left unstated, the next person to
refactor that endpoint deletes a "fix test" and takes the posture with it.
**When a finding is dispositioned accept-with-compensating-controls, say three things in
the same message:** (i) the named controls have changed job; (ii) weakening or descoping
either **reopens the decision rather than carrying forward**; (iii) their paired tests are
**posture watchers**, not fix tests, so nobody prunes them as redundant. Also ask where the
posture DURABLY lives — a work-queue Source line is not where a future reader looks for
*why we tolerate this*; recommend the decision record and let the queue entry link to it.

**⚠ A CONDITION CAN INVALIDATE A PIN THAT LIVES IN A FILE I AM NOT ASKING ANYONE TO TOUCH.**
At SELF-248 / `092` I required the existing-violation query be inlined into the migration
header — a `--` block, zero executable lines, nothing reaching `pg_description`. But QA's
paired battery header pins the migration blob by **md5**, so my comment-only edit
invalidates a hash in a *different file owned by a different agent*. Caught it while
drafting and shipped the condition as an explicit **pair** (Architect edits the header, QA
re-hashes and updates the FINALIZED-against line, same PR) plus an escape hatch (put the
query in the PR body instead, no file change, no pin break). **"Comment-only" bounds the
BEHAVIOUR of a change, never its BLAST RADIUS** — before requiring any edit, grep for
what binds to that file's bytes (`md5`, `sha`, `git show HEAD:<path>` hashes, exact-string
catalog assertions). See [[my-review-measurements-become-quoted-sources]] and
[[verify-the-stated-correctness-mechanism]]: the pin is a real control and breaking it
silently is worse than the reproducibility gap I was closing.

**How to apply:**
- Before sending: re-read my own findings section and ask *"does the diff I just described
  as acceptable contain the changes I just asked for?"*
- For every edit I require, ask **what binds to that file's BYTES** — an md5/sha pin, a
  hashed-blob assertion, an exact-string catalog leg. If something does, ship the condition
  as a pair with its owner named, or offer a venue that avoids the byte change entirely.
- After any ruling on one of my findings, re-read **my own conditions** and ask whether the
  ruling changed what they are holding up. A condition whose text is unchanged can still
  have acquired a new dependent.
- When offering 2–3 remediation options, **state the acceptance bar ONCE, for all of them** —
  including any paired-fixture or watcher requirement. Anything I omit there, I own later.
- Apply the cluster-vs-database scope check to **remediations and "either/or" rules**, not
  only to clearances. For each branch of a disjunction ask: *does this actually remove the
  thing?* Prefer prescribing the single effective action over relaying someone's menu.
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
