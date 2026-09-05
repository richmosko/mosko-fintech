-- =====================================================================
-- 108 — pfin.monthly_report (ADR-011 Decision 15 / Lock 11; SELF-345 / A1).
--   The Lock 11 header + R1 frozen-payload carrier. ADR-011 Decision 3 CANONICAL
--   LABEL #3 (included_reconciliation_event_ids), P1/CR hybrid, DORMANT.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `108`. Reviewed as ONE
-- design unit with `109`/`110`/`111` under ONE Sec joint-review (R13 step 6).
--
-- ⟦EXPECTED STACK⟧ `108`-applied. Below it the table does not exist and every
-- assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D for the aal2 leg); no PII, no real account
-- numbers, no production data. Rolled-back txn; no `supabase db reset`.
--
-- ⚠ UPDATED_AT MEASUREMENT LIMIT, stated rather than papered over: this whole
-- file runs inside ONE wrapped transaction, so `now()` (what
-- fn_refresh_updated_at writes) is FROZEN for its entire duration — a plain
-- before/after VALUE comparison cannot distinguish "the trigger fired and wrote
-- the frozen now()" from "the trigger did not fire and the value never moved",
-- because both produce the identical timestamp. Leg 13 uses a SENTINEL-OVERWRITE
-- technique for the "fires on draft" half (explicitly set updated_at to an
-- off-domain value; if the trigger fires it gets clobbered) and a STRUCTURAL
-- catalog pin for the "does not fire outside draft" half, rather than a
-- behavioural comparison the harness cannot make honest.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_superseded_terminal '%TERMINAL%'
\set m_one_transition '%admits exactly ONE transition%'
\set m_nothing_else '%NOTHING ELSE%'
\set m_insert_state '%may be INSERTed in the `draft` state ONLY%'
\set m_matched3 '%ADR-011 Decision 3 #3 array-element matched-tenant fence%'
\set m_immut_col '%users_id and target_month are immutable in EVERY state%'
\set m_live_draft '%monthly_report_one_live_draft_per_month%'

select plan(36);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- Accounts + reconciliation_event fixtures for leg 12b (the firing leg).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct', 'depository', 'household', 'taxable') returning account_id as ta_acct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct', 'depository', 'household', 'taxable') returning account_id as tb_acct \gset
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:ta_acct, '2026-08-31', 'balance', 1000.00) returning event_id as ta_event \gset
insert into pfin.reconciliation_event (account_id, reconciliation_date, dimension, statement_balance)
  values (:tb_acct, '2026-08-31', 'balance', 2000.00) returning event_id as tb_event \gset

-- =====================================================================
-- LEG 1 — cross-tenant read fails closed; owner reads own rows.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31');
select set_config('role', 'postgres', true);
select _rls.expect_owner_can_read('pfin.monthly_report'::regclass, :'ta'::uuid, 1::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.monthly_report'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- LEG 2 — aal2 as a SEPARATE leg from cross-tenant (Sec F-9).
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31');
select set_config('role', 'postgres', true);
select is(
  _rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.monthly_report where users_id = %L', :'td')),
  0::bigint,
  '(2a) aal2 backstop: a totp-enrolled reader at aal1 sees 0 of its OWN monthly_report rows'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.monthly_report where users_id = %L', :'td')),
  1::bigint,
  '(2b) NON-VACUOUS: the SAME totp reader stepped up to aal2 sees its 1 own row'
);

-- =====================================================================
-- LEG 3 — regenerate ONE month THREE times (Sec D-5): three rows, exactly one
-- final. A two-regeneration leg cannot distinguish the ratified index from a
-- defective three-column form of it.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') returning report_id as d1 \gset
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :d1;
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') returning report_id as d2 \gset
update pfin.monthly_report set generation_status = 'superseded' where report_id = :d1;
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :d2;
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') returning report_id as d3 \gset
update pfin.monthly_report set generation_status = 'superseded' where report_id = :d2;
update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb,
  payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = :d3;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-02-01'),
  3,
  '(3a) THREE regenerations of the same month -> THREE rows'
);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-02-01' and generation_status = 'final'),
  1,
  '(3b) exactly ONE final among them (d3) — the ratified UNIQUE (users_id, target_month) WHERE final holds after two regenerations, not just one'
);

