-- ============================================================================
-- Migration: pfin.fn_create_manual_purchase — the manual INSTRUMENT-PURCHASE write path.
-- Records a real acquisition on a manual account: cash leaves the account and a
-- position arrives, as ONE witnessed ledger fact.
-- Phase 6 Build Loop. SELF-325 (remaining scope; the create-path arc's second half).
-- F/CTO-ratified 2026-08-21 — venue B (a dedicated RPC), the conditional
-- price-companion rule, and the unpriced-but-LOUD posture for global assets.
-- Closes no SD/RT; extends no lock.
--
-- ----------------------------------------------------------------------------
-- THE DEFECT. After 087 a manual account can be created with bound opening
--   positions, but nothing can record a PURCHASE afterwards. The live manual-entry
--   RPC (fn_create_manual_trans, replaced at 040) hard-codes transaction_type
--   ='standard' AND leaves security_id NULL, so it writes cash and only cash. A
--   user who deposits money into a manual brokerage account and buys a security
--   has no way to say so: the deposit lands, and the purchase cannot be expressed.
--
-- WHAT THIS MIGRATION IS NOT. It adds NO table, NO column, NO FK-shaped reference,
--   NO INTEGER[], NO trigger, NO policy, NO grant, and NO SECURITY DEFINER
--   function. As at 087, the substrate already exists and the gap was composition.
--
-- ----------------------------------------------------------------------------
-- THE ROW SHAPE IS NOT A CHOICE — 084 ALREADY DECIDED IT, and the alternative is a
-- silent GL imbalance rather than a different style.
--   A purchase is ONE row: transaction_type='standard', security_id NOT NULL,
--   quantity > 0, cost_basis = +cost, amount = -cost. Against the live GL branch
--   set: P1 books the cash leg from amount (-cost); P2 books the position add from
--   cost_basis (+cost, and the row is not excluded — P2 excludes only
--   `standard AND quantity <= 0`); P10 plugs the standard-BUY residual
--   -(amount + cost_basis) to Suspense, which is 0 here. BALANCED BY CONSTRUCTION.
--   ⚠ WRITING IT AS TWO ROWS (a cash-out row plus a position-in row) IS WRONG, not
--   merely different: P1 fires on the cash row and P10 fires on the position row
--   with amount=0 and cost_basis=+cost, producing a -cost SUSPENSE PLUG. The
--   imbalance is real and it is attributed to Suspense, where it reads as a data
--   problem rather than as a shape error. Do not "simplify" this into two rows.
--
-- ----------------------------------------------------------------------------
-- PROVENANCE — why this writes 'standard' and never 'acct_setup'.
--   The distinction is load-bearing and it keys on transaction_type ALONE: 084 P5
--   contras acct_setup rows to Opening-Balance-Equity and does not contra standard
--   rows. An OPENING BALANCE is an assertion about what was already held (087,
--   acct_setup, amount=0, equity contra). A PURCHASE is a witnessed fact — money
--   moved (standard, amount=-cost, no contra; P1+P2 balance alone).
--   transaction_type is therefore HARD-CODED here, not a parameter, exactly as 040
--   hard-codes it. ⚠ NOTHING IN THE DDL PREVENTS A DIRECT INSERT FROM WRITING THE
--   WRONG transaction_type — authenticated holds INSERT on account_trans, fenced
--   for tenancy and shape but not for provenance. The provenance guarantee comes
--   from WHICH RPC A CALLER USES, in the same way 087 (F2) depends on a battery leg
--   rather than a CHECK. Stated so a future reader does not mistake it for enforced.
--
-- ----------------------------------------------------------------------------
-- THE VALUATION HAZARD HAS THREE SPELLINGS ON THIS PATH. 087 named two; the third
-- is specific to purchasing and it is the INVERSE of the first two. All three end
-- in wrong money, and the first two end in it SILENTLY.
--   049 / 050 value a position as quantity x price x fx, where price comes from
--   pfin.eod_price — never from account_trans.price.
--
--   (F3-a) A MISSING price row yields a NULL term that SUM drops. The position
--        contributes ZERO to NAV with no error and no log line.
--   (F3-b) A price row that EXISTS but is ZERO produces the identical outcome and
--        additionally defeats any watcher that checks row PRESENCE rather than row
--        VALUE. round(cost_basis/quantity, 4) yields exactly 0.0000 whenever the
--        per-unit price falls below 0.00005, i.e. quantity > 20000 x cost_basis;
--        019's only CHECK on price is the NaN fence, so such a row is legal.
--   (F4)  RETROACTIVE REVALUATION — new here, and it is (F3)'s remedy turning into
--        a defect. 078's price pick orders by price_date desc, then a source-rank
--        CASE in which manual_valuation ranks ABOVE every feed. So writing an
--        087-style companion price onto an asset that ALREADY HOLDS A POSITION
--        restates the ENTIRE holding — every prior lot — at this purchase's
--        per-unit cost, for every as_of from the trade date until a later-dated row
--        exists, and on the trade date it OUTRANKS a same-day feed price. The
--        unrealized gain on the pre-existing lots silently vanishes.
--        ⚠ 087's rule was "every instrument-bound position also writes its
--        eod_price row." Carried across to this path unchanged, that rule CAUSES
--        (F4). It is correct at create time — where there is no prior position by
--        definition — and wrong here. It must not be inherited by analogy.
--
-- THE CONDITIONAL COMPANION RULE (F/CTO-ratified 2026-08-21). The branch is chosen
-- by WHAT ALREADY EXISTS, never by what the caller asks for:
--   (1) asset OWNED by the caller, no manual_valuation row at the trade date
--       -> WRITE round(cost_basis/quantity, 4). Closes (F3-a) and (F3-b).
--   (2) asset OWNED, a manual_valuation row already exists at the trade date
--       -> SKIP the write (019 is unique on (asset_id, price_date, source), so an
--          INSERT would raise; and overwriting is exactly (F4)). ⚠ THE SKIP NEEDS
--          ITS OWN WATCHER — see the post-condition below.
--   (3) asset is GLOBAL -> NEVER write, and this is not a policy choice: 019's
--       eod_price_insert admits source='manual_valuation' only on an asset the
--       caller OWNS, so the write is unreachable. See the UNPRICED-BUT-LOUD block.
--
-- THE POST-CONDITION, AND WHY IT NEEDS NO COPY OF THE PRICE PICK.
--   The obligation is over the price a READER WILL PICK, not over a row's presence
--   — that is the whole lesson of (F3-b). Naively that would require re-deriving
--   078's D-FIRST pick here, which would be a SECOND COPY of a kernel whose
--   multiplicity is already a known drift surface (078 and 079 exist because of it).
--   It is not needed, because on branches (1) and (2) the pick's answer is FORCED:
--   the row in question sits at price_date = p_trade_date, which is the maximum
--   price_date <= p_trade_date, and it carries source='manual_valuation', which is
--   the TOP source rank. Max date and top rank together mean the pick cannot choose
--   anything else. So asserting on THAT ROW is asserting on the pick — exactly, and
--   with no rank CASE in this file to drift from 078.
--     branch (1): the v_price > 0 fence below IS the post-condition.
--     branch (2): the existing row's price is READ BACK and asserted > 0. Without
--                 this, a skip over a worthless pre-existing row re-admits (F3-b)
--                 through the one door the write-side fence cannot see.
--
-- UNPRICED-BUT-LOUD, and the composite return is what makes it real.
--   A global asset that no provider has priced cannot be priced by this caller, and
--   ⚠ THERE IS NO MARKET-PRICE FEED IN V1 TO PRICE IT LATER: no INSERT writing
--   source='market_feed' exists anywhere in this migration set or in the worker
--   source (measured 2026-08-21; the FMP feed-writer is scoped as separate work).
--   The only price writers that exist are provider_implied (the sync worker, from a
--   PROVIDER-LINKED account's holdings) and manual_valuation (owner-only, per 019).
--   So such a position values at $0 until some provider-linked account holds the
--   same security. F/CTO ratified shipping that state rather than blocking the
--   purchase — ON THE CONDITION THAT IT IS LOUD.
--   ⚠ (F3)'s harm was never the zero; it was that the zero arrived silently. This
--   function therefore RETURNS whether a usable price stands at the trade date, as
--   a composite, so a caller that wants only the trans_id must PROJECT THE FLAG
--   AWAY — a step that is visible in a diff, where an unread obligation is not.
--   That is ADR-049 Decision 4's composite-return-over-documented-obligation
--   principle, applied to the same
--   underlying failure it was written for: silence on a financial figure.
--   ⚠ WHAT `priced` DOES AND DOES NOT CLAIM, stated because a flag that overclaims
--   is worse than none. It is TRUE iff an eod_price row exists for the asset at the
--   MAXIMUM price_date <= p_trade_date carrying price > 0. It deliberately carries
--   NO source-rank CASE, so it cannot drift from 078 — and the price of that is one
--   named imprecision: when two sources tie at that maximum date and disagree about
--   being zero, this flag reports on the date band rather than on the winner. That
--   case is not reachable through this function's own writes. The flag is an
--   indicator for the rendering layer, NOT a valuation primitive; nothing downstream
--   may compute money from it.
--
-- ROUNDING ARTIFACT, carried forward from 087 with its CORRECTED bound. eod_price
--   .price and account_trans.price are numeric(20,4), so round(cost_basis/quantity,
--   4) can be inexact against the basis. The per-unit error is up to 0.00005, so the
--   position-level error is bounded by QUANTITY x 0.00005 — a cent only up to
--   quantity ~= 200, and $50.00 at quantity 1,000,000. ⚠ An earlier draft of 087
--   called this "sub-cent amounts"; that was wrong at scale and wrong in the
--   direction that understates. The artifact is inherent to the price grain (019),
--   not introduced here, and it is why paired fixtures use exactly divisible values
--   rather than a tolerance.
--
-- ----------------------------------------------------------------------------
-- WHY THE ZERO-PRICE FENCE IS UNCONDITIONAL, and it is a DEVIATION FROM 087.
--   087 fences the derived price only where it writes one. Here the fence runs on
--   EVERY call, including the global branch that writes no price row at all.
--   The reason is that the defect is in the TRADE, not only in the price row: a
--   purchase whose per-unit price rounds to 0.0000 at the numeric(20,4) grain is a
--   mis-expressed trade, and account_trans.price would record 0.0000 as a fact about
--   what the user paid. That is false regardless of who owns the asset and
--   regardless of whether a price row is written. Fencing it once, before the
--   branch, also means the ratio defect has ONE observer rather than one per branch.
--   ⚠ THE FENCE TESTS v_price, THE LOCAL ASSIGNED ABOVE IT — not a second round(...)
--   of the same expression. An earlier 087 draft recomputed it, which is two copies
--   of one rule; the fence and the value actually written must be the same number by
--   construction, not by two expressions agreeing (Sec, SELF-325 delta review).
--
-- ----------------------------------------------------------------------------
-- SOURCE-OF-TRUTH GUARD — carried from 039, same rationale. A manual purchase is
--   only for accounts the user is source-of-truth for. On a provider-linked account
--   (account.linked_source_id IS NOT NULL, 015) the provider will eventually report
--   the same buy, and both rows would land — the manual entry and the synced one —
--   double-counting the position and the cash. Rejected here at the DB layer, not
--   left to the UI.
--
-- ----------------------------------------------------------------------------
-- THE 030 TRADE FENCE CHANGES MEANING ON THIS PATH — stated because it is inert on
--   the cash path a reader may be arriving from.
--   fn_account_trans_annotation_trade_constraints (030, BEFORE INSERT OR UPDATE on
--   account_trans_annotation, WHEN sub_cat_id IS NOT NULL) enforces (a) the
--   biconditional `security_id present <=> cat = 'Trade'` and (b) sign-alignment,
--   where BTO/BTC require quantity > 0. Every row this function writes carries a
--   security_id and a positive quantity. CONSEQUENCE: a purchase carrying ANY
--   category must carry a TRADE one, and a BTO/BTC category is sign-consistent here
--   by construction. A NULL p_sub_cat_id is legal and WHEN-skips the trigger.
--   ⚠ THIS FUNCTION DOES NOT DEFAULT THE CATEGORY, deliberately. Selecting a
--   posting-prototype row on the user's behalf would mean this body guessing at a per-user
--   vocabulary it does not own — the same single-authority rule that keeps 016's
--   asset_type vocab out of 087's body. The RECOMMENDATION (F/CTO-ratified, for the
--   app layer to implement) is that the manual-purchase form defaults the category
--   to the user's BTO row where one exists, and leaves it NULL where none does. ⚠ That row
--   lives in pfin.posting_prototype post-084, NOT in pfin.user_taxonomy, and the two id
--   spaces are DISJOINT BY CONSTRUCTION (084 caps user_taxonomy's identity at 999999999
--   and mints posting_prototype from 1000000000, with an abort guard proving no id
--   resolves in both). So an id fetched from the wrong table cannot silently match the
--   right row — it fails closed. The 030 Trade fence, re-issued at 084, reads
--   pfin.posting_prototype for the same reason.
--
-- ----------------------------------------------------------------------------
-- Numbering: 088 follows 087 (manual-account create-time value binding); taken at
--   authoring time against the live listing (git ls-tree origin/main), not reserved.
--   Order-dependent on: 003 (pfin.account and its owner-scoped RLS — the account
--   read) · 004 (the immutable account_trans ledger) · 006 (account_trans grant +
--   the wr_access-JOIN INSERT policy this composes under) · 015 (account.currency,
--   copied onto a minted asset so the 049/050 fx term resolves consistently; and
--   account.linked_source_id, the source-of-truth guard's read) · 016 (pfin.asset,
--   its grants, its hybrid global-OR-owned RLS, and its asset_type + pricing_source
--   CHECK vocabs) · 017 (security_id / quantity / cost_basis / price columns, the
--   Decision-3 #7 fence, the NaN CHECKs, and account_trans_qty_requires_security) ·
--   019 (pfin.eod_price, its unique (asset_id, price_date, source), and its
--   manual_valuation-on-owned write policy) · 023 (account_trans_annotation and its
--   matched-tenant fence) · 025 (the aal2 backstop clause, inherited through the
--   policies this composes under) · 030 (the 'standard' vocab value and the Trade
--   biconditional) · 058 (the closed-account write fence, which fires on the
--   account_trans INSERT below) · 084 (the GL branch set this row shape is written
--   for). Consumed by 049 / 050 / 076 / 084 at read time. No later migration depends
--   on 088.
--
-- DEPLOY ORDERING. This migration CREATES a new function and REPLACES nothing, so
--   there is no breaking direction: migration-first and app-first are both safe.
--   ⚠ Do not carry 087's or 048's deploy notes across by analogy — both concerned a
--   signature being replaced on an existing contract, which is not the case here.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default); NOT SECURITY DEFINER.
--   Every write is reachable by the owner under an EXISTING policy, evaluated as the
--   caller: pfin.account_trans via account_trans_insert's wr_access-JOIN (006) ·
--   pfin.asset via asset_insert WITH CHECK (users_id = auth.uid()) (016) ·
--   pfin.eod_price via eod_price_insert, which admits only source='manual_valuation'
--   on an asset the caller owns (019) · pfin.account_trans_annotation via ata_insert's
--   wr_access-JOIN (023). All four are aal2-backstop-claused (025), so step-up is
--   enforced THROUGH this RPC with no in-function aal check — the INVOKER-RLS
--   composition IS the enforcement. A cross-tenant caller sees no account and cannot
--   INSERT. DEFINER would BREAK this by evaluating the fences as the owner.
--   This file states NO allowlist count; read ADR-011 Decision 9 live.
--   `set search_path = ''` is the injection fence; every reference is schema-
--   qualified. EXECUTE revoked from PUBLIC (which denies anon), granted to
--   authenticated only.
--
--   ⚠ WHAT THE ACCOUNT AND ASSET READS ARE FOR, and what they are NOT. The account
--   read resolves currency and linked_source_id and establishes that the caller can
--   see the account. The asset read establishes ONE BRANCHING FACT — whether the
--   asset is owned by the caller or global — because the companion-price rule
--   differs between them. NEITHER READ IS THE TENANT FENCE. The fence on
--   security_id is the Decision-3 #7 BEFORE INSERT trigger
--   (fn_account_trans_security_asset, 017), which is authoritative independently of
--   RLS and fires on the INSERT below. Stated explicitly because a reader who
--   mistook the branching read for the fence might later "optimize" it away and
--   would believe they had removed a redundancy.
--   ⚠ BOTH HALVES ARE TRUE AND THE SECOND IS EASY TO MISREAD. #7 is AUTHORITATIVE — it is
--   the sole gate on the service_role path, where no guard in this body runs — but
--   THROUGH THIS FUNCTION the asset guard at (5) is the OPERATIVE rejection, because #7
--   never fires here. Removing the guard would NOT open a hole: security_id is always
--   non-null on this path, so #7's WHEN clause fires and its coincident predicate
--   rejects. It would degrade the ERROR, not the outcome.
--
--   ⚠ THE ACCOUNT READ IS DELIBERATELY NARROWER THAN THE WRITE POLICY IT COMPOSES UNDER,
--   and this is the same structural fact as the #7 dormancy, seen from the other side.
--   account_select is owner-only (users_id = auth.uid(), 003) while account_trans_insert
--   keys on the wr_access-JOIN through pfin.account_users (006). So this function is
--   STRICTLY MORE RESTRICTIVE than the write it performs — fail-closed, and the shape 039
--   uses. TODAY the difference is invisible only because account_users is V1-dormant and
--   the creator-grant makes owner and wr_access-holder the same person; that is a
--   CURRENT-STATE fact, exactly the kind that goes stale silently. WHEN SHARING IS
--   UN-DORMED this becomes a real behavioural split: a collaborator holding wr_access
--   will be able to record a cash transaction (040, which reads no account row) but NOT a
--   purchase. Whoever un-dorms it decides whether that split is intended; it is named
--   here so the decision is made rather than discovered.
--
--   ⚠ ADR-011 DECISION 1 (privileged-context-write) DOES NOT APPLY TO THIS FUNCTION,
--   and saying so is not a dismissal. D1 governs writes that ingress under NO JWT and
--   execute under service_role. This RPC is the opposite on both counts: a JWT-bearing
--   authenticated caller, INVOKER, no elevation anywhere. The D1 question raised by the
--   SELF-325 arc belongs to the SEPARATE worker-mediated global-asset resolution
--   surface, whose clause-(d) audit obligation stands against the general
--   same-transaction audit-log — which does not exist (the A2 deferral; SELF-201
--   Task #7). ⚠ THIS FUNCTION MUST NOT BE READ AS DISCHARGING THAT OBLIGATION, in
--   either direction: it neither satisfies clause (d) nor is subject to it.
--
--   AUDIT FORWARD-HOOK (A2 deferral — conscious documented deviation; ADR-026), on
--   the same terms as 087 and 006 mod #1: the same-transaction audit-log table and
--   its insert helper do not exist, so no V1 path emits audit rows. WHEN that infra
--   lands, the audit row for this write belongs HERE, in this body, in this
--   transaction. The immutable ledger row is the V1 creation-provenance stand-in.
--
-- ----------------------------------------------------------------------------
-- LOCK 14 ADVERSARIAL-NUMERIC POSTURE — WHICH LAYER OBSERVES WHICH INPUT.
--   p_quantity and p_cost_basis are user-supplied numerics on a user-facing direct-DB
--   -write surface, so the Lock 14 battery obligation applies. Stated per input class,
--   because a guard that CANNOT FIRE must not be described as an observer:
--     - "NaN" / "Infinity" / "$1,000" / "1.000,50" / any quoted or locale-formatted
--       value -> these are TYPED PARAMETERS (numeric), so the rejection happens at
--       PARAMETER COERCION, before this body runs. The app-layer Zod schema is the
--       first observer and coercion is the second; neither is this body.
--       ⚠ THIS DIFFERS FROM 087, where the same inputs arrive inside jsonb and a
--       hand-written jsonb_typeof check is their SOLE observer. Do not transplant
--       087's type-check reasoning here, and do not transplant this reasoning there.
--     - NaN reaching a numeric parameter directly (a caller passing 'NaN'::numeric)
--       -> the `= 'NaN'::numeric` disjunct below. This is REACHABLE here, unlike
--       087's, where jsonb has no NaN literal.
--     - 0 and negatives -> the `<= 0` disjunct.
--     - Infinity -> the `>= 'Infinity'::numeric` disjunct.
--     - Finite-but-huge (1e400 and similar) -> rejected by numeric(28,8) /
--       numeric(20,4) COLUMN COERCION (017), not by this body. That rejection is real
--       and role-agnostic; only its message is less specific. Stated so a battery leg
--       asserts REJECTION rather than a message.
--   ⚠ `'NaN'::numeric > 0` is TRUE — numeric NaN sorts above every number — so a
--   positivity check ALONE re-admits NaN and Infinity. The disjuncts are named
--   separately for that reason and must not be collapsed into one.
--   ⚠ THE RATIO SURFACES ARE WHERE THE REAL DEFECT CLASS LIVES, and there are TWO of
--   them here where 087 had one. A ratio defect exists where NO SINGLE VARIABLE IS
--   EXTREME: quantity 1000000 with cost_basis 10.00 passes every magnitude guard and
--   derives a price of 0.0000. (i) cost_basis / quantity is the derived per-unit
--   price, fenced below. (ii) if the app lets a user enter a per-unit price and
--   derives the total, price x quantity vs cost_basis is a SECOND ratio surface — it
--   lives at the app layer, not here, and it is named so the paired battery exercises
--   RATIOS and not only magnitudes.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — UNCHANGED. NO LABEL TAKEN.
--   ADR-011 Decision 3 read live from DECISIONS.md before drafting, per its own rule.
--   This migration creates, alters and drops NO COLUMN of any kind, FK-shaped or
--   otherwise, and no INTEGER[]. The FK-shaped columns it WRITES THROUGH are existing
--   DDL-realized instances, exercised rather than extended:
--     - account_trans.security_id -> pfin.asset (#7, 017, Pattern 2 novel
--       global-OR-matched-tenant; BEFORE INSERT; tenant resolved via the account
--       chain). Fires on every row this body inserts.
--     - account_trans_annotation.sub_cat_id -> pfin.posting_prototype (instance #10;
--       the chain-resolved matched-tenant fence authored at 023) fires when a category
--       is supplied. ⚠ THE TARGET IS posting_prototype, NOT user_taxonomy, AND AN EARLIER
--       DRAFT OF THIS LINE SAID user_taxonomy. 084 / ADR-058 RE-TARGETED #10 (and #13) to
--       pfin.posting_prototype(id) when the GL split moved the posting rows out; the
--       label and the fence CLASS are unchanged — a re-target amends an entry's body and
--       never its label. ⚠ THE TRAP THAT PRODUCED THE ERROR, recorded because it is
--       reusable: Decision 3's NUMBERED ENTRY for #10 still reads `-> pfin.user_taxonomy`,
--       because that entry records original locking provenance and the re-target is a
--       LATER AMENDMENT further down the Decision. Reading the entry alone gives the stale
--       target. Read a Decision's AMENDMENTS in the same pass as its body — a retraction
--       does not travel with citations of the thing it retracts.
--   pfin.asset.users_id -> auth.users(id) is that table's TENANT ANCHOR, not a
--   cross-tenant reference.
--   ⚠ #7 IS NOT REACHABLE THROUGH THIS FUNCTION. AN EARLIER DRAFT OF THIS BLOCK SAID IT
--   WAS. The correction is recorded rather than quietly applied, because the wrong
--   version reached a commit message, three teammates and a battery plan first.
--     WHAT THE EARLIER DRAFT CLAIMED: that because 087 MINTS its asset (so #7 cannot
--     fail there, and 087's battery asserts it STRUCTURALLY via pg_trigger) while this
--     function ACCEPTS a caller-supplied p_security_id, the cross-tenant route is LIVE
--     here and the paired battery leg must exercise it behaviourally.
--     WHY IT IS FALSE — AND IT IS A PROPERTY OF THIS BODY, NOT OF #7: the account read
--     at (2) runs under account_select, which is `users_id = auth.uid()` (003) —
--     OWNER-SCOPED. Any caller who gets past (2) IS the account's tenant, so
--     acc.users_id = auth.uid(). That makes #7's predicate (GLOBAL or owned by the
--     ACCOUNT'S TENANT) coincide EXACTLY with 016's asset_select (GLOBAL or owned by the
--     CALLER), which is what the asset guard at (5) reads under. Anything the guard
--     admits, #7 admits; anything #7 would reject, the guard rejected first. No live
--     path has one passing while the other rejects.
--     MEASURED, NOT REASONED — by QA at the SELF-325 battery build, on a scratch DB with
--     this migration applied: tenant A calling with tenant B's private asset_id raises
--     the guard's message; statement (7) is never reached.
--   ⚠ IT IS DORMANT, NOT DEAD, AND THE DORMANCY RESTS ON TWO THINGS THAT CAN EACH MOVE:
--   (i) this body's OWNER-SCOPED account read, and (ii) pfin.account_users being
--   V1-dormant (003, creator-grant only), so owner and wr_access-holder coincide. Widen
--   EITHER — read the account by wr_access, or un-dorm sharing — and the caller is no
--   longer necessarily the account's tenant, at which point #7 becomes LIVE again: a
--   caller could own asset X while the account belongs to a different tenant, which #7
--   rejects and the guard does not. WHOEVER DOES EITHER MUST RE-READ THIS PARAGRAPH.
--   THE PAIRED BATTERY THEREFORE: asserts #7 STRUCTURALLY (bound + enabled, the 087
--   shape); asserts the cross-tenant rejection BEHAVIOURALLY against the GUARD, labelled
--   as the guard so it can never be mistaken for an #7 proof; and points at 017's own
--   battery, where #7's behavioural proof already lives on the path #7 actually gates
--   (raw INSERT / service_role, where no guard in this body runs at all).
--   Read Decision 3's body live at authoring time: the family GROWS, its labels are
--   NON-CONTIGUOUS, at least one is DROPPED, and *labeled* vs *DDL-realized* diverge.
--   NO COUNT IS CARRIED IN THIS FILE.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (ADR-011 Decision 4 read VERBATIM and LIVE before drafting,
-- 2026-08-21). Path B — Decision 4 is LINKED, not restated; the catalogued numbered
-- list is NOT reproduced here and NO count is carried.
--   (i)   Instance-numbering: no catalogued instance is added, removed, reordered or
--         renumbered by this migration.
--   (ii)  Layer-attribution: no catalogued instance is re-attributed, and no surface
--         becomes "four-layer". This is authenticated-tier INVOKER write-composition.
--         It touches no infrastructure-credential-presence surface, no
--         SUPABASE_SERVICE_ROLE_KEY code-layer allowlist surface, and no app->worker
--         network-admission surface. IT USES NO service_role.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is referenced, never restated.
--   LOCK 14 CLASS MEMBERSHIP: the manual-purchase form is a user-facing direct-DB
--   -write surface and its numeric inputs inherit the Lock 14 adversarial-numeric
--   battery obligation (see the posture block above). CLASS MEMBERSHIP IS NOT A
--   CATALOGUED INSTANCE — that ruling is ADR-042's, in its Consequences.
--   ⚠ It is NOT ADR-047's; that pairing is the false-composite citation ADR-011
--   Decision 4's own attribution CHANGELOG records, and it is not reproduced here.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are not
--   reconciled here or anywhere.
--
-- ----------------------------------------------------------------------------
-- SINGLE AUTHORITY FOR VOCABULARY AND UNIQUENESS — deliberately NOT re-stated here,
--   same discipline as 087. asset_type is validated by 016's own CHECK, not by a copy
--   in this body. The ONE exception is 'currency', which 016 legitimately admits and
--   the cash model forbids — cash is amount-carried, never instrument-carried (056
--   sums every amount with no security filter; 081 routes cash CLASSIFICATION through
--   the global currency-asset) — so it is rejected explicitly and the asymmetry is
--   stated rather than left to look like an oversight. Per-user asset-name uniqueness
--   is asset_user_name_uniq's (016) to enforce, not this body's.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_create_manual_purchase(
--       p_account_id  bigint, p_trade_date date, p_quantity numeric,
--       p_cost_basis  numeric,
--       p_security_id bigint DEFAULT NULL,
--       p_asset_type  text   DEFAULT NULL, p_asset_name text DEFAULT NULL,
--       p_symbol      text   DEFAULT NULL,
--       p_sub_cat_id  bigint DEFAULT NULL, p_description text DEFAULT NULL,
--       p_note        text   DEFAULT NULL)
--     RETURNS (trans_id bigint, security_id bigint, priced boolean, price numeric)
--     SECURITY INVOKER, set search_path = ''. ONE transaction, all-or-nothing.
--
--   TWO MUTUALLY EXCLUSIVE BINDING MODES — exactly one must be supplied:
--     BIND  — p_security_id names an EXISTING asset, global or caller-owned. This is
--             the market-security path (a ticker resolved against the global
--             namespace) and the buy-more-of-what-I-hold path.
--     MINT  — p_asset_type + p_asset_name (and optional p_symbol) create a new
--             CALLER-OWNED asset, pricing_source='manual_valuation', currency copied
--             from the account. This is the personal-asset path (a property, a
--             vehicle, a private holding).
--     Supplying both, or neither, raises. ⚠ MINT CANNOT PRODUCE A GLOBAL ROW and this
--     is not a policy of this body: 016's asset_insert WITH CHECK (users_id =
--     auth.uid()) rejects users_id NULL, so a user cannot create a global asset by
--     any route. A public ticker with no global row yet must be resolved through the
--     service_role-only registration path (020), not minted here.
--
--   Rows written, in one transaction:
--     MINT mode only: 1 x pfin.asset (caller-owned)
--     companion branch (1) only: 1 x pfin.eod_price (manual_valuation, p_trade_date)
--     always: 1 x pfin.account_trans (standard; amount = -p_cost_basis;
--             cost_basis = +p_cost_basis; quantity = +p_quantity; price = the derived
--             per-unit price; security_id bound)
--     when p_sub_cat_id or p_note is supplied: 1 x pfin.account_trans_annotation
--
--   RETURNS a composite so the unpriced state cannot be silently dropped (see the
--     UNPRICED-BUT-LOUD block): trans_id, the bound security_id, `priced`, and the
--     derived per-unit `price`.
--
--   RAISES (rolling the whole transaction back, so no orphan asset or price survives)
--     on: an unauthenticated caller; both or neither binding mode; a p_security_id
--     that is neither global nor caller-owned as seen under the caller's RLS; a
--     provider-linked account; a missing or empty mint name; asset_type 'currency';
--     quantity or cost_basis non-finite, zero or negative; a derived per-unit price
--     that rounds to 0.0000; and — on companion branch (2) — a pre-existing
--     manual_valuation row at the trade date whose price is not positive.
--
--   Security-load-bearing edges: the Decision-3 #7 fence is the authoritative gate on
--     security_id but does NOT FIRE on this path — the asset guard at (5) rejects first
--     and the two predicates coincide (see the Decision 3 block); the wr_access-JOIN + aal2
--     backstop gate every write as the caller; the 030 Trade biconditional and
--     sign-alignment fire when a category is supplied; the 058 closed-account fence
--     fires on the account_trans INSERT; the 004 immutable ledger is untouched
--     (corrections stay reverse-and-replace).
--
--   Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023).
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_create_manual_purchase(
  p_account_id  bigint,
  p_trade_date  date,
  p_quantity    numeric,
  p_cost_basis  numeric,
  p_security_id bigint  default null,
  p_asset_type  text    default null,
  p_asset_name  text    default null,
  p_symbol      text    default null,
  p_sub_cat_id  bigint  default null,
  p_description text    default null,
  p_note        text    default null,
  out trans_id    bigint,
  out security_id bigint,
  out priced      boolean,
  out price       numeric
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid         uuid;
  v_currency    text;
  v_linked      bigint;
  v_found       boolean;
  v_asset_found boolean;
  v_owned       boolean;
  v_name        text;
  v_symbol      text;
  v_price       numeric;
  v_existing    numeric;
  v_has_row     boolean;
begin
  -- (0) Caller-context guard — DEFENSE IN DEPTH over an already-closed path, on the
  -- same honest terms 087 records. Without it the call still fails, at (1), because
  -- the account read returns no row for a caller with no auth context. It earns its
  -- place by failing early with a named cause instead of a generic "account not
  -- found", and by pinning the requirement in the function whose entire security
  -- model is "evaluate as the caller". It removes no exercisable capability.
  v_uid := auth.uid();
  if v_uid is null then
    raise exception
      'fn_create_manual_purchase requires an authenticated caller: auth.uid() is NULL. This RPC is SECURITY INVOKER and every fence it relies on evaluates as the caller (SELF-325 / 088).';
  end if;

  -- (1) Binding mode. Exactly one of BIND / MINT. Checked before anything is written
  -- so an ambiguous request costs nothing.
  if (p_security_id is not null) and (p_asset_type is not null or p_asset_name is not null) then
    raise exception
      'Supply either p_security_id (bind an existing asset) or p_asset_type + p_asset_name (mint a new owned asset) — not both (SELF-325 / 088).';
  end if;
  if (p_security_id is null) and (p_asset_type is null or p_asset_name is null) then
    raise exception
      'A purchase must name what was bought: pass p_security_id to bind an existing asset, or p_asset_type + p_asset_name to mint a new owned one (SELF-325 / 088).';
  end if;

  -- (2) Resolve the account under the caller's RLS (003). A cross-tenant or unknown
  -- account_id returns no row and fails closed here. currency is copied onto a minted
  -- asset so the 049/050 fx term resolves the same way for the security leg as for
  -- the cash leg. ⚠ This read is not the tenant fence for the WRITE — that is
  -- account_trans_insert's wr_access-JOIN (006), evaluated as the caller.
  select true, a.currency, a.linked_source_id
    into v_found, v_currency, v_linked
    from pfin.account a
   where a.account_id = p_account_id;

  if v_found is null then
    raise exception
      'Account % not found or not visible to this caller (SELF-325 / 088).', p_account_id;
  end if;

  -- SOURCE-OF-TRUTH GUARD (carried from 039). A provider-linked account will report
  -- this same buy on its next sync; recording it manually too double-counts both the
  -- position and the cash.
  if v_linked is not null then
    raise exception
      'Account % is provider-linked, so its transactions come from the provider. Recording a purchase manually here would double-count it against the next sync (SELF-325 / 088; the 039 source-of-truth guard).',
      p_account_id;
  end if;

  -- (3) Lock 14 numeric fences. See the posture block for which layer observes which
  -- input class. ⚠ The disjuncts are named separately and must not be collapsed:
  -- 'NaN'::numeric > 0 is TRUE, so a positivity check alone re-admits NaN.
  if p_quantity is null
     or p_quantity = 'NaN'::numeric
     or p_quantity <= 0
     or p_quantity >= 'Infinity'::numeric then
    raise exception
      'p_quantity must be a finite number greater than zero, got %. A purchase adds a positive quantity; a disposal is not this path (SELF-325 / 088).',
      p_quantity;
  end if;

  if p_cost_basis is null
     or p_cost_basis = 'NaN'::numeric
     or p_cost_basis <= 0
     or p_cost_basis >= 'Infinity'::numeric then
    raise exception
      'p_cost_basis must be a finite number greater than zero, got % (SELF-325 / 088).',
      p_cost_basis;
  end if;

  -- (4) The derived per-unit price, and the UNCONDITIONAL zero-rounded fence. Division
  -- is safe: p_quantity > 0 is established above. ⚠ The fence tests v_price, THE LOCAL
  -- ASSIGNED HERE — not a second round(...) of the same expression. The fence and the
  -- value written must be the same number by construction. ⚠ It runs on every call,
  -- including branches that write no price row, because a per-unit price of 0.0000 is
  -- a mis-expressed TRADE and account_trans.price would record it as a fact.
  v_price := round(p_cost_basis / p_quantity, 4);
  if v_price <= 0 then
    raise exception
      'This purchase derives a per-unit price of 0.0000 and would record a worthless trade: cost_basis % over quantity % is below the numeric(20,4) price grain (a per-unit price under 0.00005, i.e. quantity > 20000 x cost_basis). A position priced at zero values at zero, silently. Re-express it with a smaller quantity or a larger cost_basis (SELF-325 / 088).',
      p_cost_basis, p_quantity;
  end if;

  -- (5) Bind or mint the asset, and establish the ONE branching fact the companion
  -- rule needs: is this asset OWNED by the caller, or GLOBAL?
  if p_security_id is not null then
    -- BIND. The read establishes ownership for branching. ⚠ IT IS NOT THE FENCE: the
    -- authoritative gate is the Decision-3 #7 BEFORE INSERT trigger (017), which is
    -- independent of RLS and fires at (7). This read fails closed too — 016's
    -- asset_select is global-OR-owned, so another tenant's private asset is invisible
    -- — but that coincidence is a property of a policy, and the fence must not be
    -- described as resting on it.
    select true, (a.users_id = v_uid)
      into v_asset_found, v_owned
      from pfin.asset a
     where a.asset_id = p_security_id;

    if v_asset_found is null then
      raise exception
        'security_id % is not a global or caller-owned asset (SELF-325 / 088). A public security with no global registration yet must be registered through the provider-sync resolution path (020), which is service_role-only — a user cannot create a global asset row (016 asset_insert).',
        p_security_id;
    end if;
    v_owned    := coalesce(v_owned, false);   -- users_id IS NULL => global, not owned
    security_id := p_security_id;
  else
    -- MINT a caller-owned asset. 016's CHECK is the single authority for the
    -- asset_type vocabulary; the one explicit rejection is 'currency', which the cash
    -- model forbids (see SINGLE AUTHORITY above). users_id is passed EXPLICITLY rather
    -- than left to the column DEFAULT, because pfin.asset.users_id is NULLABLE and a
    -- NULL there means GLOBAL (016's hybrid posture), not ownerless — so the owner is
    -- stated in the statement that creates the row.
    if p_asset_type = 'currency' then
      raise exception
        'p_asset_type may not be ''currency'': cash is amount-carried, not instrument-carried, and its classification already routes through the global currency-asset (056 + 081). A cash movement is fn_create_manual_trans, not a purchase (SELF-325 / 088).';
    end if;

    v_name := btrim(p_asset_name);
    if v_name = '' then
      raise exception 'p_asset_name must not be empty (SELF-325 / 088).';
    end if;
    v_symbol := nullif(btrim(coalesce(p_symbol, '')), '');

    insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
    values (v_uid, p_asset_type, 'manual_valuation', v_symbol, v_name, v_currency)
    returning asset_id into security_id;

    v_owned := true;
  end if;

  -- (6) THE CONDITIONAL PRICE COMPANION. The branch is chosen by what already exists.
  -- See the three-branch rule and the post-condition argument in the header.
  if v_owned then
    select true, e.price
      into v_has_row, v_existing
      from pfin.eod_price e
     where e.asset_id   = security_id
       and e.price_date = p_trade_date
       and e.source     = 'manual_valuation';

    if v_has_row is null then
      -- BRANCH (1) — write it. v_price > 0 is already established at (4), and that
      -- fence IS this branch's post-condition: the row sits at the maximum price_date
      -- <= p_trade_date and carries the top source rank, so it is the row the pick
      -- returns. Written under 019's eod_price_insert policy (manual_valuation on an
      -- owned asset), evaluated as the caller.
      insert into pfin.eod_price (asset_id, price_date, source, price)
      values (security_id, p_trade_date, 'manual_valuation', v_price);
    else
      -- BRANCH (2) — SKIP the write. Overwriting is (F4): manual_valuation outranks
      -- every feed, so restating this asset's price at THIS purchase's cost would
      -- revalue every prior lot. ⚠ THE SKIP IS WATCHED. A pre-existing row that is
      -- worthless re-admits (F3-b) through the one door the write-side fence cannot
      -- see — the row exists, so a presence check passes, and the position values at
      -- quantity x 0. Asserting on THIS row is asserting on the pick, for the same
      -- max-date + top-rank reason as branch (1).
      if v_existing is null or v_existing <= 0 then
        raise exception
          'A manual valuation already exists for this asset at % and its price is % — the position would value at zero. This purchase is refused rather than silently valued at nothing; correct the existing valuation first (SELF-325 / 088; the F3-b spelling a presence check cannot see).',
          p_trade_date, v_existing;
      end if;
    end if;

    priced := true;
    price  := v_price;
  else
    -- BRANCH (3) — GLOBAL asset. No price write is possible: 019's eod_price_insert
    -- admits manual_valuation only on an asset the caller OWNS. The purchase is NOT
    -- blocked (F/CTO-ratified 2026-08-21); instead the unpriced state is REPORTED, so
    -- the rendering layer can say so rather than showing a silent zero.
    -- ⚠ This predicate carries NO source-rank CASE and is NOT a copy of 078's price
    -- pick — see the header for exactly what `priced` claims and what it does not.
    select coalesce(bool_or(e.price > 0), false)
      into priced
      from pfin.eod_price e
     where e.asset_id = security_id
       and e.price_date = (
             select max(e2.price_date)
               from pfin.eod_price e2
              where e2.asset_id = security_id
                and e2.price_date <= p_trade_date);

    price := v_price;
  end if;

  -- (7) THE LEDGER ROW — ONE row, the 084 shape. amount = -cost (cash left the
  -- account), cost_basis = +cost (the position's book value), quantity = +qty,
  -- price = the derived per-unit price. P1 books -cost, P2 books +cost, P10 plugs
  -- -(amount + cost_basis) = 0. Balanced by construction; see the header for why two
  -- rows would not be. transaction_type is HARD-CODED 'standard' — this is a
  -- witnessed fact, not an opening assertion (084 P5 contras only acct_setup).
  -- source_provider / provider_txn_id / import_hash stay NULL: a manual purchase has
  -- no provider dedup identity, so it neither collides with the 017 provider-dedup
  -- partial-unique index nor gets deduped against by a later sync. is_reverse
  -- defaults false; replaces_trans_id NULL — an original, not a correction.
  -- The Decision-3 #7 fence fires HERE and is the authoritative gate on security_id.
  -- The 058 closed-account fence also fires here.
  insert into pfin.account_trans
    (account_id, transaction_date, amount, description, transaction_type,
     security_id, quantity, cost_basis, price)
  values
    (p_account_id, p_trade_date, -p_cost_basis, p_description, 'standard',
     security_id, p_quantity, p_cost_basis, v_price)
  returning account_trans.trans_id into trans_id;

  -- (8) The category / note overlay (023), only when supplied. ⚠ On THIS path the 030
  -- Trade fence is load-bearing where it is inert on the cash path: the biconditional
  -- requires cat='Trade' for a security-bearing row, and BTO/BTC require quantity > 0,
  -- which every row here satisfies. The #10 chain-resolved matched-tenant fence rejects
  -- a cross-tenant sub_cat even through this RPC. This body does NOT default the
  -- category — see the header for why that belongs to the app layer.
  if p_sub_cat_id is not null or p_note is not null then
    insert into pfin.account_trans_annotation (trans_id, sub_cat_id, note)
    values (trans_id, p_sub_cat_id, p_note);
  end if;

  -- AUDIT FORWARD-HOOK (A2 deferral; see the posture block). When the
  -- same-transaction audit-log infra lands, the audit row belongs HERE, this txn.

  return;
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke it (which denies anon, a
-- member of PUBLIC), then grant to authenticated only. The manual-purchase path is
-- authenticated-tier. Only the IN parameters form the function's identity arguments.
revoke execute on function pfin.fn_create_manual_purchase(bigint, date, numeric, numeric, bigint, text, text, text, bigint, text, text) from public;
grant execute on function pfin.fn_create_manual_purchase(bigint, date, numeric, numeric, bigint, text, text, text, bigint, text, text) to authenticated;

comment on function pfin.fn_create_manual_purchase(bigint, date, numeric, numeric, bigint, text, text, text, bigint, text, text) is
  'SECURITY INVOKER write-composition RPC (SELF-325 / 088; the purchase sibling of 087''s create-time value binding and of 040''s manual cash entry). Records an instrument PURCHASE on a manual account as ONE ledger fact, in one transaction under the caller''s RLS, and RETURNS a composite: (trans_id, security_id, priced, price). '
  'THE ROW SHAPE IS FORCED BY THE GL, not chosen: transaction_type=''standard'' with amount = -cost, cost_basis = +cost, quantity > 0 and security_id bound, so 084 P1 books -cost, P2 books +cost and the P10 standard-BUY residual plug is zero — balanced by construction. Writing the same purchase as a separate cash row plus a separate position row instead produces a -cost Suspense plug, an imbalance that reads as a data problem rather than a shape error. '
  'PROVENANCE: ''standard'' is hard-coded because a purchase is a witnessed fact while an opening balance is an assertion, and 084 P5 contras only acct_setup rows to Opening-Balance-Equity. No DDL enforces that distinction — it holds because of which RPC a caller uses. '
  'BINDING has two mutually exclusive modes: BIND an existing global or caller-owned asset via p_security_id, or MINT a new caller-owned asset from p_asset_type + p_asset_name. A user cannot create a GLOBAL asset by any route (016 asset_insert WITH CHECK rejects users_id NULL); a public security with no global row yet is registered only through the service_role resolution path (020). '
  'THE PRICE COMPANION IS CONDITIONAL, and the branch is chosen by what already exists: an owned asset with no manual_valuation row at the trade date gets one written; an owned asset that already has one is SKIPPED, because manual_valuation outranks every feed in the 078 price pick, so overwriting would restate every prior lot at this purchase''s cost; a global asset is never written, since 019 admits manual_valuation only on an owned asset. '
  'THE OBLIGATION IS OVER THE PRICE A READER PICKS, NOT OVER A ROW''S PRESENCE. A missing price row yields a NULL term SUM drops; a row that EXISTS but is zero produces the identical silent zero and defeats any presence check. Both are asserted here without copying the price pick, because a manual_valuation row at the trade date sits at the maximum price_date <= that date AND carries the top source rank, so it is necessarily the row the pick returns: the write branch is covered by the zero-price fence, and the SKIP branch reads the pre-existing row back and REFUSES the purchase when it is not positive. '
  'The zero-price fence is UNCONDITIONAL — a deviation from 087, which fences only where it writes — because a per-unit price rounding to 0.0000 at the numeric(20,4) grain (reachable whenever quantity > 20000 x cost_basis, with no single variable extreme) is a mis-expressed TRADE that account_trans.price would record as fact, whoever owns the asset. It tests the assigned local, not a recomputation of the same expression. '
  'UNPRICED-BUT-LOUD: a global asset no provider has priced cannot be priced by this caller, so the position values at zero until one does. That state ships rather than blocking the purchase, on the condition that it is not silent — hence the composite return, which forces a caller wanting only the trans_id to project the flag away, a step visible in a diff (ADR-049 Decision 4, composite-return-over-documented-obligation). ⚠ `priced` is TRUE iff an eod_price row exists at the maximum price_date <= the trade date with price > 0; it carries no source-rank CASE, so it cannot drift from 078, and the price of that is one named imprecision when two sources tie at that date. It is an indicator for the rendering layer, NOT a valuation primitive — nothing downstream may compute money from it. '
  'A provider-linked account is REFUSED (the 039 source-of-truth guard): the provider will report the same buy and both would land. '
  'Fences evaluate as the caller: account_trans_insert''s wr_access-JOIN (006), asset_insert''s WITH CHECK (016), eod_price_insert''s manual_valuation-on-owned (019) and ata_insert (023), all aal2-backstop-claused (025), so step-up is enforced through this RPC with no in-function aal check. The account and asset reads establish currency, source-of-truth and ownership-for-branching — THEY ARE NOT THE TENANT FENCE on security_id; that is the ADR-011 Decision 3 #7 BEFORE INSERT trigger (017), authoritative independently of RLS. ⚠ #7 does NOT fire on this path, and an earlier version of this comment claimed the opposite. Because the account read is owner-scoped (account_select, 003), the caller IS the account''s tenant, so #7''s global-or-account-tenant predicate coincides exactly with the global-or-caller predicate of 016''s asset_select that the body guard reads under: the guard rejects first, always (MEASURED on a scratch DB, not reasoned). #7 is DORMANT here, not dead — it becomes live again if the account read is widened to wr_access or pfin.account_users is un-dormed, since the caller would then no longer necessarily be the account''s tenant. That owner-scoped read also makes this function strictly more restrictive than account_trans_insert''s wr_access-JOIN: fail-closed today, a real behavioural split once sharing is un-dormed. '
  'On this path the 030 Trade fence is load-bearing where it is inert on the cash path: a category, if supplied, must be a Trade one, and BTO/BTC sign-alignment is satisfied by construction. This body does not default the category — selecting a per-user taxonomy row is the app layer''s to do. '
  'Lock 14 numeric posture: quoted, locale-formatted and currency-formatted values are rejected at PARAMETER COERCION before this body runs (these are typed numeric parameters — unlike 087, where the same inputs arrive inside jsonb and a hand-written type check is their sole observer); a NaN or Infinity passed directly as numeric is rejected by named disjuncts, kept separate because ''NaN''::numeric > 0 is TRUE; zero and negatives by an explicit guard; finite-but-huge magnitudes by numeric column coercion (017) rather than by this body. The defect class that matters is the RATIO, where no single variable is extreme. '
  'ADR-011 Decision 1 does NOT apply here and this function neither satisfies nor is subject to its clause (d): D1 governs writes ingressing under no JWT and executing under service_role, and this is a JWT-bearing INVOKER call with no elevation. The same-transaction audit-log remains DEFERRED (A2; forward-hook in body; SELF-201 Task #7). '
  'NOT a SECURITY DEFINER allowlist entry — needs no elevation; this file states no allowlist count, read ADR-011 Decision 9 live. Needs NO service_role. set search_path = '''' injection fence; every reference schema-qualified. EXECUTE revoked from PUBLIC, granted to authenticated only (anon denied). Adds NO column of any kind, FK-shaped or otherwise, and no INTEGER[] — ADR-011 Decision 3 family unchanged, no label taken; read Decision 3 live. Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed per ADR-023).';
