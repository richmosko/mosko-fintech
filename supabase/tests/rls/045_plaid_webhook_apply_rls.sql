-- =====================================================================
-- Per-Wave battery — SELF-206 §2.4.4.a Plaid webhook DB surface (Route Z-INVOKER)
--   (fn_plaid_webhook_resolve read-only pre-flight + fn_plaid_webhook_commit atomic write +
--    pfin.linked_source.sync_cursor A3 column; V1-SHIP-BLOCK; Sec joint-review-mandatory —
--    external-API webhook write path + RT-05 composition + ADR-011 Decision 1 privileged-
--    context-write + Decision 2 immutable audit-class + Decision 3 #15 consumed + Lock 11 INVOKER)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/045_plaid_webhook_apply.sql
--   - pfin.fn_plaid_webhook_resolve(p_event jsonb) → (resolved, already_processed,
--     should_trigger_sync, source_id, users_id). SECURITY INVOKER, STABLE, read-only. Resolves
--     tenant FROM p_event->>'item_id' (pfin.linked_source WHERE provider='plaid'); fail-closed
--     resolved=false on unknown Item; already_processed = STATE-path exact-JWT replay pre-check
--     (NULL id → false); should_trigger_sync = is_transactions_event (NOT id-gated).
--   - pfin.fn_plaid_webhook_commit(p_event jsonb) → (committed, was_fresh). SECURITY INVOKER,
--     VOLATILE. ONE txn: re-resolve tenant from Item id (RAISE if gone; RAISE on NULL
--     provider_event_id for a STATE event only) → state_history append + connection_status flip
--     ONLY-ON-CHANGE → INSERT linked_source_sync_audit gate/audit row (provider='plaid',
--     source='webhook', ON CONFLICT (provider_event_id) DO NOTHING; linked_source_id re-resolved
--     → the 044 #15 matched-tenant fence validates). was_fresh = row freshly inserted.
--   - pfin.linked_source.sync_cursor text — A3 typed incremental-sync cursor; NOT granted to
--     authenticated (REVOKE); service_role reads/advances it. users_id sole anchor → D3-neutral.
-- Prereqs exercised (all on main): 015 (linked_source + connection_status 5-value CHECK +
--   linked_source_state_history + linked_source_sync_audit + provider_event_id UNIQUE gate +
--   the service_role full-table grants), 044 (linked_source_sync_audit.linked_source_id + the
--   #15 fn_sync_audit_matched_linked_source BEFORE-INSERT matched-tenant fence).
-- Reuses the 040/042/043/044 idiom: \ir verbs, role restored to postgres between excursions,
--   \gset var names lowercase. The RPCs are service_role-only in prod but called here PRIVILEGED
--   (role=postgres, superuser holds EXECUTE + BYPASSRLS) — their tenant binding is resolved FROM
--   the Item id, so it is role-independent; that binding is exactly what this battery proves.
--
-- ┌─ WHAT THIS BATTERY PROVES (each assertion guards a REAL violation) ─────────────────────────┐
-- │ (1)-(3)  UNKNOWN/FOREIGN Item → resolve=false + ZERO writes (fail-closed; C-X2 side-effect-  │
-- │          free resolve). No cross-tenant write for an Item we do not own.                       │
-- │ (4)-(12) OVER-DEDUP GUARD (money-flow, CRITICAL): two DISTINCT same-wall-clock-second          │
-- │          transactions deliveries (byte-identical body → the handler's content-hash id would   │
-- │          collide) carry NULL provider_event_id and BOTH land an audit row + BOTH keep          │
-- │          should_trigger_sync=true. (9)/(10) are the TEETH — a regression to id-gating the      │
-- │          transactions path would drop the 2nd delivery = SILENT money-flow data loss. RED if   │
-- │          the sync decision were gated on the id or the NULLs false-collided on the UNIQUE index.│
-- │ (13)-(22) STATE PATH: UNDER-DEDUP (exact-JWT replay of a STATE event → suppressed, was_fresh=  │
-- │          false, exactly ONE audit row, already_processed short-circuit) + ONLY-ON-CHANGE state │
-- │          (a same-status replay adds NO new state_history row; a real status change DOES — the  │
-- │          (21) companion proves (20) is real, not a blanket no-write).                          │
-- │ (23)     AC2: a NULL provider_event_id on a STATE (non-transactions) event → RPC-2 RAISES.     │
-- │ (24)-(28) TWO-TENANT ISOLATION (AC8): a webhook naming tenant A's Item with a FORGED users_id  │
-- │          for tenant B can NEVER write tenant B — tenant is resolved FROM the Item id inside the │
-- │          fn; the forged key is IGNORED. The audit row lands under A; B's linked_source /        │
-- │          _state_history / _sync_audit are UNTOUCHED. (28) companion proves A DID get the write. │
-- │ (29)-(32) CURSOR ACL: authenticated CANNOT read or write sync_cursor via the Data API surface  │
-- │          (column-level denial, fail-closed); service_role CAN (non-vacuous companion).         │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22/RT-26/RT-27 — 045 authors app-callable DB
--   RPCs + a plain text column; no infra-credential, no service_role code-layer reference, no
--   app→worker network surface; per the 045 header §10 3-axis, Path B). Decision-3 family +0
--   (stays 15 labeled / 13 DDL-realized): 045 CONSUMES the 044 #15 fence (does not add an
--   instance); sync_cursor is text, not a reference → D3-neutral. Verify live counts against
--   ADR-011 Decision 3 + Decision 4 at joint-review (Sec joint-review-mandatory).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO real Plaid access tokens (SD-03) / NO prod data. Item ids +
--   provider_event_ids are readable synthetic strings. sync_audit/state_history are service_role-
--   only (no authenticated write path) — seeded + exercised PRIVILEGED (role=postgres). All in a
--   rolled-back txn.
--
-- ⟦WIRE-VALIDATE⟧ authored against 045's firmed contract; the authoritative run is the 001→045
--   reset stack. RED-until-045-applied is expected on any pre-045 stack (the RPCs/column absent).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(35);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — the sole write path for these tables).
--   Tenant A owns FOUR decoupled plaid sources (so state-mutating tests do not couple):
--     item-a-txn   (transactions OVER-dedup)   item-a-state (STATE dedup + only-on-change)
--     item-a-iso   (two-tenant isolation target)
--   Tenant B owns item-b (the isolation victim). All start connection_status='healthy'.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'item-a-txn',   'Bank A', 'healthy') returning source_id as a_txn   \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'item-a-state', 'Bank A', 'healthy') returning source_id as a_state \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'ta', 'plaid', 'item-a-iso',   'Bank A', 'healthy') returning source_id as a_iso   \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name, connection_status)
  values (:'tb', 'plaid', 'item-b',       'Bank B', 'healthy') returning source_id as b_src   \gset

