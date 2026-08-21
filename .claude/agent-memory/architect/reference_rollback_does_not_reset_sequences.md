---
name: rollback-does-not-reset-sequences
description: The pgTAP suite's inter-file isolation is rollback-based, and rollback does not rewind identity sequences — so a new battery can turn an unrelated battery RED, and a re-used scratch DB hides it
metadata:
  type: reference
---

Each pgTAP file wraps its fixture in `begin; … rollback;`. That rolls back the
ROWS. **It does not rewind `nextval`** — sequence advancement is
non-transactional. So every battery permanently shifts the identity values that
every later-sorting battery will see.

Consequence: **suite isolation is real for data and absent for ids.** Any
assertion whose result depends on id VALUES — most often an ordering — is
silently coupled to every file that runs before it in `pg_prove`'s filename
order. Adding a battery can turn a completely unrelated file red.

Measured at SELF-330: QA's new `086_…` battery advanced `pfin.asset`'s sequence,
which pushed `self200`'s ids from below 100 to 99 and 102. `self200`'s
`(v-embed-1)` compared two `array_agg`s that **sort by different keys** — left
`order by c.asset_id` (bigint), right `order by x` (the concatenated text) — and
those agree only while numeric and lexicographic order coincide. `'102:230' <
'99:229'` because `'1' < '9'`. Failure read `have: {99:229,102:230}` / `want:
{102:230,99:229}` — **same set, different order**, which looks like a data bug
and is a sort-key bug.

⚠⚠ **A RE-USED SCRATCH DB IS A PERMISSIVE HARNESS FOR THIS ENTIRE CLASS.** My
first full-suite run came back clean because the scratch had already been through
a suite pass, so the sequences were already past the boundary and the two orders
happened to agree. **CI builds a fresh database; the re-used one does not
reproduce it.** Rebuild the scratch from `git archive HEAD supabase/migrations`
immediately before any full-suite claim, and control both ways (battery present
vs absent) on freshly built databases — not on one database run twice.

The generic diagnostic when a new test file reddens an old one: **suspect the
sequence, not the data.** Look for `order by` on one side of an equality whose
other side orders by something else, and for anything comparing rendered ids.

Related: [[reference_scratch_db_full_chain_recipe]] (the build recipe this
extends), [[feedback_permissive_harness_vacuous_green]],
[[feedback_invariance_is_blindness_not_robustness]].
