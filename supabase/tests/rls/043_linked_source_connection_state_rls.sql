-- =====================================================================
-- Per-Wave battery — pfin.linked_source_connection_state INVOKER read view
--   (SELF-207 / 043 — §2.4.4.b connection-state view + reactive re-auth banner; ADR-037
--    provider-agnostic linked_source substrate; C6 EXPOSURE-GATING per ADR-023 /
--    SECURITY §4.5; V1-SHIP-BLOCK; Sec joint-review rides the SELF-207 reauth-path review)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/043_linked_source_connection_state.sql
--   - pfin.linked_source_connection_state (security_invoker = true) — one row per caller-owned
--     pfin.linked_source. Projection: linked_source_id · provider · institution_name ·
--     connection_status (healthy|login_required|institution_down|revoked|disconnected) ·
--     status_class (latest state_history transition; same domain; NULL if no history) ·
--     last_successful_sync_at (NULL if never) · is_active. GRANT SELECT to authenticated.
--     (status_detected_at is DELIBERATELY NOT projected — detected_at is used only to ORDER the
--     "latest" transition; additive later if the banner wants a 'since' timestamp.)
--     FROM linked_source ls  LEFT JOIN LATERAL (latest state_history status_class per source)
--     LEFT JOIN (MAX(created_at) over the 040 linked_source_sync_history WHERE
--     transactions_inserted IS NOT NULL).
-- Prereqs exercised (all on main):
--   015 — pfin.linked_source (linked_source_select users_id=auth.uid() + the DRIVING TABLE) +
--         connection_status CHECK + linked_source_state_history (source_id sole anchor; JOIN-scoped
--         SELECT RLS; service_role write / authenticated SELECT) + linked_source_sync_audit
--         (service_role-only, ungranted to authenticated — reached ONLY through the 040 view).
--   040 — pfin.linked_source_sync_history OWNER-SEMANTICS view (security_invoker=false; self-scopes
--         WHERE users_id=auth.uid()); transactions_inserted = detail->'result'->>'transactionsInserted'
--         (NULL when a sync produced no `result` = FAILED). The 043 last-sync derives from THIS.
--   025 — the aal2 backstop clause ANDed into linked_source_select. Because 043 is security_invoker
--         and linked_source is the FROM, this clause gates the WHOLE view: aal1 + mfa_policy in
--         (totp,passkey) → the caller's sources are RLS-invisible → the view returns ZERO rows.
-- Reuses the 040/042 idiom: \ir verbs, ALL-LOWERCASE \gset literals (005 case-fold lesson),
--   role restored to postgres between blocks (PR #121 _rls-USAGE root). The view is read UNDER
--   authenticated so it is proven to compose with RLS (INVOKER), not as a privileged read.
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ────────────────────────┐
-- │ (1)  owner sees exactly its OWN sources (one row per own linked_source) — non-vacuous positive│
-- │      (RED if the view over- or under-scoped the FROM).                                       │
-- │ (2)  cross-tenant: A sees ZERO of B's connections (INVOKER RLS on the driving table) — the    │
-- │      (9) B-sees-b1 companion proves this is real isolation, not an empty result set.          │
-- │ (3)  status_class is the MOST-RECENT state_history transition per source (ORDER BY detected_at │
-- │      DESC, history_id DESC LIMIT 1) — RED if an older transition leaked (the re-auth banner    │
-- │      would show a stale health state).                                                        │
-- │ (4)  LOAD-BEARING last_successful_sync_at EXCLUDES FAILED syncs: a1 has successful syncs at    │
-- │      07-01 + 07-05 and a LATER FAILED sync at 07-09 (NULL transactions_inserted) → last-sync   │
-- │      = 07-05, NOT 07-09. RED if the definition counted failed syncs (a broken connection would │
-- │      look freshly synced — the exact staleness bug §2.4.4 fences).                            │
-- │ (5)/(6) LEFT-JOIN + failed-only: a2 has NO history and ONLY a FAILED sync → its row is PRESENT │
-- │      (not dropped) with status_class NULL AND last_successful_sync_at NULL — RED if the joins  │
-- │      were INNER (a never-successfully-synced source would vanish from the banner list).        │
-- │ (7)/(8) re-auth predicate set surfaces faithfully: the three re-auth-trigger statuses          │
-- │      (login_required/revoked/disconnected) are projected as-is (banner shows), and             │
-- │      institution_down is surfaced DISTINCTLY (transient — banner excludes it). RED if          │
-- │      connection_status were mis-projected → the provider-blind banner predicate would misfire. │
-- │ (10)/(11) aal2 gate via the driving table: an aal1 caller with mfa_policy=totp reads ZERO rows;│
-- │      at aal2 the SAME caller reads its source — proving (10) is aal-driven (the 025 clause on   │
-- │      linked_source gates the whole INVOKER view), not a blanket block.                         │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27; 043 is an authenticated-tier
--   INVOKER read view — no infra-credential, no SUPABASE_SERVICE_ROLE_KEY code-layer (it reads the
--   040 owner-semantics view, whose service_role-only base access is the 040 mechanism, not new),
--   no app->worker surface; per the 043 header §10 3-axis, Path B). Decision-3 family UNCHANGED
--   (043 authors NO table / NO FK-shaped column; linked_source_id in the projection is the caller's
--   OWN source id). THIS battery is the pgTAP proof of owner-scoping + the aal2 gate + the derived-
--   column semantics (per the 043 header QA TEST-PAIRING; Sec joint-review rides SELF-207 reauth).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c(); NO
--   PII / NO real account numbers / NO real credentials (SD-03) / NO prod data. linked_source rows
--   carry credential_secret_id NULL (credential-less → no Vault secret). sync_audit detail blobs are
--   hand-authored count-key jsonb (no real provider payload). All privileged writes (linked_source /
--   state_history / sync_audit have no authenticated write path — Decision 1) are seeded role=postgres
--   with explicit users_id (auth.uid() is NULL under postgres). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated. Tenant UUIDs
--   + source ids resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant[_aal] is
--   called at role=postgres and each block restores role=postgres before the next. \gset var names
--   are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 043's firmed (post-alignment: status_class rename + status_detected_at
--   dropped) contract; the authoritative run is the 001->043 reset stack. RED-until-043-applied is
--   expected on any pre-043 stack (the view would not exist).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(11);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — the sole write path for these tables).
--   A owns 5 sources spanning the connection_status domain (a1 rich: history + syncs; a2
--   failed-only sync + no history; a3/a4/a5 the remaining status values). B owns b1 (cross-
--   tenant). C owns c1 + declares mfa_policy='totp' (the aal2-gate tenant). users_id explicit.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- A's sources (credential-less; connection_status spans the domain).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'conn-a1', 'Bank A1', 'login_required') returning source_id as a1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'conn-a2', 'Bank A2', 'healthy')        returning source_id as a2 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'conn-a3', 'Bank A3', 'institution_down') returning source_id as a3 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'conn-a4', 'Bank A4', 'revoked')        returning source_id as a4 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'conn-a5', 'Bank A5', 'disconnected')   returning source_id as a5 \gset

