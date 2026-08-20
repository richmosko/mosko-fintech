-- =====================================================================
-- Per-Wave battery — pfin.planning_target: per-(users_id, sub_cat_id) %Target,
--   ADR-011 Decision 3 CANONICAL #17 (matched-tenant AND matched-domain, the
--   #14 one-fence-two-predicates precedent) + full authenticated CRUD RLS +
--   the 025 aal2 step-up backstop on every policy + ON DELETE RESTRICT +
--   tenant-cascade (SELF-324 / ADR-056; V1-SHIP-BLOCK; Lock 14 first member;
--   JOINT-REVIEW-MANDATORY per ADR-056's own Sec-surface note)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/074_planning_target.sql
--   - pfin.planning_target (id, users_id NOT NULL DEFAULT auth.uid() -> auth.users
--       ON DELETE CASCADE, sub_cat_id NOT NULL -> pfin.user_taxonomy ON DELETE
--       RESTRICT, target_percent numeric(5,2) NOT NULL CHECK (>= 0 AND <= 100),
--       created/updated_at, unique(users_id, sub_cat_id)). RLS direct-owner
--       (users_id = auth.uid()) ANDed with the ADR-029/025 aal2 backstop clause
--       on ALL FOUR policies (select/insert/update/delete); full authenticated
--       CRUD; anon zero-grant; service_role UNGRANTED (no V1 writer — the app
--       writes as the user, under the user's own JWT).
--   - pfin.fn_planning_target_matched_sub_cat()  (Decision-3 CANONICAL #17; 012/022
--       Pattern 1, local anchor, PLUS a second matched-DOMAIN predicate on the #14
--       precedent; SECURITY INVOKER, set search_path = '', NULL-safe fail-closed;
--       BEFORE INSERT OR UPDATE — the table is mutable settings data, so an
--       INSERT-only fence would leave the repoint path open). TWO distinct
--       raise legs post-084: (1) unresolvable, (2) cross-tenant. (A third leg —
--       wrong domain — existed pre-084; the split makes it structurally
--       unreachable as its own predicate, and its coverage moved to leg 1. See
--       BLOCK L3 below.)
--   - trigger planning_target_set_updated_at (reuses the 001 DEFINER allowlist entry #1).
-- Prereqs exercised (already on main / applied by Backend on the reset stack): 001 (pfin
--   schema + fn_refresh_updated_at), 009 (pfin.user_taxonomy — the sub_cat_id FK target
--   + its 028 cash-flow cat CHECK), 024 (user_settings.mfa_policy), 025 (the aal2 backstop
--   clause shape this migration reuses verbatim), auth.users (the users_id anchor).
-- Reuses the SELF-187/189/190/196/012/015/016/017/022/025 idiom: \ir verbs, ALL-LOWERCASE
--   \gset literals (005 case-fold lesson), MESSAGE-precise throws_like (004 all-42501
--   false-green lesson) / SQLSTATE-precise throws_ok for built-in Postgres errors, role
--   restored to postgres between blocks (PR #121 _rls-USAGE root-cause), the 022 BLOCK-6
--   service_role ACL-hold-open device to isolate a trigger's own predicate from RLS.
--
-- ┌─ ARCHITECT ITEM 1 — WITH CHECK is not independently observable from `authenticated` ──┐
-- │ The BEFORE trigger fires before RLS WITH CHECK is ever evaluated, and RLS makes a      │
-- │ foreign taxonomy row unresolvable (leg 1) before leg 2 can trip under a well-formed     │
-- │ authenticated write. A battery asserting only "cross-tenant write fails closed" would   │
-- │ go GREEN while the WITH CHECK clause on planning_target_insert/update is NEVER           │
-- │ exercised. BLOCK S below asserts its presence STRUCTURALLY via pg_policy, independent    │
-- │ of any behavioural path. This mirrors DECISIONS.md ADR-056's own Sec item (ii) verbatim. │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⭐ QA FINDING #1 — leg 2 IS reachable from plain `authenticated`, correcting the migration │
-- │  header, ADR-056, and ADR-011 D3 #17's ledger entry (all three assert leg 2 is "reachable │
-- │  only by an RLS-EXEMPT writer") ─────────────────────────────────────────────────────── │
-- │ Empirically verified (this PR): an authenticated writer who FORGES the users_id column   │
-- │ on their own INSERT — new.users_id = a foreign tenant, sub_cat_id = the CALLER's OWN     │
-- │ real Sub-Cat — trips leg 2, because the BEFORE trigger resolves sub_cat_id's REAL owner   │
-- │ (the caller) and compares it against the FORGED new.users_id, and this runs before RLS's  │
-- │ own WITH CHECK (users_id = auth.uid()) is ever reached. RLS would ALSO have rejected the  │
-- │ same statement, but the caller experiences the trigger's leg-2 message, not a 42501 RLS   │
-- │ violation — so the "RLS-EXEMPT-only" framing is incomplete, not just imprecise. This is   │
-- │ not novel: `pfin.fn_user_asset_category_matched_sub_cat` (canonical #8, 022's twin fence, │
-- │ which THIS migration's own text calls #17's structural twin) already proves the identical │
-- │ shape at 022's block (5a) — an authenticated ownership-forge trips #8's cross-tenant leg. │
-- │ (L2a) below is the #17 analogue of 022's (5a); (L2b)/(L2c) are the RLS-EXEMPT-writer leg  │
-- │ the brief asked for, kept as genuine ADDITIONAL coverage — the exempt-writer path is real │
-- │ (a migration-role/service_role remediation script), just not the ONLY reachable path.     │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⭐ QA FINDING #2 — INSERT's aal2 WITH CHECK is UNREACHABLE behaviorally, full stop ─────┐
-- │ Empirically verified (this PR, (M5) below): 025 aal2-claused BOTH planning_target_insert  │
-- │ (via 074) AND user_taxonomy_select (025:671 `alter policy`). fn_planning_target_matched_  │
-- │ sub_cat is SECURITY INVOKER, so its own read of user_taxonomy composes with the LATTER's   │
-- │ aal2 clause. A totp caller below aal2 therefore gets LEG 1 unresolvable from the TRIGGER   │
-- │ on their OWN Sub-Cat — the trigger's aal2-gated READ shadows planning_target_insert's      │
-- │ aal2-gated WRITE, unconditionally, for every caller and every Sub-Cat. UPDATE/DELETE do    │
-- │ NOT share this: their USING clause filters candidate rows BEFORE the trigger ever fires    │
-- │ (verified empirically at (M7)), so only INSERT is affected. This makes (S1)'s structural   │
-- │ pg_policy assertion the SOLE proof planning_target_insert's aal2 WITH CHECK clause exists  │
-- │ at all — no authenticated INSERT, at any aal, against any Sub-Cat, can ever reach it        │
-- │ behaviorally. Not a defect (the row genuinely is unresolvable from the caller's own vantage │
-- │ at aal1), but a correction to this test's OWN first draft, which assumed WITH CHECK would  │
-- │ be the visible gate at (M5) and asserted 42501 — the live-stack measurement said otherwise. │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NaN vs ±Infinity — TWO DISTINCT mechanisms, TWO DISTINCT SQLSTATEs (Architect item 3) ──┐
-- │ ±Infinity is refused by the numeric(5,2) TYPMOD before it ever reaches the CHECK          │
-- │ (SQLSTATE 22003, "numeric field overflow"). NaN IS storable in a constrained numeric and  │
-- │ reaches the CHECK, where the UPPER bound catches it (NaN sorts above every non-NaN         │
-- │ numeric, so a ONE-SIDED lower bound `>= 0` would wrongly ADMIT it) — SQLSTATE 23514,       │
-- │ check_violation, naming planning_target_target_percent_check. (N1)-(N5) assert by SQLSTATE│
-- │ specifically so a regression collapsing both to one code (or admitting NaN) goes RED.      │
-- │ Fixture gotcha (Architect's own probe hit this): these legs use A's ASSET sub_cat, never   │
-- │ the cash-flow one — a cash-flow sub_cat trips LEG 3 first (wrong domain), which would      │
-- │ mask the numeric mechanism entirely and go vacuous on exactly this fixture mistake.        │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ Leg 3 fixture gotcha — 028's cash-flow cat CHECK (Architect's own probe hit this) ──────┐
-- │ pfin.user_taxonomy's 028 CHECK constrains cash-flow `cat` to the 5-class enum ('Revenue', │
-- │ 'Expense', 'Transfer', 'Equity', 'Trade'). cat='Income' FAILS AT THE FIXTURE, not the      │
-- │ fence. (L3)/(L3u) below seed domain='cashflow', cat='Revenue', sub_cat='Salary' — a VALID  │
-- │ cash-flow row, so the wrong-domain RAISE is what actually fires, not a fixture-insert error.│
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ Unset semantics — ROW ABSENT, never a seeded zero (migration's own POSTURE) ────────────┐
-- │ a_sub2 NEVER gets a planning_target row — "unset" is proven by its ABSENCE, not by seeding │
-- │ a zero for every Sub-Cat (which would make "unset" untestable — every row would look the   │
-- │ same). a_sub3 gets an EXPLICIT 0.00 row — a different, storable, user-asserted fact.        │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ Corrupt-the-control (BLOCK X) — the #474 limit-1 displacement class does NOT apply here ─┐
-- │ PR #474's F2/SELF-228 lesson: a canary asserting a specific foreign value through an       │
-- │ `order by ... limit 1`-style selector can be silently displaced by a real tied row once    │
-- │ the fence opens. planning_target has NO such selector anywhere in this battery — every read│
-- │ here is a plain equality-filtered lookup (`where sub_cat_id = :x`), so the corrupted-open   │
-- │ canary below asserts an EXACT expected value, not merely non-null/non-own. Stated           │
-- │ explicitly per house discipline, not because the class applies.                             │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 catalogued ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27 — read ADR-011
--   Decision 4 live, never from here; 074 realizes RT-23, which already scoped this write path,
--   rather than adding an entry). Decision-3 family: this migration REALIZES CANONICAL #17
--   (planning_target.sub_cat_id -> user_taxonomy, matched-tenant + matched-domain, folded in
--   this same PR per ADR-056 / DECISIONS.md ADR-011 D3). This battery is the pgTAP proof that
--   the fence catches all THREE legs of a real violation, PLUS the structural WITH CHECK proof
--   Architect's item 1 and ADR-056 Sec item (ii) both require.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c(),
--   plus raw literals for the totp tenant (td) and the cascade-only tenant (te, suffixed '74'
--   to keep this file's fixtures diffable against other batteries' fixed literals in the same
--   cluster, though each file's txn rolls back independently so collision is not actually live).
--   NO PII / NO real account numbers / NO prod data. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql LITERALS
--   via \gset at role=postgres; every _rls.set_tenant(_aal) is called at role=postgres and each
--   block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 074/075's firmed contract; the authoritative run is against
--   the 001->075 reset stack (CI, db-tests.yml, clean-apply). Locally verified on a hand-built
--   scratch DB (createdb + auth/extensions/vault schemas + pgtap restored from the live
--   Supabase container, migrations 001-075 applied in order, per the #474 venue recipe — `supabase
--   db reset` is mechanically banned). RE-VERIFIED against the 001->084 stack (ADR-058's split;
--   posture and messages confirmed live). ⚠ QA FINDING at the SELF-242 review (2026-08-20): the
--   file's own DELETE coverage (M9/M10) was same-tenant-only and (M11) cross-tenant-only-SELECT
--   — no leg exercised a cross-tenant DELETE attempt against the planning_target_delete USING
--   tenant predicate. (M12) closes that gap; plan bumped 38 -> 39 accordingly. plan(39): 4
--   structural (S1-S2 + S3a-S3b, split per Sec
--   F1 fold-in on the #476 joint-review — see the box at BLOCK S) + 2 unset-semantics
--   (U1-U2) + 2 two-tenant read isolation (R1-R2) + 2 leg-1 (L1a-L1b) + 3 leg-2 (L2a-L2c) + 2
--   leg-1-via-cross-vocabulary (L3-L3u, retained names, retargeted assertion post-084 — see
--   BLOCK L3) + 1 combined structural (L3s, new at 084) + 5 numeric mechanism (N1-N5) +
--   1 RESTRICT (FK1) + 12 aal2 backstop + cross-tenant-write
--   (M1-M12, M12 new at SELF-242) + 1 UPSERT reassign (UP1a) + 1 corrupt-the-control (X1) + 1
--   anon zero-grant (G1) + 2 tenant-cascade (CASC1a-CASC1b) = 39.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(39);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
\set td '00000000-0000-0000-0000-000000000d74'
\set te '00000000-0000-0000-0000-000000000e74'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Five tenants in auth.users: A/B (plain 'none' policy), C (NO user_settings
--    row — lazy-provision / coalesce case, via _rls.tenant_c()), D (totp — the
--    aal2 backstop subject), E (cascade-only, isolated from every other block).
--  - user_taxonomy: A owns FOUR Sub-Cats — a_sub/a_sub2/a_sub3 (asset domain,
--    the fence-PASS targets) + a_cf_sub (cashflow domain, valid per 028's CHECK
--    -- cat='Revenue' -- the leg-3 wrong-domain target). B owns TWO asset
--    Sub-Cats (b_sub, b_sub2). C owns ONE (c_sub). D owns TWO (d_sub, d_sub2).
--    E owns ONE (te_sub), used only by the cascade block.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');
-- tc: deliberately NO row (missing-row / lazy-provision coalesce case).
-- te: deliberately NO row (cascade block does not touch RLS/aal at all).

insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Brokerage', 'US Equity', 'asset') returning id as a_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Real Estate', 'Primary Home', 'asset') returning id as a_sub2 \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'ta', 'Brokerage', 'Intl Equity', 'asset') returning id as a_sub3 \gset
-- POST-084: a_cf_sub is now a pfin.posting_prototype row, not pfin.user_taxonomy — the
-- cashflow half of the split (ADR-058 Decision 1). Still A's OWN valid posting prototype
-- (cat='Revenue', legal per the unconditional CHECK). BLOCK L3 below re-targets accordingly.
insert into pfin.posting_prototype (users_id, cat, sub_cat)
  values (:'ta', 'Revenue', 'Salary') returning id as a_cf_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'tb', 'Brokerage', 'US Equity', 'asset') returning id as b_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'tb', 'Brokerage', 'Intl Equity', 'asset') returning id as b_sub2 \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'tc', 'Brokerage', 'US Equity', 'asset') returning id as c_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'td', 'Brokerage', 'US Equity', 'asset') returning id as d_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'td', 'Brokerage', 'Intl Equity', 'asset') returning id as d_sub2 \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element)
  values (:'te', 'Brokerage', 'US Equity', 'asset') returning id as te_sub \gset

-- =====================================================================
-- BLOCK S (postgres — pg_policy catalog) — STRUCTURAL WITH CHECK / USING
--   presence proof (Architect item 1 / ADR-056 Sec item (ii)). Independent of
--   any behavioural path — proves the POLICY, not just the fence.
-- =====================================================================
-- (S1) planning_target_insert carries a WITH CHECK wired to users_id = auth.uid().
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.planning_target'::regclass and polname = 'planning_target_insert'),
  '(S1) STRUCTURAL: planning_target_insert carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog) — proves the POLICY exists and is wired, independent of any behavioural test (a behavioural cross-tenant INSERT alone proves the trigger FENCE, since it fires first and never lets a well-formed authenticated write reach WITH CHECK — see the header box)'
);

-- (S2) planning_target_update carries a WITH CHECK wired the same way.
select ok(
  (select pg_get_expr(polwithcheck, polrelid) ilike '%users_id = auth.uid()%'
     from pg_policy
    where polrelid = 'pfin.planning_target'::regclass and polname = 'planning_target_update'),
  '(S2) STRUCTURAL: planning_target_update carries a WITH CHECK expression referencing users_id = auth.uid() (pg_policy catalog) — same proof as (S1) for the UPDATE path'
);

-- (S3a)/(S3b) — SPLIT by clause half (Sec F1 fold-in, #476 joint-review): an
--   OR-combined single count (the original (S3)) goes GREEN if aal2 survives in
--   EITHER half of a policy, so a WITH-CHECK-only aal2 regression on
--   planning_target_update would pass silently — USING gates first for
--   UPDATE, so no behavioural leg (M7/M8) would catch it either: whenever
--   USING already required aal2 for a caller/session, WITH CHECK's own aal2
--   clause is trivially satisfied by the same caller/session, so it is NEVER
--   independently exercised. This is exactly the migration header's own
--   point (074:188-190): "the same structural assertion is the right watcher
--   for the UPDATE clause too, since the behavioural legs there prove the
--   USING half rather than the WITH CHECK half" — TRUE with this split, false
--   with the original single OR-count. Two independent catalog counts:
--   (S3a) USING (polqual) carries aal2 — select/update/delete (the 3 policies
--   with a USING clause; insert has none). (S3b) WITH CHECK (polwithcheck)
--   carries aal2 — insert/update (the 2 policies with a WITH CHECK clause;
--   select/delete have none). Either count dropping by one is a REAL clause
--   loss, unmasked by the other half surviving.
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.planning_target'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'),
  3::bigint,
  '(S3a) STRUCTURAL — USING half: select/update/delete (the 3 policies carrying a USING clause) all carry the ADR-029/025 aal2 backstop in polqual (pg_policy catalog) — RED if any USING-side aal2 clause were dropped, independent of the WITH CHECK half'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.planning_target'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'),
  2::bigint,
  '(S3b) STRUCTURAL — WITH CHECK half: insert/update (the 2 policies carrying a WITH CHECK clause) both carry the ADR-029/025 aal2 backstop in polwithcheck (pg_policy catalog) — RED if planning_target_update''s WITH CHECK lost its aal2 clause while USING kept it, a regression (S3a) alone and no behavioural leg would ever catch (USING gates UPDATE first, so WITH CHECK''s aal2 half is never independently reached — see the box above)'
);

-- =====================================================================
-- BLOCK 1 (authenticated A / B) — real committed rows, non-vacuous fixture for
--   the two-tenant read isolation + unset-semantics blocks. a_sub2 deliberately
--   gets NO row (the unset case).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.planning_target (sub_cat_id, target_percent) values (:a_sub, 25.00);
insert into pfin.planning_target (sub_cat_id, target_percent) values (:a_sub3, 0.00);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
insert into pfin.planning_target (sub_cat_id, target_percent) values (:b_sub, 60.00);
select set_config('role', 'postgres', true);

-- (U1) unset semantics: a_sub2 was NEVER seeded -> ROW ABSENT, not a zero row.
select is(
  (select count(*) from pfin.planning_target where sub_cat_id = :a_sub2)::bigint,
  0::bigint,
  '(U1) unset = ROW ABSENT: a_sub2 has NO planning_target row (never seeded) — the migration''s POSTURE contract (unset is absence, never a seeded zero); RED if some code path defaulted an unset Sub-Cat to a phantom 0 row'
);

-- (U2) explicit 0.00 is a DIFFERENT, storable, user-asserted fact from absence.
select is(
  (select target_percent from pfin.planning_target where sub_cat_id = :a_sub3),
  0.00::numeric(5,2),
  '(U2) explicit 0.00 IS a storable fact, distinct from (U1)''s absence: a_sub3 carries a REAL row with target_percent = 0.00 — "the user asserted a zero target" is representable and different from "never classified"'
);

-- =====================================================================
-- BLOCK R (postgres — _rls verbs) — two-tenant read isolation. A owns exactly
--   2 rows at this point (a_sub@25.00, a_sub3@0.00).
-- =====================================================================
-- (R1) owner-reads-own: A sees exactly its 2 rows (guards an over-restrictive policy).
select _rls.expect_owner_can_read('pfin.planning_target'::regclass, :'ta'::uuid, 2::bigint);

-- (R2) cross-tenant read fails closed: B sees 0 of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.planning_target'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK L1 (authenticated A) — LEG 1, unresolvable. Both a nonexistent id AND a
--   real-but-foreign id land HERE (RLS renders B's row invisible to A's fence
--   read before leg 2 can ever trip), per the migration's own contract note.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (L1a) nonexistent sub_cat_id -> leg 1 unresolvable.
savepoint sp_l1a;
select throws_like(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 10.00) $$, 999999999),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(L1a) LEG 1 unresolvable: sub_cat_id references NO taxonomy row at all -> fn_planning_target_matched_sub_cat RAISES leg 1, not a bare foreign_key_violation (the FK alone would also 23503, but the fence''s own NULL-safe NOT FOUND check fires first as a BEFORE trigger)'
);
rollback to savepoint sp_l1a;

-- (L1b) real but FOREIGN sub_cat_id (B's b_sub) -> ALSO leg 1, not leg 2: RLS
--       hides B's row from A's read inside the fence, so `select ... into` finds
--       nothing (NOT FOUND), same as (L1a). Confirms the CONTRACT box's own claim.
savepoint sp_l1b;
select throws_like(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 10.00) $$, :b_sub),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(L1b) LEG 1 unresolvable (cross-tenant, authenticated path): A references B''s REAL sub_cat_id -> RLS on user_taxonomy makes B''s row INVISIBLE to A''s fence read, so it resolves as NOT FOUND (leg 1), never leg 2 -- under `authenticated`, a cross-tenant reference is caught by RLS-composed unresolvability, exactly as the migration''s CONTRACT block documents'
);
rollback to savepoint sp_l1b;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK L2 (authenticated A, then service_role) — LEG 2, cross-tenant.
--   (L2a) is the QA FINDING leg: reachable from PLAIN authenticated via an
--   ownership forge (the #8/(5a) precedent). (L2b)/(L2c) are the RLS-EXEMPT
--   writer path the brief asked for, kept as genuine additional coverage.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (L2a) ⭐ QA FINDING leg: A forges users_id = B on its OWN real sub_cat (a_sub,
--       truly owned by A). The fence resolves a_sub's REAL owner (A) and compares
--       against the FORGED new.users_id (B) -> MISMATCH -> leg 2 RAISES, from
--       PLAIN `authenticated`, before RLS's own WITH CHECK is ever reached.
savepoint sp_l2a;
select throws_like(
  format($$ insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (%L, %s, 10.00) $$, :'tb', :a_sub),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(L2a) ⭐ LEG 2 reachable from PLAIN authenticated (QA finding, corrects the migration header / ADR-056 / ADR-011 D3 #17''s "RLS-EXEMPT writer only" framing): A forges users_id=B on A''s OWN real sub_cat_id -> the BEFORE trigger resolves the TRUE owner (A) vs the FORGED new.users_id (B) and RAISES leg 2, before RLS''s own users_id=auth.uid() WITH CHECK is ever evaluated -- the #8/(022 5a) ownership-forge shape recurs identically on #17, its declared structural twin'
);
rollback to savepoint sp_l2a;
select set_config('role', 'postgres', true);

-- (L2b)/(L2c): hold service_role ACLs open in-test (rolled back) so the fence's
--   own predicate — not user_taxonomy RLS — is isolated as the sole gate (022
--   BLOCK 6 device; 074 itself grants service_role nothing — POSTURE).
grant usage on schema pfin to service_role;
grant select on pfin.user_taxonomy to service_role;
grant insert on pfin.planning_target to service_role;
select set_config('role', 'service_role', true);

-- (L2b) RLS-EXEMPT writer (team-lead's requested leg / the brief's framing):
--       users_id=B, sub_cat_id=A's real a_sub. Under RLS-bypass B's Sub-Cat set
--       is irrelevant (a_sub is A's); the explicit users_id predicate mismatches.
savepoint sp_l2b;
select throws_like(
  format($$ insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (%L, %s, 10.00) $$, :'tb', :a_sub),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(L2b) LEG 2 under service_role (RLS BYPASSED): users_id=B, sub_cat_id=A''s real Sub-Cat -> STILL RAISES -- the explicit users_id predicate (not RLS) is the gate the ADR-042 Decision 5a rationale describes (the writer no policy catches)'
);
rollback to savepoint sp_l2b;

-- (L2c) non-vacuous service_role control: users_id=B, sub_cat_id=B's OWN b_sub2
--       (unused so far) -> matched -> COMMITS. Proves (L2b) is mismatch-driven,
--       not a blanket service_role block.
savepoint sp_l2c;
select lives_ok(
  format($$ insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (%L, %s, 10.00) $$, :'tb', :b_sub2),
  '(L2c) non-vacuous service_role control: users_id=B, sub_cat_id=B''s OWN Sub-Cat -> ACCEPTED under service_role -- the fence is owner-mismatch-driven, not a blanket exempt-writer block'
);
rollback to savepoint sp_l2c;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK L3 (authenticated A) — was LEG 3 (wrong domain); POST-084 this targets LEG 1
--   (unresolvable), because a_cf_sub no longer lives in pfin.user_taxonomy at all — it moved
--   to pfin.posting_prototype under the same id (ADR-058 Decision 2). The split makes
--   cross-vocabulary REFERENCE structurally impossible (Decision 5 Finding (b)): the fence's
--   own resolving read into user_taxonomy simply finds nothing, exactly as (L1a)/(L1b) already
--   assert for a nonexistent / RLS-invisible id. RE-TARGET, not deletion — Sec's routed-(ii)
--   ruling: leg 3's coverage "does not disappear at the split — it moves to leg 1."
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (L3) INSERT: A targets its OWN cash-flow Sub-Cat (a_cf_sub, now a posting_prototype id) ->
--      user_taxonomy's resolving read finds NOTHING -> leg 1 unresolvable, not leg 3.
savepoint sp_l3;
select throws_like(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 10.00) $$, :a_cf_sub),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(L3) POST-084 RETARGET (was LEG 3 wrong-domain, now LEG 1 unresolvable): A references its OWN cash-flow Sub-Cat (a_cf_sub) -> the row no longer exists in user_taxonomy (it moved to posting_prototype under the same id, Decision 2) -> fn_planning_target_matched_sub_cat RAISES leg 1, same message as (L1a)/(L1b) -- matched-tenant alone would have PASSED pre-084 (A truly owns the row, just in the other table), proving cross-vocabulary reference is now structurally impossible rather than merely domain-checked'
);
rollback to savepoint sp_l3;

-- (L3u) UPDATE: same re-target, on the mutable repoint path.
savepoint sp_l3u;
select throws_like(
  format($$ update pfin.planning_target set sub_cat_id = %s where sub_cat_id = %s $$, :a_cf_sub, :a_sub3),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(L3u) POST-084 RETARGET (UPDATE): A reassigns its EXISTING row to its own cash-flow Sub-Cat -> RAISES leg 1 unresolvable on UPDATE too (BEFORE INSERT OR UPDATE covers the repoint path)'
);
rollback to savepoint sp_l3u;

-- (L3s) STRUCTURAL, combined (Sec routed-(ii): "ONE structural leg, asserting code and comment
--   TOGETHER... one leg, not two"): fn_planning_target_matched_sub_cat's prosrc is free of
--   `domain`, AND its obj_description is free of both `domain` and `three` (the retired
--   "THREE distinct raise legs" claim). Code/comment coherence, not proof of enforcement --
--   that is BLOCK L3's job above.
select ok(
  (select p.prosrc !~* 'domain'
     and coalesce(obj_description(p.oid, 'pg_proc'), '') !~* 'domain'
     and coalesce(obj_description(p.oid, 'pg_proc'), '') !~* 'three'
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_planning_target_matched_sub_cat'),
  '(L3s) STRUCTURAL: fn_planning_target_matched_sub_cat''s prosrc is free of `domain`, and its obj_description is free of both `domain` and `three` (the retired "THREE raise legs" claim) — code and comment coherence, not proof of enforcement'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK N (authenticated A) — NaN vs +/-Infinity vs out-of-range vs negative.
--   ALL against A's ASSET sub_cat (a_sub2, still unset) so leg 3 never masks
--   the numeric mechanism (the header box's fixture gotcha).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (N1) NaN: storable in numeric(5,2), reaches the CHECK, caught by the UPPER
--      bound (NaN sorts above every non-NaN numeric) -> 23514 check_violation.
savepoint sp_n1;
select throws_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 'NaN'::numeric) $$, :a_sub2),
  '23514', null,
  '(N1) NaN rejected by the CHECK constraint (23514 check_violation, planning_target_target_percent_check) -- NaN IS storable in a constrained numeric and reaches the CHECK, where the upper bound (>= 0 AND <= 100) catches it because NaN satisfies neither side reliably except that it sorts above every real number; a one-sided lower bound alone would have ADMITTED it'
);
rollback to savepoint sp_n1;

-- (N2) +Infinity: refused by the numeric(5,2) TYPMOD, never reaches the CHECK
--      -> 22003 numeric_value_out_of_range ("numeric field overflow"), NOT 23514.
savepoint sp_n2;
select throws_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 'Infinity'::numeric) $$, :a_sub2),
  '22003', null,
  '(N2) +Infinity rejected by the numeric(5,2) TYPMOD (22003 numeric_value_out_of_range, "numeric field overflow") -- a DIFFERENT SQLSTATE from (N1)''s CHECK violation: the typmod refuses the value BEFORE the CHECK constraint is ever consulted'
);
rollback to savepoint sp_n2;

-- (N3) -Infinity: same typmod mechanism as (N2).
savepoint sp_n3;
select throws_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, '-Infinity'::numeric) $$, :a_sub2),
  '22003', null,
  '(N3) -Infinity rejected by the same numeric(5,2) TYPMOD overflow as (N2) (22003) -- both non-finite values share the typmod mechanism, distinct from NaN''s CHECK-constraint mechanism'
);
rollback to savepoint sp_n3;

-- (N4) out-of-range high (150.00): reaches the CHECK (finite, storable in the
--      typmod), rejected by the upper bound -> 23514, SAME code as (N1).
savepoint sp_n4;
select throws_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 150.00) $$, :a_sub2),
  '23514', null,
  '(N4) out-of-range high (150.00) rejected by the CHECK constraint upper bound (23514) -- a finite, typmod-storable value, so it reaches the CHECK (unlike (N2)/(N3))'
);
rollback to savepoint sp_n4;

-- (N5) negative (-5.00): rejected by the lower bound -> 23514.
savepoint sp_n5;
select throws_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, -5.00) $$, :a_sub2),
  '23514', null,
  '(N5) negative (-5.00) rejected by the CHECK constraint lower bound (23514) -- the two-sided bound is symmetric, not merely an upper-bound NaN guard'
);
rollback to savepoint sp_n5;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK FK (postgres) — ON DELETE RESTRICT: a_sub is still referenced by A's
--   real committed row from BLOCK 1.
-- =====================================================================
-- (FK1) deleting a referenced user_taxonomy row is RESTRICTed (23503).
select throws_ok(
  format($$ delete from pfin.user_taxonomy where id = %s $$, :a_sub),
  '23503', null,
  '(FK1) sub_cat_id ON DELETE RESTRICT: deleting a user_taxonomy row still referenced by a planning_target row is RESTRICTED (foreign_key_violation 23503) -- a targeted taxonomy row cannot be silently deleted out from under a %Target'
);

-- =====================================================================
-- BLOCK M (aal2 backstop, ADR-029/025 shape, mirrored on all four policies).
--   Fixture: service_role seeds D's read/update/delete row (d_sub, 30.00) and
--   C's row (c_sub, 45.00), bypassing aal entirely (privileged seed path).
-- =====================================================================
select set_config('role', 'service_role', true);
insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (:'td', :d_sub, 30.00);
insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (:'tc', :c_sub, 45.00);
select set_config('role', 'postgres', true);

-- (M1) SELECT: totp D at aal1 -> 0 of its OWN rows (backstop blocks the read).
select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.planning_target where users_id = %L', :'td')),
  0::bigint,
  '(M1) SELECT: totp-declared D at aal1 sees 0 of its OWN rows -- the aal2 backstop blocks a direct-API read even though D genuinely has a row (RED if the backstop were dropped from planning_target_select USING)');

-- (M2) SELECT: SAME totp D at aal2 -> its row VISIBLE (proves M1 non-vacuous).
select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.planning_target where users_id = %L', :'td')),
  1::bigint,
  '(M2) SELECT: SAME totp D at aal2 sees its 1 own row -- proves (M1) is non-vacuous (D really owns a row) and the backstop does not over-block aal2');

-- (M3) SELECT NOT-BLANKET: none-policy B at aal1 -> its own row VISIBLE.
select is(_rls.count_as(:'tb'::uuid, 'aal1', format('select count(*) from pfin.planning_target where users_id = %L', :'tb')),
  1::bigint,
  '(M3) SELECT NOT-BLANKET: none-policy B at aal1 sees its own row -- RED if the clause became a blanket aal2 requirement (it would lock out a none user with no step-up declared)');

-- (M4) SELECT COALESCE-not-lockout: C has NO user_settings row (lazy provisioning)
--      -> coalesced to 'none' -> own row VISIBLE at aal1.
select is(_rls.count_as(:'tc'::uuid, 'aal1', format('select count(*) from pfin.planning_target where users_id = %L', :'tc')),
  1::bigint,
  '(M4) SELECT COALESCE-not-lockout: MISSING user_settings row (C, lazy provisioning) + aal1 -> own row VISIBLE -- RED if the subselect were not coalesced to ''none'' (NULL not in (...) would filter the row and lock out every unprovisioned user)');

-- (M5) INSERT: totp D at aal1 -> ⭐ NOT a WITH CHECK 42501 as first drafted.
--      fn_planning_target_matched_sub_cat is SECURITY INVOKER, and 025 ALSO
--      aal2-claused user_taxonomy_select (`alter policy user_taxonomy_select ...`,
--      025:671) -- so the trigger's OWN subquery resolving sub_cat_id is JUST AS
--      aal-gated as the read path. At aal1 the trigger's read of D's OWN d_sub2
--      row returns NOT FOUND (verified empirically: 0 rows visible at aal1, 1 at
--      aal2 -- see the header box) -> LEG 1 unresolvable fires BEFORE
--      planning_target_insert's own WITH CHECK is ever reached. This is a SECOND,
--      INSERT-specific instance of Architect item 1's shadowing, via a different
--      mechanism than the tenant-match legs: the trigger's own aal2-gated read
--      shadows its aal2-gated WRITE gate. UPDATE/DELETE do NOT share this
--      (their USING clause filters candidate rows BEFORE the trigger ever fires
--      -- verified empirically for (M7) below), so INSERT is the ONLY verb where
--      this applies. CONSEQUENCE: no authenticated INSERT path can EVER
--      behaviorally exercise planning_target_insert's aal2 WITH CHECK half --
--      (S1)'s structural proof is not merely additional assurance for INSERT, it
--      is the SOLE proof that clause exists at all.
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('sub', :'td', 'role', 'authenticated', 'aal', 'aal1')::text, true);
select throws_like(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 15.00) $$, :d_sub2),
  '%does not resolve to a taxonomy row readable by users_id%leg 1 unresolvable%',
  '(M5) ⭐ INSERT: totp D at aal1 -- d_sub2 IS D''s own asset Sub-Cat, yet the trigger raises LEG 1 unresolvable, NOT a WITH CHECK 42501: fn_planning_target_matched_sub_cat is SECURITY INVOKER and user_taxonomy_select is ITSELF aal2-claused (025:671), so at aal1 the trigger cannot even SEE d_sub2 -- the aal2-gated READ shadows the aal2-gated WRITE. Corrects this test''s own first draft, which assumed the fence would pass and WITH CHECK would be the visible gate'
);
select set_config('role', 'postgres', true);

-- (M6) INSERT: SAME totp D at aal2 -> succeeds (proves M5 non-vacuous).
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  format($$ insert into pfin.planning_target (sub_cat_id, target_percent) values (%s, 15.00) $$, :d_sub2),
  '(M6) INSERT: SAME totp D at aal2 -- the identical insert now SUCCEEDS -- proves (M5) is non-vacuous (the fence itself was never the blocker) and the backstop does not over-block aal2 writes'
);
select set_config('role', 'postgres', true);

-- (M7) UPDATE: totp D at aal1 -> USING hides the row -> 0 rows affected, value
--      unchanged (still 30.00 from the service_role seed).
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.planning_target set target_percent = 99.00 where sub_cat_id = :d_sub;
select set_config('role', 'postgres', true);
select is(
  (select target_percent from pfin.planning_target where sub_cat_id = :d_sub),
  30.00::numeric(5,2),
  '(M7) UPDATE: totp D at aal1 -- the UPDATE USING aal2 backstop hides D''s own row (0 rows affected); the value is UNCHANGED (still 30.00) -- RED if the backstop were dropped from planning_target_update USING'
);

-- (M8) UPDATE: SAME totp D at aal2 -> succeeds, value changes to 99.00.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.planning_target set target_percent = 99.00 where sub_cat_id = :d_sub;
select set_config('role', 'postgres', true);
select is(
  (select target_percent from pfin.planning_target where sub_cat_id = :d_sub),
  99.00::numeric(5,2),
  '(M8) UPDATE: SAME totp D at aal2 -- the UPDATE now APPLIES (value is 99.00) -- proves (M7) is non-vacuous'
);

-- (M9) DELETE: totp D at aal1 -> USING hides the row -> 0 rows affected, row
--      still present.
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.planning_target where sub_cat_id = :d_sub;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.planning_target where sub_cat_id = :d_sub)::bigint,
  1::bigint,
  '(M9) DELETE: totp D at aal1 -- the DELETE USING aal2 backstop hides D''s own row (0 rows affected); the row STILL EXISTS -- RED if the backstop were dropped from planning_target_delete USING'
);

-- (M10) DELETE: SAME totp D at aal2 -> succeeds, row gone.
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.planning_target where sub_cat_id = :d_sub;
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.planning_target where sub_cat_id = :d_sub)::bigint,
  0::bigint,
  '(M10) DELETE: SAME totp D at aal2 -- the DELETE now APPLIES (row is GONE) -- proves (M9) is non-vacuous; DELETE is what makes "unset = row absent" writable (the migration''s own POSTURE rationale for granting DELETE at all)'
);

-- (M11) cross-tenant-at-aal2: B (none-policy, at BOTH aal1 and aal2) STILL sees
--       0 of A's rows -- proves the aal conjunct is ANDed with, never REPLACES,
--       the tenant predicate.
select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.planning_target where users_id = %L', :'ta')),
  0::bigint,
  '(M11) cross-tenant-at-aal2: intruder B, EVEN claiming aal2, STILL sees 0 of A''s rows -- the aal conjunct is ANDed with the tenant predicate, never replaces it; MFA strength never weakens another tenant''s fence');

-- (M12) ⭐ QA FINDING leg (SELF-242 review): cross-tenant DELETE -- B (none-policy,
--       claiming aal2) targets A's REAL sub_cat_id (a_sub, 25.00 from BLOCK 1,
--       untouched until BLOCK UP below) with a DELETE, not a SELECT. (M9/M10)
--       only exercise planning_target_delete's aal2 backstop on D's OWN row;
--       (M11) only exercises a cross-tenant SELECT. Neither proves a
--       cross-tenant DELETE path is fenced -- a battery asserting only
--       same-tenant aal2-gating and cross-tenant READ isolation for this
--       policy would go green while a cross-tenant DELETE stayed unexercised
--       (the header box's own caution, applied to the fourth verb).
--       ⭐ EMPIRICALLY VERIFIED MECHANISM (corrects this test's own first-draft
--       assumption, in the L2a/M5 self-correcting tradition this file already
--       keeps): a DELETE requires its target row to be visible per BOTH
--       planning_target_delete's OWN USING clause AND planning_target_select's
--       USING clause -- Postgres ANDs them, since a row must be "seen" (SELECT
--       policy) to be removed (DELETE policy). Corrupt-the-control (manual,
--       off-file, against a scratch DB) confirmed BOTH tenant predicates are
--       INDEPENDENTLY sufficient: `alter policy planning_target_delete ...
--       using (true)` ALONE still left this cross-tenant DELETE at 0 rows
--       (blocked by SELECT's own clause); restoring DELETE's clause and
--       instead opening ONLY planning_target_select to `using (true)` ALSO
--       still blocked it. Only opening BOTH admits the cross-tenant DELETE.
--       This assertion is therefore RED only if BOTH tenant predicates were
--       dropped together -- it does not isolate DELETE's own clause the way
--       (M9)/(M10) isolate its aal2 half, and that is stated rather than
--       overclaimed.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal2');
delete from pfin.planning_target where sub_cat_id = :a_sub;
select set_config('role', 'postgres', true);
select is(
  (select target_percent from pfin.planning_target where users_id = :'ta' and sub_cat_id = :a_sub),
  25.00::numeric(5,2),
  '(M12) cross-tenant DELETE: intruder B (none-policy, claiming aal2) targets A''s REAL sub_cat_id (a_sub) with a DELETE -- BOTH planning_target_select''s AND planning_target_delete''s own tenant predicates independently block it (a DELETE requires SELECT-policy visibility of its target -- Postgres-verified, see comment above); A''s row SURVIVES UNCHANGED at 25.00 -- RED only if BOTH tenant predicates were dropped together, independent of (M9/M10)''s same-tenant aal2-backstop proof and (M11)''s cross-tenant SELECT proof'
);

-- =====================================================================
-- BLOCK UP (authenticated A) — UPSERT reassign path on the (users_id, sub_cat_id)
--   unique key (Decision 18: settings are not audit-class; no edit-history rows).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.planning_target (sub_cat_id, target_percent) values (:a_sub, 77.00)
  on conflict (users_id, sub_cat_id) do update set target_percent = excluded.target_percent;
select set_config('role', 'postgres', true);

-- (UP1) UPSERT reassigned a_sub's row IN PLACE (77.00, was 25.00 from BLOCK 1) --
--       no new row (still exactly 2 rows owned by A, per (R1)).
select is(
  (select target_percent from pfin.planning_target where users_id = :'ta' and sub_cat_id = :a_sub),
  77.00::numeric(5,2),
  '(UP1a) UPSERT reassign: ON CONFLICT (users_id, sub_cat_id) DO UPDATE reassigns A''s a_sub target IN PLACE (25.00 -> 77.00)'
);

-- =====================================================================
-- BLOCK X (postgres) — CORRUPT-THE-CONTROL: prove RLS, not application logic,
--   confines a caller to its own rows. No limit-1-style selector is in play
--   here (see the header box) -- this asserts an EXACT expected value, not
--   merely non-null/non-own.
-- =====================================================================
savepoint sp_leak;
alter policy planning_target_select on pfin.planning_target using (true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select target_percent from pfin.planning_target where sub_cat_id = :b_sub),
  60.00::numeric(5,2),
  '(X1) ⭐ CORRUPT-THE-CONTROL: with planning_target_select broken OPEN (using (true)), authenticated A''s query for B''s sub_cat_id returns B''s REAL value (60.00) -- proving RLS, not application logic, is what confines A to its own rows. A plain equality-filtered read (no limit-1 selector), so this is immune to the #474 displacement class -- RED here is the proof the fence is real'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_leak;

-- =====================================================================
-- BLOCK G (anon) — zero-grant.
-- =====================================================================
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.planning_target',
  '42501', null,
  '(G1) anon zero-grant: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (42501), before RLS is ever consulted -- the table is not anon-reachable'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK CASC (postgres) — tenant-cascade: deleting the auth.users row cascades
--   E's planning_target row (ON DELETE CASCADE on users_id). Isolated tenant
--   (E), touched nowhere else in this file.
-- =====================================================================
insert into pfin.planning_target (users_id, sub_cat_id, target_percent) values (:'te', :te_sub, 50.00);

select is(
  (select count(*) from pfin.planning_target where users_id = :'te')::bigint,
  1::bigint,
  '(CASC1a) fixture check: E has exactly 1 planning_target row before the cascade'
);

delete from auth.users where id = :'te';

select is(
  (select count(*) from pfin.planning_target where sub_cat_id = :te_sub)::bigint,
  0::bigint,
  '(CASC1b) tenant-cascade: deleting E''s auth.users row CASCADES E''s planning_target row (users_id ON DELETE CASCADE) -- no orphaned %Target survives a deleted tenant'
);

select * from finish();
rollback;
