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
--   SECOND-PASS CORRECTION (QA, 2026-09-04, same session): the FIRST commit
--   of this file (d1bb098) claimed AC4/AC4a/AC4b/AC4d were fully COMPOSED
--   with no new SQL. Measured FALSE for AC4 specifically —
--   `grep -rn tax_free supabase/tests/ supabase/migrations/10{0..5}*.sql`
--   returns ZERO hits in any Unrealized-exclusion context tree-wide (the
--   one hit, 042, is an unrelated Plaid-linking fixture); every existing
--   (pi)-exclusion fixture (104's a_pi, 105's b_pi) exercises taxable +
--   tax_deferred ONLY, never tax_free — exactly the gap this AC's own text
--   warns against ("assert all three states, not two"). BLOCK AC4 below
--   closes it. AC4b/AC4a/AC4d are re-scoped from "COMPOSED, no new SQL" to
--   fresh direct pins on THIS gate's own fixture, per each AC's own
--   explicit "gets its own leg" / "the only watcher" language — a
--   stricter reading than the first pass took of self257's AC8/AC10
--   economy precedent, which carries no such explicit per-AC instruction.
--   BLOCK R10 (AC1's SELF-263 clause) is also new — the first pass cited
--   100's own battery for the STORED values' correctness but authored
--   nothing proving 104 CONSUMES the corrected E4 D-ii split correctly.
--   Nothing already-committed is removed; this pass only ADDS.
--
--   THIRD-PASS FIX (QA, 2026-09-04, per Sec joint-review AMBER verdict —
--   docs/records/v14-execution/self269-sec-findings.md @ feature/self-268-sec
--   5f8a0a1). ⚠ Sec's review target (`origin/feature/self-269` @ `29f9a83`,
--   battery blob md5 `a1e6ff19…`) is the FIRST-commit (`d1bb098`) content —
--   it does NOT include the SECOND-PASS additions above (blob md5 at that
--   point was `2d004d62…`), because `feature/self-269`'s merge of
--   `feature/self-269-qa` (`e20906b`) predates this branch's second commit.
--   Sec's ruling (1) — ACCEPT the one-pin-plus-citation composition for the
--   #18 forgery shape, no fresh leg required for AC2/4/4a/4b/5b/6/8a's
--   structural half — is read here and not undone; the SECOND-PASS
--   additions stand as EXTRA rigor the AC's own "gets its own leg" text
--   independently supports, not as something Sec's ruling required. Fixed
--   in THIS pass, all still-live on the current (post-second-pass) file
--   (verified by re-grep, not assumed carried over): F-1 (blocking) —
--   `(AC4C-1)`'s `isnt()` (fail-open on NULL) replaced with `ok()`'s
--   three-state form. F-2 (blocking) — the AC 8a header deferral sentence
--   added, Sec's commit-ready text verbatim. F-3 — already fixed in the
--   SECOND PASS ("8 swept" -> "7 swept"). F-4 — the dangling `102 L3a`
--   citation (102 carries no `L3a`) corrected to `(L3b)` + `(L3h)` at
--   BOTH sites it appeared (the AC4d header bullet and the BLOCK
--   AC4A_AC4D comment — a second, THIS-PASS-INTRODUCED instance of the
--   identical citation bug, since the second pass's own AC4d rewrite
--   copied the wrong label forward without checking it resolved). N-2 —
--   `_rls.expect_owner_can_read` (Sec's finding named `expect_owner_reads`,
--   which does not exist in rls_verbs.psql; corrected to the real helper)
--   added to BLOCK CONTROL0. N-3 — `(AC4C-3b)` pins tenant C's headline to
--   a real 0. N-4 — the AC4C-2 mitigation citation moved from "105
--   DES-pin" (not independent of the shared helper either) to "102 (L2b)"
--   (the genuinely independent watcher); the historical INVERSION
--   VERIFICATION record is annotated in place, not rewritten. Plan 32 -> 34
--   (N-2 + N-3 each add one leg; every other fix is text-only).
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
--          NEW (second pass): BLOCK R10 additionally proves AC1's named
--          SELF-263 clause end to end — that 100's CORRECTED E4 D-ii
--          tax_relevant/tax_character values (generic Dividend -> ordinary,
--          Dividend - Qualified -> qualified_dividend) are CONSUMED
--          correctly by 104's reader, which 100's own battery (testing only
--          the stored values) does not prove.
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
--   AC4  — three tax_treatment states (D-5 spelling). NEW (second pass):
--          BLOCK AC4 extends BLOCK JG's own baseline (1500.00 gain,
--          unrealized_tax_liab=225.00) with a fresh tax_deferred account
--          AND a fresh tax_free account, TWO sequential reclassification
--          inversions (the 105 PI1/PI2/PI3 pattern extended from two
--          states to three — see the SECOND-PASS CORRECTION note above),
--          each moving Unrealized by EXACTLY its own account's
--          contribution. COMPOSED alongside 104 L11/L12 + 105 PI1-PI4 for
--          the (taxable, tax_deferred) two-state property this file does
--          not re-derive. The JOURNALED positive-gain fixture (BLOCK JG)
--          still gives AC4 its genuinely-new NON-ZERO Unrealized path
--          reached through the REAL production write path
--          (fn_create_manual_purchase, 088) rather than a raw
--          account_trans INSERT.
--   AC4a — designated-ledger §2.1.5 exclusion / NULL-designation inclusion
--          — "the only watcher R3's E-2 exclusion will have" (the AC's own
--          words). NEW (second pass): BLOCK AC4A_AC4D — a fresh
--          undesignated account (a_ftb269, distinct from BLOCK AC7's
--          a_irs/b_irs, which are designated FROM CREATION and never
--          exercise this transition) direct-pinned present-in-the-leaf AND
--          absent-from-YTD-Paid on THIS gate's own fixture. COMPOSED
--          alongside 102's OWN L3b/L3e/L3h/L3j for the exhaustive cycle.
--   AC4b — R9 clamp, NEGATIVE-aggregate-G/L fixture, NAV does not rise —
--          "gets its own leg" (the AC's own words). NEW (second pass):
--          BLOCK AC4B — a_bigloss269, a fresh independently-confirmed-
--          negative loss on THIS gate's own fixture, closing the exact
--          limitation this file's own INVERSION VERIFICATION section names
--          below (BLOCK JG's gain-shaped fixture was never going to
--          exercise the clamp). COMPOSED alongside 104's OWN L11 and 105's
--          OWN R9/R9-pin (identical property, different fixtures).
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
--          AC4C closes that gap: an inequality leg (ok(), not isnt() —
--          Sec F-1), an EXACT-DIFFERENCE leg (independently reconstructed,
--          citing 102's (L2b) as the real independent watcher on the
--          shared fn_tax_authority_ledgers() helper — Sec N-4), and a
--          non-vacuous companion pinning tenant C's headline to a REAL 0,
--          not merely IS NOT DISTINCT FROM (Sec N-3), proving the
--          divergence is state-driven, not an artifact.
--   AC4d — the exclusion's DEFAULT state, BOTH halves move together —
--          "gets a leg" (the AC's own words). NEW (second pass): the SAME
--          BLOCK AC4A_AC4D as AC4a above — marking a_ftb269 'ftb' moves
--          BOTH figures (YTD Paid NULL->500.00; leaf present->absent) in
--          the SAME transaction. COMPOSED alongside 102's OWN (L3b)
--          ("STATE 1: a_walk (undesignated) is PRESENT in fn_nav_
--          composition" — the buildup half) and (L3h) ("STATE 3
--          (reverted to NULL): YTD Paid is NULL again" — the YTD-Paid
--          half, reached by reversion; corrected from this file's first
--          pass, which cited a nonexistent `L3a` — Sec F-4).
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
--          ⚠ ROW-LEVEL CG ISOLATION IS NOT PROVEN BY THIS GATE AND IS
--          DEFERRED TO THE SALE-WRITER MILESTONE (Sec F-2, commit-ready
--          text verbatim). No `pfin.lot_match` row can exist in V1 (no
--          sale writer, no `lot_match` writer), so any "tenant A cannot
--          see tenant B's realized gains" leg would pass on both tenants
--          having none. What is asserted here is the STRUCTURAL fact
--          only — the CG surface reads `unavailable` for both tenants on
--          a capability, never on a row count. The first milestone that
--          lands a sale writer owes the row-level isolation legs this
--          gate cannot write.
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
--          BLOCK AC4D-composed, BLOCK AC4C-1 — the THIRD-PASS fix for Sec
--          F-1, which caught this note stopping one short of its own code);
--          BLOCK CONTROL0 runs FIRST and is a genuine
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
--     R9 leg went RED (-2415.00 instead of the clamped 0, MEASURED); BLOCK
--     JG's own JG-2 leg stayed GREEN, CORRECTLY — its fixture is a GAIN
--     (aggregate +1500.00), so `greatest(positive,0)` is a no-op for it by
--     construction and it was never going to be the clamp's watcher.
--     ⚠ SECOND-PASS ADDITION, RE-VERIFIED: BLOCK AC4B's own AC4B-2 closes
--     the limitation named above — struck on a FRESH scratch clone
--     (identical mechanism), MEASURED: AC4B-2 alone went RED, reading the
--     unclamped -6825.0000 instead of {computed,0} (AC4B-1's independently-
--     confirmed pre-clamp figure, byte-exact) — every OTHER leg in this
--     file (31/32) stayed GREEN, confirming AC4B-2 is a real, non-vacuous,
--     ISOLATED watcher of the clamp. Restored, GREEN again. 105's own
--     R9-pin/R9 remains COMPOSED, cited alongside.
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
--     THIS specific fault and 105's DES-pin/BND-block literals are ALSO
--     real watchers for it, composed not duplicated. Restored, GREEN.
--     ⚠ ANNOTATED, dated record kept as measured (Sec N-4): 105's DES-pin
--     is NOT independent of the shared helper either (it too reconstructs
--     via fn_tax_authority_ledgers()) — it happened to catch THIS specific
--     strike because it compares against a hardcoded literal, not because
--     it is helper-independent. 102's (L2b), which asserts the helper
--     returns ONLY a named fixture account, is the genuinely independent
--     watcher and is what the AC4C-2 header comment now cites.
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

-- plan = 34: CONTROL0 2 (cross-tenant-empty + Sec N-2's expect_owner_can_read
--   companion, distinguishing working RLS from deny-all) + AC1/AC5a 2
--   (canonical forgery + control) + AC3 2 (scope-collision non-inflation,
--   both tenants) + AC4E 1 (both accounts, same user, left unmarked, BOTH
--   persist) + AC7 3 (B's own value / A's own value non-vacuous companion /
--   C's NULL, three-state pen-test) + JG 2 (the journaled purchase landed as
--   expected / the Unrealized figure reached through it) + AC4 4
--   (three-state baseline + two reclassification inversions + the Sec D-5
--   underscore-literal control) + AC4B 2 (R9 clamp non-vacuous
--   negative-aggregate + the clamped 0) + AC4A_AC4D 4 (present-in-leaf /
--   absent-from-YTD-Paid pre-mark, then both halves move on marking) + R10 2
--   (qualified-dividend routing / generic-dividend routing, 100's corrected
--   values consumed by 104) + AC4C 4 (inequality via ok()/three-state per
--   Sec F-1 / exact-difference citing 102 L2b per Sec N-4 / tenant-C
--   agreement / tenant-C's value pinned to a real 0 per Sec N-3) + CDS 2
--   (non-vacuous fixture check / the CURRENT_DATE smoke itself) + ND 2
--   (cross-tenant pin / date-order read-back) + AC9 2 (non-vacuous
--   function-count companion / the sweep) = 34. Recorded so a silent
--   plan-edit shows as an arithmetic change.
select plan(34);

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

-- Sec N-2: the cross-tenant-empty leg above cannot distinguish WORKING RLS
-- from DENY-ALL (an intruder count of 0 also results if A's own policies
-- were accidentally deny-all). This companion closes that: A reads its OWN
-- schedule (sched_a), non-vacuously, on the SAME table CONTROL0 already
-- exercises. (Verb name corrected from Sec's finding text, which named
-- `_rls.expect_owner_reads` — the real helper in rls_verbs.psql is
-- `_rls.expect_owner_can_read`.)
select _rls.expect_owner_can_read('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid, 1::bigint);

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
-- BLOCK AC4 — three tax_treatment states (D-5 spelling), THE AC's OWN
--   EXPLICIT WARNING: "assert all three states, not two" (SECOND-PASS
--   CORRECTION, see the file header). Extends BLOCK JG's own baseline
--   (1500.00 gain, unrealized_tax_liab=225.00) with a FRESH tax_deferred
--   account and a FRESH tax_free account, TWO sequential reclassification
--   inversions (the 105 PI1/PI2/PI3 pattern extended from two states to
--   three), each moving Unrealized by EXACTLY its own account's
--   contribution.
-- =====================================================================
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null, 'equity', 'market_feed', 'SEC269X', 'Sec 269X (self269 AC4)') returning asset_id as ast4 \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:ast4, '2026-01-01', 'market_feed', 100.0000);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-deferred-269', 'investment', 'household', 'tax_deferred') returning account_id as a_deferred269 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at) values
  (:a_deferred269, '2026-01-05', -3000.0000, 40, :ast4, 3000.0000, 'standard', 'buy-def-269', '2026-01-05T00:00:00Z');
-- mv = 40*100 = 4000, cost_basis = 3000, gain = +1000. tax_deferred -> EXCLUDED.

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-free-269', 'investment', 'household', 'tax_free') returning account_id as a_free269 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at) values
  (:a_free269, '2026-01-05', -2000.0000, 30, :ast4, 2000.0000, 'standard', 'buy-free-269', '2026-01-05T00:00:00Z');
-- mv = 30*100 = 3000, cost_basis = 2000, gain = +1000. tax_free -> EXCLUDED.

select _rls.set_tenant(:'ta'::uuid);
select is(
  (pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric,
  225.00::numeric,
  '(AC4-0) THREE-STATE BASELINE, non-vacuous companion: with a_deferred269 (tax_deferred,+1000) and a_free269 (tax_free,+1000) BOTH added, unrealized_tax_liab is STILL 225.00 (BLOCK JG''s own figure, unaffected) — both new accounts'' gains are EXCLUDED'
);

select set_config('role', 'postgres', true);
update pfin.account set tax_treatment = 'taxable' where account_id = :a_deferred269;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric,
  375.00::numeric,
  '(AC4-1) STATE TWO — tax_deferred RECLASSIFIED to taxable: unrealized_tax_liab moves 225.00 -> 375.00, delta = 150.00 = 0.15 x 1000 EXACTLY, a_deferred269''s OWN contribution (a leaked +1000 at AC4-0 would already have made it read 375.00 there)'
);

select set_config('role', 'postgres', true);
update pfin.account set tax_treatment = 'taxable' where account_id = :a_free269;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric,
  525.00::numeric,
  '(AC4-2) STATE THREE — tax_free RECLASSIFIED to taxable: unrealized_tax_liab moves 375.00 -> 525.00, delta = 150.00 = 0.15 x 1000 EXACTLY, a_free269''s OWN contribution — ALL THREE tax_treatment states now exercised (taxable from BLOCK JG, tax_deferred-then-reclassified, tax_free-then-reclassified), closing this AC''s own "assert all three states, not two" warning'
);
select set_config('role', 'postgres', true);