-- B's source (cross-tenant referent) + C's source (aal2-gate referent).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'tb', 'plaid', 'conn-b1', 'Bank B1', 'login_required') returning source_id as b1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'tc', 'plaid', 'conn-c1', 'Bank C1', 'healthy')        returning source_id as c1 \gset

-- a1 state-history: an OLDER 'healthy' transition then a NEWER 'login_required' one. The view
-- must surface the NEWER (latest) transition (ORDER BY detected_at DESC, history_id DESC).
insert into pfin.linked_source_state_history (source_id, status_class, detected_at)
  values (:a1, 'healthy', '2026-06-01T00:00:00Z');
insert into pfin.linked_source_state_history (source_id, status_class, detected_at)
  values (:a1, 'login_required', '2026-07-10T00:00:00Z');

-- a1 sync-audit: two SUCCESSFUL syncs (07-01, 07-05; detail carries result.transactionsInserted)
-- and a LATER FAILED sync (07-09; detail has NO `result` → transactions_inserted NULL). The
-- derived last_successful_sync_at must be 07-05 (latest SUCCESSFUL), NOT the later failed 07-09.
-- NOTE (044): linked_source_id is REQUIRED — the 040 sync-history view now joins on the stable
-- linked_source_id (was the (provider, external_connection_id) digest), matching the post-044 worker
-- writeAudit behavior. Without it these rows would be excluded from the id-joined view (the ripple
-- 044 introduces for every sync_audit-seeding fixture).
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', 'conn-a1', '{"result": {"transactionsInserted": 10}}'::jsonb, '2026-07-01T00:00:00Z', :a1);
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', 'conn-a1', '{"result": {"transactionsInserted": 20}}'::jsonb, '2026-07-05T00:00:00Z', :a1);
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', 'conn-a1', '{"ok": false}'::jsonb, '2026-07-09T00:00:00Z', :a1);

