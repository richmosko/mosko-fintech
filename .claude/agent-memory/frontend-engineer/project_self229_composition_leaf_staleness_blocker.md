---
name: project_self229_composition_leaf_staleness_blocker
description: RESOLVED — NavCompositionTable per-account leaf staleness (SELF-229 AC#2) shipped via a server-side loader join, not a 051 migration; is_stale is tri-state (boolean | null). Historical record of how the blocker resolved, kept for the pattern.
metadata:
  type: project
---

**RESOLVED 2026-08-14** (commit e7b8da9 on `richmosko/self-229-...`). Originally blocked
(see prior version of this memory) on the assumption that `NavCompositionLeaf.is_stale`
needed a Backend contract extension to `051 fn_nav_composition`. The actual fix was
lighter: a **server-side join in the loader**, not a migration — `pfin.account.linked_source_id`
(an existing column) joined against the caller's already-loaded `046
fn_aggregation_has_stale_constituent` `stale_items[]`, done inside
`api/src/lib/server/queries/navComposition.ts`'s `loadNavComposition()`.

**Why this matters as a pattern:** when a browser-safe type (`$lib/nav-composition.ts`'s
`NavCompositionLeaf`) needs a field that a locked RPC's JSONB doesn't carry, the answer
isn't automatically "extend the RPC" — check whether the missing field can be resolved by
a plain RLS-scoped join in the SvelteKit loader against a column that already exists,
before assuming a migration is required. This one needed zero DDL changes.

**The tri-state shape is the other half of the lesson:** the first backend cut collapsed a
join-query failure to `is_stale: false` for every leaf — indistinguishable from "confirmed
not stale." Team-lead caught this as the same silent-fresh-on-a-read-failure shape SELF-220
Sec round-2 rejected on the NAV chart. Reworked to `is_stale: boolean | null` — `null` means
"the join failed, unknown," rendered as a DISTINCT quiet/muted note, never merged with
either `true` (confirmed stale, italic canary tag) or `false` (renders nothing).

**How to apply:** when a Backend teammate proposes degrading ANY staleness-adjacent field to
a boolean default on a read failure, check whether "false"/"healthy"/"fresh" is the honest
default or just the convenient one — if a failure and a confirmed-good state would render
identically, that's the SELF-220 defect class recurring, and the fix is usually a third
state (`null`/`unknown`), not a boolean with a chosen default.
