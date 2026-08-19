-- =====================================================================
-- Per-Wave battery — pfin.posting_prototype + pfin.posting_prototype_default: the cashflow-
--   vocabulary half of the ADR-058 split. RLS two-tenant (SELECT + INSERT only — no UPDATE/DELETE
--   grant, Sec F5), the 025 aal2 backstop on INSERT (041's user_taxonomy_insert clause verbatim,
--   Shape A), the unconditional cat CHECK (Decision 4, moved+de-conditionalized from `028`), and
--   the Decision 2 id-space construction (disjoint reserved ranges, both tables generated always).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/084_gl_split_posting_prototype.sql
--   - pfin.posting_prototype (id bigint generated always as identity (start with 1000000000
--       minvalue 1000000000 no cycle), users_id uuid not null default auth.uid() references
--       auth.users(id) on delete cascade, cat, sub_cat, tax_relevant, tax_character,
--       display_order, is_active, notes, created_at, updated_at; unique(users_id, cat, sub_cat);
--       check (cat in ('Revenue','Expense','Transfer','Equity','Trade')) UNCONDITIONAL —
--       Decision 4: the table IS the domain, so the disjunct that exempted asset-domain rows
--       under `028` has nothing left to exempt). SELECT policy users_id=auth.uid(); INSERT
--       policy carries 041's aal2 backstop clause VERBATIM (Shape A). Grants: select+insert to
--       authenticated ONLY — no update, no delete (Sec F5 VETO territory if either arrives).
--       anon zero. No service_role grant (008's per-table-explicit-grant posture makes this true
--       by construction, not by an explicit revoke).
--   - pfin.posting_prototype_default (id bigint generated always as identity — FRESH ids, no
--       reserved range, Architect's own-call: nothing references taxonomy_default ids, so the
--       audit-truth hazard Decision 2 exists for has no analogue here; cat/sub_cat/tax_relevant/
--       tax_character/display_order/notes; unique(cat, sub_cat); NO users_id, NO FK; global
--       shared-read using(true); SELECT grant to authenticated only; 025 aal2 EXCLUSION (i) —
--       the taxonomy_default posture, Decision-3-neutral).
--   - pfin.user_taxonomy.id's identity sequence gains `maxvalue 999999999` in the same migration
--       (the half that makes disjointness structural rather than inherited — two offset ranges
--       are disjoint only until the lower one advances into the upper one; with the maxvalue,
--       user_taxonomy hard-errors at the boundary instead of colliding, per Sec F1's veto of the
--       original "set past the maximum" mechanism).
-- Prereqs: 001 (pfin schema + fn_refresh_updated_at), 009/041 (the aal2 INSERT clause shape this
--   migration copies verbatim), 025 (the aal2 backstop clause), auth.users.
-- Reuses the 074 S1/S2/S3a/S3b structural idiom (Sec's own recommended model for this table,
--   ADR-058 Decision 1) and the 009 Block-6 CHECK idiom (relocated, not re-derived).
--
-- (CHK1)-(CHK7) are RELOCATED from 009_user_taxonomy_rls.sql Block 6 — same 7 ACCEPT/REJECT
--   assertions against the accounting-class CHECK, same predicate, new table, because Decision 4
--   moves the CHECK unconditionally off user_taxonomy onto posting_prototype. 009's own file drops
--   these 7 legs plus the domain-CHECK-enum leg (4b) in the companion edit riding this PR
--   (009: plan() 22 -> 14; that constraint's own domain column no longer exists to check).
--
-- ⟦WIRE-VALIDATE⟧ authored against 084 as committed (3a5bdd8) and RE-VERIFIED against the
--   001->084 stack on a hand-built scratch DB (createdb + auth/extensions/vault schemas + pgtap
--   restored from the live Supabase container, per the #474 venue recipe — `supabase db reset`
--   is mechanically banned). 20/20 PASS. Corrupt-the-control confirmed non-vacuous: granting
--   `authenticated` an UPDATE on posting_prototype turned (S4) RED naming exactly that privilege;
--   reverted, re-ran clean.
--
-- ┌─ WHY THE STRUCTURAL LEGS ARE NOT OPTIONAL (Sec F5) ─────────────────────────────────────┐
-- │ 025's battery is per-table behavioural, not an enumerative sweep, and there is no repo-  │
-- │ wide watcher asserting RLS is enabled on every `pfin` table (Sec F8, routed to BACKLOG,  │
-- │ not a gate here). A new table shipped with a missing policy or a missing aal2 clause     │
-- │ would be caught by review or not at all. (S1)-(S6) below stand in for that watcher.      │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ THE ID-SPACE LEG ASSERTS THE CONSTRUCTION, NOT A COUNT (Sec F1's condition) ───────────┐
-- │ "The two id spaces do not overlap" is the WRONG leg — on a fresh CI stack it is true     │
-- │ because nothing has been inserted, which is an assertion with nothing watching what      │
-- │ falsifies it (Sec F1 vetoed the original mechanism for exactly this class of failure).   │
-- │ (ID1) reads pg_sequence directly: user_taxonomy's maxvalue < posting_prototype's          │
-- │ minvalue — true regardless of row count, and RED if either bound is ever widened.        │
-- │ (ID2) is the directly-checkable half Decision 2 also requires ("at least one moved row    │
-- │ retains its pre-split id") — but on a FRESH stack there are zero real provisioned users,  │
-- │ so there is nothing that actually moved to observe. (ID2) instead PROVES THE MECHANISM:   │
-- │ both tables accept an explicit low id via `overriding system value`, and the value lands  │
-- │ byte-exact — which is precisely the operation 084's own copy step performs. This is a     │
-- │ synthetic proof of capability, not a claim to have observed a real historical migration    │
-- │ event; say so in the message so it is never later cited as the latter.                    │
-- └───────────────────────────────────────────────────────────────────────────────────────┘

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(20);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- BLOCK S — structural (pg_policy / pg_class / pg_sequence catalog reads, no behavioural gate
--   in front of them can shadow these the way `074`'s BEFORE trigger shadows its own WITH CHECK).
-- =====================================================================

-- (S1) posting_prototype_select carries a USING clause wired to users_id = auth.uid().
select ok(
  (select pg_get_expr(polqual, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy where polrelid = 'pfin.posting_prototype'::regclass
       and polname = 'posting_prototype_select'),
  '(S1) STRUCTURAL: posting_prototype_select carries a USING expression referencing users_id = auth.uid() — proves the SELECT policy exists and is wired to the tenant column'
);

-- (S2) posting_prototype_insert carries a WITH CHECK clause wired to users_id = auth.uid().
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy where polrelid = 'pfin.posting_prototype'::regclass
       and polname = 'posting_prototype_insert'),
  '(S2) STRUCTURAL: posting_prototype_insert carries a WITH CHECK expression referencing users_id = auth.uid()'
);

-- (S3) posting_prototype_insert's WITH CHECK also carries the 025/041 aal2 backstop clause,
--   VERBATIM per Decision 1 (Shape A) — not a paraphrase, not a re-derivation.
select ok(
  (select coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'
     from pg_policy where polrelid = 'pfin.posting_prototype'::regclass
       and polname = 'posting_prototype_insert'),
  '(S3) STRUCTURAL: posting_prototype_insert''s WITH CHECK carries the ADR-029/025 aal2 backstop clause (pg_policy catalog) — RED if the split PR shipped the tenant predicate without also copying the aal2 half'
);

-- (S4) authenticated grants are EXACTLY {select, insert} — no update, no delete (Sec F5 VETO
--   territory: "the split is a change of home, not an occasion to un-defer mutate-dormancy").
select is(
  (select array_agg(privilege_type::text order by privilege_type)
     from information_schema.role_table_grants
    where table_schema = 'pfin' and table_name = 'posting_prototype'
      and grantee = 'authenticated'),
  array['INSERT','SELECT'],
  '(S4) STRUCTURAL: authenticated holds EXACTLY {INSERT, SELECT} on posting_prototype — no UPDATE, no DELETE (RED if either mutate grant arrives; Sec F5 vetoes it explicitly)'
);

-- (S5) anon holds ZERO grants on posting_prototype.
select is(
  (select count(*)::bigint from information_schema.role_table_grants
    where table_schema = 'pfin' and table_name = 'posting_prototype' and grantee = 'anon'),
  0::bigint,
  '(S5) STRUCTURAL: anon holds zero grants on posting_prototype'
);

-- (S6) service_role holds ZERO grants on posting_prototype (008's explicit-per-table posture
--   makes this true by construction — RED if any future migration adds `alter default
--   privileges` or an explicit service_role grant here).
select is(
  (select count(*)::bigint from information_schema.role_table_grants
    where table_schema = 'pfin' and table_name = 'posting_prototype' and grantee = 'service_role'),
  0::bigint,
  '(S6) STRUCTURAL: service_role holds zero grants on posting_prototype (no V1 writer needs it; `008`''s explicit-grant posture, not an added revoke)'
);

-- =====================================================================
-- BLOCK ID — the id-space construction (Sec F1's condition; Decision 2 addendum option (B)).
-- =====================================================================

-- (ID1) the disjointness is structural: user_taxonomy's identity maxvalue is strictly below
--   posting_prototype's identity minvalue, read from pg_sequence — true regardless of how many
--   rows either table holds, and RED the moment either bound is widened.
select ok(
  (select ut_seq.seqmax < pp_seq.seqmin
     from pg_sequence ut_seq
     join pg_class ut_c on ut_c.oid = ut_seq.seqrelid
     join pg_sequence pp_seq on true
     join pg_class pp_c on pp_c.oid = pp_seq.seqrelid
    where ut_c.relname = 'user_taxonomy_id_seq' and pp_c.relname = 'posting_prototype_id_seq'),
  '(ID1) STRUCTURAL: user_taxonomy''s identity maxvalue < posting_prototype''s identity minvalue (pg_sequence) — the CONSTRUCTION, not a point-in-time overlap count (an overlap count holds vacuously on a fresh stack; this holds regardless of row count and fails the moment either bound is widened)'
);

-- (ID2) the construction PERMITS carrying a pre-split id byte-exact: insert a low id (below
--   posting_prototype's own minvalue) via `overriding system value` and assert it lands
--   unchanged. This is a synthetic proof that the operation 084's own copy step performs is
--   mechanically sound — NOT a claim to have observed a real historical migration event (a
--   fresh CI stack has zero pre-existing provisioned users, so there is nothing real to move).
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.posting_prototype (id, users_id, cat, sub_cat)
  overriding system value
  values (42, :'ta', 'Revenue', 'ID2-probe');
select ok(
  (select id = 42 and id < (select seqmin from pg_sequence ps join pg_class c on c.oid = ps.seqrelid
                              where c.relname = 'posting_prototype_id_seq')
     from pfin.posting_prototype where users_id = :'ta' and sub_cat = 'ID2-probe'),
  '(ID2) id-preservation CONSTRUCTION: a row inserted with `overriding system value` and an explicit id below posting_prototype''s own reserved range lands with that id UNCHANGED — proves the mechanism 084''s copy step depends on is sound, on a stack with zero real moved rows to observe directly'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK CHK — Decision 4's unconditional cat CHECK, relocated from 009 Block 6 (same
--   assertions, new table — the CHECK's disjunct is gone because the table IS the domain now).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Revenue', 'chk-probe-1') $$, :'ta'),
  '(CHK1) cat=''Revenue'' accepted by the unconditional CHECK'
);
select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Expense', 'chk-probe-2') $$, :'ta'),
  '(CHK2) cat=''Expense'' accepted'
);
select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Transfer', 'chk-probe-3') $$, :'ta'),
  '(CHK3) cat=''Transfer'' accepted'
);
select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Equity', 'chk-probe-4') $$, :'ta'),
  '(CHK4) cat=''Equity'' accepted (028''s GL accounting class — distinct vocabulary from the renamed asset-domain Cat, Decision 7''s (R5) control)'
);
select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Trade', 'chk-probe-5') $$, :'ta'),
  '(CHK5) cat=''Trade'' accepted'
);
select throws_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Income', 'chk-probe-6') $$, :'ta'),
  '23514', null,
  '(CHK6) cat=''Income'' (not an enum member) REJECTED — check_violation, fails closed'
);
select throws_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Groceries', 'chk-probe-7') $$, :'ta'),
  '23514', null,
  '(CHK7) cat=''Groceries'' (not an enum member — this used to be legal on the OLD combined table under the asset-domain disjunct; here there is no disjunct to exempt it) REJECTED'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK R/W — two-tenant isolation, both directions.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.posting_prototype (users_id, cat, sub_cat) values (:'tb', 'Revenue', 'b-row');
