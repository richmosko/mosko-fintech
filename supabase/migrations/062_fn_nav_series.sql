-- ============================================================================
-- Migration: pfin.fn_nav_series — the §2.1.2 net-worth-trend READ surface.
--   SECURITY INVOKER read-composition (Lock 11) over pfin.nav_daily (054).
--   Linear SELF-219 (V1.1 "Net worth full"; PRD §2.1.2). F/CTO-ratified
--   2026-08-07: OPTION A — all three granularities (monthly / weekly / daily)
--   READ FROZEN CHECKPOINTS. Coarser views are SAMPLED FROM the daily grain,
--   never recomputed. Design brief: temp/self-219-design-brief.md.
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto surface):
--   financial calculation + multi-tenant read path + SD-24 sequence exposure.
--
-- ----------------------------------------------------------------------------
-- RATIFIED SHAPE (F/CTO 2026-08-07). Option A (all granularities read
--   checkpoints) · `p_granularity text`, not an enum · the p95 reframe · and
--   the MISSING-CHECKPOINT RETURN SHAPE = option (iii) CARRY-FORWARD + EXPOSE
--   PROVENANCE (the `checkpoint_date` output column).
--   WHY (iii) AND NOT THE TWO ALTERNATIVES, since a future reader will ask why
--   a third output column earns its place:
--     (i)  OMIT the period entirely — honest, but leaves holes in the chart and
--          gives the consumer nothing to explain them with.
--     (ii) CARRY FORWARD SILENTLY — draws a FLAT LINE through a cron outage,
--          which reads as "net worth did not move" when the truth is "we have
--          not measured since." That is ADR-042's ABSENCE IS NOT A VALUE running
--          in reverse: it makes "we didn't measure" indistinguishable from "it
--          didn't change."
--     (iii) CHOSEN — carry the value forward but ALSO return the date it came
--          from, so the consumer can tell the two apart and mark staleness. The
--          column is the detectability mechanism; without it (ii) is what you
--          have, whether or not you intended it.
--
-- ----------------------------------------------------------------------------
-- WHY OPTION A — and why the ORIGINAL AC's compute-on-demand path was rejected.
--   SELF-219's AC#3/AC#4 as drafted (2026-06-03) specified that the weekly and
--   daily paths COMPUTE ON DEMAND from account_trans history + eod_price lookup,
--   with only the monthly path reading materialized rows. That was reconciled
--   away at ratify. The reason is worth recording, because the drafted shape is
--   the one a future reader will re-propose as an "optimization" for filling the
--   PRD's 60-month window:
--
--   THE VALUATION ENGINE VALUES AN UNPRICED ASSET AT ZERO, SILENTLY. `019`'s
--   valuation body (inherited by `050` / `056` / `059`) states it in-body:
--   an asset with no priced row at-or-before the as-of date yields NULL, the SUM
--   drops it, and the contribution is 0 — "needs valuation", never NaN. The FX
--   leg is the same shape in the other direction: a missing historical rate
--   COALESCEs to 1.0, valuing a foreign-currency holding at par.
--   >> So a recomputed point below price coverage is not MISSING and not NULL —
--      it is a CONFIDENT, PLAUSIBLE, WRONG NUMBER. <<
--   Rendered across a 60-month window it draws a curve climbing from near-zero
--   to true net worth, which is INDISTINGUISHABLE FROM GENUINE WEALTH
--   ACCUMULATION and is invisible to every assertion on the VALUE.
--   And per ADR-027 (h) FMP is fully out of V1, so V1 eod_price population is
--   manual valuations plus the historical-sheet seed only — for a backward
--   window the coverage is largely absent BY DESIGN, not thin by accident.
--
--   NOTE ON A STRUCK RATIONALE, so it is not re-litigated from a stale premise:
--   ADR-040 originally justified precomputation on TEMPORAL grounds (is_active
--   was current-state). ADR-042 STRUCK that argument and `059` DDL-realized the
--   strike — as-of scoping is now temporally sound at any as-of date. THE
--   TEMPORAL OBJECTION IS GONE. Option A rests on the two ADR-040 grounds that
--   never depended on it: PROVIDER RESTATEMENT (a checkpoint records what was
--   BELIEVED then; the ledger is immutable but providers add and correct rows
--   later, and price rows can be inserted for past dates) and HISTORICAL PRICE
--   COVERAGE (above). Both are unfixable by ledger hygiene, which is exactly
--   why they are the durable grounds.
--
--   CONSEQUENCE, STATED PLAINLY: the series is FORWARD-ONLY (ADR-040), so it
--   starts at the first cron run and lengthens. V1.1 ships a chart that is
--   CORRECT AND SHORT rather than long and fabricated. Filling the window is a
--   separate, un-parked-by-decision question (SELF-217, PARKED 2026-08-06);
--   the temporally-sound path if it is ever wanted is a BOUNDED backfill that
--   WRITES checkpoints, not an on-read recompute — and the bounding is
--   load-bearing, since an unbounded backfill would write the fabricated zeros
--   above into an APPEND-ONLY table where they are removable only by a
--   migration. THIS FILE'S CONTRACT IS UNCHANGED BY THAT FUTURE DECISION:
--   rows appear, the series lengthens, this function is not touched.
--
-- ----------------------------------------------------------------------------
-- Numbering: 062 follows 061 (the UTC TimeZone pin), taken at authoring time.
--   Depends on: 054 (pfin.nav_daily — the sole table read; its owner-only RLS
--   SELECT policy and its inherited 025 aal2 step-up backstop are what fence
--   this function, see TENANT FENCE below). No DDL dependency on 050 / 019 —
--   and deliberately so; see NO-RECOMPUTE FENCE. No downstream migration
--   depends on 062. Standalone read helper; order-independent after 054.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 read-composition default);
--   NOT SECURITY DEFINER. The function runs as the calling user and inherits
--   their RLS context, exactly like fn_account_unrealized_gl (049) and
--   fn_nav_composition (051), whose posture this clones. It needs no elevated
--   privilege: every row it returns is a row the caller may already SELECT
--   directly from pfin.nav_daily. DEFINER here would be strictly worse — it
--   would detach the read from the caller's RLS context and, critically, from
--   the 025 aal2 step-up backstop that nav_daily's SELECT policy carries.
--   THE SECURITY DEFINER ALLOWLIST IS NOT TOUCHED BY THIS MIGRATION — this file
--   authors ONE function and it is INVOKER. Read ADR-011 Decision 9 live for
--   the allowlist's membership; no count is restated here.
--
-- ----------------------------------------------------------------------------
-- TENANT FENCE — RLS IS THE SOLE MECHANISM, AND THAT IS A DELIBERATE CHOICE.
--   This function adds NO `users_id = auth.uid()` predicate of its own. Isolation
--   comes entirely from nav_daily's `nav_daily_select` policy (054), which the
--   INVOKER posture inherits. A cross-tenant caller therefore sees ZERO ROWS
--   rather than an error — fails closed, matching 051.
--
--   WHY NOT ADD A REDUNDANT PREDICATE as defense-in-depth. Because it would make
--   QA's cross-tenant battery VACUOUS on the mechanism it exists to test: with a
--   local users_id filter, the isolation assertion passes even if the RLS policy
--   were broken open, so the test would report green over a defeated fence. The
--   redundancy would buy a second layer at the cost of the ability to verify the
--   first, and the first is the one the whole V1 isolation model rests on. This
--   also matches the 049 / 050 / 051 read-composition precedent, which likewise
--   carry no local tenant predicate.
--   >> THIS IS NOT AN ARGUMENT YOU HAVE TO TAKE ON TRUST — IT IS MEASURED, AND
--      THE MEASUREMENT COULD HAVE FALSIFIED IT. QA did not accept the rationale;
--      it BUILT THE COUNTERFACTUAL — a variant of this function identical except
--      for the two redundant `users_id = auth.uid()` predicates — and ran both
--      under the same sabotage (policy replaced with `using (true)`). This
--      function returned the other tenant's rows and went RED; the
--      redundant-predicate variant stayed GREEN over the removed fence. The
--      omission is therefore load-bearing, and re-adding a "harmless" local
--      predicate would silently blind the battery. Re-proven on every run by
--      TWO legs that must BOTH be cited, because they prove DIFFERENT halves:
--        · (V1-FENCE-CORRUPTED-IS-DETECTED) — the battery CAN see a broken
--          fence. Necessary, but on its own it says nothing about the predicate.
--        · (V3-REDUNDANT-PREDICATE-WOULD-BLIND-US) — the predicate WOULD HAVE
--          HIDDEN it. THIS is the leg that justifies the omission; citing only
--          the first would point at evidence for a weaker claim than this block
--          makes. <<
--   A NOTE ON THE OTHER SABOTAGE, because it changes which legs are load-bearing:
--   under a DROPPED policy (rather than one broken open) RLS default-denies and
--   the cross-tenant NEGATIVE passes VACUOUSLY — only the paired POSITIVE legs
--   fire. The two sabotage modes are caught by DIFFERENT HALVES of the battery,
--   so deleting any positive leg as "redundant with the negative" silently
--   reopens one of them. Demonstrated at (V4-FENCE-ABSENT-IS-VACUOUS) — which
--   the battery labels, correctly, as a demonstration of VACUITY and NOT a proof
--   of isolation. ⚠ NEVER CITE IT AS SUPPORT FOR THE FENCE WORKING; it is the
--   worked example of a leg that passes while proving nothing.
--
--   AAL2 STEP-UP BACKSTOP — INHERITED, NOT RESTATED (C3 standing obligation /
--   ADR-029 / 025). This migration creates NO table and NO policy, so it has no
--   policy of its own to clause. The backstop reaches this surface through
--   nav_daily's SELECT policy: a reader whose own mfa_policy is totp/passkey and
--   whose session is not aal2 sees zero rows THROUGH THIS FUNCTION TOO. That is
--   a PROPERTY TO BE ASSERTED, NOT A CLAIM THIS FILE MAY MAKE ON ITS OWN
--   BEHALF — see the QA battery requirement below, which requires the positive
--   leg (aal2 session returns N > 0) precisely because the negative leg alone
--   passes vacuously on an empty fixture.
--
-- ----------------------------------------------------------------------------
-- NO-RECOMPUTE FENCE — the property that keeps Option A from silently becoming
--   Option B. This function reads exactly ONE relation: pfin.nav_daily. It calls
--   no valuation function, directly or transitively.
--   >> THE FUNCTION BODY BELOW DELIBERATELY DOES NOT NAME THE VALUATION FUNCTION
--      ANYWHERE — NOT IN CODE, AND NOT IN AN INLINE COMMENT. <<
--   That is not fastidiousness; it is what makes a SOURCE-LEVEL assertion
--   possible. QA's fence greps the function's stored source (`prosrc` — the
--   text between the $$ delimiters, which EXCLUDES this header), so any prose
--   ABOUT the valuation function placed inside the body would match the fence
--   and defeat it. A check that scans a corpus eventually scans the prose
--   written about the check. Discussion of that function belongs HERE, in the
--   header, where it cannot reach `prosrc`. KEEP IT THAT WAY when editing.
--
-- ----------------------------------------------------------------------------
-- ZONE NEUTRALITY — LOAD-BEARING, AND IT IS WHY THIS FILE DOES NOT TOUCH THE
--   OPEN nav_date ONE-WAY DOOR. Every date expression in the function operates
--   on `date` and `timestamp` (WITHOUT time zone), so NOTHING in it is
--   evaluated in the session TimeZone.
--   PRECISELY, AND THE PRECISION IS THE WHOLE POINT (see near-miss (5) below):
--   the FUNCTION BODY contains no occurrence of EITHER SPELLING of the
--   zone-aware timestamp type — neither the alias `timestamptz` NOR the
--   canonical `timestamp with time zone` — AND no clock function
--   (`current_date` / `now()` / `localtimestamp` / `current_timestamp` /
--   `statement_timestamp`), in an expression OR in a comment. So `prosrc` can
--   be asserted against all three classes directly (QA item 10). This header
--   names them freely; `prosrc` excludes everything above the $$ delimiter,
--   which is exactly why the discussion lives up here.
--   ⚠ MEASURED, and recorded because it is the reusable part. The same root
--   trap was hit NINE TIMES across this surface — five by the author of
--   the rule against it, one by the reviewer who caught the fifth, one in
--   the DESIGN both of them agreed on, and two found by Sec at joint-review
--   AFTER all of the above had been fixed. THAT is what makes the lesson general
--   rather than anecdotal: knowing the rule demonstrably does not confer
--   immunity to it.
--     (1) the fence itself — the reason the valuation function is discussed
--         only up here and never in the body;
--     (2) the first draft's inline body comment warning "do not change this to
--         <the zone-aware type>", which put the token in `prosrc` and would
--         have defeated the very fence it was advocating (the verification run
--         caught it; four careful readings had not); and
--     (3) the `comment on` below, which claimed there was no such type
--         "ANYWHERE" — in a sentence containing the type's name. Unbounded and
--         self-falsifying: a reader grepping the .sql file gets hits and
--         concludes the comment is lying, which is corrosive in a file whose
--         posture rests on its comments being trustworthy. Now bounded to
--         `prosrc`. (It survived the fix to (2) because it sits in a DIFFERENT
--         BLOCK — a corrected block reads as having handled the whole class.
--         Re-scan the file, never just the hunk you edited.)
--     (4) THE FALSIFICATION TEST PROPOSED FOR THE TENANT FENCE (see TENANT
--         FENCE) was "drop the policy and confirm the battery goes red." It
--         WOULD have gone red — for the WRONG REASON. Postgres RLS fails CLOSED
--         on an absent policy, so dropping it default-denies EVERY tenant
--         including the owner: the red comes from the owner-reads-own-rows leg
--         and proves only that RLS is switched on, while the cross-tenant leg
--         (which asserts zero rows) stays green THROUGHOUT and the leak path is
--         never exercised. >> "REMOVE THE CONTROL AND SEE IF THE TEST NOTICES"
--         IS A VALID FALSIFICATION ONLY WHEN REMOVAL FAILS *OPEN*. WHEN A
--         CONTROL FAILS CLOSED YOU MUST *CORRUPT* IT (`using (true)`), NOT
--         REMOVE IT. << Corollary, and the half most easily dropped as
--         stylistic: under `using (true)` a SAME-VALUE fixture leaks INVISIBLY.
--         ⚠ AND THE MECHANISM IS NOT ROW-DOUBLING — an earlier draft of this
--         line said it was, and QA measured otherwise. This function reads
--         through a `cross join lateral (… limit 1)`, so a leak does not
--         duplicate rows: it changes WHICH checkpoint the lateral selects and
--         it extends the upper bound (2 → 3 rows in the fixture). The
--         cardinality assertion still earns its place, for the reason QA
--         recorded rather than the one first guessed — it survives a fixture
--         that someone later "simplifies" into uniform values. Enforced at
--         (V1b-FENCE-CORRUPTED-ROW-COUNT) and
--         (V3b-REDUNDANT-PREDICATE-BLINDS-THE-COUNT-TOO).
--         >> A CORRECT CONCLUSION REACHED THROUGH A WRONG MECHANISM IS STILL A
--            DEFECT: it survives review because the conclusion checks out, and
--            it misleads the next person who reasons FROM the mechanism. <<
--     (5) THIS BLOCK'S OWN RULE, APPLIED ONLY HALFWAY. Having argued that a
--         fence must be structural rather than exhortation, the zone fence was
--         then SPECIFIED as "no occurrence of the zone-aware type's NAME" —
--         singular — while the prohibition on CLOCK FUNCTIONS was left as prose
--         telling a future editor not to. QA measured both gaps: a body using
--         the CANONICAL spelling (`timestamp with time zone`) carries a real
--         zone-aware cast and PASSES a fence written against the alias, and a
--         body using `current_date` carries NEITHER spelling and passes BOTH
--         type fences. Closed at battery legs (Z2) + (Z3);
--         (V6-ZONE-FENCE-NEEDS-BOTH-SPELLINGS) +
--         (V7-CLOCK-FENCE-IS-NOT-COVERED-BY-TYPE-FENCES) are the sabotage
--         bodies that prove they are necessary rather than decorative.
--     (6) QA'S OWN RESTORATION CHECK, and it belongs in this list even though
--         it lives in the battery rather than here, because it is the cleanest
--         statement of the family. The check that confirmed the sabotaged
--         policy had been RESTORED counted rows in `pg_policies` — but
--         `alter policy … using (true)` leaves the policy PRESENT UNDER THE
--         SAME NAME, so the count reads 1 in BOTH the corrupted and the
--         restored world. It could not tell them apart and would have passed
--         over a still-broken fence. Now asserts the qual itself.
--         >> COUNTING THE PRESENCE OF A CONTROL CANNOT OBSERVE ITS INTEGRITY. <<
--         Same shape as the ledger-count discipline this project already runs
--         on: a tally is not a description of the thing tallied.
--     (7) THE DESIGN OF THIS VERY BLOCK — recorded as the HONEST COST of a
--         deliberate choice, not as a slip in executing it. Every "(TAG)"
--         above points at a battery leg instead of restating it, chosen so
--         that only ONE artifact can go stale and so that it fails LOUDLY.
--         >> BUT THE LOUDNESS IS NOT A PROPERTY OF THE POINTER — IT IS A
--            PROPERTY OF SOMEBODY DEREFERENCING IT. Until someone follows the
--            citation, a dangling pointer is exactly as silent as the
--            divergence it was preferred over. A CITATION IS A FENCE WHOSE
--            ENFORCEMENT IS DEFERRED TO A HUMAN WHO MAY NEVER ARRIVE. <<
--         It happened here: QA froze these tags (renaming one is a
--         cross-artifact change, stated in the battery), the tags were renamed,
--         and this header shipped one commit citing the old short forms.
--         ⚠ AND THE CHECK ITSELF HAS TWO DISTINCT FAILURE MODES, which must
--         NOT be collapsed — they have DIFFERENT REMEDIES, and filing one
--         under the other prescribes a fix that cannot work on it:
--           (a) AIMED AT THE WRONG VERSION. A pointer-checker is an instrument
--               like any other and can read a remembered or reported state
--               instead of the tree. REMEDY: pin the ref — quote the commit
--               measured alongside every finding, and assert on the tree under
--               review. (Instance: a hash "independently verified" by
--               re-reading the SAME working tree the first reader used, which
--               proved nothing; `git show <commit>:<path>` settled it.)
--           (b) CORRECT WHEN TAKEN, OVERTAKEN IN FLIGHT. The dangling
--               citations WERE really dangling when the grep ran; the repair
--               commit did not exist yet. Nothing was mis-measured and the
--               finding did its job. REMEDY: none available at the checker —
--               this is inherent to async review. The discipline is on the
--               RECEIVER: re-measure whether the finding still holds before
--               acting, and say which ref you re-measured at.
--         >> (b) IS NOT A DEFECT IN (a)'s CLOTHING. Ref-pinning cannot fix a
--            latency artifact, and an over-eager reading that files every
--            surprising finding under "stale instrument" would suppress
--            correct findings — the costliest possible failure for a review
--            channel, because it degrades silently and looks calm doing it. <<
--         (This distinction is itself a correction: an earlier revision of
--         this block filed (b) under (a) and prescribed ref-pinning for both.
--         A block naming a remedy for every failure mode would have been the
--         more satisfying artifact and the less true one.)
--     (8) THE `comment on` CLAIMED FENCE REACH THE FENCE DOES NOT HAVE — found
--         by Sec at joint-review. It read that this function "reaches NO
--         valuation function DIRECTLY OR TRANSITIVELY … fenced by a
--         source-level QA assertion." The STATE was true; the CLAIM was false
--         for the transitive half, because (N1)/(N2) grep the prosrc of ONE
--         function and a source grep over one function structurally cannot
--         observe transitivity. Sec built two bodies passing both fences while
--         genuinely recomputing: a one-line `language sql` wrapper, and a name
--         assembled by concatenation in dynamic SQL.
--         >> PURE SOUND-QUOTE: every word of the sentence survives a verbatim
--            check, and the cited instrument does not support the claim.
--            VERBATIM-CHECKING A CITATION VERIFIES THE QUOTATION, NEVER THE
--            CLAIM — for that you must ask what the cited instrument can
--            actually observe. <<
--         Now bounded to what (N1)/(N2) see, with the transitive half stated
--         as HELD BY REVIEW, NOT BY THE FENCE — and whoever adds a helper call
--         warned they owe that review, because nothing will fail if they skip
--         it. ⚠ It also survived the fix to (3) for the SAME reason (3)
--         survived (2): DIFFERENT BLOCK. That is CP9 recurring a THIRD time in
--         this one file — re-scan the whole file, never the hunk.
--     (9) THE FIX FOR (5) WAS ITSELF A DENY-LIST. Having learned that one
--         spelling was too narrow, the remedy was "two spellings plus an
--         enumerated clock list" — which is the same error one level up, and
--         Sec found four more evasions that pass all three. AN ENUMERATION IS
--         EXHORTATION WEARING A REGEX. The structural fix is to stop measuring
--         the proxy and measure the property: assert output is byte-identical
--         under two extreme session TimeZones (see QA item 10).
--         >> NOTE THE SHAPE: (5) was diagnosed correctly and REMEDIED IN ITS
--            OWN IDIOM. A defect can be fully understood and still be fixed
--            with a bigger instance of itself, because the idiom that produced
--            it is the one you reach for while fixing it. <<
--         REMEDY (routed to DevOps, deliberately NOT built here — a migration
--         is the wrong home for a repo-wide fence): a CI check asserting that
--         every "(TAG)" cited in a migration resolves in its paired battery,
--         run on the PR's own tree. Until that exists, this block's soundness
--         rests on a human doing it, and that is the standing exposure.
--   >> THE GENERALIZATION: A FILE THAT FORBIDS A TOKEN WILL CONTAIN THAT TOKEN
--      MOST DENSELY IN THE PROSE EXPLAINING THE PROHIBITION. So a fence's scope
--      must be defined by STRUCTURE (`prosrc` — mechanically checkable) and
--      NEVER by EXHORTATION ("anywhere" — not checkable, and false the moment
--      you write it down). AND A SPECIFICATION IS ITSELF EXHORTATION UNTIL AN
--      ASSERTION IMPLEMENTS IT: (5) happened because the rule was stated in one
--      block and only partly encoded in another.
--   >> THE THREE DIAGNOSTIC QUESTIONS — the transferable part; the nine anecdotes
--      above are disposable, these are not:
--        · "CAN THIS CHECK EVER FAIL?" — catches an instrument that cannot
--          observe the property at all (the rejected EXPLAIN fence: plpgsql
--          bodies are opaque to the planner, so it would have passed forever,
--          including over a fully recomputing implementation).
--        · "WHICH WAY DOES THE THING I REMOVED FAIL?" — catches an instrument
--          that observes in the wrong DIRECTION (near-miss (4)). This question
--          does not occur to you when a control's ABSENCE resembles its
--          VIOLATION, which is exactly when you need it.
--        · "AM I OBSERVING THE PROPERTY, OR A PROXY FOR IT?" — catches an
--          instrument aimed at the wrong OBJECT (near-miss (6): a policy COUNT
--          in place of the policy's QUAL; a token's ALIAS in place of the type;
--          a ledger TALLY in place of the enumeration). The proxy is almost
--          always the cheaper thing to measure, which is why it gets reached
--          for, and it agrees with the property right up until the moment the
--          two diverge — which is the only moment that mattered. <<
--
--   WHY THAT MATTERS SPECIFICALLY. `060`'s comment on pfin.account.closed_at
--   records that `059` legalised past as-of dates and warns that a §2.1.2
--   trajectory passing a USER-CHOSEN date is now a sanctioned path — and that
--   whoever makes an as-of date user-supplied OWNS resolving the zone
--   explicitly. THIS FUNCTION IS THE §2.1.2 TRAJECTORY AND ITS DATE BOUNDS ARE
--   USER-SUPPLIED, so that warning is addressed to this surface. Under Option A
--   the obligation is DISCHARGED BY CONSTRUCTION rather than by a convention:
--   the user-supplied dates are compared only against nav_daily.nav_date, which
--   is itself a `date`, so the closed_at / as-of comparison the warning is about
--   IS NEVER CONSTRUCTED HERE. Had the compute-on-demand path been built, it
--   would have been.
--
--   ⚠ EXPLICIT INSTRUCTION TO A FUTURE EDITOR: the separate, still-OPEN one-way
--   door over WHICH ZONE pfin.nav_daily.nav_date DERIVES IN (open only while
--   there are zero production checkpoints; closes at Phase 7 cutover) is NOT
--   touched by this file and MUST NOT BECOME touched by it. This function only
--   READS nav_date; it writes no checkpoint and imprints no convention.
--   Introducing `current_date`, `now()`, `localtimestamp`, or any timestamptz
--   cast here would make this surface a party to that decision. If you need a
--   "today" bound, use the LAST-CHECKPOINT BOUND already implemented below —
--   it is zone-free and strictly more honest (see SERIES BOUNDS).
--
-- ----------------------------------------------------------------------------
-- SERIES BOUNDS — the series never extends past evidence, in EITHER direction.
--   · LOWER: a period whose end precedes the caller's FIRST checkpoint yields no
--     row at all (the lateral finds nothing at-or-before it). The chart begins
--     where the data begins; it does not begin at zero. A fabricated leading
--     zero is the exact defect Option A exists to avoid, and emitting one here
--     would reintroduce it from the other side.
--   · UPPER: no point is emitted beyond the caller's NEWEST checkpoint. Without
--     this, a caller passing an end date in the future would get a FLAT LINE
--     carried forward from the last checkpoint — reading as "net worth stopped
--     moving" when the truth is "we have not measured since." That is ADR-042's
--     "absence is not a value" running in reverse. The bound is expressed
--     against the caller's own max(nav_date) — RLS-scoped, and ZONE-FREE, which
--     a `current_date` cap would not have been.
--   · A caller with NO checkpoints gets ZERO ROWS (the max is NULL, the bound
--     comparison is NULL, every period filters out). Zero rows, NOT a zero
--     value: "no data yet" and "net worth is $0" MUST NOT render identically.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_nav_series(p_granularity text, p_start_date date, p_end_date date)
--     RETURNS TABLE (point_date date, nav_value numeric, checkpoint_date date)
--     — SECURITY INVOKER, STABLE, set search_path = ''.
--   · p_granularity ∈ {'monthly','weekly','daily'} — validated in-body, FAIL
--     LOUD on anything else (raise, never a silent empty result: an empty set is
--     indistinguishable from "this tenant has no data" and would hide a caller
--     bug on a financial surface). NOT an enum type: this schema declares no
--     enum types at all — vocabularies are CHECK constraints or free-text
--     labels — so a text domain validated in-body is the local convention.
--     F/CTO-ratified 2026-08-07.
--   · Period ends: 'daily' = each calendar day; 'weekly' = the ISO week-end
--     (Sunday) of each week; 'monthly' = each calendar month-end. A period whose
--     end falls outside [p_start_date, p_end_date] is EXCLUDED — a partial
--     trailing month is not reported as if it were a whole one.
--   · point_date      = the period end (the x-axis label).
--   · nav_value       = the frozen checkpoint value in effect at that period end.
--   · checkpoint_date = the nav_date the value actually came from. EQUALS
--     point_date when a checkpoint exists for that exact day; EARLIER when it
--     was carried forward across a gap (a cron outage). THIS COLUMN IS THE
--     DETECTABILITY MECHANISM — it is what lets a consumer distinguish
--     "measured on this day" from "last measured N days ago", which a bare
--     carried-forward value cannot. Consumers SHOULD surface staleness when
--     checkpoint_date <> point_date.
--   · Ordering: ascending by point_date. Callers may rely on it.
--   · Security-load-bearing edges: RLS on pfin.nav_daily is the SOLE tenant
--     fence (no local predicate — see TENANT FENCE); cross-tenant caller gets
--     zero rows, fails closed; the 025 aal2 backstop is inherited through that
--     same policy; no valuation function is reached, so no unpriced-asset
--     zero-fabrication path exists here; all date arithmetic is zone-free.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is stated. Decision 4 read
--   verbatim at the canonical anchor before drafting, 2026-08-07.)
--   (i)   Instance-numbering: nothing appended, reordered, or renumbered.
--   (ii)  Layer-attribution: fn_nav_series is an INVOKER read helper reached by
--         `authenticated` over PostgREST. It is NOT the PDF-worker container
--         credential audit (it is not a container), NOT the code-layer
--         SUPABASE_SERVICE_ROLE_KEY allowlist fence (it holds and needs no key —
--         it runs as the caller, which is the whole point of INVOKER), and NOT
--         the app→worker credential-admission network surface (there is no
--         worker in this path). No catalogued instance's layer attribution
--         moves; no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is REFERENCED, not restated. This
--         file is not the canonical anchor and never will be.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — +0. This migration creates NO
--   table, NO column, and NO FK-shaped reference of any kind (single FK, self-FK,
--   or array element). A function has nothing to matched-tenant-validate.
--   AUTHORING-TIME PROVENANCE (dated, not live state — read ADR-011 Decision 3's
--   body live, it grows and its labels are non-contiguous): read verbatim at the
--   canonical anchor on 2026-08-07, the family stood at SIXTEEN LABELED
--   INSTANCES (#1–#16), THIRTEEN DDL-REALIZED — #5 DROPPED at 048, #3 + #4
--   canonically-locked but DDL-deferred, #17 never allocated. That figure is
--   recorded here as a dated observation ONLY; it is NOT restated in any
--   `comment on` below, and it must not be copied forward.
--
-- ----------------------------------------------------------------------------
-- QA TEST-PAIRING (QA-owned — Architect does not author supabase/tests/). Ships
--   SAME-PR. Each item names the negative that would ACTUALLY FIRE; a fixture
--   that cannot fail is not a test.
--   1. TWO-TENANT, NON-VACUOUSLY: seed tenants A and B with checkpoints on the
--      SAME nav_date carrying DIFFERENT nav_value; assert A's call returns A's
--      values. A same-value or single-tenant fixture passes under a BROKEN
--      predicate — the varied value is the entire test.
--   2. Cross-tenant call returns ZERO ROWS, not an error (fails closed).
--   3. AAL2 BACKSTOP FIRES — BOTH legs. Seed a tenant with mfa_policy 'totp'
--      AND real checkpoints; assert an aal1 session gets 0 rows AND an aal2
--      session gets N > 0. Without the N > 0 leg the assertion passes on an
--      empty fixture and proves nothing.
--   4. PERIOD BUCKETING IS REAL: seed TWO checkpoints inside ONE month with
--      different values; assert the monthly point returns the at-or-before
--      month-end one. A fixture with one checkpoint per month cannot tell
--      correct bucketing from first-of-month, max, or average.
--   5. GAPS ARE NOT INTERPOLATED: seed a deliberate multi-day hole; assert
--      checkpoint_date < point_date across it and that the value is the last
--      real one. This is the leg that fires when a future "improvement" adds
--      interpolation.
--   6. EMPTY SERIES: a tenant with zero checkpoints returns ZERO ROWS — not an
--      error, and not a 0-valued point.
--   7. BOUNDS: assert no point is emitted before the first checkpoint or after
--      the last, including when p_end_date is in the future.
--   8. FAIL-LOUD: an unknown p_granularity raises; NULL or inverted date bounds
--      raise. Assert on the raise, not merely on emptiness.
--   9. NO-RECOMPUTE FENCE (the item that pins Option A against silent
--      regression): a SOURCE-LEVEL assertion that this function's stored source
--      does not reference the valuation function — see NO-RECOMPUTE FENCE above
--      for why the body is worded to keep that check honest. A source assertion
--      is STRICTLY STRONGER than an EXPLAIN assertion, which only characterises
--      the plan for the inputs tested; prefer it as the primary fence and treat
--      latency as the secondary proxy, so a FAST WRONG implementation still
--      fails.
--  10. ZONE FENCE (source-level, same shape as item 9) — THREE CLASSES, not
--      one. Assert this function's stored source contains: (a) no occurrence of
--      the ALIAS spelling of the zone-aware timestamp type; (b) no occurrence
--      of the CANONICAL spelling `timestamp with time zone`; and (c) no clock
--      function (`current_date` / `now()` / `localtimestamp` /
--      `current_timestamp` / `statement_timestamp`). This is what keeps the
--      surface off the open nav_date zone one-way door.
--      ⚠ (b) AND (c) ARE NOT PEDANTRY — a fence written against (a) alone is
--      DEFEATABLE and was measured so: a body spelled canonically carries a
--      real zone-aware cast and passes it, and a `current_date` body carries
--      neither spelling and passes both type fences. See near-miss (5) under
--      ZONE NEUTRALITY. Enforced at battery legs (Z2) + (Z3);
--      (V6-ZONE-FENCE-NEEDS-BOTH-SPELLINGS) +
--      (V7-CLOCK-FENCE-IS-NOT-COVERED-BY-TYPE-FENCES) are
--      the defeating bodies that prove they are necessary.
--      All three are checkable ONLY because the body is worded to keep every
--      such token out — including out of its own comments.
--      ⚠⚠ BUT (a)/(b)/(c) ARE A DENY-LIST, AND A DENY-LIST IS EXHORTATION
--      WEARING A REGEX (near-miss (9)). Sec found FOUR further evasions that
--      pass all three and are each measurably zone-dependent: `'today'::date`,
--      `'now'::timestamp`, `transaction_timestamp()`, and `timezone('<zone>',
--      …)` — whose spelling carries no space and so slips the `time zone`
--      pattern that `at time zone` trips. Extending the list closes those four
--      and not the fifth.
--      >> THE PRIMARY FENCE IS THEREFORE NOT A TOKEN CHECK AT ALL: run the
--         function twice over the SAME fixture under two extreme session
--         TimeZones and assert the output is BYTE-IDENTICAL. That observes
--         ZONE-INVARIANCE — the actual property — rather than a proxy for it,
--         and it is immune to spellings nobody has thought of yet. It is the
--         third diagnostic question ("am I observing the property, or a proxy
--         for it?") applied to this file's own fence, which until now failed
--         it. <<
--      Keep the token legs as a CHEAP SECONDARY: they localise a failure to
--      the offending token, which the invariance test cannot do. They are the
--      convenience, not the guarantee. Leg coordination is QA's; this
--      specification is the migration's.
--  11. ADR-040 ASSEMBLED-STATEMENT DISCIPLINE: execute the EXACT production
--      statement text — the real PostgREST-shaped call under the real
--      `authenticated` role with a real JWT claim — against a live database in a
--      ROLLED-BACK transaction. Not an approximation.
--   ⚠ `supabase db reset` is PROHIBITED here — it destroys the F/CTO's active
--   local test data. Verify non-destructively (apply-in-txn + rollback).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.fn_nav_series — §2.1.2 net-worth trend read surface (SELF-219, Option A).
-- Reads pfin.nav_daily ONLY. See the header for the full contract; the notes
-- inline below cover only what is not obvious from the code itself.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_series(
  p_granularity text,
  p_start_date  date,
  p_end_date    date
)
returns table (point_date date, nav_value numeric, checkpoint_date date)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- The RETURNS TABLE output names (point_date / nav_value / checkpoint_date)
-- collide with column names on the table being read. Every column reference
-- below is table-qualified, and this directive makes the resolution explicit
-- rather than incidental: an ambiguous bare name resolves to the COLUMN, never
-- to the output variable. Without it, a future unqualified reference would fail
-- at runtime with "column reference is ambiguous" instead of doing the obvious
-- thing. The three p_* parameters match no column name, so they are unaffected.
#variable_conflict use_column
declare
  -- The caller's OWN checkpoint extent (RLS-scoped — INVOKER, so these are this
  -- tenant's rows and nobody else's). Used to clamp the day expansion; see
  -- EXPANSION CLAMP in the header for why the output-side bound was not enough.
  v_first date;   -- earliest nav_date visible to the caller
  v_last  date;   -- latest   nav_date visible to the caller
  v_from  date;   -- clamped expansion start
  v_to    date;   -- clamped expansion end
begin
  -- FAIL LOUD on a bad granularity. Deliberately NOT a silent empty result:
  -- an empty set is indistinguishable from "this tenant has no checkpoints yet",
  -- so a caller typo would render as a legitimately-blank chart on a financial
  -- surface. Same fail-loud principle 054's immutability fences state.
  if p_granularity is null
     or p_granularity not in ('monthly', 'weekly', 'daily')
  then
    raise exception
      'pfin.fn_nav_series: unknown p_granularity %. Allowed values are ''monthly'', ''weekly'', ''daily'' (SELF-219 / PRD 2.1.2).',
      coalesce(p_granularity, '<NULL>');
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception
      'pfin.fn_nav_series: p_start_date and p_end_date are both required (got % .. %). An unbounded series is not a supported request.',
      coalesce(p_start_date::text, '<NULL>'), coalesce(p_end_date::text, '<NULL>');
  end if;

  if p_start_date > p_end_date then
    raise exception
      'pfin.fn_nav_series: p_start_date % is after p_end_date % — inverted range is a caller error, not an empty series.',
      p_start_date, p_end_date;
  end if;

  -- ---------------------------------------------------------------------
  -- EXPANSION CLAMP (Sec joint-review Condition 1). Resolve the caller's own
  -- checkpoint extent FIRST and expand only across it. Without this the day
  -- expansion is driven by CALLER-SUPPLIED bounds, so a request spanning
  -- millennia materialises millions of rows before the downstream bound ever
  -- filters them — measured at 6.7 s and +636 MB of temp files for a caller
  -- owning ONE row, by any authenticated user, with public signup live.
  -- ⚠ `greatest`/`least` IGNORE NULLs in Postgres (unlike most functions), so
  -- they CANNOT carry the no-checkpoints case: greatest(<date>, NULL) returns
  -- the date, which would leave the range UNCLAMPED in exactly the situation
  -- with no data to clamp to. The NULL is therefore tested explicitly, first.
  -- ---------------------------------------------------------------------
  select min(nd.nav_date), max(nd.nav_date) into v_first, v_last
  from pfin.nav_daily nd;

  -- No checkpoints visible → empty series. Zero rows, NOT a zero value, and
  -- NOT an error: "no data yet" is a legitimate state (battery (E1)/(E2)/(E3)).
  if v_first is null then
    return;
  end if;

  v_from := greatest(p_start_date, v_first);
  v_to   := least(p_end_date,  v_last);

  -- Requested window lies entirely outside the caller's data. Same zero-row
  -- outcome the downstream filters produced before, reached without expanding.
  if v_from > v_to then
    return;
  end if;

  return query
  with days as (
    -- Every calendar day in the requested range. The ::timestamp casts are
    -- LOAD-BEARING: this type is zone-free, so nothing in this function is
    -- evaluated in the session TimeZone. Swapping in the zone-AWARE variant
    -- would put the whole series at the mercy of the session zone. Do not
    -- "simplify" the casts away.
    -- ⚠ The zone-aware type's NAME is deliberately absent from this entire
    -- body — including from this comment, which is why it is worded around it —
    -- so that a source-level zone fence cannot be defeated by prose ABOUT the
    -- fence. See ZONE NEUTRALITY and NO-RECOMPUTE FENCE in the header.
    -- Bounds are v_from / v_to (the CLAMPED extent), never the raw parameters —
    -- that substitution IS the Condition 1 fix. The downstream `bounded` filters
    -- still apply the caller's original range, so OUTPUT is unchanged; what
    -- changes is that the expansion can no longer exceed the caller's own data.
    select gs::date as d
    from generate_series(
           v_from::timestamp,
           v_to::timestamp,
           '1 day'::interval
         ) as gs
  ),
  periods as (
    -- Map each day to the END of the period it falls in, then dedupe. One
    -- uniform pass for all three granularities: 'daily' is the degenerate case
    -- where the period end is the day itself.
    select distinct
      case p_granularity
        when 'daily'   then days.d
        -- date_trunc('week', …) returns the ISO week's MONDAY; +6 days is the
        -- Sunday that ends it.
        when 'weekly'  then (date_trunc('week',  days.d::timestamp)::date + 6)
        -- First of the month, plus a month, minus a day = the month's last day
        -- (correct for every month length, February and leap years included).
        when 'monthly' then (date_trunc('month', days.d::timestamp)
                             + '1 mon'::interval
                             - '1 day'::interval)::date
      end as pe
    from days
  ),
  bounded as (
    select periods.pe
    from periods
    -- A period whose end falls outside the requested range is dropped: a
    -- partial trailing month must not be reported as a whole one.
    where periods.pe between p_start_date and p_end_date
      -- UPPER BOUND — never emit a point past the newest checkpoint this caller
      -- can see, or a future end date would draw a flat carried-forward line
      -- reading as "net worth stopped moving". RLS-scoped (the caller's own
      -- max) and zone-free. NULL when the caller has no checkpoints, which
      -- correctly filters every period out and yields zero rows.
      and periods.pe <= (select max(nd_max.nav_date) from pfin.nav_daily nd_max)
  )
  select
    bounded.pe,
    cp.nav_value,
    cp.nav_date
  from bounded
  -- CROSS JOIN LATERAL (inner semantics) is deliberate: a period with no
  -- checkpoint at-or-before it produces NO ROW. That is the LOWER BOUND — the
  -- chart begins where the data begins rather than at a fabricated zero.
  cross join lateral (
    select nd.nav_value, nd.nav_date
    from pfin.nav_daily nd
    where nd.nav_date <= bounded.pe
    order by nd.nav_date desc
    limit 1
  ) as cp
  order by bounded.pe;
end;
$$;

revoke execute on function pfin.fn_nav_series(text, date, date) from public;
grant  execute on function pfin.fn_nav_series(text, date, date) to authenticated;

comment on function pfin.fn_nav_series(text, date, date) is
  'SECURITY INVOKER §2.1.2 net-worth-trend read surface (V1.1 "Net worth full"; PRD §2.1.2 / SELF-219; Lock 11 read-composition). '
  'Returns TABLE(point_date date, nav_value numeric, checkpoint_date date) ordered ascending by point_date. '
  'OPTION A (F/CTO-ratified 2026-08-07): ALL THREE granularities READ FROZEN CHECKPOINTS from pfin.nav_daily (054) — '
  'monthly and weekly are SAMPLED FROM the daily grain, never recomputed. p_granularity is one of ''monthly'' / ''weekly'' / ''daily'', '
  'validated in-body and RAISING on anything else (fail loud: an empty result would be indistinguishable from a tenant with no '
  'checkpoints, hiding a caller bug on a financial surface). NOT an enum type — this schema declares none; vocabularies are CHECK '
  'constraints or free-text labels. NULL or inverted date bounds also raise. '
  'PERIOD ENDS: daily = each calendar day; weekly = the ISO week-end (Sunday); monthly = the calendar month-end. A period whose end '
  'falls outside [p_start_date, p_end_date] is EXCLUDED, so a partial trailing month is not reported as a whole one. '
  'CARRY-FORWARD WITH PROVENANCE: nav_value is the checkpoint in effect at point_date, and checkpoint_date is the nav_date it actually '
  'came from — equal to point_date when a checkpoint exists for that exact day, EARLIER when carried across a gap (a cron outage). '
  'checkpoint_date IS THE DETECTABILITY MECHANISM: it lets a consumer distinguish "measured on this day" from "last measured N days ago", '
  'which a bare carried-forward value cannot, and consumers SHOULD surface staleness when checkpoint_date <> point_date. '
  'BOUNDS — the series never extends past evidence in either direction: no point before the caller''s first checkpoint (so the chart '
  'begins where the data begins, NOT at a fabricated zero), and no point after their newest (so a future end date cannot draw a flat '
  'carried-forward line reading as "net worth stopped moving"). A caller with no checkpoints gets ZERO ROWS — not a zero value; '
  '"no data yet" and "net worth is $0" must never render identically. '
  'READS EXACTLY ONE RELATION, pfin.nav_daily, and reaches no valuation function — which is why no unpriced-asset '
  'zero-fabrication path exists on this surface. ⚠ MIND WHAT HOLDS THAT, because the two halves are held by DIFFERENT things and an '
  'earlier revision of this comment claimed the fence covered both: the (N1)/(N2) QA fences assert the absence of a DIRECT reference '
  'in this function''s own prosrc, and the body is deliberately worded so prose about the fence cannot defeat it. They do NOT — and '
  'structurally CANNOT — observe a TRANSITIVE call through a helper function, nor a name assembled in dynamic SQL; a source grep over '
  'one function cannot see either. THE TRANSITIVE PROPERTY IS HELD BY REVIEW, NOT BY THE FENCE. Anyone adding a helper call here owes '
  'that review, because nothing will fail if they skip it. '
  'TENANT FENCE: RLS on pfin.nav_daily is the SOLE mechanism — this function adds no users_id predicate of its own, deliberately, so '
  'that QA''s cross-tenant battery tests the real fence rather than a local redundancy that would pass even if the policy were dropped '
  '(the 049 / 050 / 051 precedent). Cross-tenant caller sees zero rows (fails closed). The 025 aal2 step-up backstop is INHERITED '
  'through that same policy and reaches this surface too — a totp/passkey reader on an aal1 session sees zero rows here; QA asserts '
  'both legs, since the negative alone passes vacuously on an empty fixture. '
  'ZONE-FREE BY CONSTRUCTION: every date expression in the function body operates on date / timestamp (WITHOUT time zone), so the '
  'body contains no zone-aware timestamp type — assert it against prosrc, which is the checkable scope (this comment and the '
  'migration header both NAME that type in order to discuss it, and neither is part of prosrc; a bare grep over the .sql file '
  'therefore hits prose, not code, and is the wrong instrument). The assertion covers BOTH SPELLINGS of the zone-aware type — the '
  'alias and the canonical "timestamp with time zone" — AND the clock functions, because a body using only the canonical spelling, or '
  'only a clock function, would otherwise pass a fence written against the alias alone (measured; QA legs (Z2) / (Z3), proven '
  'necessary by (V6-ZONE-FENCE-NEEDS-BOTH-SPELLINGS) / (V7-CLOCK-FENCE-IS-NOT-COVERED-BY-TYPE-FENCES)). Nothing here is evaluated '
  'in the session TimeZone. This surface takes USER-SUPPLIED date bounds, which is the caller class 060''s '
  'comment on pfin.account.closed_at warns owns resolving the zone explicitly — the obligation is discharged BY CONSTRUCTION here, '
  'because the bounds are compared only against nav_daily.nav_date (itself a date) and the as-of/closed_at comparison that warning '
  'concerns is never constructed. A future editor MUST NOT introduce current_date, now(), localtimestamp, or any timestamptz cast: '
  'the separate open one-way door over which zone nav_daily.nav_date derives in is NOT touched by this function, which only READS '
  'nav_date and imprints no convention. For a "today" bound use the existing last-checkpoint bound, which is zone-free. '
  'FORWARD-ONLY (ADR-040): the series accumulates from the first cron run and lengthens; a future bounded backfill would lengthen it '
  'as a pure data operation WITHOUT changing this contract. '
  'set search_path = ''''; SECURITY INVOKER — NOT a DEFINER allowlist entry, and this migration authors no DEFINER function; read '
  'ADR-011 Decision 9 live for the allowlist. §10 catalogued ledger UNCHANGED BY THIS OBJECT — and NO COUNT IS STATED HERE, '
  'deliberately. A ledger-impact claim is AUTHORING-TIME PROVENANCE: it belongs in a migration header, which is a dated artifact, not '
  'in a catalog comment, which reads as LIVE STATE. Read ADR-011 Decision 4 live. Decision-3 unchanged (this migration creates no '
  'table, column, or FK-shaped reference). EXECUTE revoked from PUBLIC, granted to authenticated. '
  'Sec joint-review-mandatory (financial calculation + multi-tenant read path + SD-24 sequence exposure — this is the first surface '
  'returning a tenant''s entire per-day net-worth sequence in one call); RLS verification → SELF-219 two-tenant battery.';