-- Sec D-5 fixture-literal control: the PRD's hyphenated spelling
-- ('tax-deferred') is REJECTED by the CHECK — proves the fixture above
-- used the CHECK's real underscored literals by construction, not luck.
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_underscore;
select throws_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment) values ('hyphen-check-269', 'depository', 'household', 'tax-deferred') $$,
  '23514', null,
  '(AC4-UNDERSCORE) Sec D-5 fixture-literal control: tax_treatment=''tax-deferred'' (PRD hyphenated spelling) is REJECTED (23514) by 003''s CHECK — a fixture seeding the PRD spelling would read as a passing fence rather than a broken fixture'
);
rollback to savepoint sp_underscore;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC4B — the R9 clamp, ITS OWN leg on THIS gate's own fixture, with
--   a genuinely NEGATIVE aggregate (the AC's explicit "gets its own leg"
--   instruction) — closes the limitation named in this file's own
--   INVERSION VERIFICATION section (BLOCK JG's gain-shaped fixture was
--   never going to exercise the clamp). COMPOSED alongside 104's OWN L11
--   and 105's OWN R9/R9-pin (identical property, different fixtures).
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-bigloss-269', 'investment', 'household', 'taxable') returning account_id as a_bigloss269 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at) values
  (:a_bigloss269, '2026-01-05', -50000.0000, 10, :ast4, 50000.0000, 'standard', 'buy-bigloss-269', '2026-01-05T00:00:00Z');
