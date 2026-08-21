-- ============================================================================
-- Migration: pfin.fn_subcat_contributors — per-Sub-Cat CONTRIBUTOR MAP.
-- Phase 6 Build Loop (SELF-330; PRD §2.2.2 staleness tinting). Read-only over
-- existing relations: NO new base table, NO writes, NO new SECURITY DEFINER,
-- NO new FK-shaped column, NO new grant to service_role.
--
-- WHAT THIS DOES: emits the DISTINCT (sub_cat_id, account_id) pairs that stand
-- behind pfin.fn_subcat_market_value's rows at the SAME arguments — which
-- accounts contribute to which Sub-Cat. It answers "who fed this row", never
-- "how much". The consumer resolves account_id -> pfin.account.linked_source_id
-- -> the `046` stale set (the SELF-229 bridge, reused as-is) and tints the
-- rendered Sub-Cat row from the staleness of its contributors.
--
-- ----------------------------------------------------------------------------
-- RATIFY RECORD (durable) — SHAPE 1 OF 3, F/CTO-ratified 2026-08-20. Recorded
-- here because the two rejected shapes are the ones a future author re-derives
-- if only the code survives, and one of them is actively dangerous.
--
--   S1. A CONTRIBUTOR MAP CARRIES NO MONEY, AND THAT IS THE WHOLE POINT.
--       fn_subcat_market_value participates in a binding financial seam —
--       Σ fn_subcat_market_value(as_of, true) = fn_compute_nav(as_of). A sibling
--       function that returns no monetary column CANNOT move that seam: there is
--       no expression here whose drift could change a total. The seam is
--       untouchable BY CONSTRUCTION rather than by care, which is a different
--       and stronger guarantee than "we were careful".
--   S2. SHAPE 2 REJECTED — DO NOT RE-PROPOSE. "Widen fn_subcat_market_value's
--       return to carry contributors" requires DROP + CREATE (a return-type
--       change cannot go through CREATE OR REPLACE) on a SHIPPED financial
--       function with three live consumers. `072` measured what DROP + CREATE
--       costs: the EXECUTE grants and the catalog comment are destroyed and the
--       function lands PUBLIC-executable by default until rebuilt. Doing that to
--       the function that anchors the NAV seam, to add a column that carries no
--       money, trades a real privilege-surface risk for a convenience.
--   S3. SHAPE 3 REJECTED — DO NOT RE-PROPOSE. "Return a DB-side is_stale
--       boolean per Sub-Cat" collapses three states into two: there is no honest
--       UNKNOWN in a boolean, so a not-yet-computed row becomes `false` (fresh)
--       rather than unknown. That is the SELF-220 round-2 failure repeated on a
--       new surface, and it fails OPEN — a stale row renders as fresh.
--   S4. THE PRODUCER CONSTRAINT IS THE CONSUMER'S, NOT THIS FUNCTION'S. The
--       tri-state (fresh / stale / unknown) lives in the app layer, where a
--       not-yet-computed entry MUST default to null (UNKNOWN) and never to
--       undefined. This function neither implements nor checks that rule, so
--       neither its header nor its catalog comment promises it. It returns pairs.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT WAS DELETED FROM THE MIRRORED BODY, AND — the load-bearing half — WHAT
-- WAS NOT. This function is the LIVE fn_subcat_market_value join skeleton, read
-- from the catalog with pg_get_functiondef, with every VALUATION expression
-- removed. "Valuation expression" is not the same category as "filter
-- that decides whether a row exists", and conflating the two silently breaks the
-- parity property below.
--
--   DELETED (pure valuation; none of it can affect which rows exist):
--     · the eod_price latest-on-or-before price sub-select (both legs' pricing),
--     · both FX sub-selects and their `case when currency = 'USD'` wrappers,
--     · `coalesce(sum(v), 0) as market_value` and the GROUP BY it required.
--
--   KEPT, DELIBERATELY (each one decides row MEMBERSHIP, not row VALUE):
--     · `and coalesce(c.balance_native, 0) <> 0` on the cash leg. This is the
--       single most dangerous line to mistake for a valuation expression. It is
--       the ZERO-CASH-ACCOUNTS-EMIT-NO-ROW filter `076` added after measurement:
--       fn_account_cash_as_of is TOTAL over pfin.account, so without it every
--       open account contributes a row that groups under the NULL key. Dropping
--       it here would manufacture a phantom unclassified contributor set for
--       essentially every caller — and would break parity in the direction that
--       is hardest to notice, since the extra key is NULL.
--     · the INNER `join pfin.asset a on a.asset_id = h.asset_id`. Inner, so it
--       is a row filter: a holding whose asset row is not visible drops out.
--       `a.currency` is no longer read, but the JOIN is not therefore removable.
--     · the three-conjunct `059` closure predicate on the LEFT-JOINed securities
--       leg (`acc2.account_id is not null` AND the dated test), and the
--       two-clause form on the directly-joined cash leg. A bare
--       closed_at-is-null on the LEFT-JOINed leg fails OPEN.
--     · the liability cash route (introduced at `081`) and its
--       `lut.users_id = acc.users_id` conjunct — the SOLE tenant discriminator
--       on a join keyed
--       by SHARED-VOCABULARY STRING LABELS ('Liabilities' / 'Liability
--       Balances'), which fails OPEN under an RLS regression where the id-keyed
--       sibling joins fail CLOSED. It is carried here for the same reason the
--       live body carries it, and for the avoidance of doubt it is NOT
--       decorative.
--     · the AC3 real-estate exclusion in its `is distinct from` form, so the
--       NULL-cat group survives it.
--
--   DROPPED FROM THE PROJECTION ONLY (not from the semantics): `cat` and
--     `sub_cat`. Both are functionally determined by `sub_cat_id`
--     (user_taxonomy.id is its primary key), and where the key is NULL all three
--     are NULL together in both legs — so grouping on the id alone cannot merge
--     two distinct groups. `cat` is still computed inside the CTEs because the
--     real-estate exclusion reads it.
--
-- ----------------------------------------------------------------------------
-- THE PARITY PROPERTY — A STANDING REQUIREMENT, ASSERTED IN THE PAIRED BATTERY.
--   For every (p_as_of, p_include_real_estate) and every caller:
--
--     { distinct sub_cat_id from pfin.fn_subcat_contributors(a, b) }
--       ==  { sub_cat_id from pfin.fn_subcat_market_value(a, b) }
--
--   as SETS, in BOTH DIRECTIONS, with NULL treated as equal to NULL (the
--   unclassified key). It holds by construction — identical FROM / JOIN / WHERE,
--   and a grouping key that is a projection of the same expressions — but "by
--   construction" is exactly the claim that stops being true when someone edits
--   one of the two bodies. QA's pgTAP battery ships in the SAME PR and asserts it
--   both directions per the ADR-058 Amendment 2 complement-leg discipline. A SQL
--   sibling without that assertion is an app-layer re-derivation written in SQL.
--   ⚠ The assertion must use set difference (EXCEPT), not an equality join: the
--   unclassified key is NULL and `=` is not true of it. This is stated as the
--   requirement, not as a claim about what any file currently contains.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT THIS FUNCTION DOES NOT GUARANTEE — stated because a consumer will
--   otherwise assume it.
--   · account_id is NOT guaranteed to have a linked source. A manually-managed
--     account contributes here exactly like a connected one, and its
--     pfin.account.linked_source_id is null. "No linked source" is a distinct
--     condition from "linked source is stale", and this function does not
--     collapse them — resolving that is the consumer's, at the `046` hop.
--   · The pair set is NOT a staleness verdict and carries no freshness column.
--   · A Sub-Cat present in fn_subcat_market_value with market_value 0.00 still
--     appears here with its contributors: `076` R3 coalesces value to 0, so a
--     zero row and an all-unpriced row are indistinguishable BY VALUE, and this
--     function keys on group existence rather than on value.
--
-- ----------------------------------------------------------------------------
-- Numbering: 086 follows 085 (taxonomy_element); taken at authoring time against
--   the live listing, not reserved ahead.
--   ⚠ ORDER-DEPENDENT ON `084`, whose re-emission of fn_subcat_market_value is
--   the LIVE definition this skeleton mirrors — NOT `076`, NOT `078` and NOT
--   `081`, each of which has since been replaced. This is not a paper
--   distinction: `084` drops `pfin.user_taxonomy.domain` and re-emits the
--   function without its `domain = 'asset'` join conjuncts, so a skeleton copied
--   from `081`'s file text does not even PARSE against the post-`084` schema.
--   That was caught by a clean-apply of the whole chain onto an empty scratch
--   database, and it is why the skeleton below was rebuilt from the LIVE CATALOG
--   BODY (`pg_get_functiondef`) rather than from any migration file. A migration
--   file states what was true when it landed; only the catalog states what is
--   true now.
--   Depends further on 009 (user_taxonomy: id / cat), 016 (the hybrid asset
--   registry + the global currency-asset rows), 019 (fn_holdings_as_of), 022
--   (user_asset_category), 041 + 080 (the seeded taxonomy incl. the Liabilities
--   catch-all the liability route matches by name), 056 (fn_account_cash_as_of),
--   059 (the dated closure predicate), 003 (account_type), 084 (the domain drop,
--   the re-emitted body, and the unique (users_id, cat, sub_cat) that replaced
--   009's). No downstream migration depends on 086.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. The function only READS, and every relation it reads is
--   already RLS-fenced to the caller — the identical read set as
--   fn_subcat_market_value, minus pfin.eod_price, which this function no longer
--   touches at all. It needs no privilege the caller lacks; DEFINER would turn a
--   read-composition helper into a confused deputy for no benefit.
--   `set search_path = ''` applied. EXECUTE revoked from public, granted to
--   authenticated only. → SECURITY DEFINER allowlist UNCHANGED, adds no entry;
--   ADR-011 Decision 9 was read verbatim and live before drafting — read the
--   allowlist there, it is not restated here.
--   ⚠ NO TENANT PARAMETER, deliberately, and the reasoning is `076` R1 unchanged:
--   tenant scope comes from SECURITY INVOKER plus the caller's own RLS via
--   auth.uid(). A p_users_id would be the confused-deputy foot-gun that `049` R3
--   and `051` A1 both name and drop. This matters MORE here than on the value
--   function, not less: a contributor map is an account-identity disclosure
--   surface, so a caller-supplied tenant would leak account_ids rather than
--   sums.
--   `stable` IS DECLARED. ⚠ It is declared over the same VOLATILE
--   fn_holdings_as_of that `079` recorded as an open interior seam for
--   fn_subcat_market_value: in READ COMMITTED a VOLATILE callee re-establishes a
--   snapshot rather than inheriting the caller's. This function INHERITS that
--   seam from the skeleton it mirrors and does not create it; `079` names the
--   audit-and-pin of fn_holdings_as_of and fn_gl_entries as the follow-up, and
--   closing it partially here would look complete while leaving it open
--   elsewhere. ⚠ Any future CREATE OR REPLACE of this function MUST carry
--   `stable` in its own body — a replace resets volatility silently.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
-- numbered list is NOT restated here and NO count is carried, deliberately).
-- Decision 4 was read verbatim and live before drafting, 2026-08-20. This
-- migration introduces ZERO catalogued §10 instances: a read-only SQL function
-- with no write path, no credential surface, and no network/config surface.
--   (i)   Instance-numbering: unchanged — nothing added, reordered, renumbered.
--   (ii)  Layer-attribution: unchanged — no catalogued instance's layer moves and
--         no surface becomes "four-layer". No grant to service_role, no ACL move.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
-- DE-CONFLATION GUARD: this function is a READ surface. The Lock 14
-- user-facing-direct-DB-write class does not apply to it, and no §10 class
-- membership is claimed here. ⚠ The §10 CATALOGUED set and the CI-FENCED RT set
-- are different sets and are not reconciled here.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family UNCHANGED, +0.
--   ADR-011 Decision 3 was read verbatim and live before drafting, 2026-08-20.
--   This migration creates, alters and drops NO column of any kind, FK-shaped or
--   otherwise, and no INTEGER[] array. It only reads existing relations through
--   existing fences; the references it makes are join predicates inside a query,
--   not stored ones (the `081` precedent). No label is taken. Read Decision 3's
--   numbered list live for the family's shape — the labels are non-contiguous,
--   at least one is DROPPED, and *labeled* versus *DDL-realized* diverge, so no
--   count is carried here.
--
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances unchanged ·
--   SECURITY DEFINER allowlist unchanged · Decision-3 family unchanged ·
--   RT-26 allowlist untouched (no service_role surface) · RT catalog unchanged ·
--   aal2 step-up backstop: no new table, so nothing to inherit the `025` clause.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface), on three independent grounds:
--   (1) a MULTI-TENANT READ on a financial-calculation-adjacent path, whose
--       tenant fence is entirely INHERITED — this function adds no isolation
--       predicate of its own beyond the liability-route conjunct, and
--       relies on the RLS of every relation it reads. If any of those relations
--       lost its policy, this function would silently widen.
--   (2) it is an ACCOUNT-IDENTITY disclosure surface. fn_subcat_market_value
--       discloses sums; this discloses WHICH ACCOUNTS. The blast radius of an
--       isolation failure is different in kind, not merely in degree.
--   (3) it feeds the staleness pipeline, whose failure direction is fail-OPEN
--       (a stale row rendering as fresh), which is why S3 was rejected.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_subcat_contributors(p_as_of date default current_date,
--                               p_include_real_estate boolean default false)
--     RETURNS TABLE (sub_cat_id bigint, account_id bigint)
--     SECURITY INVOKER · STABLE · set search_path = ''
--
--     - DISTINCT (sub_cat_id, account_id) pairs. One pair per (Sub-Cat, account)
--       combination that contributes value to that Sub-Cat under
--       fn_subcat_market_value at the same arguments.
--     - sub_cat_id is NULL for the UNCLASSIFIED contributor set — the same
--       key fn_subcat_market_value emits for its unclassified row. A consumer
--       folding contributor sets MUST match that key by IS NULL, never by
--       equality.
--     - account_id is NEVER NULL. On the securities leg the row is admitted only
--       when the account row resolved (`acc2.account_id is not null`); on the
--       cash leg pfin.account is joined directly and account_id is its primary
--       key.
--     - EMPTY PORTFOLIO RETURNS ZERO ROWS — a set-returning function's empty
--       answer is the empty set.
--     - p_include_real_estate = FALSE (default) excludes cat = 'Real Estate'
--       Sub-Cats entirely, on the exact asset-class taxonomy match, exactly as
--       fn_subcat_market_value does. The unclassified key is never excluded by
--       the flag: its cat is NULL and cannot be known to be Real Estate.
--     - Carries NO monetary column and NO freshness column, by design.
--   Security-load-bearing edges: no tenant predicate is written here except the
--     `lut.users_id = acc.users_id` conjunct carried from the live body — isolation is
--     otherwise INHERITED from the RLS on every relation read, under SECURITY
--     INVOKER. The function writes nothing and grants nothing to service_role.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_subcat_contributors(
  p_as_of               date    default current_date,
  p_include_real_estate boolean default false
)
returns table (
  sub_cat_id bigint,
  account_id bigint
)
language sql
security invoker
stable
set search_path = ''
as $$
  with sec_leg as (
    -- Securities contributors. Skeleton copied from the LIVE catalog body (084's
    -- re-emission of fn_subcat_market_value) with the price and FX expressions
    -- deleted; every JOIN and every WHERE conjunct is
    -- retained, because each one decides row MEMBERSHIP.
    -- CLOSURE PREDICATE (059): pfin.account is reached by LEFT JOIN here, so the
    -- three-conjunct form is mandatory — acc2.account_id is not null AND the
    -- dated test. A bare closed_at-is-null would fail OPEN on a join miss.
    -- CLASSIFICATION: LEFT JOIN the junction and the taxonomy, so an unclassified
    -- (or non-asset-classified) holding keeps its contributor pair and lands
    -- under the NULL key rather than disappearing.
    select
      ut.id        as k_id,
      ut.cat       as k_cat,
      h.account_id as k_account_id
    from pfin.fn_holdings_as_of(p_as_of) h
    -- INNER, and load-bearing as a FILTER even though no column of `a` is read
    -- any more: a holding whose pfin.asset row is not visible drops out here in
    -- fn_subcat_market_value too, and must drop out here as well.
    join pfin.asset a on a.asset_id = h.asset_id
    left join pfin.account acc2 on acc2.account_id = h.account_id
    left join pfin.user_asset_category uac on uac.asset_id = h.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id
    where acc2.account_id is not null
      and (acc2.closed_at is null or acc2.closed_at::date > p_as_of)
  ),
  cash_leg as (
    -- Cash contributors. TWO classification routes, chosen by account_type and
    -- by nothing else (the rule introduced at `081`):
    --   · account_type = 'liability' -> the seeded 'Liabilities' /
    --     'Liability Balances' row in the CALLER'S OWN taxonomy (080), by NAME.
    --   · every other account_type   -> the GLOBAL currency-asset's per-user
    --     junction row (the 022 cash-via-currency-asset model), which yields ONE
    --     Sub-Cat per user per currency and cannot distinguish per account.
    -- ⚠ CONSEQUENCE FOR THE CONSUMER, and it is by design: because non-liability
    -- cash resolves to one Sub-Cat per user per currency, that Sub-Cat's
    -- contributor set is the WIDEST in the map — every open account holding
    -- non-zero cash is in it. One stale institution therefore tints the whole
    -- cash row. That is the L1 substrate limit surfacing, not a defect here.
    -- pfin.account is joined DIRECTLY (not left-joined), so the bare two-clause
    -- 059 predicate is correct — the 049 / 059 cash-leg shape.
    select
      case when acc.account_type = 'liability' then lut.id  else ut.id  end as k_id,
      case when acc.account_type = 'liability' then lut.cat else ut.cat end as k_cat,
      acc.account_id                                                        as k_account_id
    from pfin.account acc
    -- Retained for its WHERE conjunct below, not for a value: the balance is
    -- read only to decide whether the account contributes a row at all.
    left join pfin.fn_account_cash_as_of(p_as_of) c
      on c.account_id = acc.account_id
    left join pfin.asset cur
      on cur.users_id is null
     and cur.asset_type = 'currency'
     and cur.symbol = acc.currency
    left join pfin.user_asset_category uac on uac.asset_id = cur.asset_id
    left join pfin.user_taxonomy ut
      on ut.id = uac.sub_cat_id
    -- LIABILITY ROUTE TARGET, matched by NAME because there is no id to follow:
    -- no junction row points at it, and pfin.account.sub_cat_id was dropped at
    -- 048. At most one row can match — 084's unique (users_id, cat, sub_cat)
    -- — so this cannot multiply rows. LEFT JOIN, never INNER: a caller
    -- missing the 080 row gets NULL keys and the account lands in the
    -- unclassified contributor set rather than vanishing from the map.
    -- ⚠ THE users_id CONJUNCT IS LOAD-BEARING, NOT DECORATIVE — do not strike it
    -- for consistency with the `ut` joins above. Those key on `ut.id =
    -- uac.sub_cat_id`, a TENANT-BOUND surrogate: a foreign id cannot match the
    -- caller's own ids, so they fail CLOSED. This join keys on `cat`/`sub_cat`
    -- STRING LABELS, which are SHARED VOCABULARY across every tenant, so without
    -- `lut.users_id = acc.users_id` it fails OPEN. Carried verbatim from the
    -- live body for the same reason that body carries it.
    left join pfin.user_taxonomy lut
      on lut.users_id = acc.users_id
     and lut.cat      = 'Liabilities'
     and lut.sub_cat  = 'Liability Balances'
    where (acc.closed_at is null or acc.closed_at::date > p_as_of)
      -- ⚠ ZERO-CASH ACCOUNTS EMIT NO ROW — MEMBERSHIP FILTER, NOT A VALUATION
      -- EXPRESSION. fn_account_cash_as_of is TOTAL over pfin.account, so without
      -- this every open account would contribute a pair under the NULL key and
      -- the map would manufacture a phantom unclassified contributor set for
      -- essentially every caller. Deleting it as "part of the valuation" is the
      -- single most likely way to break the parity property, and it would break
      -- it on the NULL key, where it is hardest to see.
      and coalesce(c.balance_native, 0) <> 0
  ),
  both_legs as (
    select k_id, k_cat, k_account_id from sec_leg
    union all
    select k_id, k_cat, k_account_id from cash_leg
  )
  -- REAL-ESTATE EXCLUSION (AC3): `is distinct from` rather than `<>` so the
  -- UNCLASSIFIED group (k_cat IS NULL) survives — an unknown cat cannot be known
  -- to be Real Estate. Identical to fn_subcat_market_value's, and it must stay
  -- identical or the parity property fails at p_include_real_estate = false.
  select distinct
    b.k_id         as sub_cat_id,
    b.k_account_id as account_id
  from both_legs b
  where p_include_real_estate or b.k_cat is distinct from 'Real Estate'
$$;

revoke execute on function pfin.fn_subcat_contributors(date, boolean) from public;
grant  execute on function pfin.fn_subcat_contributors(date, boolean) to authenticated;

comment on function pfin.fn_subcat_contributors(date, boolean) is
  'Per-Sub-Cat CONTRIBUTOR MAP (PRD §2.2.2 staleness tinting; SELF-330). Returns '
  'the DISTINCT (sub_cat_id, account_id) pairs standing behind '
  'pfin.fn_subcat_market_value''s rows at the SAME arguments: which accounts fed '
  'which Sub-Cat. SECURITY INVOKER + STABLE + set search_path = ''''; NO tenant or '
  'scope parameter — isolation is INHERITED from the RLS on every relation read, '
  'via auth.uid() under the caller''s own session (the 049/051/076 convention). ⚠ '
  'THIS FUNCTION CARRIES NO MONEY AND NO FRESHNESS. It has no monetary column, so '
  'it cannot move the binding seam Σ fn_subcat_market_value(as_of, true) = '
  'fn_compute_nav(as_of); and it returns no staleness verdict — resolving '
  'account_id through pfin.account.linked_source_id to the linked-source '
  'staleness surface, and representing fresh/stale/unknown, belongs to the '
  'consumer and is NOT checked here. STANDING REQUIREMENT: the set of DISTINCT '
  'sub_cat_id values returned here MUST equal the set of sub_cat_id values '
  'returned by pfin.fn_subcat_market_value at identical arguments, in BOTH '
  'directions, with NULL equal to NULL; it holds by construction because this is '
  'that function''s join skeleton with the valuation expressions removed, and a '
  'paired pgTAP battery asserts it. ⚠ A set difference (EXCEPT) is required to '
  'assert it — the unclassified key is NULL and `=` is not true of NULL. '
  'sub_cat_id IS NULL is the UNCLASSIFIED contributor set (the same key '
  'fn_subcat_market_value emits for its unclassified row): consumers folding '
  'contributor sets MUST match it by IS NULL, never by equality. account_id is '
  'NEVER NULL, and is NOT guaranteed to have a linked source — a manually-managed '
  'account contributes here exactly like a connected one, and "no linked source" '
  'is a different condition from "linked source is stale". ⚠ Non-liability cash '
  'resolves to ONE Sub-Cat per user per currency (the 022 cash-via-currency-asset '
  'model), so that Sub-Cat''s contributor set is the WIDEST in the map — every '
  'open account holding non-zero cash is in it, and one stale institution tints '
  'the whole cash row by design; liability-type accounts'' cash routes instead to '
  'the seeded Liabilities / Liability Balances row per the account-type rule. '
  'Empty '
  'portfolio returns the EMPTY SET. p_include_real_estate = FALSE excludes cat = '
  '''Real Estate'' entirely on the exact asset-class taxonomy match, and never '
  'excludes the unclassified key. Closed accounts excluded on the 059 dated '
  'predicate, three-conjunct on the LEFT-JOINed securities leg (a bare '
  'closed_at-is-null fails OPEN). Reads only: no write path, no new FK-shaped '
  'column, no SECURITY DEFINER entry, no service_role grant.';
