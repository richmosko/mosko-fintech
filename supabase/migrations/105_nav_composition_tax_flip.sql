-- ============================================================================
-- Migration: 105 — pfin.fn_nav_composition: the §2.5.4 TAX FLIP. The two
--   0::numeric tax literals — BOTH the `buildups` rows AND the two inside the
--   `nav` arithmetic — are replaced by 104's two nav_components envelopes.
--   Phase 6 Build Loop, V1.4 (§2.1.5 / §2.5.4) — Linear SELF-268.
--
-- ⚠ THIS CHANGES THE VALUE OF NAV. It is the DB half of a ONE-WAY DOOR ruled by
--   F/CTO at R3 as PM's (A′) on 2026-09-03 and recorded at ADR-067 Decision 3.
--   Sec joint-review MANDATORY (financial calculation + the definition of NAV).
--
-- WHAT THIS DOES: replaces exactly one function. NO table, NO column, NO index,
--   NO policy, NO trigger, NO enum, NO grant on any table. It reads and it
--   composes; it writes nothing.
--
-- Numbering: 105, taken against the live listing at authoring time (001..104 on
--   main at 524d273) and NOT reserved ahead. Order-dependent.
--   Depends on: 102 (the body this replaces, its leaf-set exclusion, and
--   fn_tax_authority_ledgers), 104 (fn_compute_tax_liability — the callee),
--   079 (the STABLE pin CREATE OR REPLACE would otherwise silently reset),
--   049 as re-issued at 056 (the leaf substrate), 051 (the original function).
--   Nothing on main depends on 105.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS IS, IN ONE PARAGRAPH. §2.1.5's buildup ladder has carried two tax
--   rows as literal zeros since 051. 104 now computes the two figures. This
--   migration threads them in: the two `buildups` keys carry 104's envelopes
--   verbatim, and the `nav` expression SUBTRACTS the amounts. The §2.1.1
--   headline and the §2.1.5 foot then read ONE composed value from ONE reader
--   (R3 rider 0) — the headline's read-source move is Backend's half, in
--   api/src/lib/server/queries/netWorth.ts, and is NOT in this file.
--
-- ⚠ AC 3a IS ALREADY ON main AND IS NOT RE-LANDED HERE. SELF-268's AC 3a (the
--   tax-authority leaf-set exclusion) shipped at 102: the `leaf` CTE below
--   already carries `left join pfin.fn_tax_authority_ledgers() tal … where
--   tal.account_id is null`. Verified on the tree before drafting, and the
--   anti-join arrives here unchanged as part of the substituted body. What
--   SELF-268 owes the DB is the tax scalars, and only those.
--
-- ⚠ HOW THIS BODY WAS PRODUCED — SUBSTITUTION, NOT RETYPING. The base is 102's
--   fn_nav_composition text (which IS the live catalog definition: nothing
--   between 102 and 104 re-creates this function, and 104's own verification
--   measured md5(prosrc) unchanged across a chain with and without it). FIVE
--   anchored substitutions, each asserted to match EXACTLY ONCE, applied by
--   literal string replacement — so everything outside those five spans is
--   byte-identical to 102 BY CONSTRUCTION rather than by inspection. The five:
--   the `sums` CTE's tail (to append the two tax CTEs), the assemble comment
--   block, the two `buildups` literals, the `nav` expression's two literals,
--   and the final `from` clause.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER, and the SECURITY DEFINER allowlist is UNCHANGED — read it
--   live at ADR-011 Decision 9; this file states no count.
--
--   The posture is 102's, unchanged, and it is the only correct one: every
--   figure this function emits is a figure about the CALLER, over tables that
--   are owner-scoped by RLS. A DEFINER form would compose one user's NAV with
--   another user's row visibility. A cross-tenant caller sees no accounts, no
--   ledgers and no schedules, so it gets empty groups, a nav of 0 and two
--   `unavailable` envelopes — it FAILS CLOSED, into a shape that says so.
--
--   EXECUTE posture UNCHANGED: revoked from PUBLIC, granted to `authenticated`.
--   CREATE OR REPLACE preserves the existing ACL, so the pair below is a
--   RE-ASSERTION, not a change — restated because every shipped reader carries
--   it and a missing one is a silent divergence.
--   ⚠ THE STRENGTH OF THAT GRANT IS A PROPERTY OF THE CALLER (ADR-011 Decision
--   4's 2026-09-03 amendment: multiplicity of layers is a property of a surface
--   AND the writer). For `authenticated` — the only role granted — RLS on every
--   underlying table applies regardless and the grant is the weakest fence. For
--   a `rolbypassrls` caller RLS applies to nothing and the grant is the ENTIRE
--   perimeter; `service_role` has NO EXECUTE here, and that ABSENCE is what
--   makes the surface correct for it. STANDING CONDITION, inherited from 104
--   because this function now composes 104's money figures: any grant of
--   EXECUTE on either function to a `rolbypassrls` role is Sec-JOINT-REVIEW-
--   MANDATORY.
--
-- ----------------------------------------------------------------------------
-- VOLATILITY — `stable`, DECLARED IN THE BODY, PER SIGNATURE (R3 rider 7).
--   `create or replace` RESETS volatility to the language default, so the
--   declaration cannot live in a later `alter function`.
--
--   ⚠ PREMISE CORRECTION, carried from E26 / ADR-067 Decision 5 and repeated
--   here because SELF-268 AC 4c states the falsified form: AC 4c says "051 and
--   049 carry no declaration today and default VOLATILE." That is FALSE on the
--   tree — 079_volatility_pin_stable.sql pinned fn_account_unrealized_gl(date),
--   both fn_compute_nav signatures and fn_nav_composition(date) to `stable`,
--   and 102 re-declares `stable` explicitly when it re-creates this function.
--   THE INSTRUCTION AC 4c GIVES IS RIGHT AND IS FOLLOWED HERE; only its stated
--   reason is stale, and it is corrected by amendment rather than by dropping
--   the instruction. Omitting the declaration would silently un-pin the
--   function and redden 079's own battery leg (pg_proc.provolatile = 's') with
--   no value anywhere changing.
--
--   `stable` is honest here: the new callee, fn_compute_tax_liability(date), is
--   itself `stable` and writes nothing (104 states the argument over its own
--   transitive read set, including the two unpinned-but-read-only functions
--   fn_gl_entries(date) and fn_holdings_as_of(date); that argument is NOT
--   restated here — read it at 104).
--
-- ----------------------------------------------------------------------------
-- SIGN CONVENTION (AC 7 / Sec M-3) — STATED HERE SO FRONTEND ADDS NO SECOND FLIP.
--   Before this migration `debt` was the ladder's ONLY flipped row: 051 emits it
--   as a positive magnitude and the consumer negates it at ONE site. That site
--   stays; the two tax rows JOIN it rather than move it. ONE SITE, THREE ROWS.
--     • This function emits `debt` as a POSITIVE MAGNITUDE (= −(liability
--       subtotal)) and the two tax `amount`s with 104's SIGN UNCHANGED (no abs,
--       no re-clamp, no negation). A POSITIVE tax amount is a liability OWED; a
--       NEGATIVE realized amount is an OVERPAYMENT RECEIVABLE.
--     • `nav` SUBTRACTS all three.
--     • The CONSUMER's ladder NEGATES ALL THREE at its SINGLE flip site
--       (displayValue = −value, applied to debt, realized and unrealized alike).
--       That is ONE NEGATION SITE APPLIED TO THREE ROWS — not one row flipped and
--       two passed through. Two things follow, and they are the whole point of
--       the convention: a leading minus means "reduces NAV" on EVERY row, so the
--       column FOOTS (gross_total + Σ displayed = nav); and a NEGATIVE realized
--       amount renders POSITIVE — an ADD-BACK, which is exactly what an
--       overpayment receivable does to net worth. There is no flip in this file.
--     • Ruled at V1.4 execution-log E44 (2026-09-04) on Sec's freeze-review
--       F-1 / F-2: option (A), the consumer negates all three, chosen over
--       leaving the two tax rows unflipped so ONE visual convention holds across
--       all five ladder rows. The code is being changed to match this comment,
--       not this comment weakened to match the code.
--   ⚠ Realized is SIGNED and NOT clamped: an overpayment is a genuine receivable,
--   so its `amount` is NEGATIVE and NAV RISES by the excess — R3 / E-2 option (A).
--   ⚠ Unrealized is clamped at zero BY 104 (R9 / Sec M-2); this file re-clamps
--   nothing and CITES rather than restates the clamp's rationale, whose single
--   home is 104's `comment on function`.
--
-- ----------------------------------------------------------------------------
-- THE PAYLOAD SHAPE, AND WHY IT IS A DECISION RATHER THAN A SHAPE.
--   104 returns each scalar as an ENVELOPE — {status:'computed', amount} or
--   {status:'unavailable', reason:<stable machine code>} — because two states
--   that must mean one thing belong in the TYPE and not in consumer discipline
--   (ADR-067 Decision 5). This function carries those envelopes THROUGH,
--   VERBATIM, as the `buildups.realized_tax_liab` / `buildups.unrealized_tax_liab`
--   values. THOSE TWO KEYS ARE NO LONGER NUMERIC.
--     • WHY: one representation of one fact, so there is no drift surface. A
--       consumer writing `?? 0` or currency-formatting the key receives an
--       OBJECT and fails at the first arithmetic, instead of rendering "no
--       ledger is designated" as "$0 is owed" — Sec B3's watcher by
--       construction. And the keys' change of MEANING arrives as a compile
--       error rather than being inherited invisibly, which is 104's own
--       `quarters_elapsed` precedent applied one layer down.
--     • LOSING SIDE, NAMED: it is a BREAKING contract change on two shipped
--       keys. api/src/lib/nav-composition.ts's NavCompositionBuildups must
--       change and buildupRows() must unwrap `.amount` (both inside SELF-268
--       AC 2 already); every pgTAP leg asserting `buildups->>'realized_tax_liab'
--       = '0'` goes red (they go red under AC 1 regardless); and the payload
--       stops footing LITERALLY off `buildups` — checking
--       nav = gross_total − debt − realized − unrealized now needs an unwrap.
--       That last cost is affordable because NOTHING IN CODE RE-FOOTS: the
--       component renders `nav` directly as the foot and buildupRows() renders
--       rows. The alternative shape (numeric keys plus a parallel
--       tax_components block) represents the amount TWICE and leaves a consumer
--       reading `buildups` alone rendering $0 as a determination.
--
--   THE UNAVAILABLE CASE IS THE BOOTSTRAP DEFAULT, NOT AN EDGE CASE. Ruled at
--   E26 (1) / ADR-067 Decision 5: an unavailable scalar SUBTRACTS ZERO and the
--   §2.1.5 row renders unavailable-WITH-REASON. No ledger is designated at
--   signup, so this is the state EVERY user starts in, and NAV therefore reads
--   HIGH by the tax lines' worth until a ledger is designated — the same
--   direction as R3 rider 0b. That makes the rendered reason LOAD-BEARING
--   rather than decorative (SELF-268 AC 10a): it is the only observer of the
--   default state on this surface. The `coalesce(…, 0)` in tax_scalars below is
--   the single home of that rule; a consumer re-deriving it keeps a second copy.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS MIGRATION DOES NOT TOUCH — the intended end state, not an oversight.
--   pfin.fn_compute_nav(date) and pfin.fn_compute_nav(date, boolean) are
--   UNCHANGED (md5(prosrc) of both measured against a control chain). They keep
--   the GROSS definition, keep writing pfin.nav_daily, and are then read by NO
--   LIVE SURFACE once Backend moves the §2.1.1 headline. pfin.nav_daily stays
--   the gross pre-tax series PERMANENTLY and carries no definition-version
--   column; a back-fill of past rows is Sec-VETOED (R3) because the tax state
--   for a past date is not recoverable and a back-fill would be a fabrication
--   with the shape of a measurement. The checkpointed series carries NO
--   definitional step at changeover, because the definition it freezes never
--   changed.
--
-- ----------------------------------------------------------------------------
-- LEDGERS — nothing moves.
--   §10: ADR-011 Decision 4 was read VERBATIM and LIVE before drafting, and the
--     three axes are clean — nothing appended, reordered or renumbered; no layer
--     re-attributed; no surface becomes "four-layer". The catalogued list is NOT
--     restated here (Path B — the link carries it) and NO COUNT is stated.
--     ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are
--     not reconciled here.
--   ADR-011 Decision 3: UNCHANGED and not extended — this migration creates no
--     table, no column and no FK-shaped reference of any kind, so no
--     matched-tenant obligation arises. Read Decision 3's body live.
--   ADR-011 Decision 9: the SECURITY DEFINER allowlist is UNCHANGED; this
--     function is and stays INVOKER under Lock 11.
--
-- ----------------------------------------------------------------------------
-- NAMED RESIDUALS — recorded so a reader does not conclude the case is handled.
--   (1) NAV READS HIGH BY DEFAULT. Stated above under the unavailable case; it
--       is the bootstrap state of every new user and its only observer on this
--       surface is the rendered reason.
--   (2) 104's `nav_components` is non-NULL BY CONSTRUCTION, not by fence. Its
--       two envelopes come from a CTE that cross-joins two single-row CTEs (a
--       bare aggregate and a bare scalar select), so it always yields exactly
--       one row and both envelopes are always objects. This function therefore
--       does NOT defend against a JSON-null envelope — a defensive coalesce
--       there would render a malformed payload as $0, which is the failure the
--       envelope exists to prevent. It is a WATCHER's job, not a fence's: a
--       battery leg asserting both keys are objects with a `status` is what
--       makes a future 104 change fail loudly here.
--   (3) 104's OVERSTATEMENT RESIDUAL PROPAGATES. While wash_sale basis_adjust
--       and substantive corp_action remain Suspense-parked (035 / 037),
--       cost_basis is understated, 049's unrealized_gl is overstated, and the
--       Unrealized figure this function now subtracts is overstated — so NAV
--       reads LOW by that amount. 104 records the residual; it is named here
--       because this is where it first reaches NAV.
--   (4) THE §10.5e nav_daily SELECT-POLICY OBLIGATION HAS NO READER ON THIS
--       PATH. R3's consequence list places it on "the §2.1.5 read-time path at
--       051". Measured in the catalog on a clean apply, not grepped from the
--       file: NEITHER this function NOR fn_compute_tax_liability READS
--       pfin.nav_daily — `position('nav_daily' in prosrc) > 0` is FALSE for both
--       bodies, which is the same property 104 pins on itself. The obligation's
--       referent does not exist on this path; it is recorded rather than
--       silently dropped, so a later reader does not take its absence for a
--       discharge. ⚠ The reason the body prose above says "the checkpointed
--       daily series" rather than naming the table: that measurement cannot
--       distinguish a comment from a read, and an earlier draft of this file
--       flipped the property to TRUE from a COMMENT alone.
--   (5) PERFORMANCE. Every §2.1.5 composition read now also runs 104, which
--       walks bracket schedules, cash-flow items and the unrealized aggregate.
--       Not measured against a load target; no V1 target exists. Named so a
--       later latency finding is not read as a regression of unknown origin.
--       ⚠ THE MULTIPLIER SEC N-1 NAMED WAS REAL, AND IS NOW MEASURED AND FIXED.
--       With the `tax` CTE unqualified it is referenced once, so the planner
--       INLINES it and tax_scalars' FOUR dereferences of t.nc each carried their
--       own evaluation: MEASURED 4 calls of fn_compute_tax_liability per 1 call
--       of fn_nav_composition, and 1 after adding `materialized`
--       (pg_stat_user_functions.calls under track_functions = 'all', on a
--       pfin_tmpl clone with this migration applied, 2026-09-04). Correctness
--       was never at stake - the callee is STABLE, so every evaluation agreed
--       within the statement - the COST was. What remains unmeasured is the
--       ABSOLUTE cost of that one 104 evaluation inside the composition read.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_composition(p_as_of date default current_date) RETURNS jsonb —
--     { groups: [ { category, accounts: [ { account_id, account_name,
--                   current_market_value, unrealized_gl } ], subtotal } ],
--       buildups: { total_non_re: numeric, gross_total: numeric, debt: numeric,
--                   realized_tax_liab:   <104 envelope>,
--                   unrealized_tax_liab: <104 envelope> },
--       nav: numeric }
--     SECURITY INVOKER · stable · set search_path = '' · EXECUTE: authenticated.
--     `debt` is a POSITIVE MAGNITUDE. The two envelope `amount`s carry 104's
--     sign. `nav` subtracts debt and both amounts, treating an unavailable
--     envelope as 0. `nav` is NEVER NULL.
--
-- QA PAIRING, SAME PR (SELF-269). The legs each fence here needs to be
--   falsifiable: both envelopes reach `buildups` as OBJECTS carrying `status`;
--   a tenant with both scalars computed has nav lower by exactly their sum than
--   the same tenant's pre-105 nav; a tenant with NO designated ledger gets
--   `realized_tax_liab.status = 'unavailable'` AND a nav that subtracted zero
--   (not a NULL nav); an OVERPAID tenant (negative realized amount) has nav
--   HIGHER, which is the leg that goes red if someone abs()es or clamps it; the
--   negative-aggregate-G/L fixture pins the R9 clamp at 0 (R9's required leg);
--   provolatile = 's' on this signature; the ACL pair; cross-tenant invisibility;
--   and fn_compute_nav's two signatures byte-identical across the migration.
--   ⚠ A leg that cannot fail is not a test.
-- ============================================================================

create or replace function pfin.fn_nav_composition(p_as_of date default current_date)
returns jsonb
language sql
security invoker
stable
set search_path = ''
as $$
  with
  -- LEAF rows: 049 (single substrate — per active account current_market_value + unrealized_gl,
  -- naturally signed) joined to pfin.account for name + account_type (grouping key). 049 already
  -- filters by the as-of predicate (closed_at is null or closed_at::date > p_as_of) — the
  -- boolean flag it used to filter on was RETIRED at 059 — so composing on 049
  -- inherits the correct filter for free. This function adds NO predicate of its
  -- own, and MUST NOT: adding one here would double-filter. If you came looking
  -- for 'where acc.is_active' in 049 because an older comment sent you, that is
  -- what this note replaces.
  leaf as (
    select
      g.account_id,
      a.name          as account_name,
      a.account_type  as category,
      g.current_market_value,
      g.unrealized_gl
    from pfin.fn_account_unrealized_gl(p_as_of) g
    join pfin.account a on a.account_id = g.account_id
    -- E-2 EXCLUSION (SELF-267 AC 2a / R3): tax-authority-designated ledgers leave the
    -- leaf set. The predicate is NOT written here — pfin.fn_tax_authority_ledgers() is
    -- its single home (ADR-063 Decision item 2). ANTI-JOIN, not a correlated NOT EXISTS:
    -- one call, and a designated ledger's absence from the helper (another tenant's, or
    -- an unmarked one) leaves the row IN, which is the pre-102 behaviour.
    left join pfin.fn_tax_authority_ledgers() tal on tal.account_id = g.account_id
    where tal.account_id is null
  ),

  -- CANONICAL category ordering (asset half → real_estate → liability; PRD §2.1.5 / AC#2).
  cat_order (category, ord) as (
    values ('depository', 1), ('investment', 2), ('retirement', 3), ('crypto', 4),
           ('manual_other', 5), ('real_estate', 6), ('liability', 7)
  ),

  -- Per-category group: leaf array (ordered by account_id) + category subtotal (natural sign).
  grp as (
    select
      l.category,
      jsonb_agg(
        jsonb_build_object(
          'account_id',           l.account_id,
          'account_name',         l.account_name,
          'current_market_value', l.current_market_value,
          'unrealized_gl',        l.unrealized_gl        -- NULL for non-investment (049, AC#3)
        ) order by l.account_id
      )                       as accounts,
      sum(l.current_market_value) as subtotal            -- liability subtotal is naturally negative
    from leaf l
    group by l.category
  ),

  -- groups[] JSON in canonical order; empty categories omitted (A4). '[]' if no accounts.
  groups_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('category', grp.category, 'accounts', grp.accounts, 'subtotal', grp.subtotal)
        order by co.ord
      ),
      '[]'::jsonb
    ) as groups
    from grp join cat_order co on co.category = grp.category
  ),

  -- BUILDUP components over the FULL active-account leaf set (independent of emitted groups).
  -- total_non_re = asset-half excl. real_estate; real_estate + liability split out for the foot.
  sums as (
    select
      coalesce(sum(l.current_market_value)
               filter (where l.category not in ('real_estate', 'liability')), 0) as total_non_re,
      coalesce(sum(l.current_market_value)
               filter (where l.category = 'real_estate'), 0)                     as real_estate,
      coalesce(sum(l.current_market_value)
               filter (where l.category = 'liability'), 0)                       as liability_signed
    from leaf l
  ),

  -- §2.5.4 TAX SCALARS — ONE call to the keystone helper (104 / SELF-262), with
  -- 051's OWN p_as_of threaded UNCHANGED (R3 rider 4; ADR-067 Decision 5: the same
  -- fn_server_today() value must reach both functions on one request, or the §2.1.5
  -- foot reconciles to nothing). ONE call and not two: two calls could observe two
  -- snapshots and the emitted rows would then foot to a nav computed from neither.
  -- MATERIALIZED IS LOAD-BEARING, NOT DECORATION (Sec N-1). This CTE is referenced
  -- exactly ONCE, so PostgreSQL would INLINE it, and tax_scalars below dereferences
  -- t.nc FOUR times: MEASURED four evaluations of the 104 callee per ONE call of this
  -- function without the keyword, and ONE with it (pg_stat_user_functions.calls under
  -- track_functions = 'all', pfin_tmpl clone, 2026-09-04). Correctness never depended
  -- on it - the callee is STABLE, so all four agreed within the statement - but COST
  -- did, and this is the dashboard's main query. The (ONE) battery leg pins the SOURCE
  -- text and is unmoved by this keyword; MATERIALIZED is what makes the RUNTIME count
  -- match what that leg is read as saying.
  -- The callee's NAME is deliberately not repeated in this comment: the (ONE) leg's
  -- companion note counts bare name-substring occurrences in prosrc, and a mention
  -- here would move that count with no call having moved.
  tax as materialized (
    select pfin.fn_compute_tax_liability(p_as_of) -> 'nav_components' as nc
  ),

  -- The ENVELOPE is carried VERBATIM into buildups; only the SUBTRACTED scalar is
  -- unwrapped, here and nowhere else. `->> 'amount'` is NULL on an unavailable
  -- envelope (that key is absent by construction, not null), and the coalesce is the
  -- whole of E26 ruling (1): AN UNAVAILABLE SCALAR SUBTRACTS ZERO, and the §2.1.5 row
  -- renders unavailable-WITH-REASON rather than $0. A consumer that re-foots the
  -- ladder off `buildups` would be keeping a SECOND COPY of that rule — do not.
  tax_scalars as (
    select
      t.nc -> 'realized_tax_liab'                                        as realized_env,
      t.nc -> 'unrealized_tax_liab'                                      as unrealized_env,
      coalesce((t.nc -> 'realized_tax_liab'   ->> 'amount')::numeric, 0) as realized_applied,
      coalesce((t.nc -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0) as unrealized_applied
    from tax t
  )

  -- Assemble. THREE SUBTRACTIVE ROWS, ONE SIGN CONVENTION, ONE FLIP SITE - AND THE
  -- FLIP SITE IS NOT HERE (AC 7 / Sec M-3). `debt` is emitted as a POSITIVE MAGNITUDE
  -- (= -liability_signed), and the two tax envelopes carry 104's `amount` WITH ITS SIGN
  -- UNCHANGED - positive means a liability OWED, a NEGATIVE realized amount is an
  -- OVERPAYMENT RECEIVABLE; `nav` SUBTRACTS all three. The consumer's ladder NEGATES
  -- ALL THREE at its SINGLE flip site (displayValue = -value for debt, realized and
  -- unrealized alike): ONE SITE, THREE ROWS - not one row flipped and two passed
  -- through. So a leading minus means "reduces NAV" on every row, the column FOOTS,
  -- and a negative realized amount renders POSITIVE as the add-back an overpayment
  -- receivable is. A SECOND FLIP ANYWHERE RENDERS A CORRECT VALUE WITH THE WRONG
  -- SIGN, which is the double-negation route Sec M-3 names. Frontend adds no flip of
  -- its own beyond that one site (ruling E44, 2026-09-04).
  --   * REALIZED IS SIGNED AND IS NOT CLAMPED (104, deliberately asymmetric with 102's
  --     fn_ytd_paid_per_jurisdiction, and the two must not be reconciled): an OVERPAYMENT
  --     is a genuine receivable, so `amount` goes NEGATIVE and nav RISES by the excess -
  --     the behaviour R3 / E-2 option (A) ruled. Do not abs() it and do not clamp it here.
  --   * UNREALIZED IS CLAMPED AT ZERO BY 104 (R9 / Sec M-2). This function re-clamps
  --     nothing and deliberately does NOT restate the reason: the clamp's WHY lives in
  --     fn_compute_tax_liability's `comment on function`, which is its single home. Read
  --     it THERE before "restoring symmetry" by removing it.
  -- FOOT-TO-NAV, AND THE fn_compute_nav IDENTITY IS BROKEN TWICE OVER, BOTH TIMES ON
  -- PURPOSE - IT IS NOT A DEFECT TO REPAIR:
  --   nav = (total_non_re + real_estate) - debt - realized_applied - unrealized_applied,
  --   summed over the leaf set MINUS every tax-authority-designated ledger (102).
  --   fn_compute_nav(p_as_of, true) keeps its GROSS definition, keeps writing the
  --   checkpointed daily series, and is UNTOUCHED by this migration; the two therefore
  --   differ by the designated ledgers'
  --   balances (102) PLUS the two tax scalars (here). Within this function the buildup
  --   still foots to its own nav by construction.
  select jsonb_build_object(
    'groups',   (select groups from groups_json),
    'buildups', jsonb_build_object(
      'total_non_re',        s.total_non_re,
      'gross_total',         s.total_non_re + s.real_estate,
      'debt',                -s.liability_signed,
      -- ENVELOPES, NOT NUMERICS - {status:'computed', amount} | {status:'unavailable', reason},
      -- carried verbatim from 104. The TYPE is the fence (ADR-067 Decision 5): a consumer
      -- writing `?? 0` or formatting this as currency receives an OBJECT and fails at the
      -- first arithmetic, instead of rendering "no ledger designated" as "$0 owed".
      'realized_tax_liab',   t.realized_env,
      'unrealized_tax_liab', t.unrealized_env
    ),
    'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - t.realized_applied - t.unrealized_applied
  )
  from sums s cross join tax_scalars t;
$$;

-- EXECUTE posture RE-ASSERTED, not changed (CREATE OR REPLACE preserves the ACL).
revoke execute on function pfin.fn_nav_composition(date) from public;
grant execute on function pfin.fn_nav_composition(date) to authenticated;

-- ----------------------------------------------------------------------------
-- THE `comment on function` IS REWRITTEN IN THIS MIGRATION, NOT LATER — R3
--   rider 3 / SELF-268 AC 9b. The comment 102 left in the catalog asserts that
--   the tax scalars "are STILL 0::numeric literals here", and it is FALSIFIED by
--   the same migration that lands this change. A `comment on …` has a database
--   representation: it can only be corrected by emitting a new one, so
--   correcting it later is not available. The in-body placeholder captions
--   beside the two tax keys are struck in the same act; no ramp-era caption
--   survives in this file or in the catalog.
-- ----------------------------------------------------------------------------
comment on function pfin.fn_nav_composition(date) is
  'SECURITY INVOKER §2.1.5 NAV-composition aggregation, TAX-ADJUSTED (PRD §2.1.5 + §2.5.4; SELF-225 / SELF-268; Lock 11 read-composition). Returns the composition tree as JSONB: {groups:[{category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}], subtotal}], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, nav}. ⚠ THE TWO TAX KEYS ARE ENVELOPE OBJECTS, NOT NUMERICS — {status:''computed'', amount} or {status:''unavailable'', reason:<stable machine code>} — carried VERBATIM from pfin.fn_compute_tax_liability''s nav_components. That is the TYPE doing the work rather than consumer discipline (ADR-067 Decision 5): a consumer writing `?? 0` or currency-formatting the key receives an OBJECT and fails at the first arithmetic instead of rendering "no ledger is designated" as "$0 is owed". They were 0::numeric literals until this function was replaced; that is a dated fact about the past, and the keys'' change of MEANING is deliberately delivered as a type change so it cannot be inherited invisibly. COMPOSES ON 049 fn_account_unrealized_gl (single leaf substrate — per active account current_market_value + unrealized_gl, naturally signed) joined to pfin.account for name + account_type; 049 already filters by the AS-OF predicate (closed_at is null or closed_at::date > p_as_of) — the boolean flag it used to filter on was RETIRED at 059 per ADR-042 — and this function still adds NO predicate of its own and MUST NOT (adding one double-filters). LEAF-SET EXCLUSION, unchanged from 102: tax-authority-designated ledgers are ANTI-JOINED OUT, and the predicate is NOT written in this body — pfin.fn_tax_authority_ledgers() is its single home, shared with pfin.fn_ytd_paid_per_jurisdiction (ADR-063 Decision item 2 — that ADR numbers its protocols as ITEMS inside one Decision block). An UNMARKED tax-authority ledger is therefore NOT excluded and NAV reads high by its balance; the designation is a user-set NULLABLE attribute, so that default state is reachable by omission alone and its only observer on this surface is the §2.1.5 rendering of the exclusion. groups[] in canonical category order (depository/investment/retirement/crypto/manual_other → real_estate → liability), empty categories omitted; accounts[] by account_id; leaf unrealized_gl NULL for non-investment (049). ONE CALL, ONE CLOCK: fn_compute_tax_liability is called ONCE, with THIS function''s own p_as_of threaded UNCHANGED (F/CTO ruling R3 rider 4). The caller must pass the SAME fn_server_today() value it passes to any other as-of read on the same request, or the §2.1.5 foot reconciles to nothing. SIGN CONVENTION — ONE FLIP SITE, THREE ROWS, AND THE SITE IS NOT IN THIS FUNCTION: buildups.debt is a POSITIVE MAGNITUDE (= −(liability subtotal); the liability leaves and subtotal carry 049''s natural negative sign), and the two envelope amounts carry fn_compute_tax_liability''s sign UNCHANGED — no abs, no negation, no re-clamp here; a POSITIVE tax amount is a liability OWED and a NEGATIVE realized amount is an OVERPAYMENT RECEIVABLE. `nav` SUBTRACTS all three. The consumer''s buildup ladder NEGATES ALL THREE at its SINGLE flip site — displayValue = −value for debt, realized and unrealized alike, which is ONE SITE APPLIED TO THREE ROWS and not one row flipped with two passed through — so a leading minus means "reduces NAV" on every row, the column FOOTS (gross_total + Σ displayed = nav), and a NEGATIVE realized amount renders POSITIVE as the add-back an overpayment receivable is. A SECOND FLIP ANYWHERE RENDERS A CORRECT VALUE WITH THE WRONG SIGN. ⚠ REALIZED IS SIGNED AND IS NOT CLAMPED: an overpayment is a genuine receivable, so its amount is NEGATIVE and NAV RISES by the excess (F/CTO ruling R3 / E-2 option A). ⚠ UNREALIZED IS CLAMPED AT ZERO BY fn_compute_tax_liability (ruling R9): this function re-clamps nothing, and the clamp''s RATIONALE is deliberately NOT restated here — its single home is that function''s own comment, and a reader tempted to "restore symmetry" by removing the clamp must read it THERE. THE UNAVAILABLE CASE IS THE BOOTSTRAP DEFAULT, NOT AN EDGE CASE: an envelope with status ''unavailable'' carries no amount, and `nav` SUBTRACTS ZERO for it — never NULL, so the headline is never blanked. No ledger is designated at signup, so this is the state every user starts in and NAV READS HIGH by the tax lines'' worth until one is designated; the §2.1.5 row must therefore render UNAVAILABLE-WITH-REASON rather than $0, and that rendering is the only thing on this surface that says so. The coalesce-to-zero rule lives in this function''s tax_scalars CTE and NOWHERE ELSE — a consumer that re-foots the ladder off buildups is keeping a second copy of it. FOOT-TO-NAV, AND THE fn_compute_nav IDENTITY IS BROKEN TWICE OVER, DELIBERATELY, AND MUST NOT BE "RESTORED": nav = total_non_re + real_estate + Σ liability_signed over the leaf set MINUS every tax-authority-designated ledger, MINUS the two tax amounts. pfin.fn_compute_nav(p_as_of, true) keeps its GROSS definition, still INCLUDES those ledgers, has no tax leg, and is UNTOUCHED — so the two differ by the designated ledgers'' balances PLUS the two tax scalars. The first break is arithmetic (a tax payment lands as cash on a designated ledger while the obligation falls by the same amount, so counting both would raise NAV by money that is gone); the second is the §2.5.4 definition of NAV itself. WITHIN this function the buildup still foots to its own nav by construction (single-substrate natural summation over the filtered leaf set; ADR-038/039; no fn_compute_nav call). pfin.nav_daily stays the GROSS PRE-TAX series PERMANENTLY, is append-only audit-class with no definition-version column, and is NOT back-filled — the tax state for a past date is not recoverable, so a back-fill would be a fabrication with the shape of a measurement (Sec veto, recorded at ruling R3). The checkpointed series carries no definitional step at changeover because the definition it freezes never changed; a surface rendering that series and a surface rendering this nav differ by both tax lines PLUS the designated ledgers'' balances, and copy that says "tax only" is wrong. p_scope DROPPED (pfin.scope type does not exist; scope is a free-text ADR-004 label — per-scope reporting is V2+, PRD §2.1.7); p_users_id DROPPED (INVOKER + RLS scope by auth.uid()). AS-OF via 049 threading (Lock 15). INVOKER → a cross-tenant caller sees no accounts, no ledgers and no schedules → empty groups, nav 0, both envelopes unavailable (fails closed, into a shape that says so). ⚠ That argument covers only callers subject to RLS: for a rolbypassrls caller RLS applies to nothing and the EXECUTE grant is the ENTIRE perimeter rather than the weakest fence; service_role has no EXECUTE here, and that ABSENCE is what makes the surface correct for it. STANDING CONDITION, inherited because this function now composes that function''s money figures: any grant of EXECUTE on this function or on pfin.fn_compute_tax_liability to a rolbypassrls role is Sec-JOINT-REVIEW-MANDATORY. Volatility STABLE, declared in the body per signature because CREATE OR REPLACE resets it; the callee is likewise stable and writes nothing, and the honest volatility argument is stated over the transitive read set in fn_compute_tax_liability''s own comment rather than recomposed here. set search_path = ''''; NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here). §10 catalogued ledger UNCHANGED BY THIS OBJECT — and NO COUNT IS STATED, deliberately: a ledger-impact claim is AUTHORING-TIME PROVENANCE and belongs in a migration header, which is a dated artifact, not in a catalog comment, which reads as LIVE STATE. Read ADR-011 Decision 4 live. Decision 3 unchanged (no table, no column, no FK-shaped reference). NAMED RESIDUAL, propagated rather than introduced: while wash_sale basis_adjust and substantive corp_action remain Suspense-parked at 035/037, cost_basis is understated, so 049''s unrealized_gl is overstated, so the Unrealized amount subtracted here is overstated and NAV reads LOW by that amount. Sec joint-review MANDATORY (financial calculation + the definition of NAV + multi-tenant); RLS verification → the SELF-225 two-tenant battery as extended at SELF-269. §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl and the §2.5.4 Unrealized computation inside fn_compute_tax_liability.';
