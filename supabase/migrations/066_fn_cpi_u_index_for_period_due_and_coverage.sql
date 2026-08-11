-- ============================================================================
-- Migration: pfin.fn_cpi_u_index_for_period — RETURN SHAPE CHANGE, 6 -> 8
--   columns. Adds `period_was_due boolean` (Option A) and `coverage_through
--   date` (rider A'), F/CTO-ratified 2026-08-10 against the Architect ratify
--   gate opened after the PRD §2.4.4 amendment landed.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): ADR-011 Decision 1 — this helper
--   is the read path by which a recorded non-publication reaches an
--   inflation-adjusted financial figure. Unlike `065` (comment-only), this is
--   REAL DDL: it DROPS and RECREATES a function on that path.
--
-- ----------------------------------------------------------------------------
-- ⚠ WITHDRAWN-QUOTE GUARD — READ BEFORE ANY AUTOMATED SWEEP OF THIS FILE.
--   Several strings in this header are quoted PRECISELY BECAUSE THEY ARE FALSE.
--   They are the SUBJECT of a withdrawal, not support for an argument: their
--   falsity is the assertion, not the premise. They are kept so a reader who
--   remembers the old text learns it CHANGED rather than doubting their memory.
--   >> EVERY LINE CARRYING SUCH A QUOTATION IS PREFIXED `WQ>`. <<
--   THE MARKER REPEATS ON EVERY LINE OF A QUOTATION rather than heading it once,
--   and that redundancy is the entire point: a marker that a trim, a `grep -A1`,
--   a partial-block copy or a context boundary can separate from its quote is a
--   conditional waiting to be RE-ARMED BY TRANSCRIPTION. Inseparable beats
--   nearby. If you add a withdrawn quote here, mark every line of it.
--   >> A STALENESS SWEEP MUST EXCLUDE `WQ>` LINES. << They will match a search
--   for stale state claims — that is exactly what they are, quoted as such.
--   "Correcting" one RESTORES the false text this file exists to retire, and it
--   would look like a cleanup. The precedent is DECISIONS.md's ratified rule
--   that an artifact which NAMES a drift class by its proper name is not itself
--   drift and is left alone; only an artifact that ASSERTS can drift.
--
-- ----------------------------------------------------------------------------
-- Numbering: 066 follows 065 (the cpi_u comment corrections). Next free number
--   taken AT AUTHORING TIME by reading the tree, never reserved ahead.
--   ⚠ THE READING IS BRANCH-DEPENDENT, AND THIS FILE IS ITS OWN WORKED EXAMPLE.
--   AT AUTHORING TIME `065` was not yet on `main`, so a tree read at `main`
--   reported 064 as the maximum and would have handed the next author 065 — a
--   silent collision with an open branch. This file was therefore authored on a
--   branch STACKED on `065`, so its number was read from a tree that contained
--   it.
--   ⚠ THIS PARAGRAPH PREVIOUSLY STATED THAT IN THE PRESENT TENSE:
--   WQ> "`065` is not yet on `main`, so a tree read at `main` reports 064 as
--   WQ>  the maximum"
--   — which
--   went FALSE the moment `065` merged, and would then have misdirected the very
--   numbering author it exists to protect. Restated above as the dated event it
--   always was. This is the SAME DRIFT CLASS `065`'s own correction (C) fixed in
--   `063`: a merge-order state claim, true when written, false on merge —
--   committed one file later by the author who wrote the rule.
--   THE STANDING RULE, which depends on none of that history: a migration number
--   MUST be read from a tree that can actually see its neighbours, and MUST NOT
--   be reserved ahead. The 058->059 slip is the precedent.
--   Depends on: 001 (pfin schema) + 053 (cpi_u_index) + 063
--   (cpi_u_nonpublication) + 064 (the function this replaces). Order-DEPENDENT.
--
-- ----------------------------------------------------------------------------
-- ⚠ WHY A DROP AND NOT A REPLACE — and the two things the DROP TAKES WITH IT.
--   PostgreSQL cannot `create or replace` a function across a CHANGED RETURN
--   TYPE (`cannot change return type of existing function`), and `returns table`
--   IS the return type. A column-set change is therefore necessarily
--   drop-and-recreate, which is why the ratify gate flagged this as a ONE-WAY
--   DOOR on TIMING rather than on difficulty: at zero consumers it costs one
--   migration; after the first consumer ships it is a contract change against
--   live code.
--   >> DROP DESTROYS THE FUNCTION'S ACL AND ITS CATALOG COMMENT. << Both are
--   pg_proc-attached and neither survives. This migration therefore RE-ISSUES:
--     · `revoke execute ... from public` + `grant execute ... to authenticated`
--       — NOT boilerplate. Omitting the revoke would leave EXECUTE granted to
--       PUBLIC by Postgres default, silently WIDENING access on a function
--       feeding financial figures, and it would look exactly like success.
--     · the full `comment on function`.
--   ⚠ THIS IS THE FAIL-OPEN EDGE OF THIS MIGRATION, stated in the header and in
--   the commit subject per the fail-closed-removal rule: between the DROP and
--   the REVOKE the default grant is PUBLIC. Both statements are in the same
--   migration and migrations run in a transaction, so the window is not
--   observable — but a future author who splits this file, or who copies the
--   drop-and-recreate shape without the revoke, reopens it. The revoke is
--   load-bearing, not tidy.
--   No CASCADE, deliberately: if anything has come to depend on this function,
--   the DROP must FAIL LOUD rather than quietly removing the dependent.
--
--   ⚠⚠ AND THE DROP TAKES `065`'s FUNCTION COMMENT WITH IT — stated here because
--   it is a REVIEW FACT, not a defect. `065` was reviewed on its own. (That
--   clause previously read
--   WQ> "and Sec is reviewing `065` separately"
--   — a review-STATE claim that went false when `065` merged. Same drift class
--   as the numbering paragraph above.)
--   `065` is a comment-only migration that corrects, among other things, this
--   function's catalog comment. This migration DROPS the function, so on a full
--   replay `065`'s function-comment correction is applied and then SUPERSEDED
--   moments later by the comment at the foot of this file. That is not wasted
--   work and `065` must NOT be trimmed on account of it. THE REASONS BELOW ARE
--   LABELLED, NOT COUNTED.
--   ⚠ This sentence previously ended
--   WQ> "for two reasons:"
--   — above a list of THREE, which this PR then extended again. A tally sitting
--   beside the list it counts, in the header whose whole subject is text that
--   went false. Same lesson as the sites-named-not-counted note further down,
--   landing TWICE IN ONE COMMIT by the same author: A LABEL IS A STABLE
--   REFERENCE AND A COUNT IS A MAINTENANCE OBLIGATION. The labels (i)/(ii)/(iii)
--   are load-bearing and MUST NOT be stripped — they are how a reader looks an
--   instance up. Only the tally goes. Do not re-count; stop counting:
--     (i)  `065`'s TABLE-comment corrections (the reconciliation formula, the
--          "catches both obstacles" over-claim, and the merge-order state claim)
--          are on pfin.cpi_u_nonpublication and are NOT touched by this
--          migration at all; and
--     (ii) a deployment that stops between `065` and `066` — or a `065` that
--          merges while this branch is still in review — must still hold a TRUE
--          function comment rather than the false one `064` shipped; and
--    (iii) ⚠ REVERT-INDEPENDENCE, which is the LOAD-BEARING reason and is
--          stronger than (ii). Sec's, recorded because it beats the ground this
--          block originally gave. `065` and `066` are SEPARATELY REVERTABLE, and
--          a return-type change on a function feeding financial figures is a
--          plausible thing to back out. If `066` were reverted and `065` had been
--          trimmed on the argument that `066` supersedes it, `064`'s FALSE
--          comment would be RESURRECTED — because the only correction of it
--          would have left with `066`. (ii) describes a transient window a `\d+`
--          reader might catch; (iii) describes a durable regression that a
--          revert would introduce silently.
--   The comment at the foot of this file is authored fresh for the EIGHT-column
--   shape. It SUPERSEDES `065`'s correction with a later-true statement, and in
--   particular does NOT resurrect the `064` claim `065` corrected. (This
--   previously read that it
--   WQ> "carries `065`'s correction forward"
--   — wrong in a
--   way that fed the same misreading (iii) invites: "carries forward" implies
--   `065`'s text survives somewhere, and the DROP guarantees it does not.)
--
--   ⚠⚠⚠ THE DUAL (iii) OMITS — (iii)'s PROTECTION IS REAL IN ONE REVERT MODEL
--   AND ABSENT IN THE OTHER, AND (iii) DOES NOT SAY WHICH IT MEANS. (iii) is
--   preserved above and is NOT withdrawn; it is QUALIFIED here, so a reader who
--   remembers it alone learns that it acquired a scope it did not originally
--   state. (iii) argues that keeping `065` is what stops `064`'s FALSE comment
--   being resurrected by a revert of this migration. Which is true depends
--   entirely on what "revert" means:
--     · CHAIN REMOVAL — this file is REMOVED from the tree and the chain is
--       applied from `001` onto a database that has therefore never run it.
--       `064` runs, `065` runs after it, and `065`'s six-column correction is
--       the live comment on the six-column function. (iii) holds EXACTLY as
--       written: had `065` been trimmed, `064`'s false text would stand.
--       ⚠ THIS IS NOT A CI-ONLY CURIOSITY, AND CALLING IT ONE WOULD BE THE
--       ERROR. V1 is GREENFIELD (ADR-021), so V1's FIRST DEPLOY applies the
--       chain from `001` onto a database that has run nothing. Chain-from-`001`
--       is therefore a real deploy path and not a lab exercise, and removing a
--       file from that chain is a real revert. (Stated as the FIRST DEPLOY — a
--       fixed event — rather than as
--       WQ> "the deploy target stands up from scratch",
--       which was a present-tense state claim of exactly the kind corrected in
--       the numbering paragraph above: it goes false once V1 is deployed, after
--       which the selector below is what governs.)
--     · FORWARD-REVERT — a NEW migration, applied to a database on which THIS
--       one has ALREADY RUN. Under it (iii)'s protection DOES NOT EXIST. The
--       `drop function` below has ALREADY destroyed the comment `065` set, and
--       `065` has already run — a migration does not run twice. A forward-revert
--       therefore inherits NOTHING from `065`. Nor is `064`'s false text
--       resurrected: the recreated function is left with NO COMMENT AT ALL,
--       which is a quieter failure than a false one and not a better one.
--   ⚠ WHICH MECHANISM APPLIES IS FIXED BY THE TARGET'S STATE, NOT BY PREFERENCE:
--   chain removal is available only where this file has NOT been applied,
--   forward-revert only where it HAS. Neither reverter gets to choose.
--
--   STANDING REQUIREMENT — AND IT IS A PROPERTY OF `DROP`, NOT OF "CHANGING THIS
--   FUNCTION". Any migration that DROPS this function MUST ISSUE ITS OWN
--   `comment on function` AND ITS OWN `revoke` + `grant`, leaning on neither
--   `065` nor this file.
--   ⚠ THE CONVERSE IS EQUALLY LOAD-BEARING AND MUST NOT BE LOST IN THE WARNING:
--   `create or replace function`, and `alter function ... rename to` /
--   `... set schema`, PRESERVE BOTH THE COMMENT AND THE ACL — the pg_proc OID
--   SURVIVES those, and pg_description and proacl are keyed to it. ONLY THE DROP
--   DESTROYS THEM. Writing this as "any change to this function loses the
--   comment" would be an OVERCLAIM that trains the next author to distrust
--   `create or replace` — the cheap, safe, OID-preserving path — and to reach
--   instead for a drop-and-recreate that drags this entire hazard along with it.
--   What forces the DROP here is narrow and specific: a change to the RETURN
--   TYPE (`returns table` IS the return type) or to the argument types. A change
--   confined to the BODY is a `create or replace` and loses nothing.
--   None of this is a new rule, and the mechanism is NOT newly stated — this
--   file already states it at the ">> DROP DESTROYS THE FUNCTION'S ACL AND ITS
--   CATALOG COMMENT. <<" block above, again at the `065` clause above, and again
--   in the note at the `drop function` itself. (Sites named, not counted: a
--   tally of them would be a maintenance obligation this sentence cannot
--   honour, and it would go stale the first time anyone states the mechanism a
--   further time.) What was missing, and is added here, is the OBLIGATION THE
--   MECHANISM TRANSFERS TO THE NEXT AUTHOR — and that (iii) must not be read as
--   an exception to it.
--   ⚠ SCOPE OF THE PAIR NAMED ABOVE, so it is not read as an exhaustive account
--   of everything a DROP can destroy: it is scoped to what THIS drop
--   demonstrably destroys and what this file therefore re-issues — the ACL and
--   the catalog comment. An author dropping some OTHER function must ask the
--   question again for that function rather than inherit this answer.
--   ⚠⚠ TWO THINGS, NOT THREE — READ THIS BEFORE COUNTING. The `revoke`/`grant`
--   statements above and "the ACL" ARE THE SAME OBJECT, named by its STATEMENT
--   and by its STORAGE (pg_proc.proacl). They are not two separate casualties of
--   the DROP. The DROP takes exactly two things: THE ACL AND THE CATALOG
--   COMMENT — which is what the header's opening block says in as many words.
--   ⚠ NAMING ONE OBJECT TWICE IN TWO VOCABULARIES IS WHAT LETS AN ENUMERATION
--   READ AS COMPLETE WHILE A MEMBER IS MISSING, and this file is the worked
--   example: the catalog comment at the foot names the grant by its statement
--   ("RE-ISSUES THE GRANT") and again by its storage ("the DROP takes the ACL
--   with it"), and omits the comment entirely — which is precisely WHY it reads
--   as though it covers everything. A reviewer of this very file then counted
--   three casualties from that construction and nearly corrected the correct
--   tally in the opening block to match. THE MISCOUNT IS A PROPERTY OF THE
--   PROSE, NOT OF THE READER.
--
-- ----------------------------------------------------------------------------
-- WHAT FORCED THIS — the gap was in marker-versus-nothing, not in the signals.
--   PRD §2.4.4 (F/CTO-ratified 2026-08-10) discharged the PM half of ADR-049
--   Decision 5 and routed the remainder here in its own words: "how these
--   product distinctions map onto that helper's result shape is
--   architecture-layer detail carried there, not pinned in this story."
--   `064`'s six columns already carried §2.4.4's two required independent
--   signals. What they did NOT carry was the predicate that gates the marker:
--     §2.4.4, verbatim — "The informational marker therefore fires only where
--     the period was actually due, and never where the absence is explained by
--     the edge of coverage alone."
--     (§2.4.4 emphasises "was actually due" and leaves the rest plain. Quoted
--     flat here: this file cannot render emphasis, so ADDING capitals under the
--     label "verbatim" would attribute stress to the source that it does not
--     carry. Where the source's emphasis matters, it is stated OUT OF BAND like
--     this rather than smuggled into the quotation.)
--   Under the six-column shape a consumer had to compute that as
--   `is_carried AND gap_class in ('recorded_nonpublication','unrecorded_gap')`
--   — i.e. it had to know WHICH MEMBERS MEAN DUE. That mapping IS the gap
--   policy, and ADR-049 Decision 4's standing requirement forbids re-deriving
--   the gap policy in a consumer, in as many words.
--   ⚠ AND IT IS THE DEFAULT PATH, NOT AN EDGE CASE — which is why this was worth
--   a drop-and-recreate. CPI-U publishes one to two months in arrears (§2.4.4:
--   "a permanent property of the deflator — not an event, not a defect"), so
--   EVERY current-month inflation-adjusted figure lands is_carried = true with
--   gap_class = 'beyond_coverage'. A consumer reading is_carried as the marker
--   trigger marks EVERY FIGURE, ALWAYS — precisely what §2.4.4 rules out: "A
--   marker present on every figure at all times would carry no information and
--   would dilute the actionable tier beside it."
--
-- ----------------------------------------------------------------------------
-- COLUMN TRACE — each new column to the §2.4.4 sentence that requires it. Read
--   §2.4.4 verbatim; the traces below are pointers, not substitutes.
--
--   period_was_due boolean  ->  §2.4.4 "The publication lag is disclosed, not
--     marked": the marker "fires only where the period was actually due, and
--     never where the absence is explained by the edge of coverage alone."
--     ⚠ TRACED HONESTLY: this column is NOT one of the two signals enumerated
--     in §2.4.4's "What the user must be able to distinguish" paragraph. It
--     QUALIFIES the marker-versus-nothing decision that signal (2) owns. Stated
--     this way so nobody later "finds" it in the two-signal list and concludes
--     the list has three members.
--     TRUE  for 'published' / 'recorded_nonpublication' / 'unrecorded_gap'.
--     FALSE for 'before_coverage' / 'beyond_coverage' (both edges, and the
--           empty store, where no coverage window exists to be inside).
--     The consumer's whole marker rule becomes `is_carried AND period_was_due`,
--     with NO member-set knowledge. A future gap_class member cannot silently
--     change any consumer's marker behaviour, because the new branch MUST set
--     period_was_due explicitly — the classification chain below assigns both in
--     the SAME if/elsif, which is what keeps them from drifting apart.
--
--   coverage_through date  ->  §2.4.4, same paragraph: the trailing edge "is
--     instead disclosed once, statically, as part of each surface's stated
--     inflation-adjustment basis, and that disclosure names the period it runs
--     through (in the spirit of 'real terms, CPI-U through March 2026') rather
--     than describing the basis as current. Naming the period is load-bearing,
--     not cosmetic."
--     (§2.4.4 emphasises "once, statically" and "names the period it runs
--     through"; the load-bearing sentence is PLAIN in the source. An earlier
--     draft here had that exactly inverted — capitalising the plain sentence
--     while flattening the two emphasised phrases, AND dropping "instead" with
--     no ellipsis. Quoted flat, emphasis noted out of band. The ONLY remaining
--     departure from the source bytes: the nested quotation marks around 'real
--     terms, CPI-U through March 2026' are single here because they cannot nest
--     inside a double-quoted span — stated rather than left for the next
--     mechanical check to re-flag.)
--     = the latest period present in cpi_u_index; NULL on an empty store, where
--     there is no basis to name and saying so is the honest answer.
--     ⚠ IT IS A PROPERTY OF THE STORE, NOT OF THE REQUESTED PERIOD — the only
--     column here that is. It rides on this function because every consumer
--     that needs the basis line is already calling it, and a separate one-row
--     helper would be a second round trip for one scalar. Recorded because the
--     asymmetry is real and a later reader will notice it.
--     ⚠ WHY IT COULD NOT BE LEFT DERIVABLE: under `064` the trailing edge was
--     recoverable as carried_from ONLY on the 'beyond_coverage' path — NOT on
--     'published', which is the ordinary case. A basis line that can only be
--     rendered when the data is stale is not a basis line.
--
--   ⚠ CONTROL-FLOW CONSEQUENCE, stated because it is the one behavioural change
--   to an existing path: the coverage extent is now resolved BEFORE the
--   exact-print branch instead of after it, because 'published' must also report
--   coverage_through. Cost is one min/max aggregate over an indexed primary key
--   on a path that previously skipped it. The exact-print RESULT is unchanged in
--   all six pre-existing columns.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE TWO SIGNALS STAY UNCOLLAPSED — the constraint §2.4.4 states twice.
--   "The rendering above requires exactly two independent signals to reach the
--   presentation layer, and they must not be collapsed into one" — and, on the
--   uncomputable case, "The trigger is whether a value could be resolved, not
--   why the period is absent — the two are independent, and a reason-for-absence
--   must never be read as a proxy for the carry outcome."
--   (Both quoted flat. §2.4.4 carries NO emphasis on the first; on the second it
--   emphasises the WHOLE opening clause — "The trigger is whether a value could
--   be resolved, not why the period is absent" — and leaves the proxy warning
--   plain. ⚠ An earlier draft here inverted precisely that: it reduced the
--   emphasised clause to a lone capitalised "NOT" and then capitalised the plain
--   clause in full. That is the more damaging direction, because the clause the
--   source stresses IS the marker rule an implementer has to get right, and
--   moving stress off it moves attention off it.)
--     Signal (1) — could a value be resolved: `cpi_value IS NULL`. Directly the
--       fact itself, not a proxy for it.
--     Signal (2) — exact-or-carried + which period + from where + cause on
--       record: is_carried / cpi_period / carried_from / nonpublication_on_record
--       (marker-versus-nothing additionally gated by period_was_due).
--   >> period_was_due IS NOT A PROXY FOR is_carried, AND THE PROOF IS THAT THEY
--   DISAGREE ON A REACHABLE ROW. << A period recorded in cpi_u_nonpublication
--   with NOTHING at or before it returns period_was_due = TRUE (the source spoke
--   about it, so it was due) with is_carried = FALSE and cpi_value = NULL. That
--   is §2.4.4's "Uncomputable is not stale" case: it renders as unavailable with
--   a reason, NOT as a marked number. A consumer that reads either column as
--   standing in for the other gets this row wrong, in a way no value assertion
--   would catch — the figure is absent either way; only the RENDERING differs.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE C4 PROVISIONALITY MARKER IS CLEARED HERE — an Architect ruling, with
--   the reason recorded rather than the clearance asserted. Sec raised C4;
--   Sec should see the disposition.
--   WHAT C4 SAID: the return shape — column set AND gap_class member set alike —
--   was, per ADR-049 D4's closing sentence quoted here at source capitalization,
--   "the implementing PR's call pending the product ruling; the composite return
--   and the non-silence it enforces are not."
--   ⚠ QUOTED FLAT DELIBERATELY: `064` renders this same sentence with "PENDING
--   THE PRODUCT RULING" upper-cased for emphasis (⚠ SWEEP GUARD: that
--   capitalized string is HELD OUT — it NAMES the erroneous rendering in order to
--   retract it, and must not be swept with text that COMMITS it), and that
--   emphasis is NOT in
--   ADR-049. Harmless there, but this file is the one a reader will now cite, and
--   a quotation that adds stress the source did not place is a quotation that has
--   been edited. Re-read D4 rather than either rendering.
--   BOTH INPUTS IT NAMED ARE NOW DISCHARGED: the PM half (ADR-049 Decision 5 /
--   the PRD §2.4.4 amendment) was F/CTO-ratified 2026-08-10, and the Architect
--   half (this shape) was F/CTO-ratified at the ratify gate that produced this
--   migration. Nothing pending remains for the caveat to name.
--   WHY CLEARING IS CORRECT RATHER THAN MERELY PERMITTED — the argument that
--   kept it alive last time now runs the other way. Keeping a provisionality
--   marker that names no live dependency does not preserve caution: it ANCHORS a
--   reader while making the surface FEEL HANDLED, which is the same failure mode
--   as a self-aware stale count. Worse, on THIS function it invites the exact
--   harm D4 exists to prevent — a consumer who reads the shape as still
--   negotiable has every reason to re-derive the gap policy locally rather than
--   inherit it.
--   >> WHAT REPLACES IT IS NOT SILENCE. << A ratified contract's successor to
--   "provisional" is a CHANGE-CONTROL REQUIREMENT, stated as a standing rule
--   rather than a state claim: THE RETURN SHAPE IS F/CTO-RATIFIED; ANY CHANGE TO
--   THE COLUMN SET OR THE gap_class MEMBER SET REQUIRES Sec RE-REVIEW + F/CTO
--   RATIFY + AN ADR-049 AMENDMENT, AND — because of the DROP above — A NEW
--   MIGRATION THAT RE-ISSUES BOTH THE GRANT AND THE CATALOG COMMENT. That is
--   durable; a marker that merely records something as pending was not.
--   ⚠ THE COMMENT WAS ADDED TO THIS ENUMERATION LATER — IT PREVIOUSLY READ
--   WQ> "A NEW MIGRATION THAT RE-ISSUES THE GRANT"
--   AND STOPPED THERE. Recorded because
--   of HOW it failed, which is reusable: an omission in PROSE reads as prose,
--   but AN OMISSION IN A LIST READS AS A COMPLETE LIST. An author working this
--   sentence as a checklist could tick Sec, F/CTO, the ADR amendment and the
--   grant — and ship with no comment, having followed every instruction given.
--   See the STANDING REQUIREMENT block above for why the obligation attaches to
--   the DROP itself and not to "changing this function".
--   ⚠⚠ KNOWN-INCOMPLETE COPY, MARKED RATHER THAN LEFT SILENT: this same
--   enumeration also appears in the CATALOG comment at the foot of this file,
--   and THERE IT STILL NAMES ONLY THE GRANT. It is not corrected here because a
--   catalog string HAS a database representation and can change only by issuing
--   new SQL — which this correction deliberately does not do. THIS CORRECTION IS
--   OWED A DEDICATED COMMENT-ONLY MIGRATION under the full `052` shape
--   (regenerate-and-diff, anchor asserted to match EXACTLY ONCE, containment
--   proof, parse-in-rollback, render-verify via obj_description).
--   ⚠ STATED AS AN OBLIGATION, NOT AS A PLAN, AND THE DIFFERENCE IS THE POINT —
--   the shape `065` uses for its transport contract test: an obligation is TRUE
--   THE MOMENT IT IS WRITTEN and stays true until DISCHARGED, and it still reads
--   as UNMET WORK if nothing satisfies it. A plan does not: any construction
--   asserting that the correction ALREADY HAS a vehicle — a present-tense
--   passive naming one, a scheduling verb, an ordering clause — asserts a
--   mechanism that may not exist. (Those forms are DESCRIBED rather than quoted
--   here, deliberately: a sweep hunting stale plan-claims scans the prose
--   written ABOUT plan-claims too, and that prose is the densest concentration
--   of exactly the tokens it hunts. Measured during this correction — a grep for
--   the forbidden forms matched only this paragraph.)
--   A CORRECTNESS CLAIM MUST NOT FORWARD-REFERENCE THE
--   MECHANISM THAT MAKES IT TRUE — `065`'s own rule, which `065` honoured by
--   DELIBERATELY REFUSING to name the branch that would lift the transport drop.
--   Carrying NO migration number, NO issue reference and NO ordering claim is
--   the same decision as that one, not three separate ones: a number would be
--   reserved ahead of the tree, and an issue reference inside a merged PR closes
--   the very tracker that holds this work open.
--   ⚠ THIS PARAGRAPH PREVIOUSLY SAID THE CORRECTION WOULD
--   WQ> "ride along with the next migration that touches this function's
--   WQ>  comment for an independent reason."
--   THAT DISPOSITION IS WITHDRAWN, and the circularity note below is the reason:
--   A TRIGGER THAT MAY BE THE FAILURE ITSELF IS NOT A SCHEDULE. Recorded rather
--   than quietly swapped, because of WHAT it was — an OPEN QUESTION WRITTEN DOWN
--   AS A PLAN, asserted from the vantage current at authoring time. That is the
--   same authoring habit the STANDING REQUIREMENT block above exists to
--   document, committed in the text documenting it: THE HABIT SURVIVED BEING
--   NAMED, IN THE PARAGRAPH NAMING IT. Naming a habit does not cure it; the
--   check is whether a claim is stated from a vantage other readers share.
--   ⚠ THE CIRCULARITY IS REAL AND IS STATED RATHER THAN HOPED AWAY: the next
--   migration to touch this function's comment for an independent reason is most
--   likely authored by the very person this sentence warns — which is precisely
--   WHY the correction is SCHEDULED as its own migration rather than left
--   opportunistic.
--   THIS HEADER IS THEREFORE THE LOAD-BEARING SITE AND THE CATALOG COMPLETION IS
--   HYGIENE — which is the right way round, because this sentence is an
--   INSTRUCTION TO A MIGRATION AUTHOR, who necessarily has the repo in front of
--   them (migrations live in code, not the dashboard). It is not a fact about
--   the data, so the `\d+`-reader-with-no-repo argument that justifies the
--   comment-only migration vehicle does not reach it. (An earlier draft quoted "pending a
--   ruling" as if from ADR-049. That string is in no ADR — D4 reads "pending the
--   product ruling" — so the quotation marks dressed a paraphrase as a citation.
--   De-quoted.)
--   ⚠ DECISION 3's SKETCHED CALENDAR MECHANISM WAS DELIBERATELY NOT TAKEN, and
--   that is a DISCHARGE, not an omission. D3 sketches the due-period bound as a
--   comparison against `date_trunc('month', <server today>) - interval '1 month'`
--   "or a stricter bound". period_was_due takes the stricter bound and takes it
--   DATA-DERIVED: bracketed by prints on both sides, consulting NO clock — no
--   current_date, no now(), no fn_server_today(). D3 itself warns that the lag
--   constant "must be verified against BLS's published release schedule at
--   implementation, not assumed", and a bound needing no constant cannot be got
--   wrong by guessing one. ⚠ Recorded because otherwise D3 reads as an UNMET
--   instruction, and the natural way for a later reader to "discharge" it is to
--   add the very constant it cautioned against.
--   ⚠ AND THE RESIDUE THAT IS **STILL OPEN** IS NOT THIS ONE — recorded so it is
--   not mistaken for a survival of C4. PRD Appendix B §2.1 flag (d) names TWO
--   Architect residues: (1) mapping the helper's result shape onto §2.4.4's
--   user-visible distinctions — CLOSED by this migration; and (2) the per-surface
--   signal THREADING shared with §2.4.4's existing marker-threading flag — STILL
--   OPEN. Residue (2) is a presentation-layer threading question: how these
--   columns reach each consuming surface. It does NOT reopen the signature, and
--   a reader who conflates the two will re-mark this shape provisional for a
--   reason that was never about the shape.
--   UNCHANGED AND NOT REOPENED, so the clearance is not read as license: the
--   composite/row return and the non-silence it enforces (ADR-049 D4 LOCKS
--   these — they were never the implementing PR's call), and the C1
--   both-coverage-edges-bounded correction, which is independent of any product
--   ruling. The gap_class MEMBER SET is unchanged by this migration; only the
--   column set moves.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. Unchanged from `064` and re-stated because a DROP means
--   the posture is re-declared from scratch rather than inherited: the helper
--   reads two GLOBAL public reference tables whose SELECT policies are
--   `using (true)`, so it needs no elevated privilege and INVOKER gives the
--   caller exactly the rows their own policies already permit. This migration
--   authors NO SECURITY DEFINER function, so the ADR-011 Decision 9 DEFINER
--   allowlist is UNCHANGED by it (+0). Stated as a DELTA, not as a level: the
--   allowlist's size is read live from Decision 9, never copied into a file that
--   cannot maintain it.
--   ADR-023 Step 0: both tables are PURE-GLOBAL, so reads execute under
--   `authenticated` — this helper composes with that rule rather than excepting
--   it. The `authenticated`-only EXECUTE grant is carried forward DELIBERATELY;
--   see the grant block at the foot for the measured reasoning, which the DROP
--   does not invalidate.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — ADR-011 Decision 4 is LINKED, not restated;
--   read verbatim live before drafting this file. This migration is not the
--   canonical anchor, so the catalogued numbered list is deliberately NOT
--   reproduced and NO count appears — a derived surface that copies a count
--   acquires a maintenance obligation it will not honour.)
--   (i)   Instance-numbering: catalogues NO new §10 instance and reorders none.
--         Ledger DELTA = 0.
--   (ii)  Layer-attribution: a DB-LAYER read helper over two global public
--         reference tables. NOT the code-layer SUPABASE_SERVICE_ROLE_KEY
--         allowlist grep fence, NOT the PDF-worker container credential audit,
--         NOT the app->worker admission network/config surface. It touches no
--         credential, no container and no endpoint. ⚠ The function-level EXECUTE
--         grant re-issued below is a DB-LAYER ACL, and re-issuing an identical
--         ACL after a DROP moves no layer attribution.
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated (Path B).
--   DE-CONFLATION GUARD: no FK-shaped column, no credential-presence surface, no
--   admission endpoint — none is a §10 catalogued instance.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS; neither
--   is reconciled to the other here, and neither should be "tidied" to match.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — family UNCHANGED (+0). This migration creates no table
--   and no column on any table, hence no FK-shaped reference column; and both
--   tables it reads are GLOBAL, so there is no tenant boundary to bypass. Both
--   ADR-049 Decision 1 grounds carry through unchanged. The family's size is
--   read live from Decision 3's body — this file carries no tally.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (C3 / ADR-029 / 025) — NOT APPLICABLE. This migration
--   introduces no table. The two tables read are global shared-read (exclusion
--   reason (i)), as `063` records for itself.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (all confirmed FLAT, stated as deltas): §10 catalogued
--   instances +0 · SECURITY DEFINER allowlist +0 · ADR-011 Decision 3 family +0
--   · SD matrix — NO expansion (reads public reference data only). Sec review is
--   MANDATORY notwithstanding the flat ledgers: ADR-011 Decision 1, the read
--   path into an inflation-adjusted financial figure, and a DROP + regrant on
--   that path.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_cpi_u_index_for_period(p_period date)
--     returns table (cpi_period date, cpi_value numeric, is_carried boolean,
--                    carried_from date, gap_class text,
--                    nonpublication_on_record boolean, period_was_due boolean,
--                    coverage_through date)
--     — resolves the CPI-U index level to use for p_period, and says how it was
--       resolved. Exactly ONE row, always. SECURITY INVOKER, STABLE,
--       set search_path = ''.
--     RETURN SHAPE IS RATIFIED, NOT PROVISIONAL (see the C4 block above).
--       Changing the column set or the gap_class member set requires Sec
--       re-review + F/CTO ratify + an ADR-049 amendment + a new migration that
--       re-issues the grant.
--     p_period is NORMALIZED to first-of-month (the CPI grain) and the
--       normalized value is RETURNED as cpi_period, so a caller passing a
--       mid-month date is TOLD which period answered rather than having to know.
--       NULL p_period raises — an empty result would be indistinguishable from
--       "no CPI data", which on a financial surface is the silence Decision 4
--       forbids.
--     cpi_value is NULL only when nothing at or before the period is present in
--       cpi_u_index (no carry source). It is NEVER a fabricated zero.
--     THE CONSUMER'S RENDERING RULE, stated once here so it is not re-derived:
--       cpi_value IS NULL                -> render UNAVAILABLE with a reason
--                                           (§2.4.4 "Uncomputable is not stale");
--       is_carried AND period_was_due    -> INFORMATIONAL marker, asserting
--                                           carried-ness and the span
--                                           (cpi_period from carried_from), with
--                                           a CAUSE clause iff
--                                           nonpublication_on_record;
--       otherwise                        -> plain exact figure, no marker.
--       Basis line on every path: "CPI-U through {coverage_through}".
--     ⚠ gap_class IS OPERATOR-AXIS, NOT USER-AXIS. 'unrecorded_gap' remains its
--       ONLY alarm class, and per §2.4.4 that alarm is operator-side ONLY: "An
--       absence held to be operationally alarming is still not alarming to the
--       user ... on the user-facing axis it renders exactly as a recorded
--       non-publication does, minus the cause clause. The user is not the
--       operator, even when V1 ships to one person." A consumer MUST NOT branch
--       user-visible tiering on gap_class; that is what period_was_due and
--       nonpublication_on_record are for.
--   ⚠ AN INHERITED PRECONDITION, recorded because all branches depend on it and
--     none of them can check it: 053 documents cpi_period as first-of-month but
--     does NOT enforce it (063 does, for its own rows). A mis-keyed 053 row such
--     as 2025-10-15 would be INVISIBLE to the exact-print branch (no equality
--     match), yet SELECTED as a carry source, and it would MOVE THE COVERAGE
--     EDGE — so one malformed row can change another period's answer, its
--     classification, its period_was_due AND the coverage_through every caller
--     is shown, all at once. Fixing 053 is a separate vehicle (its CHECK cannot
--     be added by editing a merged file); this helper's correctness is
--     conditional on that grain holding.
--   Security-load-bearing edges: INVOKER over two `using (true)` global tables —
--     NO tenant isolation surface is crossed and no tenant predicate exists to
--     get wrong; `set search_path = ''` fences search_path injection, and every
--     object reference below is schema-qualified accordingly; the row return is
--     itself security-load-bearing in the FINANCIAL-CORRECTNESS sense (it is the
--     mechanism that prevents a silently-carried CPI value from entering a
--     real-terms figure); the p_period NULL raise is fail-loud, not fail-quiet;
--     and the re-issued REVOKE is what keeps the DROP from widening EXECUTE to
--     PUBLIC.
--   ⚠ WHAT THIS FUNCTION DELIBERATELY DOES NOT DO — recorded so no consumer
--     infers it: it does NOT detect a stalled ingest (coverage_through is a
--     DISCLOSURE, not a freshness monitor — §2.4.4 is explicit that the dated
--     basis line "is not ingest-freshness monitoring and does not substitute for
--     it"); it does NOT separate "our ingest dropped it" from "backfill never
--     covered the span" (ADR-049 Decision 2 keeps (c)/(d) collapsed, and §2.4.4
--     rules the user must NOT be asked to distinguish them); it does NOT decide
--     what the USER sees — it supplies the signals the presentation layer
--     renders; and it does NOT compute an inflation adjustment — it supplies the
--     input to one.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- DROP — required, not stylistic: the return type is changing and PostgreSQL
-- cannot `create or replace` across that. NO CASCADE: if a dependent has
-- appeared, this must fail loud rather than silently remove it. `if exists`
-- keeps a replay onto a tree without 064 from erroring; it is not a claim that
-- the function might legitimately be absent.
-- ⚠ THE ACL AND THE CATALOG COMMENT DIE WITH THE FUNCTION. Both are re-issued
-- below. The REVOKE in particular is load-bearing — without it, Postgres's
-- default EXECUTE-to-PUBLIC silently reinstates a wider grant than 064 had.
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_cpi_u_index_for_period(date);

-- ----------------------------------------------------------------------------
-- pfin.fn_cpi_u_index_for_period — the ONE place the CPI-U gap policy lives.
-- See the header for the full contract; the notes inline cover only what is not
-- obvious from the code itself.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_cpi_u_index_for_period(p_period date)
returns table (
  cpi_period                date,
  cpi_value                 numeric,
  is_carried                boolean,
  carried_from              date,
  gap_class                 text,
  nonpublication_on_record  boolean,
  period_was_due            boolean,
  coverage_through          date
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
-- The RETURNS TABLE output names (cpi_period / cpi_value) collide with column
-- names on the tables being read. Every column reference below is table-
-- qualified, and this directive makes the resolution explicit rather than
-- incidental: an ambiguous bare name resolves to the COLUMN, never to the output
-- variable. Without it a future unqualified reference would fail at runtime with
-- "column reference is ambiguous" instead of doing the obvious thing. The p_*
-- parameter and the v_* locals match no column name, so they are unaffected —
-- including the two added here, whose output names (period_was_due,
-- coverage_through) also collide with nothing on either table.
#variable_conflict use_column
declare
  v_period   date;     -- p_period normalized to the CPI grain (first-of-month)
  v_from     date;     -- period the carried value came from; NULL if none exists
  v_val      numeric;  -- the carried value itself
  v_min      date;     -- earliest period present in cpi_u_index (leading edge)
  v_max      date;     -- latest   period present in cpi_u_index (trailing edge)
  v_class    text;     -- resolved gap_class
  v_recorded boolean;  -- a non-publication record exists for this period
  v_due      boolean;  -- the period was demonstrably DUE (marker gate)
begin
  -- FAIL LOUD on a missing period. Deliberately NOT a silent empty result: an
  -- empty set is indistinguishable from "there is no CPI data", and this
  -- function feeds inflation-adjusted figures where that ambiguity is exactly
  -- the silence ADR-049 Decision 4 exists to prevent. Same fail-loud principle
  -- as 062's granularity guard and 054's immutability fences.
  if p_period is null then
    raise exception
      'pfin.fn_cpi_u_index_for_period: p_period is required (got NULL). A CPI-U lookup with no period is a caller error, not an empty series.';
  end if;

  -- Normalize to the CPI grain. NON-SILENT: v_period is RETURNED as cpi_period
  -- in every branch below, so a caller passing a mid-month date is told which
  -- period answered.
  -- ⚠ The ::timestamp cast is LOAD-BEARING: that type is zone-free, so nothing
  -- in this function is evaluated in the session TimeZone. The zone-AWARE
  -- variant would put the resolved period at the mercy of the session zone
  -- (ADR-044's hazard). Do not "simplify" the cast away.
  v_period := date_trunc('month', p_period::timestamp)::date;

  -- ---------------------------------------------------------------------
  -- (0) RECORD LOOKUP — resolved ONCE, BEFORE the exact-print branch, and
  -- returned on EVERY path.
  -- ⚠ THIS ORDERING IS THE WHOLE POINT (Sec joint-review note N1). 063 exists
  -- so that a period present in BOTH tables reads as "unpublished when we
  -- looked, published later" — that IS the audit trail, in 063's own words. If
  -- the record were only consulted on the absent path, that case would
  -- short-circuit to 'published' at branch (1) and the audit trail would be
  -- INVISIBLE through the one helper consumers are permitted to use, while they
  -- are simultaneously forbidden from hand-rolling the join. The table would be
  -- preserving evidence nothing could read.
  -- Note this column is NOT derivable from gap_class: on the absent paths the
  -- two agree, but for a LATER-PUBLISHED period gap_class is 'published' and
  -- only this flag carries the history. That non-derivability is why it is a
  -- column and not a comment (ADR-011 Decision 4 derive-by-looking test).
  -- ---------------------------------------------------------------------
  v_recorded := exists (
    select 1 from pfin.cpi_u_nonpublication n
    where n.cpi_period = v_period
  );

  -- ---------------------------------------------------------------------
  -- (0.5) COVERAGE EXTENT — BOTH EDGES, and now resolved BEFORE the exact-print
  -- branch rather than after it. ⚠ THAT MOVE IS THE ONE CONTROL-FLOW CHANGE IN
  -- THIS MIGRATION, and its reason is coverage_through: the 'published' path
  -- must report the trailing edge too, because the §2.4.4 basis line is rendered
  -- on surfaces whose data is NOT stale — a basis line that only exists when the
  -- series has a gap is not a basis line. Cost: one min/max aggregate over an
  -- indexed primary key on a path that previously skipped it.
  -- The data-derived bound replaces a calendar lag constant; see the
  -- coverage-edge reasoning carried in 064 for why this is the "stricter bound"
  -- ADR-049 Decision 3 permits, and for the stalled-ingest cost it accepts. No
  -- "today" is consulted anywhere in this function.
  -- ⚠ BOTH edges, not just the trailing one (Sec joint-review C1, preserved
  -- here unchanged — it is a correctness fix independent of any product ruling).
  -- ---------------------------------------------------------------------
  select min(c.cpi_period), max(c.cpi_period) into v_min, v_max
  from pfin.cpi_u_index c;

  -- ---------------------------------------------------------------------
  -- (1) EXACT PRINT. The period has its own row — nothing is carried and no
  -- classification is needed. carried_from is set to the period itself rather
  -- than NULL so that "where did this value come from?" has the same answer
  -- shape in every row a consumer receives.
  -- period_was_due is TRUE here and the reason is not circular: the print
  -- EXISTS, which is the strongest possible evidence the period was due. It
  -- gates no marker on this path (is_carried is false), but it must be
  -- internally consistent, because a consumer reading period_was_due alone must
  -- never conclude a published period was somehow not due.
  -- ---------------------------------------------------------------------
  return query
  select v_period, c.cpi_value, false, v_period, 'published'::text, v_recorded,
         true, v_max
  from pfin.cpi_u_index c
  where c.cpi_period = v_period;

  if found then
    return;
  end if;

  -- ---------------------------------------------------------------------
  -- (2) ABSENT. Resolve the carry source: the latest print STRICTLY BEFORE the
  -- period (equality was already excluded by (1)). This is the 019 LOCF idiom —
  -- order-desc-limit-1 over the at-or-before window — applied once, here, so no
  -- consumer re-derives it.
  -- Both v_from and v_val stay NULL when nothing precedes the period; that is
  -- the "no carry source" case, and it is reported, never papered over with a
  -- zero. 053 declares cpi_value NOT NULL, so a found row always carries a
  -- value: v_from IS NOT NULL is the authoritative "we carried something" test.
  -- ---------------------------------------------------------------------
  select c.cpi_period, c.cpi_value into v_from, v_val
  from pfin.cpi_u_index c
  where c.cpi_period < v_period
  order by c.cpi_period desc
  limit 1;

  -- ---------------------------------------------------------------------
  -- (3) CLASSIFY THE ABSENCE. Order matters, and every branch is positive.
  -- The RECORD is consulted first, so a period the source published valueless
  -- is named as such even at an edge, where the extent test alone could not
  -- tell. Then the two edges are excluded explicitly, which leaves
  -- 'unrecorded_gap' meaning STRICTLY INTERIOR — bracketed on BOTH sides by
  -- prints we hold. That is what makes it an alarm worth having: a period that
  -- was demonstrably due, and is unexplained.
  -- ⚠ v_due IS ASSIGNED IN THIS SAME CHAIN, DELIBERATELY. Keeping the class and
  -- the due-ness in one if/elsif is what stops them drifting apart: a future
  -- author adding a member cannot add it without answering "was it due?", and
  -- an answer they must supply is worth more than a mapping table they must
  -- remember to update. Do NOT refactor v_due into a derived expression over
  -- v_class — that reintroduces exactly the member-set knowledge this column
  -- exists to remove from consumers, one layer down.
  -- ---------------------------------------------------------------------
  if v_recorded then
    -- The source published this period with no usable value. It was DUE — the
    -- source spoke about it, which is positive evidence, not an inference.
    v_class := 'recorded_nonpublication';
    v_due   := true;
  elsif v_max is null then
    -- The store is EMPTY: there is no coverage window at all, so no period can
    -- be shown to have been due. Lands in the not-an-alarm class deliberately —
    -- an empty store must not report every period in history as a gap.
    v_class := 'beyond_coverage';
    v_due   := false;
  elsif v_period < v_min then
    -- Earlier than anything we hold. States (c)/(d) collapsed — most plausibly
    -- "backfill never covered this span". NOT an alarm, and NOT due.
    v_class := 'before_coverage';
    v_due   := false;
  elsif v_period > v_max then
    -- Later than anything we hold: the ordinary publication-lag case. NOT an
    -- alarm, and NOT due — this is the branch that keeps the informational
    -- marker off every current-month figure (§2.4.4, publication lag disclosed
    -- rather than marked).
    v_class := 'beyond_coverage';
    v_due   := false;
  else
    -- Strictly inside the window and absent: bracketed by prints on both sides,
    -- so it was due, and nothing explains it.
    v_class := 'unrecorded_gap';
    v_due   := true;
  end if;

  -- ---------------------------------------------------------------------
  -- (4) EMIT. Exactly one row, always — a consumer never has to distinguish
  -- "the function returned nothing" from "the answer is nothing".
  -- ---------------------------------------------------------------------
  return query
  select v_period, v_val, (v_from is not null), v_from, v_class, v_recorded,
         v_due, v_max;
end;
$$;

-- ⚠ RE-ISSUED AFTER THE DROP, NOT DECORATIVE. `drop function` removes the
-- pg_proc row and its ACL with it, and Postgres grants EXECUTE to PUBLIC by
-- default on a freshly created function. Without the REVOKE below this
-- migration would SILENTLY WIDEN access on a function feeding financial
-- figures, and it would look exactly like a successful no-op. The grant that
-- follows is then the whole of the access rather than an addition on top of an
-- implicit one (054's discipline). anon is denied earlier by schema USAGE, but
-- that is a second fence, not this one.
--
-- ⚠ THE `authenticated`-ONLY GRANT IS DELIBERATE AND IS CARRIED FORWARD
-- UNCHANGED FROM 064. service_role is NOT granted EXECUTE, and that is a
-- decision, not an oversight — recorded here because the next person to hit
-- `permission denied for function` will otherwise read silence as a gap and
-- "fix" it by widening the grant.
--
--   WHY. Both tables this helper reads are PURE-GLOBAL (SELECT policy
--   `using (true)`, no tenant discrimination), and ADR-023's ETL read-role
--   amendment Step 0 rules that pure-global reads execute under `authenticated`.
--   Granting service_role EXECUTE would open a SECOND read path for exactly the
--   data that rule assigns to the first, turning a file that COMPOSES with Step 0
--   into one that excepts it. It would also buy nothing: service_role's
--   distinguishing power is BYPASSRLS, and there is no RLS restriction here to
--   bypass — `using (true)` already admits every authenticated caller.
--
--   AND NO CALLER IS SHUT OUT BY IT:
--     · App server routes read under `authenticated` per ADR-023 — covered.
--     · The worker identity is a member of BOTH `authenticated` and
--       `service_role` (granted at 055), so it reaches this helper by taking the
--       former. >> IT IS NOINHERIT: it must EXPLICITLY `set role authenticated`;
--       privileges do not arrive implicitly. <<
--       Measured end-to-end 2026-08-10 against the 064 shape, and the DROP does
--       not change it: under the worker identity, `set role service_role` then
--       calling this function gives `permission denied for FUNCTION`;
--       `set role authenticated` then calling it SUCCEEDS. >> THE FIX IS
--       `set role authenticated`, NOT WIDENING THIS GRANT. <<
--       ⚠ TWO DIFFERENT ERRORS LEAD HERE, and only one of them names this
--       function. In BARE worker-identity context (NOINHERIT, no SET ROLE at
--       all) the failure arrives EARLIER and reads `permission denied for SCHEMA
--       pfin`, since schema USAGE is checked before the function ACL. Same
--       cause, same fix, different message.
--     · The 063 writer does not need this helper at all: it WRITES
--       non-publication records; it does not read carry-forward or gap
--       classification.
--
--   ⚠ IF a future caller genuinely needs service_role EXECUTE, that is a GRANT
--   CHANGE ON A FUNCTION FEEDING FINANCIAL FIGURES and routes to Sec re-review.
--   It does not ride along with an unrelated migration.
revoke execute on function pfin.fn_cpi_u_index_for_period(date) from public;
grant execute on function pfin.fn_cpi_u_index_for_period(date) to authenticated;

comment on function pfin.fn_cpi_u_index_for_period(date) is
  'THE single CPI-U consumption helper (ADR-049 Decision 4). Resolves the CPI-U '
  'index level to use for a period AND says how it was resolved. SECURITY INVOKER '
  '(ADR-011 Lock 11 read-composition; not a DEFINER allowlist entry — this '
  'migration adds none), STABLE, set search_path = ''''. Reads pfin.cpi_u_index '
  '(053) and pfin.cpi_u_nonpublication (063), both global public reference tables '
  'with `using (true)` SELECT policies, so no tenant boundary is crossed. '
  'Returns EXACTLY ONE ROW: (cpi_period, cpi_value, is_carried, carried_from, '
  'gap_class, nonpublication_on_record, period_was_due, coverage_through). '
  'p_period is normalized to first-of-month and the normalized value is returned, '
  'so a caller passing a mid-month date is told which period answered; NULL '
  'p_period raises rather than returning an empty set. '
  'STANDING REQUIREMENT — a consumer needing a CPI-U level calls this function; '
  'the carry-forward and gap-classification policy MUST NOT be re-derived inline '
  'in a consumer (the 019 eod_price LOCF-in-one-helper precedent). '
  'STANDING REQUIREMENT — the return MUST stay a ROW and MUST NOT be narrowed to '
  'a bare scalar: CPI-U is supposed to be monthly-complete, so carrying a value '
  'forward silently understates inflation, and the row return is the '
  'by-construction mechanism forcing a consumer to project carried-ness away '
  'deliberately and visibly rather than merely forget it. '
  'THE RETURN SHAPE IS F/CTO-RATIFIED (2026-08-10), NOT PROVISIONAL — the earlier '
  'C4 provisionality caveat named two pending inputs and BOTH are discharged (the '
  'PRD 2.4.4 product ruling, and the architecture-layer mapping this shape '
  'realizes). STANDING REQUIREMENT — any change to the column set or the '
  'gap_class member set requires Sec re-review, F/CTO ratify, an ADR-049 '
  'amendment, and a new migration that RE-ISSUES THE GRANT, because a return-type '
  'change cannot be a create-or-replace and the DROP takes the ACL with it. '
  'THE CONSUMER RENDERING RULE, so it is not re-derived: cpi_value IS NULL renders '
  'the figure UNAVAILABLE with a reason; is_carried AND period_was_due renders an '
  'INFORMATIONAL marker asserting carried-ness and the span (cpi_period from '
  'carried_from), with a cause clause IFF nonpublication_on_record; otherwise the '
  'plain exact figure with no marker. The basis line on every path names '
  'coverage_through. '
  'period_was_due is TRUE for ''published'' / ''recorded_nonpublication'' / '
  '''unrecorded_gap'' and FALSE at BOTH coverage edges and on an empty store. It '
  'exists so a consumer never encodes which gap_class members mean "due" — that '
  'mapping IS the gap policy, and PRD 2.4.4 requires the informational marker to '
  'fire only where the period was actually due and never where the absence is '
  'explained by the edge of coverage alone. Without it every current-month figure '
  'would be marked, since CPI-U publishes one to two months in arrears. '
  '⚠ period_was_due is NOT a proxy for is_carried and they DISAGREE on a reachable '
  'row: a recorded non-publication with nothing at or before it returns '
  'period_was_due TRUE, is_carried FALSE, cpi_value NULL — rendered unavailable, '
  'not marked. PRD 2.4.4: the two signals must not be collapsed, and a '
  'reason-for-absence must never be read as a proxy for the carry outcome. '
  'coverage_through is the LATEST period present in pfin.cpi_u_index (NULL on an '
  'empty store) — a property of the STORE, not of the requested period, and the '
  'only such column here. It carries PRD 2.4.4''s dated basis line, which must '
  'name the period it runs through rather than describe the basis as current. It '
  'is a DISCLOSURE, NOT a freshness monitor: 2.4.4 is explicit that the dated '
  'basis line is not ingest-freshness monitoring and does not substitute for it. '
  'gap_class is a TEXT set (unchanged): ''published'' (own print) / '
  '''recorded_nonpublication'' (source published the period with no usable value; '
  'ADR-049 Decision 2 state (a), the only positively-recorded absence) / '
  '''unrecorded_gap'' (absent and STRICTLY INTERIOR to the coverage window, so it '
  'was demonstrably due and nothing explains it — THE ONLY ALARM CLASS) / '
  '''before_coverage'' (absent and earlier than anything the store holds) / '
  '''beyond_coverage'' (absent and later than anything the store holds; also the '
  'empty-store case) — the last two are NOT alarms. ⚠ gap_class is the OPERATOR '
  'axis, not the user axis: per PRD 2.4.4 an absence held to be operationally '
  'alarming is still not alarming to the USER, and renders exactly as a recorded '
  'non-publication does minus the cause clause. Do NOT branch user-visible '
  'tiering on gap_class — that is what period_was_due and nonpublication_on_record '
  'are for. gap_class reports the ABSENCE REASON and is ORTHOGONAL to the carry '
  'outcome: cpi_value is NULL when no period at or before the requested one '
  'exists, never a fabricated zero. '
  'nonpublication_on_record is TRUE iff a non-publication record exists for the '
  'period REGARDLESS of whether a print now exists — it is the only way the '
  '"unpublished when we looked, published later" audit trail is readable through '
  'this helper, and it is NOT derivable from gap_class, which reads ''published'' '
  'in exactly that case. '
  'BOUNDED BY CONSTRUCTION — the due-period test is DATA-DERIVED (is the period '
  'bracketed by prints on BOTH sides?), not calendar-derived, which is the '
  'stricter bound ADR-049 Decision 3 permits; it consults no clock, so it is '
  'outside ADR-044''s two-clock hazard. ITS COST: it CANNOT detect a stalled '
  'ingest — a dead ETL yields ''beyond_coverage'' indefinitely, indistinguishable '
  'from "not yet published". Ingest-freshness monitoring is NOT this function''s '
  'job and must not be inferred from its output. '
  '⚠ EXECUTE IS GRANTED TO authenticated ONLY, DELIBERATELY — service_role is not '
  'granted EXECUTE and that is a decision, not an oversight. Both tables read here '
  'are pure-global, and ADR-023 Step 0 assigns pure-global reads to authenticated; '
  'a service_role grant would open a second read path for the same data and would '
  'buy nothing, since service_role''s distinguishing power is BYPASSRLS and '
  '`using (true)` leaves no RLS restriction to bypass. A privileged-context caller '
  'must SET ROLE authenticated — note the worker identity is NOINHERIT, so it must '
  'do so EXPLICITLY. Measured end-to-end 2026-08-10: under that identity, '
  'service_role context gives `permission denied for function`, and bare context '
  'with no SET ROLE fails EARLIER still with `permission denied for schema pfin` '
  '(schema USAGE is checked before the function ACL) — two different messages, '
  'same cause, same fix. SET ROLE authenticated then succeeds. THE FIX FOR EITHER '
  'ERROR IS SET ROLE, NOT WIDENING THIS GRANT. Widening it is a grant change on a '
  'function feeding financial figures and requires Sec re-review.';
