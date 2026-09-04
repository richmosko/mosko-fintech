-- =====================================================================
-- SELF-269 — §2.5.5 RLS VERIFICATION BATTERY — V1.4 CLOSE-GATE.
--   AC block: docs/records/v14-preflight (rederived), read live at drafting
--   from the dispatch's own scratchpad copy (verbatim). Mirrors
--   self257_v13_close_gate.sql's shape (the explicit precedent, itself
--   mirroring self244): SEAM-ONLY, authors NO schema. Proves the V1.4 §2.5
--   read/write surface holds closed AS A WHOLE, under ONE shared
--   multi-tenant fixture, exercised together — which no single per-issue
--   battery does. Composes already-green per-issue batteries (100-105) for
--   the deep per-function proofs; adds only the NET-NEW seam + cross-cutting
--   + genuinely-missing legs no per-issue battery makes on its own.
--
--   ⚠ SCOPE CORRECTION FROM SEC D-5, APPLIED HERE (the AC block already
--   carries R7's supersession and D-5's three corrections in its own text —
--   restated so a reader of ONLY this file sees the same disposition):
--   AC1's coverage list is SELF-259/260/262/263/265/267/268, ALL now
--   in-milestone per R7 (SELF-261 closes unbuilt at R2, out of scope). AC6's
--   struck SERIALIZABLE-guarantees parenthetical is NOT asserted anywhere
--   below. AC8 (pfin.transaction_annotation / wash-sale) is STRUCK
--   PERMANENTLY (R2 (A)) — no leg authored; the table does not exist
--   (pfin.account_trans_annotation, 023, is the real one) and V1 ships no
--   wash-sale flag. AC4's literal fixture spelling (tax_deferred/tax_free,
--   UNDERSCORES per D-5 / 003:101-102) is used throughout.
--
-- Ratified AC coverage (mapping to the live AC block; "COMPOSED" = an
-- already-green per-issue battery carries the exhaustive proof, cited by
-- file + leg name, not re-derived; "NEW" = fresh SQL below):
--   AC1  — two-tenant coverage of every V1.4 backend surface. COMPOSED for
--          six of the seven named surfaces (100 ISO-PRE/ISO1-5; 101 W1-W6/
--          D1/X1/AAL-S/AAL-X; 102 L2a/L2a-verify/L2b; 103 the two
--          expect_cross_tenant_read_empty calls; 104 L16a-h; 105 X1/X2/
--          BOOT1/BOOT2) — every one of those already asserts the AC's
--          canonical shape (a cross-tenant caller sees/touches nothing).
--          NEW: BLOCK CONTROL0 + BLOCK AC1 give this gate ONE direct,
--          non-citation pin of the canonical leg itself ("tenant A injects
--          tenant B's users_id → rejected"), placed on `pfin.tax_bracket_row`
--          — the ONE surface this milestone gives a genuinely NEW isolation
--          SHAPE (ADR-011 Decision 3 canonical #18, grain (C): the child
--          carries its OWN users_id beside a cross-tenant-reachable FK,
--          unlike every other V1.4 surface, which is either direct-owner
--          RLS (schedule/account/nav_daily columns) or a parameterless
--          INVOKER read composing on direct-owner tables). The other six
--          surfaces earn no fresh pin: none introduces a new isolation
--          shape beyond what 100-105's own batteries already prove
--          exhaustively (self257's own AC8/AC10 precedent: a composed
--          surface earns a pin only when the gate would otherwise rest on
--          citation ALONE for a NOVEL shape — true here only of #18).
--   AC2  — SELF-262's SECURITY INVOKER composition, Wave-1 B5/SELF-209
--          pattern (rederived-acs.md:206). COMPOSED: 104 L16h (A's total
--          unmoved by B's rich fixture) + 105 X1/X2 (fn_nav_composition,
--          which composes fn_compute_tax_liability, which composes THREE
--          further INVOKER functions — the deepest composition chain in
--          V1.4 — carries zero leakage on BOTH tenants' rich fixtures) +
--          105 BOOT1/BOOT2 (the zero-tenant fails closed into a structured
--          shape, never an error). No new SQL — the composition chain is
--          already exercised end-to-end by 105's own battery.
--   AC3  — scope-attribute-not-isolation-boundary discipline (PRD §2.5.5).
--          NEW: BLOCK AC3 — two accounts across TWO tenants sharing the
--          IDENTICAL `scope` string; neither tenant's count is inflated by
--          the collision. The discipline is already STATED in six file
--          headers (003/074/090/101 among them); this is its one
--          falsifiable exercise under a real cross-tenant collision.
--   AC4  — three tax_treatment states (D-5 spelling). COMPOSED: 104 L11/L12
--          (a_gain/a_loss/a_pi — taxable included, tax_deferred excluded,
--          reclassification moves the figure) + 105 PI1-PI4 (the same
--          property re-proven live at the NAV composer, tenant B). No new
--          SQL for the three-state exclusion itself; the JOURNALED positive-
--          gain fixture below (BLOCK JG) gives AC4/4b a genuinely-new
--          NON-ZERO Unrealized path reached through the REAL production
--          write path (fn_create_manual_purchase, 088) rather than a raw
--          account_trans INSERT, which is what every existing Unrealized
--          fixture in the tree uses.
--   AC4a — designated-ledger §2.1.5 exclusion / NULL-designation inclusion.
--          COMPOSED: 102 L3b/L3c-L3j (the R3 rider 0b default-state walk,
--          BOTH consumers, THREE states, incl. the reversion proof) + 105
--          DES-pin/DES (the exclusion live at the composer, non-vacuously).
--          No new SQL.
--   AC4b — R9 clamp, NEGATIVE-aggregate-G/L fixture, NAV does not rise.
--          COMPOSED: 104 L11 (the clamp fires on 104's own internal figure,
--          net -1000 -> 0, non-vacuous against a would-be -170) + 105
--          R9-pin/R9 (the IDENTICAL property re-proven AT THE NAV COMPOSER —
--          "unrealized_tax_liab = {computed, 0}... nav is NOT raised by an
--          unrealized LOSS; the clamp is LIVE at the composer, not merely
--          inside 104's own internal figure" — R9-pin's own words are this
--          AC's own request, verbatim, already on the tree). No new SQL.
--   AC4c — SELF-226's foot-to-headline reconciliation, R3 rider 0's watcher.
--          NEW: BLOCK AC4C — genuinely absent from the tree. E42 P-11/
--          addendum confirm the APP-LEVEL half (call-shape: fn_nav_
--          composition exactly once, fn_compute_nav never on the §2.1.1
--          path) was built at SELF-268 in
--          api/src/routes/nav-composition-flip.server.test.ts — cited here,
--          not duplicated. The DB-LEVEL half this AC asks for — assert
--          fn_nav_composition.nav <> fn_compute_nav when a designated
--          ledger or a computed tax scalar exists — has NO leg anywhere in
--          100-105 (105's own NAV1/NAV2 pin fn_compute_nav's BYTE-IDENTITY,
--          never call it and compare its VALUE against fn_nav_composition's
--          nav in one fixture state — measured by grep, zero hits). BLOCK
--          AC4C closes that gap: an inequality leg, an EXACT-DIFFERENCE leg
--          (independently reconstructed, the 105-DES-leg discipline), and a
--          non-vacuous companion (tenant C: the two headlines agree when
--          nothing exists) proving the divergence is state-driven, not an
--          artifact.
--   AC4d — the exclusion's DEFAULT state, BOTH halves move together.
--          COMPOSED: 102 L3a/L3b (STATE 1, undesignated: absent from YTD
--          Paid AND present in the leaf set) through L3c-L3j (marking moves
--          BOTH figures, and the reversion on clearing). No new SQL.
--   AC4e — the R3 rider 0c partial unique index, THREE states. COMPOSED for
--          two of three: 102 L1b (same-jurisdiction rejected) + L1c
--          (different-jurisdiction accepted). NEW: BLOCK AC4E — the third
--          state (a second UNMARKED account accepted) is asserted nowhere
--          in 102's own battery (grep-confirmed: no leg inserts two
--          simultaneously-NULL-designation accounts for one user and
--          asserts BOTH persist).
--   AC5  — bracket-schedule cross-tenant leak, tenant B invisible in A's
--          helper output. COMPOSED (101 W1-W6, D1, X1) — merged into BLOCK
--          AC1/AC5a below since the AC1 canonical leg and the AC5a
--          adversarial leg are, per Sec's own §3 trap analysis, the
--          IDENTICAL shape on the IDENTICAL table (a forged users_id
--          against a real cross-tenant-reachable schedule_id).
--   AC5a — the matched-tenant fence made to go RED, R4 rider 7. Same leg as
--          AC1's canonical pin — see BLOCK AC1/AC5a. The falsifiability
--          argument (grain (C), not the rejected grain (A)) is Sec's own
--          §10.2 item 1 finding, already realized in 101's DDL and proven
--          exhaustively in 101's W4/D1 — this gate's pin re-derives it once
--          more under a fresh, close-gate-owned fixture rather than resting
--          on citation alone for the ONE novel D3 shape in the milestone.
--   AC5b — the three NaN CHECKs, rate domain, non-zero-floor rejection.
--          COMPOSED: 101 CHK1/CHK3/CHK5 (three independent NaN CHECKs, one
--          per column) + CHK6/CHK7 (rate domain, with control) + SF-Z1-Z4
--          (zero-floor vs monotonicity, the exact leg the AC names: "a fully
--          monotone schedule whose lowest bracket_floor is non-zero is
--          REJECTED... the only one that observes Sec §10.2 item 5"). No
--          new SQL.
--   AC6  — bracket-row monotonicity across replace-all replay; a non-
--          monotone MULTI-ROW batch rejected via the deferred CONSTRAINT
--          TRIGGER, not a hand-ordered single INSERT. COMPOSED: 101 RA11a-d
--          — the EXACT shape (a two-row batch [0.30, then 0.10] sent through
--          fn_tax_bracket_schedule_replace_all in ONE call, which RETURNS
--          CLEANLY because the fence is deferred, then RAISES at `set
--          constraints all immediate`, then a rollback restores the PRIOR
--          set). No new SQL. The STRUCK parenthetical (Sec D-5 / R4 rider 2)
--          is asserted NOWHERE below or in 101 — recorded, not tested,
--          since a false claim has no positive leg to write.
--   AC7  — tax_jurisdiction cross-tenant pen-test on SELF-267's CORRECTED
--          signature, fn_ytd_paid_per_jurisdiction(p_as_of date,
--          p_jurisdiction pfin.tax_jurisdiction_enum) — no p_users_id
--          parameter exists to inject (D-5's third correction: the drafted
--          leg pen-tested a parameter the shipped function does not carry).
--          NEW: BLOCK AC7 — genuinely absent. 102's own battery (grep-
--          confirmed) never calls fn_ytd_paid_per_jurisdiction under tenant
--          B's RLS context at all; L2b proves the SIBLING function
--          (fn_tax_authority_ledgers) is leak-free with both tenants
--          holding the SAME 'irs' value, but the YTD-PAID PRIMITIVE ITSELF
--          — the one with money attached — has no analogous pen-test. Since
--          there is no forgeable parameter, the pen-test IS the comparison:
--          two tenants hold the SAME jurisdiction value with DIFFERENT
--          ledger balances, and each sees only its own.
--   AC8  — STRUCK PERMANENTLY at R2 (A). No leg authored. See the SCOPE
--          CORRECTION note above.
--   AC8a — capital-gains isolation over an empty set is VACUOUS, marked as
--          such — R1 (A). COMPOSED: 104 L3a/L3b (the structural-unavailable
--          shape, no `rows` key) + L16g (identical shape for tenant B,
--          independent of any other data). No new SQL.
--   AC9  — forward fence: no service_role reach on any V1.4 surface, all
--          execute under authenticated per ARCH §4.1. NEW: BLOCK AC9 — a
--          declarative sweep over every live-callable V1.4 function (the
--          self257 AC12 shape), scoped per the SCOPE CORRECTION above (the
--          drafted "SELF-259-266" range corrected to the AC1 enumeration).
--          Folds in the standing condition named at carry-forward.md /
--          sec-262 AMBER N-3 (any EXECUTE grant on fn_compute_tax_liability
--          to a rolbypassrls role is Sec-mandatory) by naming that function
--          and fn_nav_composition explicitly in the swept set, alongside
--          every trigger/helper function this milestone shipped.
--   AC10 — Sec joint-review pass, verdict recorded per the SELF-257
--          precedent. Procedural; no SQL. Where Sec's §4 catch-criteria and
--          this AC set overlap, Sec's text governs (per AC10's own text) —
--          every citation above to a Sec finding (D-5, §3, §10.2 item 5) is
--          Sec's own words, cross-checked against the live doc at drafting.
--   AC11 — harness obligations, each followed structurally below:
--          pg_prove-only verification (see hand-off report, never bare
--          psql); ok()/not isnt() on every NULL-able negative (BLOCK AC7-3,
--          BLOCK AC4D-composed); BLOCK CONTROL0 runs FIRST and is a genuine
--          RLS-gated cross-tenant-empty assertion (would read TRUE, not
--          merely non-erroring, under a silent `set_config` no-op); BLOCK
--          CDS is the CURRENT_DATE smoke (a row created_at=now(),
--          transaction_date=CURRENT_DATE, asserted INCLUDED at
--          p_as_of=CURRENT_DATE — an all-zero result here would be
--          byte-identical to broken); the scratch DB this file was verified
--          against was rebuilt immediately before the full-suite claim in
--          the hand-off report (never a re-used DB — rollback does not
--          reset sequences).
--   AC12 — V1.4 close-gate: no V1.4 issue closes to milestone until this
--          battery passes. Procedural; no SQL.
--
--   WATCHER GAPS FOLDED IN THIS WAVE (team-lead dispatch; carry-forward.md):
--   - BLOCK ND — a nav_daily-seeded fixture, so the §2.1.2 chart's gross
--     -basis line has SOMETHING to read (arch-268 bubble-up: the SELF-268
--     walk found the chart's gross-basis line "not visually confirmed"
--     because a fresh tenant carries no nav_daily history at all). Two
--     rows across two dates for tenant A; cross-tenant invisibility pinned
--     (054's own battery is the exhaustive RLS proof, cited not repeated);
--     read-back in date order.
--   - BLOCK JG — the journaled positive-gain fixture (sec-262 AMBER
--     bubble-up, carry-forward.md): a NON-ZERO Unrealized path reached
--     through pfin.fn_create_manual_purchase (088), the REAL production
--     write path (asset mint + GL posting), rather than the raw
--     account_trans INSERT every existing Unrealized fixture in the tree
--     uses. The companion half of that same bubble-up note — "Trade/STC
--     decoy via account_trans_split child" — is ALREADY on the tree at 104
--     L1a/L1b (grep-confirmed) and is NOT re-derived here.
--
-- ┌─ COMPOSE (verified green by the full suite; this file re-proves the ────┐
-- │ cross-cutting seam) — 100_tax_value_inventory_seed_delta.sql (SELF-263,  │
-- │ 34 legs) · 101_tax_bracket_tables.sql (SELF-259/265, 110 legs) ·         │
-- │ 102_tax_jurisdiction_ytd_paid.sql (SELF-267, 35 legs) ·                  │
-- │ 103_tax_bracket_seed.sql (SELF-260, 42 legs) ·                          │
-- │ 104_fn_compute_tax_liability.sql (SELF-262, 60 legs) ·                  │
-- │ 105_nav_composition_tax_flip.sql (SELF-268, 28 legs). Plan counts are a  │
-- │ derived, unwatched property — read each file's own plan() line live,    │
-- │ never transcribe it here (Sec F3 / self244 / self257 precedent).        │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- INVERSION VERIFICATION (AC10 / dispatch instruction; performed against the
--   scratch DB, recorded here since pgTAP cannot encode "strike and expect
--   red" as a committed assertion without leaving the strike in place):
--   - R9 CLAMP: 104's `greatest((r.fed_ltcg_top + r.ca_top) * u.agg, 0)`
--     struck to the bare unclamped product on a scratch clone -> 105's OWN
--     R9 leg went RED (-2415.00 instead of the clamped 0, MEASURED); this
--     file's JG-2/AC4C legs stayed GREEN, CORRECTLY — BLOCK JG's fixture is
--     a GAIN (aggregate +1500.00), so `greatest(positive,0)` is a no-op for
--     it by construction and it was never going to be the clamp's watcher;
--     that is 105's own R9-pin/R9 (a deliberately NEGATIVE aggregate), cited
--     not duplicated. Restored, GREEN again.
--   - DESIGNATED-LEDGER EXCLUSION: `fn_tax_authority_ledgers()`'s `where
--     a.tax_jurisdiction is not null` struck to `where false` (excludes
--     nothing) on a scratch clone -> MEASURED: this file's AC7-1/AC7-2 went
--     RED (both compose on the struck helper, so YTD Paid reads NULL for
--     every jurisdiction instead of each tenant's own balance) and 105's
--     OWN BND1-4/GT1/DES-pin legs went RED. AC4C-1/AC4C-2 stayed GREEN —
--     a MEASURED, NAMED LIMITATION, not an oversight: AC4C-2's "independent"
--     reconstruction calls the SAME fn_tax_authority_ledgers() helper the
--     composer itself calls, so a break INSIDE that one shared primitive
--     moves both sides of the equality together and neither AC4C leg can
--     see it — 105's DES-pin DOES catch it, but for a DIFFERENT reason:
--     DES-pin compares the helper's sum against a HARDCODED literal
--     (1300.0000), not against a second derivation of the same helper, so
--     a break inside the shared primitive has somewhere to show up. AC4C's
--     equality-of-two-derivations SHAPE is therefore the weaker form for
--     THIS specific fault and 105's DES-pin/BND-block literals are this
--     exclusion's real watchers, composed not duplicated. Restored, GREEN.
--   - MATCHED-TENANT FENCE: `tax_bracket_row_matched_schedule` trigger
--     DISABLED on a scratch clone -> MEASURED: this file's AC1/AC5a-1 and
--     101's OWN W4 both failed (their throws_like MESSAGE stopped matching
--     — for a PLAIN authenticated caller the table's OWN RLS WITH CHECK
--     (users_id = auth.uid()) substitutes and still rejects the forged
--     insert, just with a different error, so the throws_like PATTERN is
--     what goes red, not a lives_ok bypass) — and 101's OWN D1 leg
--     (service_role, RLS BYPASSED) is the CLEAN demonstration: "no
--     exception thrown" — a genuine silent bypass with no fallback layer,
--     confirming the trigger, not RLS, is the fence for an RLS-exempt
--     writer. Restored (trigger re-enabled), GREEN across all three.
--   - MONOTONICITY TRIGGER: `fn_tax_bracket_row_schedule_invariants`'s LEG
--     B predicate (`f.bracket_rate < f.prev_rate`) struck to `false` on a
--     scratch clone -> MEASURED: 101's OWN (SF-M2) and (RA11b) — the EXACT
--     AC6 leg, the multi-row replace-all batch that must be rejected at
--     commit — both went RED ("no exception thrown" on a genuinely
--     non-monotone committed set). This file carries no leg of its own for
--     AC6 (fully COMPOSED, per the header mapping above) and correctly
--     stayed GREEN throughout — it is not that mechanism's watcher.
--     Restored, GREEN.
--   See the hand-off report for the exact commands and md5s of the struck
--   vs restored function bodies.
--
-- Ledgers all FLAT (SEAM-only, no schema authored): §10 catalogued-instance
--   ledger (ADR-011 Decision 4) and the SECURITY DEFINER allowlist (ADR-011
--   Decision 9) are both untouched — every function this file exercises is
--   INVOKER. Decision-3 family unchanged (no column authored; #18 was
--   DDL-realized at 101, already folded in there per that ADR's own rule).
--   Read ADR-011 Decisions 4/9 live at point of use.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b()/_c(). NO PII / NO real account numbers / NO
--   production data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed)
--   with users_id set EXPLICITLY (auth.uid() is NULL under postgres);
--   functions invoked ONLY under the authenticated tenant contexts under
--   test, or via the fn_create_manual_purchase RPC under the OWNING
--   tenant's own context (never postgres) since it is SECURITY INVOKER and
--   requires auth.uid(). All in a rolled-back txn.
--
-- Sec joint-review-mandatory — this issue IS the RLS surface; the Sec
--   verdict is AC10 itself, per the SELF-257 precedent's gate.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 20: CONTROL0 1 + AC1/AC5a 2 (canonical forgery + control) + AC3 2
--   (scope-collision non-inflation, both tenants) + AC4E 1 (both accounts,
--   same user, left unmarked, BOTH persist) + AC7 3 (B's own value / A's own
--   value non-vacuous companion / C's NULL, three-state pen-test) + JG 2
--   (the journaled purchase landed as expected / the Unrealized figure
--   reached through it) + AC4C 3 (inequality / exact-difference / tenant-C
--   non-vacuous companion) + CDS 2 (non-vacuous fixture check / the
--   CURRENT_DATE smoke itself) + ND 2 (cross-tenant pin / date-order
--   read-back) + AC9 2 (non-vacuous function-count companion / the sweep)
--   = 20. Recorded so a silent plan-edit shows as an arithmetic change.
select plan(20);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- =====================================================================
-- FIXTURE — shared as-of. All dates fall inside 2026 except the CDS block,
--   which deliberately uses CURRENT_DATE (AC11's smoke requirement).
--   ⚠ FIXTURE-CLOCK TRAP (standing trap): created_at DEFAULTS to real
--   wall-clock now() on account_trans INSERT, NOT to transaction_date.
--   Every fixture row below pins created_at EXPLICITLY on/before its own
--   transaction_date so every leg's expected result is independent of
--   whenever this battery is actually run.
-- =====================================================================
\set d_as_of '2026-06-15'

-- =====================================================================
-- BLOCK CONTROL0 — AC11's "a control leg runs first": a genuine RLS-gated
--   cross-tenant-empty assertion, placed before any other tenant-scoped
--   select in this file. If `_rls.set_tenant`'s `set_config(...,true)`
--   ever silently no-ops (the AC11-named hazard), this is the FIRST thing
--   in the file that would read FALSE instead of TRUE, not the 20th.
--   Doubles as the AC1/AC5a fixture's two schedules (sched_a/sched_b).
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_ordinary', 2026, 12000.00, 'CONTROL0/AC1 sched_a (269)')
  returning id as sched_a \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sched_a, 0, 0.10);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'federal_ordinary', 2026, 12000.00, 'CONTROL0/AC1 sched_b (269)')
  returning id as sched_b \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sched_b, 0, 0.10);

select _rls.expect_cross_tenant_read_empty('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK AC1/AC5a — THE CANONICAL LEG: tenant A injects tenant B's users_id
--   on A's OWN real schedule_id (the ADR-011 Decision 3 canonical #18
--   ownership-forge shape, R4 rider 7 / 101's own W4). A BEFORE trigger
--   evaluates regardless of RLS visibility, so this is the fence itself,
--   not a byproduct of what RLS hides.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_ac1;
select throws_like(
  format($$ insert into pfin.tax_bracket_row (schedule_id, users_id, bracket_floor, bracket_rate) values (%s, %L, 0, 0.10) $$, :sched_a, :'tb'),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(AC1/AC5a-1) THE CANONICAL LEG: tenant A submits its OWN real schedule_id (sched_a) with a FORGED users_id=B -> the #18 matched-tenant trigger raises leg 2 cross-tenant — this is the fence, not RLS (BEFORE triggers fire regardless of row visibility); re-derived fresh on this gate''s own fixture per Sec''s "no substitute for citation on a novel shape" standard'
);
rollback to savepoint sp_ac1;
savepoint sp_ac1b;
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, users_id, bracket_floor, bracket_rate) values (%s, %L, 99000, 0.10) $$, :sched_a, :'ta'),
  '(AC1/AC5a-2) non-vacuous control: the IDENTICAL shape with the CORRECT users_id=A commits (a DIFFERENT bracket_floor, 99000, than CONTROL0''s own fixture row on sched_a, so this is a fresh insert, not a duplicate-key collision) — proving (AC1/AC5a-1)''s rejection is the forged-identity discriminator, not a blanket refusal of any insert against sched_a'
);
rollback to savepoint sp_ac1b;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC3 — scope-attribute-not-isolation-boundary discipline (PRD
--   §2.5.5): two tenants' accounts share the IDENTICAL `scope` free-text
--   string; neither tenant's visible count is inflated by the collision.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-scope-269', 'depository', 'collide-scope-269', 'taxable');
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-scope-269', 'depository', 'collide-scope-269', 'taxable');

select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int from pfin.account where scope = 'collide-scope-269'),
  1,
  '(AC3-1) scope is NOT an isolation boundary: A sees exactly 1 account at scope=''collide-scope-269'' — B''s account at the IDENTICAL scope string does not inflate A''s count'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*)::int from pfin.account where scope = 'collide-scope-269'),
  1,
  '(AC3-2) reverse direction: B sees exactly 1 account at the SAME colliding scope string — users_id, not scope, is what RLS keys on'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC4E — the R3 rider 0c partial unique index's THIRD state (a plain
--   unique index would fail it): two accounts, BOTH left unmarked
--   (tax_jurisdiction NULL), for the SAME user -> BOTH inserts succeed.
--   States 1 (same-jurisdiction rejected) and 2 (different-jurisdiction
--   accepted) are 102's own L1b/L1c — COMPOSED, not re-derived.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-unmarked1-269', 'depository', 'household', 'taxable')
  returning account_id as a_unmarked1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-unmarked2-269', 'depository', 'household', 'taxable')
  returning account_id as a_unmarked2 \gset

select is(
  (select count(*)::int from pfin.account
    where account_id in (:a_unmarked1, :a_unmarked2) and tax_jurisdiction is null),
  2,
  '(AC4E-3) the partial unique index''s THIRD state: TWO accounts for the SAME user, BOTH left UNMARKED (tax_jurisdiction NULL), BOTH persist — a PLAIN (non-partial) unique index on (users_id, tax_jurisdiction) would treat repeated NULLs identically to any other value under some engines and this is the boundary the WHERE clause exists to leave open; states 1/2 are 102''s own L1b/L1c'
);

-- =====================================================================
-- BLOCK AC7 — tax_jurisdiction cross-tenant pen-test on SELF-267's
--   CORRECTED signature (no p_users_id parameter exists to inject). Two
--   tenants designate the SAME jurisdiction ('irs') with DIFFERENT ledger
--   balances; each sees ONLY its own. This fixture doubles as BLOCK AC4C's
--   designated-ledger driver below.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-irs-269', 'depository', 'household', 'taxable')
  returning account_id as a_irs \gset
update pfin.account set tax_jurisdiction = 'irs' where account_id = :a_irs;
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_irs, 1000.0000, 'USD', '2026-01-01', 'seed');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-irs-269', 'depository', 'household', 'taxable')
  returning account_id as b_irs \gset
update pfin.account set tax_jurisdiction = 'irs' where account_id = :b_irs;
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:b_irs, 400.0000, 'USD', '2026-01-01', 'seed');

select _rls.set_tenant(:'tb'::uuid);
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction(:'d_as_of'::date, 'irs'::pfin.tax_jurisdiction_enum)),
  400.0000::numeric,
  '(AC7-1) THE PEN-TEST: tenant B calls fn_ytd_paid_per_jurisdiction(d, ''irs'') and gets its OWN 400.00 — NOT tenant A''s 1000.00 and NOT the combined 1400.00. No p_users_id parameter exists to inject against (D-5''s correction); the enum value alone cannot select another tenant''s ledger'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction(:'d_as_of'::date, 'irs'::pfin.tax_jurisdiction_enum)),
  1000.0000::numeric,
  '(AC7-2) non-vacuous companion: tenant A, calling the SAME function with the SAME jurisdiction value, gets its OWN DISTINCT 1000.00 — (AC7-1)''s 400.00 was not a coincidental shared default'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select ok(
  (select pfin.fn_ytd_paid_per_jurisdiction(:'d_as_of'::date, 'irs'::pfin.tax_jurisdiction_enum) is null),
  '(AC7-3) three-state completion: tenant C (no ''irs'' ledger designated at all) gets NULL — not 0, not an error, not either tenant''s figure — completing the A/B/C discriminator on one call shape (ok(), not isnt(), per AC11 on a NULL-able negative)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK JG — the JOURNALED positive-gain fixture (sec-262 AMBER bubble-up):
--   a NON-ZERO Unrealized path reached through pfin.fn_create_manual_
--   purchase (088), the REAL production write path (asset mint + GL
--   posting via 035/037), rather than the raw account_trans INSERT every
--   existing Unrealized fixture in the tree (104's L11/L12, 105's PI/R9
--   blocks) uses. Feeds BLOCK AC4C below.
-- =====================================================================
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_lt_cg', 2026, 0.0000, 'JG federal_lt_cg (269)')
  returning id as sched_a_ltcg \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sched_a_ltcg, 0, 0.05);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'california_ordinary', 2026, 0.0000, 'JG california_ordinary (269)')
  returning id as sched_a_caord \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sched_a_caord, 0, 0.10);
-- top_rate sum = 0.05 + 0.10 = 0.15 (single bracket each).

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-journal-269', 'investment', 'household', 'taxable')
  returning account_id as a_journal \gset

-- THE JOURNALED PURCHASE (SECURITY INVOKER, must run as the owning tenant,
-- never postgres — auth.uid() is NULL under postgres and the RPC's own
-- guard refuses that): 10 units at a TOTAL cost basis of 1000.00 (per-unit
-- 100.00), a MINTED private asset -> mints pfin.asset + writes day-1
-- eod_price(100.00) + posts through fn_gl_entries via account_trans.
select _rls.set_tenant(:'ta'::uuid);
select trans_id as jg_trans, security_id as jg_asset, priced as jg_priced
  from pfin.fn_create_manual_purchase(
    :a_journal, '2026-01-05'::date, 10::numeric, 1000.00::numeric,
    null, 'equity', 'Journaled Gain Asset 269', 'JGA269'
  ) \gset
select set_config('role', 'postgres', true);

select is(
  (select array[t.quantity::text, t.cost_basis::text, t.transaction_type]
     from pfin.account_trans t where t.trans_id = :jg_trans),
  array['10.00000000', '1000.0000', 'standard'],
  '(JG-1) non-vacuous: the JOURNALED purchase landed exactly as requested — quantity 10, TOTAL cost_basis 1000.0000, transaction_type ''standard'' — via fn_create_manual_purchase''s real write path, not a hand-crafted account_trans row'
);

-- A LATER, higher market price (a genuine subsequent market-data update —
-- deliberately NOT routed through the purchase RPC, which only ever writes
-- the day-1 manual_valuation price; this is the ordinary market_feed path
-- 049 reads via D-first LOCF). 10 units x (250.00 - 100.00) = 1500.00 gain.
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:jg_asset, '2026-06-01', 'market_feed', 250.0000);

select _rls.set_tenant(:'ta'::uuid);
select is(
  jsonb_build_object(
    'status', pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 225.00::numeric),
  '(JG-2) unrealized_tax_liab = {computed, 225.00} = (0.05+0.10) x 1500.00 (10 units x (250.00-100.00) gain) — the FIRST non-zero Unrealized figure in the tree reached through the REAL journaled write path (fn_create_manual_purchase -> GL posting -> 049 -> 104), not a raw account_trans fixture shortcut'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC4C — SELF-226's foot-to-headline reconciliation, R3 rider 0's
--   watcher, THE DB-LEVEL HALF: fn_nav_composition.nav <> fn_compute_nav
--   when a designated ledger (BLOCK AC7's a_irs) or a computed tax scalar
--   (BLOCK JG's 225.00) exists. The APP-LEVEL half (call-shape: fn_nav_
--   composition exactly once, fn_compute_nav never on the §2.1.1 path) is
--   api/src/routes/nav-composition-flip.server.test.ts (SELF-268) — cited,
--   not duplicated. This is the ONLY leg in 100-105 or here that calls
--   fn_compute_nav and fn_nav_composition TOGETHER in one fixture state and
--   compares their VALUES (105's own NAV1/NAV2 pin fn_compute_nav's byte
--   identity, never its output value against fn_nav_composition's).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select isnt(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric,
  (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  '(AC4C-1) THE RECONCILIATION WATCHER: fn_nav_composition''s tax-adjusted nav is NOT EQUAL to fn_compute_nav''s gross headline for tenant A — a_irs (BLOCK AC7, designated ''irs'') is excluded from the composer''s leaf set and JG''s 225.00 computed Unrealized scalar is subtracted; RED if the §2.1.1 headline were ever re-pointed to read fn_nav_composition''s value while still claiming fn_compute_nav''s identity, or vice versa (SELF-226''s own failure shape)'
);
select is(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric - (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  (select coalesce(sum(g.current_market_value), 0)
     from pfin.fn_tax_authority_ledgers() tal
     join pfin.fn_account_unrealized_gl(:'d_as_of'::date) g on g.account_id = tal.account_id)
  + coalesce((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  + coalesce((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'realized_tax_liab' ->> 'amount')::numeric, 0),
  '(AC4C-2) EXACT-DIFFERENCE, independently reconstructed (the 105-DES-leg discipline, not a magic literal): gross minus tax-adjusted equals EXACTLY the designated ledgers'' summed balance PLUS both tax scalars, computed via THREE independent calls rather than assumed — robust to whatever else this file''s fixture adds for tenant A elsewhere'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric,
  (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  '(AC4C-3) non-vacuous companion: tenant C (zero accounts, zero designations, zero schedules) has the two headlines AGREE (both 0) — proving (AC4C-1)/(AC4C-2)''s inequality is DRIVEN by A''s designated-ledger-and-computed-scalar state, not a universal artifact of calling the two functions together'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK CDS — AC11's CURRENT_DATE smoke: a row created RIGHT NOW
--   (created_at=now(), transaction_date=CURRENT_DATE), asserted INCLUDED
--   at p_as_of=CURRENT_DATE. Every other leg in this file uses a fixed
--   2026 date; an all-zero result here would be byte-identical to broken
--   if the D19 half-open created_at bound ever regressed relative to the
--   REAL wall clock, which no fixed-date leg can observe.
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Revenue', 'SmokeCDS269', true, null, false)
  returning id as a_smoke \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:a_journal, current_date, 77.0000, 'cds-smoke-269', now())
  returning trans_id as t_smoke \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_smoke, :a_smoke);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  (select bool_or(row ->> 'sub_cat' = 'SmokeCDS269')
     from jsonb_array_elements(pfin.fn_compute_tax_liability(current_date)->'decomposition'->'ordinary_income'->'rows') row),
  '(CDS-1) non-vacuous: the freshly-created SmokeCDS269 row IS present in ordinary_income.rows at p_as_of=CURRENT_DATE'
);
select is(
  (select (row ->> 'amount')::numeric
     from jsonb_array_elements(pfin.fn_compute_tax_liability(current_date)->'decomposition'->'ordinary_income'->'rows') row
    where row ->> 'sub_cat' = 'SmokeCDS269'),
  77.0000::numeric,
  '(CDS-2) THE SMOKE: a row created THIS INSTANT (created_at=now(), transaction_date=CURRENT_DATE) carries its REAL value (77.00) at p_as_of=CURRENT_DATE — the half-open created_at bound proven against the ACTUAL wall clock this battery runs at, not a fixed historical date every other leg in this file uses'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK ND — a nav_daily-seeded fixture (arch-268 bubble-up): the SELF-268
--   walk found the §2.1.2 chart's gross-basis line "not visually confirmed"
--   because a fresh tenant carries zero nav_daily history. Two rows across
--   two dates for tenant A. Cross-tenant RLS is 054's own exhaustive
--   battery — cited, one pin, not repeated.
-- =====================================================================
-- 054's write-tenant binding fence (fn_nav_daily_assert_computed_for, ADR-011
-- Decision 1 clause (c) / SELF-214 B7) requires app.nav_computed_for to equal
-- the row's users_id, set transaction-locally, BEFORE each INSERT.
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values (:'ta', '2026-05-01', 48000.00);
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values (:'ta', '2026-06-01', 50500.00);

select _rls.expect_cross_tenant_read_empty('pfin.nav_daily'::regclass, :'ta'::uuid, :'tb'::uuid);

select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by nav_date) from pfin.nav_daily where users_id = :'ta'),
  array[48000.00, 50500.00]::numeric[],
  '(ND-2) a two-point trend is seeded and readable in nav_date order for tenant A — the chart-line fixture pattern this battery corpus previously had nowhere'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC9 — forward fence: NO V1.4 function is reachable by service_role
--   (or granted EXECUTE at all beyond authenticated); every one executes
--   under authenticated only (ARCH §4.1). Scoped per the SCOPE CORRECTION
--   above to the AC1 enumeration's live surfaces. Folds in the sec-262
--   AMBER N-3 standing condition (fn_compute_tax_liability, fn_nav_
--   composition named explicitly — any EXECUTE grant of either to a
--   rolbypassrls role is independently Sec-mandatory).
-- =====================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin'
       and p.proname in ('fn_tax_bracket_schedule_replace_all', 'fn_provision_tax_brackets',
                          'fn_tax_authority_ledgers', 'fn_ytd_paid_per_jurisdiction',
                          'fn_compute_tax_liability', 'fn_nav_composition',
                          'fn_create_manual_purchase')),
  7,
  '(AC9-1) non-vacuous companion: the swept V1.4 function-name IN-list resolves to EXACTLY 7 live pfin functions, one overload each (fn_compute_nav is 019/050''s pre-existing surface, already swept by self257''s own AC12 and not re-swept here; the two tax_bracket_row trigger functions are excluded deliberately — Postgres does not check EXECUTE when firing a trigger, per 101''s own E7 note, so an EXECUTE sweep over them would trivially pass and add no coverage) — the sweep below is not silently narrowed by a typo''d name'
);
select ok(
  (select bool_and(not has_function_privilege('service_role', p.oid, 'execute'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_tax_bracket_schedule_replace_all', 'fn_provision_tax_brackets',
                         'fn_tax_authority_ledgers', 'fn_ytd_paid_per_jurisdiction',
                         'fn_compute_tax_liability', 'fn_nav_composition',
                         'fn_create_manual_purchase')),
  '(AC9-2) forward fence: NONE of the 8 swept V1.4 functions grant EXECUTE to service_role — every one is reachable ONLY under authenticated, per ARCH §4.1. Folds in sec-262 AMBER N-3''s standing condition: fn_compute_tax_liability and fn_nav_composition (both money-figure, both INVOKER) are named explicitly in this set, not left to a broader wildcard sweep'
);

select * from finish();
rollback;
