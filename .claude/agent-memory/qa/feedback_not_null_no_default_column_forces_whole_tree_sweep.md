---
name: feedback-not-null-no-default-column-forces-whole-tree-sweep
description: A migration adding NOT NULL/no-DEFAULT to a widely-fixtured table breaks every existing fixture INSERT that omits it — recurred twice (085 `element`, 091 `is_tax_payment`); grep the WHOLE tests tree, not just that table's own RLS file, before finalizing the paired battery.
metadata:
  type: feedback
---

When a migration adds `<col> <type> not null` with **no DEFAULT** to a table other
fixtures already INSERT into, every existing fixture INSERT that doesn't list the new
column now hard-errors (`null value in column "<col>" violates not-null constraint`) —
this is not hypothetical or rare, it is the DESIGNED behavior (fail-closed: every
INSERT must state the value) and it fires on the very next full-suite run. Recurred
twice at real scale: `085` (`element` on `user_taxonomy`/`taxonomy_default`, its own
header records a 63-statement/14-file sweep) and `091` (`is_tax_payment` on
`posting_prototype`/`posting_prototype_default`, SELF-245, 2026-08-25: 16 files, ~50
statements).

**Why:** NOT NULL + no DEFAULT is deliberate, not an oversight (both cases: the column
marks something that must be explicit or the surface reading it would silently draw a
wrong conclusion — a Cat auto-defaulting to 'asset', a Sub-Cat auto-defaulting to
"not a tax payment"). The very property that makes it a good fence for the app also
makes it a hard break for every pre-existing test fixture that constructs a row without
it — there is no soft-fail path, Postgres raises immediately.

**How to apply:** the moment a migration under review adds a NOT NULL/no-DEFAULT column
to any table, before finalizing the paired battery:
1. `grep -rn "insert into <schema>.<table>\b" supabase/tests/ | grep -v <new_col>` —
   grep the WHOLE `tests/` tree, not just that table's own battery file or its RLS
   directory neighbors. Column-listed `INSERT ... SELECT ... FROM <default_table>`
   copy-provisioning statements need the column added on BOTH the target column list
   AND the source select list, not just a literal — a hardcoded literal there would
   silently stop tracking the source-of-truth table.
2. Also grep for hardcoded row-COUNT assertions against the seeded/default table if the
   migration adds seed rows alongside the column (091 added a 2-row Equity seed pair to
   `posting_prototype_default`, which shifted `041`'s and `082`'s hardcoded `27`/`65`
   counts to `29`/`67` in five+ sites plus header prose — a SEPARATE class of breakage
   from the NOT NULL one, easy to miss if you only grep for the column name).
3. A statement wrapped in `lives_ok(...)`/`throws_ok(...)` does not abort the whole
   test file on the NOT NULL violation (pgTAP's exception handler catches it as a
   FAILED assertion instead) — but a BARE unwrapped `insert into ...` does abort the
   session, and every subsequent statement in that file then fails as "current
   transaction is aborted." Reading the pg_prove Test Summary Report line ("Bad plan:
   you planned N but ran 0") is the tell for the bare-statement case; a normal
   `not ok` with a `died: 23502` detail is the tell for the wrapped case. Both are the
   SAME root cause — don't diagnose them as different bugs.
4. Re-run the FULL suite (not just the new file) via `pg_prove` on a scratch DB after
   the sweep — a file-by-file spot check will miss whichever file you didn't think to
   check.

Related: [[feedback_scratch_db_pgtap_harness_gotchas]] (the verification harness itself)
· [[feedback_pg_prove_scope_full_tests_tree_not_rls_only]] (scope the run correctly) ·
[[feedback_test_only_grants_dont_follow_a_fk_retarget]] (the single-file version of the
"grep the whole thing, not just where you expect it" lesson).
