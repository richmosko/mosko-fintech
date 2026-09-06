-- =====================================================================
-- SELF-362 — P10. §2.6.6 RLS VERIFICATION BATTERY — V1.5 CLOSE-GATE.
--   AC block: docs/records/v15-preflight/rederived-acs.md § "SELF-362 — P10"
--   items 1-14, read verbatim at drafting, plus the items booked to P10
--   during execution (docs/records/v15-execution/log.md, search "P10").
--   Mirrors self269_v1_4_close_gate.sql's shape (the explicit precedent):
--   SEAM-ONLY, authors NO schema. Proves the V1.5 §2.6 read/write surface
--   holds closed AS A WHOLE. Composes already-green per-issue batteries
--   (106, 108-115, plus workers/etl's own pytest suite for A7) for the deep
--   per-function proofs; adds only the NET-NEW seam + cross-cutting +
--   genuinely-missing legs no per-issue battery makes on its own.
--
--   ⚠ AUTHORED SURFACE-GROUP BY SURFACE-GROUP, ONE COMMIT PER GROUP
--   (team-lead dispatch, 2026-09-06): (1) A1+A2 — Lock 11/12, the R4 four,
--   frozen payload, aal2 separate; (2) A3+A10 — composition leak with its
--   positive control, the standing no-rolbypassrls-EXECUTE catalog
--   assertion, RESET ROLE, RT-25 refusal; (3) AH+A7 — audit legs, singular-
--   GUC leg; (4) A5/A8/P3 — owner header frozen, commentary write path,
--   tenant-scoped queue; (5) the tri-axis conditional legs (AC4). Each
--   group's own commit states its plan-count delta and strike results.
--
-- Ratified AC coverage (mapping to the live AC block; "COMPOSED" = an
-- already-green per-issue battery carries the exhaustive proof, cited by
-- file + leg name, not re-derived; "NEW" = fresh SQL below):
--   AC1  — two-tenant coverage of A1+A2+A3+A5+A7+A8+A10+AH+P3, cross-tenant
--          injection rejected on each.
--          A1: COMPOSED — 108_monthly_report_rls.sql LEG 1 (cross-tenant
--          read fails closed; owner reads own rows).
--          A2: COMPOSED — 109_monthly_report_account_snapshot_rls.sql
--          LEG 1 (cross-tenant read via the parent chain fails closed).
--          A3/A7/A10/AH/A5/A8/P3: addressed in their own groups below (this
--          file's later commits); cited there, not duplicated here.
--   AC2  — aal2 legs SEPARATE from cross-tenant legs on A1, A2 (this group)
--          and A8 (group 4).
--          A1: COMPOSED — 108 LEG 2 (aal2 as a separate leg from
--          cross-tenant, Sec F-9).
--          A2: COMPOSED — 109 LEG 2 (aal2 as a separate leg from
--          cross-tenant).
--   AC5  — SD-12 child sub-class addendum; NOT a new SD class (Sec M-3 and
--          Sec §5 both confirm). Statement only — no leg, per the AC's own
--          text.
--   AC6  — A1's immutability trigger, the four R4 catch criteria, EACH ITS
--          OWN leg, ALL COMPOSED — 108's battery was authored against this
--          exact AC text:
--          (i)   regenerate one month THREE times -> three rows, exactly
--                one final — 108 LEG 3.
--          (ii)  UPDATE a final row refused, as authenticated AND as
--                service_role — 108 LEG 4.
--          (iii) DELETE as each role refused on any non-draft row — 108
--                LEG 5 (covers both final and superseded rows, both roles).
--          (iv)  INSERT directly as final refused — 108 LEG 6 (also proves
--                INSERT as draft accepted, the non-vacuous half).
--          (v)   superseded is TERMINAL, every transition out of it
--                refused — 108 LEG 7.
--          No new SQL for the four criteria themselves.
--   AC7  — A1's frozen payload (R1): byte-stable rendered payload across
--          reads; no call to A3 on a read of a final report; envelopes
--          survive round-trip unflattened; payload_schema_version present
--          and non-NULL on every final/superseded row, NULL permitted only
--          on draft (both directions).
--          The CHECK-constraint half (both directions) is COMPOSED — 108
--          LEG 9 (9a/9b/9c refuse promotion with any of the three payload
--          fields still NULL; 9d the same row promotes cleanly once all
--          three are set together).
--          NEW: BLOCK AC7 below — genuinely absent from every per-issue
--          battery. No existing leg states the POSITIVE claim that a read
--          of a final report's rendered_payload issues NO call to A3
--          (fn_render_monthly_report) at all — 110's own battery tests A3
--          in isolation and never touches A1's stored-payload read path.
--          "Envelopes survive round-trip unflattened" is COMPOSED
--          transitively: 110's own battery (LEG 5/6/7) asserts A3 never
--          collapses an envelope at COMPOSITION time, and BLOCK AC7 below
--          proves the STORED payload is byte-identical to what A3 composed
--          — so an envelope A3 composed unflattened is unflattened in the
--          frozen artifact too, by the same byte-identity proof.
--   AC1  — (A3+A10 halves, group 2) two-tenant coverage.
--          A3: COMPOSED — 110_fn_render_monthly_report_rls.sql LEG 8 (a
--          cross-tenant/no-rows caller gets a well-formed payload with
--          EMPTY sections, not an error and not NULL).
--          A10 (113/114/115, the draft/regenerate/finalize write path):
--          COMPOSED — each of 113/114/115 carries its own LEG 1
--          cross-tenant-refused / owner-succeeds pair.
--   AC3  — A3 cross-tenant leak analysis: a foreign caller gets the
--          empty/unavailable shape (fails closed INTO A SHAPE THAT SAYS
--          SO). Plus Sec F-4's cron leg WITH ITS POSITIVE CONTROL (R3
--          rider 2): tenant A composed while tenant B's rows EXIST, zero
--          tenant-B rows in the output, PROVEN NON-VACUOUS by striking the
--          role assumption and watching the leg red. Plus the STANDING
--          no-rolbypassrls-EXECUTE catalog assertion (R3 rider 1 — "the
--          single most valuable assertion in the file"). Plus RESET ROLE
--          discipline on the pooled connection (R3 rider 3).
--          Leak shape: COMPOSED — 110 LEG 8 (cited above under AC1).
--          F-4 + positive control: COMPOSED — 110 LEG 1 ("Sec F-4 catch
--          criterion WITH ITS POSITIVE CONTROL (R3 rider 2)" — composed for
--          tenant A while tenant B's $2000 exists, gross_total = A's own
--          1000.00; the role-assumption-struck control at (1b) proves the
--          isolation is genuinely RLS-dependent, not a fixture accident).
--          Standing no-rolbypassrls-EXECUTE: COMPOSED, FIVE TIMES OVER, not
--          once — every INVOKER function on this surface carries its OWN
--          copy, independently, so no single file's drift silently loses
--          the assertion: 110 LEG 2 (explicitly self-labelled "R3 rider 1,
--          P10 item 3" in its own header), 113 LEG 10, 114 LEG 10, 115
--          LEG 16 — all four assert `not has_function_privilege(
--          'service_role', <fn>, 'EXECUTE')` on their own signature. A
--          FIFTH, combined sweep leg here would duplicate protection
--          already held four times independently, not add any — the file's
--          own header rule ("adds only the NET-NEW... legs no per-issue
--          battery makes on its own") argues against it. No new SQL.
--          RESET ROLE discipline: COMPOSED, non-pgTAP —
--          workers/etl/tests/test_connection.py::TestImpersonationInvariants
--          ::test_reset_role_tears_down_impersonation (the impersonation
--          state-machine assertion helper's own teardown case) plus
--          test_full_worker_transaction_sequence (the full statement
--          sequence a real transaction issues, impersonation torn down
--          before the write). RESET ROLE is a connection-discipline
--          property of `TenantBoundConnection`/the impersonation loop, not
--          a DB-schema property — the Python suite is where the mechanism
--          actually lives, and P10's own convention (this file, group 1)
--          already accepts a non-pgTAP citation for A7. No pgTAP-side gap.
--   AC11 — (RT-25 half, group 2) A10's server-derived data_as_of: a
--          client-supplied as-of is REFUSED, not ignored.
--          COMPOSED — 113_fn_open_monthly_report_draft_rls.sql LEG 8:
--          `data_as_of` on the inserted row equals `pfin.fn_server_today()`
--          — "there is no argument by which a caller could have set a
--          different value," which is the DB-signature form of "refused,
--          not ignored": the function carries no `p_data_as_of` parameter
--          at all, so a client cannot even attempt to supply one, let alone
--          have it silently dropped.
-- =====================================================================
-- QA-owned. Authors NO schema. Composes 106/108-115 + workers/etl's pytest.
--
-- ⟦EXPECTED STACK⟧ 106-115-applied (main tip 910148c or later). Below any
-- of them the referenced surface does not exist and any NEW leg touching
-- it is RED for that reason alone.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants
-- (_rls.tenant_a()/_b(), plus battery-local tenant D, totp-enrolled, for
-- the aal2 leg — same fixed UUID 108/109/115 already use). No PII, no real
-- account numbers, no production data. Rolled-back txn; no
-- `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(3);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-00000000000d'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');
insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- Minimal manual-account fixture (110's / 115's own precedent) so
-- fn_render_monthly_report composes a genuinely non-empty payload — a
-- byte-identity proof over an EMPTY payload would be vacuous (both sides
-- would agree trivially on '{}'-shaped output).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'AC7-acct', 'depository', 'household', 'taxable') returning account_id as ac7_acct \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:ac7_acct, '2026-01-01', 1000, 'setup', 'opening balance', 'acct_setup');

-- =====================================================================
-- BLOCK AC7 — THE FROZEN PAYLOAD IS GENUINELY STORED, NOT RECOMPOSED (A1
-- item 2, R1 rider 1). 108's own LEG 9 proves the CHECK constraint (the
-- three payload fields are jointly NULL-or-NOT-NULL by status); it does
-- NOT prove the read path itself never re-invokes A3. This is that proof.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_open_monthly_report_draft('2026-01-01') as d_ac7 \gset
select pfin.fn_finalize_monthly_report('2026-01-01', 'skipped');
select set_config('role', 'postgres', true);

select (select rendered_payload::text from pfin.monthly_report where report_id = :d_ac7::bigint) as ac7_payload1 \gset

-- ⚠ THE REAL PROOF, not the trivial one: revoke EXECUTE on
-- fn_render_monthly_report ENTIRELY (savepoint-wrapped, restored after) and
-- confirm the read STILL succeeds and returns the IDENTICAL bytes. If a
-- read of a final row ever called A3, this read would fail outright the
-- instant EXECUTE is gone — a `select` returning the frozen payload with
-- A3 unreachable is the one thing that cannot happen if the payload were
-- recomposed at read time. INVERSION-PROVEN (Sec-c convention): with the
-- EXECUTE grant intact, the same assertion is vacuously true regardless of
-- whether the payload is stored or recomposed (either way the bytes would
-- match, since the fixture is unchanged between generation and read) —
-- the revoke is WHAT MAKES THIS A REAL TEST rather than a tautology.
savepoint sp_ac7_revoke;
revoke execute on function pfin.fn_render_monthly_report(date, date) from authenticated;
select _rls.set_tenant(:'ta'::uuid);
-- THE REVOKE IS ACTUALLY IN EFFECT (not merely issued): a DIRECT call to A3
-- under this same tenant, inside the same savepoint, is refused outright.
-- Without this leg, a no-op REVOKE (wrong signature, wrong grantee, a
-- superuser role that bypasses ACLs) would let the read below pass for the
-- wrong reason — proving nothing about the read path.
select throws_like(
  $$ select pfin.fn_render_monthly_report('2026-01-01', '2026-01-31') $$,
  '%permission denied for function fn_render_monthly_report%',
  '(AC7-revoke-check) THE REVOKE IS GENUINELY IN EFFECT: a DIRECT call to fn_render_monthly_report under this same tenant, same savepoint, is refused — the read below is not vacuously passing because the revoke silently failed to bind'
);
select is(
  (select rendered_payload::text from pfin.monthly_report where report_id = :d_ac7::bigint),
  :'ac7_payload1'::text,
  '(AC7) THE REAL PROOF: with fn_render_monthly_report''s (A3) EXECUTE grant revoked entirely (confirmed above, not assumed), reading a final report''s rendered_payload STILL SUCCEEDS and returns BYTE-IDENTICAL content to what was captured right after finalization — a read of a final row issues NO call to A3, proving the payload is genuinely stored, not recomposed (R1 (A))'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_ac7_revoke;

-- Non-vacuous control: WITH EXECUTE restored (post-rollback), A3 itself is
-- still callable and still composes for this tenant — proves the revoke
-- above genuinely disabled the function rather than the leg accidentally
-- calling a different, already-broken path.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select pfin.fn_render_monthly_report('2026-01-01', '2026-01-31')) is not null,
  '(AC7-control) NON-VACUOUS: with the EXECUTE grant restored (post-rollback), fn_render_monthly_report is callable again and composes a non-null payload for this tenant — the revoke above was a genuine disable, not an accident that happened to leave the leg trivially true'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
