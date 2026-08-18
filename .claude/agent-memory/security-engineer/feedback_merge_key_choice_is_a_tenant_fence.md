---
name: merge-key-choice-is-a-tenant-fence
description: When two independently-RLS'd reads are merged in application code, WHICH KEY the merge joins on decides whether a single-sided leak degrades to zero or surfaces a foreign value — tenant-unique ids fail closed, shared vocabulary (labels/names/slugs) fails open.
metadata:
  type: feedback
---

**Rule: in a TS-side merge of two independently-RLS-scoped result sets, trace what happens if
ONE side leaks. Joining on a globally-unique id fails closed; joining on shared vocabulary
fails open. The choice is a tenant fence and it is invisible at the line where someone would
change it.**

**Why:** SELF-240 merges a `user_taxonomy` read (label → id) with a `fn_subcat_market_value`
read (id → value) and looks up **by id**. Traced both single-sided leaks:
- taxonomy read leaks a foreign row → the label resolves to a foreign `id`; the caller's own
  value rows carry only the caller's ids → **lookup misses → 0**. Tenant sees a zero, never a
  foreign figure.
- value read leaks foreign rows → the map holds foreign ids; lookups use the caller's ids, and
  `user_taxonomy.id` is a **global identity sequence** so there is no collision → foreign values
  are never read.

**Surfacing a foreign value requires BOTH reads broken at once** — which is what let me decline
a module-specific two-tenant test without hand-waving: the conjunction is already covered by the
sibling surface's live integration test plus the pgTAP batteries.

**⚠ The fragility, and it is the whole finding: labels are SHARED VOCABULARY across tenants.**
Every provisioned tenant has a `US-06-Financials` row. The tempting simplification — key the
value map by `sub_cat` instead of `sub_cat_id`, since the RPC returns the label anyway and it
removes an indirection — **deletes the fence silently**: a leaked foreign row would then match
by label directly, and no existing test fails.

**⚠ THE SAME RULE IN SQL, and it decides whether a "redundant" tenant conjunct may be struck.**
SELF-329's `081` added `left join pfin.user_taxonomy lut on lut.users_id = acc.users_id and
lut.cat = 'Liabilities' and lut.sub_cat = 'Liability Balances'`. Architect flagged the
`users_id` conjunct as REDUNDANT under INVOKER RLS and invited me to strike it. **Keep it —
and the "redundant" characterisation is wrong in the way that matters.** Every *other* taxonomy
join in that function keys on `ut.id = uac.sub_cat_id`, a **tenant-bound surrogate**, and fails
CLOSED under an RLS regression (a foreign id cannot collide with the caller's own, ids being a
global sequence). The new join keys on **string labels — shared vocabulary** — and fails OPEN:
a leaked foreign row matches by name.

**Formulation worth reusing:** *the conjunct is redundant against a CORRECTLY FUNCTIONING RLS
and is the SOLE tenant discriminator against an RLS regression; that asymmetry is why this join
carries one and its id-keyed siblings do not.* Without it stated, the next reviewer strikes it
"for consistency with the joins above" — and the original comment's own reasoning
("explicit rather than inherited") has no answer to that argument.

**How to apply:**
- In SQL, classify every join's key: **surrogate id → inherited tenancy is fine; name / label /
  symbol / email → require an explicit tenant conjunct.** "Redundant under RLS" is only ever an
  argument about the id-keyed case.
- A redundant-looking predicate flagged for removal deserves the fail-open/fail-closed trace
  before the ruling. **Sometimes the author is right by instinct and wrong in the comment** —
  fix the comment, keep the code, and say which.
- On any app-layer merge of RLS'd reads, ask: *if exactly one side returned foreign rows, does
  the output show a foreign VALUE or a ZERO?* Write out both directions; the asymmetry is
  invisible in prose.
- **Prefer joining on tenant-unique surrogate ids. Treat names, labels, slugs, symbols and
  emails as shared vocabulary** — they are not tenant-discriminating even when they feel like
  keys.
- When the property holds, **say so as the reason for declining a redundant test** rather than
  citing the AC set. A structural argument survives an AC rewrite; deference does not.
- **Recommend a comment at the construction site, not at the lookup.** The property is
  load-bearing where the map is BUILT, and that is where the removing edit happens. Same shape
  as a "this restriction is load-bearing, not a filter for tidiness" note.
- Sibling check on any figure fed by DB numerics: confirm a NaN cannot arrive
  (`check (x <> 'NaN'::numeric)` at the write boundary) — a `=== 0` guard does not catch NaN and
  `Number()` propagates it silently. See [[cpi-positivity-check-must-be-additive]].
