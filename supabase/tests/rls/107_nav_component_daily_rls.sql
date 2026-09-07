-- =====================================================================
-- 107 — pfin.nav_component_daily (ADR-054 Decision 1 Option C / SELF-353 / A9):
--   the NAV component-checkpoint capture substrate. ADR-011 Decision 3 CANONICAL
--   INSTANCE #19 (account_id). Sec joint-review-mandatory per ADR-054's Governance
--   block: FOUR independent triggers (new tenant-scoped audit-class financial table
--   + new RLS + a cron write-path extension + a Decision 3 family extension).
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `107`.
--
-- ⟦EXPECTED STACK⟧ `107`-applied. Below `107` the table does not exist and every
-- assertion here is RED for that reason alone. Report the applied set alongside
-- any result: select max(version) from supabase_migrations.schema_migrations;
--
-- SOURCE NOTE (Architect F-1, 107 header): the worker's REAL leaf source is
-- pfin.fn_account_unrealized_gl (049), NOT fn_nav_composition (051/105) — that
-- function anti-joins out tax-authority-designated ledgers while nav_daily stays
-- GROSS. This battery does NOT call 049 (its own correctness is 049's own
-- battery's job); it exercises the PRODUCTION STATEMENT SHAPE VERBATIM (W1-W4)
-- against literal leaf values, which is exactly what a DDL/RLS two-tenant battery
-- can prove — the cross-artifact invariant (arbiter grant <-> ON CONFLICT target
-- <-> real unique index) and the reconciliation identity itself.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b()/_c() plus battery-local tenants D (aal2 leg) and E (GUC-null-trap +
-- same-day-rerun-watcher legs)). NO PII, no real account numbers, no production
-- data. Rolled-back txn; no `supabase db reset`.
--
-- ⚠ GUC ORDERING CONSTRAINT (structural, per 054's own documented lesson):
-- `app.nav_computed_for` is transaction-local and CANNOT be restored to NULL once
-- set (set_config(..., NULL, true) yields '', not NULL). (B0), the genuinely-UNSET
-- case, MUST therefore run before ANY set_config of that GUC anywhere in this file
-- — including the fixture rows for other legs. DO NOT REORDER.
--
-- LAYER MAP — which mechanism each section actually exercises:
--   B  — nav_component_daily_assert_computed_for (write-tenant binding), NULL/empty legs.
--   R  — THE RECONCILIATION (AC 6): production statement shape, Σ(leaves) = nav_daily.nav_value.
--   RR — same-day re-run (W3): no leaves written; reconciliation still holds; watcher-teeth proof.
--   M  — ADR-011 Decision 3 #19 (matched_account) + disjointness from the binding fence.
--   I  — immutability (UPDATE/DELETE/TRUNCATE, all roles) + the authenticated no-write ACL.
--   S  — RLS SELECT (owner-only + cross-tenant-empty) + the 025 aal2 step-up backstop.
--   G  — grants exactly as declared; no JSONB; FK delete-actions.
--   N  — finiteness CHECK (nav_component_daily_value_finite): NaN/±Infinity rejected,
--        finite numeric accepted (F-4).
--   F  — structural BEFORE-INSERT-only pin + same-transaction rollback (F-2).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_binding '%write-tenant binding REJECTED%'
\set m_matched '%ADR-011 Decision 3 #19 matched-tenant fence%'
\set m_immut_upd '%is immutable%UPDATE blocked%'
\set m_immut_del '%is immutable%DELETE blocked%'
\set m_immut_trunc '%is immutable%TRUNCATE blocked%'
\set m_acl '%permission denied for table nav_component_daily%'
\set m_acl_navdaily '%permission denied for table nav_daily%'

select plan(52);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
-- Tenant D: battery-local, totp-enrolled reader for the aal2 backstop leg (054/057 shape).
\set td '00000000-0000-0000-0000-00000000000d'
-- Tenant E: battery-local, used ONLY by (B0)/(B0b) and (RR4) so those legs cannot perturb
-- any count asserted for tenant A elsewhere in this file (the 054 leg-isolation lesson).
\set te '00000000-0000-0000-0000-00000000000e'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td'), (:'te');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'),
  (:'tb', 'none'),
  (:'td', 'totp'),
  (:'te', 'none');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct-1', 'depository', 'household', 'taxable') returning account_id as ta1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct-2', 'investment', 'household', 'taxable') returning account_id as ta2 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct-1', 'depository', 'household', 'taxable') returning account_id as tb1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'td', 'D-acct-1', 'depository', 'household', 'taxable') returning account_id as td1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'te', 'E-acct-1', 'depository', 'household', 'taxable') returning account_id as te1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'te', 'E-acct-2', 'depository', 'household', 'taxable') returning account_id as te2 \gset

