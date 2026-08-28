---
name: grep-the-existing-battery-before-scoping-a-remediation
description: Before offering "add a test" as a remediation option, grep for the surface's EXISTING battery — the option may already be in the tree, and describing it as absent is a false claim riding inside a correct condition
metadata:
  type: feedback
---

When a remediation option is *"QA adds a leg that asserts X"*, first measure whether a battery for that
table already asserts X. Read the battery's own header block, not just its test titles — these files
state which mechanism each block proves.

**Why:** at the SELF-252 review I set a condition with three discharge options, and option (B) was
*"QA pgTAP leg expressing the same statement at the DB layer."* It already existed. `supabase/tests/rls/
090_cashflow_target_rls.sql` landed with migration `090` on `main`, and its header reads *"BLOCK U proves
the actual mechanism: an UPSERT that names only ONE column in its DO UPDATE SET leaves the sibling column
untouched."* I had reviewed the branch diff and the application source and never opened the battery,
because the battery was not in the diff — the same "a brief's scope is a hypothesis about where the claim
lives" failure recorded at [[catalog-comments-carry-live-state-tallies]].

**The half worth keeping, because it is what made the error survivable:** the condition itself was still
correctly scoped. BLOCK U writes the `on conflict do update set` clause **by hand**, so it proves
Postgres's semantics and cannot observe the **client library's generation** of that clause from JSON body
keys — a different layer, and the one that was actually unwatched. So the *ask* was right and the
*characterisation* was wrong. **State the LAYER a proposed test would observe, and check whether the
existing battery observes that same layer or a neighbouring one.** Two tests of "the same property" at
different layers are not substitutes, and conflating them is how a real gap gets waved off as covered —
the failure mode in the opposite direction from the one I hit.

**How to apply:** for any table-scoped finding, run `ls supabase/tests/**/<migration-number>*` and read
the battery header before drafting options. Cheap, and it also tells you the plan count you would be
perturbing. If an option turns out to exist, say so in the condition rather than discovering it later —
and name the miss in the same message as the finding, never in a follow-up.

Related: [[assertion-with-no-watcher]] · [[instrument-cannot-observe-the-property]] ·
[[relay-from-the-tree-not-the-report]].
