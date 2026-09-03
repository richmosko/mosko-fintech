---
name: no-sale-writer-lot-match-unreachable
description: V1 has no way to record a sale and zero lot_match writers, so every realized-capital-gain surface is structurally empty — and lot_match is write-ENABLED-and-unreachable, not write-dormant, which is the more misleading state.
metadata:
  type: project
---

Measured at `2cd94ae` during the V1.4 pre-flight (Seam J). PM found the gap; I verified and sharpened
it.

**Three commands, three zeros:**
- `088`'s `fn_create_manual_purchase` rejects `p_quantity <= 0`; its `comment on function` says the
  row shape is *"forced by the GL"* with `quantity > 0`. **BUY-only.**
- `api/src/lib/server/queries/transactions.ts` says it in its own words: *"NO delete, NO skip, NO sell
  path, NO basis_adjust writer."*
- `insert into pfin.lot_match` → **zero hits** in `supabase/migrations/`, **zero** in `api/src`.

**Why:** `036` shipped the lot_match write **enablement** but deliberately withheld the other half —
its own header: *"NOT deferred to 037: the FIFO/specific-lot matching INFERENCE + selection UI."*

⚠ **`lot_match` is NOT write-dormant — `036` write-ENABLED it and refreshed the table comment from
`WRITE-DORMANT` to `WRITE-ENABLED` to say so.** It is **write-enabled and unreachable**: the grants
and policies advertise a live surface that nothing can reach. That is the more misleading of the two
states, and *write-dormant* is the wrong word for it — a reader checking "does the capability exist?"
gets the wrong answer from the grants.

**How to apply.** Any AC that consumes a realized capital gain — ST/LT split, holding period,
§1256 60/40, wash-sale disallowed loss, `fn_compute_tax_liability`'s CG half — is **correct and
unexercised**. Render the surface UNAVAILABLE-with-a-reason rather than `0.00`; the predicate is the
**structural** fact (no sale-recording capability), never the row-count fact (`lot_match` empty this
year), because the row-count form silently becomes *"you had no gains"* the day the writer lands.
A QA isolation leg over this surface is **vacuous** — it passes on both tenants having none.

Corollary: any ruling about *unmatched* sells (Sec's F-2) has **no V1 instance** and is owed before
the sale writer ships, not before V1.4.

Related: [[feedback_a_grep_hit_in_a_comment_is_not_a_call_site]] ·
[[feedback_ratified_name_is_not_a_built_table]] ·
[[reference_nav_definition_flip_is_a_oneway_door]] · [[project_prd_predates_gl_recalibration]]
