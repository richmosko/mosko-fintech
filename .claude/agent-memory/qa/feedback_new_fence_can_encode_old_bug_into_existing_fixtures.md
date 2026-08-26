---
name: new-fence-can-encode-old-bug-into-existing-fixtures
description: A new DB fence can break a PRE-EXISTING test's fixture, not just its own file — full-suite pg_prove regression sweep found what a catalog-assertion-only sweep (item 7's literal scope) would have missed. SELF-248/092, 2026-08-25.
metadata:
  type: feedback
---

The SELF-248 dispatch's "sweep" item scoped narrowly: "does 092 invalidate any EXISTING
battery's catalog assertions (regprocedure/trigger lists...)?" I did that grep (clean, no
hits) and would have reported the sweep as done. Running the FULL `pg_prove -r /tests`
suite against a from-scratch 001→092 apply (which I did anyway, per the standing
scratch-DB verification discipline, not because the sweep item told me to) surfaced a
completely different class of break: **037_gl_completion.sql's own FIXTURE setup started
raising 092's new fence**, aborting the whole file before a single assertion ran.

**Why:** 037 predates 092. Its fixture built the exact defect state 092 exists to refuse —
a journaled leg classified as Revenue — and treated it as CORRECT, INTENDED behavior: one
leg (`comp1`) was explicitly commented "a classified revenue cash flow → routes to Revenue,
NOT Suspense" as the POSITIVE control for a "fully-resolved compound group closes" test.
Another leg (`(5e)`) reclassified an already-attached leg to Revenue post-reopen to prove a
freeze guard was close-status-driven, not blanket. Both are legitimate test intents built on
top of what was, at authoring time, correct behavior — and both silently became assertions
of the bug the new migration fixes.

**How to apply:** A catalog-assertion sweep (regprocedure/trigger LIST checks) only catches
schema-shape drift. A new BEHAVIORAL fence — anything that starts refusing a write shape
that used to succeed — needs the full pg_prove run to surface fixture-level breaks, because
the break happens at INSERT/UPDATE inside another file's `begin;...rollback;` setup, not at
an assertion. When you find one: don't just make the write succeed by loosening the new
fence or deleting the old assertion — read what the OLD leg was actually testing, and
retarget the fixture to a value that still exercises that same intent under the corrected
invariant (here: swap the forbidden Revenue classification for Transfer, which is exempt
from the new fence AND still routes to the same "resolved, non-Suspense" outcome the old
test needed — the compound group's Σ=0 conservation law turned out to be
classification-agnostic, so nothing about the ORIGINAL assertion's mechanism needed to
change, only the fixture's classification choice). Confirm the untouched sibling legs (here,
`(5d)`, which still uses the same forbidden classification but is caught by a DIFFERENT,
earlier-firing fence) are unaffected before moving on — don't assume a shared root cause
means a shared fix is needed everywhere the value appears.

Also worth a standing habit: when a migration's own header documents BEFORE-trigger firing
order (092's did, explicitly, because Postgres fires same-table BEFORE triggers in NAME
order), check whether any OTHER file's header ALSO documents that ordering — 037 had its own
stale pre-092 ordering comment that needed the new trigger inserted into it, or a future
reader gets a wrong mental model from a comment that looks authoritative but predates the
change.

Related: [[feedback_verify_paired_artifacts_before_push]] — this is the same "the paired
half isn't just my own new file" discipline, one layer removed: the paired battery for a new
migration includes the NEIGHBORING batteries the new invariant now constrains, not only the
migration's own dedicated file.
