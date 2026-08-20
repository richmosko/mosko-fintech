---
name: test-only-grants-dont-follow-a-fk-retarget
description: When a fixture retargets to a new table (FK moved), any TEST-ONLY grant block elsewhere in the same file (e.g. a service_role load-bearing leg) still names the OLD table and must be updated too — pg_prove found this, reading the file did not.
metadata:
  type: feedback
---

Retargeting `023_account_trans_annotation_rls.sql`'s fixture from `user_taxonomy` to
`posting_prototype` (ADR-058 split) broke a block I hadn't touched: a `service_role`
load-bearing leg further down the file does `grant select on pfin.user_taxonomy to
service_role;` as a TEST-ONLY isolation device (held open in-test, rolled back with
the transaction) so RLS-bypass exposes the referenced rows and the trigger's explicit
predicate is the sole remaining gate. Post-retarget, the trigger reads
`posting_prototype`, but the grant still named `user_taxonomy` — the block died with
`permission denied for table posting_prototype` instead of testing what it claimed to.

**Why reading the file didn't catch it:** the grant statement is textually distant
from the fixture inserts I was editing, in a different BLOCK with its own header
("F3/F4 — THE LOAD-BEARING LEG"), and nothing about the fixture edit's diff touches
it. It only surfaced by actually running the file.

**Same session, same file:** my own new conversion leg happened to reuse the label
`(F3)` that this pre-existing service_role block already used for something else —
a silent numbering collision, cosmetically confusing but not caught by any tool
short of reading the pg_prove output's test *numbers* against the file's own labels.

**How to apply:** when retargeting a table across a battery file, grep the WHOLE file
for the old table name before calling the edit done — not just the fixture INSERT
lines. Grant statements, `grant ... to service_role` teeth-isolation blocks, and
comment-only mentions all need the same sweep. And when adding a new leg with its
own parenthetical label, grep for that label first — a large file can already use it
for something else.

Related: [[feedback_run_before_deliver_when_migration_is_committed]] — same session,
same discipline: this bug (and the ON-DELETE-RESTRICT-target bug in the same file)
were both only found by running, not by re-reading the diff.
