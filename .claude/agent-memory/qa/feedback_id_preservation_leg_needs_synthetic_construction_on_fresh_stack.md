---
name: id-preservation-leg-needs-synthetic-construction-on-fresh-stack
description: A "prove a moved/migrated row keeps its pre-split id" leg can't observe real data on a fresh CI stack — no real users exist yet — so it must synthesize the mechanism via `overriding system value`, not assert over real rows.
metadata:
  type: feedback
---

At the ADR-058 split (`user_taxonomy` → `posting_prototype`), Sec's F1 condition required a battery
leg proving "at least one moved row retains its pre-split id" — the directly-checkable half of the
id-space construction, alongside the structural `pg_sequence` bound check.

**The trap:** on a genuinely fresh CI stack (`001..084` applied cold, no app-driven signups), the
migration's own copy step moves **zero real rows** — `user_taxonomy` is a tenant-owned table with
no migration-seeded per-user data, so there is nothing that actually moved to observe. A leg that
queries for "a row whose id is below the reserved range" will find nothing, and — same shape as
Sec's own F1 veto of the original "two sequences past a shared max" mechanism — a leg that's
vacuously true (or vacuously absent) on a fresh stack is not a check.

**The fix:** don't try to observe a real historical move. Synthesize the mechanism the migration's
copy step depends on: insert a row via `overriding system value` with an explicit low id (below
the new table's reserved range) and assert it lands byte-exact. This proves the CONSTRUCTION the
real migration relies on is sound, without claiming to have observed a real event. State that
distinction explicitly in the assertion message — "this is a synthetic proof of capability, not an
observation of a real historical migration" — so it's never later cited as the latter.

**How to apply:** any time a migration claims "ids are preserved across a move/split/re-key" and
the battery runs on a fresh stack with no pre-existing tenant data, check whether the directly-
checkable half of that claim has anything real to check. If not, build the synthetic-construction
leg rather than either (a) skipping the leg, or (b) writing an assertion that will pass vacuously
until the first populated instance actually exercises it.

Related: [[reference_rls_battery_file_keyed_to_original_migration]] (same ADR-058 split); the
DESIGN.md rule "the paired battery asserts the CONSTRUCTION, not a point-in-time count" (Sec F1) is
the general form this is an instance of.
