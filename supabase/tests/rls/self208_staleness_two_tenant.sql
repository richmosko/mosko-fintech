-- =====================================================================
-- Per-Wave battery — pfin.fn_aggregation_has_stale_constituent() INVOKER read primitive
--   (SELF-208 / 046 — §2.4.4.c D1 non-silent staleness markers; ADR-013 Decision 1 "aggregation
--    data is never silently presented as fresh when a contributing connection is unhealthy";
--    RT-13 requesting-tenant-scoped credential-state resolution; V1-SHIP-BLOCK; Sec joint-review
--    rides the SELF-208 surface:plaid RT-13 review)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/046_fn_aggregation_has_stale_constituent.sql
--   pfin.fn_aggregation_has_stale_constituent() RETURNS TABLE(is_stale boolean, stale_items jsonb)
--   — SECURITY INVOKER (prosecdef=f, verified), STABLE, no params. Returns EXACTLY ONE aggregate
--   row for the calling user: is_stale = TRUE iff the caller owns >=1 ACTIVE (is_active=TRUE)
--   linked_source whose connection_status IS DISTINCT FROM 'healthy'; stale_items = jsonb array of
--   {linked_source_id, institution_name, provider, connection_status, status_class} for those
--   sources ('[]' when none). Composes over the 043 pfin.linked_source_connection_state INVOKER
--   view → linked_source RLS (linked_source_select users_id=auth.uid() + the 025 aal2 clause).
--
-- ┌─ ASSERT AGAINST THE FUNCTION DIRECTLY (Sec's explicit note) ───────────────────────────────┐
-- │ Every assertion calls pfin.fn_aggregation_has_stale_constituent() as the tenant — NOT the   │
-- │ 043 view. Rationale: if a future regression flips 043 to owner-BROKEN (or someone rewires   │
-- │ 046 off 043 onto an owner-unscoped source), the isolation break must be caught AT THIS       │
-- │ surface (the primitive the NAV badge actually calls), not only at 043's own battery.         │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (a) CROSS-TENANT, IDENTITY-LEVEL (the load-bearing isolation proof): as A, NO stale_items[]  │
-- │     element is B's source b_login, and the element id-set is EXACTLY A's two active non-      │
-- │     healthy sources {a_login, a_down}. Not a mere is_stale count — an identity assertion that │
-- │     A NEVER surfaces any of B's stale sources. INVERSION (how it goes RED): if 046 read an    │
-- │     owner-unscoped source (or 043 regressed to leak cross-tenant rows), b_login's id would    │
-- │     appear in A's stale_items → A3 (b_login-absent) fails AND A5 (exact {a_login,a_down} set) │
-- │     fails. The (B8/B9) companion proves b_login is a REAL stale source B owns — so A3's       │
-- │     absence is genuine isolation, not a vacuous empty set.                                    │
-- │ (b) is_active SCOPING: a_inactive is a NON-HEALTHY but INACTIVE source → EXCLUDED from        │
-- │     stale_items (A2 length=2, A4 id-absent). Proves constituent-set alignment with the NAV    │
-- │     active-only contract — RED (length=3) if is_active were not scoped. Non-vacuous: the row  │
-- │     exists and IS non-healthy, so its exclusion is a real filter, not an empty set.           │
-- │ (c) ALL-HEALTHY caller (D) → is_stale=FALSE and stale_items = '[]'::jsonb — EXACTLY one row,  │
-- │     empty array (NOT NULL, NOT zero-rows). D10 + D11.                                          │
-- │ (d) aal2 ZEROING: C (mfa_policy=totp) at aal1 → is_stale=FALSE / '[]' (the 043 driving-table  │
-- │     025 clause makes C's sources RLS-invisible → the view is empty → the fn is empty). C12+13. │
-- │     Non-vacuous control C14: the SAME caller at aal2 → is_stale=TRUE (c_login visible) → the   │
-- │     zeroing is aal-driven, not a blanket block of C.                                           │
-- │ (e) PER-ITEM connection_status = authoritative CURRENT health (the badge affordance driver):  │
-- │     a_down's element carries connection_status='institution_down' (A6). status_class MAY be    │
-- │     NULL (context, not driver): a_down has no state_history → its element's status_class is    │
-- │     null and is CARRIED (A7), not dropped.                                                     │
-- │ (f) DEFENCE-IN-DEPTH (PUBLIC EXECUTE safe under INVOKER+RLS): an ANON caller is DENIED at the  │
-- │     pfin schema-USAGE ACL (42501) — F15 (measured: anon lacks USAGE on schema pfin; the PUBLIC │
-- │     EXECUTE on 046 never gets reached → no leak, fail-closed). The faithful "auth.uid() NULL → │
-- │     empty" property is proven by an AUTHENTICATED caller with NO sub claim (auth.uid()=NULL) → │
-- │     is_stale=FALSE / '[]' (F16+F17). NOTE-TO-SEC/ARCH: the 046 header case (f) states an ANON   │
-- │     caller "→ is_stale=false/'[]'"; empirically anon is DENIED at schema USAGE (a hard 42501),  │
-- │     NOT an empty row. The security property (no leak) holds either way; the header's described  │
-- │     shape does not. Flagged as a header-accuracy finding — the ACTUAL empty-row shape is the    │
-- │     no-sub authenticated case (F16/F17), which this battery asserts.                            │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; 046 is an authenticated-tier
--   INVOKER read primitive — no infra-credential, no SUPABASE_SERVICE_ROLE_KEY code-layer (uses NO
--   service_role), no app->worker surface; per the 046 header §10 3-axis, Path B). Decision-3 family
--   UNCHANGED (046 authors NO table / NO FK-shaped column; linked_source_id in the projection is the
--   caller's OWN source id, owner-safe, surfaced from the 043 view). THIS battery is the pgTAP proof
--   of owner-scoping + is_active alignment + the aal2 gate + the aggregate empty-case shape.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a()/_b()/_c() + a fixed
--   tenant-D literal); NO PII / NO real account numbers / NO real credentials (SD-03) / NO prod data.
--   linked_source rows are credential-less (credential_secret_id NULL). All privileged writes are
--   seeded role=postgres with explicit users_id (auth.uid() is NULL under postgres). Rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + source ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant[_aal] is
--   called at role=postgres and each block restores role=postgres before the next. \gset names lower.
--
-- ⟦WIRE-VALIDATE⟧ authored against 046's applied contract (local head=046). RED-until-046-applied is
--   expected on any pre-046 stack (the function would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(17);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
-- Tenant D is the all-healthy caller (no verb needed — a fixed literal, set via _rls.set_tenant).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-00000000000d'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — the sole write path for these tables).
--   A: healthy + login_required(active) + institution_down(active) + login_required(INACTIVE).
--   B: healthy + login_required(active)  [b_login = cross-tenant referent + B non-vacuous].
--   C: login_required(active) + mfa_policy='totp'  [the aal2-gate tenant].
--   D: healthy + healthy (all-healthy caller).  users_id explicit on every row.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td');

-- A's sources.
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'ta', 'plaid', 'conn-a-login', 'Bank A-Login', 'login_required',   true)  returning source_id as a_login \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'ta', 'plaid', 'conn-a-down',  'Bank A-Down',  'institution_down', true)  returning source_id as a_down \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'ta', 'plaid', 'conn-a-ok',    'Bank A-OK',    'healthy',          true)  returning source_id as a_ok \gset
-- a_inactive: NON-HEALTHY but is_active=FALSE → must be EXCLUDED (is_active scoping; non-vacuous).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'ta', 'plaid', 'conn-a-inact', 'Bank A-Inact', 'login_required',   false) returning source_id as a_inactive \gset

