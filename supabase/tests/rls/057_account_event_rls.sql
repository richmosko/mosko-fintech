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
-- LAYER DISCIPLINE — why the #16 fence is load-bearing, and AT WHICH TIER:
--   account_event's RLS keys on `users_id = auth.uid()`. A row carrying users_id=A and
--   account_id = B's account therefore PASSES the WITH CHECK (its users_id is A's own) and
--   only the matched-tenant fence catches the mismatch. A test that only proved "B cannot
--   write A's row" would be testing RLS and reporting it as the fence.
--   ⚑⚑ CORRECTED 2026-08-04 — THIS PARAGRAPH USED TO SAY "SO THE FENCE IS THE SOLE GATE AT
--     AUTHENTICATED", AND THAT IS NOW FALSE. `057`'s Amendment-3 F2 fence
--     (`account_event_block_direct_insert`) sorts alphabetically BEFORE
--     `account_event_matched_account` and refuses every non-owner INSERT, so **#16 no longer
--     evaluates at the authenticated tier at all.** Its behavioural proof is (D2b)/(D2c) at
--     the OWNER tier — which is the RLS-exempt migration-role remediation writer #16 was
--     justified for in the first place, so the fence still has exactly one live justification
--     and one live proof. Coverage NARROWED, not lost.
--     Corrected rather than deleted because the stale form is the most misleading sentence
--     this file could carry: a standing argument for a fence at a tier where it is inert.
--
-- ┌─ LAYER MAP — WHICH MECHANISM EACH ASSERTION ACTUALLY TARGETS ──────────────────────┐
-- │ Required by Sec 2026-08-03. This file KEEPS the `_rls` suffix because — unlike `058` │
-- │ and `059`, which were renamed to `..._fences.sql` — it genuinely carries RLS. But it │
-- │ is MIXED, and the mix is the hazard: the `#16` fence sits on an RLS-protected table, │
-- │ so an author can write an RLS assertion, watch it pass, and believe the fence is     │
-- │ covered. It is not. FIVE mechanisms live here:                                       │
-- │                                                                                      │
-- │   RLS policies on pfin.account_event   D1a · D1b                                     │
-- │   BEFORE INSERT #16 (matched-tenant)   D2b · D2c        ← OWNER TIER ONLY, see below │
-- │   BEFORE INSERT F2 (wrong-origin)      D1c · D1e · D1f · D2a                         │
-- │   CHECK constraints (vocabularies)     D4a · D4b · D4c                               │
-- │   Table ACL (no write grant)           D5a · D5b                                     │
-- │   Immutability trigger (cross-tier)    D5c                                           │
-- │   pg_catalog / information_schema      D1d · D1d2 · D1g · D2d · D3a · D3b · D4d ·    │
-- │                                        D6a · D6b                                     │
-- │                                                                                      │
-- │ ⚑ THE TWO BEFORE INSERT TRIGGERS ARE ORDERED BY NAME, AND THE ORDER IS THE MAP.      │
-- │   `account_event_block_direct_insert` sorts before `account_event_matched_account`,  │
-- │   so at `authenticated` the F2 fence fires and #16 NEVER EVALUATES. Every            │
-- │   authenticated row above therefore targets F2, whatever it forges. #16 is reachable │
-- │   only where F2 exempts — the table OWNER — which is why its whole behavioural proof  │
-- │   is (D2b)/(D2c). Rename either trigger and this entire column silently re-points.   │
-- │                                                                                      │
-- │ THE ONE TO GET RIGHT: an assertion here phrased as an RLS denial would go green      │
-- │ while proving nothing about either trigger — RLS WITH CHECK is evaluated AFTER both  │
-- │ BEFORE ROW triggers and is unreachable at this tier. See the LAYER DISCIPLINE note.  │
-- │                                                                                      │
-- │ ⚑ AND A SECOND AXIS, added after Sec's F1 veto 2026-08-04. This map organises by      │
-- │   MECHANISM, which is what it is for — but every authenticated-tier row in it probes  │
-- │   the CROSS-TENANT axis, and the map's own completeness made that invisible. The      │
-- │   matched-tenant ACTOR forge (D1e) needed no cross-tenant step and had no assertion   │
-- │   at any tier while this file read 15/15 green. **BEFORE ADDING A CASE, ask which     │
-- │   AXIS it probes as well as which mechanism it targets** — a map with one axis        │
-- │   reports coverage of the tier.                                                       │
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

