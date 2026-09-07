# SELF-345 / A1+A2+A3+AH — Architect notes beyond the report

Branch `feature/self-345`. Migrations `108`–`111`, ADR-068, ADR-011 D3 (#3/#4) + D9 amendments, ARCH doc halves.

## The helper's payload shape (Backend/Frontend build against this)

`pfin.fn_render_monthly_report(p_target_month date, p_data_as_of date) returns jsonb`, INVOKER, `stable`, `search_path=''`, EXECUTE to `authenticated` only. No default on either parameter — a caller cannot omit `p_data_as_of` and silently get a server date.

    { payload_schema_version:1, target_month, as_of,
      sections: {
        account_holdings:   <fn_nav_composition(as_of) verbatim: groups/buildups/nav>,
        nav_performance:    { series[], series_inflation_adjusted[],
                              delta_panel:{status:'unavailable',reason:'reader_not_as_of_threadable'},
                              reference_dates:{ same } },
        asset_allocation:   { rows:[{sub_cat_id,cat,sub_cat,market_value,target_percent}] },
        rebalancing_targets:{ source_report_id, cash, bonds, marketable_securities,
                              alternatives, disposition },
        cash_flow:          { cross_account_rollup, historical_expenditures[] },
        estimated_taxes:    <fn_compute_tax_liability(as_of) verbatim, 6 keys>
      } }

`target_percent` is NULL when no `planning_target` row exists — unset is row-absent and an explicit `0.00` is a distinct fact, so it is NOT coalesced. Real estate is excluded (`p_include_real_estate => false`), the §2.2.2 read-layer rule that is not fenced in the table.

## Findings, in priority order

**F-1 (F/CTO) — AC 4 and AC 7 cannot both be satisfied.** `fn_nav_delta_panel()` and `fn_nav_reference_dates()` take no parameters and call `fn_server_today()` internally (live at `097`). On a regeneration months later a today-anchored panel would be frozen into a report about a past month. Taken: compose from the threadable readers and emit the other two as `unavailable` with a stable machine code. The fix — an as-of parameter on both — requires DROPPing zero-argument signatures, invalidating other files' `regprocedure` legs and re-opening two shipped financial surfaces. Not taken unilaterally.

**F-2 (Sec) — R5's dormancy premise is false at the DB layer.** `pfin.reconciliation_event` carries an INSERT grant AND an INSERT policy for `authenticated`. The dormancy is a product-path property. The construction-only leg ships as ruled; a firing leg is recommended alongside.

**F-3 (Sec) — two D3 entry descriptions were wrong, same root cause.** #3 names `reconciliation_event.users_id`, which does not exist; #4's class is CR not P1 because the child has no `users_id`. Both entries were written before their tables existed. Corrected by amendment, entries untouched. #3 is recorded as the family's first `P1/CR` hybrid, on the #12 precedent.

**F-4 (F/CTO + Sec) — nothing guarantees one draft per month**, which the ruled two-argument signature needs to identify the row it composes from. Mitigated by echoing `source_report_id`; the real fix is a one-line partial unique index on `108`, product-visible, not taken unilaterally.

**F-5 (Sec) — the audit helper takes DEFINER, and it is forced.** A10 runs under the user's own session, so INVOKER would need an INSERT grant to `authenticated` on an append-only audit table — the shape D9 already ruled against. Realizes the reserved slot; the D9 amendment rides this PR.

**F-6 (team-lead) — `docs/SECURITY/index.html` is Sec-owned and I did not edit it.** R14 rider 2 and the brief both name RT-21's row, but artifact ownership sits with Sec. Asking rather than taking it. The substance needed: RT-21's purpose changes from *prove who is asking* to *prove the caller is our app*; letters (a)–(g) re-derived against a PUSH direction; (a)/(b) still reject Supabase-JWT-signed tokens but the identity claim is no longer a tenant; (e)'s no-escalation clause is unchanged; (g)'s detection commitment is unchanged and still unbuilt.

**F-7 (Sec) — a third ARCH site carried the old PDF direction**, the §3 system-overview flowchart, not named in the brief. Found only by rendering the page.

**F-8 (team-lead) — merge hazard.** This branch and `feature/self-353` both edit ADR-011 Decision 3's opening status sentence and have not seen each other. Correct post-merge text: **nineteen labeled, eighteen DDL-realized** — neither branch's text taken whole. Recorded at D3 consequence (f) and in ADR-068's Consequences.

## Open markers that must close before the PR opens

- `[PROBE PENDING]` in `110`'s header — the render budget, awaiting Backend's p95. The budget must be stated over TWO evaluations of `104`, not one, and `fn_gl_entries` / `fn_holdings_as_of` are VOLATILE so the planner may re-execute them per reference.
- `[PM PENDING]` in `108` — the commentary CHECK bound is 4000 chars as a placeholder. P3's Zod bound must match and count characters, as `length()` does.

## Verification

Combined clean apply of 111 migration files (this branch's `001`–`106` + `108`–`111` with the sibling `107` interleaved in numeric order), zero errors. Behaviour legs run for every fence on both tables plus the composer and the audit helper — see the four commit messages for the per-file lists. Catalog read-back confirms exactly one new SECURITY DEFINER function in the wave (`fn_emit_audit_log`), `pfin.audit_log` with zero policies and zero role grants, and the composer holding EXECUTE for `authenticated` only.

All six mermaid blocks parse against the vendored 11.15.0 runtime; §3.2 screenshot-confirmed rendering with the amended direction.