-- pg_temp helper: reproduces the worker's SCALAR statement (054's qa_rc idiom EXACTLY —
-- ROW_COUNT via GET DIAGNOSTICS, NOT `RETURNING nav_id`). See (R0) below for why: the
-- header-specified W3 form (`... on conflict (users_id, nav_date) do nothing returning
-- nav_id`) is REJECTED for service_role today — RETURNING requires SELECT on every
-- returned column, even for a just-inserted row, and 054's column grant on nav_daily is
-- (users_id, nav_date) ONLY, not nav_id. ROW_COUNT (1 = inserted, 0 = conflict no-op) is
-- the did-it-insert signal this helper uses instead — needs no additional grant and is
-- what 054's own qa_rc already established as the idiom. MUST NOT PROPAGATE an exception
-- (pgTAP evaluates assertion arguments before running the assertion; an uncaught
-- exception here would abort the whole file rather than redden one assertion — the 054
-- (h11) lesson).
create function pg_temp.qa_scalar_insert(p_uid uuid, p_date date, p_val numeric) returns int
language plpgsql as $qa$
declare n int;
begin
  insert into pfin.nav_daily (users_id, nav_date, nav_value) values (p_uid, p_date, p_val)
    on conflict (users_id, nav_date) do nothing;
  get diagnostics n = row_count;
  return n;
exception when others then
  return null;
end $qa$;

-- =====================================================================
-- B — WRITE-TENANT BINDING FENCE, NULL/EMPTY TRAP (fn_nav_component_daily_assert_computed_for)
--   Positioned FIRST, by necessity: see the GUC ORDERING CONSTRAINT above.
-- =====================================================================
select set_config('role', 'service_role', true);

-- (B0) GUC NEVER SET -> current_setting(...,true) is NULL -> MUST reject.
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-01', %s, 1.00) $$, :'te', :te1),
  :'m_binding',
  '(B0) GUC NEVER SET: the NULL trap. current_setting(''app.nav_computed_for'', true) is NULL -> MUST reject (a naive equality test would fail OPEN here, not raise). Must run before ANY set_config of that GUC in this transaction — it cannot be restored to NULL once set'
);