-- mv = 10*100 = 1000, loss = 1000-50000 = -49000. New taxable-only
-- aggregate (a_journal 1500 + a_deferred269 1000 + a_free269 1000, all now
-- taxable, - 49000) = -45500.00 (NEGATIVE).

select _rls.set_tenant(:'ta'::uuid);
select ok(
  0.15 * (select coalesce(sum(g.unrealized_gl), 0) from pfin.fn_account_unrealized_gl(:'d_as_of'::date) g
             join pfin.account a on a.account_id = g.account_id where a.tax_treatment = 'taxable') < 0,
  '(AC4B-1) non-vacuous: the PRE-CLAMP figure (0.15 x the taxable-only aggregate, computed INDEPENDENTLY of 104) is genuinely NEGATIVE (-6825.00 = 0.15 x -45500) on THIS gate''s own fixture — the clamp leg below is not exercising an already-nonnegative case'
);
select is(
  jsonb_build_object(
    'status', pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 0::numeric),
  '(AC4B-2) unrealized_tax_liab = {computed,0}, NOT the negative pre-clamp figure (AC4B-1) — the R9 clamp gets ITS OWN leg with a NEGATIVE-AGGREGATE-G/L fixture on THIS gate''s own fixture, per the AC''s explicit instruction; nav is NOT raised by an unrealized LOSS'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC4A_AC4D — designated-ledger exclusion / undesignated inclusion,
--   BOTH HALVES MOVING TOGETHER on THIS gate's own fixture — "the only
--   watcher R3's E-2 exclusion will have" (AC4a) / "gets a leg" (AC4d),
--   the AC's own words. BLOCK AC7's a_irs/b_irs are designated FROM
--   CREATION and never exercise the undesignated-then-marked transition;
--   this block is genuinely new ground. COMPOSED alongside 102's OWN
--   (L3b) through (L3j) for the exhaustive cycle (102 carries no `L3a`
--   — Sec F-4).
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-ftb-269', 'depository', 'household', 'taxable') returning account_id as a_ftb269 \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_ftb269, 0.0000, 'USD', '2026-01-01', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at) values
  (:a_ftb269, '2026-02-01', 500.0000, 'ftb-pay-269', '2026-02-01T00:00:00Z');
-- balance 500.00. UNDESIGNATED at load.

select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from jsonb_array_elements(pfin.fn_nav_composition(:'d_as_of'::date) -> 'groups') g,
                       jsonb_array_elements(g -> 'accounts') acc
           where (acc ->> 'account_id')::bigint = :a_ftb269),
  '(AC4A-1) a_ftb269 (UNDESIGNATED, tax_jurisdiction NULL) is PRESENT in fn_nav_composition''s leaf set — R3 rider 0b''s default-state hazard, observed directly on THIS gate''s own fixture (BLOCK AC7''s a_irs/b_irs are designated FROM CREATION and never exercise this transition)'
);
select ok(
  pfin.fn_ytd_paid_per_jurisdiction(:'d_as_of'::date, 'ftb'::pfin.tax_jurisdiction_enum) is null,
  '(AC4A-2) california YTD Paid is NULL (unavailable) while a_ftb269 is undesignated — the OTHER half of the default-state hazard, absent-from-YTD-Paid while present-in-the-leaf-set (AC4A-1), neither figure contradicting the other on screen'
);

