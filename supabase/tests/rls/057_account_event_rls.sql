-- =====================================================================
-- 057 — pfin.account_event (ADR-042 Decision 5 + 5a): the closure audit surface,
--        Decision-3 instance #16, and the closed-vocabulary bounding claim.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `057`.
-- Sec joint-review-mandatory (ADR-011 D2 immutable/append-only audit-class · D3 family
-- extension #16 · multi-tenant isolation).
--
-- ┌─ WHAT THIS FILE IS REALLY FOR ─────────────────────────────────────────────────────┐
-- │ ADR-042's own drafting produced a document whose BODY reasoned instance #17          │
-- │ (`account_event.linked_source_id`) out of existence — no system-path writer survives │
-- │ the ratified model — while its CONSEQUENCES BLOCK still asserted and COUNTED it,     │
-- │ 43 lines apart. The stale half was the SUMMARY, which is where anyone checks a       │
-- │ ledger. Architect writing `057` from that summary ships #17 and a `detail jsonb`.    │
-- │ (D8a)/(D8b)/(D8c) are column-ABSENCE assertions and they are the mechanical fence on │
-- │ exactly that. A consistency defect in a design doc becomes a schema defect unless    │
-- │ something outside the doc checks it.                                                 │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- LAYER DISCIPLINE — why the #16 fence is genuinely load-bearing at BOTH tiers:
--   account_event's RLS keys on `users_id = auth.uid()`. A row carrying users_id=A and
--   account_id = B's account therefore PASSES the WITH CHECK (its users_id is A's own) and
--   only the matched-tenant fence catches the mismatch. So the fence is the SOLE gate at
--   authenticated, and again at the migration role (RLS-exempt entirely). Both are asserted.
--   A test that only proved "B cannot write A's row" would be testing RLS and reporting it
--   as the fence.
--
-- ┌─ LAYER MAP — WHICH MECHANISM EACH ASSERTION ACTUALLY TARGETS ──────────────────────┐
-- │ Required by Sec 2026-08-03. This file KEEPS the `_rls` suffix because — unlike `058` │
-- │ and `059`, which were renamed to `..._fences.sql` — it genuinely carries RLS. But it │
-- │ is MIXED, and the mix is the hazard: the `#16` fence sits on an RLS-protected table, │
-- │ so an author can write an RLS assertion, watch it pass, and believe the fence is     │
-- │ covered. It is not. FIVE mechanisms live here:                                       │
-- │                                                                                      │
-- │   RLS policies on pfin.account_event   D1a · D1b · D1c                               │
-- │   BEFORE INSERT trigger (#16 fence)    D2a · D2b · D2c                               │
-- │   CHECK constraints (vocabularies)     D4a · D4b · D4c                               │
-- │   Table ACL (no write grant)           D5a · D5b                                     │
-- │   Immutability trigger (cross-tier)    D5c                                           │
-- │   pg_catalog / information_schema      D2d · D3a · D3b · D6a · D6b                   │
-- │                                                                                      │
-- │ THE ONE TO GET RIGHT: D2a runs as `authenticated` and its row PASSES RLS — users_id  │
-- │ is A's own. Only the TRIGGER rejects it. An assertion phrased as an RLS denial there │
-- │ would go green while proving nothing about the fence. See the LAYER DISCIPLINE note. │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- CORRESPONDENCE (Sec's joint-review check): does at least one assertion reference an object
--   existing ONLY in the migration this battery names? YES — `pfin.account_event` and every
--   one of its columns and constraints are created in `057` and exist nowhere earlier, so
--   every assertion in this file fails against `056` and below.
--
-- ┌─ ⚠ MEASURED vs WRITTEN — READ BEFORE QUOTING A COUNT FROM THIS FILE ─────────────┐
-- │ This file's assertions are **WRITTEN, NOT MEASURED**: its migration is not applied │
-- │ to any database I can reach (local stack at `056`; verified `account_event`,       │
-- │ `closed_at` and `account_closure_gate` all ABSENT). **No assertion here has ever   │
-- │ run.** They are authored against the DDL text at a cited ref, which is a weaker    │
-- │ claim than green and must not be aggregated with one.                              │
-- │ Reporting rule adopted 2026-08-03 after Architect flagged that a single total      │
-- │ ("95 assertions") sitting beside a green ("22/22") invites reading all of them as  │
-- │ measured — wrong about 57. **Quote two numbers, never one sum.**                   │
-- │ Same defect as the (B5) it superseded: comparing what I had WRITTEN rather than    │
-- │ what the database SAID. Applied there to an assertion, here to a status report.    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⟦EXPECTED STACK⟧ — READ BEFORE INTERPRETING ANY RESULT FROM THIS FILE ──────────┐
-- │ **A RESULT FROM THIS BATTERY IS UNINTERPRETABLE WITHOUT THE MIGRATION SET IT RAN │
-- │ AGAINST.** A red cannot be distinguished from "this DB predates the change"; a    │
-- │ green cannot be distinguished from "this DB already had it". Report the applied   │
-- │ set alongside the result, every run — `select max(version) from                   │
-- │ supabase_migrations.schema_migrations;`                                           │
-- │                                                                                   │
-- │ EXPECTED STACK: `057`-applied.                                                      │
-- │ pfin.account_event exists with the #16 fence + vocabularies. Below `057` the tab
-- │   le does not exist and every assertion is RED for that reason alone.
-- │                                                                                   │
-- │ ⚠ SECOND STATE VARIABLE, added after it bit us: **WHICH BRANCH / WORKTREE.** A     │
-- │ FILE read is branch-dependent, so "I read the migration" is not a fixed referent   │
-- │ either. Cite migrations by COMMIT REF, never by working-tree path:                 │
-- │   git show <ref>:supabase/migrations/<file>                                        │
-- │ So a claim needs THREE coordinates, not one: DATABASE STATE (this block) +         │
-- │ ARTIFACT REF + the assertion itself. Two of the three bit this review.             │
-- │                                                                                   │
-- │ Convention follows `self209_close_gate.sql`'s ⟦WIRE-VALIDATE⟧ note. Generalized    │
-- │ to every file 2026-08-03 after I reported a pre-`056` database's expected red as   │
-- │ a code defect — the error was mine and this header is the fence on repeating it.   │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants; no PII, no real account
--   numbers (SD-15), no prod data; rolled-back txn; no `supabase db reset`.
--
-- ⟦WIRE-PENDING — ARCH Q1(e)⟧ the #16 raise text is bound once below, by analogy to the
--   `#15` fence at `044`. Rebind there when `057` lands.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

\set m_fence16 '%Decision-3 #16 matched-tenant fence%'

-- plan = 18: D1 3 · D2 4 · D3 2 · D4 3 · D5 3 · D6 2 · D7 1. Recorded so a silent plan-edit is
-- visible in review as an arithmetic change.
select plan(18);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-acct', 'depository', 'household', 'taxable') returning account_id as aacct \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-acct', 'depository', 'household', 'taxable') returning account_id as bacct \gset

insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
  values (:'ta', :aacct, 'closed', 'no_longer_used', 'user:' || :'ta', '2026-06-30');
insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
  values (:'tb', :bacct, 'closed', 'sold', 'user:' || :'tb', '2026-06-30');

-- ⟦VOCABULARY REBOUND at `e88b76c` (ADR-042 Amendment 1, F/CTO-ratified): reason_code
--   `closed` is RENAMED to `no_longer_used`, and `institution_closed` is NEW. Six values:
--   no_longer_used | sold | transferred_out | duplicate | institution_closed | other.
--   ⚑ Every fixture row here used `reason_code = 'closed'` and would now FAIL THE CHECK —
--     five sites, corrected. Note event_type STAYS 'closed'; only reason_code renamed, and
--     the two are adjacent in every VALUES list, which is exactly how a blind rename would
--     have broken the event_type vocabulary instead. Changed by counting sites first.⟧
--
-- ┌─ ⚠ WHAT THIS BATTERY STRUCTURALLY CANNOT PROVE ──────────────────────────────────┐
-- │ **Nothing in this file can establish that anything ever WRITES pfin.account_event.**│
-- │ Every assertion below inserts its OWN rows and then checks the table's PROPERTIES — │
-- │ RLS isolation, the #16 fence, the vocabularies, immutability. **All of that goes    │
-- │ green forever against a table no production path writes**, because THE FIXTURE IS   │
-- │ THE WRITER. A table's own battery cannot prove the table is reached.                │
-- │                                                                                     │
-- │ REACHABILITY IS ASSERTED ELSEWHERE, in the would-be writer's battery:                │
-- │   `058_account_closure_fences.sql` (B1b) — closing an account produces a row         │
-- │   `058_account_closure_fences.sql` (B9b) — reopening produces one too                │
-- │ Those drive the gated control and assert a row appears. As of `2cd4457` they are the │
-- │ only assertions in the whole set that FAIL, because nothing writes this table yet.   │
-- │                                                                                     │
-- │ ⚑ THIS NOTE EXISTS BECAUSE THE ABSENCE WAS FOUND TWICE AND ALMOST WRITTEN TWICE.     │
-- │   Coverage did not fail — DISCOVERABILITY did. Sec independently derived (B1b) as a  │
-- │   required addition while it already existed, because anyone auditing account_event  │
-- │   coverage reads THIS file and finds only property tests. Without this pointer the   │
-- │   next auditor concludes there is a gap, or writes a duplicate.                      │
-- │   General form (Architect): **a battery should state what it structurally cannot     │
-- │   prove.** Queued for tests/rls/DESIGN.md alongside the other three lessons.         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- =====================================================================
-- D1 — TWO-TENANT ISOLATION (the standing per-Wave battery obligation)
-- =====================================================================
select _rls.expect_owner_can_read('pfin.account_event'::regclass, :'ta'::uuid, 1::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.account_event'::regclass, :'ta'::uuid, :'tb'::uuid);
select _rls.set_tenant(:'tb'::uuid);
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'user:%s', '2026-06-30') $$, :'ta', :aacct, :'ta'),
  'new row violates row-level security policy%for table "account_event"',
  '(D1c) cross-tenant INSERT: B forging users_id=A is rejected by the account_event INSERT WITH CHECK — an RLS-policy violation specifically, not an incidental 42501'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- D2 — DECISION-3 INSTANCE #16 (account_event.account_id matched-tenant fence)