-- B's sources (b_login = the cross-tenant referent A must NEVER surface; b non-vacuous companion).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'tb', 'plaid', 'conn-b-login', 'Bank B-Login', 'login_required',   true)  returning source_id as b_login \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'tb', 'plaid', 'conn-b-ok',    'Bank B-OK',    'healthy',          true);

-- C's source + mfa_policy='totp' → C's sources are aal2-gated (025 backstop on linked_source).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'tc', 'plaid', 'conn-c-login', 'Bank C-Login', 'login_required',   true)  returning source_id as c_login \gset
insert into pfin.user_settings (users_id, mfa_policy) values (:'tc', 'totp');

-- D's sources — ALL healthy active (the all-healthy caller → is_stale=false / '[]').
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'td', 'plaid', 'conn-d-ok1', 'Bank D-OK1', 'healthy', true);
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status, is_active)
  values (:'td', 'plaid', 'conn-d-ok2', 'Bank D-OK2', 'healthy', true);

-- =====================================================================
-- BLOCK A (authenticated A; plain set_tenant = aal1, mfa_policy coalesces 'none' → ungated).
--   Cross-tenant identity isolation + is_active exclusion + per-item health/status_class carry.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (A1) is_stale = TRUE — A owns >=1 active non-healthy source.
select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  true,
  '(A1) is_stale=TRUE for A (owns active non-healthy sources a_login + a_down)'
);

