-- ============================================================================
-- Migration: 102 — pfin.account.tax_jurisdiction designation + the YTD-Paid read
--   primitive + ONE shared tax-authority predicate + the §2.1.5 leaf-set exclusion.
--   Phase 6 Build Loop, V1.4 (§2.5.3.c) — Linear SELF-267. Realizes F/CTO Gate B
--   Option A (2026-06-03) and F/CTO ruling R3 / E-2 option (A) (2026-09-03), whose
--   riders 0b, 0c, 1, 3 and 7 each land here. Closes no SD/RT; extends no fence
--   family. apply-migration applied.
--
-- Numbering: 102 follows 099 on this branch. `100` and `101` are held by sibling
--   V1.4 branches authored in parallel; the gap is deliberate, not a missing file.
--   Depends on: 003 (pfin.account — the table altered, its direct-owner RLS, and the
--   users_id isolation anchor), 025 (the aal2 step-up conjunct already carried by
--   account_select / account_insert / account_update), 049 + 051 (the §2.1.5 leaf
--   substrate and the composition this replaces), 056 (the per-account native cash
--   roll-forward the YTD-Paid primitive composes on), 079 (the STABLE pin on
--   fn_nav_composition, which CREATE OR REPLACE would otherwise silently reset).
--   Nothing downstream of 099 depends on 102.
--
-- ----------------------------------------------------------------------------
-- WHAT THIS IS, IN ONE PARAGRAPH. A user may designate one account per tax
--   authority as that authority's ledger. Money sent to the IRS or the FTB is a
--   §2.4.3 manual transfer that lands on the designated ledger as cash, so the
--   ledger's balance IS the year-to-date amount paid. That same fact is why the
--   designated ledgers must leave the §2.1.5 composition's leaf set: the payment
--   is already reflected by the obligation falling, and counting the cash too
--   would raise NAV by money that is gone. ONE designation, TWO consumers.
--
-- ⚠ THE DEFAULT STATE IS THE HAZARD, AND IT IS WHAT THE WALK MUST OBSERVE
--   (R3 rider 0b). tax_jurisdiction is NULLABLE and user-set, so an UNMARKED
--   IRS account is simultaneously EXCLUDED from YTD Paid (Funds Due overstated)
--   and INCLUDED in the buildup (NAV overstated) — two halves failing in
--   OPPOSITE directions from one omission, and neither figure visibly
--   contradicts the other. A walk that only exercises a MARKED account cannot
--   observe this at all. The walk is: mark the account, and both figures move
--   together. On the §2.1.5 surface the exclusion's rendering (SELF-268 AC 10a)
--   is the only observer an unmarked ledger has.
--
-- ⚠ WHAT THIS MIGRATION MAKES DIVERGE, STATED BECAUSE IT LOOKS LIKE A DEFECT.
--   pfin.fn_nav_composition(as_of)->>'nav' NO LONGER EQUALS
--   pfin.fn_compute_nav(as_of, true). 051's own comment asserted that identity;
--   this migration rewrites it (R3 rider 3) rather than leaving a comment the
--   same statement falsifies. fn_compute_nav is NOT touched: it keeps its gross
--   definition, keeps writing nav_daily, and the checkpointed series stays the
--   gross pre-tax definition permanently (R3). The two figures differ by exactly
--   the designated ledgers' balances, and while no account is designated they
--   are equal — which is why the existing equality legs stay green on their own
--   fixtures rather than being retired: 051's own (F1) / (F2)
--   (`nav == fn_compute_nav(as_of, TRUE)` and `… FALSE`) and self227's (12).
--   self228's (D2) is affected by the same fixture condition but asserts
--   agreement with an independently-summed household total, not equality with
--   fn_compute_nav. Every one of them holds only while no account in its fixture
--   is designated; a fixture that designates one must re-derive them, not delete
--   them.
--
-- ----------------------------------------------------------------------------
-- ONE EXTRACTED PREDICATE, ZERO READ-PATH COPIES — R3 rider 1 / ADR-063
--   Decision item 2.
--   `tax_jurisdiction is not null` has exactly ONE EXECUTABLE HOME,
--   pfin.fn_tax_authority_ledgers(), and BOTH read consumers call it: the
--   YTD-Paid primitive drives off it, and fn_nav_composition anti-joins against
--   it.
--   ⚠ WHY A SECOND COPY IS THE DEFECT ADR-063 NAMES: four restatements of one
--   predicate drift independently and the drift is INVISIBLE, because each copy
--   is locally plausible. Here the two copies would drift in opposite directions
--   — a ledger counted by one consumer and not the other is precisely the
--   rider-0b failure with no omission to point at. The seam's answer is stated
--   once and consuming surfaces CITE it.
--   ⚠ The shape was chosen for this: a set-returning helper, not a scalar
--   `fn_is_tax_authority_ledger(account_id) boolean`. With the scalar, the
--   YTD-Paid primitive would still have to write `tax_jurisdiction = p_jurisdiction`
--   beside it — the boolean call would be a redundant guard and the jurisdiction
--   test would be the second realization of the same idea. The set form lets the
--   jurisdiction filter be a REFINEMENT of the shared set rather than a parallel
--   statement of it.
--   ⚠ ONE further textual occurrence exists and CANNOT be routed through the
--   helper: the partial unique index's own `where tax_jurisdiction is not null`
--   predicate below. An index predicate must be IMMUTABLE, and a STABLE
--   set-returning function is not indexable — so this is a constraint clause
--   that the extraction discipline structurally cannot reach, not a read-path
--   copy that was missed. Stated so a later reader does not "fix" it. ⚠ The
--   residual is real: if the shared predicate ever NARROWS (say, to exclude
--   closed accounts), the index will NOT follow and nothing will say so — the
--   two must be changed together by hand.
--   ⚠ CITATION NOTE: ADR-063 numbers its four protocols as ITEMS inside a single
--   `### Decision` block, so *"ADR-063 Decision 2"* — the form the SELF-267 AC and
--   R3 rider 1 both use — is not a well-formed pointer. Read as Decision ITEM 2
--   (the seam-inventory protocol, whose load-bearing half is the extraction
--   discipline). ADR-066's cross-references already record the malformation.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER, for either new function.
--   pfin.fn_tax_authority_ledgers() reads pfin.account only, under the caller's
--   own direct-owner RLS plus the 025 aal2 conjunct. pfin.fn_ytd_paid_per_jurisdiction
--   composes that helper with 056 (itself INVOKER over account / account_trans /
--   account_balance_checkpoint). Neither needs elevated privilege and DEFINER
--   would BREAK tenant isolation on both — the helper would enumerate every
--   tenant's designated ledgers and the primitive would sum every tenant's
--   payments. INVOKER is load-bearing, not a default taken for tidiness. A
--   cross-tenant caller sees no account rows, so the helper returns the empty
--   set: the exclusion becomes a no-op (nothing to exclude, and there is nothing
--   in the leaf set either) and YTD Paid returns NULL. Fails closed both ways.
--   `set search_path = ''` is the privesc fence on all three functions; every
--   reference is fully qualified. → SECURITY DEFINER allowlist UNCHANGED
--   (ADR-011 Decision 9, read live at authoring; no entry added, none re-posed).
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 — STATED PER COLUMN, NOT PER MIGRATION (AC 7, per 085's
--   rule; 084's Amendment 1 records the check not actually having been run on the
--   second table of a pair).
--   `pfin.account.tax_jurisdiction` — ENUM column. No FK, no relation reference,
--   no id array, no snapshot of another table's key. There is NO REFERENCED ROW
--   and therefore no tenant to match: the cross-tenant FK-bypass family is not
--   engaged and NO matched-tenant validation is owed. This is the whole check,
--   run and recorded, not assumed. The Decision 3 family is FLAT across this
--   migration (its body read live at authoring; no instance added, re-targeted,
--   or dropped, and no label moves).
--   ⚠ The partial unique index below is NOT a Decision 3 fence and must not be
--   read as one — it constrains a tenant's OWN rows against each other, which is
--   a different question from whether a reference crosses a tenant boundary.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   list is LINKED, NOT RESTATED, and NO COUNT is carried here. Decision 4 read
--   VERBATIM and LIVE before drafting, 2026-09-03.)
--   (i)   Instance-numbering: no catalogued instance is added, removed, reordered
--         or renumbered by this migration.
--   (ii)  Layer-attribution: nothing moves. What lands here is one nullable enum
--         column, one partial unique index, and two authenticated-tier INVOKER
--         read helpers reached over PostgREST — no service_role grant, no
--         credential, no container, no admission or network-exposure surface. No
--         surface becomes "four-layer"; the three-class composition is untouched.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, never restated; 102 is
--         not the canonical anchor and carries no enumeration of it.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are
--   NOT reconciled here.
--   LOCK 14 NOTE: the designation is a user-facing direct DB write, so it joins
--   the Lock 14 CLASS — and class membership is not a catalogued instance
--   (ADR-042's own Consequences ruling for the 058 fences). Its Lock 14 layers
--   are the app-layer validation (Backend/Frontend `.strict()` + the enum union)
--   and the RLS WITH CHECK it already inherits from 003+025. Decision 4's
--   numeric-input adversarial battery is INAPPLICABLE to an enum column rather
--   than absent, and the partial unique index below is a correctness fence
--   rather than one of Decision 4's enumerated Lock 14 components — named here
--   so it is not counted as one.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW-MANDATORY (Sec veto surface) — a money figure, a new column on a
--   central tenant table, and a new read primitive on the NAV path. Sec
--   joint-review is required even though there is no DEFINER entry, no Decision 3
--   extension and no §10 ledger change. Light loop: NO (ADR-066 Decision 1 (a)).
--   QA pgTAP two-tenant pairing ships same-PR (SECURITY §4.5); the SELF-269 AC-7
--   cross-tenant jurisdiction pen-test is written against THIS signature. The
--   live walk precedes the Sec spawn (ADR-063 Decision item 4).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.tax_jurisdiction_enum — ('irs','ftb'). The V1 value set. A THIRD value is
--     an additive ALTER TYPE, not a migration of stored data.
--   pfin.account.tax_jurisdiction pfin.tax_jurisdiction_enum NULL — the designation.
--     NULL means "not a tax-authority ledger". It does NOT mean "unknown".
--     Written by an ordinary UPDATE under account_update; NOT a creation parameter
--     (see the AC-8 note below).
--   account_tax_jurisdiction_uniq — UNIQUE (users_id, tax_jurisdiction)
--     WHERE tax_jurisdiction IS NOT NULL. One account per authority per user.
--   pfin.fn_tax_authority_ledgers() RETURNS TABLE (account_id bigint,
--     tax_jurisdiction pfin.tax_jurisdiction_enum) — SECURITY INVOKER, STABLE,
--     search_path=''. The caller's designated ledgers. THE single realization of
--     `tax_jurisdiction is not null`.
--   pfin.fn_ytd_paid_per_jurisdiction(p_as_of date,
--     p_jurisdiction pfin.tax_jurisdiction_enum) RETURNS numeric — SECURITY
--     INVOKER, STABLE, search_path=''. The designated ledger's native cash balance
--     as of p_as_of. NULL when the caller has designated no ledger for that
--     authority — see the NULL note on the function's own comment.
--   pfin.fn_nav_composition(p_as_of date default current_date) RETURNS jsonb —
--     signature and JSONB shape UNCHANGED; leaf set now excludes designated
--     ledgers; volatility re-declared STABLE explicitly (R3 rider 7).
--   Security-load-bearing edges: INVOKER on all three (cross-tenant caller → empty
--     helper set → NULL YTD Paid and an inert exclusion, fails closed); EXECUTE
--     revoked from PUBLIC and granted to authenticated only on all three; the
--     designation carries no tenant parameter anywhere (Sec D-2 (i)) and the
--     jurisdiction parameter is ENUM-typed, not text (Sec D-2 (ii)).
--
-- ⚠ NO TENANT PARAMETER, AND THE TYPING IS A CONTROL (Sec D-2). No shipped pfin
--   reader takes a tenant parameter; a client-supplied tenant on a SECURITY
--   INVOKER function is either IGNORED — a lie in the signature — or USED in the
--   predicate, which is an ownership-forge vector. And with a `text` jurisdiction
--   parameter an unknown value returns zero rows and a silent $0 YTD Paid, which
--   OVERSTATES Funds Due; with the enum it is a type error at the boundary. That
--   is the RT-25 parameter-bypass shape arriving on a new surface.
--
-- ⚠ AC-8 CREATION-PATH PAIRING CHECK — RUN AND RECORDED, NOT ASSUMED. The LIVE
--   body of pfin.fn_create_manual_account is 087 (013 → 048 → 087; reading 013
--   would show a sub_cat_id column that 048 dropped). Its account INSERT column
--   list is (name, account_type, scope, tax_treatment). tax_jurisdiction is added
--   NULLABLE with no NOT NULL and no DEFAULT, so that INSERT continues to
--   succeed unchanged and the created account is simply undesignated. 087's
--   SIGNATURE IS NOT CHANGED — adding a parameter would break other files'
--   regprocedure assertions, and the designation is set by a subsequent UPDATE
--   under account_update exactly as every other editable account attribute is.
--   The §2.4.2 form may still present the field. (The recorded result of running
--   this check is in the PR/report, not asserted here.)
--
-- ⚠ AAL2 BACKSTOP (ADR-029 / 025) — NO NEW OBLIGATION, stated so the absence is
--   not read as an omission. 025's C3 standing obligation attaches to a new
--   SENSITIVE TENANT-OWNED TABLE. 102 creates no table; it adds a column to
--   pfin.account, whose account_select / account_insert / account_update policies
--   already carry the per-user-conditional aal2 conjunct (025). A column inherits
--   its table's policies, so the designation is aal2-fenced on both read and
--   write from the moment it exists.
--
-- ----------------------------------------------------------------------------
-- VERIFICATION (run before push; results in the report, not asserted here):
--   clean-apply of this file onto a template clone of the 001..099 chain (never
--   the Supabase CLI's destructive local-reset path — it wipes the F/CTO's local
--   test data); the two-accounts-one-jurisdiction rejection; the YTD-Paid ==
--   fn_account_cash_as_of equality; the measured fn_nav_composition /
--   fn_compute_nav DIVERGENCE with a ledger designated and its REVERSION with the
--   designation NULL (rider 0b's default state, observed rather than argued); and
--   the existing pgTAP batteries that touch fn_nav_composition, run with pg_prove.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) The jurisdiction vocabulary.
--
-- An ENUM rather than a text CHECK because the parameter type of the read
-- primitive is the control (Sec D-2 (ii)) — a CHECK constrains a column but
-- gives a function parameter nothing to be typed as, and the whole point is that
-- an unknown jurisdiction is rejected at the call boundary rather than returning
-- a silent zero. Guarded rather than `if not exists` because CREATE TYPE has no
-- such clause; the guard is a catalog lookup, fully qualified.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_type t
    join pg_catalog.pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'pfin' and t.typname = 'tax_jurisdiction_enum'
  ) then
    create type pfin.tax_jurisdiction_enum as enum ('irs', 'ftb');
  end if;
