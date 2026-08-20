---
name: run-before-deliver-when-migration-is-committed
description: Once a migration lands (has a real commit sha), building the scratch DB and running pg_prove is fast (~15 commands, seconds each) and catches real bugs a text review can't — don't stay in "draft, unverified" mode past that point.
metadata:
  type: feedback
---

At ADR-058's split (migration 084), I authored a full new pgTAP battery file
(`posting_prototype`) and a retarget patch to `074` purely from reading the migration text and
Architect's confirmations, delivering both as "DRAFT, unverified — no scratch DB exists yet."
Once Architect committed and pushed 084, I ran the actual scratch-DB recipe
([[reference_scratch_db_full_chain_recipe]]) and it found THREE real bugs in the new file that
careful reading had missed:

1. `array_agg(privilege_type order by ...)` compared against a `text[]` literal — silently the
   wrong type (`information_schema.character_data[]`), needed an explicit `::text` cast.
2. `overriding system value` placed BEFORE the column list instead of after — a syntax error,
   not a semantic bug, but one that only running the SQL surfaces.
3. A reused verb (`_rls.expect_cross_tenant_write_blocked`) leaves `role=authenticated` on exit
   and doesn't self-restore — the next `_rls.set_tenant` call needs `USAGE` on schema `_rls`,
   which `authenticated` doesn't have. Only visible by actually hitting the permission error.

None of these were guessable from reading the verb definitions or the migration text alone — all
three needed the interpreter. The whole recipe (dump aux schemas, load as supabase_admin, create
extensions, transfer ownership to postgres, apply migrations, install pgtap, run pg_prove) took
about 15 commands and each step completed in seconds once I stopped treating it as a big
undertaking to defer.

**How to apply:** once a migration this session is testing against has an actual commit sha (not
just a plan or a draft file), the excuse "no scratch DB exists yet" is gone. Build one and run
the battery before calling a delivery "unverified" — the cost is low and the bugs it catches are
exactly the ones a second read-through won't find. Reserve "authored but not run" framing for
migrations that are still drafts with no committed DDL to run against.

Also confirmed reusable this session: [[feedback_scratch_db_pgtap_harness_gotchas]] and
[[reference_scratch_db_full_chain_recipe]]'s postgres-ownership step are both still exactly
right — no drift since they were last written.