\set m_fence16 '%Decision 3 #16 matched-tenant fence%'
-- ⟦WIRE-BOUND 2026-08-04 against `fn_account_event_block_direct_insert` (ADR-042 Amendment 3
--   F2). Distinct from m_fence16 on purpose: both are BEFORE INSERT triggers on this table and
--   Architect made the messages distinguishable precisely so a battery can say WHICH fired.
--   ⚑ REBOUND TWICE IN ONE SESSION, and the second time is the lesson. First bound while the
--     trigger was named `account_event_origin_fence`, which sorts AFTER
--     `account_event_matched_account`, so a mismatched pair met #16 first. Architect then
--     RENAMED it to `account_event_block_direct_insert` — which sorts BEFORE `m` — precisely
--     to invert that order, and pre-announced the resulting (D1c)/(D2a) red in `057`'s own
--     header. **TRIGGER NAMES ARE FIRING ORDER, NOT LABELS.** A rename with no behavioural
--     intent silently re-points every assertion that matched on a message, and it re-points
--     them to something that still raises — so they fail with a plausible message rather than
--     an obviously broken one. Measured here: two assertions flipped fence mid-session with no
--     edit to either battery or fence logic.⟧
\set m_direct  '%rejects direct INSERT%written ONLY by the account_event_write trigger%'