-- =====================================================================
-- BLOCK A — UNKNOWN / FOREIGN Item: resolve fails closed, writes nothing (C-X2 side-effect-free).
-- =====================================================================

-- (1) unknown Item → resolved=false (the handler acks-and-drops; no tenant is resolvable).
select is(
  (select resolved from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-nonexistent","is_transactions_event":true}'::jsonb)),
  false,
  '(1) unknown/foreign Item → fn_plaid_webhook_resolve returns resolved=false (fail-closed)'
);

-- (2) unknown Item → should_trigger_sync=false (no sync fired for an Item we do not own).
select is(
  (select should_trigger_sync from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-nonexistent","is_transactions_event":true}'::jsonb)),
  false,
  '(2) unknown Item → should_trigger_sync=false (no external sync fired for an unresolved Item)'
);

-- (3) resolve is SIDE-EFFECT-FREE (C-X2): repeated resolves of the unknown Item write NOTHING.
select is(
  (select count(*) from pfin.linked_source_sync_audit
     where external_connection_id = 'item-nonexistent')::bigint,
  0::bigint,
  '(3) C-X2 side-effect-free: two resolves of an unknown Item leave ZERO sync_audit rows (a pure re-runnable SELECT — Plaid''s at-least-once retry re-drives safely)'
);

-- =====================================================================
-- BLOCK B — OVER-DEDUP GUARD (transactions path; money-flow CRITICAL). Two DISTINCT same-second
--   transactions deliveries carry NULL provider_event_id → BOTH resolve to should_trigger_sync=true
--   and BOTH land an audit row. The core hazard the 045 design closes.
-- =====================================================================

-- (4) transactions event (A's item) → resolved=true.
select is(
  (select resolved from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true}'::jsonb)),
  true,
  '(4) resolved transactions event (A''s item) → resolved=true'
);

-- (5) transactions event → should_trigger_sync=true (the money-path sync fires on every delivery).
select is(
  (select should_trigger_sync from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true}'::jsonb)),
  true,
  '(5) transactions event → should_trigger_sync=true (fires the external sync — NOT id-gated)'
);

-- (6) transactions event carries NULL id → already_processed=false (never id-deduped).
select is(
  (select already_processed from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true}'::jsonb)),
  false,
  '(6) transactions event (NULL provider_event_id) → already_processed=false (the id-gate is RESERVED for the STATE path; a NULL id never dedups)'
);

-- (7) COMMIT #1 (NULL id, byte-identical body) → was_fresh=true (lands).
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true,"status_class":null,"event_type":"TRANSACTIONS.SYNC_UPDATES_AVAILABLE","sync_outcome":{"ok":true}}'::jsonb)),
  true,
  '(7) OVER-dedup: commit transactions #1 (NULL id) → was_fresh=true (audit row lands)'
);

-- (8) COMMIT #2 — a DISTINCT same-second delivery, byte-identical body, NULL id → ALSO was_fresh=true.
--     A regression to id-gating (content-hash id → same-iat-second collision) would drop this.
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true,"status_class":null,"event_type":"TRANSACTIONS.SYNC_UPDATES_AVAILABLE","sync_outcome":{"ok":true}}'::jsonb)),
  true,
  '(8) OVER-dedup TEETH: a 2nd DISTINCT same-second transactions delivery (byte-identical body, NULL id) → was_fresh=true (NOT falsely id-deduped; RED under any id-gating regression that would drop it = silent money-flow data loss)'
);