--   The fence's justification, stated per ADR-042's own symmetric rule ("every exemption
--   states what makes it safe; every fence states what makes it necessary"): the one-time
--   remediation path writes as the MIGRATION ROLE, which is RLS-exempt and could write a
--   mismatched (account_id, users_id) pair. #16 catches exactly that. If that writer ever
--   disappears, #16's necessity should be re-derived — the failure mode ADR-042 names as
--   "a requirement outliving its own precondition".
-- =====================================================================

-- (D2a) AUTHENTICATED tier: users_id=A (passes RLS — it IS A's own tenant) + account_id =
--   B's account. RLS admits this row; ONLY the fence rejects it.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'user:%s', '2026-06-30') $$, :'ta', :bacct, :'ta'),
  :'m_fence16',
  '(D2a) #16 TEETH at authenticated: users_id=A + account_id=B''s account RAISES the fence. This row PASSES RLS (its users_id is A''s own), so the fence is the SOLE gate here — a test asserting only "B cannot write A''s row" would be testing RLS and reporting it as the fence'
);
select set_config('role', 'postgres', true);

-- (D2b) MIGRATION-ROLE tier — the writer #16 actually exists for. RLS-exempt entirely.
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'system:remediation', '2026-06-30') $$, :'ta', :bacct),
  :'m_fence16',
  '(D2b) #16 TEETH at the MIGRATION ROLE (RLS-exempt): the same mismatched pair RAISES. This is the writer the fence exists for per ADR-042 D5a — the one-time remediation script runs privileged and is gated by nothing else'
);

