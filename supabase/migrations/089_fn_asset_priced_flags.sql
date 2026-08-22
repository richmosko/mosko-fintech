-- ============================================================================
-- Migration: pfin.fn_asset_priced_flags — ONE definition of "does this asset
-- have a usable price", called by both the write path and the read path.
-- Phase 6 Build Loop. SELF-325. Executes Sec's F1 plan requirement and closes
-- Sec's C3 by construction rather than by re-alignment.
-- Closes no SD/RT; extends no lock.
--
-- ----------------------------------------------------------------------------
-- WHY THIS EXISTS. 088 computes a `priced` flag inline for its composite return,
--   and the account-detail read path computed the same flag independently in
--   TypeScript. Sec's C3 found that the two DIVERGED — the read side took the
--   first row at an asset's max price_date with NO TIEBREAK, so at a same-date
--   tie it was not merely different from 088 but NONDETERMINISTIC: the same
--   holding could report differently between two page loads. The migration
--   header for 088 and the read-side comment both claimed the predicate had been
--   "reused verbatim". It had not, and it could not have been:
--   ⚠ "VERBATIM" ACROSS A SQL/TYPESCRIPT BOUNDARY IS IMPOSSIBLE BY CONSTRUCTION.
--   Only a reimplementation was ever available, and the claim that it matched
--   survived as documentation until Sec read both sides.
--   Re-aligning two implementations fixes the instance. It does not remove the
--   class: two bodies required to agree, in two languages, with nothing forcing
--   agreement. THIS FUNCTION IS THE THING THAT FORCES IT.
--
-- ⚠ IT IS ONLY WORTH ANYTHING IF 088 CALLS IT TOO. Adding a helper while 088
--   keeps its inline copy would leave two definitions AND a function — the
--   appearance of consolidation without the fact, which is worse than honestly
--   having two, because the next reader sees a shared helper and assumes it is
--   shared. 088's inline block is replaced in the same PR (a paired edit, not a
--   follow-up). If that edit is ever reverted, this migration stops delivering
--   its own premise.
--
-- ----------------------------------------------------------------------------
-- IT ALSO FIXES SEC'S F1, AND THAT IS NOT A COINCIDENCE — F1 AND C3 ARE ONE
-- DEFECT SEEN TWICE.
--   The read path fetched the ENTIRE price history <= as_of for every held asset
--   and then picked per asset in application code: no `.limit()`, against
--   PostgREST's max_rows = 1000. pfin.eod_price is unique on (asset_id,
--   price_date, source), so one asset priced daily by one source for three years
--   is ~750 rows and TWO ordinary holdings exceed the cap. Truncation dropped the
--   HIGHEST asset_ids (the query ordered by asset_id ascending), which then
--   defaulted to priced = false — rendering the loud unpriced marker on a
--   CORRECTLY-PRICED holding. ⚠ A false financial statement, silently, and one
--   that fails in the same fail-closed direction chosen deliberately elsewhere,
--   which is exactly why it would survive review looking like the safe behaviour.
--   ⚠ THE BOUND IS BY CONSTRUCTION HERE, NOT BY A LIMIT CLAUSE: this function
--   returns EXACTLY ONE ROW PER INPUT ASSET, so the result set is the caller's
--   holding count and cannot be truncated by a row cap keyed to price history.
--   A `.limit()` on the old query would have bounded the fetch and still picked
--   from a truncated window; moving the pick into the database removes the
--   window entirely.
--
-- ----------------------------------------------------------------------------
-- THE PREDICATE, and what it deliberately is NOT.
--   For each asset: TRUE iff an eod_price row exists at that asset's MAXIMUM
--   price_date <= p_as_of carrying price > 0. An asset with no rows at or before
--   p_as_of returns FALSE, not NULL and not absent.
--   ⚠ IT CARRIES NO SOURCE-RANK CASE, DELIBERATELY. 078's D-FIRST price pick is
--   already inlined in 019 / 049 / 050 / 056 / 059 / 076 / 078, which is why 078
--   and 079 exist as drift watchers. An eighth copy — in a helper, or worse in
--   application code where nothing watches it — is a cost this indicator does not
--   need to pay.
--   ⚠ THE PRICE OF THAT IS ONE NAMED IMPRECISION, restated here rather than
--   inherited from 088's header: when two sources tie at the maximum price_date
--   and disagree about being zero, this reports on the DATE BAND rather than on
--   the pick's winner — so it can report PRICED where 078's actual pick would
--   land on the zero row. It is optimistic in exactly one reachable case.
--   ⚠ INVERTING TO bool_and WOULD BE WORSE AND WAS EXPLICITLY NOT TAKEN. It would
--   be locally safer and would make the purchase confirmation and the account
--   view disagree about the SAME HOLDING — two answers, with no way for a user to
--   tell which to believe. Agreement between the two surfaces is the property
--   this function exists to guarantee; trading it for a safer single reading
--   would spend the thing being bought.
--   ⚠ IT IS AN INDICATOR FOR THE RENDERING LAYER, NOT A VALUATION PRIMITIVE.
--   Nothing downstream may compute money from it. Value comes from 049 / 050.
--
-- ----------------------------------------------------------------------------
-- Numbering: 089 follows 088 (the manual instrument-purchase write path); taken
--   at authoring time against the live listing, not reserved. Order-dependent on
--   019 (pfin.eod_price, its unique (asset_id, price_date, source), and the
--   eod_price_select global-OR-owned read policy this composes under) and 001
--   (the pfin schema). Consumed by 088 (replacing its inline block, same PR) and
--   by the account-detail read path. No later migration depends on 089.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default); NOT SECURITY DEFINER.
--   It reads pfin.eod_price and nothing else, and it needs no elevation:
--   eod_price_select (019) admits a price row iff its asset is GLOBAL or OWNED by
--   the caller, and that policy evaluates as the caller here. DEFINER would break
--   the isolation this relies on and would turn a read helper into a privilege
--   boundary. This file states no allowlist count; read ADR-011 Decision 9 live.
--   `set search_path = ''` is the injection fence; every reference is schema-
--   qualified. EXECUTE revoked from PUBLIC (which denies anon), granted to
--   authenticated only. service_role is deliberately UNGRANTED — no worker path
--   uses this, and least privilege is the default.
--
--   ⚠ IT CANNOT BE USED AS AN EXISTENCE ORACLE, and that is worth stating because
--   it is the first thing to probe on a function taking caller-supplied ids. An
--   asset the caller cannot see yields no visible price rows and therefore FALSE
--   — the SAME answer as an asset that exists, is visible, and has no usable
--   price. Invisible and unpriced are indistinguishable in the output, so a
--   caller learns nothing about another tenant's private assets by passing their
--   ids. `STABLE` (it reads tables; not IMMUTABLE) is pinned on the signature
--   rather than left to the language default.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — UNCHANGED. NO LABEL TAKEN.
--   ADR-011 Decision 3 read live before drafting, per its own rule, INCLUDING
--   its amendments — the re-target resolution below the numbered entries is where
--   #10's and #13's targets actually live, and reading the entries alone gives a
--   stale answer.
--   This migration creates, alters and drops NO COLUMN of any kind.
--   ⚠ ON THE ARRAY ARGUMENT: Decision 3 governs any FK-shaped reference COLUMN,
--   including an INTEGER[] whose ELEMENTS are FK-shaped. `p_asset_ids bigint[]`
--   is a TRANSIENT ARGUMENT, not a stored column — nothing is persisted, and the
--   same reasoning 087 recorded for its jsonb payload applies. The isolation that
--   would otherwise need a matched-tenant fence is supplied instead by RLS: this
--   is INVOKER, so 019's eod_price_select filters every row to global-or-owned,
--   and an unowned id simply yields no rows. ⚠ THAT SUBSTITUTION IS ONLY VALID
--   WHILE THE FUNCTION STAYS INVOKER AND READ-ONLY. Making it DEFINER, or adding
--   any write, removes the fence that stands in for the family's discipline —
--   whoever does either must revisit this paragraph and route to Sec.
--   No label is taken and the next unallocated instance remains #18.
--
-- ----------------------------------------------------------------------------
-- THIS IS AN INSTANCE OF AN ESTABLISHED PATTERN, NOT A NEW ONE — pointer recorded
--   because rediscovering a precedent costs more than citing it (Sec, SELF-325).
--   ADR-049 Decision 4 already ruled that a CONSUMPTION POLICY lives in ONE
--   SECURITY INVOKER composition helper and is never re-derived per consumer, and
--   it reached that ruling from a structurally identical problem: pfin.eod_price is
--   SPARSE, its last-observation-carried-forward policy is implemented once inside
--   fn_compute_nav rather than per reader, and with two readers there would have
--   been two answers. THIS FUNCTION IS THAT RULING APPLIED TO A SECOND POLICY over
--   the same table — and the SELF-325 divergence is the empirical confirmation of
--   its rationale, since here there WERE two readers and they DID give two answers.
--   ⚠ IT DOES NOT RISE TO AN ADR OF ITS OWN, and that is a deliberate call rather
--   than an omission: ADR-049 Decision 4 already holds the decision, so a new ADR
--   would restate a ratified ruling and create a second place to keep in step. An
--   instance earns a pointer; it does not earn a label.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (ADR-011 Decision 4 read VERBATIM and LIVE before
-- drafting). Path B — Decision 4 is LINKED, not restated; the catalogued
-- numbered list is NOT reproduced here and NO count is carried.
--   (i)   Instance-numbering: no catalogued instance is added, removed, reordered
--         or renumbered.
--   (ii)  Layer-attribution: no catalogued instance is re-attributed and no
--         surface becomes "four-layer". This is an authenticated-tier INVOKER
--         read helper. It touches no infrastructure-credential-presence surface,
--         no SUPABASE_SERVICE_ROLE_KEY code-layer allowlist surface, and no
--         app->worker network-admission surface. IT USES NO service_role.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is referenced, never restated.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are not
--   reconciled here or anywhere.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_asset_priced_flags(p_asset_ids bigint[], p_as_of date)
--     RETURNS TABLE (asset_id bigint, priced boolean)
--     SECURITY INVOKER, STABLE, set search_path = ''.
--   One row per DISTINCT non-null input id, in no guaranteed order. Duplicate
--     ids collapse; NULL elements are dropped. An id with no visible usable price
--     returns FALSE — never NULL, never absent — so a caller may rely on the row
--     being present for every id it passed.
--   Security-load-bearing edges: INVOKER + 019's global-OR-owned eod_price_select
--     is the whole isolation story; invisible and unpriced are indistinguishable
--     in the output; the result set is bounded by input size, not by price
--     history, which is what makes the PostgREST row cap unreachable.
--   Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per
--     ADR-023).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_asset_priced_flags(
  p_asset_ids bigint[],
  p_as_of     date
)
returns table (asset_id bigint, priced boolean)
language sql
security invoker
stable
set search_path = ''
as $$
  -- DISTINCT collapses duplicate ids and the NOT NULL filter drops NULL elements,
  -- so the caller gets exactly one row per real id it asked about.
  with ids as (
    select distinct u.asset_id
      from unnest(p_asset_ids) as u(asset_id)
     where u.asset_id is not null
  )
  select
    ids.asset_id,
    -- bool_or over EVERY row at this asset's own maximum price_date <= p_as_of.
    -- ⚠ Not "the first row" — that was Sec's C3, and with no tiebreak it was
    -- nondeterministic at a same-date tie, not merely divergent.
    -- coalesce turns "no rows at all" into FALSE rather than NULL, which is what
    -- lets the caller treat a present row as an answer for every id.
    coalesce(
      (
        select bool_or(e.price > 0)
          from pfin.eod_price e
         where e.asset_id = ids.asset_id
           and e.price_date = (
                 select max(e2.price_date)
                   from pfin.eod_price e2
                  where e2.asset_id = ids.asset_id
                    and e2.price_date <= p_as_of
               )
      ),
      false
    ) as priced
  from ids;
