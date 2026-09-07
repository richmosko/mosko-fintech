---
name: feedback-earlier-unconditional-fence-masks-the-specific-one-under-test
description: A leg meant to prove ON DELETE RESTRICT on a child table instead proved a DIFFERENT, earlier-firing parent-immutability trigger — the FK layer was unreachable through a `final`-row fixture. 115 (SELF-356), 2026-09-06.
metadata:
  type: feedback
---

Writing 115's leg 14e-c ("the parent cannot be deleted while children exist — ON DELETE
RESTRICT"), the obvious fixture was: take an already-`final` parent with children (the
file's own `d1`), attempt `DELETE FROM pfin.monthly_report WHERE report_id = d1`, expect
the FK-violation message. Live: the DELETE was refused, but with 108's OWN "a final
report is retained indefinitely" immutability message — NOT the FK message. 108's BEFORE
DELETE trigger fires first and blocks deleting ANY final row, unconditionally, whether or
not it has children — the FK-restrict layer behind it is never reached through that path.

Same shape as [[feedback_scope_the_grep_to_what_the_assertion_checks]] and 111's leg 4d
(a CHECK made unreachable by an else-branch that now fires first) — but this time
"unreachable" is a genuine PRODUCT fact about fence ORDERING, not a prosrc-matching
artifact. The fix was in the fixture, not the assertion: 109's own migration comment
named the reachable path directly — "108's trigger PERMITS deleting a draft parent...
so a draft parent that has children cannot be deleted." Built it: open a draft, INSERT a
child directly (owner path, while the parent is still `draft` — 109's own
closes-at-finalization trigger permits this), THEN attempt to delete that draft parent.
108 does not block deleting a draft, so the FK-restrict layer is the first (and only)
fence reached, and the real message finally shows up.

**How to apply:** when a leg's target fence sits BEHIND another table/trigger on the same
object, and the fixture reaches for the "obviously blocked" state (here: `final`) to prove
it, check whether an EARLIER, MORE GENERAL guard already blocks that state unconditionally
— if so, the leg is proving the wrong thing even though it passes. Read the guard chain
(migration comments usually name it, as 109's did here) and construct the fixture at the
state where the earlier guard does NOT fire, so the specific fence under test is the one
actually reached.
