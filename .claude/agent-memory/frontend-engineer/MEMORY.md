# Memory index

## Resolved patterns worth reusing

- [SELF-229 composition-leaf staleness — resolved](project_self229_composition_leaf_staleness_blocker.md) — loader join, not a migration; tri-state `is_stale` over a boolean-with-a-default when a read failure could masquerade as "healthy."

## Verification discipline

- [Verify a DB fn's signature against the applied migration](feedback_verify_db_fn_signature_against_migration.md) — a teammate's brief describing params/scope is a claim, not a fact.
- [A component header can predate its migration and go stale](feedback_stale_component_header_vs_migration.md) — read the migration's own CONTRACT block over a sibling test's narrative prose.
- [Mirrored render gate must match the server guard SHAPE](feedback_mirrored_render_gate_must_match_server_guard_shape.md) — Sec AMBER on SELF-241: dropped a sibling table's denominator-gate param assuming it was redundant; the two server cores guarded on genuinely different predicates (one `> 0` unified, one two independent `=== 0`s). Grep the actual guard before reusing/dropping a formatter's gate.
- [Build ahead of migration — default nullable](feedback_build_ahead_of_migration_default_nullable.md) — type client shapes defensively-nullable when the AC text is silent; narrow only on explicit non-null guarantees.
- [+page.svelte ahead of Backend's loader](feedback_page_svelte_ahead_of_backend_loader.md) — validated precedent (SELF-242, SELF-241): OK when the underlying query layer exists; import real `PageData`, document an EXPECTED CONTRACT, report the missing loader as a bubble-up gap not "Broken."

## Working with the team

- [temp/ handoff files need a shared path](feedback_temp_handoff_files_need_a_shared_path.md) — per-worktree `temp/` is gitignored and never syncs; check the main checkout or ask for inline paste.
- [Mechanical boundary exception — flag, don't block](feedback_mechanical_boundary_exception_flag_dont_block.md) — a one-line pattern-matching fix to a Backend-owned file is fine unilaterally when my own committed work needs it; anything requiring real judgment still needs to ask first.

## Test-environment gotchas

- [testing-library `container` + rune_outside_svelte](feedback_testing_library_container_queryselector_rune_error.md) — don't destructure `container` for DOM queries in this repo's `.dom.test.ts` files; use the query helpers.
