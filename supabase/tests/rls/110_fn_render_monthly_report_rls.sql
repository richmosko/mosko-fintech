-- =====================================================================
-- 110 — pfin.fn_render_monthly_report(p_target_month, p_data_as_of) (SELF-347 /
--   A3). The Lock 11 read-composition helper — THE payload shape Backend and
--   Frontend build against, and verbatim what gets FROZEN into `108`'s
--   rendered_payload at finalization. SECURITY INVOKER, STABLE.
--   Canonical test labels: RT-19 (read-time tenant-scoping), RT-25 (as-of
--   parameter-bypass adversarial input, the DB half).
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `110`. Reviewed as ONE
-- design unit with `108`/`109`/`111` under ONE Sec joint-review.
--
-- ⟦EXPECTED STACK⟧ `110`-applied (depends on `108`, `104`, `105`, and the
-- other read helpers it composes). Below it the function does not exist and
-- every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()
-- / _b() / _c()). Minimal manual-account fixtures (a single opening-balance
-- `acct_setup` row per tenant) — enough to make the composition genuinely
-- non-empty without re-proving 049/051/104's own correctness, which is their
-- own batteries' job (per this file's own SOURCE NOTE precedent at 107).
-- No PII, no real account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_live_draft '%monthly_report_one_live_draft_per_month%'

select plan(15);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'tc', 'none');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct', 'depository', 'household', 'taxable') returning account_id as ta_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct', 'depository', 'household', 'taxable') returning account_id as tb_acct \gset
-- tenant C deliberately gets NO account at all (leg 8 — cross-tenant/no-rows caller).

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:ta_acct, '2026-01-01', 1000, 'setup', 'opening balance', 'acct_setup');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:tb_acct, '2026-01-01', 2000, 'setup', 'opening balance', 'acct_setup');

-- =====================================================================
-- LEG 1 — Sec F-4 catch criterion WITH ITS POSITIVE CONTROL (R3 rider 2):
-- composing for tenant A while tenant B's rows EXIST must show ZERO tenant-B
-- contribution. Vacuous by default on a fixture with no tenant-B rows, so
-- ALSO prove the leg REDS when the role assumption is struck (no SET LOCAL
-- ROLE authenticated — i.e. called as postgres, which bypasses RLS).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select (pfin.fn_render_monthly_report('2026-08-01', '2026-08-31')
             -> 'sections' -> 'account_holdings' -> 'buildups' ->> 'gross_total')::numeric),
  1000.00,
  '(1a) composed for tenant A while tenant B''s $2000 account EXISTS: gross_total = 1000.00, tenant A''s OWN balance only'
);
select set_config('role', 'postgres', true);
-- (1b) CORRUPT-THE-CONTROL: the SAME call, but role assumption struck (postgres
-- bypasses RLS entirely — no SET LOCAL ROLE authenticated). If (1a)'s isolation
-- were vacuous (e.g. the fixture accidentally had no tenant-B data), this would
-- read the SAME 1000.00 regardless. It does not: it picks up BOTH tenants.
select isnt(
  (select (pfin.fn_render_monthly_report('2026-08-01', '2026-08-31')
             -> 'sections' -> 'account_holdings' -> 'buildups' ->> 'gross_total')::numeric),
  1000.00,
  '(1b) TEETH: with the role assumption struck (called as postgres, RLS bypassed), gross_total is NOT 1000.00 — it picks up tenant B''s balance too (3000.00), proving (1a)''s isolation genuinely depends on RLS scoping and is not a fixture accident'
);

-- =====================================================================
-- LEG 2 — STANDING catalog assertion (R3 rider 1, P10 item 3): no
-- rolbypassrls role holds EXECUTE on this function, on
-- fn_compute_tax_liability, or on fn_nav_composition. Scoped BY NAME to
-- `service_role` — the actual application-reachable rolbypassrls identity —
-- rather than a bare `rolbypassrls` catalog sweep: on this local Supabase
-- stack `postgres` itself carries rolbypassrls=true (measured) while also
-- OWNING these functions, so it always shows EXECUTE regardless of any grant
-- and would make the sweep permanently, uninformatively red. 104's own header
-- states the scope in these terms: "service_role holds the attribute AND pfin
-- USAGE... service_role has no EXECUTE here."
-- =====================================================================
select is(
  (select count(*)::int
     from (values
       ('fn_render_monthly_report(date,date)'),
       ('fn_compute_tax_liability(date)'),
       ('fn_nav_composition(date)')
     ) as f(sig)
    where has_function_privilege('service_role', ('pfin.' || f.sig)::regprocedure, 'EXECUTE')),
  0,
  '(2) STANDING: service_role holds EXECUTE on NONE of fn_render_monthly_report, fn_compute_tax_liability or fn_nav_composition — for this RLS-exempt caller the EXECUTE grant would be the ENTIRE perimeter, not the weakest fence'
);