-- plan = 24: D1 8 (3 + D1d/D1d2 declarative policy pair + D1e/D1f/D1g, the Amendment-3 forge
-- trio) · D2 4 · D3 2 · D4 4 (+D4d vocabulary pin) · D5 3 · D6 2 · D7 1. Recorded so a silent
-- plan-edit is visible in review as an arithmetic change.
select plan(24);

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
-- (D1c) ⚑ REBOUND AND RENAMED. It asserted an RLS-POLICY denial; it gets the #16 fence, and
--   THE RLS PATTERN CAN NEVER MATCH. Postgres applies a policy's WITH CHECK *after* BEFORE ROW
--   triggers, and #16 is INVOKER — running as B, A's account row is INVISIBLE, so its
--   NOT EXISTS is true and it raises first.
--   ⚑ THIS IS THE MIRROR IMAGE OF THE HAZARD THIS FILE'S LAYER MAP ALREADY CAUGHT for (D2a):
--     there, an assertion phrased as an RLS denial would have gone green while proving nothing
--     about the fence. Here it goes red for the same underlying reason. Same defect, opposite
--     symptom — which is why it survived longer.
--   ⚠ AND THE POLICY IS BEHAVIOURALLY UNPROVABLE AT authenticated, BY CONSTRUCTION — not
--     merely untested. Reaching the WITH CHECK requires an (account_id, users_id) pair that is
--     both MATCHED and VISIBLE; a forged cross-tenant pair can never be both. The aal2 route
--     fails identically: account_select carries the character-identical conjunct, so an
--     aal1 session under mfa_policy='totp' cannot see its own account either and #16
--     intercepts again. NO ROW EXISTS THAT PASSES #16 AND FAILS THE POLICY.
--     So the policy is proven DECLARATIVELY below — the honest instrument when the
--     behavioural one is unreachable, and the idiom this file already uses for D3a/D3b/D6a/D6b.
--   ⚑ COROLLARY, AND IT IS A FINDING RATHER THAN A NOTE: #16'S FAIL-CLOSED DEPENDS ON RLS.
--     Invisibility is what makes its NOT EXISTS true — the layers are NOT independent in the
--     direction this battery assumed. If account_select ever gains a broader read predicate
--     (V2 sharing, rd_access), #16 STOPS RAISING on a cross-tenant forge and the RLS WITH
--     CHECK silently becomes the only fence. That is BACKLOG §7.7's V2-grantee / rd_access
--     class, on a surface nobody has filed it against.
--     ADR-042's symmetric rule says every fence states what makes it NECESSARY; this one must
--     also state what makes it SUFFICIENT, because it borrows that from somewhere else.
--
-- ⚑⚑ REBOUND A SECOND TIME, 2026-08-04 — ARCHITECT'S PRE-ANNOUNCED DESIGNED RED, ACCEPTED.
--   `057` renamed the F2 fence `account_event_origin_fence` -> `account_event_block_direct_
--   insert`, which sorts BEFORE `account_event_matched_account`, so a direct POST now meets
--   the WRONG-ORIGIN fence before the CROSS-TENANT one. Architect states the intent in the DDL
--   ("#16 should not be what a direct POST hits first — it would report a tenant defect for
--   what is really a wrong-origin write") and pre-announced this exact red, ruling that **the
--   expectations get renamed, not the trigger.** Accepted: ordering the DDL around a test's
--   convenience is backwards, and the new diagnosis is the more accurate one.
--   ⚠ SEC'S "LEAVE D1c AS IT IS" RULING WAS MADE AGAINST THE PRIOR ORDERING AND IS SUPERSEDED
--     BY A LATER DDL CHANGE — flagged rather than quietly worked around. An approval names a
--     REF, not a readiness; this rebind is a ruled delta on top of it, not a reopening of it.
--   ⚑ AND THE REAL CONSEQUENCE, WHICH IS A COVERAGE CHANGE AND NOT A RENAME: **NO DIRECT
--     authenticated INSERT REACHES #16 ANY MORE.** The direct-insert fence refuses every
--     non-owner, non-trigger INSERT before #16 evaluates, so no direct probe can reach it —
--     not this one, not (D2a), not any future one. #16's behavioural proof is now (D2b)/(D2c)
--     at the OWNER tier. So coverage is NARROWED, not lost, and the file's LAYER DISCIPLINE
--     note above — "the fence is the SOLE gate at authenticated" — is now FALSE as written and
--     is corrected there. Left uncorrected it would be the most misleading sentence in the
--     file: an argument for a fence that no longer participates on that path.
--   ⚠⚠ AND #16 IS NOT REDUNDANT — READ THIS BEFORE PROPOSING THE CONSOLIDATION, BECAUSE THE
--     RENAME MAKES IT MORE TEMPTING, NOT LESS. Architect's correction to my first draft of this
--     note, and they are right: I wrote that #16's only surviving reach is the migration-role
--     remediation. **It is TWO writers, not one.** The origin fence admits (a) the table OWNER
--     and (b) anything at `pg_trigger_depth() >= 2` — i.e. the ORDINARY PRODUCTION PATH,
--     `fn_account_event_write` firing on every close and reopen. Both then meet #16, which is
--     INVOKER and still validates the tenant pair on each. So #16 guards the live writer AND
--     the remediation — almost exactly the writers Decision 5a justified it by.
--     **A fence that now fires on fewer paths is not a fence that matters less**; it fires on
--     precisely the paths that can write, and it is the only tenant-pair check on either.
--     Two BEFORE INSERT triggers on one small table will read as duplication to someone later.
--     They cover DISJOINT cases and neither substitutes for the other — `057`'s own catalog
--     comment says so, and this is the battery-side copy of that refusal.
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'user:%s', '2026-06-30') $$, :'ta', :aacct, :'ta'),
  :'m_direct',
  '(D1c) cross-tenant direct POST FAILS CLOSED AT THE WRONG-ORIGIN FENCE (rebound twice — see the block above): B forging users_id=A is refused by account_event_block_direct_insert, which sorts first and therefore diagnoses the write as wrong-ORIGIN rather than wrong-TENANT. That is deliberate and is the more accurate diagnosis. #16 still holds the cross-tenant property but no longer participates at authenticated — see (D2b)/(D2c) for its surviving behavioural proof'
);
select set_config('role', 'postgres', true);

-- (D1d) THE POLICY ITSELF, asserted DECLARATIVELY because (D1c) shows it is behaviourally
--   unreachable at authenticated. This is what stops the rebind above from quietly reducing
--   coverage: the fence is proven by behaviour, the policy by catalog, and neither is assumed
--   from the other.
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'pfin' and tablename = 'account_event'
      and policyname = 'account_event_insert' and cmd = 'INSERT'
      and with_check like '%users_id = auth.uid()%'),
  1,
  '(D1d) DECLARATIVE: the account_event_insert policy exists, is scoped to INSERT, and its WITH CHECK binds users_id to auth.uid(). RED if the tenant binding were dropped or loosened — the case (D1c) structurally cannot reach, since #16 intercepts every forged pair first'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'pfin' and tablename = 'account_event'
      and policyname = 'account_event_insert'
      and with_check like '%aal2%'),
  1,
  '(D1d2) DECLARATIVE: the same policy still carries the 025 aal2 step-up conjunct. Behaviourally unreachable for the same reason — an aal1 session under a totp policy cannot see its own account, so #16 raises before the conjunct is evaluated'
);