-- =====================================================================
-- LEG 4 — UPDATE a final row (any column but the transition) refused, as
-- authenticated AND as service_role.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.monthly_report set owner_header_at_generation = 'forged' where report_id = %s $$, :d3),
  :'m_one_transition',
  '(4a) authenticated UPDATE of a final row (non-transition column) refused'
);
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.monthly_report set owner_header_at_generation = 'forged' where report_id = %s $$, :d3),
  :'m_one_transition',
  '(4b) service_role UPDATE of the SAME final row refused — the trigger carries no role test'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 5 — DELETE a final and a superseded row, refused under both roles.
-- ⚠ NO role holds a DELETE grant on this table at all (R4 (a)) — the trigger's
-- own DELETE-permits-draft branch is DORMANT BY GRANT. So the refusal here is
-- an ACL denial, BEFORE RLS and BEFORE the trigger ever runs, not the trigger's
-- own message. That is the correct layer to assert (I1-style attribution).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ delete from pfin.monthly_report where report_id = %s $$, :d3),
  '%permission denied for table monthly_report%',
  '(5a) authenticated DELETE of the final row refused AT THE ACL — no DELETE grant exists for any role'
);
select throws_like(
  format($$ delete from pfin.monthly_report where report_id = %s $$, :d1),
  '%permission denied for table monthly_report%',
  '(5b) authenticated DELETE of a superseded row refused AT THE ACL'
);
select set_config('role', 'service_role', true);
select throws_like(
  format($$ delete from pfin.monthly_report where report_id = %s $$, :d3),
  '%permission denied for table monthly_report%',
  '(5c) service_role DELETE of the final row refused AT THE ACL — service_role holds SELECT/INSERT/UPDATE only'
);
select throws_like(
  format($$ delete from pfin.monthly_report where report_id = %s $$, :d1),
  '%permission denied for table monthly_report%',
  '(5d) service_role DELETE of the superseded row refused AT THE ACL'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 6 — INSERT directly as final refused; INSERT as draft accepted.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ insert into pfin.monthly_report (target_month, data_as_of, generation_status, rendered_payload, payload_schema_version, generated_at, commentary_disposition)
       values ('2026-03-01', '2026-03-31', 'final', '{}'::jsonb, 1, now(), 'skipped') $$,
  :'m_insert_state',
  '(6a) INSERT straight into `final` refused — would take the month''s slot without passing the authoring gate'
);
select lives_ok(
  $$ insert into pfin.monthly_report (target_month, data_as_of) values ('2026-03-01', '2026-03-31') $$,
  '(6b) INSERT as `draft` (the only legal INSERT state) accepted'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 7 — superseded is TERMINAL: superseded->final and superseded->draft both
-- refused.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.monthly_report set generation_status = 'final' where report_id = %s $$, :d1),
  :'m_superseded_terminal',
  '(7a) superseded -> final refused'
);
select throws_like(
  format($$ update pfin.monthly_report set generation_status = 'draft' where report_id = %s $$, :d1),
  :'m_superseded_terminal',
  '(7b) superseded -> draft refused'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 8 — users_id / target_month UPDATE refused in the DRAFT state too (Lock
-- 12's parent-immutability extension; Decision 3 label #4 half, verified here).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-04-01', '2026-04-30') returning report_id as d8 \gset
select set_config('role', 'postgres', true);
select throws_like(
  format($$ update pfin.monthly_report set target_month = '2026-05-01' where report_id = %s $$, :d8),
  :'m_immut_col',
  '(8a) target_month UPDATE refused on a DRAFT row — audit-load-bearing in every state, not a value column'
);
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.monthly_report set users_id = %L where report_id = %s $$, :'tb', :d8),
  :'m_immut_col',
  '(8b) users_id UPDATE refused on a DRAFT row (as service_role, which could otherwise re-tenant it) — Lock 12''s chain-attack catch'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 9 — final with NULL rendered_payload / NULL payload_schema_version / NULL