select set_config('role', 'postgres', true);
update pfin.account set tax_jurisdiction = 'ftb' where account_id = :a_ftb269;
select _rls.set_tenant(:'ta'::uuid);
select is(
  pfin.fn_ytd_paid_per_jurisdiction(:'d_as_of'::date, 'ftb'::pfin.tax_jurisdiction_enum),
  500.0000::numeric,
  '(AC4D-1) HALF ONE MOVES: marking a_ftb269 ''ftb'' moves california YTD Paid from NULL to its real 500.00 balance, in the SAME transaction'
);
select ok(
  not exists (select 1 from jsonb_array_elements(pfin.fn_nav_composition(:'d_as_of'::date) -> 'groups') g,
                           jsonb_array_elements(g -> 'accounts') acc
              where (acc ->> 'account_id')::bigint = :a_ftb269),
  '(AC4D-2) HALF TWO MOVES: a_ftb269 is now ABSENT from the leaf set — present->absent, the OPPOSITE direction from HALF ONE''s NULL->value, both figures moving from the SAME single UPDATE, neither contradicting the other on screen (R3 rider 0b''s exact shape)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK R10 — AC1's SELF-263 clause: 100's CORRECTED tax_relevant/
--   tax_character values (E4 D-ii: generic Dividend -> ordinary, Dividend
--   - Qualified -> qualified_dividend) are CONSUMED correctly by 104's
--   reader, end to end on this shared fixture. COMPOSED with 100's OWN
--   34-leg battery for the row-level correctness — this proves the
--   end-to-end CONSUMPTION, which 100's own battery cannot (it tests only
--   the stored values).
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-div-269', 'depository', 'household', 'taxable') returning account_id as a_div269 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment) values
  (:'ta', 'Revenue', 'Dividend269', true, null, false) returning id as pp_div269 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment) values
  (:'ta', 'Revenue', 'DividendQualified269', true, 'qualified_dividend', false) returning id as pp_divq269 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at) values
  (:a_div269, '2026-01-15', 1000.0000, 'div-269', '2026-01-15T00:00:00Z') returning trans_id as t_div269 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_div269, :pp_div269);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at) values
  (:a_div269, '2026-01-20', 1000.0000, 'divq-269', '2026-01-20T00:00:00Z') returning trans_id as t_divq269 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_divq269, :pp_divq269);