-- (A2) is_active SCOPING + active-set alignment: exactly 2 stale items (a_login, a_down) — the
--      INACTIVE non-healthy a_inactive is EXCLUDED. RED (=3) if is_active were not scoped.
select is(
  (select jsonb_array_length(stale_items) from pfin.fn_aggregation_has_stale_constituent()),
  2,
  '(A2) is_active scoping: exactly 2 stale_items (a_login + a_down) — the INACTIVE non-healthy a_inactive is EXCLUDED (RED=3 if is_active unscoped); non-vacuous — a_inactive exists and is non-healthy'
);

-- (A3) LOAD-BEARING cross-tenant identity isolation: B's source b_login NEVER appears in A's items.
--      INVERSION: RED iff a cross-tenant row leaks into stale_items (046 read owner-unscoped / 043 regressed).
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
    where (e->>'linked_source_id')::bigint = :b_login
  ),
  '(A3) LOAD-BEARING cross-tenant identity isolation: A NEVER surfaces B''s stale source b_login (no stale_items[] element has linked_source_id = b_login) — RED iff a cross-tenant row leaks; (B8/B9) prove b_login is a REAL stale source B owns'
);

-- (A4) is_active exclusion, explicit: a_inactive's id is NOT among the stale_items.
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
    where (e->>'linked_source_id')::bigint = :a_inactive
  ),
  '(A4) is_active exclusion: the INACTIVE non-healthy source a_inactive is NOT in stale_items (a suspended source feeds nothing into NAV → flagging it would be a false positive; NOT a D1 violation)'
);

-- (A5) exact identity set: the stale_items id-set = EXACTLY {a_login, a_down} (sorted both sides).
--      Ties (A2) count + (A3) isolation into a single identity-equality — the non-vacuous proof.
select is(
  (
    select array_agg((e->>'linked_source_id')::bigint order by (e->>'linked_source_id')::bigint)
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
  ),
  (select array_agg(x::bigint order by x::bigint) from (values (:a_login), (:a_down)) v(x)),
  '(A5) exact identity set: stale_items id-set = EXACTLY {a_login, a_down} — every surfaced id is owned by A, and both (and only) A''s active non-healthy sources appear'
);

-- (A6) per-item authoritative CURRENT health: a_down's element carries connection_status='institution_down'.
select is(
  (
    select e->>'connection_status'
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
    where (e->>'linked_source_id')::bigint = :a_down
  ),
  'institution_down',
  '(A6) per-item connection_status is the authoritative current-health value (a_down → institution_down) — the badge keys its per-status affordance on THIS (institution_down = informational, not re-auth)'
);

-- (A7) status_class MAY be NULL (context, not driver): a_down has no state_history → element's
--      status_class is null AND the element is CARRIED (not dropped for lack of history).
select ok(
  (
    select (e ? 'status_class') and (e->>'status_class') is null
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
    where (e->>'linked_source_id')::bigint = :a_down
  ),
  '(A7) status_class may be NULL (context): a_down has no state_history → its element carries status_class=null (key present, value null) and is NOT dropped — connection_status, not status_class, drives the affordance'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK B (authenticated B) — non-vacuous companion: B DOES own a real stale source b_login,
--   so (A3)'s absence-of-b_login for A is REAL isolation, not a vacuous empty set.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (B8) B is_stale=TRUE (B owns an active non-healthy source).
select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  true,
  '(B8) is_stale=TRUE for B (owns active non-healthy b_login) — establishes b_login is a genuine stale source'
);

-- (B9) B's stale_items = EXACTLY [b_login] (length 1, the sole id = b_login).
select is(
  (
    select array_agg((e->>'linked_source_id')::bigint)
    from jsonb_array_elements(
      (select stale_items from pfin.fn_aggregation_has_stale_constituent())
    ) e
  ),
  array[:b_login]::bigint[],
  '(B9) non-vacuous companion: B''s OWN stale_items = EXACTLY [b_login] → (A3)''s no-b_login for A is real cross-tenant isolation, not an empty result set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK D (authenticated D, all-healthy) — the unambiguous empty case: exactly one row,
--   is_stale=FALSE, stale_items = '[]'::jsonb (NOT NULL, NOT zero-rows).
-- =====================================================================
select _rls.set_tenant(:'td'::uuid);

-- (D10) all-healthy → is_stale=FALSE.
select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  false,
  '(D10) all-healthy caller D → is_stale=FALSE'
);

