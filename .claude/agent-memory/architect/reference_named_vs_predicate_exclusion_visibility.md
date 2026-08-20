---
name: named-vs-predicate-exclusion-visibility
description: A NAMED exclusion is made visible by naming it; a PREDICATE exclusion is made visible by asserting what the predicate excludes — listing a predicate-excluded value in the named set converts a LOUD failure into a silent one.
metadata:
  type: reference
---

When an assertion excludes something, the "make the exclusion visible" rule (ADR-058
Amendment 1) is discharged by **opposite instruments** depending on how the exclusion is
expressed:

- **Named exclusion** (a visible constant, e.g. `EXCLUDED_FROM_CAT_GROUP_ORDER = {'Real
  Estate'}`) — visible by *listing* it. Correct when no column can express the exclusion:
  Real Estate is `element='asset'` like every other non-liability Cat, so its exclusion is
  a **product** reason (`076`'s `p_include_real_estate := false`), not a structural one.
- **Predicate exclusion** (`.eq('element','asset')` per `085`) — visible by *asserting what
  the predicate excludes* (a structural leg: "Liabilities is absent from the
  `element='asset'` set entirely").

⚠ **The trap, and it inverts failure direction.** Adding a predicate-excluded value to the
named-exclusion set looks like belt-and-braces and is the opposite. The named set's contract
is *"exists in the filtered set but is deliberately excluded"* — so if a drifted backfill or
a weakened CHECK ever put that value INTO the filtered set, the name **swallows it
silently**. The structural leg fails LOUDLY on the same drift. Two layers only compose when
they fail in the same direction.

⚠ **Aligning an assertion's derivation with the surface's own predicate is a TRADE.**
Deriving the assertion's comparison set from the same predicate the production query uses
buys divergence-immunity by construction and **costs vocabulary totality**: anything the
predicate filters out is now invisible to the assertion too. Name the losing side
explicitly (see [[feedback_structural_fence_must_cover_the_same_class]] and the
replacement-control discipline) — here, a *new* Cat mis-elemented at seed time. The forward
leg still catches an *existing* named member being re-elemented; only the never-named new
one escapes. That residual belongs to the SEED's invariant, not to the consuming surface's
assertion — putting it in the consumer re-creates the divergence.

**The resolution that beats both, and it is what shipped:** keep **two named constants with
different contracts** (present-but-excluded vs removed-by-predicate) and add a **complement
leg** — assert *raw set MINUS filtered set EQUALS the predicate-excluded constant, exactly,
both directions*, read from the same catalog in the same call. That restores the totality the
filter removed, so the trade above collapses to no losing side; and it catches the case a
bare "value X is absent" check cannot — some OTHER value quietly acquiring the excluded
property and dropping out of row set and denominator together.

Worked instance: ADR-058 Decision 7 → Amendment 1 (Real Estate, named) → Amendment 2
(Liabilities, predicate + complement leg), 2026-08-20.

⚠ **A complement leg over NAMES does not close a residual over ROWS.** `element NOT NULL`
under a two-value CHECK exhausts the **rows**; the table's key
(`unique (domain, cat, sub_cat)`) means one Cat is MANY rows and can straddle both values.
A **mixed** Cat appears in the raw set AND the filtered set, so raw-minus-filtered omits it
and the leg PASSES while half its rows leave row-set and denominator together. I claimed the
partition was total from the COLUMN's constraint without reading the TABLE's key, and
wrongly told team-lead their seed-layer watcher was redundant. **A set-level claim needs the
key, not the column constraint.** The watcher belongs at the SEED layer — it catches the
mixed case by construction and needs no venue.

⚠ **A watcher that exists is not a watcher that is armed.** That whole battery is
venue-gated and SKIPS in the default CI run. "Build it" and "arm it" are different
obligations and a backlog entry that conflates them books work already done.
