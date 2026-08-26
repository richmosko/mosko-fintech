---
name: corrupt-the-control-canary-boundary-tie
description: Ways a corrupt-the-control leak canary fails to bite — boundary-date ties, probing the table not the surface, revisions that fix framing not mechanism, a same-date A/B fixture that defeats both legs, third-party displacement on a data-bearing stack, corrupting the WRONG relation set so the flagged fence is never exercised, and a helper that LEAKS the RLS role context so the next leg is vacuous.
metadata:
  type: feedback
---

Two failure modes in `corrupt-the-control` leak canaries (break the RLS policy open with
`using (true)`, assert another tenant's row is now visible). Both found on the `071`/`072`
`fn_nav_delta_panel` battery.

**1. A canary pinned to a boundary date ties, it does not lose.** If the canary row sits at
exactly the boundary of an `at-or-before ... order by desc limit 1` query, no other row can
be *strictly more recent* — the only way it is displaced is a **tie at that exact date**,
resolved arbitrarily. So a trace explaining a flaky RED as *"a real tenant's row is more
recent"* is mechanically impossible and therefore a misdiagnosis, even when its conclusion
(environment property, not a regression) is right. **The misdiagnosis is what costs
something: it implies no fix exists short of a pristine DB.** One does — assert the
**negative predicate** (`nav_value <> <A's own value>`) rather than the specific foreign
value. Same security meaning ("A's read is no longer confined to A"), robust to any extra
rows the shared dev DB carries.

**Why:** the SELF-217 seeding run put real month-end checkpoints in the shared local dev DB,
and the canary sat on the last completed month-end. A fixture offset designed to break an
**A/B** tie does nothing about a **third-party** tie.

**2. Check what the canary actually probes.** A canary that queries the *table* proves the
policy fences the table; it does not prove the *function's output* is fenced by nothing but
that policy. That gap is exactly where a later redundant local `users_id` predicate hides —
the thing QA measured on `062`. Ask for a canary that calls the surface under test, and
name a **deterministic** column to assert on (a provenance column like
`anchor_checkpoint_date` is often deterministic where the value column is not).

**3. A "fuller version that supersedes" can preserve the defect while improving the frame.**
The `072` caveat was rewritten (`f9cdd65` → `a6aa5db`) into a materially better note — right
cross-reference to the canonical environment-sensitive-RED leg, plus a new
why-CI-is-unaffected paragraph that was the actually load-bearing addition — **and carried
the wrong mechanism through verbatim in substance.** Re-read superseding text against the
original finding; do not let "supersedes, fuller" stand in for "fixed". The tell that made
it sharp: the file already contained its own refutation two blocks away (the leg's own
description states the boundary fact that makes the caveat's mechanism impossible), so the
rewrite had the answer in front of it and passed over it.

**4. A fixture that seeds A and B on the SAME date to be "non-vacuous" can defeat BOTH the
positive leg and the negative probe.** Found on `self228_v1_1_close_gate.sql` (PR #464). The
header's stated discipline — *"A and B hold checkpoints on the SAME dates with DIFFERENT
values … a same-value fixture would pass under a broken tenant predicate"* — is true of a
**sum** leak and false of a **pick-one** leak: `fn_nav_series`'s selector is
`order by nd.nav_date desc limit 1` with **no tiebreak column**, so under a leak the tie
resolves arbitrarily and can land on A for every period. Then the exact-equality leg passes
AND the negative probe (`where nav_value in (<B's five values>)`) returns empty. **Mode 1's
remedy does not rescue mode 4** — the tie here is designed into the fixture, not imported
from the environment, so no predicate over A's own call can see it. The only fix that bites
is a **two-sided positive leg**: the identical call under B must return B's literal. One
tiebreak outcome cannot satisfy both sides. Tell: a function whose isolation legs are
`{A-exact, negative-probe, zero-owner}` with **no B-side positive** — every sibling function
in that same file had one, which is what made the two exceptions visible.

**5. THE CLASS FACT, and it bounds mode 4's remedy too.** Any corrupt-the-control canary asserting a
**specific foreign value** through a `limit 1`-style selector is subject to **third-party displacement**
on any stack carrying real data. Confirmed twice on the same mechanism: SELF-217 seeding (mode 1) and
the 2026-08-14 recovery, where `062`'s (V1) canary — B's month-end `2026-03-31 = 5000` — collides with
the recovered dataset's own month-end row and loses an arbitrary tiebreak, so the leg goes RED **for
the wrong reason** and is blind to the leak it exists to detect. ⚠ **My own mode-4 remedy inherits
this.** The two-sided positive legs I blocked SELF-228 on use synthetic dates inside the recovered
span, so under a leak on a data-bearing stack a real month-end row is *strictly more recent* and
displaces **both** sides — not a tie, a loss. The fix is still right (correct under a working fence on
every stack; full teeth in CI) but **the counterfactual-catch property is venue-dependent, and I did
not examine the venue when I demanded it** — I reasoned about the fixture, not the stack it runs on.
**The leg shape that IS immune:** query the raw table filtered on `users_id = <other tenant>` and
assert a **COUNT**, not a `limit 1` winner — unselected third-party rows cannot displace a count. Ship
it as a **COMPANION, never a replacement**, and name the losing side: a table-level leg cannot prove
function-output propagation, cardinality, provenance-column, or grant-path channels. ⚠ Distinguish it
in writing from the redundant-predicate anti-pattern (`062`'s (V3)): a `users_id` filter in the
**observer** targets the leak; the same filter in the **read path** suppresses it.

**6. THE CORRUPTION TARGETED THE WRONG RELATION SET — the canary exists, and the flagged fence is
still unfalsifiable (SELF-330 / `086`).** A function had TWO legs: a securities leg fenced only by
inherited RLS, and a cash/liability leg carrying an explicit conjunct (`lut.users_id = acc.users_id`)
on a join keyed by **shared-vocabulary string labels**. The migration header, the `comment on
function`, and the battery's own section title all named that conjunct as the joint-review-mandatory
control. The battery had X1/X2 corrupt-the-control legs — and they corrupted `account_select` /
`account_trans_select` / `account_balance_checkpoint_select`, the **securities** leg's relations.
`pfin.user_taxonomy` was corrupted nowhere. **All four legs named after the fence passed with the
conjunct struck out**, because under normal RLS the caller sees only their own taxonomy row and only
their own accounts, so nothing in the file could tell the fence from its absence.

**The tell is structural and cheap: a fence whose stated failure mode is "fails OPEN under an RLS
regression on relation R" is only measured by a leg that corrupts R.** A battery that corrupts a
*sibling* relation and asserts normal-condition isolation is asserting what RLS already gives you.
Ask, per fence: which single policy, broken open, makes this conjunct the sole discriminator? Corrupt
**that one**, then assert the **winner** (`array_agg(key order by key) = array[own_key]`), never a
`count(*) = 1` — a count passes if the one surviving row carries the FOREIGN key, which is the leak.
And require the leg be **demonstrated RED with the conjunct struck**, with the observed failing value
reported; a leg added alongside the control it guards proves only self-consistency.
**Why this is worth blocking on rather than booking:** the assertion that the control is load-bearing
ships durably into `pg_description`, and the legs are *named after* the fence — post-merge, "covered"
becomes the assumed state and the next reader must re-derive that the coverage was nominal.

**How to apply:** at any battery review, ask (a) can the canary's expected value be tied
or displaced by rows outside the fixture, (b) does the canary invoke the surface or
something beneath it, and (c) if the text was revised after a finding, does the revision
touch the finding or only its framing. None is usually merge-blocking — all are QA
follow-ups — but say so explicitly rather than leaving the canary's teeth unexamined.

Related: [[which-ref-the-probe-was-aimed-at]] — a ref correction mid-review means
re-measuring the delta from the tree yourself (blob SHA equality, hunk headers, a
non-comment-lines filter in BOTH directions) before transferring prior findings forward.

**A control that WORKED, recorded so I repeat it — the BOUNDARY PAIR (SELF-325, `087`).** To prove a
`22003` rejection was about *crossing `numeric(28,8)`'s ceiling* rather than about magnitude in
general, QA paired `quantity=1e20` (21 integer digits, rejected) with `quantity=1e19` (20 digits,
`lives_ok`) and **held every other operand identical** (`cost_basis=9e15` on both sides). One
representable step apart, one moving part. **A non-vacuity companion that merely picks "a smaller
number" proves almost nothing; one that lands on the other side of the exact constraint boundary
proves the attribution.** Ask: *what single value differs between my positive and negative case, and
is it the value the constraint names?*

**And the placement rule for a control that SUCCEEDS.** A `lives_ok` control **persists rows**, so it
is the one fixture in a battery that can falsify its neighbours' counts. Here it was put last —
after both atomicity watchers and immediately before `finish()` — so it could perturb nothing.
**Verify placement by reading what runs AFTER it, not by accepting "it's placed late"**: the hazard
is any later blanket/aggregate/baseline assertion, and a whole-file `rollback` does not protect
in-transaction ones. A leg placed where it is convenient rather than where the numbers allow is a
quiet way a battery goes wrong. Related: [[shared-predicate-then-second-narrowing]].

**7. THE INVERSE OF THE PLACEMENT RULE — read what runs BEFORE a leg, because a helper can LEAK the
RLS role context and make the next leg vacuous (SELF-245 / `091`).** `_rls.expect_cross_tenant_write_blocked`
does `perform _rls.set_tenant(p_intruder)` and returns `throws_ok` **without restoring the role** —
unlike its sibling `_rls._visible_owner_rows`, which restores to `postgres` on its way out. Two verbs
in the same fixture file, opposite cleanup contracts, neither documented at the call site. `091`'s
next statement was a precondition leg counting *tenant A's* rows and expecting 0 — evaluated while
still `role = authenticated` as tenant **B**, so RLS returns 0 for A's rows **whatever the table
holds**. The `set_config('role','postgres',true)` restore sat one statement too late. `084` called the
same helper and restored immediately; the divergence is invisible without diffing the two call sites.

**The tell:** a leg whose expected value is `0` / empty, sitting immediately after any helper that
sets a tenant context. Ask *what role is current here*, not *what does this leg assert*. **Grep the
fixture for which verbs restore and which do not** rather than assuming a uniform contract — the
per-verb cleanup asymmetry is the actual defect generator, and the leg is only where it surfaces.

**Severity:** this is a watcher defect, not a control weakening — the leaked context makes a leg
unfalsifiable, it does not let anything through. **Flag, do not veto**, and say so explicitly so the
GREEN is not read as having missed it. But recommend it ride the PR: a one-line statement move in a
test file is free pre-merge and costs a whole PR cycle after — see [[block-when-the-vehicle-cost-inverts]].