-- (D2c) NON-VACUOUS: the matched pair SUCCEEDS at the privileged tier.
select lives_ok(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'sold', 'system:remediation', '2026-06-30') $$, :'ta', :aacct),
  '(D2c) NON-VACUOUS: a MATCHED (users_id=A, account_id=A''s) pair succeeds privileged -> (D2a)/(D2b) are mismatch-driven, not a blanket privileged-write block'
);

-- (D2d) #16 is the ONLY new D3 instance. #17 (`linked_source_id`) is NOT created: its
--   misroute-prevention justification depended on a system-path writer and the ratified
--   model removed every one. This is the assertion that catches `057` being written from
--   the ADR's stale Consequences block.
select hasnt_column('pfin', 'account_event', 'linked_source_id',
  '(D2d) #17 IS NEVER CREATED: account_event has NO linked_source_id column. ADR-042''s body reasoned it out of existence while its Consequences block still counted it — this assertion is the fence on Architect building from the stale summary. An unused fenced column is an attractive nuisance: it looks authoritative and someone eventually populates it, at which point the fence validates tenant-match but not meaning');

-- =====================================================================
-- D3 — THE BOUNDING CLAIM, ASSERTED AS STATED RATHER THAN AS HOPED
--   ADR-042 D5: "no free-form string anywhere" is FALSE and would mislead the next
--   reviewer. Post-D5a (`provider_event_id` dropped — no provider event drives a closure
--   event) the honest claim becomes unconditional: every text column is a closed vocabulary.
-- =====================================================================

