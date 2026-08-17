# Architect memory index

## Open work / findings

- [053 CPI positivity CHECK follow-up](project_053_cpi_positivity_check_followup.md) — pointer only; canonical home is **BACKLOG §7.14** with Sec's four binding conditions. ⚠ `> 0` alone re-admits NaN *and* Infinity.

- **[Schema-impossible ACs trace to the incumbent](reference_schema_impossible_ac_traces_to_incumbent.md)** — the folded ETL still names `pfin.asset_cat`; "wrong AC" vs "different system" changes the disposition, and the masked residual is the load-bearing part.

## Postgres / RLS facts worth not re-deriving

- **[Scratch-DB recipe for a full clean chain apply](reference_scratch_db_full_chain_recipe.md)** — container `pg_dump`, load as `supabase_admin`, dump-then-extensions, `supabase_vault` for `vault.decrypted_secrets`; never `--no-privileges`.
- **[`set local` outside a transaction is a silent no-op](feedback_set_local_outside_transaction_is_a_noop.md)** — the RLS smoke then runs as superuser and every leg passes; a vacuous harness looks PERMISSIVE, not empty. Control leg first.
- **[`user_settings` can never carry the aal2 clause](reference_user_settings_excluded_from_aal2_backstop.md)** — `025` names it a NON-NEGOTIABLE exclusion (policy recursion); wrong home for step-up-fenced tenant data.
- **[The TimeZone pin is a default, not a fence](reference_timezone_pin_is_a_default_not_a_fence.md)** — `061` pins the DB default; `PGTZ` moves a client's own session. Make timestamptz/date comparisons invariant BY MARGIN (>26h zone span).
- **[pgTAP `isnt()` PASSES on NULL](reference_pgtap_isnt_passes_on_null.md)** — `IS DISTINCT FROM`, so a negative assertion over a subquery is fail-OPEN; `ok()` fails on NULL. Prove three states.
- **[A stale worktree listing misreads the tree](reference_stale_worktree_listing_misreads_the_tree.md)** — `ls` answers about the ref you're parked at; use `git ls-tree origin/main`. Twice in one session; Sec's instance nearly became a false accusation.
- [RLS qual privilege semantics](reference_rls_qual_privilege_semantics.md) — policy quals call by stored OID, so schema USAGE is never re-checked; a harness missing the bootstrap's REVOKEs is more permissive than prod.
- **[CREATE OR REPLACE resets volatility](reference_create_or_replace_resets_volatility.md)** — silently erases an `ALTER … STABLE` pin, invisible to every value assertion; pin per SIGNATURE, and a STABLE caller of a VOLATILE callee is an unbacked promise.

## How to work

- **[A self-authored label hardens into fact](feedback_self_authored_label_hardens_into_fact.md)** — I invented `C1` for symmetry and it reached a commit subject, which has NO supersession mechanism. Grep the dispatch, not your own earlier use.

- **[A count over history is not a count over live definitions](feedback_count_over_history_vs_live_definitions.md)** — 6 textual kernel copies vs 3 live; a CI fence specced from the historical count goes RED on correct code. Case-insensitive grep, or `059` reads as empty.

- **[A ratified name is not a built table](feedback_ratified_name_is_not_a_built_table.md)** — the whole Lock-14 settings family was named in 6 artifacts with ZERO DDL; grep migrations first, and the shape you ratify templates every unbuilt sibling.
- **[Scope the invariant before writing it](feedback_scope_the_invariant_before_writing_it.md)** — "always equal / NULL together" is usually falsified by the surface's own NULL-cause rows. One message in a draft; a migration after merge.
- **[A diff of two outputs proves nothing until both are non-empty](feedback_diff_of_two_outputs_proves_nothing_until_nonempty.md)** — two empty captures diff as IDENTICAL; `wc -l` both in the same command as the diff.
- **[Verify the bytes you commit](feedback_verify_the_bytes_you_commit.md)** — copy FIRST, then verify the copy. Verifying a teammate's source and copying later let a concurrent edit in; my commit message then described bytes I never checked.
- **[An incoming message is not newer state](feedback_incoming_message_is_not_newer_state.md)** — a holder doc describes its own moment, not a status feed. ⚠ Also the inverse: a stale "you didn't do it" poke gets MEASURED, never redone — and an **unpushed** branch makes every origin-anchored check read as *never done*.
- **[Address teammates by NAME, not agent type](feedback_address_teammates_by_name_not_type.md)** — `frontend` not `frontend-engineer`; ⚠ `ListAgents` cannot see in-process teammates, so its silence is not absence.

- **[Watcher, not fence, for by-construction properties](feedback_watcher_not_fence_for_by_construction_properties.md)** — a constraint over a guaranteed property can't fire and turns a future regression into an outage. Test it instead.
- **[Spot-check the contract at its consumer](feedback_spot_check_the_contract_at_its_consumer.md)** — authoring ≠ watching it land; a predicate sound in isolation can be unsound as a stand-in for a broader question. Test where implementations DIVERGE.
- **[A structural fence must cover the same class](feedback_structural_fence_must_cover_the_same_class.md)** — swapping a deny-list for a structural property removes a watcher unless the sets match. Two classes → two legs.
- **[Diff filters strip `--` comment lines](feedback_diff_filter_strips_comment_lines.md)** — `grep '^[+-][^+-]'` blinds you to comment changes; use `--numstat`. Bit me twice in one session.
- **[A cited precedent transmits its RETRACTED half](feedback_cited_precedent_transmits_its_retracted_half.md)** — ADR-042 already corrected the "RLS-exempt writer only" claim for #16; I cited its rationale and reproduced the retraction into 4 surfaces. Grep the ADR for later amendments before citing.
- **[Prove derived text against its source](feedback_prove_derived_text_against_its_source.md)** — rebuild from source + named substitutions (fidelity by construction); a period inside quote marks claims the sentence ended; ⚠ **verbatim carry is safe for claims, UNSAFE for indexicals** ("here" re-points with no edit) **and for FIGURES** — a byte-exact quote of a wrong number passes every fidelity check, so measure what you quote and check a count against its own enumeration.
- [A fixture is shared state](feedback_fixture_is_shared_state.md) — a per-leg fixture edit is a global edit; "all fixture, no assertion logic" means re-derive every leg.
- [Path beats paste for reviewable artifacts](feedback_path_beats_paste_for_reviewable_artifacts.md) — a path can be grepped; a paste adds a transcription surface. Name which path — not the shared read anchor.
