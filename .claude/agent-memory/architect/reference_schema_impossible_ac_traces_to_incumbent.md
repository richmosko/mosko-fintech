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