end
$$;

comment on type pfin.tax_jurisdiction_enum is
  'Tax-authority vocabulary for pfin.account.tax_jurisdiction (SELF-267; F/CTO Gate B Option A, 2026-06-03). V1 values: ''irs'' (US Federal) and ''ftb'' (California Franchise Tax Board). The TYPE — not a text CHECK — because pfin.fn_ytd_paid_per_jurisdiction takes this as its parameter type, so an unrecognised authority is a TYPE ERROR at the call boundary rather than a zero-row read returning a silent $0 YTD Paid, which would OVERSTATE Funds Due (Sec D-2 (ii); the RT-25 parameter-bypass shape). Adding a further authority is an additive ALTER TYPE ... ADD VALUE and migrates no stored data. Product copy calls this a "tax authority"; the schema identifier is tax_jurisdiction, and the two are deliberately allowed to differ.';

-- ----------------------------------------------------------------------------
-- (2) The designation column on pfin.account.
--
-- NULLABLE with no DEFAULT. That is the whole write contract: an account is
-- undesignated until a user says otherwise, by UPDATE, under account_update
-- (003 + the 025 aal2 conjunct). fn_create_manual_account (087) is NOT touched.
-- ----------------------------------------------------------------------------
alter table pfin.account
  add column if not exists tax_jurisdiction pfin.tax_jurisdiction_enum null;