-- (D1e)/(D1f) ⚑⚑ THE MATCHED-TENANT ACTOR FORGE — Sec veto F1, 2026-08-04.
--   ⚑ WHY THIS FILE WAS 15/15 GREEN WHILE THE SURFACE WAS WIDE OPEN, stated as the finding
--     rather than as an apology, because the SHAPE is what generalises:
--     every authenticated-tier assertion in this file probes the CROSS-TENANT axis — (D1c)
--     forges users_id, (D2a) forges account_id. Both are caught, by #16, and their green
--     reads as "the authenticated tier is covered". IT IS NOT. The forge that needs NO
--     cross-tenant step — A writing A's OWN account with a SYSTEM actor — had no assertion
--     at any tier. **A battery organised around one axis reports coverage of the tier.**
--     Same family as `a battery cannot prove it is reached`: the missing case is invisible
--     from inside the set of cases that exist.
--
--   THE HOLE, verified leg by leg against the DDL as merged:
--     · pfin is Data-API-exposed and `authenticated` holds INSERT on account_event (057).
--     · `account_event_insert`'s WITH CHECK mentions `actor` ZERO times — it binds users_id
--       and the aal2 conjunct, nothing else.
--     · #16 PASSES: the pair is matched; it is the tenant's own account.
--     · `account_event_actor_check` PASSES: 'system:remediation' is IN the vocabulary — the
--       CHECK bounds the SHAPE of the string, never its RELATIONSHIP to the session.
--     -> the row LANDS, permanently, on an append-only table with no redaction path, and it
--        attributes a user's action to the system. (D4c) is not this assertion: it rejects a
--        BARE uid, i.e. a malformed actor. This one is WELL-FORMED and FALSE.
--
--   ⚑⚑ FIRST DRAFT WENT GREEN FOR THE WRONG REASON, AND THE PAIR IS WHAT CAUGHT IT — recorded
--     because it is a live instance of DESIGN.md rule 4 rather than a restatement of it.
--     (D1e) was first written MECHANISM-AGNOSTIC (`throws_ok(sql, null, null, …)`) on the
--     reasoning that naming a SQLSTATE would encode whichever fix landed. Measured: it PASSED
--     on the first run — not because actor binds to the session, but because Architect's F2
--     ORIGIN FENCE had already landed and refuses EVERY direct authenticated INSERT whatever
--     the actor says. **An "any exception" assertion cannot distinguish the fence it is about
--     from a fence that refuses everything.** Its companion went red simultaneously, and the
--     disagreement between two independently-derived results is the only thing that exposed it.
--     So these are now bound to the ORIGIN FENCE MESSAGE: this file's own layer discipline
--     already requires an assertion to identify WHICH mechanism fired, and Architect made the
--     two BEFORE-INSERT messages distinguishable for exactly that.
--
--   ⚠ WHERE EACH OF SEC'S TWO FIXES IS ACTUALLY PROVEN, because they are not proven in the
--     same place and assuming otherwise is how one of them goes unwatched:
--       F2 (origin fence, a BEFORE trigger)      -> BEHAVIOURALLY, by (D1e)/(D1f).
--       F1 (the `actor = 'user:' || auth.uid()`  -> DECLARATIVELY, by (D1g). A policy's
--           WITH CHECK conjunct)                    WITH CHECK is evaluated AFTER BEFORE ROW
--                                                   triggers, so with F2 in place NO authenticated
--                                                   INSERT ever reaches it. It is unreachable by
--                                                   construction — the same structural situation
--                                                   as (D1c)/(D1d), one fence over.
--   ⚑ AND THAT IS THE THIRD INSTANCE IN THIS FILE OF ONE FENCE BORROWING ITS SUFFICIENCY FROM
--     ANOTHER (#16 from RLS; F1 from F2). If F2 were ever removed as "belt and braces", F1
--     becomes the sole fence on the forge — and F1 is behaviourally unprovable here, so (D1g)
--     would be the only thing watching it. Neither may be deleted on the strength of the other.
--   NON-VACUITY: the table is demonstrably writable by its permitted writer — see (D2c), which
--     inserts a matched pair as the OWNER and succeeds. Cross-referenced rather than duplicated,
--     per the discoverability corollary; (D1e)/(D1f) are refusals and prove nothing on their own
--     about whether the audit surface still works.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'system:remediation', '2026-06-30') $$, :'ta', :aacct),
  :'m_direct',
  '(D1e) CORROBORATING ONLY — the matched-tenant actor forge is REFUSED, BY THE WRONG-ORIGIN FENCE (F2), which refuses it WITHOUT EVER CONSULTING THE ACTOR. ⚠ THIS ASSERTION PROVES NOTHING ABOUT F1''s ACTOR BINDING; (D1g) is what proves that, declaratively, and this one would stay green if F1''s conjunct were deleted tomorrow. Kept because it fixes the forge''s REACHABILITY in place: every other layer admits this row — #16 passes (the pair really is matched), the tenant conjunct passes (it really is their uid), and account_event_actor_check passes (the value IS in the vocabulary; that CHECK bounds the string''s SHAPE, never its RELATIONSHIP to the session). Before F1+F2 it LANDED, permanently, on an append-only table with no redaction path'
);
-- (D1f) THE REFUSAL IS ORIGIN-BASED, NOT ACTOR-VALUE-BASED — a strictly stronger property than
--   the veto asked for, and the assertion that replaced my broken companion. An actor-VALUE
--   fence would refuse 'system:remediation' and admit any other well-formed-but-false actor;
--   an ORIGIN fence refuses the whole caller-supplied route, so there is no actor string that
--   buys a direct write. Proven by driving the SAME insert with a LEGITIMATE own-uid actor and
--   asserting it hits the SAME fence.
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'sold', 'user:%s', '2026-06-30') $$, :'ta', :aacct, :'ta'),
  :'m_direct',
  '(D1f) ⭐ THE WRONG-ORIGIN FENCE''S OWN NON-VACUITY PROOF, and the only assertion in this file that isolates it. A MATCHED pair for the caller''s OWN account with a CORRECT actor passes #16, would pass every WITH CHECK conjunct, and is refused by NOTHING ELSE — so the fence is the sole possible cause and this is the assertion that shows it FIRES rather than merely existing. It doubles as the proof the refusal is ORIGIN-based and not an actor-VALUE blocklist: no caller-supplied actor buys a direct write, because a state transition is recorded BY THE TRANSITION. RED here with (D1e) green means the fence was narrowed to a blocklist, which admits every well-formed-but-false actor not on it'
);
select set_config('role', 'postgres', true);
-- (D1g) F1's ACTOR CONJUNCT, proven DECLARATIVELY — the only instrument available, because F2
--   intercepts every authenticated INSERT before any WITH CHECK is evaluated. Sec ruled this
--   the honest form for (D1d); it is the same situation and the same answer.
--   ⚑ ASSERTED ON THE BINDING, NOT ON THE STRING: what must hold is that actor is tied to
--     auth.uid(). RED if the conjunct is dropped or loosened — which is the change that would
--     matter the moment F2 is ever relaxed or a second writer trigger is added to pfin.account.
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'pfin' and tablename = 'account_event'
      and policyname = 'account_event_insert' and cmd = 'INSERT'
      and with_check like '%actor%auth.uid()%'),
  1,
  '(D1g) SEC F1 DECLARATIVE: account_event_insert''s WITH CHECK binds `actor` to auth.uid(). This is the conjunct Sec''s veto asked for, and it can ONLY be proven from the catalog — F2''s BEFORE INSERT trigger refuses every authenticated INSERT before Postgres evaluates any WITH CHECK, so no behavioural probe can reach it. RED means the identity binding was dropped: harmless while F2 stands, and the entire fence the moment it does not'
);

