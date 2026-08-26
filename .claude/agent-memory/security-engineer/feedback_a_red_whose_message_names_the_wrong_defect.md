---
name: a-red-whose-message-names-the-wrong-defect
description: A watcher can fire correctly while its failure message names a defect that did not occur — and the message dictates the repair, which is usually the one that disables the watcher. Also: state the expected post-change delta as a prediction BEFORE the change runs.
metadata:
  type: feedback
---

**Rule: when an assertion goes RED for a cause its own failure message does not enumerate,
the finding is THE MESSAGE — and I must name the tempting repair and forbid it explicitly.**

**Why:** `054` h12/h18 (2026-08-17) `string_agg` over `pg_auth_members` with no de-duplication.
A scratch build double-recorded `pfin_etl`'s memberships under two grantors, so both legs went
RED with `authenticated,authenticated,service_role,service_role`. **They caught real drift.**
But h12's message says *"RED if a THIRD membership were granted"* and h18's says *"RED on a
re-grant WITH SET FALSE"* — neither is what happened. A reader hunts for a third role, finds
none, concludes the leg is broken, and reaches for `string_agg(distinct …)`. **That repair makes
both legs tolerate forever exactly the drift they just caught.** Same shape as the h14
blind-disjunction the file was already hardened against once: true, but stopped discriminating.

**Corollary — a leg-independence argument only covers the drift dimensions it ENUMERATED.**
h18 was deliberately scoped so a third membership would not red both legs. That split modelled
*membership-set* drift and not *grantor multiplicity*, so one defect reddened both anyway — the
exact coupling the design note existed to prevent, defeated by a dimension it never listed.
Ask of any independence claim: *which drift dimensions did the author enumerate, and is mine
one of them?*

**Second rule, same episode: state the expected delta as a FALSIFIABLE PREDICTION before the
change runs.** A baseline read *after* a fix is an interpretation; the same numbers stated
beforehand are a test I cannot move the goalposts on. Enumerate which assertions flip, which
must NOT move (and why — h14 reads `pg_authid`, the REVOKEs touch `pg_auth_members`), and
declare any deviation a finding rather than a variance.

**⚠ Bind the prediction to the PROPERTY, not to the INSTRUMENT.** I wrote predictions 1–4 as
*"these battery legs flip"* when what I needed was *"the cluster catalog holds these values."*
The venue then broke and my sign-off was hostage to a rebuild I did not need. **Cluster-scoped
legs (`pg_auth_members` / `pg_authid` / `pg_has_role`) can be evaluated by running the leg's OWN
predicate SQL against any database in the cluster** — which is stronger evidence than the pgTAP
wrapper, since the wrapper only reports on that same query. Bound the blast radius the same way:
`grep -rln 'pg_auth_members\|pg_authid\|pg_has_role' supabase/tests/rls/` returned exactly ONE
battery, so "no other leg changes state" became a measurement instead of an argument.
**Format: name the property, then list acceptable instruments — in that order.**

**⚠ Watch for the remediation that BREAKS a venue because the venue depended on the defect.**
Revoking the escalation broke the scratch DBs: `create schema` there had been reaching through
the inherited superuser membership. That is **self-confirming evidence, not a setback** — it
proved the recipe did not find superuser *convenient*, it built venues that **cannot function
without it**, which reclassifies the recipe from hygiene to the actual defect and the grant to
its symptom. **When a fix breaks something, ask what the broken thing was silently standing on
before treating the break as a cost.** And refuse the obvious unblock (`GRANT … TO postgres` to
restore operability) — a narrower instance of the rejected pattern is still the pattern.

**How to apply:**
- On any RED, ask *"does this leg's own message describe what actually happened?"* If not,
  fix the message in the same pass and **name the repair that must not be taken**.
- Never accept `distinct` / `coalesce` / a widened tolerance as the fix for a leg that fired
  correctly. The leg is right; the environment is wrong. See
  [[corrupt-the-control-canary-boundary-tie]].
- Before any remediation lands, write the predicted post-state as a numbered list and send it.
- Check whether the defect has a **CI watcher at all**: a fresh-stack CI lane cannot see
  cluster-state drift (duplicate memberships, ad-hoc role grants) — it is clean *by
  construction*, not by verification. Say so, and route the recurrence-prevention item
  separately, or closing the instance will read as closing the class.

