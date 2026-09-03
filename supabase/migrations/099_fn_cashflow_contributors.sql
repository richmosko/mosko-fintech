-- ============================================================================
-- Migration: pfin.fn_cashflow_contributors — per-Sub-Cat CONTRIBUTOR MAP for
-- the §2.3 cash-flow surfaces. Phase 6 Build Loop (SELF-258 AC4/AC5 — per-row
-- staleness indicators on the §2.3.2 cross-account rollup and the §2.3.3
-- per-account drill-down). Read-only over `093`'s shared reader: NO new base
-- table, NO writes, NO new SECURITY DEFINER, NO new FK-shaped column, NO new
-- grant to service_role.
--
-- WHAT THIS DOES: emits the DISTINCT (cat, sub_cat, sub_cat_id, account_id,
-- account_name) tuples standing behind the Sub-Cat rows that
-- pfin.fn_cashflow_cross_account_rollup and pfin.fn_cashflow_per_account render
-- at the SAME p_as_of — which accounts fed which cash-flow Sub-Cat row. It
-- answers "who fed this row", never "how much" and never "how fresh".
--
-- ----------------------------------------------------------------------------
-- ⚠ THIS FUNCTION RETURNS NO STALENESS VERDICT, AND THAT IS THE DESIGN, NOT AN
-- OMISSION. The `086` ratify record's SHAPE 3 is binding here and reads, of the
-- structurally identical §2.2.2 surface: *"Return a DB-side is_stale boolean per
-- Sub-Cat" collapses three states into two: there is no honest UNKNOWN in a
-- boolean, so a not-yet-computed row becomes `false` (fresh) rather than
-- unknown. That is the SELF-220 round-2 failure repeated on a new surface, and
-- it fails OPEN — a stale row renders as fresh.* Nothing about the cash-flow
-- model weakens that argument, so the shape is not re-proposed here.
--
--   CONSEQUENCE FOR THE "SINGLE-SOURCED STALENESS PREDICATE" REQUIREMENT: it is
--   satisfied by there being ZERO copies. `046`
--   fn_aggregation_has_stale_constituent remains the SOLE home of "what counts
--   as stale" (`is_active` AND `connection_status is distinct from 'healthy'`
--   over the `043` linked_source_connection_state view). This migration does not
--   read that predicate, does not restate it, and does not extract it. The
--   `fn_expenditure_window` extraction precedent (`098`) is deliberately NOT
--   applied: an extraction is the right answer when TWO producers must agree on
--   one rule, and here there is only ever one producer.
--
--   THE RESOLUTION PATH IS ALREADY BUILT AND RATIFIED, end to end:
--     `099` (cat, sub_cat) -> account_id
--       -> resolveStaleAccountIds() [api/src/lib/server/queries/navComposition.ts,
--          EXPORTED at SELF-330 as THE bridge from a resolved `046` stale
--          linked_source_id set to pfin.account.account_id]
--       -> the Kleene-OR tri-state fold [nonReAllocation.ts subCatIsStale /
--          foldIsStale: TRUE dominates; else UNKNOWN dominates FALSE; the
--          `staleAccountIds === null` short-circuit that Sec's SELF-330 review
--          required BEFORE the loop].
--   Adding a second route to that same answer is how two routes come to
--   disagree. See R2 below for the `linked_source_id` column that was rejected
--   on exactly that ground.
--
-- ----------------------------------------------------------------------------
-- WHERE THIS FOLLOWS `086` AND WHERE THE CASH-FLOW MODEL FORCES DIVERGENCE.
-- Stated as a list because a future author will reach for `086` and needs to
-- know which of its properties transferred.
--
--   FOLLOWED:
--   · Contributor map, not a verdict — no monetary column and no freshness
--     column (`086` S1 + S3).
--   · No tenant parameter. Isolation is INHERITED via SECURITY INVOKER and
--     auth.uid(); a p_users_id would be the confused-deputy foot-gun `049` R3 /
--     `051` A1 name. This matters MORE here than on a value function, for
--     `086`'s reason: a contributor map is an ACCOUNT-IDENTITY disclosure
--     surface, so a caller-supplied tenant would leak account identities rather
--     than sums.
--   · The NULL key is KEPT, not filtered. sub_cat_id IS NULL is the
--     UNCLASSIFIED contributor set — the same key both §2.3 surfaces count for
--     the S-2 banner. A consumer folding contributor sets MUST match it by
--     IS NULL, never by equality.
--   · A standing both-directions parity requirement, asserted in the paired
--     battery rather than claimed here (see PARITY below).
--
--   DIVERGED — each with the reason, because each is a place `086`'s shape would
--   be wrong here:
--   D1. NO MIRRORED BODY. `086` had to mirror fn_subcat_market_value's join
--       skeleton from the live catalog and delete its valuation expressions,
--       because that function had no extracted reader. §2.3 DOES: `093`
--       pfin.fn_cashflow_items is the shared reader and the SOLE home of the six
--       reader rules. This function therefore COMPOSES on it and contains no
--       copy of any rule. ⚠ A reader rule appearing in this body IS the drift
--       defect the `093` extraction exists to prevent — the same standing
--       requirement `093`'s own header places on fn_cashflow_cross_account_rollup.
--       That eliminates `086`'s entire hazard class (the deleted-vs-kept
--       membership-filter audit) rather than repeating it.
--   D2. NO CLOSURE PREDICATE, and this is a DELIBERATE OMISSION where `086`
--       carries one. `086` excludes closed accounts on the `059` dated
--       predicate because fn_subcat_market_value does — a closed account holds
--       nothing NOW. A cash-flow row is a record of what HAPPENED in the window,
--       and a since-closed account's transactions are still in it. Adding a
--       closure predicate here would drop a contributor that the rendered figure
--       still contains, and it would fail in the OPEN direction (a row whose only
--       stale contributor is a closed account would render fresh). The row set is
--       the reader's; this function narrows it on nothing but `in_ytd`.
--   D3. account_name IS CARRIED, where `086` returns bare ids. Two reasons, and
--       the second is the load-bearing one. (i) AC5's tooltip names the stale
--       contributors, and every §2.3 row is fed by whole accounts, so the name is
--       the contributor's identity rather than a second fact about it — it is
--       functionally determined by account_id and cannot split a DISTINCT group.
--       (ii) See the LEFT JOIN block below: `account_name IS NULL` is the
--       function's only honest signal that a contributor exists whose staleness
--       the consumer CANNOT resolve.
--   D4. ONE ARGUMENT, not two. `094` fn_cashflow_per_account takes p_account_id
--       and the drill-down is account-scoped, so a p_account_id overload looks
--       natural. It is NOT added — see R3.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE JOIN TO pfin.account IS **LEFT**, AND THAT IS LOAD-BEARING, NOT
-- DEFENSIVE. `086`'s cash leg joins pfin.account INNER. Copying that here would
-- be wrong, because the two relations this function spans are fenced by
-- DIFFERENT policies and the difference is measurable in the catalog:
--
--     pfin.account_trans  SELECT policy: EXISTS (account_users au WHERE
--                         au.account_id = ... AND au.users_id = auth.uid()
--                         AND au.rd_access)          -- the Lock 3 ACL JOIN
--     pfin.account        SELECT policy: users_id = auth.uid()
--
-- These are not the same predicate. A caller holding rd_access on an account
-- they do NOT own reads that account's transactions — so the reader emits items
-- — while pfin.account hides the account row itself. Under an INNER join that
-- contributor would VANISH from the map while its money REMAINS in the rendered
-- figure (the rollup reads only fn_cashflow_items and never touches
-- pfin.account). The consumer would then fold over a contributor set that is
-- missing a member and conclude FRESH. **That is a fail-OPEN, produced by a join
-- that reads as a lookup.**
--
--   THE SIGNAL IS IN THE SHAPE. pfin.account.name is NOT NULL (`003`, verified
--   in the catalog), so in this function's output `account_name IS NULL` can
--   mean EXACTLY ONE thing: the contributor's account row was not visible to the
--   caller. It is therefore a checkable UNKNOWN, and a consumer MUST fold such a
--   contributor to UNKNOWN (null) — never to fresh, and never to stale. No extra
--   boolean column is added to say this, because the return shape already says
--   it and a second column could disagree with the first.
--
--   ⚠ REACHABILITY, STATED HONESTLY: this branch is **DORMANT IN V1**, not live.
--   pfin.account_users carries a SELECT policy only — no INSERT or UPDATE policy
--   and no write grant to `authenticated` — so its rows arrive solely from the
--   `003` fn_grant_creator_access creator self-grant, and every visible
--   account_trans today belongs to an account the caller also owns. **REVIVAL
--   CONDITION: the first write path that inserts an account_users row for a
--   users_id other than the account owner's** — i.e. any V2 sharing or
--   invitation feature (Lock 2, V1-dormant per `003`). The LEFT join is here so
--   that feature does not silently convert this surface to fail-open on the day
--   it lands. Recorded rather than asserted as live, because an overclaimed
--   reachability is how a fence gets removed as decoration.
--
-- ----------------------------------------------------------------------------
-- THE WINDOW — `in_ytd`, AND NOTHING ELSE. This function applies exactly one
-- filter of its own to the reader's output: `i.in_ytd`.
--   · It is NOT a date predicate of this function's. `in_ytd` is a column the
--     reader COMPUTES under its own rule 5; consuming a reader flag is the
--     opposite of restating a reader rule. This body contains no date literal,
--     no date arithmetic, and no comparison against p_as_of. p_as_of is passed
--     through to fn_cashflow_items and read nowhere else.
--   · It is REQUIRED for row-set alignment, and both consumers agree on it:
--     `093` and `094` each filter `in_ytd` for the Sub-Cat sums AND for the
--     unclassified count. Omitting it would admit contributors from the §2.3.4
--     five-year window that fed NO rendered row, tinting a row for an account
--     that is not in it — a false positive that is dishonest in the direction
--     D1 does not license (D1 forbids silent freshness; it does not license
--     invented staleness).
--   · in_ytd is the UNION of every period this surface renders (month and each
--     quarter are subsets of it by rule 5's construction), so the map is correct
--     for a row-level indicator. ⚠ It is NOT correct for a CELL-level (per-
--     quarter) indicator, and AC4 does not ask for one. A future per-column
--     indicator needs the period flags carried through, which changes the grain
--     and therefore the function.
--
-- ----------------------------------------------------------------------------
-- REJECTED SHAPES — recorded because these are the ones a future author
-- re-derives from the brief if only the code survives.
--   R1. A per-row `is_stale` boolean or a per-row stale-account-name array.
--       REJECTED — `086` S3, quoted verbatim above. The array form is the same
--       defect wearing different clothes: an EMPTY array is indistinguishable
--       between "no contributor is stale" and "staleness could not be resolved",
--       which is precisely the two-states-for-three collapse S3 names. The map
--       returns ALL contributors; the consumer intersects with the `046` stale
--       set and names the survivors in the tooltip. Same tooltip, honest UNKNOWN.
--   R2. Carrying `pfin.account.linked_source_id` to save the consumer a hop.
--       REJECTED. `086` states the boundary — *"resolving that is the consumer's,
--       at the `046` hop"* — and SELF-330 then BUILT that resolver as an exported
--       function. Carrying the column would create a SECOND route from a
--       contributor to a linked source, and two routes to one answer is how the
--       two come to disagree. It also buys nothing: the consumer needs
--       resolveStaleAccountIds() regardless, because that is where the tri-state
--       short-circuit lives.
--   R3. A `p_account_id` argument for the §2.3.3 drill-down. REJECTED on two
--       independent grounds, either sufficient.
--       (a) NULL-SEMANTICS COLLISION. `094` fn_cashflow_per_account ruled that a
--           NULL p_account_id returns the ORDINARY EMPTY DOCUMENT. A
--           NULL-means-ALL-accounts overload in the sibling function would make
--           NULL mean opposite things in one family, on the same surface, at the
--           same grain. A caller who threads a NULL through the wrong one gets a
--           silently different answer.
--       (b) ⚠ THE DRILL-DOWN DOES NOT NEED IT, AND THIS IS A FINDING RATHER THAN
--           A CONVENIENCE. Every §2.3.3 row is folded from items of ONE account:
--           the reader stamps split children with the SPLIT PARENT's account_id
--           (`093` rule 2 emission), so no row can span accounts, and `094`
--           filters the reader's output to a single account_id. **Every row on
--           the drill-down therefore has the SAME single contributor, so a
--           per-row staleness indicator there is CONSTANT across all rows** — it
--           carries no per-row information and is fully determined by the
--           account's own staleness. On §2.3.3 the honest surface is the
--           existing account-level indicator; the map is what makes §2.3.2's
--           indicator informative, because only there do rows differ in their
--           contributor sets.
--           ⚠ **RULED, NOT MERELY OBSERVED — SELF-258, team-lead default-and-
--           notify (ADR-063 Decision 3), 2026-09-03, F/CTO-reversible at PR
--           review: the §2.3.3 PER-ROW indicator is OFF.** The per-row icon
--           renders on §2.3.2 ONLY; the drill-down keeps its existing SECTION
--           badge. Grounds: a provably-constant per-row icon is anti-information
--           — it occupies the affordance a user reads as "this row differs" while
--           being incapable of differing. The measurement above is what decided
--           it, so it is recorded here rather than in a review thread.
--           CONSEQUENCE FOR THIS FUNCTION, which is why it belongs in the
--           contract and not only in an ADR: **§2.3.3 is not a per-row consumer
--           of this map.** `094`'s surface consumes the account-level staleness
--           it already had. A future reader finding the drill-down not calling
--           this function is looking at the ruling, NOT at an unfinished wiring —
--           and a future author must not "complete" it without reversing the
--           ruling first. The map itself is UNCHANGED by this: it still emits
--           every account's contributors, because §2.3.2 needs the whole set and
--           narrowing it to one surface's needs would be the drift this family
--           is organised to avoid.
--
-- ----------------------------------------------------------------------------
-- THE PARITY PROPERTY — A STANDING REQUIREMENT, ASSERTED IN THE PAIRED BATTERY.
-- It holds by construction: both consumers group the SAME reader's output at the
-- SAME p_as_of under the SAME `in_ytd` and `sub_cat_id is not null` conjuncts,
-- and this function's grouping key is a projection of the same columns. But "by
-- construction" is exactly the claim that stops being true when someone edits one
-- of the three bodies.
--
--   (P1) For every p_as_of and every caller, as SETS in BOTH DIRECTIONS:
--        { (cat, sub_cat) from fn_cashflow_contributors(d)
--            where sub_cat_id is not null and cat in ('Revenue','Expense') }
--          == { (cat, sub_cat) of the Sub-Cat rows of
--               fn_cashflow_cross_account_rollup(d) }
--
--   (P2) For every p_as_of, every caller and every account a, in BOTH DIRECTIONS:
--        { (cat, sub_cat) from fn_cashflow_contributors(d)
--            where account_id = a and sub_cat_id is not null
--            and cat in ('Revenue','Transfer','Equity','Expense') }
--          == { (cat, sub_cat) of the Sub-Cat rows of
--               fn_cashflow_per_account(a, d) }
--
--   (P3) EXISTS a row with sub_cat_id IS NULL and account_id = a
--          <==> fn_cashflow_per_account(a, d) -> 'unclassified' -> 'count_ytd' > 0.
--
--   ⚠ The cat restrictions in P1/P2 are NOT filters this function applies — it
--   applies none. They are the CONSUMERS' section vocabularies, named in the
--   assertion so the assertion is well-formed. This function is a SUPERSET of
--   both consumers in the cat dimension: it emits every cat the reader emits,
--   'Trade' included, because filtering to a consumer's section list would copy
--   that consumer's `section_cats` mapping into a third place. A superset is the
--   safe direction — an unlooked-up key is inert, a MISSING key folds to UNKNOWN.
--
--   ⚠ Assert P1/P2 with set difference (EXCEPT) in both directions, never an
--   equality join: `sub_cat` is text and the unclassified key is NULL, and `=`
--   is not true of NULL.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHAT THIS FUNCTION DOES NOT GUARANTEE — stated because a consumer will
--   otherwise assume it.
--   · account_id is NOT guaranteed to have a linked source. A manually-managed
--     account contributes here exactly like a connected one, and its
--     pfin.account.linked_source_id is null. "No linked source" is a DISTINCT
--     condition from "linked source is stale", and this function does not
--     collapse them.
--   · The tuple set is NOT a staleness verdict and carries no freshness column.
--   · It inherits `093`'s NAMED RESIDUAL unchanged and does not repair it: the
--     reader cannot see the reversal of a SPLIT PARENT, so such a reversal has no
--     emitted item, appears in no §2.3 figure, and correspondingly contributes
--     nothing here. What holds that line is the app-layer write-path refusal.
--     This function does not check it and does not promise it.
--   · A Sub-Cat row summing to exactly 0.00 still appears here with its
--     contributors: a fully-reversed item nets to 0 and stays inside its own
--     Sub-Cat (`093` rule 3), and this function keys on group existence rather
--     than on value.
--
-- ----------------------------------------------------------------------------
-- Numbering: 099 follows 098 (expenditure_window_and_unclassified_count); taken
--   at authoring time against the live listing and against every ref and
--   worktree HEAD, not reserved ahead.
--   ORDER-DEPENDENT ON `093` (pfin.fn_cashflow_items — the shared reader and the
--   sole relation-reading dependency of consequence) and on `003`
--   (pfin.account.account_id / name / the account_select policy). Depends
--   further, only through the reader, on `004`/`017`/`019`/`029` (account_trans,
--   its annotation overlay and the split children) and `084` (posting_prototype,
--   which supplies cat/sub_cat). ⚠ NOT order-dependent on `046` or `043`: this
--   function reads NEITHER, by design.
--   No downstream migration depends on 099.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. The function only READS, and every relation it reads is
--   already RLS-fenced to the caller: pfin.fn_cashflow_items is itself INVOKER
--   (verified in the catalog, prosecdef = false), and pfin.account carries
--   account_select plus the `025` aal2 backstop clause. It needs no privilege the
--   caller lacks; DEFINER would turn a read-composition helper into a confused
--   deputy for no benefit — and on an account-identity surface the blast radius
--   of that mistake is account identities, not sums.
--   `set search_path = ''` applied. EXECUTE revoked from public, granted to
--   authenticated only. → SECURITY DEFINER allowlist UNCHANGED, adds no entry;
--   ADR-011 Decision 9 was read verbatim and live before drafting — read the
--   allowlist there, it is not restated here.
--   `stable` IS DECLARED, and it is BACKED rather than promised: its only
--   function callee, pfin.fn_cashflow_items(date), is itself STABLE in the live
--   catalog (pg_proc.provolatile = 's', verified — not read from `093`'s source
--   text). This function therefore introduces no new STABLE-over-VOLATILE seam
--   of the class `079` records. ⚠ Any future CREATE OR REPLACE of this function
--   MUST carry `stable` in its own body — a replace resets volatility silently.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
-- numbered list is NOT restated here and NO count is carried, deliberately).
-- Decision 4 was read verbatim and live before drafting, 2026-09-02. This
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
--   ADR-011 Decision 3 was read verbatim and live before drafting, 2026-09-02.
--   This migration creates, alters and drops NO column of any kind, FK-shaped or
--   otherwise, and no INTEGER[] array. It only reads existing relations through
--   existing fences; the references it makes are join predicates inside a query,
--   not stored ones (the `081` / `086` precedent). No label is taken. Read
--   Decision 3's numbered list live for the family's shape — the labels are
--   non-contiguous, at least one is DROPPED, and *labeled* versus *DDL-realized*
--   diverge, so no count is carried here.
--   ⚠ The join `a.account_id = i.account_id` is NOT a Decision-3 surface, but it
--   IS an id-keyed join and therefore fails CLOSED under an RLS regression — the
--   `086` reasoning. Contrast `086`'s liability cash route, which is keyed on
--   SHARED-VOCABULARY STRING LABELS and needs an explicit users_id conjunct for
--   that reason. No such join exists here: cat and sub_cat arrive as projections
--   of the reader's own rows and are never used as join keys.
--
-- LEDGER DELTAS (confirmed FLAT): §10 catalogued instances unchanged ·
--   SECURITY DEFINER allowlist unchanged · Decision-3 family unchanged ·
--   RT-26 allowlist untouched (no service_role surface) · RT catalog unchanged ·
--   aal2 step-up backstop: no new table, so nothing to inherit the `025` clause;
--   the clause is INHERITED at read time from account_trans and account.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface), on three independent grounds:
--   (1) a MULTI-TENANT READ whose tenant fence is ENTIRELY INHERITED — this
--       function adds no isolation predicate of its own whatsoever, and relies
--       on the RLS of the reader's relations plus pfin.account. If any of those
--       lost its policy, this function would silently widen.
--   (2) it is an ACCOUNT-IDENTITY disclosure surface. The §2.3 value functions
--       disclose sums; this discloses WHICH ACCOUNTS, BY NAME. The blast radius
--       of an isolation failure is different in kind, not merely in degree, and
--       account_name widens it beyond `086`'s bare ids.
--   (3) it feeds the staleness pipeline, whose failure direction is fail-OPEN
--       (a stale row rendering as fresh) — which is why S3 is not re-proposed
--       and why the pfin.account join is LEFT.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_cashflow_contributors(p_as_of date)
--     RETURNS TABLE (cat text, sub_cat text, sub_cat_id bigint,
--                    account_id bigint, account_name text)
--     SECURITY INVOKER · STABLE · set search_path = ''
--
--     EXACTLY-ONE-BEHAVIOR CONTRACTS:
--     - Returns the DISTINCT (cat, sub_cat, sub_cat_id, account_id,
--       account_name) tuples over pfin.fn_cashflow_items(p_as_of) restricted to
--       in_ytd. One tuple per (Sub-Cat, account) combination contributing to the
--       §2.3 surfaces at the same p_as_of. DISTINCT cannot merge two genuinely
--       different groups: sub_cat_id determines (cat, sub_cat) through
--       pfin.posting_prototype's primary key, and account_id determines
--       account_name through pfin.account's.
--     - sub_cat_id IS NULL is the UNCLASSIFIED contributor set — the same key
--       both §2.3 surfaces count for the S-2 banner. Match by IS NULL, never by
--       equality.
--     - ⚠ THE THREE TAXONOMY COLUMNS ARE **NOT** ALWAYS NULL TOGETHER, AND AN
--       EARLIER DRAFT OF THIS CONTRACT CLAIMED THEY WERE. Measured on a scratch
--       chain-apply: a THIRD state is reachable — sub_cat_id NOT NULL with cat
--       AND sub_cat both NULL. Cause: the reader resolves cat/sub_cat by a LEFT
--       JOIN to pfin.posting_prototype, which is per-user and RLS-scoped, while
--       sub_cat_id is copied from the annotation unchanged. A caller reading an
--       item on an account they do not OWN therefore sees the id but not the
--       label. Consumers MUST NOT infer "classified" from `sub_cat_id IS NOT
--       NULL` and MUST NOT infer "unclassified" from `sub_cat IS NULL` — the two
--       tests disagree in exactly this state.
--       ⚠ SAME V1 DORMANCY AND SAME REVIVAL CONDITION as the account_name NULL
--       branch, and NOT this function's to repair: the state originates in the
--       `093` reader and reaches `093`/`094` FIRST, where such an item passes
--       their `sub_cat_id is not null` conjunct and is summed into a rendered row
--       keyed (cat NULL, sub_cat NULL) — neither the unclassified banner nor a
--       named Sub-Cat row. This function reports the state faithfully rather than
--       collapsing it; the §2.3 row-set question belongs to `093`/`094`.
--       Recorded here because a consumer reading only this contract would
--       otherwise assume the collapse.
--     - account_id is NEVER NULL (pfin.account_trans.account_id is NOT NULL,
--       verified in the catalog; split children inherit the parent's).
--     - account_name IS NULL means EXACTLY ONE thing and nothing else: the
--       caller cannot see that contributor's pfin.account row, so its staleness
--       is UNRESOLVABLE and MUST fold to UNKNOWN. pfin.account.name is NOT NULL,
--       so no other cause can produce it. V1-dormant — see the LEFT JOIN block.
--     - NULL-ARG SEMANTICS, EXPLICIT: p_as_of IS NULL returns ZERO ROWS. It is
--       not STRICT and does not raise; the reader's bounds CTE yields NULL for
--       every bound, every period comparison evaluates to NULL, `where i.in_ytd`
--       admits nothing. This is the ordinary empty answer of a set-returning
--       function and is NOT distinguishable from "this caller has no cash-flow
--       activity in the rendered year" — a caller needing that distinction must
--       not pass NULL.
--     - EMPTY ANSWER IS THE EMPTY SET. No sentinel row, no NULL row.
--     - NO DEFAULT on p_as_of, deliberately: `093` and `094` both require the
--       argument, and a default here would let a caller silently read a
--       different as-of than the figures it is annotating. ⚠ This DIVERGES from
--       `086`, which defaults to current_date; the §2.3 family's convention wins
--       over the §2.2 sibling's because the as-of must match the surface being
--       annotated.
--
--     SECURITY-LOAD-BEARING EDGES
--     • Owner scope is INHERITED, wholly: fn_cashflow_items is INVOKER over
--       account_trans (Lock 3 account_users rd_access ACL JOIN + the `025` aal2
--       clause), and pfin.account carries account_select + its own `025` clause.
--       At aal1 with mfa_policy in (totp, passkey) both driving relations return
--       zero rows, so this function returns the empty set — fail-closed.
--     • UNAUTHENTICATED (role anon) → DENIED with 42501 at the pfin schema-USAGE
--       fence, before the body runs and before the EXECUTE grant is consulted.
--       Fail-closed and STRONGER than an empty result. DISTINCT from the
--       authenticated-with-no-sub case below.
--     • AUTHENTICATED-with-no-sub (auth.uid() resolves NULL) → reaches the body;
--       account_users matches no row; the empty set. Fail-closed, no leak.
--     • NO caller-supplied tenant or scope parameter exists to abuse.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (same-PR; QA-authored — Architect does not edit tests/).
--   CRUX LEGS — the three that are not decoration:
--     (X1) STALENESS-PREDICATE SINGLE-SOURCE PIN. Assert this function's body
--          contains NO staleness predicate and reads NEITHER `046` nor `043`:
--          pg_get_functiondef of fn_cashflow_contributors matches neither
--          'connection_status' nor 'linked_source' nor 'has_stale', and
--          pg_depend / regprocedure shows no reference to
--          fn_aggregation_has_stale_constituent or
--          linked_source_connection_state. This is the leg that catches a future
--          author "helpfully" inlining the rule — the drift class this design
--          exists to prevent, and the one no value assertion can see.
--     (X2) PARITY, BOTH DIRECTIONS, VIA EXCEPT — P1 and P2 above, each asserted
--          as two EXCEPT legs (never an equality join; sub_cat is text and the
--          unclassified key is NULL). Plus P3's iff.
--     (X3) NON-VACUITY OF THE ITEM LIST. Every parity leg must run against a
--          fixture where BOTH sides are NON-EMPTY, asserted in the same test:
--          two empty relations pass EXCEPT in both directions and look identical
--          to a correct answer. Assert count(*) > 0 on each side before, or in,
--          the same leg.
--     (X4) POSTURE TRIPLE, from the CATALOG not the file: prosecdef = false ·
--          provolatile = 's' · proconfig contains 'search_path='. Plus EXECUTE
--          revoked from public and granted to authenticated (has_function_
--          privilege on both roles), and the 42501 for anon.
--   TWO-TENANT LEGS:
--     - fixture: tenants A and B each own accounts with classified and
--       unclassified cash-flow items in the rendered year;
--     - as A, the returned set contains NO account_id owned by B, and no
--       account_name of B's — asserted on the NAME too, since that is the column
--       `086` did not have;
--     - A's own contributors are all present (not a vacuous green);
--     - aal2 gate: an aal1 caller with mfa_policy in (totp,passkey) gets the
--       empty set;
--     - p_as_of NULL → empty set, asserted as EMPTY rather than as an error.
--   GRAIN LEGS (the reader's item grain rules, which this function must not
--   re-implement and must not lose):
--     - a SPLIT PARENT's children each contribute under the CHILD's sub_cat but
--       the PARENT's account_id — one account, several Sub-Cats;
--     - a fully-reversed item nets to 0 and STILL contributes (group existence,
--       not value);
--     - an item OUTSIDE the rendered year (in the §2.3.4 five-year window)
--       contributes NOTHING — the in_ytd leg; this is the one that fails if a
--       future edit drops the conjunct;
--     - an account contributing to TWO Sub-Cats yields TWO tuples; a Sub-Cat fed
--       by TWO accounts yields TWO tuples (the §2.3.2 case that makes the
--       indicator informative);
--     - a manually-managed account (linked_source_id IS NULL) contributes
--       exactly like a connected one.
--   DORMANT-BRANCH LEGS (both revive on the same condition — the first
--   pfin.account_users row granting rd_access to a NON-OWNER; V2 sharing, Lock 2).
--   ⚠ These assert a branch that CANNOT be reached by any V1 write path, so the
--   fixture must insert that account_users row DIRECTLY. Without them both
--   branches are untested code that looks live:
--     - account_name IS NULL for a contributor on a non-owned readable account,
--       AND that contributor is PRESENT (the LEFT-vs-INNER discriminator — an
--       INNER join drops the row entirely, which is the fail-open);
--     - sub_cat_id IS NOT NULL while cat AND sub_cat are both NULL for that same
--       contributor (the third taxonomy state), asserted as a POSITIVE
--       observation of all three columns, not as an absence.
--   Sec joint-review: MANDATORY — see the JOINT-REVIEW-MANDATORY block.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_cashflow_contributors(p_as_of date)
returns table (
  cat          text,
  sub_cat      text,
  sub_cat_id   bigint,
  account_id   bigint,
  account_name text
)
language sql
stable
security invoker
set search_path = ''
as $$
  -- THE ONLY READ OF THE ITEM SET. `093` pfin.fn_cashflow_items owns every
  -- predicate over pfin.account_trans, including the Lock 15 dual-column as-of
  -- pair; p_as_of is threaded through and is read nowhere else in this body.
  -- ⚠ A reader rule appearing here IS the drift defect the `093` extraction
  -- exists to prevent.
  select distinct
    i.cat,
    i.sub_cat,
    i.sub_cat_id,
    i.account_id,
    -- ⚠ LEFT, not INNER. account_trans is fenced by the Lock 3 account_users
    -- rd_access ACL JOIN; pfin.account by users_id = auth.uid(). They are not
    -- the same predicate, so an INNER join would DROP a contributor whose money
    -- the rendered figure still contains — a fail-OPEN produced by a join that
    -- reads as a lookup. pfin.account.name is NOT NULL, so a NULL here means
    -- exactly "not visible to this caller" and the consumer MUST fold it to
    -- UNKNOWN. See the header's LEFT JOIN block for the V1-dormancy and the
    -- revival condition.
    a.name as account_name
  from pfin.fn_cashflow_items(p_as_of) i
  left join pfin.account a on a.account_id = i.account_id
  -- The ONLY filter this function applies. `in_ytd` is the reader's own rule-5
  -- flag, not a predicate of ours — it aligns the contributor set with the row
  -- set both §2.3 surfaces render, which filter on the identical flag for both
  -- the Sub-Cat sums and the unclassified count. No cat filter: this map is a
  -- deliberate SUPERSET of each consumer's section vocabulary, because copying
  -- a consumer's section_cats mapping into a third place is the drift this
  -- family is organised to avoid.
  where i.in_ytd
$$;

revoke execute on function pfin.fn_cashflow_contributors(date) from public;
grant  execute on function pfin.fn_cashflow_contributors(date) to authenticated;

comment on function pfin.fn_cashflow_contributors(date) is
  'Per-Sub-Cat CONTRIBUTOR MAP for the §2.3 cash-flow surfaces (PRD §2.3.2 per-row staleness '
  'indicators; SELF-258 AC4/AC5). ⚠ ITS PER-ROW CONSUMER IS §2.3.2 ONLY: at SELF-258 the §2.3.3 '
  'drill-down per-row indicator was RULED OFF and that surface keeps its section badge, because '
  'every §2.3.3 row is folded from items of ONE account (split children carry the split PARENT''s '
  'account) so a per-row icon there is provably constant and cannot differ between rows. A reader '
  'finding the drill-down not consuming this map per-row is looking at that ruling, not at '
  'unfinished wiring. Returns the DISTINCT (cat, sub_cat, sub_cat_id, '
  'account_id, account_name) tuples standing behind the Sub-Cat rows that '
  'pfin.fn_cashflow_cross_account_rollup and pfin.fn_cashflow_per_account render at the SAME '
  'p_as_of: which accounts fed which cash-flow row. SECURITY INVOKER + STABLE + set search_path '
  '= ''''; NO tenant and NO scope parameter — isolation is INHERITED from the RLS on every '
  'relation read, via auth.uid() under the caller''s own session (the 049/051/076/086 '
  'convention); a contributor map is an account-identity disclosure surface, so a caller-supplied '
  'tenant would leak account identities rather than sums. COMPOSES on pfin.fn_cashflow_items '
  '(093), which is the SOLE home of the six reader rules — this function restates NONE of them, '
  'contains no date literal and no date arithmetic, and threads p_as_of straight through. '
  '⚠ THIS FUNCTION CARRIES NO MONEY AND NO FRESHNESS. It has no monetary column, and it returns '
  'no staleness verdict: pfin.fn_aggregation_has_stale_constituent (046) remains the SOLE home of '
  'what counts as stale, and this function neither reads nor restates it. Resolving account_id to '
  'a linked source and representing fresh/stale/unknown belongs to the consumer and is NOT '
  'checked here — a DB-side per-Sub-Cat is_stale boolean, and equally a per-row stale-name array '
  'whose EMPTY value cannot distinguish none-stale from unresolved, both collapse three states '
  'into two and fail OPEN (the 086 SHAPE 3 ruling, which applies unchanged to this surface). '
  'THE ONLY FILTER APPLIED is the reader''s own in_ytd flag, which is what both consumers filter '
  'on for the Sub-Cat sums AND the unclassified count; the map is otherwise a deliberate SUPERSET '
  'of each consumer''s section vocabulary (Trade included) because copying a section_cats mapping '
  'into a third place is the drift this family is organised to avoid. STANDING REQUIREMENT: '
  'restricted to sub_cat_id IS NOT NULL and to a consumer''s own cat set, the (cat, sub_cat) '
  'pairs returned here MUST equal that consumer''s rendered Sub-Cat keys at identical p_as_of, in '
  'BOTH directions; it holds by construction because all three group the same reader output under '
  'the same in_ytd, and a paired pgTAP battery asserts it. ⚠ Assert with set difference (EXCEPT) '
  'and over a NON-EMPTY fixture on both sides — sub_cat is text, the unclassified key is NULL, '
  'and two empty relations differ in neither direction. sub_cat_id IS NULL is the UNCLASSIFIED '
  'contributor set: consumers MUST match by IS NULL, never by equality. ⚠ THE THREE TAXONOMY '
  'COLUMNS ARE NOT ALWAYS NULL TOGETHER — sub_cat_id NOT NULL with cat AND sub_cat both NULL is '
  'reachable (measured), because the reader resolves cat/sub_cat through the per-user RLS-scoped '
  'pfin.posting_prototype while copying sub_cat_id from the annotation unchanged, so a caller '
  'reading an item on an account they do not OWN sees the id but not the label. Do NOT infer '
  '"classified" from sub_cat_id IS NOT NULL nor "unclassified" from sub_cat IS NULL; the two '
  'tests disagree in that state. It shares the account_name branch''s V1 dormancy and revival '
  'condition, originates in the 093 reader, and reaches 093/094 first — this function reports it '
  'faithfully rather than collapsing it. account_id is NEVER NULL (account_trans.account_id is NOT NULL; split '
  'children carry the split PARENT''s account, so no row spans accounts). account_id is NOT guaranteed to have a linked source — a manually-managed '
  'account contributes exactly like a connected one, and "no linked source" is a different '
  'condition from "linked source is stale". ⚠ account_name IS NULL means EXACTLY ONE thing: the '
  'caller cannot see that contributor''s pfin.account row, so its staleness is UNRESOLVABLE and '
  'MUST fold to UNKNOWN, never to fresh. pfin.account.name is NOT NULL, so no other cause '
  'produces it. The join to pfin.account is LEFT for that reason and it is load-bearing, not '
  'defensive: account_trans is fenced by the Lock 3 account_users rd_access ACL JOIN and '
  'pfin.account by users_id = auth.uid(), which are different predicates, so an INNER join would '
  'drop a contributor whose money the rendered figure still contains. That branch is DORMANT '
  'while pfin.account_users carries no write path for a non-owner, and REVIVES with the first '
  'such write path (V2 sharing, Lock 2). No closure predicate is applied, unlike 086: a cash-flow '
  'row records what happened in the window, and a since-closed account''s transactions are still '
  'in it. p_as_of has NO default (the 093/094 convention, diverging from 086''s current_date) and '
  'a NULL p_as_of returns the EMPTY SET, indistinguishable from a caller with no activity. Reads '
  'only: no write path, no new FK-shaped column, no SECURITY DEFINER entry (allowlist unchanged; '
  'read ADR-011 Decision 9 live), no service_role grant, no new table and so no 025 aal2 clause '
  'to inherit — the clause is inherited at read time from account_trans and account.';
