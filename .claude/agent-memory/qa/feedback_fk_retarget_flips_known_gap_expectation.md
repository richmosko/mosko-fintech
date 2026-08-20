---
name: fk-retarget-flips-known-gap-expectation
description: When a migration re-targets an FK to a narrower table, a battery's documented KNOWN-GAP lives_ok leg can flip to throws_ok as a side effect — not via the mechanism the leg's own comment anticipated.
metadata:
  type: feedback
---

At the ADR-058 split (`pfin.user_taxonomy` → asymmetric split with `pfin.posting_prototype`), a
KNOWN-GAP leg in `self200_pending_symbol_classification_rls.sql` ((v1)/(v1v)) asserted a cross-domain
sub_cat_id `lives_ok` through `022`'s FK, with a comment explicitly pre-anticipating the fix: "if
DB-level domain enforcement is ever added, update lives_ok -> throws". The split delivers exactly that
flip, but by a **different mechanism** than the comment named — not a new domain CHECK, but the
referenced row simply no longer existing in the FK's target table (it moved to the sibling table under
the same id, per the id-preservation invariant). Same observable outcome, different cause.

**Why this matters beyond this one instance:** a narrower-FK-retarget migration doesn't just break
files that INSERT into the old shape (the obvious F7-style breakage) — it silently flips the expected
outcome of any EXISTING "known-gap, succeeds today" leg whose fixture row happens to move to the
sibling table. These are invisible to a straight grep for the old INSERT pattern (F7's own method)
because the leg itself doesn't insert into the split table — it consumes a captured id from elsewhere.

**How to apply:** whenever an FK re-target lands, don't just grep for INSERT-pattern breakage
(mechanical). Also trace every existing "succeeds despite X" / KNOWN-GAP leg whose fixture row's
domain/class determines which side of the split it lands on — check whether the FK it flows through
still resolves post-split. A leg's own comment pre-naming its future fix ("update this if X is ever
added") is a strong signal to check first; it means the author already knew this was fragile.

Related: [[reference_rls_battery_file_keyed_to_original_migration]] (same ADR-058 split), and
`supabase/tests/rls/DESIGN.md`'s "a trigger's name is its firing order" rule — same family, different
mechanism: both are "the assertion still runs and still passes/fails cleanly, but the reason changed
underneath it."