select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from jsonb_array_elements(pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'decomposition' -> 'ordinary_income' -> 'rows') r
           where (r ->> 'sub_cat_id')::bigint = :pp_divq269 and r ->> 'tax_character' = 'qualified_dividend'),
  '(R10-A) 100''s E4 D-ii corrected route: pp_divq269 (Dividend - Qualified) carries tax_character=''qualified_dividend'' in the decomposition row — routes to the Federal LT CG walk, not ordinary'
);
select ok(
  exists (select 1 from jsonb_array_elements(pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'decomposition' -> 'ordinary_income' -> 'rows') r
           where (r ->> 'sub_cat_id')::bigint = :pp_div269 and (r ->> 'tax_character') is null),
  '(R10-B) 100''s E4 D-ii corrected route: pp_div269 (the GENERIC Dividend row, corrected to ordinary per PM''s C'') carries a NULL tax_character in the decomposition row — routes to the ordinary walk, not LT CG'
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
-- Sec F-1 (blocking): isnt() is IS DISTINCT FROM and PASSES on NULL — a
-- watcher for 105's own "nav is NEVER NULL" contract that could not
-- observe a regression of exactly that promise. Replaced with ok() over
-- AC 11's "prove three states" form: both sides present, AND unequal.
select ok(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric is not null
  and (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric is not null
  and (pfin.fn_compute_nav(:'d_as_of'::date))::numeric
      <> (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  '(AC4C-1) THE RECONCILIATION WATCHER: BOTH fn_compute_nav''s gross headline AND fn_nav_composition''s tax-adjusted nav are NOT NULL, AND they are NOT EQUAL, for tenant A — a_irs (BLOCK AC7, designated ''irs'') is excluded from the composer''s leaf set and JG''s 225.00 computed Unrealized scalar is subtracted; RED if the §2.1.1 headline were ever re-pointed to read fn_nav_composition''s value while still claiming fn_compute_nav''s identity, or vice versa (SELF-226''s own failure shape), OR if either side ever regressed to NULL (105''s own "nav is NEVER NULL" contract) — ok(), not isnt(), per AC 11 (Sec F-1)'
);
select is(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric - (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  (select coalesce(sum(g.current_market_value), 0)
     from pfin.fn_tax_authority_ledgers() tal
     join pfin.fn_account_unrealized_gl(:'d_as_of'::date) g on g.account_id = tal.account_id)
  + coalesce((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  + coalesce((pfin.fn_compute_tax_liability(:'d_as_of'::date) -> 'nav_components' -> 'realized_tax_liab' ->> 'amount')::numeric, 0),
  -- Sec N-4: this reconstruction calls fn_tax_authority_ledgers() — the SAME
  -- helper fn_nav_composition itself anti-joins against — so a regression
  -- INSIDE that helper would move both sides together and this leg alone
  -- would not see it. 102''s (L2b) is the real independent watcher for that
  -- fault (it asserts the helper returns ONLY a NAMED fixture account,
  -- a_idx2 — a regression there reds L2b even though it would not red
  -- here); 105''s DES/DES-pin reconstruct via the SAME helper and are NOT
  -- independent of it either (corrected from this file''s first pass, which
  -- cited DES-pin as if it were).
  '(AC4C-2) EXACT-DIFFERENCE, independently reconstructed (not a magic literal): gross minus tax-adjusted equals EXACTLY the designated ledgers'' summed balance PLUS both tax scalars, computed via THREE independent calls rather than assumed — robust to whatever else this file''s fixture adds for tenant A elsewhere. Composed with 102''s (L2b) for the actual independent watcher on the fn_tax_authority_ledgers() helper this reconstruction shares with the function under test (Sec N-4)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric,
  (pfin.fn_nav_composition(:'d_as_of'::date) ->> 'nav')::numeric,
  '(AC4C-3) non-vacuous companion: tenant C (zero accounts, zero designations, zero schedules) has the two headlines AGREE — proving (AC4C-1)/(AC4C-2)''s inequality is DRIVEN by A''s designated-ledger-and-computed-scalar state, not a universal artifact of calling the two functions together'
);
-- Sec N-3: is() is IS NOT DISTINCT FROM under pgTAP, so (AC4C-3) alone
-- would pass on a double-NULL regression as readily as on a double-zero
-- one, and its own message claims "both 0" with nothing pinning that.
-- This companion pins the actual value.
select is(
  (pfin.fn_compute_nav(:'d_as_of'::date))::numeric,
  0::numeric,
  '(AC4C-3b) THE VALUE (AC4C-3)''s message claims: tenant C''s gross headline is a REAL 0, not a NULL that (AC4C-3)''s IS NOT DISTINCT FROM equality would have let pass silently (Sec N-3)'
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
  '(AC9-2) forward fence: NONE of the 7 swept V1.4 functions grant EXECUTE to service_role — every one is reachable ONLY under authenticated, per ARCH §4.1. Folds in sec-262 AMBER N-3''s standing condition: fn_compute_tax_liability and fn_nav_composition (both money-figure, both INVOKER) are named explicitly in this set, not left to a broader wildcard sweep'
);

select * from finish();
rollback;