-- a2 sync-audit: ONLY a FAILED sync (no history either) → last_successful_sync_at must be NULL AND
-- the row must still appear (LEFT JOIN, never dropped). linked_source_id=a2 so the row IS in the
-- id-joined 040 view (non-vacuous: failed-excluded even when present), yet excluded from last-sync.
insert into pfin.linked_source_sync_audit (provider, source, users_id, external_connection_id, detail, created_at, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', 'conn-a2', '{"ok": false}'::jsonb, '2026-07-03T00:00:00Z', :a2);

-- C declares MFA policy 'totp' → the 025 backstop makes C's sources aal2-gated.
insert into pfin.user_settings (users_id, mfa_policy) values (:'tc', 'totp');

-- =====================================================================
-- BLOCK 1 (authenticated A; plain set_tenant = aal1, mfa_policy coalesces to 'none' -> ungated)
--   Owner scoping + cross-tenant isolation + latest-transition + failed-sync exclusion +
--   LEFT-JOIN presence + re-auth predicate projection.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1) owner sees exactly its 5 OWN sources (one row per own linked_source).
select is(
  (select count(*) from pfin.linked_source_connection_state)::bigint,
  5::bigint,
  '(1) owner scoping: A sees exactly 5 rows — one per A-owned linked_source (the INVOKER view scopes the FROM to the caller''s own sources)'
);

-- (2) cross-tenant isolation: A sees ZERO of B's connections (b1 is RLS-invisible to A).
select is(
  (select count(*) from pfin.linked_source_connection_state where linked_source_id = :b1)::bigint,
  0::bigint,
  '(2) cross-tenant isolation: A sees ZERO rows for B''s source b1 (linked_source_select RLS via the INVOKER view; the (9) B-sees-b1 companion proves this is real isolation, not an empty view)'
);

-- (3) status_class is the MOST-RECENT transition for a1 (login_required @ 07-10, NOT the older
--     healthy @ 06-01). detected_at is not projected — it only orders "latest".
select is(
  (select status_class from pfin.linked_source_connection_state where linked_source_id = :a1),
  'login_required',
  '(3) latest transition: a1''s status_class = ''login_required'' (the 07-10 row), NOT the older ''healthy'' 06-01 row — the LATERAL LIMIT 1 (ORDER BY detected_at DESC, history_id DESC) surfaces the most-recent state_history transition'
);

-- (4) LOAD-BEARING failed-sync exclusion: a1 last_successful_sync_at = 07-05 (latest SUCCESSFUL),
--     NOT the LATER FAILED sync at 07-09.
select is(
  (select last_successful_sync_at::date from pfin.linked_source_connection_state where linked_source_id = :a1),
  '2026-07-05'::date,
  '(4) LOAD-BEARING failed-sync exclusion: a1''s last_successful_sync_at = 2026-07-05 (latest SUCCESSFUL), NOT the later FAILED 2026-07-09 (NULL transactions_inserted) — RED if the derivation counted failed syncs (a broken connection would look freshly synced)'
);