comment on column pfin.account.tax_jurisdiction is
  'Marks this account as a tax authority''s ledger (SELF-267 / PRD §2.5.3.c; F/CTO Gate B Option A). NULL MEANS "NOT A TAX-AUTHORITY LEDGER" — it does NOT mean "unknown", and no code may treat it as a to-be-filled-in state. Set by the user on the §2.4.2 account form at creation or edit; the WRITE PATH IS AN ORDINARY UPDATE under account_update, not a creation parameter — pfin.fn_create_manual_account''s signature is deliberately unchanged, because adding a parameter to it breaks other objects'' regprocedure assertions. Two consumers, one designation: pfin.fn_ytd_paid_per_jurisdiction sums the designated ledger''s cash balance as YTD Paid, and pfin.fn_nav_composition EXCLUDES designated ledgers from its §2.1.5 leaf set (a payment already lands as cash here while the obligation falls by the same amount, so counting both would raise NAV by money that is gone; F/CTO ruling R3, E-2 option A). BOTH consumers reach this column through pfin.fn_tax_authority_ledgers(), which is the single home of the `is not null` predicate — do not write that predicate anywhere else. ⚠ THE DEFAULT STATE FAILS IN TWO DIRECTIONS AT ONCE: an unmarked tax-authority account is excluded from YTD Paid (Funds Due reads HIGH) and included in the NAV buildup (NAV reads HIGH), and neither figure contradicts the other. At most one account per user may carry any given value — enforced by the partial unique index account_tax_jurisdiction_uniq, because a second ledger with the same value would be summed twice into YTD Paid. Tenant isolation is pfin.account''s own users_id = auth.uid() RLS plus the ADR-029/025 aal2 conjunct; this column adds no reference and therefore carries no ADR-011 Decision 3 matched-tenant obligation.';

