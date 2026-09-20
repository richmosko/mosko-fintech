---
name: a-disposition-without-a-mechanism
description: A ruling that says what an artifact SHOULD do ("stays fail-closed", "joins the supervised lane") without saying HOW it is ever executed — and how its bookkeeping row is written — becomes a permanent blocker under ordered-apply semantics.
metadata:
  type: feedback
---

**Grade every disposition on two questions, not one: what does it DO, and by what PATH is it ever executed?**
A ruling that settles behaviour and leaves execution unstated reads complete and is not.

**Why:** ADR-072 Amendment 5 ruled migration `119` *"stays FAIL-CLOSED"* and *"joins the supervised lane."* Both
correct — and **nothing said how `119` is ever applied, or how it gets a `schema_migrations` row.** Under
`supabase db push`'s ordered-apply semantics the unsupervised lane reaches `119`, its guard raises 42501, the
push fails, **`120`+ never apply, and every subsequent push dies at the same statement** — a permanent blocker on
the exact lane the ADR exists to build. Measured basis for the finding: `migration repair` appeared **zero**
times in the decision record, and the named pre-step file list excluded the file.

**How to apply:**
- On any "this file/step is handled out-of-band" ruling, ask: **which command applies it, under which identity,
  and what writes its ledger/bookkeeping row?** An artifact applied outside the tracking tool is *untracked*, and
  an untracked artifact in an ordered pipeline is retried forever.
- **Grep the decision record for the escape hatch you would expect** (`migration repair`, `--skip`, a repair
  runbook step). A zero count is the finding.
- Say **when** it bites. "Before the first re-bootstrap `db push`" lands differently from "someday" — the first
  run of the very PR that implements the ruling is usually the trigger.
- Offer the shapes, and check whether the ruling's **own criterion** already permits one of them; a criterion
  stated over a list is often mistaken for a prohibition on a member. Related: [[hazard-mechanism-vs-reachability]]
  and [[a-guarantee-moves-only-if-the-same-file-runs]].
