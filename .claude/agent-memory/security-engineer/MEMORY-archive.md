# Memory archive — security-engineer

⚠ **Retired or subsumed index entries moved out of `MEMORY.md` on 2026-09-19** to keep that file
inside its load budget. **Every file linked here is still on disk and still authoritative** — nothing
was deleted. An entry lands here when its triggering surface is settled, or when a sibling entry that
stayed in `MEMORY.md` already carries its lesson. **Read this file when a review touches SQL/DDL
mechanics, ETL merge keys, or a past consolidation** — the hooks below are as incomplete as the main
index's, so open the topic file before acting on one.

## Review method

- [Review the delivery note against the ref](feedback_review_the_delivery_note_against_the_ref.md) — a teammate's local suite figure ≠ the fenced CI lane.
- [Auditing a consolidation against my own file](feedback_consolidation_drift_catch_method.md) — a quote attributed to me may be LAUNDERED; enumerate my ids first.

## Mechanism / defect classes

- [The merge key is a tenant fence](feedback_merge_key_choice_is_a_tenant_fence.md) — joining on a global id fails CLOSED; on a label, OPEN.
- [Two functions, two partitions — check the axis](feedback_two_functions_two_partitions_axis_mismatch.md) — diff both member sets before the arithmetic.
- [Verify the stated correctness mechanism](feedback_verify_the_stated_correctness_mechanism.md) — `STABLE` is a claim about the TRANSITIVE reach set.
- [A label rename moves every unfenced join](feedback_a_label_rename_moves_every_unfenced_join_that_branches_on_it.md) — "edits no function body" ≠ output invariant.
- [A shared predicate covers only that predicate](feedback_shared_predicate_then_second_narrowing.md) — find the SECOND narrowing.
- [Stored status column vs derived history half](feedback_stored_status_column_vs_derived_history_half.md) — two truths in one view row; the affordance keys off the MUTABLE one.
- [Re-derive a uniform-response rationale vs the predicate](feedback_uniform_response_rationale_vs_built_predicate.md) — an explicit `.eq('users_id')` voids every cross-tenant-existence argument
- [APPLIED ≠ DEMONSTRATED when discharging a booking](feedback_applied_vs_demonstrated_discharge.md) — a same-recipe diff proves no-drift, never parity.
- [Backup rotation prunes its own recovery points](feedback_backup_rotation_prunes_its_own_recovery_points.md) — run the DEFENDED event through the retention policy.
- [A signature change needs a DROP, not a runbook](feedback_signature_change_needs_a_drop_not_a_runbook.md) — a changed param list ADDS an overload with its grant.
- [A period-named figure may carry no period bound](feedback_a_period_named_figure_may_carry_no_period_bound.md) — then ask what DRAINS the accumulator.
- [dblink in a test is a privilege boundary](feedback_dblink_in_a_test_is_a_privilege_boundary.md) — `dblink_connect_u` and role elevation are veto-shaped.
- [Grep the existing battery before scoping a remediation](feedback_grep_the_existing_battery_before_scoping_a_remediation.md) — state which LAYER a proposed test observes.