-- (D11) all-healthy → stale_items = '[]'::jsonb (empty array, not NULL) — one aggregate row.
select is(
  (select stale_items from pfin.fn_aggregation_has_stale_constituent()),
  '[]'::jsonb,
  '(D11) all-healthy caller D → stale_items = ''[]''::jsonb exactly (empty array, NOT NULL, exactly one row — no client "zero rows = healthy or errored?" ambiguity)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK C (authenticated C, mfa_policy='totp') — aal2 gate INHERITED from the linked_source
--   driving table (025 clause) via the 043 INVOKER view. aal1 → empty; aal2 → visible.
-- =====================================================================

-- (C12) aal2 ZEROING (is_stale): C at aal1 → is_stale=FALSE (the 025 clause makes C's sources
--       RLS-invisible → 043 view empty → the fn's aggregate is empty).
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  false,
  '(C12) aal2 zeroing: a totp caller at aal1 → is_stale=FALSE (the 025 clause on linked_source zeroes the 043 driving view → the fn sees no sources; fail-closed, no staleness asserted for an un-stepped-up caller)'
);

-- (C13) aal2 ZEROING (stale_items): same caller/aal1 → stale_items = '[]'::jsonb.
select is(
  (select stale_items from pfin.fn_aggregation_has_stale_constituent()),
  '[]'::jsonb,
  '(C13) aal2 zeroing: a totp caller at aal1 → stale_items = ''[]''::jsonb (empty, not NULL)'
);
select set_config('role', 'postgres', true);

-- (C14) non-vacuous aal control: the SAME totp caller at aal2 → is_stale=TRUE (c_login visible) →
--       (C12/C13)'s empty is aal-DRIVEN, not a blanket block of tenant C.
select _rls.set_tenant_aal(:'tc'::uuid, 'aal2');
select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  true,
  '(C14) non-vacuous aal control: the SAME totp caller at aal2 → is_stale=TRUE (c_login now visible) → (C12/C13)''s empty is aal-driven (the driving-table 025 gate), not a blanket block of tenant C'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK F — DEFENCE-IN-DEPTH: PUBLIC EXECUTE is safe under INVOKER+RLS.
--   F15: an ANON caller is DENIED at the pfin schema-USAGE ACL (42501) — the PUBLIC EXECUTE on 046
--        is never reached (measured: anon lacks USAGE on schema pfin). Fail-closed, no leak.
--   F16/F17: the faithful "auth.uid() NULL → empty" property via an AUTHENTICATED caller with NO
--        sub claim (auth.uid()=NULL) → is_stale=FALSE / '[]'. (This is the ACTUAL empty-row shape;
--        see the header NOTE — the 046 header attributes it to the anon caller, which is instead
--        denied at schema USAGE.)
-- =====================================================================

-- (F15) anon → DENIED (42501 at schema USAGE). stmt_denied_as sets role=anon, runs the call,
--       returns TRUE iff insufficient_privilege was raised; restores role=postgres.
select ok(
  _rls.stmt_denied_as('anon', 'select 1 from pfin.fn_aggregation_has_stale_constituent()'),
  '(F15) defense-in-depth: an ANON caller is DENIED (42501) at the pfin schema-USAGE ACL — the PUBLIC EXECUTE on 046 is never reached; no leak, fail-closed'
);

-- (F16/F17) authenticated with NO sub claim (auth.uid()=NULL) → empty aggregate row.
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);

select is(
  (select is_stale from pfin.fn_aggregation_has_stale_constituent()),
  false,
  '(F16) auth.uid()=NULL (authenticated, no sub) → is_stale=FALSE (no owned sources resolve; the faithful empty-identity case)'
);
select is(
  (select stale_items from pfin.fn_aggregation_has_stale_constituent()),
  '[]'::jsonb,
  '(F17) auth.uid()=NULL (authenticated, no sub) → stale_items = ''[]''::jsonb (empty, not NULL) — no cross-tenant leak for an identity-less caller'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
