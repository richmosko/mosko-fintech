-- =====================================================================
-- Per-Wave battery — 040 manual↔provider dedup DETECTION + per-account sync-history read
--   (SELF-204; ADR-034 (landed) + Amendment 1). FOUR surfaces:
--     (i)   account_trans_hash_dedup_idx RELAXED UNIQUE → plain non-unique lookup.
--     (ii)  pfin.fn_create_manual_trans widened with an additive p_import_hash param (8-arg;
--           SECURITY INVOKER, STORES the caller-supplied hash; 7-arg still resolves via default).
--     (iii) pfin.manual_provider_dup_candidate — security_invoker=true DETECTION-ONLY view.
--     (iv)  pfin.linked_source_sync_history — OWNER-SEMANTICS (security_invoker=false) +
--           security_barrier view over the service_role-only linked_source_sync_audit (015).
--   surface:plaid + sec-joint-review; V1-SHIP-BLOCK. Paired with the migration in the SAME PR
--   (verify-paired-artifacts). Author: QA. Consumes (does not author) the Architect's migration.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/040_dedup_detection_and_sync_history.sql
--
-- ┌─ CRITERION → ASSERTION MAP (the two-tenant §4.5 gate) ─────────────────────────────────────────┐
-- │ PART A — manual_provider_dup_candidate (security_invoker=true detection view)                   │
-- │  1. Detection: manual(source_provider NULL)+provider(NOT NULL) sharing (account_id,import_hash) │
-- │     surface as a candidate pair ............................... D1                              │
-- │  2. Non-matching pair does NOT surface ........................ D2                              │
-- │  3. Reversed rows (is_reverse=true) excluded .................. D3                              │
-- │  4. Two-tenant NO-LEAK on the view (BOTH directions) ......... D4 (B sees 0 of A) [load-bearing]│
-- │                                                              + D6 (A sees 0 of B)               │
-- │     ...non-vacuous companion (owner DOES see own) ............ D5 (B sees its own pair)         │
-- │ PART B — linked_source_sync_history (owner-semantics security_barrier view)                     │
-- │  5. Two-tenant NO-LEAK on the view ........................... S2 (A sees 0 of B) + S7 (B of A) │
-- │  6. ANTI-LEAK TEETH: base linked_source_sync_audit NOT SELECTable by authenticated (no grant) → │
-- │     the owner-semantics view is the SOLE path; detail unreachable . S3 (42501) [load-bearing]   │
-- │  7. Projection allowlist: ONLY provider/source/created_at/transactions_inserted/_skipped —      │
-- │     NOT detail / NOT event_type ............................... S4 (detail 42703) + S5 (event_)  │
-- │     ...projection extraction is correct + owner reads own .... S1 (A: 7/3) + S6 (B: 11/2)       │
-- │  7b. PER-CONNECTION join (view revised → INNER-joins linked_source, projects linked_source_id): │
-- │     linked_source_id resolves to caller's own source (positive) . J1 (auth-A: = a_source)       │
-- │     join is NO new leak path (cross-tenant re-check) ............ J2 (auth-B: 0 of a_source)     │
-- │     INNER-join drops unattributable rows (NULL ext-conn) ........ J3 (auth-A: marker 999 absent) │
-- │ PART C — index relax + RPC widening                                                             │
-- │  8. Index UNIQUE→non-unique (structural) ..................... C1 (indisunique=false)           │
-- │     8-arg RPC STORES import_hash ............................. C2                                │
-- │     Two IDENTICAL manual entries now BOTH insert (was: unique aborted the 2nd) ... C3 (count 2)  │
-- │     7-arg RPC still resolves (import_hash defaults NULL) ..... C4                                │
-- │     Widened RPC still cross-tenant fail-closed + NO orphan ... C5 (RLS reject) + C6 (0 orphan)   │
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
-- SEC CATCH-CRITERIA (1–7) → ASSERTIONS (all owner-view + RPC tests run under the `authenticated`
--   role with auth.uid() set per-tenant via _rls.set_tenant — NEVER postgres/service_role; under
--   postgres auth.uid() is NULL and the owner-semantics WHERE users_id=auth.uid() matches nothing,
--   making every no-leak assertion VACUOUS. S1/S6 are the non-vacuous anchors proving auth.uid() is
--   live): #1 owner-reads-own → S1 (auth-A: 7/3) + S6 (auth-B: 11/2); #2 sync-history cross-tenant
--   fail-closed → S2 (auth-A: 0 of B) + S7 (auth-B: 0 of A); #3 blob unreadable → S3 (auth-A base
--   SELECT → 42501); #4 projection column-set → S4 (detail 42703) + S5 (event_type 42703) [+ S1/S6
--   confirm the 5 allowlisted cols]; #5 detection owner-pair + cross-tenant-none → D1 (auth-A sees
--   pair) + D4/D6 (cross-tenant none both dirs) + D5 (auth-B sees own) [+ D2/D3 negatives]; #6
--   fn_create_manual_trans 8-arg stores / 7-arg resolves / cross-tenant fail-closed → C2 + C4 + C5/C6;
--   #7 index-relax → C1 (structural) + C3 (behavioral count=2). PER-CONNECTION JOIN MERGE-GATE
--   (view revised 2026-07-27 → INNER-joins linked_source, projects linked_source_id; Sec GREEN
--   conditional on join coverage): J1 (auth-A: linked_source_id resolves to a_source — positive) +
--   J2 (auth-B: 0 of A's a_source — join is no new leak path, load-bearing) + J3 (auth-A: an
--   A-owned NULL-linked_source_id row is EXCLUDED — conservative INNER drop). NOTE (044): the
--   audit→linked_source join is now on the STABLE linked_source_id, not the (provider,
--   external_connection_id) digest — fixtures set linked_source_id; J3's exclusion is a NULL id.
--
-- Prereqs exercised on the 001→040 reset stack (Backend owns the clean-apply): 001 (pfin,
--   fn_refresh_updated_at, auth.uid()), 003 (account + fn_grant_creator_access DEFINER creator-
--   grant trigger → account_users rd=t/wr=t — the detection view composes under rd_access; the
--   RPC under wr_access), 004 (account_trans immutable ledger — the INSERT target + import_hash +
--   is_reverse cols + the relaxed hash index host), 006 (account_trans rd/wr_access-JOIN RLS +
--   grant — the chain surfaces (i)/(iii) compose under), 015 (linked_source_sync_audit — the
--   service_role-only base of surface (iv), its users_id/detail/event_type cols), 017 (source_
--   provider / provider_txn_id / import_hash cols + the cash-row shape quantity=0/security_id NULL),
--   023 (account_trans_annotation — the RPC's conditional overlay, WHEN-skipped on NULL cat+note),
--   024 (user_settings.mfa_policy — A/B 'none' → the account_trans_insert aal2 backstop is a no-op),
--   030 (transaction_type='standard' default + the Trade fence, WHEN-skipped on NULL sub_cat), 038
--   (fn_create_manual_trans 7-arg — the RPC 040 widens to 8-arg).
--
-- ┌─ WHY THE DETECTION FIXTURE ITSELF EXERCISES THE INDEX RELAX (i) ───────────────────────────────┐
-- │ Surface (iii)'s candidate pair is a manual leg + a provider leg sharing (account_id,import_hash)│
-- │ on the SAME account. Under the PRE-040 hard-UNIQUE (account_id,import_hash) index that pair     │
-- │ could not COEXIST (the 2nd insert would abort 23505). Seeding it at all requires the 040        │
-- │ relaxation → the fixture's existence is a live dependency on (i). C1/C3 add the explicit guards.│
-- └────────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 040 adds ZERO catalogued §10
--   instances — an index relax + an INVOKER RPC param + two authenticated-tier read views; NO new
--   service_role grant (linked_source_sync_audit stays service_role-only; the owner-semantics view
--   is the read path, not a grant to the base), no credential, no admission channel). Decision-3
--   family UNCHANGED — 040 adds NO FK-shaped reference column (the index relax removes a uniqueness
--   property; p_import_hash stores text; the detection view READS existing FKs; the sync-history
--   view keys on users_id = auth.uid(), a direct-owner anchor, not a matched-tenant two-anchor FK).
--   SECURITY DEFINER allowlist UNCHANGED at 4 (fn_create_manual_trans stays INVOKER; the two views
--   are not DEFINER functions). DE-CONFLATION: the sync-history owner-semantics view is a
--   privileged-READ surface (Sec-reviewed), NOT a §10 catalogued instance and NOT a Decision-3
--   instance. This battery introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants _rls.tenant_a()/_b(); NO PII / NO
--   real account numbers / NO prod data. import_hash values are opaque synthetic markers ('hashcand-a'
--   …), detail blobs are hand-authored count-key jsonb — no real Plaid payload. A owns acct-alpha; B
--   owns acct-beta. account.users_id set EXPLICITLY (auth.uid() NULL under postgres). All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121): `_rls` grants no USAGE to authenticated; each block restores
--   role=postgres before the next; \gset var names ALL-LOWERCASE; %L for uuids / %s for bigints;
--   SQLSTATE-precise throws_ok (42501 ACL deny · 42703 undefined_column) — never message-only, so
--   one fence can't pass for another (004 all-42501 lesson).
--
-- ⟦WIRE-VALIDATE⟧ authored against 040's firmed contract; the AUTHORITATIVE run is the 001→040 reset
--   stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's clean-apply + `supabase
--   migration up`). The committed file does NOT self-apply the migration. plan(22).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case → ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(22);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS + ACL bypassed; the creator-grant trigger fires role-
-- agnostically and grants account_users rd=t/wr=t on the seeded accounts).
--  - Two tenants A + B, both mfa 'none' (→ the account_trans_insert aal2 backstop is a no-op).
--  - Accounts via the 003 creator-grant trigger. A: acct-alpha; B: acct-beta.
--  - DETECTION legs (cash rows: security_id NULL + quantity 0 default → 017 CHECK):
--      A/accta: a manual leg (source_provider NULL) + a provider leg (source_provider 'plaid')
--        sharing import_hash 'hashcand-a', both is_reverse=false → ONE candidate pair (D1).
--        A non-matching manual ('hashnomatch-a', no provider partner) → D2.
--        A reversed pair on 'hashrev-a' (manual leg is_reverse=TRUE) → D3-excluded.
--      B/acctb: a manual+provider pair on import_hash 'hashcand-b' → B's OWN candidate (D5),
--        the cross-tenant referent (D4/D6).
--  - SYNC-HISTORY rows (service_role-only linked_source_sync_audit, seeded privileged):
--      A: provider 'plaid'/source 'scheduled_poll', detail result {inserted:7, skipped:3}.
--      B: provider 'plaid'/source 'webhook',       detail result {inserted:11, skipped:2}.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_settings (users_id, mfa_policy) values (:'ta', 'none'), (:'tb', 'none');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'depository', 'household', 'taxable') returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-beta', 'depository', 'household', 'taxable') returning account_id as acctb \gset

-- A's candidate pair (manual + provider) sharing import_hash 'hashcand-a' — COEXISTENCE requires
-- the 040-relaxed non-unique hash index (pre-040 UNIQUE would abort the 2nd insert).
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:accta, '2026-04-10', 42.00, 'CAND-A-manual', 'A manual leg', 'standard', null, null, 'hashcand-a', false)
  returning trans_id as a_manual \gset
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:accta, '2026-04-10', 42.00, 'CAND-A-provider', 'A provider leg', 'standard', 'plaid', 'ptxn-a', 'hashcand-a', false)
  returning trans_id as a_provider \gset

-- A's non-matching manual (no provider partner sharing its hash) → never a candidate.
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:accta, '2026-04-11', 13.00, 'NOMATCH-A', 'A lone manual', 'standard', null, null, 'hashnomatch-a', false);

-- A's reversed pair on 'hashrev-a': manual leg is_reverse=TRUE (the only difference from a real
-- candidate) + a live provider leg → the view's m.is_reverse=false clause EXCLUDES it.
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:accta, '2026-04-12', 99.00, 'REV-A-manual', 'A reversed manual leg', 'standard', null, null, 'hashrev-a', true);
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:accta, '2026-04-12', 99.00, 'REV-A-provider', 'A reversed-pair provider leg', 'standard', 'plaid', 'ptxn-rev', 'hashrev-a', false);

-- B's OWN candidate pair on 'hashcand-b' (the cross-tenant referent).
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:acctb, '2026-04-13', 55.00, 'CAND-B-manual', 'B manual leg', 'standard', null, null, 'hashcand-b', false)
  returning trans_id as b_manual \gset
insert into pfin.account_trans
  (account_id, transaction_date, amount, vendor, description, transaction_type, source_provider, provider_txn_id, import_hash, is_reverse)
  values (:acctb, '2026-04-13', 55.00, 'CAND-B-provider', 'B provider leg', 'standard', 'plaid', 'ptxn-b', 'hashcand-b', false);

-- Per-connection linked_source rows. NOTE (044): the view now INNER-joins the audit to linked_source
--   on the STABLE linked_source_id (was the (provider, external_connection_id) digest), WHERE
--   ls.users_id=auth.uid(), projecting source_id as linked_source_id. A's + B's audit rows carry
--   linked_source_id → the join resolves their OWN source_id (J1/J2). Seeded privileged; users_id
--   explicit (RLS bypass under postgres; the linked_source write path is service_role-only anyway).
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'ta', 'plaid', 'qa-conn-a', 'QA A Institution') returning source_id as a_source \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'tb', 'plaid', 'qa-conn-b', 'QA B Institution') returning source_id as b_source \gset

-- Sync-history audit rows (service_role-only table; append-only). users_id = the resolved tenant;
--   linked_source_id = the tenant's own source (044 stable key — the post-044 worker writeAudit sets
--   it) → the INNER id-join resolves. detail carries ONLY the named count keys the view projects;
--   event_type is set to prove S5 excludes it even when present.
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, event_type, detail, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', 'qa-conn-a', 'SYNC_COMPLETE',
          '{"result": {"transactionsInserted": 7, "transactionsSkipped": 3}}'::jsonb, :a_source);
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, event_type, detail, linked_source_id)
  values ('plaid', 'webhook', :'tb', 'qa-conn-b', 'SYNC_COMPLETE',
          '{"result": {"transactionsInserted": 11, "transactionsSkipped": 2}}'::jsonb, :b_source);

-- An UNATTRIBUTABLE A-owned audit row: users_id=A (passes the WHERE lsa.users_id=auth.uid()) but
--   linked_source_id NULL (044: a pre-companion / removed-source / unattributable row) → NO id-join
--   match → the conservative INNER join EXCLUDES it (J3). Marker count 999 (distinct from 7/11) so
--   its absence is provable & non-vacuous vs J1.
insert into pfin.linked_source_sync_audit
  (provider, source, users_id, external_connection_id, event_type, detail, linked_source_id)
  values ('plaid', 'scheduled_poll', :'ta', null, 'SYNC_COMPLETE',
          '{"result": {"transactionsInserted": 999, "transactionsSkipped": 0}}'::jsonb, null);

-- =====================================================================
-- PART A — manual_provider_dup_candidate (security_invoker=true DETECTION view).
--   BLOCK A1 (authenticated A): positive detection + owner-read + the negative filters + A→B leak.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (D1) [criterion 1] positive detection + owner-read: A's manual+provider pair sharing
--      (accta, 'hashcand-a') surfaces as EXACTLY ONE candidate, with the projected columns wired
--      to the right legs (manual_trans_id=a_manual, provider_trans_id=a_provider, provider='plaid',
--      provider_txn_id='ptxn-a', both amounts 42.00).
select is(
  (select count(*) from pfin.manual_provider_dup_candidate
     where account_id = :accta
       and manual_trans_id = :a_manual and provider_trans_id = :a_provider
       and provider = 'plaid' and provider_txn_id = 'ptxn-a'
       and import_hash = 'hashcand-a'
       and manual_amount = 42.00 and provider_amount = 42.00)::bigint,
  1::bigint,
  '(D1) detection + owner-read: A''s manual(source_provider NULL) + provider(NOT NULL) legs sharing (accta, hashcand-a) surface as EXACTLY ONE candidate pair, projected columns wired to the correct legs'
);

-- (D2) [criterion 2] non-matching pair does NOT surface: the lone manual 'hashnomatch-a' has no
--      provider partner sharing its hash → 0 candidate rows.
select is(
  (select count(*) from pfin.manual_provider_dup_candidate where import_hash = 'hashnomatch-a')::bigint,
  0::bigint,
  '(D2) non-match excluded: a manual row whose import_hash is shared by NO provider row surfaces as ZERO candidates — the self-join requires a provider leg on the same (account_id, import_hash)'
);

-- (D3) [criterion 3] reversed rows excluded: the 'hashrev-a' pair is manual+provider on the same
--      account/hash but the manual leg is_reverse=TRUE → the view's is_reverse=false clause drops it.
select is(
  (select count(*) from pfin.manual_provider_dup_candidate where import_hash = 'hashrev-a')::bigint,
  0::bigint,
  '(D3) reversed excluded: an otherwise-matching manual+provider pair whose manual leg is_reverse=TRUE surfaces as ZERO candidates — the view''s m.is_reverse=false AND p.is_reverse=false clauses exclude reversed rows'
);

-- (D6) [criterion 4] two-tenant no-leak (A→B): A sees ZERO of B's candidates (acct-beta) — the
--      security_invoker view composes under A's account_trans rd_access RLS (B's account invisible).
select is(
  (select count(*) from pfin.manual_provider_dup_candidate where account_id = :acctb)::bigint,
  0::bigint,
  '(D6) two-tenant no-leak (A→B): A calling the security_invoker view sees ZERO candidate rows on B''s account (acct-beta) — the view composes ENTIRELY under A''s account_trans rd_access-JOIN RLS'
);

select set_config('role', 'postgres', true);

-- =====================================================================
--   BLOCK A2 (authenticated B): the load-bearing cross-tenant no-leak (B→A) + its non-vacuous
--     companion (B DOES see its own pair) — together they prove real isolation, not an empty view.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (D4) [criterion 4] LOAD-BEARING two-tenant no-leak (B→A): tenant B sees ZERO of A's candidate
--      rows (acct-alpha) → the detection view leaks NO foreign-tenant pair. RED if security_invoker
--      were lost (a DEFINER/owner view would leak A's pair to B).
select is(
  (select count(*) from pfin.manual_provider_dup_candidate where account_id = :accta)::bigint,
  0::bigint,
  '(D4) two-tenant no-leak (B→A) [load-bearing]: tenant B calling manual_provider_dup_candidate sees ZERO of A''s candidate rows (acct-alpha) — owner-only via the security_invoker rd_access composition'
);

-- (D5) [criterion 4 non-vacuous] B DOES see its OWN candidate pair (acct-beta, hashcand-b) →
--      proves D4's 0 is genuine isolation, not a globally-empty view.
select is(
  (select count(*) from pfin.manual_provider_dup_candidate
     where account_id = :acctb and manual_trans_id = :b_manual and import_hash = 'hashcand-b')::bigint,
  1::bigint,
  '(D5) non-vacuous companion: B DOES see its OWN candidate pair (acct-beta, hashcand-b) → D4''s ZERO for A is real cross-tenant isolation, not an empty result set'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- PART B — linked_source_sync_history (OWNER-SEMANTICS security_barrier view; base ungranted).
--   BLOCK B1 (authenticated A): owner-read + projection extraction + no-leak + ANTI-LEAK TEETH +
--     projection allowlist (detail/event_type absent).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (S1) [criterion 7] owner-read + projection extraction: A sees its OWN sync row with the count
--      keys correctly extracted from detail->'result' (transactions_inserted=7, _skipped=3) and the
--      allowlisted scalars (provider/source). WHERE users_id=auth.uid() scopes it to A.
select is(
  (select count(*) from pfin.linked_source_sync_history
     where provider = 'plaid' and source = 'scheduled_poll'
       and transactions_inserted = 7 and transactions_skipped = 3)::bigint,
  1::bigint,
  '(S1) owner-read + projection: A sees its OWN sync-history row with transactions_inserted=7 / transactions_skipped=3 correctly extracted from detail->''result'' (+ provider/source) — the owner-semantics view returns A''s own rows'
);

-- (S2) [criterion 5] two-tenant no-leak (A→B): A sees ZERO rows carrying B's marker count
--      (transactions_inserted=11) → the owner-semantics view scopes WHERE users_id=auth.uid().
select is(
  (select count(*) from pfin.linked_source_sync_history where transactions_inserted = 11)::bigint,
  0::bigint,
  '(S2) two-tenant no-leak (A→B): A sees ZERO sync-history rows carrying B''s marker (transactions_inserted=11) — the view scopes rows WHERE users_id = auth.uid()'
);

-- (S3) [criterion 6] LOAD-BEARING ANTI-LEAK TEETH: the base linked_source_sync_audit is NOT
--      granted to authenticated (stays service_role-only, 015) → a direct SELECT raises 42501 (hard
--      ACL deny). This proves the owner-semantics view is the SOLE authenticated read path and the
--      caller CANNOT reach `detail`/`event_type` by hitting the base table directly. RED if the
--      migration accidentally granted the base table to authenticated (defeating the projection).
select throws_ok(
  $$ select count(*) from pfin.linked_source_sync_audit $$,
  '42501', null,
  '(S3) anti-leak teeth [load-bearing]: the base linked_source_sync_audit is ungranted to authenticated → a direct SELECT raises 42501 (hard ACL deny). The owner-semantics view is the SOLE path; the caller cannot reach the raw detail blob directly'
);

-- (S4) [criterion 7] projection allowlist: the view has NO `detail` column → SELECT detail raises
--      42703 undefined_column. The raw JSONB blob is never exposed through the view.
select throws_ok(
  $$ select detail from pfin.linked_source_sync_history $$,
  '42703', null,
  '(S4) projection allowlist: the view exposes NO `detail` column → SELECT detail raises 42703 (undefined_column) — the raw blob is never selectable from the view'
);

-- (S5) [criterion 7] projection allowlist: the view has NO `event_type` column → 42703 (even though
--      the base row carries event_type='SYNC_COMPLETE', the projection omits it).
select throws_ok(
  $$ select event_type from pfin.linked_source_sync_history $$,
  '42703', null,
  '(S5) projection allowlist: the view exposes NO `event_type` column → SELECT event_type raises 42703 (undefined_column) — excluded from the allowlist even though the base row carries it'
);

-- (J1) [join positive] linked_source_id resolves: A's sync row (ext-conn 'qa-conn-a') joins A's OWN
--      linked_source and projects linked_source_id = a_source. Non-vacuous positive — proves the
--      per-connection join resolves to the caller's own source_id (RED if the join dropped the row
--      or projected a wrong/foreign source_id).
select is(
  (select count(*) from pfin.linked_source_sync_history
     where linked_source_id = :a_source and provider = 'plaid' and transactions_inserted = 7)::bigint,
  1::bigint,
  '(J1) join positive: A''s sync-history row resolves linked_source_id = a_source (its OWN connection, joined on the STABLE linked_source_id (044) WHERE ls.users_id=auth.uid()) — the per-connection discriminator is correctly wired'
);

-- (J3) [INNER-join exclusion] the A-owned audit row with a NULL linked_source_id (044: marker
--      transactions_inserted=999) is ABSENT from A's view — its users_id passes the WHERE, but a
--      NULL linked_source_id has no id-join match → the conservative INNER join drops it (an
--      unattributable / pre-companion / removed-source row is NEVER surfaced). Non-vacuous vs J1:
--      same tenant, only the connection match differs.
select is(
  (select count(*) from pfin.linked_source_sync_history where transactions_inserted = 999)::bigint,
  0::bigint,
  '(J3) INNER-join exclusion: an A-owned audit row with NULL linked_source_id (044; marker 999) is ABSENT from A''s view — passes WHERE lsa.users_id=auth.uid() but has NO id-join match, so the INNER join excludes it (unattributable rows dropped, not surfaced)'
);

select set_config('role', 'postgres', true);

-- =====================================================================
--   BLOCK B2 (authenticated B): owner-read non-vacuous companion + no-leak (B→A).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (S6) [criterion 7 non-vacuous] B sees its OWN sync row (transactions_inserted=11, _skipped=2) →
--      the view works under B; proves S2/S7's 0 is real scoping, not a globally-empty view.
select is(
  (select count(*) from pfin.linked_source_sync_history
     where provider = 'plaid' and source = 'webhook'
       and transactions_inserted = 11 and transactions_skipped = 2)::bigint,
  1::bigint,
  '(S6) non-vacuous companion: B sees its OWN sync-history row (transactions_inserted=11 / _skipped=2) → the no-leak ZEROs are real per-tenant scoping, not an empty view'
);

-- (S7) [criterion 5] two-tenant no-leak (B→A): B sees ZERO rows carrying A's marker (7).
select is(
  (select count(*) from pfin.linked_source_sync_history where transactions_inserted = 7)::bigint,
  0::bigint,
  '(S7) two-tenant no-leak (B→A): B sees ZERO sync-history rows carrying A''s marker (transactions_inserted=7) — WHERE users_id = auth.uid() scopes each caller to its own rows'
);

-- (J2) [join no-leak, load-bearing re-check] the added per-connection join is NOT a new leak path:
--      under auth-B, B sees ZERO rows carrying A's linked_source_id (a_source). The join is
--      owner-scoped on BOTH sides (lsa.users_id + ls.users_id = auth.uid()) → it cannot widen to a
--      foreign connection. Non-vacuous companion: S6 (B DOES see its own row, 11/2) proves B's view
--      is not globally empty, so this ZERO is real isolation across the join.
select is(
  (select count(*) from pfin.linked_source_sync_history where linked_source_id = :a_source)::bigint,
  0::bigint,
  '(J2) join no-leak (B→A) [load-bearing]: under auth-B, B sees ZERO rows carrying A''s linked_source_id (a_source) — the owner-scoped INNER join (ls.users_id=auth.uid() on the join + lsa.users_id=auth.uid() in WHERE) is fail-closed on BOTH sides, so the added join is no new leak path'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- PART C — index relax (i) + fn_create_manual_trans widening (ii).
--   C1 is structural (postgres); C2/C3/C4 exercise the RPC under authenticated A (the real INVOKER
--   path), then read back privileged (deterministic full visibility).
-- =====================================================================
-- (C1) [criterion 8 structural] the relaxed index is NON-unique: pg_index.indisunique = false. RED
--      if the migration failed to drop-and-recreate the 004 UNIQUE index as a plain lookup index.
select is(
  (select i.indisunique
     from pg_class c join pg_index i on i.indexrelid = c.oid
     where c.relname = 'account_trans_hash_dedup_idx'),
  false,
  '(C1) index relax (structural): account_trans_hash_dedup_idx is NON-unique (pg_index.indisunique=false) — the 004 hard-UNIQUE (account_id, import_hash) fence was relaxed to a plain lookup index (ADR-034 Amdt 1)'
);

-- RPC calls under authenticated A (the composition under test): 8-arg twice with the SAME hash,
-- then a 7-arg call. A holds wr_access on acct-alpha; mfa 'none' → aal2 backstop is a no-op.
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_create_manual_trans(:accta, '2026-04-20', 25.00, 'DUP-VENDOR', 'dup entry', null, null, 'duphash-001') as rpc_dup1 \gset
select pfin.fn_create_manual_trans(:accta, '2026-04-20', 25.00, 'DUP-VENDOR', 'dup entry', null, null, 'duphash-001') as rpc_dup2 \gset
select pfin.fn_create_manual_trans(:accta, '2026-04-21', 10.00, 'NOHASH-VENDOR', 'no hash entry', null, null) as rpc_nohash \gset
select set_config('role', 'postgres', true);

-- (C2) [criterion 8] the 8-arg call STORES the caller-supplied import_hash into account_trans, as a
--      manual cash leg (source_provider NULL, transaction_type standard, security_id NULL).
select is(
  (select count(*) from pfin.account_trans
     where trans_id = :rpc_dup1 and account_id = :accta
       and import_hash = 'duphash-001' and source_provider is null
       and transaction_type = 'standard' and security_id is null and quantity = 0)::bigint,
  1::bigint,
  '(C2) 8-arg RPC stores import_hash: the widened fn_create_manual_trans persists p_import_hash (''duphash-001'') into account_trans.import_hash on a manual cash leg (source_provider NULL) — the additive param is wired to the column'
);

-- (C3) [criterion 8 LOAD-BEARING regression guard] two IDENTICAL manual entries (same account/date/
--      amount/vendor → the caller supplies the same canonical import_hash) now BOTH insert → count 2.
--      Under the pre-040 UNIQUE (account_id, import_hash) index the SECOND call would have aborted
--      23505; the relaxation is what lets legitimately-identical manual entries coexist.
select is(
  (select count(*) from pfin.account_trans where account_id = :accta and import_hash = 'duphash-001')::bigint,
  2::bigint,
  '(C3) index-relax regression: two identical manual entries sharing (accta, duphash-001) BOTH insert (count=2) — pre-040 the UNIQUE index aborted the 2nd (23505); the 040 non-unique relaxation admits both'
);

-- (C4) [criterion 8] the 7-arg call still resolves (p_import_hash defaults NULL) → the row lands
--      with import_hash NULL (the pre-040 behavior; backward-compatible signature).
select is(
  (select count(*) from pfin.account_trans
     where trans_id = :rpc_nohash and account_id = :accta and import_hash is null)::bigint,
  1::bigint,
  '(C4) 7-arg RPC backward-compatible: a 7-arg call (no p_import_hash) still resolves and lands the row with import_hash NULL (the param defaults NULL — pre-040 behavior preserved)'
);

-- (C5) [criterion 6 cross-tenant] the WIDENED 8-arg RPC still fails closed cross-tenant: authenticated
--      A calls fn_create_manual_trans with B's account_id (acctb) + a hash → the account_trans_insert
--      wr_access-JOIN WITH CHECK REJECTS under A's RLS (the additive p_import_hash param does NOT
--      re-open tenant isolation; the RPC stays SECURITY INVOKER, composing under the caller's RLS).
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_trans(%s, '2026-04-22', 30.00, 'RPC-XTENANT-040', 'steal', null, null, 'xtenant-hash') $$, :acctb),
  '%violates row-level security policy%',
  '(C5) widened RPC cross-tenant fail-closed: authenticated A calling fn_create_manual_trans (8-arg) with B''s account_id is REJECTED by the account_trans_insert wr_access-JOIN WITH CHECK under A''s RLS — the additive param does not bypass isolation (INVOKER-composed)'
);
select set_config('role', 'postgres', true);

-- (C6) [criterion 6 atomicity] the (C5) reject left NO orphan on the immutable ledger (statement-1
--      is the rejected write; the marker vendor confirms nothing landed).
select is(
  (select count(*) from pfin.account_trans where vendor = 'RPC-XTENANT-040')::bigint,
  0::bigint,
  '(C6) atomicity: the (C5) cross-tenant reject left ZERO ''RPC-XTENANT-040'' rows on the immutable account_trans ledger — the wr_access WITH CHECK denied statement-1, so no orphan (no authenticated DELETE exists to clean one up)'
);

select * from finish();
rollback;
