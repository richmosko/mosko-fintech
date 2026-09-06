-- =====================================================================
-- 113 — pfin.fn_open_monthly_report_draft(p_target_month) returns bigint
--   (SELF-366 AC 1-4, E15 items 9/11). The A10 generate-a-draft write path.
--   Idempotent: opens the caller's LIVE DRAFT for a month, or creates it with
--   the cron's own shape. Writes an audit row THROUGH `111`'s DEFINER helper,
--   in the SAME transaction, ONLY when a row is actually inserted.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `113`. Depends on `108`
-- (the table + its two partial unique indexes) and `111` (fn_emit_audit_log).
--
-- ⟦EXPECTED STACK⟧ `113`-applied. Below it the function does not exist and
-- every assertion is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/
-- _b() plus battery-local tenant D, totp-enrolled, for the aal2 leg). No PII,
-- no real account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
--
-- ⚠ LEG 1 IS A STRUCTURAL/CATALOG PIN, NOT A LIVE TWO-CONNECTION RACE, AND
-- THAT IS A DELIBERATE, DISCLOSED DEPARTURE FROM THE PAIRING LIST'S LITERAL
-- "TWO CONCURRENT calls" FRAMING — matching this codebase's own established
-- posture for exactly this class of claim (101's SF-L legs, verbatim: "pgTAP
-- cannot hold two concurrent sessions... presence and effect are different
-- claims, and only presence is checkable here"). This file is one wrapped
-- transaction that must roll back at the end; a genuine second connection
-- would COMMIT independently and survive the rollback, breaking the harness's
-- own isolation contract. Leg 2 supplies the one BEHAVIOURAL half that IS
-- safely testable single-connection: the DB-layer fact the function's race
-- resolution relies on (E15 item 11 (ii)).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_live_draft '%monthly_report_one_live_draft_per_month%'
\set m_rls '%row-level security policy%'

select plan(23);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- LEG 1 — THE RACE MECHANISM, STRUCTURALLY (see the file header for why this
-- is a catalog pin rather than a live race): the body takes a FOR UPDATE lock
-- BEFORE its INSERT, and its `exception when unique_violation` handler
-- RE-READS under the SAME (target_month, draft) predicate and returns a
-- report_id rather than swallowing to NULL or unconditionally re-raising —
-- the exact shape E15 item 11(i) requires ("a version that returns NULL or
-- raises for the loser passes a row-count check and still breaks the
-- endpoint").
-- =====================================================================
select ok(
  (select regexp_count(lower(pg_get_functiondef(p.oid)), 'for update') = 1
      and position('for update' in lower(pg_get_functiondef(p.oid))) < position('insert into' in lower(pg_get_functiondef(p.oid)))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_open_monthly_report_draft'),
  '(1a) STRUCTURAL: exactly one `for update` lock, positioned BEFORE the `insert into` — the lock precedes the write it must serialize, matching 101''s SF-L presence-not-effect idiom for the same class of un-simulatable claim'
);
select ok(
  (select lower(pg_get_functiondef(p.oid)) ~ 'exception when unique_violation'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_open_monthly_report_draft'),
  '(1b) STRUCTURAL: an `exception when unique_violation` handler exists — the race is EXPECTED and resolved by re-reading, not merely hoped not to happen'
);
select ok(
  (select regexp_count(lower(pg_get_functiondef(p.oid)), 'is null then') = 1
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_open_monthly_report_draft'),
  '(1c) STRUCTURAL, THE UNCONDITIONAL-SWALLOW GUARD: exactly one `is null then` conditional in the whole body — the re-raise inside the exception handler is CONDITIONAL on the re-read also coming up empty, not blanket; a version that always returns whatever the re-read finds (even NULL) would still show a bare re-read but this leg''s regexp_count would still pass at 1 only if the guard is written as the migration states it — combined with (1b), the shape the pairing list names is present'
);

-- =====================================================================
-- LEG 2 — THE DB-LAYER FACT THE FUNCTION RELIES ON, PROVED WITHOUT THE APP
-- (E15 item 11 (ii)): a second `draft` INSERT for (users_id, target_month)
-- submitted DIRECTLY through PostgREST (bypassing this function entirely) is
-- refused by the DB.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31');
select throws_like(
  $$ insert into pfin.monthly_report (target_month, data_as_of) values ('2026-01-01', '2026-01-31') $$,
  :'m_live_draft',
  '(2) a second direct draft INSERT for the same (tenant, month) is refused by 108''s partial unique index — the same fact this function''s race resolution relies on, proved independently of it'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG 3 — IDEMPOTENCE: calling twice in sequence returns the SAME report_id
-- and leaves exactly one row.
-- LEG 4 — AUDIT ROWS, BOTH HALVES: exactly ONE on the inserting (first) call,
-- and NO additional row on the idempotent (second) call. (4c)/(4d) — team-lead
-- relay at the 5ca2cd1 rebase — make the (4a) proof EXPLICIT rather than
-- incidental: this function's own INSERT sits inside `begin … exception when
-- unique_violation … end` (a SUBTRANSACTION with its own xid) on EVERY
-- successful call, colliding or not — exactly the shape a naive `xmin =
-- pg_current_xact_id()` C2 implementation would refuse (measured by
-- Architect: top xid and row xmin differ by the subtransactions consumed
-- since top-xid assignment). `111`'s own battery only proves C2 accepts a
-- BARE top-level INSERT (its leg 8-iii, self-contained on that branch, with
-- no `fn_open_monthly_report_draft` to call) — THIS is the through-the-real-
-- subtransaction half, on the branch where that function actually lives.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-03-01') as d3_first \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-03-01'),
  1,
  '(3a) NON-VACUOUS PRECONDITION: exactly one row exists after the FIRST call'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :d3_first::bigint),
  1,
  '(4a) exactly ONE audit row exists after the inserting (first) call'
);
select ok(
  (select r.xmin::text::xid8 <> pg_current_xact_id() from pfin.monthly_report r where r.report_id = :d3_first::bigint),
  '(4c) NON-VACUOUS: the row this call inserted carries a SUBTRANSACTION xid, NOT the session''s top-level xact id — this really is the exception-wrapped path (line ~283 of 113''s migration), not a bare top-level INSERT that merely happens to sit inside a plpgsql function'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :d3_first::bigint and trigger_source in ('cron', 'on_demand')),
  1,
  '(4d) THE LEG: `111`''s C2 (pg_visible_in_snapshot, not xid equality) accepted this SUBTRANSACTION-written row anyway and stamped a real trigger_source on it — combined with (4c), this is the exact call a naive xid-equality C2 implementation would have refused'
);
select _rls.set_tenant(:'ta'::uuid);
select is(
  pfin.fn_open_monthly_report_draft('2026-03-01'),
  :d3_first::bigint,
  '(3b) the SECOND call returns the SAME report_id as the first'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-03-01'),
  1,
  '(3c) NON-VACUOUS: still exactly ONE row after the second call — idempotence leaves no second row'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :d3_first::bigint),
  1,
  '(4b) NO additional audit row was written on the idempotent (second, open-only) call — opening writes nothing, so emitting there would size the audit trail by UI clicks rather than by generation'
);

-- =====================================================================
-- LEG 5 — ROLLBACK: a transaction that calls this and then aborts leaves NO
-- report row and NO audit row (the same-transaction property is free here:
-- a plpgsql body is one transaction).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_rollback_leg;
select pfin.fn_open_monthly_report_draft('2026-05-01') as d5 \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-05-01'),
  1,
  '(5a) the report row EXISTS in the same transaction as the call'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :d5::bigint),
  1,
  '(5b) the audit row ALSO exists, same transaction'
);
rollback to savepoint sp_rollback_leg;
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'ta'::uuid and target_month = '2026-05-01'),
  0,
  '(5c) RESTORED CATCH CRITERION: the report row is ABSENT once the transaction rolls back'
);
select is(
  (select count(*)::int from pfin.audit_log where subject_table = 'pfin.monthly_report' and subject_id = :d5::bigint),
  0,
  '(5d) the audit row is ALSO absent — a row that survives a rolled-back generation is worse than no row'
);

-- =====================================================================
-- LEG 6 — CROSS-TENANT: tenant B cannot open OR create a draft under tenant
-- A's month; whatever id B receives is never tenant A's row.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-06-01') as d6_a \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select pfin.fn_open_monthly_report_draft('2026-06-01') as d6_b \gset
select set_config('role', 'postgres', true);
select isnt(
  :d6_b::bigint,
  :d6_a::bigint,
  '(6a) tenant B''s returned id is NEVER tenant A''s row id — B''s own RLS-scoped read cannot see A''s draft, so B creates its OWN separate row for the same calendar month rather than opening A''s'
);
select ok(
  (select users_id from pfin.monthly_report where report_id = :d6_b::bigint) = :'tb'::uuid,
  '(6b) NON-VACUOUS: the row B''s call actually touched is named B as its owner (users_id default from auth.uid()), not A'
);
select is(
  (select count(*)::int from pfin.monthly_report where target_month = '2026-06-01' and generation_status = 'draft'),
  2,
  '(6c) NON-VACUOUS: TWO separate draft rows now exist for the same calendar month, one per tenant — 108''s partial unique index is scoped to (users_id, target_month), not to target_month alone'
);

-- =====================================================================
-- LEG 7 — aal2 AS A SEPARATE LEG FROM CROSS-TENANT (Sec F-9): a totp-enrolled
-- caller at a below-aal2 JWT is refused. Unlike 112, this function has no
-- custom diagnostic message for the case — the SELECT finds nothing (aal2
-- backstop on the SELECT policy) so it proceeds to INSERT, and 108's INSERT
-- policy carries the SAME aal2 backstop in its WITH CHECK, so the raw RLS
-- violation is what a caller observes here, uncaught by this function (its
-- only exception handler catches unique_violation, not RLS).
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
select throws_like(
  $$ select pfin.fn_open_monthly_report_draft('2026-07-01') $$,
  :'m_rls',
  '(7) totp-enrolled tenant D at aal1 -> refused: the SELECT sees no draft (aal2 backstop), so the function proceeds to INSERT, and the INSERT policy''s OWN aal2 WITH CHECK refuses it — a raw RLS violation, not a custom message from this function'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.monthly_report where users_id = :'td'::uuid and target_month = '2026-07-01'),
  0,
  '(7b) NON-VACUOUS: no row was created for tenant D under the refused call'
);

-- =====================================================================
-- LEG 8 — data_as_of IS SERVER-DERIVED: the stored value equals the server's
-- date (RT-25) — LEG 9 rides the same fixture: the inserted row is `draft`,
-- never `final`.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-08-01') as d8 \gset
select set_config('role', 'postgres', true);
select is(
  (select data_as_of from pfin.monthly_report where report_id = :d8::bigint),
  (select pfin.fn_server_today()),
  '(8) data_as_of on the inserted row equals pfin.fn_server_today() — there is no argument by which a caller could have set a different value (RT-25 closed by the signature)'
);
select is(
  (select generation_status from pfin.monthly_report where report_id = :d8::bigint),
  'draft',
  '(9) the inserted row is `draft` — this function never writes `final`, and 108''s own state fence admits nothing else on INSERT regardless'
);

-- =====================================================================
-- LEG 10 — STANDING: no rolbypassrls role (service_role, by name) holds
-- EXECUTE on this function.
-- =====================================================================
select ok(
  not has_function_privilege('service_role', 'pfin.fn_open_monthly_report_draft(date)'::regprocedure, 'EXECUTE'),
  '(10) service_role holds NO EXECUTE on fn_open_monthly_report_draft'
);

select * from finish();
rollback;