**The GREEN counterpart, and it is harder to see (SELF-325, `087`).** A leg's message can name an
observer it is not exercising, while passing for a reason that is real but different. QA added
`(l5-q-column-overflow)` — `quantity=1e20 / cost_basis=1e16` — to restore observation of `017`'s
`numeric(28,8)` **quantity** column, whose old observer a new upstream fence had shadowed. But
`numeric(20,4)` permits `p − s = 16` integer digits and `1e16` needs 17, so **`cost_basis` overflows
too**: both columns fail coercion, and the leg reaches its named observer only because `quantity`
precedes `cost_basis` in the INSERT's target list. `throws_ok('22003')` is satisfied either way, so
nothing is ever red and nothing ever asks. **An evaluation-order dependency is not a property.**
Fix shape: move the *other* operand well inside its own constraint (`cost_basis 9e15`) so the column
under test is the ONLY one that can raise — then the leg observes what it names by construction.

**The tell that found it: the leg's own comment stated a window, and the fixture sat on the excluded
endpoint** — *"`cost_basis in [5e15, 1e16]` … stays under cost_basis's OWN `numeric(20,4)` ~1e16
ceiling"*, a CLOSED interval whose upper bound is exactly the first excluded value. **When a comment
states a window, recompute both endpoints and check which side the fixture is on** — a `~` in front
of a bound ("~1e16 ceiling") is where the off-by-one hides, and Postgres's own overflow text gives
the bound exactly (*"must round to an absolute value less than 10^16"*). Same family as the
degenerate-state fixture shaped to the claim in [[zero-value-sentinel-flips-meaning]].

**And the generalisable half, which QA and Architect got RIGHT and I want to repeat — LAYER-MOVE.**
Adding a guard UPSTREAM of an existing layer **shadows that layer's observer**: `087`'s new
zero-price fence (`P0001`) began catching `quantity=1e400` before `017`'s column coercion (`22003`)
ever ran, so the leg that used to prove the column constraint silently began proving the new fence.
They re-targeted the old leg, said so in its message, **and added a fresh leg in the narrow window
where the new fence does NOT win** — restoring independent observation of the shadowed layer.
**How to apply:** whenever a new validation lands in front of an existing one, enumerate every
battery leg whose fixture the new guard now intercepts, and for each ask *does any leg still exercise
the lower layer at all?* If the answer is no, the lower layer became unwatched on a commit that
looked purely additive.

**⚠ THE BLUNTEST VARIANT, AND IT SHIPS GREEN: A TEST TITLE THAT STATES THE INVERSE OF ITS OWN
ASSERTION.** SELF-250 / PR #572, `transactions.reverseAndReplace.test.ts:306` — title: *"a 23505
with no code at all … but the index name present **still matches on message alone**"*; assertion:
`status: 422`, i.e. it does **not** match. The body comment two lines above the assertion was
correct and explicit, and the assertion was correct for the code as written. Only the name lied.
Nothing is red, so nothing asks — **until the day someone drops the guarded conjunct, when this leg
goes red and its failure message reads as though the test WANTED the behaviour the change
introduced, pointing the repair at re-breaking the discriminator.** A test name is the instruction a
future reader follows under time pressure, and it is the only part of a passing test anyone reads.

**How to apply — on any leg I review, read the title and the assertion as two independent claims and
check they agree.** They are written minutes apart by the same hand and drift silently; a body
comment agreeing with the assertion is not a defence, because the comment is not what a failing run
prints. Grade it a flag, not a note, when the leg guards a money path — but say plainly it changes
no behaviour and does not gate the merge, or a one-line rename gets argued about like a redesign.

**⚠ AND WHEN A FLAG I RAISED COMES BACK DISCHARGED, VERIFY PLACEMENT, NOT JUST PRESENCE.** The
invariant leg I supplied (`count(*) where sub_cat_id is not null and cat is null = 0`) is
green-by-construction by design — so the only thing that can go wrong is it landing where the query
returns nothing at all. Placed after a tenant switch it would pass vacuously forever. I checked it
sat inside the tenant-A block, upstream of the role change, where a sibling leg already proves the
reader returns ≥10 rows. **For any `= 0` / `is empty` leg, the arming question is "what makes the
denominator non-empty here, and does a leg prove it?"** — see [[shared-predicate-then-second-narrowing]]
on unarmed watchers and [[corrupt-the-control-canary-boundary-tie]] on what runs before a
`0`-expecting leg.

Related: [[enumeration-and-watcher-stop-one-short]],
[[shared-predicate-then-second-narrowing]].