-- (D3a) NO `detail jsonb`. The column was adopted from `015:453`'s sync-audit precedent
--   WITHOUT its condition — jsonb's condition is VARIABLE SHAPE, and closure events carry a
--   fixed, small, closed set of facts. Its allowlist constrained TYPE, not CONTENT
--   (`jsonb_typeof(detail->'k') in ('string',...)` admits an arbitrarily long string), so
--   with reason_code closed it was the only remaining path for unbounded content into a
--   permanent, user-readable, append-only record.
select hasnt_column('pfin', 'account_event', 'detail',
  '(D3a) NO `detail jsonb`: the escape hatch the closed `reason_code` vocabulary exists to shut, still open one column over. Also removes the "omission-passes" hole — a writer unable to express its provenance omitted `detail` and the row landed CLEAN, with no provenance, looking like it worked');

-- (D3b) EVERY text column is covered by a CHECK. This is the assertion that catches a
--   free-text column being added LATER, which is the realistic failure — the next person
--   needing somewhere to put a string finds nowhere, unless someone added one.
select is(
  (select count(*)::int
     from information_schema.columns c
    where c.table_schema = 'pfin' and c.table_name = 'account_event'
      and c.data_type = 'text'
      and not exists (
        select 1 from pg_constraint con
          join pg_class cl on cl.oid = con.conrelid
          join pg_namespace n on n.oid = cl.relnamespace
         where n.nspname = 'pfin' and cl.relname = 'account_event'
           and con.contype = 'c'
           and pg_get_constraintdef(con.oid) like '%' || c.column_name || '%')),
  0,
  '(D3b) EVERY text column on account_event is bound by a CHECK constraint — the bounding claim in its honest form. Goes RED the moment an unconstrained text column is added, which is the realistic future failure: a widened event_type whose provenance needs somewhere to go'
);

-- =====================================================================
-- D4 — CLOSED VOCABULARIES HAVE TEETH (three columns, three assertions)
--   Asserted per-column rather than once: a single CHECK covering all three would make the
--   three indistinguishable and one broken vocabulary would hide behind the other two.
-- =====================================================================
select throws_ok(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'not-a-reason', 'system:remediation', '2026-06-30') $$, :'ta', :aacct),
  '23514',
  null,
  '(D4a) reason_code is a CLOSED vocabulary: an out-of-vocabulary value is rejected by CHECK. No free text anywhere on this surface — and no `other` + "please specify", which reintroduces the unredactable-PII problem while LOOKING like a closed vocabulary'
);
select throws_ok(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor)
              values (%L, %s, 'not-an-event', 'closed', 'system:remediation') $$, :'ta', :aacct),
  '23514',
  null,
  '(D4b) event_type is a CLOSED vocabulary. NOTE: widening it is Sec-joint-review-MANDATORY, not a routine ALTER — SD-25''s tier, the read posture, and §4.6 indefinite retention were all calibrated for closure events specifically, and SD-25 rates WHAT THE CHECK ADMITS, not what the table is named'
);
-- (D4c) `actor` is DISCRIMINATED: `user:<uid>` / `system:<source>`, never a bare uid that
--   means "system" when null. Absence is not a value — the ADR-011 D1(d) detectability class.
select throws_ok(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', %L, '2026-06-30') $$, :'ta', :aacct, :'ta'),
  '23514',
  null,
  '(D4c) `actor` is DISCRIMINATED: a BARE uid is rejected — it must be `user:<uid>` or `system:<source>`. A bare uid, or a NULL meaning "system", makes "we did not record the actor" indistinguishable from "the actor was the system" on a permanent audit record'
);

