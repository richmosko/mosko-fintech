---
name: zod-coerce-number-on-fk-id-fields
description: The house schema pattern z.coerce.number().int().positive() on FK-shaped ID fields accepts true, [5], "0x10" and "5e2" — measured; it is pre-existing across several api/src/lib/server/schemas sites and is NOT a per-branch defect.
metadata:
  type: project
---

**Fact, measured 2026-08-17 with the repo's own Zod:** `z.object({ id: z.coerce.number().int().positive() }).strict()` **ACCEPTS** `true`→1 · `[5]`→5 · `"0x10"`→16 · `"5e2"`→500 · `" 7 "`→7 · `"1.0"`→1. It rejects `1e21`, `[]`, `null`, `false`, `{}`.

**Why it matters:** Lock 14 mod #1's literal text is *"strict typed-input validation."* Accepting a boolean as a bigint FK is not that. The sharpest form to quote: **in one `.strict()` schema, `target_percent` rejects scientific notation with a message that names it while `sub_cat_id` accepts `"5e2"` as 500.** Same request, opposite treatment of the same adversarial category.

**Why it is NOT a per-branch veto:**
- **Pre-existing house pattern.** `git grep 'z.coerce'` over `api/src/lib/server/schemas/` finds it at several sites (`classification.ts`, `transaction.ts`, `planning-target.ts`) — **re-grep for the live site list; do not cite a count from here.**
- **No cross-tenant path.** These ID fields are all guarded DB-side by matched-tenant BEFORE triggers (the ADR-011 Decision-3 family — e.g. `022`'s `fn_user_asset_category_matched_sub_cat`, `074`'s `fn_planning_target_matched_sub_cat` = instance #17). A coerced value resolves to the caller's OWN row or trips the trigger → clean 4xx. **The fence that matters holds**, and the app layer is correct to decline re-implementing it.
- Blocking one branch fixes one site and punishes the branch that followed the convention.

**How to apply:**
- Raise as **one item covering every site**, never as a condition on whichever branch happens to add the next one.
- Fix shape is a **positive pin**: `z.number().int().positive()` (no coerce), or an explicit
  `z.string().regex(/^\d+$/).transform(Number)` branch where a form genuinely posts strings.
  Never a widened coercion. See [[measure-the-fence-regex-not-its-comment]].
- **Measure with the real Zod before restating any of this** — the accept-set is a property of
  the installed version.