-- (9) TEETH: BOTH transactions deliveries landed → 2 audit rows for item-a-txn.
select is(
  (select count(*) from pfin.linked_source_sync_audit
     where external_connection_id = 'item-a-txn')::bigint,
  2::bigint,
  '(9) OVER-dedup TEETH: both same-second transactions deliveries landed an audit row (2 rows) — no false-collision drop'
);

-- (10) NULLs distinct in the UNIQUE index → both transactions rows carry NULL provider_event_id + coexist.
select is(
  (select count(*) from pfin.linked_source_sync_audit
     where external_connection_id = 'item-a-txn' and provider_event_id is null)::bigint,
  2::bigint,
  '(10) NULL-id transactions audit rows coexist: 2 rows with NULL provider_event_id (NULLs distinct in the UNIQUE index — no false collision, no dedup)'
);

-- (11) even AFTER rows exist, a resolved transactions event still fires the sync (never id-gated).
select is(
  (select should_trigger_sync from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-txn","provider_event_id":null,"is_transactions_event":true}'::jsonb)),
  true,
  '(11) resolve NEVER returns should_trigger_sync=false for a resolved transactions event on account of the id-gate (still true after audit rows exist)'
);

-- (12) a pure transactions event (NULL status_class) writes NO state_history row.
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_txn)::bigint,
  0::bigint,
  '(12) pure transactions event (NULL status_class) → NO state_history write (no health change)'
);

-- =====================================================================
-- BLOCK C/E — STATE PATH: UNDER-DEDUP (exact-JWT replay suppressed) + ONLY-ON-CHANGE state.
--   Operates on item-a-state (decoupled from the transactions source so connection_status is clean).
-- =====================================================================

-- (13) C-X2: a FRESH (not-yet-committed) STATE delivery → already_processed=false (re-drive allowed).
select is(
  (select already_processed from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-state","provider_event_id":"plaid:1000:ev-s1","is_transactions_event":false}'::jsonb)),
  false,
  '(13) C-X2 re-drive: a fresh STATE delivery (no prior gate row) → already_processed=false (resolve re-reads; the sync/commit re-drives safely)'
);

-- (14) COMMIT STATE #1 (login_required) → was_fresh=true; flips healthy→login_required + 1 state row.
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-state","provider_event_id":"plaid:1000:ev-s1","is_transactions_event":false,"status_class":"login_required","provider_error_code":"ITEM_LOGIN_REQUIRED","event_type":"ITEM.ERROR"}'::jsonb)),
  true,
  '(14) commit STATE #1 (login_required, non-null id) → was_fresh=true (gate/audit row lands)'
);

-- (15) UNDER-DEDUP: exact-JWT replay (SAME provider_event_id) → was_fresh=false (suppressed).
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-state","provider_event_id":"plaid:1000:ev-s1","is_transactions_event":false,"status_class":"login_required","provider_error_code":"ITEM_LOGIN_REQUIRED","event_type":"ITEM.ERROR"}'::jsonb)),
  false,
  '(15) UNDER-dedup: an exact-JWT replay of a STATE event (SAME provider_event_id) → was_fresh=false (ON CONFLICT DO NOTHING suppresses it)'
);

