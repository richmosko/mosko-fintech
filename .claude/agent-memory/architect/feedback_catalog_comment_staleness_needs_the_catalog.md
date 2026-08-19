---
name: catalog-comment-staleness-needs-the-catalog
description: To claim a `comment on ...` is stale, read obj_description on an applied stack — never grep the migration that wrote it, because a later migration may have already re-emitted it
metadata:
  type: feedback
---

**To claim a catalog comment is stale or wrong, read it from the CATALOG
(`obj_description` / `col_description`) on an applied stack. Never grep the migration file
that wrote it.**

**Why:** at the rename PR I reported that `041`'s `comment on table pfin.taxonomy_default`
carried a stale *"63 rows"* count, recommended folding a correction into my comment-only
migration, and got a nod to proceed. Building the correction, I extracted the comment from
a live scratch apply — and **the count was not there.** `077` had already re-emitted the
comment without it. The catalog had been correct for two migrations; **only the merged
`041` file still held the old text, which is exactly how the "vehicle follows where the
text lives" ruling is supposed to work.** Reading the file **over-reports staleness by
construction**: a superseded comment statement stays in its old file forever, looking live.

⚠ **The sharper half — I mixed two instruments inside one sentence.** *"the live table is 65,
measured on a clean apply"* (read from the DB) fused to *"041's comment asserts 63"* (read
from the source file), and the pair was reported as a contradiction. Each half was
individually defensible; **the contradiction existed only between the instruments.**

⚠ **Two verifications through the same instrument are ONE verification.** Team-lead
independently confirmed *"verified at 041:247"* — same file, same wrong answer. What would
have caught it was not more care but a **different route to the same fact**.

**How to apply.** Any claim of the form *"text X is stale relative to state Y"*: read X and
Y **from the same authority the reader uses**. For a `comment on ...` the reader is at
`\d+`, so the authority is the catalog. Grep the migrations only to find *which* file to
re-emit from, never to judge what currently ships. Corollary: `grep -ln "comment on <obj>"
supabase/migrations/*.sql` returning MORE THAN ONE file is the tell that a re-emission
already happened — check it before reporting anything.

Related: [[count-over-history-vs-live-definitions]] ·
[[verifying-a-measurement-is-not-verifying-a-claim]] ·
[[which-ref-the-probe-was-aimed-at]] · [[prove-derived-text-against-its-source]]