-- ----------------------------------------------------------------------------
-- (3) One account per authority per user — R3 rider 0c, a DEFAULT-AND-NOTIFY
--     item (team-lead; reversal window open until the V1.4 amendment batch
--     merges), raised by Sec as F-1's live caveat X-1.
--
-- Nothing in a nullable column prevents two accounts marked 'irs'. The YTD-Paid
-- primitive sums over ALL designated ledgers for the jurisdiction, so a second
-- one DOUBLE-COUNTS YTD Paid -> Funds Due understated -> Realized understated ->
-- NAV overstated: a chain that is well-formed at every step and wrong at every
-- step, with no error anywhere in it. A UNIQUE CONSTRAINT cannot be partial, so
-- this is a partial unique INDEX; the WHERE clause is what leaves the undesignated
-- majority unconstrained (many NULLs per user are legal and ordinary).
--
-- The alternative — declaring multi-account-per-jurisdiction legal and summing
-- deliberately — was NOT taken. It also matches the PRD §2.4.2 text ("one account
-- per authority per user") landed in the same close-out.
-- ----------------------------------------------------------------------------
create unique index if not exists account_tax_jurisdiction_uniq
  on pfin.account (users_id, tax_jurisdiction)
  where tax_jurisdiction is not null;

comment on index pfin.account_tax_jurisdiction_uniq is
  'One account per tax authority per user (SELF-267 AC 3; F/CTO ruling R3 rider 0c, taken under the ADR-063 default-and-notify protocol). PARTIAL: undesignated accounts are unconstrained, and a user may hold any number of them. This is a CORRECTNESS fence, not a modelling preference — pfin.fn_ytd_paid_per_jurisdiction sums over every designated ledger for the authority, so a second one marked the same way double-counts YTD Paid, which understates Funds Due, which understates Realized Tax Liability, which OVERSTATES NAV, with no error raised at any step. Not an ADR-011 Decision 3 fence: it constrains one tenant''s own rows against each other and involves no cross-tenant reference.';

-- ----------------------------------------------------------------------------
-- (4) THE SINGLE PREDICATE HOME — R3 rider 1 / ADR-063 Decision item 2.
--
-- `tax_jurisdiction is not null` appears in exactly one executable place in the
-- schema, and it is here. Both consumers below call this function; neither
-- restates the predicate.
--
-- ⚠ WHY A SECOND COPY IS THE DEFECT, and not merely untidy: each copy is
-- LOCALLY PLAUSIBLE, so drift between them raises no error and shows up only as
-- two money figures that disagree with no omission to point at. The exclusion
-- and the YTD-Paid sum fail in OPPOSITE directions from the same disagreement
-- (rider 0b), so a reader inspecting either one alone finds nothing wrong.
--
-- TOTALITY IS NOT CLAIMED HERE, deliberately, and the contrast with 056 is the
-- point: 056 returns one row per visible account ALWAYS, because its callers
-- would silently lose accounts otherwise. This function returns one row per
-- DESIGNATED ledger and NO row for an undesignated account — that is its whole
-- meaning, and an empty result is the ordinary state for a user who has
-- designated nothing. Callers must therefore decide what an EMPTY result means
-- for them; both callers below state their answer explicitly.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_tax_authority_ledgers()
returns table (account_id bigint, tax_jurisdiction pfin.tax_jurisdiction_enum)
language sql
security invoker
stable
set search_path = ''
as $$
  select a.account_id, a.tax_jurisdiction
  from pfin.account a
  where a.tax_jurisdiction is not null;
$$;

revoke execute on function pfin.fn_tax_authority_ledgers() from public;
grant execute on function pfin.fn_tax_authority_ledgers() to authenticated;

comment on function pfin.fn_tax_authority_ledgers() is
  'SECURITY INVOKER — the caller''s tax-authority-designated account ledgers (SELF-267; Lock 11 read-composition). THIS FUNCTION IS THE SINGLE HOME OF THE PREDICATE `pfin.account.tax_jurisdiction is not null`, and it exists for that reason rather than for convenience: F/CTO ruling R3 rider 1 requires the designation to be stated ONCE and CITED, per ADR-063''s extraction discipline (numbered as Decision ITEM 2, inside that ADR''s single Decision block). Its consumers are pfin.fn_ytd_paid_per_jurisdiction and pfin.fn_nav_composition, and ANY further consumer of the designation MUST call this function rather than restate the predicate. ⚠ DO NOT WRITE THAT PREDICATE ANYWHERE ELSE. A second copy is locally plausible wherever it is written, so drift between the copies raises no error — and because those consumers fail in OPPOSITE directions (a ledger missed by the exclusion overstates NAV; a ledger missed by the sum overstates Funds Due), inspecting either consumer alone finds nothing wrong. RETURNS NO ROW for an undesignated account, and an EMPTY result is the ordinary state for a user who has designated nothing — this is NOT the 056 totality contract and must not be read as one; each caller states what empty means for it. Tenant scope is pfin.account''s own users_id = auth.uid() RLS plus the ADR-029/025 aal2 conjunct, so a cross-tenant caller gets the empty set and both consumers fail closed. set search_path = ''''; NOT a SECURITY DEFINER allowlist entry — DEFINER here would enumerate every tenant''s designated ledgers.';

-- ----------------------------------------------------------------------------
-- (5) THE YTD-PAID READ PRIMITIVE — SELF-267 AC 4 / AC 5 / AC 5a.
--
-- SHAPE, and the three corrections that are invisible in the output (Sec D-2):
--   (i)   NO TENANT PARAMETER. No shipped pfin reader takes one; on a SECURITY
--         INVOKER function a client-supplied tenant is either IGNORED (a lie in
--         the signature) or USED in the predicate (an ownership-forge vector).
--         The tenant comes from auth.uid() through RLS, as everywhere else.
--   (ii)  p_jurisdiction IS THE ENUM, NOT text. With text, an unknown authority
--         returns zero rows and a silent $0, which OVERSTATES Funds Due; with the
--         enum it is a type error at the boundary. The typing IS the control.
--   (iii) NO QUARTER PARAMETER AND NO QUARTER GRAMMAR. The figure is a BALANCE
--         AS OF A DATE, 056-shaped. A quarter-ordinal form would drop the Federal
--         Q4 payment every year — Q4 for tax year Y is due Jan 15 of Y+1 and so
--         falls outside every calendar-quarter flag of Y, including
--         fn_cashflow_items' in_q4 (Oct 1 – Dec 31, 093). A balance read never
--         meets that hazard: R8's rider dissolves it for YTD Paid specifically,
--         and the F-4 render window is about the OBLIGATION row only, computed
--         once in fn_compute_tax_liability (SELF-262) and cited by §2.5.3.
--         ⚠ Sec's M-4 (a UTC-pinned year boundary flips a Pacific user's year
--         ~7h early) is BROADER THAN §2.5 and stays UNOWNED per R8. It is NOT
--         discharged here, and this function does not pretend to bound it.
--
-- COMPOSES ON 056; IT DOES NOT RE-DERIVE THE ROLL-FORWARD. 056's own header
--   rejects a second inline copy of that expression on the ground that a copy
--   inside a consumer fails APART from NAV and is green while NAV is wrong. That
--   argument applies here unchanged, and it is why this body carries no
--   checkpoint anchor and no transaction sum of its own.
--
-- ⚠ AND THAT IS WHY THERE IS NO `transaction_type = 'standard'` FILTER, which a
--   reader of AC 5a will look for. AC 5a's clause — "every `standard` cash row on
--   that ledger counts … there is no per-row 'is payment' flag" — is the
--   NO-PER-ROW-FLAG rule, not an instruction to filter. Filtering would mean
--   re-deriving the roll-forward here (a third copy, the thing 056 exists to
--   prevent) and would break the equality this figure is defined by. So an
--   `acct_setup` opening row on a designated ledger COUNTS, which is correct: a
--   user who opens the ledger with payments already made this year states them
--   as the opening balance.
--
-- WHAT A PAYMENT IS — Sec D-2 (iii) / M-3, stated in the database because that is
--   where the next reader of this function looks:
--     SIGN. Money sent to the authority lands on the designated ledger as a
--       POSITIVE amount, so YTD Paid is POSITIVE when payments have been made.
--       The paying account falls by the same amount on its own row; that is the
--       §2.4.3 manual transfer, and the ledger side is the half this reads.
--     A REFUND is a NEGATIVE amount on the ledger and REDUCES the figure. It is
--       not a separate concept and needs no flag.
--     AN INBOUND TRANSFER is not distinguishable from a payment and is not meant
--       to be: every cash row on a designated ledger counts. That is the whole
--       content of "no per-row is-payment flag".
--     A CORRECTION is a new offsetting row — pfin.account_trans is immutable
--       audit-class (004), so a correction cannot be an edit — and it nets into
--       the same balance with no special handling.
--     NOT CLAMPED. A net-negative figure means refunds exceeded payments, and it
--       is reported rather than floored: flooring would hide a data-entry error
--       as a plausible zero. ⚠ This is deliberately NOT symmetric with the R9
--       zero-clamp on Unrealized Tax Liability, which is a different figure in a
--       different function; do not "restore symmetry" between them.
--     NOT is_tax_payment. ADR-062 scopes that flag to EXPENSE-class prototypes
--       while the seeded tax buckets (041) are TRANSFER-class, so the flag cannot
--       reach them and a `false` there would read as an answered question (M-6).
--
-- NATIVE CURRENCY, NO FX TERM — inherited from 056 by construction, and stated
--   because it is a real edge: for a USD-denominated authority ledger native IS
--   USD, but a designated ledger in another currency returns a native figure that
--   a consumer must fx-normalize itself, exactly as 049 and 050 do for their own
--   cash legs. Adding an fx multiplier here would re-import the eod_price
--   dependency 056 was extracted to avoid.
--
-- NULL vs 0 — THE ONE DESIGN CHOICE THIS FILE MAKES THAT THE AC LEAVES OPEN, and
--   it is a one-character reversal (a coalesce) if F/CTO wants the other:
--   NO DESIGNATED LEDGER returns NULL; a designated ledger holding nothing
--   returns 0. Collapsing them would make "you have not set this up" and "you
--   have paid nothing" the same number, and that is precisely rider 0b's
--   overstated-Funds-Due half arriving as a plausible figure instead of an
--   absent one. NULL propagates through a Funds Due subtraction and fails LOUD;
--   a consumer that wants $0 writes its own coalesce and says so.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_ytd_paid_per_jurisdiction(
  p_as_of        date,
  p_jurisdiction pfin.tax_jurisdiction_enum
)
returns numeric
language sql
security invoker
stable
set search_path = ''
as $$
  -- LEFT JOIN, not INNER — 056's call-site contract, and it is not redundant with
  -- that function's totality guarantee. It changes what a breach COSTS: an inner
  -- join would turn a totality failure into a MISSING ledger and a silently small
  -- YTD Paid; the left join plus coalesce turns it into 0. One degrades to a
  -- visible zero, the other to a wrong number.
  -- Zero designated ledgers => zero rows => sum() is NULL, which is the "not
  -- configured" signal (see the NULL vs 0 note above). This is why the coalesce
  -- sits on balance_native and NOT on the sum.
  select sum(coalesce(c.balance_native, 0))
  from pfin.fn_tax_authority_ledgers() t
  left join pfin.fn_account_cash_as_of(p_as_of) c
    on c.account_id = t.account_id
  where t.tax_jurisdiction = p_jurisdiction;
$$;

revoke execute on function pfin.fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum) from public;
grant execute on function pfin.fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum) to authenticated;

comment on function pfin.fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum) is
  'SECURITY INVOKER §2.5.3 YTD-Paid read primitive (SELF-267 AC 4/5/5a; PRD §2.5.3.c; Lock 11 read-composition). Returns the caller''s tax-authority ledger balance for p_jurisdiction as of p_as_of: the ledgers come from pfin.fn_tax_authority_ledgers() (the single home of the designation predicate) and the balance from pfin.fn_account_cash_as_of (056), composed — NOT re-derived, because a second copy of that roll-forward fails apart from NAV and is green while NAV is wrong. WHAT A PAYMENT IS, since nothing per-row marks one: money sent to the authority lands on the designated ledger as a POSITIVE amount, so this figure is POSITIVE when payments have been made, and the paying account falls by the same amount on its own row. A REFUND is a negative amount on the ledger and REDUCES this figure. AN INBOUND TRANSFER is not distinguished from a payment and is not meant to be — every cash row on a designated ledger counts, which is the whole content of "no per-row is-payment flag", and there is deliberately no transaction_type filter, so an acct_setup opening row counts as payments already made. A CORRECTION is a new offsetting row (pfin.account_trans is immutable audit-class, 004) and nets in with no special handling. NOT CLAMPED: a net-negative figure means refunds exceeded payments and is reported rather than floored, because flooring would hide a data-entry error as a plausible zero — this is deliberately NOT symmetric with the R9 zero-clamp on Unrealized Tax Liability, and the two must not be reconciled. NOT is_tax_payment: ADR-062 scopes that flag to Expense-class prototypes while the seeded tax buckets (041) are Transfer-class, so it cannot reach them. NO YEAR LOWER BOUND, AND THE NAME OVERSTATES THE SCOPE: this is the ledger''s balance as of p_as_of since account inception, not a calendar-year flow. Nothing in V1 drains a designated ledger at a year boundary and account_tax_jurisdiction_uniq permits only ONE designated ledger per authority at a time, so a per-year ledger cannot simply be added alongside the old one, so from the SECOND tax year onward this figure carries prior years'' payments forward — which OVERSTATES YTD Paid and therefore UNDERSTATES Funds Due, the under-reserving direction. The balance-as-of shape is F/CTO-ruled (sitting-log R8 rider, Seam B Option A, explicitly NOT re-opened); this clause records the consequence rather than the choice, so a later reader does not take the absence of a year bound as a question already asked and answered. THE ROLLOVER MECHANISM, AND V1 SHIPS NO OTHER — THREE STEPS, IN THIS ORDER: CLOSE the old ledger, CLEAR its designation, then DESIGNATE a fresh ledger for the new tax year. account_tax_jurisdiction_uniq is per user + jurisdiction, NOT per year, so a fresh designation is always available once the old one is cleared; and CLOSING IS THE STEP THAT KEEPS THE MONEY ALREADY PAID OUT OF NAV, because 049''s as-of predicate (closed_at is null or closed_at::date > p_as_of) drops a closed account from the §2.1.5 leaf set whatever its designation, while clearing alone does not. ⚠ STEP 1 HAS A PRECONDITION V1 DOES NOT HELP WITH: the 058 close gate REFUSES an account holding a non-zero cash balance (leg 2 of 3), and a designated ledger''s balance IS the payments made, so the ledger has to be drained before it can be closed. V1 ships no year-end settle/drain affordance; whether it owes one is a booked product call. ⚠ AND THE ROLLOVER ITSELF MOVES NAV, WHICH IS THE HALF THE PROCEDURE DOES NOT SHOW: clearing a designation returns that ledger to fn_nav_composition''s leaf set immediately — the exclusion is a live read, not a one-way latch (this migration''s battery proves the reversion at L3i / L3j) — so NAV RISES by the whole of the cleared ledger''s balance, which is every payment made to that authority. That is the §9.1 / PM A-9 double-count this migration exists to prevent, re-entered through the ONE rollover path V1 ships, silently and in the NAV-overstating direction. Until a settle/drain affordance exists, a user rolling over must ALSO empty or close the old ledger, and nothing in V1 tells them so or checks that they did. NULL MEANS NO LEDGER IS DESIGNATED FOR THIS AUTHORITY; 0 means a designated ledger holding nothing — collapsing the two would report "not set up" as "nothing paid", which OVERSTATES Funds Due exactly as an unmarked ledger does. NATIVE currency, no fx term (inherited from 056); a non-USD designated ledger must be fx-normalized by the consumer. NO TENANT PARAMETER (a client-supplied tenant on an INVOKER function is either ignored or an ownership-forge vector) and the jurisdiction parameter is ENUM-typed so an unknown authority is a type error at the boundary rather than a silent $0. NO QUARTER PARAMETER: this is a balance as of a date, which is why the Federal Q4-due-Jan-15 hazard does not reach it; the render-window boundary is computed once in fn_compute_tax_liability and cited, and Sec M-4''s UTC year-boundary flag is broader than §2.5 and is NOT discharged here. INVOKER: a cross-tenant caller sees no ledgers => NULL, fails closed. set search_path = ''''; NOT a SECURITY DEFINER allowlist entry. Sec joint-review-mandatory (money figure); two-tenant pgTAP pairing ships same-PR.';

-- ----------------------------------------------------------------------------
-- (6) THE §2.1.5 LEAF-SET EXCLUSION — SELF-267 AC 2a, F/CTO ruling R3 / E-2 (A).
--
-- CREATE OR REPLACE, signature-preserving. The JSONB shape, the category order,
--   the debt sign, the buildup arithmetic and the two 0::numeric tax literals are
--   all UNCHANGED — SELF-268 owns replacing the literals. What changes is the
--   LEAF SET, in one place, by an anti-join against the shared predicate helper.
--
-- ⚠ VOLATILITY IS DECLARED EXPLICITLY — R3 rider 7, and it is load-bearing here
--   rather than stylistic. 079 pinned this function STABLE by ALTER FUNCTION;
--   CREATE OR REPLACE RESETS volatility to the language default, so omitting the
--   declaration would silently un-pin it and 079's own battery leg (V4,
--   pg_proc.provolatile = 's') would go red — with no value anywhere changing.
--
-- ⚠ THE BODY BELOW WAS PRODUCED BY SUBSTITUTION FROM THE LIVE CATALOG
--   DEFINITION, NOT RETYPED FROM 051's FILE — the live body is 059's re-issue,
--   which differs from 051's file text in the leaf CTE's comment block. One
--   anchored substitution, asserted to match exactly once, with a containment
--   proof that the prefix and suffix around the replaced span are byte-identical
--   to the live text, and post-assertions that the executable text still contains
--   no `is_active` reference (059's X6 leg) and exactly one call to the new
--   helper.
--
-- ⚠ THIS BREAKS THE fn_compute_nav IDENTITY ON PURPOSE, and the comment that
--   asserted it is rewritten immediately below rather than left to be corrected
--   later — correcting it later is not available, because a comment on a merged
--   migration can only be changed by emitting a new one. fn_compute_nav is NOT
--   touched: it keeps its gross definition, keeps writing nav_daily, and the
--   checkpointed series stays gross pre-tax permanently (R3).
-- ----------------------------------------------------------------------------
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
  )

  -- Assemble. DEBT-SIGN (A3): debt = −(liability_signed) = positive magnitude. FOOT-TO-NAV
  -- EXACT: nav = gross_total − debt − 0 − 0 = total_non_re + real_estate + liability_signed
  -- = Σ 049(active) = fn_compute_nav(p_as_of, true).
  select jsonb_build_object(
    'groups',   (select groups from groups_json),
    'buildups', jsonb_build_object(
      'total_non_re',        s.total_non_re,
      'gross_total',         s.total_non_re + s.real_estate,
      'debt',                -s.liability_signed,
      'realized_tax_liab',   0::numeric,      -- Option A V1.1 (AC#5); V1.4 ramp
      'unrealized_tax_liab', 0::numeric       -- Option A V1.1 (AC#5); V1.4 ramp
    ),
    'nav', (s.total_non_re + s.real_estate) - (-s.liability_signed) - 0::numeric - 0::numeric
  )
  from sums s;
$$;

revoke execute on function pfin.fn_nav_composition(date) from public;
grant execute on function pfin.fn_nav_composition(date) to authenticated;

comment on function pfin.fn_nav_composition(date) is
  'SECURITY INVOKER §2.1.5 NAV-composition aggregation (V1.1 "Net worth full"; PRD §2.1.5 / SELF-225; Lock 11 read-composition). Returns the composition tree as JSONB: {groups:[{category, accounts:[{account_id, account_name, current_market_value, unrealized_gl}], subtotal}], buildups:{total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab}, nav}. COMPOSES ON 049 fn_account_unrealized_gl (single leaf substrate — per active account current_market_value + unrealized_gl, naturally signed) joined to pfin.account for name + account_type; 049 already filters by the AS-OF predicate (closed_at is null or closed_at::date > p_as_of) — the boolean flag it used to filter on was RETIRED at 059 per ADR-042, and this function still adds NO predicate of its own and MUST NOT (adding one double-filters). groups[] in canonical category order (depository/investment/retirement/crypto/manual_other → real_estate → liability; §2.1.5/AC#2), empty categories omitted; accounts[] by account_id; leaf unrealized_gl NULL for non-investment (049, AC#3). DEBT SIGN (D-1): liability leaves + subtotal carry 049''s natural negative sign; buildups.debt = −(liability subtotal) = positive magnitude so AC#4 nav = gross_total − debt reads literally. TAX PLACEHOLDERS (Option A V1.1, AC#5): realized_tax_liab and unrealized_tax_liab are STILL 0::numeric literals here — including the two inside the nav expression above — and SELF-268 is where fn_compute_tax_liability''s values replace them. 102 changed the LEAF SET, not the tax scalars. FOOT-TO-NAV, AS AMENDED AT 102 — THE IDENTITY WITH fn_compute_nav IS DELIBERATELY BROKEN AND MUST NOT BE "RESTORED": nav = total_non_re + real_estate + Σ liability_signed over the leaf set MINUS every tax-authority-designated ledger (SELF-267 AC 2a; F/CTO ruling R3, E-2 option A, 2026-09-03), while fn_compute_nav(p_as_of, true) keeps its GROSS definition and still INCLUDES those ledgers — so the two differ by exactly the designated ledgers'' balances, and 051 no longer foots to it. The reason is arithmetic, not presentation: a tax payment lands as cash on a designated ledger while the obligation falls by the same amount, so counting both would raise NAV by the amount paid. WITHIN this function the buildup still foots to its own nav by construction (single-substrate natural summation over the FILTERED leaf set; ADR-038/039; no separate fn_compute_nav call). The exclusion predicate is NOT written in this body: pfin.fn_tax_authority_ledgers() is its single home, shared with pfin.fn_ytd_paid_per_jurisdiction (ADR-063 Decision item 2 — note ADR-063 numbers its protocols as ITEMS inside one Decision block). An unmarked tax-authority ledger is therefore NOT excluded and NAV reads high by its balance. The designation is a user-set NULLABLE attribute, so that default state is reachable by omission alone; it becomes visible on the §2.1.5 surface only where that surface renders the exclusion (SELF-268 AC 10a), and until it does, an unmarked ledger has no observer here. p_scope DROPPED (pfin.scope type does not exist; scope is a free-text ADR-004 label — per-scope reporting is V2+, PRD §2.1.7); p_users_id DROPPED (INVOKER + RLS scope by auth.uid()). AS-OF via 049 threading (Lock 15; V1.1 consumers pass CURRENT_DATE). INVOKER → cross-tenant caller sees no rows → empty groups / nav 0 (fails closed). set search_path=''''; NOT a DEFINER allowlist entry (read ADR-011 Decision 9 live; no count is stated here, for the same reason the next clause gives); §10 catalogued ledger UNCHANGED BY THIS OBJECT — and NO COUNT IS STATED HERE, deliberately. A ledger-impact claim is AUTHORING-TIME PROVENANCE: it belongs in a migration header, which is a dated artifact, not in a catalog comment, which reads as LIVE STATE. Read ADR-011 Decision 4 live. Decision-3 unchanged (no new FK column). Sec joint-review-mandatory (financial calc + multi-tenant); RLS verification → SELF-225 two-tenant battery. §2.1.6 MV-vs-COST-BASIS AUDIT-TRACE (SELF-227, comment-only — no body/signature/logic change): investment-account contributions to NAV use CURRENT MARKET VALUE (eod_price × qty × fx), NOT cost basis; cost basis is confined to 049.cost_basis / unrealized_gl (+ future §2.2.x cost-basis-display surfaces). PRD §2.1.6 / SELF-227.';