-- commentary_disposition refused by the status CHECK; the same row with all set
-- accepted.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-05-01', '2026-05-31') returning report_id as d9 \gset
select throws_like(
  format($$ update pfin.monthly_report set generation_status = 'final', payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = %s $$, :d9),
  '%monthly_report_payload_by_status%',
  '(9a) final with rendered_payload still NULL -> refused by the status CHECK'
);
select throws_like(
  format($$ update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb, generated_at = now(), commentary_disposition = 'skipped' where report_id = %s $$, :d9),
  '%monthly_report_payload_by_status%',
  '(9b) final with payload_schema_version still NULL -> refused'
);
select throws_like(
  format($$ update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb, payload_schema_version = 1, generated_at = now() where report_id = %s $$, :d9),
  '%monthly_report_payload_by_status%',
  '(9c) final with commentary_disposition still NULL -> refused — the DB half of the complete-or-explicitly-skip gate'
);
select lives_ok(
  format($$ update pfin.monthly_report set generation_status = 'final', rendered_payload = '{}'::jsonb, payload_schema_version = 1, generated_at = now(), commentary_disposition = 'skipped' where report_id = %s $$, :d9),
  '(9d) NON-VACUOUS: the SAME row promotes cleanly once all four are set together'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 10 — commentary one character over the 4000-char bound (PM's ruled
-- product number, 2026-09-05 — no longer a placeholder) refused THROUGH
-- POSTGREST (the DB layer), not only the app. Sec N-5: the bound is CODE
-- POINTS (length()), and P3's Zod mirror must count the same unit
-- (Array.from(s).length, not s.length) or the two layers disagree on
-- astral characters — this leg proves the DB half of that equality.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-06-01', '2026-06-30') returning report_id as d10 \gset
select throws_like(
  format($$ update pfin.monthly_report set commentary_cash = repeat('x', 4001) where report_id = %s $$, :d10),
  '%monthly_report_commentary_cash_len%',
  '(10a) commentary_cash at 4001 chars -> refused by the DB CHECK (the ruled bound: 4000 characters, PM 2026-09-05)'
);
select lives_ok(
  format($$ update pfin.monthly_report set commentary_cash = repeat('x', 4000) where report_id = %s $$, :d10),
  '(10b) NON-VACUOUS: exactly 4000 chars is accepted'
);
-- (10c)/(10d) SEC N-5 UNIT PROOF: an ASTRAL character (outside the BMP, e.g. an
-- emoji) is ONE code point to Postgres length() but TWO UTF-16 code units to
-- JavaScript's `.length` — N-5's catch criterion is that the SAME VALUE is
-- rejected at BOTH layers, an EQUALITY. A `.length`-based Zod mirror would
-- treat 4000 astral characters as 8000 and wrongly refuse what the DB accepts.
select throws_like(
  format($$ update pfin.monthly_report set commentary_cash = repeat('😀', 4001) where report_id = %s $$, :d10),
  '%monthly_report_commentary_cash_len%',
  '(10c) 4001 ASTRAL characters (code points, not bytes/UTF-16 units) -> refused by the SAME DB CHECK as (10a) — the bound is measured in code points'
);
select lives_ok(
  format($$ update pfin.monthly_report set commentary_cash = repeat('😀', 4000) where report_id = %s $$, :d10),
  '(10d) NON-VACUOUS, THE EQUALITY N-5 REQUIRES: exactly 4000 astral characters is ACCEPTED — a `.length`-based Zod mirror would count this input as 8000 and WRONGLY reject it, the exact layer-disagreement N-5 exists to prevent (P3''s Zod bound must use Array.from(s).length, never s.length)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 11 — target_month not the 1st of the month refused.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ insert into pfin.monthly_report (target_month, data_as_of) values ('2026-06-15', '2026-06-30') $$,
  '%monthly_report_target_month_is_month_start%',
  '(11) target_month not the 1st of its month -> refused; without this the Lock 11 partial UNIQUE would enforce one final per (user, DATE), not per MONTH'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 12 — CONSTRUCTION-ONLY (R5 rider, ruled): the #3 array fence EXISTS, is
-- ATTACHED to included_reconciliation_event_ids, and carries the matched-tenant
-- body.
-- =====================================================================
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'pfin.monthly_report'::regclass
      and tgfoid = 'pfin.fn_monthly_report_matched_event_tenants()'::regprocedure
      and not tgisinternal),
  1,
  '(12a) exactly ONE trigger uses fn_monthly_report_matched_event_tenants, attached to pfin.monthly_report'
);
select ok(
  (select pg_get_triggerdef(oid) like '%BEFORE INSERT OR UPDATE%'
     from pg_trigger where tgrelid = 'pfin.monthly_report'::regclass and tgname = 'monthly_report_matched_event_tenants'),
  '(12b) the trigger fires BEFORE INSERT OR UPDATE'
);
select ok(
  (select prosrc like '%included_reconciliation_event_ids%' and prosrc like '%a.users_id%'
     from pg_proc where oid = 'pfin.fn_monthly_report_matched_event_tenants()'::regprocedure),
  '(12c) STRUCTURAL: the function body chain-resolves through pfin.account.users_id and iterates included_reconciliation_event_ids — the matched-tenant body, not a stub'
);