-- =====================================================================
-- D5 — APPEND-ONLY / IMMUTABLE (ADR-011 D2 audit-class)
--   Precedents: `015` linked_source_state_history, `031` reclass_history. Asserted at BOTH
--   tiers because they fail by DIFFERENT mechanisms: authenticated at the ACL (no grant),
--   service_role at the immutability TRIGGER (RLS-bypass is not trigger-bypass, `004:165`).
--   Collapsing them into one assertion would leave whichever tier is unasserted unproven.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ update pfin.account_event set reason_code = 'sold' $$,
  'permission denied for table account_event',
  '(D5a) authenticated UPDATE fails closed at the TABLE ACL — audit-class rows are append-only; a closure record is a historical fact'
);
select throws_like(
  $$ delete from pfin.account_event $$,
  'permission denied for table account_event',
  '(D5b) authenticated DELETE fails closed at the TABLE ACL'
);
select set_config('role', 'postgres', true);
-- Hold the ACL open to service_role so the TRIGGER — not a missing grant — is the sole
-- gate (the `self209` (b3)/(b4) grant-then-trigger pattern). Rolled back with the txn.
grant usage on schema pfin to service_role;
grant update, delete on pfin.account_event to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  $$ update pfin.account_event set reason_code = 'sold' $$,
  '%immutable%',
  '(D5c) CROSS-TIER: service_role UPDATE is blocked by the immutability TRIGGER with the ACL deliberately held OPEN -> the fence is the trigger, not the absent grant. RLS-bypass does not bypass a trigger'
);

-- (D7) THE INDEX CARRIES `nulls last` — queued at the measurement, landed at `9e16a5a`.
--   MEASURED (two independent runs, 20k and 5k rows, ANALYZEd, enable_seqscan=off):
--     index (account_id, effective_date desc)            -> `desc nulls last` query SORTS
--     index (account_id, effective_date desc nulls last) -> Index Only Scan
--   Each index shape serves exactly ONE ordering, so this is a trade, not a free fix — and
--   it is decidable because plain `desc` returns the WRONG ROW: with a closure dated
--   2026-02-20 and a NULL-dated reopen, `desc` returns the reopen. The ordering that gives
--   up its index is the one nobody should write.
--   ⚑ WHY THIS NEEDS A TEST AT ALL: the property has a SILENT failure mode. Rebuild the
--     index without `nulls last` and nothing goes red — the latest-event query returns a
--     wrong row with a sort node attached, and a sort node reads as a performance
--     characteristic rather than a correctness signal.
--   ⚑ AND IT IS THE STRUCTURAL HALF OF A TWO-PART FIX. The column comment is the procedural
--     half ("ANY latest-event lookup MUST use nulls last") and depends on someone reading
--     it. This assertion depends on nobody.
select ok(
  (select indexdef like '%effective\_date DESC NULLS LAST%' escape '\'
     from pg_indexes where schemaname = 'pfin' and indexname = 'account_event_account_idx'),
  '(D7) account_event_account_idx is declared (account_id, effective_date DESC NULLS LAST). Without it a `desc nulls last` latest-event lookup silently acquires a Sort, and a plain `desc` lookup returns a NULL-dated reopen ahead of every dated event. Measured independently by QA and team-lead at 20k and 5k rows. RED means the index was rebuilt without the qualifier — fix the index, never this assertion'
);

-- =====================================================================
-- D6 — POSTURE
-- =====================================================================
select set_config('role', 'postgres', true);
-- (D6a) the event fires in BOTH directions (close AND reopen and closed->cleared), while
--   the GATE fires into-closed only. Asserted structurally on the trigger's WHEN clause,
--   because a one-directional audit trail loses every reopen — and reopen is the correction
--   path the whole reject-all fence design depends on being visible.
select ok(
  (select count(*)::int from pg_trigger t
     join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'account' and not t.tgisinternal
      and pg_get_triggerdef(t.oid) like '%closed_at IS DISTINCT FROM%') >= 1,
  '(D6a) the audit trigger fires on `closed_at IS DISTINCT FROM old.closed_at` — BOTH directions (close, reopen, and clears), while the GATE fires into-closed only. A one-directional trail loses every reopen, which is the correction path reject-all depends on being visible'
);
-- (D6b) authors no SECURITY DEFINER function.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.prosecdef
       and p.proname not in ('fn_refresh_updated_at', 'fn_grant_creator_access', 'fn_reclass_history_insert')),
  0,
  '(D6b) `057` authors ZERO SECURITY DEFINER functions -> the allowlist stays at its 3 authored entries; any escalation here is a Sec-joint-review ledger event, not a free ALTER'
);

select * from finish();
rollback;