select set_config('role', 'postgres', true);

-- (R1) owner (A) reads exactly its own rows (5 CHK accepts + 1 ID2 probe = 6).
select _rls.expect_owner_can_read('pfin.posting_prototype'::regclass, :'ta'::uuid, 6::bigint);

-- (R2) intruder (B reading toward A) sees ZERO of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.posting_prototype'::regclass, :'ta'::uuid, :'tb'::uuid);

-- (W1) B cannot forge users_id=A on an INSERT (WITH CHECK rejects; RLS 42501).
select _rls.expect_cross_tenant_write_blocked(
  :'tb'::uuid,
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Revenue', 'forge-probe') $$, :'ta'),
  '(W1) cross-tenant write fails closed: B cannot INSERT a row with users_id=A (WITH CHECK rejects the forge)'
);

-- (W2) non-vacuous companion: B inserting its OWN row (own tenant) still succeeds — (W1) is
--   mismatch-driven, not a blanket authenticated-INSERT block.
-- ⚠ expect_cross_tenant_write_blocked leaves role=authenticated (intruder context) on exit —
--   it does not self-restore the way _visible_owner_rows does. Restore to postgres before the
--   next _rls.set_tenant call, which needs USAGE on schema _rls (authenticated lacks it).
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select lives_ok(
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat) values (%L, 'Expense', 'w2-control') $$, :'tb'),
  '(W2) non-vacuous control: B inserting its OWN row (own tenant) succeeds — (W1)''s rejection is mismatch-driven, not a blanket block'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK G — anon literally cannot read (corroborates S5 behaviourally).
-- =====================================================================
select set_config('role', 'anon', true);
select throws_ok(
  $$ select count(*) from pfin.posting_prototype $$,
  '42501', null,
  '(G1) anon SELECT on posting_prototype is denied at the ACL (permission denied), corroborating (S5)''s zero-grant catalog read'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