-- (16) UNDER-DEDUP TEETH: exactly ONE audit row for that provider_event_id (replay did not double-insert).
select is(
  (select count(*) from pfin.linked_source_sync_audit
     where provider_event_id = 'plaid:1000:ev-s1')::bigint,
  1::bigint,
  '(16) UNDER-dedup TEETH: exactly ONE sync_audit row for the replayed provider_event_id (the UNIQUE gate held)'
);

-- (17) resolve of the ALREADY-committed STATE delivery → already_processed=true (handler short-circuits 200).
select is(
  (select already_processed from pfin.fn_plaid_webhook_resolve(
     '{"item_id":"item-a-state","provider_event_id":"plaid:1000:ev-s1","is_transactions_event":false}'::jsonb)),
  true,
  '(17) resolve of an already-committed STATE delivery → already_processed=true (the handler short-circuits to 200 — a present gate row ⟺ that signed delivery fully processed)'
);

-- (18) exactly ONE state_history row after the flip + the suppressed replay.
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_state)::bigint,
  1::bigint,
  '(18) one state_history row after the healthy→login_required flip + the suppressed exact replay (the replay added no state row)'
);

-- (19) connection_status flipped to login_required.
select is(
  (select connection_status from pfin.linked_source where source_id = :a_state),
  'login_required',
  '(19) connection_status flipped healthy→login_required on the first STATE commit'
);

-- (20) ONLY-ON-CHANGE: a DIFFERENT-id STATE event with the SAME status (login_required) → NO new state row.
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-state","provider_event_id":"plaid:2000:ev-s2","is_transactions_event":false,"status_class":"login_required","provider_error_code":"ITEM_LOGIN_REQUIRED","event_type":"ITEM.ERROR"}'::jsonb)),
  true,
  '(20a) only-on-change: a distinct-id same-status STATE event still lands its (forensic) audit row (was_fresh=true)'
);
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_state)::bigint,
  1::bigint,
  '(20b) ONLY-ON-CHANGE: a same-status (login_required→login_required) replay adds NO new state_history row (still 1)'
);

-- (21) NON-VACUOUS companion: a REAL status change (login_required→revoked) DOES append a state row.
select is(
  (select was_fresh from pfin.fn_plaid_webhook_commit(
     '{"item_id":"item-a-state","provider_event_id":"plaid:3000:ev-s3","is_transactions_event":false,"status_class":"revoked","provider_error_code":"ITEM_LOGIN_REQUIRED","event_type":"ITEM.ERROR"}'::jsonb)),
  true,
  '(21a) non-vacuous companion: a real status change (login_required→revoked) commits (was_fresh=true)'
);
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :a_state)::bigint,
  2::bigint,
  '(21b) non-vacuous companion: the real status change DID append a 2nd state_history row → (20b)''s no-row is genuine only-on-change, not a blanket no-write'
);

-- (22) connection_status now reflects the latest real change (revoked).
select is(
  (select connection_status from pfin.linked_source where source_id = :a_state),
  'revoked',
  '(22) connection_status now = revoked (the latest real state transition flipped it)'
);

-- =====================================================================
-- BLOCK D — AC2: NULL provider_event_id on a STATE event → RPC-2 RAISES.
-- =====================================================================

-- (23) a STATE (non-transactions) event with NULL provider_event_id → RAISE (the id-gate is REQUIRED
--      for the non-cursor path). The RAISE fires FIRST (before any write) — no state mutation.
select throws_like(
  $$ select was_fresh from pfin.fn_plaid_webhook_commit(
       '{"item_id":"item-a-state","provider_event_id":null,"is_transactions_event":false,"status_class":"login_required","event_type":"ITEM.ERROR"}'::jsonb) $$,
  '%provider_event_id is required for a STATE%',
  '(23) AC2: a STATE event (is_transactions_event=false) with NULL provider_event_id RAISES (the id-gate is required for the non-cursor path; transactions events may be NULL)'
);

-- =====================================================================
-- BLOCK F — TWO-TENANT ISOLATION (AC8). A webhook naming tenant A's Item with a FORGED users_id for
--   tenant B can NEVER write tenant B: tenant is resolved FROM the Item id inside the fn; the forged
--   key is IGNORED. B's linked_source / _state_history / _sync_audit stay UNTOUCHED.
-- =====================================================================