$$;

revoke execute on function pfin.fn_asset_priced_flags(bigint[], date) from public;
grant execute on function pfin.fn_asset_priced_flags(bigint[], date) to authenticated;

comment on function pfin.fn_asset_priced_flags(bigint[], date) is
  'SECURITY INVOKER, STABLE read helper (SELF-325 / 089). THE single definition of "does this asset have a usable price as of a date", called by BOTH pfin.fn_create_manual_purchase (088, replacing its inline block in the same PR) and the account-detail read path. '
  'It exists because those two computed the same flag independently — one in SQL, one in TypeScript — and Sec found at the SELF-325 joint review that they had DIVERGED: the read side took the first row at an asset''s maximum price_date with no tiebreak, which at a same-date tie was not merely different but NONDETERMINISTIC, so one holding could report differently between two page loads. Both sides documented the predicate as "reused verbatim"; it was not, and it could not have been, because verbatim reuse across a SQL/TypeScript boundary is impossible by construction. Re-aligning two implementations fixes an instance; this function removes the class. ⚠ It delivers that only while 088 actually calls it — a helper alongside a surviving inline copy would be two definitions plus a function, which reads as consolidation and is not. '
  'It also closes Sec''s F1, which is the same defect seen from the other side: the read path fetched the entire price history <= as_of for every held asset with no limit, against PostgREST''s row cap, and pfin.eod_price is unique on (asset_id, price_date, source) — so two ordinary holdings could exceed the cap, truncation dropped the highest asset_ids, and those defaulted to priced = false, rendering the loud unpriced marker on a CORRECTLY-PRICED holding: a false financial statement, silently, failing in the same fail-closed direction chosen deliberately elsewhere. ⚠ The bound here is BY CONSTRUCTION, not a limit clause — exactly one row per input id, so the result set is the caller''s holding count and a cap keyed to price history cannot reach it. '
  'PREDICATE: for each asset, TRUE iff an eod_price row exists at that asset''s maximum price_date <= p_as_of with price > 0; an asset with no such rows returns FALSE, never NULL and never absent. It carries NO source-rank CASE, deliberately — 078''s D-FIRST pick is already inlined in several valuation kernels, which is why 078 and 079 exist as drift watchers, and an eighth copy is a cost an indicator need not pay. The price of that is one named imprecision: at a same-date tie between sources disagreeing about zero it reports on the DATE BAND rather than the pick''s winner, so it is optimistic in exactly one reachable case. ⚠ Inverting to bool_and would be locally safer and was explicitly NOT taken — it would make the purchase confirmation and the account view disagree about the same holding, spending the very agreement this function exists to guarantee. ⚠ INDICATOR ONLY, never a valuation primitive: nothing downstream may compute money from it; value comes from 049/050. '
  'Isolation rests entirely on INVOKER plus 019''s eod_price_select, which admits a price row iff its asset is GLOBAL or OWNED by the caller. ⚠ It cannot serve as an existence oracle: an asset the caller cannot see yields FALSE, the same answer as a visible asset with no usable price, so invisible and unpriced are indistinguishable in the output. ⚠ p_asset_ids is a TRANSIENT ARGUMENT, not a stored column, so ADR-011 Decision 3''s INTEGER[]-element rule does not reach it — RLS supplies the isolation a matched-tenant fence would otherwise owe, and THAT SUBSTITUTION HOLDS ONLY WHILE THIS STAYS INVOKER AND READ-ONLY; making it DEFINER or adding any write removes the stand-in and must return to Sec. Decision 3 family unchanged, no label taken; read Decision 3 live, including its amendments. '
  'NOT a SECURITY DEFINER allowlist entry — this file states no allowlist count; read ADR-011 Decision 9 live. service_role deliberately UNGRANTED (no worker path uses it). STABLE is pinned on the signature rather than left to the language default. set search_path = '''' injection fence. EXECUTE revoked from PUBLIC, granted to authenticated only. Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023).';
