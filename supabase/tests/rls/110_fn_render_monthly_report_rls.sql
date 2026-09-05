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

select plan(11);

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
-- LEG 5 — every envelope crosses UNFLATTENED: {status, reason} arrives as an
-- OBJECT, not a collapsed scalar.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select jsonb_typeof(r -> 'sections' -> 'nav_performance' -> 'delta_panel') = 'object'
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel') ? 'status'
      and (r -> 'sections' -> 'nav_performance' -> 'delta_panel') ? 'reason'
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(5) nav_performance.delta_panel crosses as an OBJECT with status+reason keys, not a collapsed scalar — no `?? 0` inside this function'
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
-- LEG 7 — the §2.1.3 / §2.1.4 sections carry the reader_not_as_of_threadable
-- envelope (Finding 1, option α): asserted so that closing Finding 1 REDS
-- this leg and forces the payload contract to be re-read.
-- =====================================================================
select ok(
  (select (r -> 'sections' -> 'nav_performance' -> 'delta_panel' ->> 'reason') = 'reader_not_as_of_threadable'
      and (r -> 'sections' -> 'nav_performance' -> 'reference_dates' ->> 'reason') = 'reader_not_as_of_threadable'
     from (select pfin.fn_render_monthly_report('2026-08-01', '2026-08-31') as r) q),
  '(7) both delta_panel AND reference_dates carry reason = ''reader_not_as_of_threadable'' (Finding 1) — closing that finding must REDDEN this leg, forcing the payload contract to be re-read rather than silently drifting'
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
-- LEG E13 — Finding 4 (F/CTO + Sec, routed, one-line fix not taken
-- unilaterally): nothing guarantees one draft per month. Two drafts for the
-- SAME month are legal; the composer picks the HIGHEST report_id and echoes
-- it as source_report_id so the caller can ASSERT it against the row it is
-- about to write.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of, commentary_cash)
  values ('2026-09-01', '2026-09-30', 'first-draft') returning report_id as d_first \gset
insert into pfin.monthly_report (target_month, data_as_of, commentary_cash)
  values ('2026-09-01', '2026-09-30', 'second-draft') returning report_id as d_second \gset
select ok(
  :d_second > :d_first,
  '(E13-setup) NON-VACUOUS: the second draft''s report_id is genuinely HIGHER than the first (fixture sanity, not a real assertion of the fence)'
);
select ok(
  (select (r -> 'sections' -> 'rebalancing_targets' ->> 'source_report_id')::bigint = :d_second
      and (r -> 'sections' -> 'rebalancing_targets' ->> 'cash') = 'second-draft'
     from (select pfin.fn_render_monthly_report('2026-09-01', '2026-09-30') as r) q),
  '(E13) MULTIPLE DRAFTS PER MONTH ARE LEGAL: with two drafts open for the same month, the composer picks the HIGHEST report_id (the LATER draft) — source_report_id echoes it AND the commentary actually read back is the SECOND draft''s, not the first''s'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
