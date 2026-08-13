# Architect memory index

## Open work / findings

- [053 CPI positivity CHECK follow-up](project_053_cpi_positivity_check_followup.md) — `cpi_value` admits 0 and negatives; `067` only guards around it. Verify it hasn't landed before acting.

## Postgres / RLS facts worth not re-deriving

- [RLS qual privilege semantics](reference_rls_qual_privilege_semantics.md) — policy quals call by stored OID, so schema USAGE is never re-checked; a harness missing the bootstrap's REVOKEs is more permissive than prod.

## How to work

- **[Watcher, not fence, for by-construction properties](feedback_watcher_not_fence_for_by_construction_properties.md)** — a constraint over a guaranteed property can't fire and turns a future regression into an outage. Test it instead.
- **[A structural fence must cover the same class](feedback_structural_fence_must_cover_the_same_class.md)** — swapping a deny-list for a structural property removes a watcher unless the sets match. Two classes → two legs.
- **[Diff filters strip `--` comment lines](feedback_diff_filter_strips_comment_lines.md)** — `grep '^[+-][^+-]'` blinds you to comment changes; use `--numstat`. Bit me twice in one session.
- **[Prove derived text against its source](feedback_prove_derived_text_against_its_source.md)** — rebuild regenerated blocks from source + named substitutions (fidelity by construction, no byte counts); a period inside quote marks claims the sentence ended.
- [A fixture is shared state](feedback_fixture_is_shared_state.md) — a per-leg fixture edit is a global edit; "all fixture, no assertion logic" means re-derive every leg.
- [Path beats paste for reviewable artifacts](feedback_path_beats_paste_for_reviewable_artifacts.md) — a path can be grepped; a paste adds a transcription surface. Name which path — not the shared read anchor.
