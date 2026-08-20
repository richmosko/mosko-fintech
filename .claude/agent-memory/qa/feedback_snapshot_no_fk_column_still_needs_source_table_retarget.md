---
name: snapshot-no-fk-column-still-needs-source-table-retarget
description: A "snapshot, NO FK" column (031's history.sub_cat_id) looks retarget-immune because the storage column itself never gained a new FK — but the LIVE row it snapshots from still must be seeded in the post-split target table, or the upstream fence (the one that DOES carry the FK) rejects the fixture before the snapshot is ever taken.
metadata:
  type: feedback
---

031_reclass_history_rls.sql's `account_trans_annotation_history.sub_cat_id` is a plain
bigint with NO FK — explicitly "SNAPSHOT NO FK" so the audit trail survives deletion of
the referenced taxonomy row. That property is real and untouched by the ADR-058 GL split.
But it doesn't mean the file is retarget-immune: the snapshot value is copied off
`account_trans_annotation.sub_cat_id`, and THAT column still carries 023's FK — which
084 retargeted to `pfin.posting_prototype`. Fixture rows still seeded into
`user_taxonomy` (cashflow-domain, disjoint id range from `posting_prototype`) fail the
023 fence before any capture/snapshot logic runs at all.

**Why this was the file Architect flagged as most likely to "go green and prove
nothing":** a fixer under time pressure sees "no FK on this column" and concludes no
retarget is needed anywhere in the file — technically true for the history table, false
for the fixture feeding it. A pure no-op edit (touch nothing) would have left the file
in exactly this state: it wouldn't compile at all (023's fence 23503s on the mismatched
id range), so it's an obvious break, not a silent pass — but on a LARGER file where only
some legs consume the mis-targeted id, some legs could stay green while the ones
touching the snapshot silently degrade to testing "insert rejected" instead of "snapshot
survives deletion."

**How to apply:** when a table's own column has no FK, don't stop there — trace one hop
upstream to whatever DOES enforce a fence on the value flowing into it (here: 023's
`fn_account_trans_annotation_matched_sub_cat`), and check whether ITS target moved.
"No FK on this table" and "no FK anywhere in this data's lineage" are different claims.

Related: [[feedback_id_preservation_leg_needs_synthetic_construction_on_fresh_stack]] —
same file family (id-preservation / snapshot-truth legs), same session's broader
gap-fill round.
