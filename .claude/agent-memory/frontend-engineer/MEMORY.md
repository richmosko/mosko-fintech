# Memory index

## Resolved patterns worth reusing

- [SELF-229 composition-leaf staleness — resolved](project_self229_composition_leaf_staleness_blocker.md) — loader join, not a migration; tri-state `is_stale` over a boolean-with-a-default when a read failure could masquerade as "healthy."

## Verification discipline

- [Issue-ID audit slash-shorthand blind spot](feedback_issue_id_audit_slash_shorthand_blind_spot.md) — a bare `self-[0-9]+` grep misses IDs inside "SELF-239/241/330"-style shorthand; use `self-[0-9]+(/[0-9]+)*` before reporting a pre-push ID audit complete.
- [Verify a DB fn's signature against the applied migration](feedback_verify_db_fn_signature_against_migration.md) — a teammate's brief describing params/scope is a claim, not a fact.
- [A component header can predate its migration and go stale](feedback_stale_component_header_vs_migration.md) — read the migration's own CONTRACT block over a sibling test's narrative prose.
- [Mirrored render gate must match the server guard SHAPE](feedback_mirrored_render_gate_must_match_server_guard_shape.md) — Sec AMBER on SELF-241: dropped a sibling table's denominator-gate param assuming it was redundant; the two server cores guarded on genuinely different predicates (one `> 0` unified, one two independent `=== 0`s). Grep the actual guard before reusing/dropping a formatter's gate.
- [Build ahead of migration — default nullable](feedback_build_ahead_of_migration_default_nullable.md) — type client shapes defensively-nullable when the AC text is silent; narrow only on explicit non-null guarantees.
- [+page.svelte ahead of Backend's loader](feedback_page_svelte_ahead_of_backend_loader.md) — validated precedent (SELF-242, SELF-241, SELF-325): OK when the underlying query layer exists; import real `PageData`, document an EXPECTED CONTRACT, report the missing loader as a bubble-up gap not "Broken." SELF-325: bubble-up turned out understated, not overstated — grep for actual CALLERS of a query module before trusting "wired," not just whether load() returns the field.
- [Structural picker beats validation-only rejection](feedback_structural_picker_over_validation_only.md) — Architect-praised on SELF-325: when a UI boundary is correctness/security (not UX), narrow the PICKER's option set so the wrong choice is unreachable, rather than only rejecting it after selection; keep validation as defense-in-depth, not the primary fence.
- [Attribute checks to the actual performer](feedback_attribute_checks_to_actual_performer.md) — Architect-corrected on SELF-325: crediting a reviewer with a before/after check I ran myself (meant generously) erases real provenance on a Sec-reviewed branch. Name who actually performed each half of a verification, including self.
- [A test from observed behavior encodes the bug](feedback_test_from_observed_behavior_encodes_the_bug.md) — SELF-325: I asserted what the code DID (a wrong error message), not what it SHOULD do; the green test then locked the defect in and would have made a future correct fix look like a regression. Derive expectations from the underlying facts, never from the code's current output.
- [A stub affordance can already satisfy a later AC](feedback_stub_affordance_can_already_satisfy_a_later_ac.md) — SELF-358/P6: the "Download PDF" brief asked me to build what P2's `pdfHref` stub already fully implemented and tested; grep the exact copy string + `git log --follow` before writing new markup.

## Working with the team

- [temp/ handoff files need a shared path](feedback_temp_handoff_files_need_a_shared_path.md) — per-worktree `temp/` is gitignored and never syncs; check the main checkout or ask for inline paste.
- [Mechanical boundary exception — flag, don't block](feedback_mechanical_boundary_exception_flag_dont_block.md) — a one-line pattern-matching fix to a Backend-owned file is fine unilaterally when my own committed work needs it; anything requiring real judgment still needs to ask first.
- [Batch commit-ready deliveries](feedback_batch_commit_ready_deliveries.md) — send path+md5 for ALL changed files in ONE message once every file is final; a piecemeal per-file send lets the committer read a file mid-edit against a stale md5.
- **[A fork's prompt scope is advisory, not enforced](feedback_fork_scope_is_advisory_not_enforced.md)** — a "research-only" fork can still write/commit/push to a shared remote and SendMessage a teammate on its own; verify the live tree after any fork returns, don't trust its self-narration.
- **[Worktree path — `.claude/worktrees/frontend-engineer`](reference_agent_worktree_path.md)** — moved 2026-09-06 from `~/Projects/mosko-fintech-worktrees/`; confirm `pwd` at session start.
- **[No heredoc / `$(...)` / shell loops in Bash](feedback_bash_sandbox_no_heredoc_no_substitution.md)** — each prompts F/CTO and stalls the whole roster; commit via `-F <file>` written with Write, never `-F -` with a heredoc.
- **[Agent memory lives in the ROOT checkout, uncommitted — never a worktree](feedback_verify_pwd_before_writing_agent_memory.md)** — both paths silently resolve; team-lead sweeps `main`'s uncommitted `.claude/agent-memory/` into chore PRs, a worktree's copy rides a ticket branch or is lost.

## Test-environment gotchas

- [testing-library `container` + rune_outside_svelte](feedback_testing_library_container_queryselector_rune_error.md) — don't destructure `container` for DOM queries in this repo's `.dom.test.ts` files; use the query helpers.
- [getByLabelText breaks on a required field's "Label*"](feedback_getbylabeltext_required_asterisk_no_space.md) — TextField/SelectField's required-marker span has no space; `getByLabelText` does exact textContent match (not ARIA accname) so it fails on any required field. Use `getByRole(...,{name})` or `{exact:false}`.
- [tests/stubs/app-forms.ts `enhance` extended to fire real submits](reference_app_forms_stub_extended_submit.md) — was a pure no-op; now calls the real `SubmitFunction` synchronously on a `submit` event (still no async result-callback / fetch pipeline). Needed to DOM-test a client Zod `cancel()` path from a real button click.
