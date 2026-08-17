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