-- (B0b) GUC = empty string -> MUST reject (a set_config that ran with an empty value).
select set_config('app.nav_computed_for', '', true);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-01', %s, 1.00) $$, :'te', :te1),
  :'m_binding',
  '(B0b) GUC = empty string -> MUST reject — the explicit `= ''''` arm; a bound-but-empty GUC must never read as "bound"'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- R — THE RECONCILIATION (AC 6): Σ(component_value) = nav_daily.nav_value for the
--   same (users_id, nav_date), via the PRODUCTION STATEMENT SHAPE VERBATIM (W1-W4):
--   scalar INSERT first (ROW_COUNT signal, NOT `returning nav_id` — ruling E10; see (R0)),
--   TARGETED on conflict (users_id, nav_date, account_id) do nothing, as service_role
--   under the app.nav_computed_for GUC 054 and this table share.
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'ta', true);

-- (R0) ⚠ CROSS-ARTIFACT GAP FOUND HERE, flagged rather than silently worked around:
-- 107's header specifies W3 as "INSERT ... RETURNING nav_id". RETURNING requires
-- SELECT privilege on every returned column — even for the row the SAME statement
-- just inserted (measured directly; not inferred). service_role's column-level
-- SELECT grant on pfin.nav_daily (054) is (users_id, nav_date) ONLY — no nav_id.
-- So the VERBATIM W3 statement, as specified, is REJECTED for service_role today.
-- RULING E10: W3 uses GET DIAGNOSTICS ROW_COUNT instead of RETURNING (no grant
-- needed — this battery's own helper uses that form; see qa_scalar_insert).
-- Widening the 054 grant to `select (nav_id)` is FORBIDDEN without Sec joint
-- review — 054's own header requires that review for any grant change on
-- nav_daily, and this leg exists to keep that requirement from being routed
-- around silently.
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-09-01', 1.00)
              on conflict (users_id, nav_date) do nothing returning nav_id $$, :'ta'),
  :'m_acl_navdaily',
  '(R0) PERMANENT KNOWN-GAP WATCHER: the `RETURNING nav_id` form of the scalar INSERT is REJECTED for service_role — 054''s column grant is (users_id, nav_date) only, and RETURNING needs SELECT on every returned column even for a just-inserted row. RULING E10: the signal is ROW_COUNT, and 054''s grant is NOT widened. ⚠ IF THIS LEG REDS, the grant was widened — that is a Sec-joint-review-mandatory change per 054''s own header, not a repair to make here'
);

select is(
  pg_temp.qa_scalar_insert(:'ta'::uuid, '2026-09-01', 1500.00),
  1,
  '(R1) scalar INSERT (ROW_COUNT form — see (R0)) ACCEPTED for a fresh (ta, 2026-09-01): ROW_COUNT = 1, the did-it-insert signal W3 branches on'
);

select lives_ok(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-01', %s, 1000.00), (%L, '2026-09-01', %s, 500.00)
              on conflict (users_id, nav_date, account_id) do nothing $$, :'ta', :ta1, :'ta', :ta2),
  '(R2) multi-row leaf INSERT (W4, PRODUCTION STATEMENT SHAPE VERBATIM — targeted ON CONFLICT) ACCEPTED for both of tenant A''s accounts'
);

-- Switch to postgres for the verification reads below: service_role CANNOT read
-- component_value (column grant is arbiter-columns-only, proven at (G2)) and CANNOT
-- read nav_daily.nav_value either (054's own column grant is (users_id, nav_date)
-- only) — reading the reconciliation as service_role would itself be a permission
-- error, not a test of the reconciliation.
select set_config('role', 'postgres', true);

select is(
  (select sum(component_value) from pfin.nav_component_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  (select nav_value from pfin.nav_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  '(R3) THE RECONCILIATION (AC 6): Σ(component_value) over (ta, 2026-09-01) EQUALS nav_daily.nav_value for the same key — natural signs, no abs, both frozen from the same substrate in this transaction'
);

select is(
  (select count(*)::int from pfin.nav_component_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  2,
  '(R4) NON-VACUOUS: exactly 2 leaf rows landed — (R3)''s sum is over real rows, not a vacuous 0=0 match'
);

-- =====================================================================
-- RR — SAME-DAY RE-RUN (W3): re-run writes NO leaves, and the sum still reconciles.
--   Also proves the leg has TEETH: a contract-violating worker that writes an extra
--   leaf on a re-run day the scalar did NOT re-insert breaks the reconciliation —
--   which is precisely why the battery leg (not a CHECK) is the watcher (Governance).
-- =====================================================================
select set_config('role', 'service_role', true);
select is(
  pg_temp.qa_scalar_insert(:'ta'::uuid, '2026-09-01', 9999.00),
  0,
  '(RR1) same-day re-run: the scalar INSERT (targeted on conflict do nothing) reports ROW_COUNT = 0 for the existing (ta, 2026-09-01) — the signal W3 branches on to skip the leaf write'
);
select set_config('role', 'postgres', true);
select is(
  (select nav_value from pfin.nav_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  1500.00,
  '(RR2) NON-VACUOUS: nav_daily.nav_value is UNCHANGED at the ORIGINAL 1500.00 — the re-run''s 9999.00 never landed, confirming DO NOTHING really means nothing changed'
);
-- Per the worker contract (W3), a CORRECT worker writes NO leaves here — omitted deliberately.
select is(
  (select sum(component_value) from pfin.nav_component_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  (select nav_value from pfin.nav_daily where users_id = :'ta'::uuid and nav_date = '2026-09-01'),
  '(RR3) reconciliation STILL holds after the same-day re-run: no leaves were written (correctly, per W3), so Σ(component_value) still equals nav_daily.nav_value exactly'
);

-- (RR4a)/(RR4b) WATCHER TEETH, on isolated tenant E so nothing here perturbs (a)/(R)/(S)
--   counts elsewhere. Simulates a worker that VIOLATES the contract.
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'te', true);
select is(
  pg_temp.qa_scalar_insert(:'te'::uuid, '2026-09-02', 700.00),
  1,
  '(RR4-day1) tenant E day-1 scalar INSERT ACCEPTED (ROW_COUNT = 1) — sets up the same-day-rerun watcher-teeth demonstration in (RR4a)/(RR4b)'
);
insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
  values (:'te', '2026-09-02', :te1, 700.00)
  on conflict (users_id, nav_date, account_id) do nothing;
select is(
  pg_temp.qa_scalar_insert(:'te'::uuid, '2026-09-02', 999999.00),
  0,
  '(RR4a) tenant E same-day re-run: scalar INSERT correctly reports ROW_COUNT = 0 (idempotent), mirroring (RR1)'
);
-- CONTRACT VIOLATION, deliberately: an extra leaf for a NEW account on the SAME day the
-- scalar did not re-insert. No DDL can prevent this (Governance: PARITY, NOT INVARIANT).
insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
  values (:'te', '2026-09-02', :te2, 300.00)
  on conflict (users_id, nav_date, account_id) do nothing;
select set_config('role', 'postgres', true);
select isnt(
  (select sum(component_value) from pfin.nav_component_daily where users_id = :'te'::uuid and nav_date = '2026-09-02'),
  (select nav_value from pfin.nav_daily where users_id = :'te'::uuid and nav_date = '2026-09-02'),
  '(RR4b) WATCHER TEETH: with the contract violated (an extra leaf written on a re-run day the scalar did not re-insert), Σ(component_value) NO LONGER equals nav_daily.nav_value — this is exactly the worker-contract regression the reconciliation battery leg exists to catch, and no CHECK constraint could (Governance / PARITY NOT INVARIANT)'
);

-- =====================================================================
-- M — ADR-011 DECISION 3 #19 (fn_nav_component_daily_matched_account) + DISJOINTNESS
--   from the write-tenant binding fence. Neither BEFORE INSERT fence subsumes the
--   other (107 header, lines ~493-506; Architect notes legs 2 and 4).
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'tb', true);

select lives_ok(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-03', %s, 250.00) $$, :'tb', :tb1),
  '(M1) OWN-ACCOUNT LEAF ACCEPTED: GUC bound to tenant B, account_id genuinely owned by B — passes BOTH BEFORE INSERT fences (the positive control for M2/M3)'
);

select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-04', %s, 250.00) $$, :'tb', :ta1),
  :'m_matched',
  '(M2) FOREIGN account_id UNDER OWN users_id: GUC still correctly bound to tenant B (assert_computed_for PASSES: new.users_id=B matches the GUC), but account_id names tenant A''s account -> REJECTED ONLY by #19. Disjointness leg 1/2 (Architect notes leg 2): the binding fence alone would NOT catch this'
);

select set_config('app.nav_computed_for', :'ta', true);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-04', %s, 250.00) $$, :'tb', :tb1),
  :'m_binding',
  '(M3) SELF-CONSISTENT PAIR, WRONG SERVED TENANT: (users_id=B, account_id=B''s own) is internally matched -> #19 would PASS it -> but the GUC says the database served tenant A -> REJECTED ONLY by the write-tenant binding fence. Disjointness leg 2/2 (Architect notes leg 4): #19 alone would NOT catch this'
);

select set_config('app.nav_computed_for', :'ta', true);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-05', 999999999, 250.00) $$, :'ta'),
  :'m_matched',
  '(M4) NONEXISTENT account_id UNDER A CORRECTLY BOUND GUC (F-5): users_id=A matches the GUC (assert_computed_for PASSES), but account_id 999999999 references no pfin.account row AT ALL -> REJECTED by #19''s own NOT EXISTS check, not by the account_id FK. PINS ORDERING: a BEFORE INSERT row trigger always runs before the referencing FK constraint is checked, so the matched-tenant message is what a caller observes for a wholly-invented account_id, never a foreign key violation — the second of #19''s two catalogued raise legs (the first is the cross-tenant leg at M2)'
);
select set_config('role', 'postgres', true);

select ok(
  (select t1.tgname < t2.tgname
     from pg_trigger t1, pg_trigger t2
    where t1.tgrelid = 'pfin.nav_component_daily'::regclass and t1.tgname = 'nav_component_daily_assert_computed_for'
      and t2.tgrelid = 'pfin.nav_component_daily'::regclass and t2.tgname = 'nav_component_daily_matched_account'),
  '(M5) TRIGGER FIRING ORDER IS ALPHABETICAL BY NAME: nav_component_daily_assert_computed_for sorts before nav_component_daily_matched_account, so the write-tenant binding fence evaluates first on every INSERT — a rename that reorders them would silently swap which message a battery observes first'
);

-- =====================================================================
-- I — IMMUTABILITY (all roles) + the authenticated no-write ACL.
--   authenticated: NO INSERT grant, NO INSERT policy -> the forge is refused AT THE
--   ACL, before RLS and before any trigger — so assert the ACL message, not a trigger.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-10', %s, 100.00) $$, :'ta', :ta1),
  :'m_acl',
  '(I1) authenticated INSERT forge REFUSED AT THE TABLE ACL (permission denied) — there is no INSERT grant and no INSERT policy, so this is never reached by any trigger'
);
select set_config('role', 'postgres', true);

select is(
  (select count(*)::int from pg_policies where schemaname = 'pfin' and tablename = 'nav_component_daily' and cmd in ('INSERT', 'UPDATE', 'DELETE')),
  0,
  '(I2) DECLARATIVE: zero INSERT/UPDATE/DELETE policies exist on nav_component_daily for any role — the RLS-layer default-deny behind (I1)''s ACL denial'
);

grant update, delete on pfin.nav_component_daily to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ update pfin.nav_component_daily set component_value = 999 where users_id = %L $$, :'ta'),
  :'m_immut_upd',
  '(I3) service_role UPDATE blocked by the row-level immutability trigger (test-only grant held open so the TRIGGER, not a missing grant, is the sole gate — the 004/054 idiom)'
);
select throws_like(
  format($$ delete from pfin.nav_component_daily where users_id = %L $$, :'ta'),
  :'m_immut_del',
  '(I4) service_role DELETE blocked by the same trigger'
);
select set_config('role', 'postgres', true);
-- Close the test-only grant immediately — otherwise (G4)/(G5) below would observe
-- the WIDENED grant, not production posture (the 054 leg-(c) discipline: assert
-- least-privilege absence either BEFORE opening a test-only grant, or after
-- explicitly closing it again).
revoke update, delete on pfin.nav_component_daily from service_role;

select throws_like(
  format($$ update pfin.nav_component_daily set component_value = 999 where users_id = %L $$, :'ta'),
  :'m_immut_upd',
  '(I5) OWNER (postgres) UPDATE blocked by the row-level trigger — no grant needed, RLS bypassed by ownership, so the TRIGGER is the sole gate (the cleanest tier: no grant, no role switch, no BYPASSRLS dependency)'
);
select throws_like(
  format($$ delete from pfin.nav_component_daily where users_id = %L $$, :'ta'),
  :'m_immut_del',
  '(I6) OWNER DELETE blocked by the same trigger'
);
select throws_like(
  $$ truncate pfin.nav_component_daily $$,
  :'m_immut_trunc',
  '(I7) TRUNCATE blocked by the STATEMENT-level trigger, as the table OWNER — ownership confers TRUNCATE intrinsically and RLS is bypassed, so the statement trigger is the ONLY thing stopping a full-table wipe (row-level triggers do not fire on TRUNCATE)'
);

select ok(
  not has_table_privilege('authenticated', 'pfin.nav_component_daily', 'INSERT')
  and not has_table_privilege('authenticated', 'pfin.nav_component_daily', 'UPDATE')
  and not has_table_privilege('authenticated', 'pfin.nav_component_daily', 'DELETE'),
  '(I8) authenticated holds NO INSERT/UPDATE/DELETE grant on nav_component_daily — (I1)''s ACL denial is a genuine absence of grant, not an RLS default-deny behind an open ACL'
);

-- =====================================================================
-- S — RLS SELECT (owner-only + cross-tenant-empty) + the 025 aal2 step-up backstop
--   (C3 standing obligation), as a SEPARATE leg per team-lead's brief, plus an
--   in-suite corrupt-the-control inversion.
-- =====================================================================
select _rls.expect_owner_can_read('pfin.nav_component_daily'::regclass, :'ta'::uuid, 2::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.nav_component_daily'::regclass, :'ta'::uuid, :'tb'::uuid);

select ok(
  (select pg_get_expr(pol.polqual, pol.polrelid) like '%totp%' and pg_get_expr(pol.polqual, pol.polrelid) like '%passkey%'
     from pg_policy pol join pg_class c on c.oid = pol.polrelid
    where c.relname = 'nav_component_daily' and pol.polname = 'nav_component_daily_select'),
  '(S6a) STRUCTURAL TEXT-PIN: nav_component_daily_select''s USING clause mentions both ''totp'' and ''passkey'' — the mfa_policy gate the 025 backstop conditions on'
);
select ok(
  (select pg_get_expr(pol.polqual, pol.polrelid) like '%aal2%'
     from pg_policy pol join pg_class c on c.oid = pol.polrelid
    where c.relname = 'nav_component_daily' and pol.polname = 'nav_component_daily_select'),
  '(S6b) STRUCTURAL TEXT-PIN: the same USING clause mentions ''aal2'' — the JWT claim check the step-up backstop requires'
);

-- fixture row for the behavioural aal2 legs (tenant D, totp-enrolled). Set AFTER (B0)/
-- (B0b) per the GUC ordering constraint — already satisfied at this point in the file.
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
  values (:'td', '2026-09-06', :td1, 400.00);

select is(
  _rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.nav_component_daily where users_id = %L', :'td')),
  0::bigint,
  '(S3) THE BACKSTOP: a totp-enrolled reader at aal1 sees 0 of its OWN nav_component_daily rows'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.nav_component_daily where users_id = %L', :'td')),
  1::bigint,
  '(S4) NON-VACUOUS: the SAME totp reader stepped up to aal2 sees its 1 own row — proves (S3) blocks on aal and not on the user being row-less'
);

-- (S5) CORRUPT-THE-CONTROL, IN-SUITE: strip the aal2 conjunct and prove (S3)''s zero was
-- the backstop''s doing, not an accident of the fixture. Restored immediately below.
savepoint corrupt_aal2;
drop policy nav_component_daily_select on pfin.nav_component_daily;
create policy nav_component_daily_select on pfin.nav_component_daily
  for select to authenticated using (users_id = auth.uid());
select is(
  _rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.nav_component_daily where users_id = %L', :'td')),
  1::bigint,
  '(S5) CORRUPT-THE-CONTROL: with the aal2 conjunct stripped from nav_component_daily_select, the SAME totp@aal1 reader NOW sees its row — the regression (S3) exists to catch'
);
rollback to savepoint corrupt_aal2;
select set_config('role', 'postgres', true);

-- =====================================================================
-- G — GRANTS EXACTLY AS DECLARED; NO JSONB; FK DELETE-ACTIONS.
-- =====================================================================
select set_config('role', 'service_role', true);
select ok(has_column_privilege('service_role', 'pfin.nav_component_daily', 'users_id', 'SELECT'), '(G1a) service_role holds column-level SELECT on users_id (arbiter column)');
select ok(has_column_privilege('service_role', 'pfin.nav_component_daily', 'nav_date', 'SELECT'), '(G1b) service_role holds column-level SELECT on nav_date (arbiter column)');
select ok(has_column_privilege('service_role', 'pfin.nav_component_daily', 'account_id', 'SELECT'), '(G1c) service_role holds column-level SELECT on account_id (arbiter column)');
select throws_like(
  $$ select component_value from pfin.nav_component_daily limit 1 $$,
  :'m_acl',
  '(G2) service_role CANNOT read component_value — the column grant is EXACTLY the three arbiter columns and nothing else; no monetary figure is reachable by the writer'
);
select throws_like(
  $$ select * from pfin.nav_component_daily limit 1 $$,
  :'m_acl',
  '(G3) service_role CANNOT select * — a positive column-select alone cannot distinguish a column grant from a table grant; this negative is what does'
);
select set_config('role', 'postgres', true);

select ok(not has_table_privilege('service_role', 'pfin.nav_component_daily', 'UPDATE'), '(G4) service_role holds NO UPDATE grant (least privilege; the trigger fences it too, but the ACL should not silently widen)');
select ok(not has_table_privilege('service_role', 'pfin.nav_component_daily', 'DELETE'), '(G5) service_role holds NO DELETE grant');

select is(
  (select count(*)::int from information_schema.columns where table_schema = 'pfin' and table_name = 'nav_component_daily' and data_type = 'jsonb'),
  0,
  '(G6) NO jsonb column on nav_component_daily — a plain relational leaf capture, per the 107 header'
);

select is(
  (select con.confdeltype from pg_constraint con
     join pg_attribute att on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
    where con.conrelid = 'pfin.nav_component_daily'::regclass and con.contype = 'f'
      and array_length(con.conkey, 1) = 1 and att.attname = 'account_id'),
  'r',
  '(G7) the account_id FK is ON DELETE RESTRICT — a captured observation must not be silently erased by an account deletion (the 057 #16 choice, for the same reason: the table is append-only, so CASCADE would be the one deletion path that bypasses the immutability fences)'
);
select is(
  (select con.confdeltype from pg_constraint con
     join pg_attribute att on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
    where con.conrelid = 'pfin.nav_component_daily'::regclass and con.contype = 'f'
      and array_length(con.conkey, 1) = 1 and att.attname = 'users_id'),
  'c',
  '(G8) the users_id FK is ON DELETE CASCADE — a user''s checkpoints are dependent data'
);
select ok(has_table_privilege('authenticated', 'pfin.nav_component_daily', 'SELECT'), '(G9) authenticated holds table-level SELECT (grant-before-RLS, PR #106 shape) — RLS filters rows, the grant lets the role reach the table at all');

-- =====================================================================
-- N — FINITENESS CHECK (nav_component_daily_value_finite): NaN and ±Infinity
--   rejected; an ordinary finite numeric passes (F-4 — this CHECK had no watcher).
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'ta', true);

select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-11', %s, 'NaN'::numeric) $$, :'ta', :ta1),
  '%nav_component_daily_value_finite%',
  '(N1) NaN is REJECTED by the finiteness CHECK — a poisoned leaf must never enter the series (the 053 N1 lesson this idiom is named for)'
);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-12', %s, 'Infinity'::numeric) $$, :'ta', :ta1),
  '%nav_component_daily_value_finite%',
  '(N2) +Infinity is REJECTED by the same CHECK'
);
select throws_like(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-13', %s, '-Infinity'::numeric) $$, :'ta', :ta1),
  '%nav_component_daily_value_finite%',
  '(N3) -Infinity is REJECTED by the same CHECK — both non-finite ends of the domain, not just NaN'
);
select lives_ok(
  format($$ insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
              values (%L, '2026-09-14', %s, 42.00) $$, :'ta', :ta1),
  '(N4) POSITIVE CONTROL: an ordinary finite numeric is ACCEPTED — N1-N3 reject non-finite values specifically, not every write through this CHECK'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- F — STRUCTURAL BEFORE-INSERT-ONLY PIN + SAME-TRANSACTION ROLLBACK (F-2).
-- =====================================================================
select is(
  (select count(*)::int from pg_trigger
    where tgrelid = 'pfin.nav_component_daily'::regclass
      and tgfoid = 'pfin.fn_nav_component_daily_matched_account()'::regprocedure
      and not tgisinternal),
  1,
  '(F1a) exactly ONE trigger uses fn_nav_component_daily_matched_account'
);
select ok(
  (select pg_get_triggerdef(oid) like '%BEFORE INSERT%'
     and pg_get_triggerdef(oid) not like '%UPDATE%'
     and pg_get_triggerdef(oid) not like '%DELETE%'
     from pg_trigger
    where tgrelid = 'pfin.nav_component_daily'::regclass and tgname = 'nav_component_daily_matched_account'),
  '(F1b) nav_component_daily_matched_account fires BEFORE INSERT ONLY — no UPDATE/DELETE variant (the table is immutable audit-class, so an UPDATE fence would be dead code; the 019/044/057 shape)'
);

select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'ta', true);
select throws_like(
  format($fmt$
    do $do$
    begin
      insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-09-07', 3000.00)
        on conflict (users_id, nav_date) do nothing;
      insert into pfin.nav_component_daily (users_id, nav_date, account_id, component_value)
        values (%L, '2026-09-07', %s, 3000.00);
    end $do$;
  $fmt$, :'ta', :'ta', :tb1),
  :'m_matched',
  '(F2a) SAME-TRANSACTION ATOMICITY (F-2): the scalar INSERT and a #19-violating leaf INSERT (tenant A''s row referencing tenant B''s account) run inside ONE statement (a DO block); the leaf raises and PostgreSQL statement-level atomicity rolls back BOTH — proving the same-transaction shape is observable, not merely asserted'
);
select is(
  (select count(*)::int from pfin.nav_daily where users_id = :'ta'::uuid and nav_date = '2026-09-07'),
  0,
  '(F2b) NON-VACUOUS: the scalar row from the aborted same-transaction attempt was never persisted — confirms (F2a) rolled back the WHOLE statement, not just the leaf half'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