-- =====================================================================
-- LEG 12b — RECOMMENDED FIRING LEG, alongside 12 and never instead of it (the
-- rider's premise that "nothing can populate the array" is false at the DB
-- layer: pfin.reconciliation_event carries an authenticated INSERT grant AND
-- policy). Own-tenant element accepted; foreign element rejected.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ insert into pfin.monthly_report (target_month, data_as_of, included_reconciliation_event_ids)
              values ('2026-07-01', '2026-07-31', array[%s]) $$, :ta_event),
  '(12b-1) own-tenant reconciliation_event_id in the array -> ACCEPTED (positive control for 12b-2)'
);
select throws_like(
  format($$ insert into pfin.monthly_report (target_month, data_as_of, included_reconciliation_event_ids)
              values ('2026-07-02', '2026-07-31', array[%s]) $$, :tb_event),
  :'m_matched3',
  '(12b-2) FIRING: tenant B''s reconciliation_event_id in tenant A''s array -> REJECTED. A battery is not the product — this fence is behaviourally reachable even though nothing in the shipped V1.5 product populates the array yet'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 13 — updated_at refresh fires on a draft UPDATE and does NOT fire on the
-- final -> superseded transition. See the file header for why this is split
-- into a behavioural sentinel-overwrite half and a structural half rather than
-- a plain value comparison (now() is frozen for this whole transaction).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-08-01', '2026-08-31') returning report_id as d13 \gset
-- (13a) SENTINEL: on a DRAFT row, explicitly set updated_at to an off-domain value
-- alongside a real edit. The immutability trigger's draft branch permits anything
-- and returns NEW unchanged; if fn_refresh_updated_at then fires (WHEN
-- old.generation_status = 'draft'), it OVERWRITES the sentinel with now(). A
-- surviving sentinel would mean the refresh did NOT fire.
update pfin.monthly_report set commentary_cash = 'leg13', updated_at = '1999-01-01'::timestamptz where report_id = :d13;
select set_config('role', 'postgres', true);
select isnt(
  (select updated_at from pfin.monthly_report where report_id = :d13),
  '1999-01-01'::timestamptz,
  '(13a) BEHAVIOURAL: updated_at refresh FIRES on a draft UPDATE — my explicit 1999-01-01 sentinel was overwritten, proving the trigger ran (not merely that no one touched the column)'
);
select ok(
  (select pg_get_triggerdef(oid) like '%WHEN%draft%'
     from pg_trigger where tgrelid = 'pfin.monthly_report'::regclass and tgname = 'monthly_report_refresh_updated_at'),
  '(13b) STRUCTURAL: the refresh trigger carries a WHEN (old.generation_status = ''draft'') clause — the reason it cannot fire on final/superseded rows is structural, not merely unobserved-in-this-harness (now() is frozen for the whole transaction, so a plain before/after value comparison on the final->superseded path cannot tell "correctly did not fire" from "fired and produced this same frozen instant coincidentally")'
);

-- =====================================================================
-- LEG 14 — E15: AT MOST ONE LIVE DRAFT PER (user, month)
-- (monthly_report_one_live_draft_per_month, ruled 2026-09-05 reversing an
-- earlier decline — PM's tab-A/tab-B silent-loss scenario). Reuses LEG 8's
-- still-`draft` row (d8, month 2026-04-01) for the collision, and LEG 3's
-- month (2026-02-01, one `final` + two `superseded`, zero live drafts) for
-- the positive control — proving the index is PARTIAL (WHERE draft), not a
-- blanket one-row-per-month fence that would make regeneration impossible.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ insert into pfin.monthly_report (target_month, data_as_of) values ('2026-04-01', '2026-04-30') $$,
  :'m_live_draft',
  '(14a) A SECOND draft for a month that already has a live draft (d8, still `draft` from LEG 8) -> REJECTED 23505 on monthly_report_one_live_draft_per_month — the tab-A/tab-B scenario PM supplied: without this fence a concurrent Generate silently orphans the first draft''s commentary forever (no DELETE grant exists for any role)'
);
select lives_ok(
  $$ insert into pfin.monthly_report (target_month, data_as_of) values ('2026-02-01', '2026-02-28') $$,
  '(14b) NON-VACUOUS, PROVES PARTIAL: a NEW draft for 2026-02-01 -- a month that already carries one `final` (d3) and two `superseded` (d1, d2) rows from LEG 3, and ZERO live drafts -- is ACCEPTED. A leg testing only (14a)''s refusal cannot distinguish this index from one keyed on ALL THREE states, which would make regeneration impossible'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
