---
name: feedback-test-from-observed-behavior-encodes-the-bug
description: A test written by asserting whatever the code currently does (rather than what it SHOULD do, decided independently) cannot distinguish intended behavior from a bug — it faithfully locks in both. This is worse than no test, because it makes a future correct fix look like a regression.
metadata:
  type: feedback
  score: n/a
---

On SELF-325's resolve-response wire-format bug, I wrote a DOM test asserting a wrong-shaped
response ("assetId as a number") would show `"Couldn't find or create a match…"`. That assertion
was correct against the CODE at the time I wrote it, but the code itself was wrong — a schema-
parse failure and a genuine "endpoint found nothing" (`assetId: null`) were sharing one branch,
so a parse failure was showing a false, specific-sounding claim. My test was green, and it locked
that false claim in place.

Architect's framing (2026-08-21), which is the part worth keeping: **"The test was encoding the
defect… That is the most dangerous state a watcher can be in — worse than no test at all. No test
leaves a bug findable; a test asserting the bug makes the correct behaviour look like a
regression."** If nobody had caught this independently, the next person to notice the misleading
message would have "fixed" it, watched my test go red, and concluded THEY were wrong.

**Why this happens, mechanically:** I wrote the test *after* the code, asserting what the code
did. A test derived from observed behavior cannot tell intended from accidental — it faithfully
records both. The only defense is deriving the expectation from what *should* happen, decided
independently of what the code currently does (from a spec, a ruling, or — failing that — first
reasoning through the correct behavior BEFORE looking at what the code outputs).

**How to apply:** when writing a test for a branch/message/value that isn't independently
specified anywhere (no ticket, no design ruling, no prior test), pause and ask "is this what the
code does, or what it should do — have I actually derived the second thing?" before asserting.
For error/message-routing logic specifically (which branch produces which user-facing string),
derive the correct mapping from the underlying FACTS each branch represents (e.g., "the endpoint
ran and found nothing" vs. "we couldn't read the reply" are different facts and are entitled to
different messages) — not from running the code and copying its output into the assertion.
Related: [[feedback_a_check_chained_to_its_action_is_decoration]] in shared team memory covers a
neighboring failure mode (a check that can't fail because of how it's wired); this one is a check
that can't fail because it was derived from the thing it's supposedly checking.
