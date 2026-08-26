---
name: shared-predicate-then-second-narrowing
description: A "row set and denominator share one predicate" guarantee covers only that predicate — check what narrows the RENDERED set afterward, because a later projection the denominator does not see is the same divergence wearing a passed check
metadata:
  type: feedback
---

When a surface satisfies a same-predicate binding ("row set and denominator derive from ONE filtered
set, so divergence is structurally unreachable"), **verify the claim's SCOPE, not its truth.** It is
usually true of the predicate named and false of everything applied after it.

**Why:** SELF-239 built `assetSubCatIds` once and fed both the row set and `total_non_re` from it —
genuinely structural for `element`. But the **rendered** set narrowed twice more afterward, and the
denominator saw neither: `groups = CAT_GROUP_ORDER.map(cat => rowsByCat.get(cat) ?? [])` drops any
row under a Cat outside the four while its value stays in the denominator, and Real Estate is
excluded by name from the row set while RE ids stay inside `assetSubCatIds`. Percentages under-sum,
silently, on a financial surface — the exact fail-open the binding existed to close, arriving
*through* a satisfied check. Both were unreachable in practice, and the reason mattered: RE was
reconciled only by a **hardcoded argument at a call site in another module**
(`p_include_real_estate: false`), not by structure in the module making the claim.

**The generalizable test: rendered ⊆ row set ⊆ denominator-domain.** Ask what shrinks the set at each
step and whether the denominator shrank with it. A projection through a hardcoded vocabulary
(`CAT_GROUP_ORDER.map`) is a narrowing; a name-exclusion beside an id-membership test is a narrowing.

**⚠ Prefer BOTH arms of a two-arm binding, even when the first is met.** My binding offered
same-query-predicate OR a paired `Σ(rendered) = denominator` assertion. Backend shipped both — and the
**Σ leg is the one that covers the later narrowings**, because an unrendered-but-counted row breaks
it by exactly its value. The first arm was written assuming row set == rendered set. **Never let the
satisfied arm be used to argue the other is redundant.**

**⚠ A watcher can exist, be unconditional, and still be UNARMED.** The Σ leg ran in default CI and no
fixture carried a Cat outside the vocabulary, so the identity held trivially. **A property-shaped
assertion over chosen fixtures asserts the fixtures, not the property** — ask which fixture would
break it, and if none would, the ask is one fixture, not a code change.

**⚠ And check the WATCHED TABLE is the READ table.** The paired equality assertion queried
`taxonomy_default` (global seed) while the compute read `user_taxonomy` (per-tenant). Under ADR-057
a seed change's REACH may not deliver to existing tenants, so a tenant carrying a stale label is
invisible to a seed-layer watcher. A grain gap on the *table axis*, distinct from the row-vs-name
grain gap the team had already recorded.

**⚠ THE ONE-QUERY VARIANT: TWO FIGURES FROM ONE QUERY STILL LEAVE A THIRD BUCKET, WHEN THEIR
PREDICATES ONLY LOOK COMPLEMENTARY.** SELF-250's `093` rollup derives both figures from one reader —
*"sum where `sub_cat_id` IS NOT NULL; count where `sub_cat_id` IS NULL; two counts of how much is
missing cannot drift if there is only one query."* The two predicates partition on `sub_cat_id`, so
the argument reads airtight. But the **sum side narrows a second time on a DIFFERENT column** —
`join sections s on r.cat = s.cat`, which drops every row whose `cat` is NULL — so
`sub_cat_id IS NOT NULL AND cat IS NULL` is in **neither** figure. Money leaves the surface with no
banner signal: the exact drift the one-query design was built to make impossible, arriving through
the design's own satisfied premise.

**The move, and it is the fastest one in this whole memory: name the row states that are in NEITHER
figure.** Not "do the predicates partition?" — they did — but "**does anything downstream of either
figure narrow again, on a column the partition does not mention?**" One `join`, one `filter (where …)`,
one `?? 0` on a different key is enough.

**And grade it on REACHABILITY, separately from mechanism** ([[hazard-mechanism-vs-reachability]]).
Here the third bucket was unreachable — a CHECK constraint on the vocabulary, matched-tenant fences
on both writer columns, an identical aal2 clause on every read relation (so no visibility
asymmetry), and no `account_users` sharing writer at all. **Verify each of those legs rather than
asserting the state is unreachable**; then the ask is proportionate: one battery leg asserting
`count(*) where sub_cat_id is not null and cat is null = 0`, which costs nothing now and reds the
day the dormant sharing path activates. A watcher over an unreachable state is not waste — it is
the only thing that notices when the state becomes reachable.

**How to apply:** at any joint-review citing a binding I wrote, re-derive what the binding was
protecting rather than checking the words were honoured — and say so when the implementation exceeds
the brief's account of it (here, the brief said "no paired Σ shipped" and one was, unconditionally;
correcting that prevents a future reviewer deleting it as redundant). Related:
[[uniform-response-rationale-vs-built-predicate]], [[enumeration-and-watcher-stop-one-short]],
[[zero-value-sentinel-flips-meaning]].