-- =====================================================================
-- D2 — DECISION-3 INSTANCE #16 (account_event.account_id matched-tenant fence)
--   The fence's justification, stated per ADR-042's own symmetric rule ("every exemption
--   states what makes it safe; every fence states what makes it necessary"): the one-time
--   remediation path writes as the MIGRATION ROLE, which is RLS-exempt and could write a
--   mismatched (account_id, users_id) pair. #16 catches exactly that. If that writer ever
--   disappears, #16's necessity should be re-derived — the failure mode ADR-042 names as
--   "a requirement outliving its own precondition".
-- =====================================================================

-- (D2a) ⚑ REBOUND 2026-08-04 WITH (D1c) — Architect's pre-announced designed red.
--   It asserted "#16 TEETH at authenticated". **THAT CLAIM IS NO LONGER TRUE OF ANY PROBE**:
--   account_event_block_direct_insert sorts first and refuses every non-owner INSERT, so #16
--   never evaluates at this tier. Rebinding the pattern without renaming the assertion would
--   have been the worse outcome — a green labelled "#16 TEETH at authenticated" while #16 was
--   not consulted, which is precisely the failure this file's LAYER MAP was written to prevent
--   (an assertion reporting one mechanism while a different one does the work).
--   ⚑ WHAT IT PROVES NOW, and it is worth keeping rather than deleting: the SAME cross-tenant
--     pair that (D1c) drives from B's session is here driven from A's OWN session — the two
--     differ in WHOSE session forges, which used to select which #16 branch fired. Both now
--     land on the origin fence, and asserting that they BOTH do is what shows the fence is
--     origin-based rather than tenant-sensitive: it does not care who is asking.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_event (users_id, account_id, event_type, reason_code, actor, effective_date)
              values (%L, %s, 'closed', 'no_longer_used', 'user:%s', '2026-06-30') $$, :'ta', :bacct, :'ta'),
  :'m_direct',
  '(D2a) WRONG-ORIGIN REFUSAL IS TENANT-BLIND (renamed from "#16 TEETH at authenticated", which is no longer true of any probe): A''s own session POSTing a row for B''s account is refused by account_event_block_direct_insert — the same fence, and the same message, as (D1c) driving the mirror-image forge from B''s session. The refusal does not depend on who is asking or on which tenant the pair belongs to. #16''s teeth are now proven ONLY at the owner tier — (D2b)/(D2c)'
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

