# Memory index — security-engineer

## Review method

- [Measure the fence regex, not its comment](feedback_measure_the_fence_regex_not_its_comment.md) — grep the real predicate over a written evasion list; watch for replaced-not-extended fences.
- [Sec-Lock cross-check catches my own misreads](feedback_sec_lock_cross_check_catches_my_own_misreads.md) — read the source the text CITES; flatten SQL comments before grepping a quote.
- [Catalog comments carry live-state tallies](feedback_catalog_comments_carry_live_state_tallies.md) — a perfect containment proof says nothing about the PRESERVED span; grep the rendered comment for counts.
- [Zero-value sentinels flip meaning when a predicate changes](feedback_zero_value_sentinel_flips_meaning.md) — re-check EMPTY/`?? DEFAULT` against the NEW predicate; branch on the full state tuple, not one field.
- [Block when the vehicle cost inverts at merge](feedback_block_when_the_vehicle_cost_inverts.md) — return-shape rulings are free pre-merge; an assigned-but-never-read local is a dropped output column.

## Standing constraints on future work

- [CPI positivity CHECK must be additive](project_cpi_positivity_check_must_be_additive.md) — `NaN > 0` is TRUE in Postgres; replacing `cpi_u_index_value_finite` re-admits NaN into a financial figure.