-- Commit A's Item WITH a forged users_id = tenant B embedded in p_event (the fn must ignore it).
select is(
  (select committed from pfin.fn_plaid_webhook_commit(
     ('{"item_id":"item-a-iso","provider_event_id":"plaid:9000:ev-iso","is_transactions_event":false,"status_class":"institution_down","event_type":"ITEM.ERROR","users_id":"' || :'tb' || '"}')::jsonb)),
  true,
  '(24a) forged-key commit executes (committed=true) — sets up the isolation assertions'
);

-- (24) the audit row is attributed to TENANT A (resolved from the Item id), NOT the forged tenant B.
select is(
  (select users_id from pfin.linked_source_sync_audit where provider_event_id = 'plaid:9000:ev-iso'),
  :'ta'::uuid,
  '(24) AC8: the audit row for A''s Item is attributed to tenant A (resolved FROM item_id), NOT the FORGED users_id=B in p_event (the fn never reads the caller-supplied key — ADR-011 Decision 1 privileged-context-write)'
);

-- (25) tenant B's sync_audit is UNTOUCHED (zero rows) — the forged key wrote nothing to B.
select is(
  (select count(*) from pfin.linked_source_sync_audit where users_id = :'tb')::bigint,
  0::bigint,
  '(25) AC8: tenant B''s linked_source_sync_audit is UNTOUCHED (0 rows) — the forged users_id=B did not attribute any write to B'
);

-- (26) tenant B's state_history is UNTOUCHED (zero rows for B's source).
select is(
  (select count(*) from pfin.linked_source_state_history where source_id = :b_src)::bigint,
  0::bigint,
  '(26) AC8: tenant B''s linked_source_state_history is UNTOUCHED (0 rows)'
);

-- (27) tenant B's connection_status is UNCHANGED (still healthy).
select is(
  (select connection_status from pfin.linked_source where source_id = :b_src),
  'healthy',
  '(27) AC8: tenant B''s connection_status is UNCHANGED (still healthy) — the A-Item webhook never touched B''s source'
);

-- (28) NON-VACUOUS companion: A's Item DID get the write (the isolation is real, not an empty result).
select is(
  (select count(*) from pfin.linked_source_sync_audit where provider_event_id = 'plaid:9000:ev-iso')::bigint,
  1::bigint,
  '(28) non-vacuous companion: A''s Item DID land the audit row → (25)-(27)''s ZERO-for-B is real cross-tenant isolation, not an empty write'
);

-- =====================================================================
-- BLOCK G — CURSOR ACL. authenticated CANNOT read/write sync_cursor via the Data API; service_role can.
--   _rls.stmt_denied_as sets the role, runs the stmt, reports insufficient_privilege (42501), restores
--   postgres. Column-level denial is checked at the ACL layer (before RLS).
-- =====================================================================

-- (29) authenticated CANNOT SELECT sync_cursor (not in the 015 column grant; explicit REVOKE) → denied.
select ok(
  _rls.stmt_denied_as('authenticated', 'select sync_cursor from pfin.linked_source'),
  '(29) cursor ACL: authenticated CANNOT SELECT sync_cursor via the Data API (column-level 42501 — the 015 grant excludes it + the 045 REVOKE; fail-closed)'
);

-- (30) authenticated CANNOT UPDATE sync_cursor (no authenticated write path on linked_source) → denied.
select ok(
  _rls.stmt_denied_as('authenticated', $$ update pfin.linked_source set sync_cursor = 'x' where external_connection_id = 'item-a-txn' $$),
  '(30) cursor ACL: authenticated CANNOT UPDATE sync_cursor (service_role is the sole writer; no authenticated UPDATE grant) → fail-closed'
);

-- (31) service_role CAN read sync_cursor (non-vacuous: the deny above is column-scoped, not total).
select ok(
  not _rls.stmt_denied_as('service_role', 'select sync_cursor from pfin.linked_source'),
  '(31) cursor ACL companion: service_role CAN read sync_cursor (the worker sync path reads it) → (29) is a column-scoped denial, not a blanket block'
);

-- (32) service_role CAN write sync_cursor (advances it on a successful sync).
select ok(
  not _rls.stmt_denied_as('service_role', $$ update pfin.linked_source set sync_cursor = 'cursor-xyz' where external_connection_id = 'item-a-txn' $$),
  '(32) cursor ACL companion: service_role CAN advance sync_cursor (the service_role worker sync path) → the withholding is authenticated-scoped, by design'
);

select * from finish();
rollback;