-- (D4d) ⚑ THE VOCABULARY PIN — ADR-042 B3 sub-decision 2, Sec F9 2026-08-04.
--   `reason_code` has THREE representations: this CHECK, `CLOSURE_REASONS` in
--   `api/src/lib/schemas/account-constants.ts`, and the picker built from it. Architect ruled
--   it is deliberately NOT re-validated inside `fn_close_account` — that would be a FOURTH.
--   With no fourth copy, the CHECK is the single enforcement point and this is the only thing
--   holding the other two to it.
--
--   ⚑ THE DIRECTION IS THE WHOLE POINT (Sec): **a value the picker offers and the CHECK
--     rejects fails loudly — a user hits an error. A value the CHECK ADMITS and the picker
--     OMITS is INVISIBLE.** Nothing breaks; the option simply never appears, and the
--     vocabulary quietly narrows to whatever the UI happens to list. That asymmetry is why
--     the pin belongs on the ADMITTED SET rather than on the picker: widening the CHECK is
--     the move that has no natural failure mode, so it needs the one that is not natural.
--
--   ⚑ DERIVED, NOT RE-TYPED. The measured side is extracted from `pg_get_constraintdef` — so
--     it is whatever the database ADMITS, not whatever this file's author believed. Anchored
--     on the SUBJECT (the single-column CHECK whose conkey IS `reason_code`) rather than on
--     the auto-generated constraint NAME, per DESIGN.md's anchoring rule: an explicit
--     `constraint <name> check (...)` re-declaration would rename it and a name-anchored
--     probe would then measure NOTHING and report an empty set as agreement.
--   ⚑ THE EXPECTED SIDE IS A LITERAL, AND IT HAS TO BE. pgTAP cannot read TypeScript, so this
--     is the DB-side half of a two-file invariant. Its job is to make a DDL vocabulary change
--     go RED so nobody can land one without also touching the constant — the remedy is NAMED
--     in the message, because a red whose fix is "go find the other copy" gets fixed here.
select is(
  (select array(
     select m[1]
       from pg_constraint con
       join pg_attribute att
         on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
       cross join lateral regexp_matches(pg_get_constraintdef(con.oid), '''([a-z_]+)''::text', 'g') m
      where con.conrelid = 'pfin.account_event'::regclass
        and con.contype = 'c'
        and array_length(con.conkey, 1) = 1
        and att.attname = 'reason_code'
      order by 1)),
  array['duplicate', 'institution_closed', 'no_longer_used', 'other', 'sold', 'transferred_out'],
  '(D4d) VOCABULARY PIN: the reason_code CHECK admits EXACTLY the six values mirrored by CLOSURE_REASONS in api/src/lib/schemas/account-constants.ts. Derived from pg_constraint, not hand-copied from the DDL. RED means the CHECK changed — THE REMEDY IS TO UPDATE `CLOSURE_REASONS` (and the picker labels beside it) IN THE SAME PR, then this literal. Do NOT fix this by editing the literal alone: a value the CHECK admits and the picker omits breaks nothing and is therefore invisible, which is exactly the drift this pin exists to make loud'
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
