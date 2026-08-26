---
name: feedback-write-blocked-helper-leaves-intruder-role
description: _rls.expect_cross_tenant_write_blocked does NOT self-restore role on exit — a precondition assertion placed right after it silently runs as the intruder tenant and reads vacuously. Sec caught this in my own 091 battery, 2026-08-25; the gotcha was already documented in 084's own file, I just didn't check.
metadata:
  type: feedback
---

`_rls.expect_cross_tenant_write_blocked(intruder, sql, desc)` sets the RLS context to
the intruder tenant to run the write-blocked probe, and — unlike
`_rls._visible_owner_rows` / `_rls.expect_owner_can_read` / `_rls.expect_cross_tenant_read_empty`
— does **not** restore `role=postgres` before returning. Any assertion placed
immediately after it (with no intervening `select set_config('role', 'postgres', true);`)
silently runs under the INTRUDER's RLS context, not the privileged one the author
usually assumes.

**Why this bit me:** authored a fresh `BLOCK FS` in `091_is_tax_payment_rls.sql`
starting with a precondition count (`(FS0)`: tenant A carries zero rows) right after a
prior block ended in `_rls.expect_cross_tenant_write_blocked` (`(ISO3)`), with the
restore-to-postgres line placed one statement too late — AFTER `(FS0)` instead of
before it. `(FS0)` therefore counted tenant A's rows as seen by intruder tenant B under
RLS, which is unconditionally 0 regardless of A's real row count — an unfalsifiable
assertion that would pass even if the fresh-signup copy never ran. Sec caught it at
review (PR #555); I verified the mechanism against `rls_verbs.psql:91-97` myself before
fixing, then proved the fix with a RED-then-GREEN inversion (temp probe row for A,
confirmed the leg goes RED, reverted, confirmed GREEN — never committed the probe).

**The gotcha was already written down** — `084_posting_prototype_rls.sql`'s own (W2)
comment states this exact behavior explicitly: *"⚠ expect_cross_tenant_write_blocked
leaves role=authenticated (intruder context) on exit — it does not self-restore the way
_visible_owner_rows does. Restore to postgres before the next _rls.set_tenant call."*
I didn't check it before writing a new block that used the same helper.

**How to apply:** before writing ANY new block/leg that follows a call to
`_rls.expect_cross_tenant_write_blocked` (or any helper whose role-restore behavior you
haven't personally verified), either (a) grep other battery files for that helper's name
and read their own inline comments about it first, or (b) treat "does this helper
self-restore role" as an open question requiring a direct read of `rls_verbs.psql`
before trusting the ambient role at the next statement. Never assume role state carries
over correctly between blocks just because the prior leg passed — a leg reading the
WRONG tenant's rows can pass by coincidence (0 == 0) exactly as easily as it can fail.

Related: [[feedback_assertion_with_no_watcher]] (a leg that cannot fail is the same
failure class as one reading the wrong context) · [[feedback_a_check_chained_to_its_action_is_decoration]].
