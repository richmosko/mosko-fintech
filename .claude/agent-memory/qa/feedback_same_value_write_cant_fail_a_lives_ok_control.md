---
name: same-value-write-cant-fail-a-lives-ok-control
description: A lives_ok control that writes a value the row ALREADY holds cannot distinguish a correct state-based guard from an incorrect transition-scoped one that would silently block every real change — SELF-248/037, Sec round-2, 2026-08-25.
metadata:
  type: feedback
---

Fixing one Sec finding (retargeting a `throws_ok`/`lives_ok` pair off a value the new
fence forbids) introduced a SECOND, quieter bug: I picked the retarget value from
whatever was already sitting in the fixture (`tx_xfer`, the row's own seeded
classification) without checking whether the row already held it. It did. Both the
`throws_ok` leg (closed → rejected) and the `lives_ok` leg (reopened → allowed) ended
up writing the SAME value the row already had.

**Why this matters:** a same-value `UPDATE` still fires a BEFORE trigger (Postgres
doesn't skip triggers just because the new value equals the old one), so a
`throws_ok` control built this way still correctly proves a MEMBERSHIP-only guard
(one that keys on `journal_id`/status, not on the value being written) has teeth —
that leg survives untouched. But a `lives_ok` control meant to prove the SAME
guard's absence — "this write succeeds once the blocking condition is lifted" —
cannot distinguish a correctly-scoped guard from an incorrectly TRANSITION-scoped one
(`WHEN new.x IS DISTINCT FROM old.x`) that would block every REAL change to that
column. A same-value write trivially satisfies `IS NOT DISTINCT FROM` and passes
regardless of whether the guard is doing its job on values that actually change — the
leg goes green either way and asserts nothing about the case it exists to cover.

**How to apply:** whenever a `lives_ok`/positive-control leg proves "the guard is
LIFTED, not present," check that the write's target value is DIFFERENT from what the
row already holds — not just legal. If two prototype rows of the same class exist for
convenience, that's not enough; verify the SPECIFIC one you're passing to `format()`
isn't the row's current value. When retargeting an existing leg to dodge a new fence's
forbidden set, prefer minting a genuinely fresh, distinct value over reusing whatever
fixture row happens to already be nearby — cheap, and it closes this exact gap before
Sec (or a future reader) has to find it. `throws_ok` controls are less exposed to this
(a same-value write still exercises a membership/status-keyed guard correctly) but
`lives_ok` controls that exist specifically to prove close-status-driven (not
value-driven) behavior are the ones that go silently toothless.

Verified with the stronger inversion form: struck the guard mid-run (via a temporary,
uncommitted probe copy of the file, corruption injected right before the leg and the
real function restored right after) and confirmed the fixed leg alone goes RED while
every sibling assertion stays green — the cleanest possible proof a single leg has
teeth without touching anything else. [[feedback_inversion_test_the_rationale_not_the_presence]]