-- =====================================================================
-- LEG 3 — ONE CALL, ONE CLOCK: the payload's echoed as_of equals p_data_as_of,
-- and equals the as_of echoed by the Estimated Taxes section (the two 104
-- evaluations agree).
-- =====================================================================
select ok(
  (select (r ->> 'as_of')::date = '2026-08-31'::date
      and (r -> 'sections' -> 'estimated_taxes' ->> 'as_of')::date = '2026-08-31'::date
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(3) ONE CALL, ONE CLOCK: top-level as_of AND sections.estimated_taxes.as_of both equal p_data_as_of — the two evaluations of 104 agree'
);

-- =====================================================================
-- LEG 4 — RT-25 DB half: no default on p_data_as_of, so a caller cannot omit
-- it and silently receive a server date.
-- =====================================================================
select throws_like(
  $$ select pfin.fn_render_monthly_report('2026-08-01') $$,
  '%function pfin.fn_render_monthly_report(unknown) does not exist%',
  '(4) calling with ONLY p_target_month (omitting p_data_as_of) fails to resolve to any function — there is no default to silently supply a server date'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 5 — UPDATED BY FINDING-1 CLOSURE (2026-09-05): delta_panel/reference_dates
-- no longer cross as the {status,reason} unavailable envelope (that shape moved
-- to LEG 7's fallback case) — they now cross as real ARRAYS of per-horizon rows.
-- The principle this leg exists to prove is unchanged: an unavailable DATA POINT
-- inside a row (no checkpoint data in this bare fixture) crosses as JSON null,
-- never a collapsed `?? 0`.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select jsonb_typeof(r -> 'sections' -> 'nav_performance' -> 'delta_panel') = 'array'
      and jsonb_typeof(r -> 'sections' -> 'nav_performance' -> 'reference_dates') = 'array'
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 0 -> 'delta_nominal') = 'null'::jsonb
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(5) nav_performance.delta_panel / reference_dates cross as real ARRAYS (Finding 1 closed — no longer the collapsed envelope), and an unavailable data point inside a row (delta_nominal, no checkpoint data in this fixture) crosses as JSON null — no `?? 0` inside this function'
);

-- =====================================================================
-- LEG 6 — the `unavailable` case is the BOOTSTRAP DEFAULT, not an edge case:
-- neither tenant has designated a tax ledger, so estimated_taxes.jurisdictions
-- carries unavailable envelopes, never a numeric $0.
-- =====================================================================
-- On a bare bootstrap fixture (no tax_bracket_schedule seeded either), the
-- top-level jurisdiction status reads 'no_schedule_any_year' (a more
-- fundamental unavailability than the ledger-designation question) — but the
-- ytd_paid sub-envelope specifically reads 'no_ledger_designated', which is
-- the exact claim this leg makes. Both are checked: the top-level status
-- proves "unavailable, never $0" generically; ytd_paid.reason proves the
-- specific no-designated-ledger case by name.
select ok(
  (select (r -> 'sections' -> 'estimated_taxes' -> 'jurisdictions' -> 'federal' ->> 'status') = 'unavailable'
      and (r -> 'sections' -> 'estimated_taxes' -> 'jurisdictions' -> 'federal' -> 'ytd_paid' ->> 'status') = 'unavailable'
      and (r -> 'sections' -> 'estimated_taxes' -> 'jurisdictions' -> 'federal' -> 'ytd_paid' ->> 'reason') = 'no_ledger_designated'
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(6) BOOTSTRAP DEFAULT: no tax ledger designated -> jurisdictions.federal is unavailable and its ytd_paid sub-envelope names the reason explicitly (no_ledger_designated), never $0 — this is every new user''s report'
);

-- =====================================================================
-- LEG 7 — FINDING 1 CLOSED (2026-09-05, migration 110 Part 1): the composer now
-- threads p_data_as_of through fn_nav_delta_panel_as_of / fn_nav_reference_dates_as_of
-- instead of emitting the reader_not_as_of_threadable fallback. As originally
-- promised at this leg's own prior text: closing Finding 1 REDDENED it and forced
-- the payload contract to be re-read — this is that re-read.
-- (7a) THE REAL CATCH CRITERION (regeneration-months-later): composing for a PAST
-- month returns THAT month's anchors, not today's. Values match Architect's own
-- measured worked example verbatim (110 header, RENDER-BUDGET section neighbor).
-- (7b) NON-VACUOUS / "THE PANEL ACTUALLY MOVES" (QA PAIRING LIST item 2): the SAME
-- horizon set anchored on a DIFFERENT p_data_as_of (2026-08-31, LEG 1/3's date)
-- returns DIFFERENT anchor dates — a body that ignored p_data_as_of would pass
-- (7a) by coincidence; this is what rules that out.
-- =====================================================================
select ok(
  (select (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 0 ->> 'anchor_date') = '2024-06-30'   -- 1y
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 1 ->> 'anchor_date') = '2022-06-30'   -- 3y
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 2 ->> 'anchor_date') = '2020-06-30'   -- 5y
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 3 ->> 'anchor_date') = '2025-05-31'   -- month
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 4 ->> 'anchor_date') = '2024-12-31'   -- ytd
      and (r -> 'sections' -> 'nav_performance' -> 'reference_dates' -> 2 ->> 'reference_date') = '2025-06-30'  -- this_month = p_data_as_of itself
     from (select pfin.fn_render_monthly_report('2025-06-01', '2025-06-30') as r) q),
  '(7a) AS-OF ANCHORING, REGENERATION-MONTHS-LATER CASE: composing for target_month=2025-06 / data_as_of=2025-06-30 anchors every delta_panel horizon and reference_dates.this_month on THAT month — 1y/3y/5y/month/ytd = 2024-06-30/2022-06-30/2020-06-30/2025-05-31/2024-12-31, matching Architect''s own measured worked example — never today''s server date frozen into a report about the past'
);
select ok(
  (select (r -> 'sections' -> 'nav_performance' -> 'delta_panel' -> 0 ->> 'anchor_date') <> '2024-06-30'
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(7b) NON-VACUOUS, THE PANEL ACTUALLY MOVES (QA PAIRING LIST item 2): the SAME 1y-horizon anchor for a DIFFERENT p_data_as_of (2026-08-31) is NOT (7a)''s 2024-06-30 — the parameter is genuinely load-bearing, not merely accepted'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 8 — a cross-tenant / no-rows caller (INVOKER) gets a well-formed
-- payload with EMPTY sections, NOT an error and NOT NULL.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select ok(
  (select r is not null
      and (r -> 'sections' -> 'account_holdings' -> 'groups') = '[]'::jsonb
      and (r -> 'sections' -> 'asset_allocation' -> 'rows') = '[]'::jsonb
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(8) tenant C (zero accounts, RLS-scoped, no rows anywhere) gets a well-formed NON-NULL payload with empty groups/rows — fails closed INTO A SHAPE THAT SAYS SO, never an error and never NULL'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG E13 — UPDATED BY E15 (108, 2026-09-05): monthly_report_one_live_draft_per_month
-- now enforces AT MOST ONE LIVE DRAFT per (user, month), so the scenario this leg
-- originally exercised — TWO SIMULTANEOUS drafts for the same month — is no longer
-- reachable at the DB layer; the second INSERT below now raises 23505 instead of
-- landing. Per 108's own header, the "highest report_id in draft" rule and its
-- echoed source_report_id are KEPT AS WRITTEN even though E15 makes the choice
-- degenerate (nothing to choose between with at most one candidate) — the echo is
-- still what lets a caller assert the composer read the exact row it is about to
-- write, and an assertion that can no longer fail is still what proves E15 holds.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of, commentary_cash)
  values ('2026-09-01', '2026-09-30', 'first-draft') returning report_id as d_first \gset
select throws_like(
  $$ insert into pfin.monthly_report (target_month, data_as_of, commentary_cash)
       values ('2026-09-01', '2026-09-30', 'second-draft') $$,
  :'m_live_draft',
  '(E13-setup) E15 HOLDS HERE TOO: a second draft for the SAME month is REJECTED by monthly_report_one_live_draft_per_month — the two-simultaneous-drafts scenario this leg originally exercised is no longer reachable, cross-checked from a different battery file than 108''s own E15 leg'
);
select ok(
  (select (r -> 'sections' -> 'rebalancing_targets' ->> 'source_report_id')::bigint = :d_first
      and (r -> 'sections' -> 'rebalancing_targets' ->> 'cash') = 'first-draft'
     from (select pfin.fn_render_monthly_report('2026-09-01', '2026-09-30') as r) q),
  '(E13) DEGENERATE BUT KEPT (108 header): with at most one live draft possible, the "highest report_id in draft" rule has nothing left to choose between — but source_report_id still echoes the ONE draft actually read (d_first) and its commentary reads back correctly, proving the composer reads the row it claims to rather than coincidentally succeeding because only one candidate exists'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG D1 — DELEGATION EQUIVALENCE (QA PAIRING LIST item 1, migration 110 Part 1):
-- the re-issued zero-argument delta_panel/reference_dates delegators are
-- BEHAVIOUR-PRESERVING — each equals its own _as_of form called with
-- pfin.fn_server_today(), column-for-column, on a NON-EMPTY set (tenant A's
-- fixture already produces 5 delta_panel rows and 3 reference_dates rows, per
-- LEG 5/7 above).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select count(*) > 0 from pfin.fn_nav_delta_panel())
  and not exists (select * from pfin.fn_nav_delta_panel() except select * from pfin.fn_nav_delta_panel_as_of(pfin.fn_server_today()))
  and not exists (select * from pfin.fn_nav_delta_panel_as_of(pfin.fn_server_today()) except select * from pfin.fn_nav_delta_panel())
  and (select count(*) > 0 from pfin.fn_nav_reference_dates())
  and not exists (select * from pfin.fn_nav_reference_dates() except select * from pfin.fn_nav_reference_dates_as_of(pfin.fn_server_today()))
  and not exists (select * from pfin.fn_nav_reference_dates_as_of(pfin.fn_server_today()) except select * from pfin.fn_nav_reference_dates()),
  '(D1) DELEGATION EQUIVALENCE, NON-VACUOUS: fn_nav_delta_panel() returns a NON-EMPTY set and matches fn_nav_delta_panel_as_of(fn_server_today()) exactly (zero rows in either symmetric-difference direction), and likewise for fn_nav_reference_dates() / fn_nav_reference_dates_as_of — the delegation is behaviour-preserving, not merely plausible'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG D2 — CATALOG: volatility is `stable` on all four signatures after this
-- migration (QA PAIRING LIST item 4). `CREATE OR REPLACE` resets volatility to
-- the default (VOLATILE) unless re-declared — invisible to every value
-- assertion above, which is why this is a catalog leg and not inferred from D1.
-- =====================================================================
select is(
  (select count(*)::int from pg_proc
    where oid in (
      'pfin.fn_nav_delta_panel()'::regprocedure,
      'pfin.fn_nav_reference_dates()'::regprocedure,
      'pfin.fn_nav_delta_panel_as_of(date)'::regprocedure,
      'pfin.fn_nav_reference_dates_as_of(date)'::regprocedure
    ) and provolatile = 's'),
  4,
  '(D2) all four signatures — the two zero-argument delegators and the two _as_of forms — are STABLE. Omitting the re-declaration on a CREATE OR REPLACE would silently reset it to VOLATILE, losing planner optimisation with no value assertion able to see the regression'
);

-- =====================================================================
-- LEG 9 (Sec FLAG-4, option A) — VERSION PIN. The purpose of this leg is to
-- give "a payload_schema_version bump is a Sec-review event" an actual
-- MECHANISM: nothing in CI or the workflows currently fences that literal
-- (Sec measured zero pins, zero `fence-payload-version` context), so a bump
-- could land silently and freeze `108`'s rendered_payload contract forever
-- with no reviewer noticing. This leg asserts the CURRENT literal against
-- the INSTALLED body's `prosrc`, comment-stripped and case-insensitive,
-- matching this file's own 111-sibling structural-leg convention (see
-- `111`'s leg 7g). A version bump changes the literal and REDs THIS test —
-- in front of QA and Sec, at the same PR that makes the change — rather
-- than shipping a frozen-but-invisible contract drift. Deliberately placed
-- HERE and NOT in `115`: Sec's FLAG-4 read accepted 115's reasoning for
-- declining a pin there (a real payload-shape gap 14i already discloses
-- would be masked by a same-file pin comparing the column to its own
-- field), so the mechanism-carrying pin belongs on the composer that OWNS
-- the literal, not on a consumer that only echoes it.
-- =====================================================================
select ok(
  (select count(*) = 1
     from regexp_matches(
            (select regexp_replace(prosrc, '--[^\n]*', '', 'g') from pg_proc
              where oid = 'pfin.fn_render_monthly_report(date,date)'::regprocedure),
            '''payload_schema_version''\s*,\s*1\y', 'gi')),
  '(9) VERSION PIN: the composed payload''s payload_schema_version literal is 1 in the installed, comment-stripped body of fn_render_monthly_report — a bump to any other value REDs this leg instead of silently changing the frozen `108` contract shape with no fence anywhere in CI'
);

select * from finish();
rollback;
