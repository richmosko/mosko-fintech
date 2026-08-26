---
name: schema-impossible-ac-traces-to-incumbent
description: Schema-impossible PM-draft ACs usually describe the INCUMBENT pfindash schema (pfin.asset_cat etc.), not ours — check the folded ETL before calling an AC merely wrong
metadata:
  type: reference
---

When a drafted AC describes columns that do not exist, check whether it describes the
**incumbent pfindash schema** rather than V1's. `workers/etl/src/pfin_back_etl/core.py`
(the folded Python ETL) still queries `pfin.asset_cat` and stamps an `asset_cat_id`
onto `pfin.asset` — a table that exists in **no** V1 migration. SELF-234's whole AC
(denormalized `cat`/`sub_cat` TEXT on `pfin.asset`, `('Uncategorized','Unsorted')`
placeholders) is that incumbent shape transcribed forward.

**Why this matters:** the diagnosis changes the disposition. An AC that is *wrong*
gets corrected; an AC that describes *a different system* is superseded, and the
residual it was masking has to be looked for separately — twice now that residual
was the load-bearing part.

**How to apply:** before writing "schema-impossible", grep `workers/etl` and the
incumbent-history references in 009/010/012 for the named columns. State the
provenance in the verdict — it is what stops the same AC being re-drafted.

Related: [[scope-the-invariant-before-writing-it]].

⚠ V1's "unclassified" state is the **absence** of a `pfin.user_asset_category` row
(the SELF-200 read-time derived view), never a placeholder value. Seeding an
`Uncategorized` taxonomy row would be a regression, not a fix.

**⚠ The sibling case: the PRD asserts a DATA MODEL the schema never had — and it propagates,
because agents reach for the doc's model when composing amendment text.** Measured at SELF-340's
close-out, PRD §2.4.3's split paragraph:

- *"the user-created children are independent records"* — **false.** Split lines are rows on
  `pfin.account_trans_split` (`029`), a child table. They are not ledger rows: no provider
  identity, no `is_reverse`, no `transaction_type`.
- *"the original … excluded from aggregations"* — **false.** The parent stays the single ledger
  row and its cash is booked **once regardless** (`fn_gl_entries` P1 fires on `amount <> 0`
  whatever the split state). Splitting excludes nothing; it switches **which contra branch fires**
  — P3 gated `split_count = 0` vs P4 gated `split_count > 0` — on a **derived `count(*)`**, never
  stored.
- *"excluded … from re-creation on resync"* via split state — **false attribution.** That is the
  provider-identity dedup index plus `ON CONFLICT DO NOTHING` at ingest, which protects every
  provider row, split or not.

**The tell, and why it is worth catching:** PM's *replacement* sentence for this paragraph was
wrong **in the same way as the sentence it replaced** — an amendment authored to fix stale doc text
inherited the stale text's model. **A rewrite is not a verification.** When asked to verify a
mechanism sentence, re-derive it from the migrations and hand back a rewritten sentence rather than
a confirmation, and say it is a rewrite, not a tweak.

**Related, and often the same paragraph:** the removal story. PRD §2.4.3's `skip_flag` /
deleted-skipped-view language describes a primitive [[reference_adr032_no_skip_primitive]] killed
and that never shipped — and there is no replacement: `editTransFact` / `recategorize` /
`splitTrans` / `unsplitTrans` are the only transaction actions, `004` blocks `DELETE` for every
role, both manual RPCs hard-code `is_reverse = false`, and the edit schema's `nonZeroAmount()`
forbids zeroing a row. **Reverse-and-replace is a CORRECTION primitive, not a REMOVAL one.**
