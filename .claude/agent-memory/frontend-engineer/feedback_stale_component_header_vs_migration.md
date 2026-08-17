---
name: feedback_stale_component_header_vs_migration
description: A component's own module-header comment can predate the migration it was built against and go stale after reconciliation — cross-check the migration's own CONTRACT text, not just the frontend mirror's header, when the two could disagree.
metadata:
  type: feedback
---

On SELF-229 I found `NavReferenceDatesPanel.ssr.test.ts`'s "QA Finding 3" comment
(written for SELF-223) narrating the January duplicate-row coincidence as "This Month
and Prior Year-End resolve to the identical date." Migration `073_fn_nav_reference_dates.sql`'s
own header — landed AFTER that test was authored, per `NavReferenceDatesPanel.svelte`'s
own note ("the migration is being authored in parallel... reconciled against the live
migration below") — states explicitly and repeatedly that the real coincidence is
**Prior Month ≡ Prior Year-End**, not This Month ≡ Prior Year-End, and even warns
"a test asserting prior_year_end is the ONLY exact row will red every January." I initially
assumed the test's fixture data still exercised a legitimate assertion despite the stale
prose — WRONG: team-lead independently caught the same drift, QA re-verified against 073
directly and confirmed it was a REAL fixture bug, not just backward comment text — the
old fixture put the shared date on `this_month` (a different concept: 072's CURRENT
ENDPOINT, not "most recent completed month-end") and gave `prior_month` a distinct date,
so it was testing the wrong row pairing. Fixed in commit 4c44d66. Lesson holds either way:
relying on the stale comment (or assuming "the assertions still pass so the fixture must
be fine") would have missed a real bug, not just a documentation one.

**Why:** components/tests in this repo are frequently built against a "ratified contract
text" (a PM/Architect doc) BEFORE the actual migration lands, then reconciled — but the
reconciliation is not always caught in every comment across every file that narrates the
same fact. A frontend `.ts` mirror's own header saying "reconciled against the live
migration" is a stronger signal than a sibling test file's narrative prose, which may not
have been re-touched at reconciliation time.

**How to apply:** when a component's behavior depends on a specific DB-computed structural
fact (which two rows/columns coincide, which field is per-row vs panel-wide, etc.), read
the APPLIED migration's own header/CONTRACT block directly — it's the actual ground truth —
rather than trusting a sibling test file's or an older doc's narrative description of the
same fact, even when that description sounds authoritative (has "QA Finding" or "ratified"
attached to it). See [[feedback_verify_db_fn_signature_against_migration]] for the sibling
lesson on function signatures specifically.
