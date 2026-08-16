# Architect memory index

## Open work / findings

- [053 CPI positivity CHECK follow-up](project_053_cpi_positivity_check_followup.md) — pointer only; canonical home is **BACKLOG §7.14** with Sec's four binding conditions. ⚠ `> 0` alone re-admits NaN *and* Infinity.

- **[Schema-impossible ACs trace to the incumbent](reference_schema_impossible_ac_traces_to_incumbent.md)** — the folded ETL still names `pfin.asset_cat`; "wrong AC" vs "different system" changes the disposition, and the masked residual is the load-bearing part.

## Postgres / RLS facts worth not re-deriving

- **[The TimeZone pin is a default, not a fence](reference_timezone_pin_is_a_default_not_a_fence.md)** — `061` pins the DB default; `PGTZ` moves a client's own session. Make timestamptz/date comparisons invariant BY MARGIN (>26h zone span).
- **[pgTAP `isnt()` PASSES on NULL](reference_pgtap_isnt_passes_on_null.md)** — `IS DISTINCT FROM`, so a negative assertion over a subquery is fail-OPEN; `ok()` fails on NULL. Prove three states.
- **[A stale worktree listing misreads the tree](reference_stale_worktree_listing_misreads_the_tree.md)** — `ls` answers about the ref you're parked at; use `git ls-tree origin/main`. Twice in one session; Sec's instance nearly became a false accusation.
- [RLS qual privilege semantics](reference_rls_qual_privilege_semantics.md) — policy quals call by stored OID, so schema USAGE is never re-checked; a harness missing the bootstrap's REVOKEs is more permissive than prod.

## How to work

- **[Scope the invariant before writing it](feedback_scope_the_invariant_before_writing_it.md)** — "always equal / NULL together" is usually falsified by the surface's own NULL-cause rows. One message in a draft; a migration after merge.
- **[A diff of two outputs proves nothing until both are non-empty](feedback_diff_of_two_outputs_proves_nothing_until_nonempty.md)** — two empty captures diff as IDENTICAL; `wc -l` both in the same command as the diff.
- **[Verify the bytes you commit](feedback_verify_the_bytes_you_commit.md)** — copy FIRST, then verify the copy. Verifying a teammate's source and copying later let a concurrent edit in; my commit message then described bytes I never checked.
- **[An incoming message is not newer state](feedback_incoming_message_is_not_newer_state.md)** — a holder doc describes its own moment, not a status feed. Twice in one day I took the arriving message over the disproof in my own history.
- **[Address teammates by NAME, not agent type](feedback_address_teammates_by_name_not_type.md)** — `frontend` not `frontend-engineer`; ⚠ `ListAgents` cannot see in-process teammates, so its silence is not absence.

- **[Watcher, not fence, for by-construction properties](feedback_watcher_not_fence_for_by_construction_properties.md)** — a constraint over a guaranteed property can't fire and turns a future regression into an outage. Test it instead.
- **[Spot-check the contract at its consumer](feedback_spot_check_the_contract_at_its_consumer.md)** — authoring ≠ watching it land; a predicate sound in isolation can be unsound as a stand-in for a broader question. Test where implementations DIVERGE.
- **[A structural fence must cover the same class](feedback_structural_fence_must_cover_the_same_class.md)** — swapping a deny-list for a structural property removes a watcher unless the sets match. Two classes → two legs.
- **[Diff filters strip `--` comment lines](feedback_diff_filter_strips_comment_lines.md)** — `grep '^[+-][^+-]'` blinds you to comment changes; use `--numstat`. Bit me twice in one session.
- **[Prove derived text against its source](feedback_prove_derived_text_against_its_source.md)** — rebuild from source + named substitutions (fidelity by construction); a period inside quote marks claims the sentence ended; ⚠ **verbatim carry is safe for claims, UNSAFE for indexicals** — "here" re-points with no edit.
- [A fixture is shared state](feedback_fixture_is_shared_state.md) — a per-leg fixture edit is a global edit; "all fixture, no assertion logic" means re-derive every leg.
- [Path beats paste for reviewable artifacts](feedback_path_beats_paste_for_reviewable_artifacts.md) — a path can be grepped; a paste adds a transcription surface. Name which path — not the shared read anchor.