-- (5) LEFT-JOIN presence: a2 (no history, failed-only sync) is PRESENT with status_class NULL.
select ok(
  exists (select 1 from pfin.linked_source_connection_state where linked_source_id = :a2)
    and (select status_class from pfin.linked_source_connection_state where linked_source_id = :a2) is null,
  '(5) LEFT-JOIN presence: a2 (no state_history) is PRESENT in the view with status_class NULL — the row is not dropped (RED if the state_history join were INNER)'
);

-- (6) failed-only → NULL last-sync: a2 has ONLY a failed sync → last_successful_sync_at is NULL AND
--     the row still appears (proves a failed sync never advances last-sync, even as the sole audit row).
select ok(
  (select last_successful_sync_at from pfin.linked_source_connection_state where linked_source_id = :a2) is null,
  '(6) failed-only → NULL: a2 has ONLY a FAILED sync (NULL transactions_inserted) → last_successful_sync_at is NULL, and the row still appears (LEFT JOIN) — a never-successfully-synced source is not dropped'
);

-- (7) re-auth predicate set: the three re-auth-trigger statuses surface faithfully (a1
--     login_required, a4 revoked, a5 disconnected) → count = 3.
select is(
  (select count(*) from pfin.linked_source_connection_state
     where connection_status in ('login_required', 'revoked', 'disconnected'))::bigint,
  3::bigint,
  '(7) re-auth predicate set: connection_status is projected faithfully for the 3 re-auth-trigger states (login_required/revoked/disconnected = a1/a4/a5) — the provider-blind banner reads exactly this predicate'
);

-- (8) institution_down surfaced DISTINCTLY (transient — the banner EXCLUDES it from re-auth).
select is(
  (select count(*) from pfin.linked_source_connection_state where connection_status = 'institution_down')::bigint,
  1::bigint,
  '(8) transient status distinct: institution_down (a3) is surfaced as its own value (1 row) — NOT collapsed into the re-auth set; the banner shows it as transient, not a re-auth trigger'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated B) — non-vacuous cross-tenant companion: B DOES see its OWN b1, so (2)'s
--   ZERO for A is real isolation, not an empty view.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (9) B sees its OWN b1 (exactly one row) — the non-vacuous companion to (2).
select is(
  (select count(*) from pfin.linked_source_connection_state where linked_source_id = :b1)::bigint,
  1::bigint,
  '(9) non-vacuous companion: B DOES see its OWN source b1 (1 row) → (2)''s ZERO for A is real cross-tenant isolation, not an empty result set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated C, mfa_policy='totp') — the aal2 gate INHERITED from the linked_source
--   driving table. aal1 → ZERO rows; aal2 → the source is visible (aal-driven, not a blanket block).
-- =====================================================================

-- (10) LOAD-BEARING aal2 gate: C at aal1 (mfa_policy=totp) reads ZERO rows — its sources are
--      RLS-invisible via the 025 clause on linked_source, so the whole INVOKER view is empty.
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select is(
  (select count(*) from pfin.linked_source_connection_state)::bigint,
  0::bigint,
  '(10) LOAD-BEARING aal2 gate: a totp caller at aal1 reads ZERO rows from the view (the 025 clause on the linked_source driving table makes its sources RLS-invisible → the INVOKER view is empty; fail-closed)'
);
select set_config('role', 'postgres', true);

-- (11) non-vacuous aal control: the SAME caller at aal2 sees its source c1 (1 row) → (10) is
--      aal-driven, not a blanket block of tenant C.
select _rls.set_tenant_aal(:'tc'::uuid, 'aal2');
select is(
  (select count(*) from pfin.linked_source_connection_state where linked_source_id = :c1)::bigint,
  1::bigint,
  '(11) non-vacuous aal control: the SAME totp caller at aal2 sees its OWN source c1 (1 row) → (10)''s ZERO is aal-driven (the driving-table 025 gate), not a blanket block of tenant C'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
