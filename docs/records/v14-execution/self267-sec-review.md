# SELF-267 — Security joint-review (ADR-011 D1/D2/D3/D4 · Lock 11 · Lock 14 · Lock 15)

**Verdict: AMBER.** No veto. No tenant-isolation defect, no privilege-boundary defect, no
`SECURITY DEFINER` addition, no §10 ledger movement, no Decision 3 obligation. Three blocking
conditions, all cheap, two of which have a **pre-merge-only fix window** (a merged migration's
header and `comment on` text can only be changed by emitting a new migration — which is 102's own
stated reason for rewriting `051`'s comment now rather than later).

**Reviewed at** `origin/feature/self-267` tip **`2c158e4`** (`git rev-parse`), base `origin/main`
**`762f793`**. `git diff --stat 46f896d 2c158e4` = the walk record only, so the walk (recorded
against `46f896d`) named the same source tree as this review.

---

## 0. Verify-hook — read verbatim before verdict

Read verbatim from `DECISIONS.md` on this branch (the PR edits no ADR — `git diff --stat
origin/main...HEAD` carries no `DECISIONS.md` path, so branch and `main` are the same text):
ADR-011 Decision 3, Decision 4 (body + the §10 attribution CHANGELOG + the 2026-09-03 amendment),
Decision 15 (Lock 11), Decision 18 (Lock 14); ADR-063 in full; ADR-062 Decision 2. Located by
bracketing `## ADR-` header, never by line number.

### §10 three-axis cross-check — CLEAN on all three

- **(i) Instance-numbering.** Decision 4's catalogued list read live: RT-22 first, RT-26 second,
  RT-27 third. 102 adds, removes, reorders and renumbers nothing, and states so without carrying a
  count. Clean.
- **(ii) Layer-attribution.** Decision 4's own words are *"Three classes of surface"* and
  *"no surface becomes 'four-layer'"*. 102 writes *"the three-class composition is untouched"* —
  the **correct noun**, which is precisely the PR #368 inherited-mislabel catch (four-LAYER
  vocabulary standing in for four-CLASS content). Clean. One sub-note at §5 below.
- **(iii) Verbatim-vs-paraphrase.** Path B applied correctly: Decision 4 is linked, never restated;
  no enumeration, no count. 102 is not the canonical anchor and does not claim to be. Clean.

**⚠ Set-disjointness restated, not reconciled.** §10 CATALOGUED = RT-22 / RT-26 / RT-27 (read from
ADR-011 D4 body). CI-FENCED = RT-05 / RT-22 / RT-26 / RT-27 (`grep -rhoE 'RT-[0-9]{2}'
.github/workflows/ | sort -u`). These are **different sets** — the fenced set adds RT-05 — and they
must never be reconciled. 102 says exactly this and adds nothing to either. Clean.

### Citation-pointer checks run against the cited sources

- **ADR-063 "Decision item 2".** ADR-063 does number four bolded protocols **inside a single
  `### Decision` block** (verified: no `### Decision N` headers under ADR-063, unlike ADR-011 which
  uses `### Decision 1..20`). 102's citation note is therefore accurate, and its claim that
  *"ADR-066's cross-references already record the malformation"* is **true verbatim** — ADR-066's
  Cross-references carries the identical warning. Clean.
- **ADR-011 Decision 3.** *"Any FK-shaped reference column (single FK, self-FK, INTEGER[] array
  element) that crosses an isolation boundary requires explicit matched-tenant validation."*
  `pfin.account.tax_jurisdiction` is an ENUM with no referent — no referenced row, therefore no
  tenant to match. **No matched-tenant obligation is owed.** The family is flat: nothing added,
  re-targeted or dropped, no label moves, next instance still takes #18. 102's per-column statement
  (085's rule) is correct and is the whole check. Clean.
- **ADR-062 Decision 2 / the `is_tax_payment` non-use.** D2's own text scopes the flag to
  Expense-class prototypes and warns that an unscoped reader would take `false` on a non-Expense row
  *"as evidence the question had been asked and answered."* 102 paraphrases this (not in quotes) and
  reaches the correct conclusion: the flag cannot reach the Transfer-class seeded tax buckets.
  Clean.
- **The ADR-042-not-ADR-047 attribution.** 102 attributes the *"class membership is not a
  catalogued instance"* ruling to **ADR-042's own Consequences**. That is the correct pointer —
  Decision 4's PR #476 catch (2) records ADR-047 as the false composite. 102 avoids it. Clean.
- **Lock 14 (ADR-011 Decision 18).** *"V1-SHIP-BLOCK strict typed-input validation +
  mass-assignment prevention"* — satisfied (see §3). *"`users_id` from `auth.uid()` not
  `req.body`"* — satisfied: no write path sends `users_id`, and both schemas are `.strict()`.
- **Lock 11 (ADR-011 Decision 15).** The mod reads *"V1-SHIP-BLOCK SECURITY INVOKER on read-time
  composition (no DEFINER bypass)"*, scoped in its own text to the `monthly_report` composition.
  102's gloss *"SECURITY INVOKER (default per ADR-011 Lock 11)"* widens it. **I do NOT require a
  change**: 22 migration files already carry the phrase *"Lock 11 read-composition"*
  (`grep -rl "Lock 11 read-composition" supabase/migrations/ | wc -l` = 22), so this is established
  project convention inherited from `051`'s own pre-existing comment, not drift introduced here.
  Recorded so the widening is on the record rather than unexamined.

---

## 1. The shared predicate — ONE executable home, verified by grep, not by claim

`grep -rn "tax_jurisdiction" supabase/migrations/` returns hits in **`102` only** — no other
migration mentions the column. Within `102`, the non-comment occurrences of the predicate are:

- **`102:296`** — `where a.tax_jurisdiction is not null`, inside `pfin.fn_tax_authority_ledgers()`.
  The single read-path home.
- **`102:405`** — `where t.tax_jurisdiction = p_jurisdiction`, a **refinement of the shared set**,
  not a parallel realization. The set-returning-vs-scalar rationale in the header is correct: with a
  scalar `fn_is_tax_authority_ledger(account_id) boolean` the jurisdiction test would have had to be
  written beside it, which is the second realization.
- **`102:261`** — `where tax_jurisdiction is not null`, the partial unique index's own predicate.

**On `102:261` — I do NOT call this a second realization, and I state why so a later reviewer does
not "fix" it.** A partial index's predicate cannot be routed through a function (an index predicate
must be immutable; a `stable` SRF is not indexable). It is a *constraint* clause, not a *read*
clause, and the two consumers ADR-063 item 2 governs are the read consumers. **The one residual is
real and is a NOTE, not a flag:** the header sentence *"realized in exactly ONE object,
`pfin.fn_tax_authority_ledgers()`"* is, read literally, falsified by `102:261`. If the shared
predicate ever narrows (say, to exclude closed accounts), the index will not follow and nothing
will say so.

`grep -rn "tax_jurisdiction" api/src` — no app-layer restatement of the predicate anywhere. The
app writes the column and reads it into `PageData`; it never re-derives designated-ness. Clean.

---

## 2. `fn_ytd_paid_per_jurisdiction` — posture, composition, and the four rulings I was asked for

**Posture, read off the file.** `security invoker` · `stable` · `set search_path = ''` ·
`revoke execute … from public` + `grant execute … to authenticated`
(`102:383-409`). Same triple on `fn_tax_authority_ledgers` (`102:287-300`) and re-emitted on
`fn_nav_composition` (`102:444-544`). **No tenant parameter** (D-2 (i) discharged).
**`p_jurisdiction` is `pfin.tax_jurisdiction_enum`, not `text`** (D-2 (ii) discharged).

**Fail-closed composition, verified one level down rather than assumed.**
`pfin.fn_account_cash_as_of(date)` (`056:149-181`) is itself `security invoker` / `stable` /
`search_path = ''` with the same revoke+grant pair. So a cross-tenant caller sees no accounts →
`fn_tax_authority_ledgers()` returns empty → the sum is over zero rows → **NULL**, and the `051`
anti-join has nothing to exclude, which is the pre-102 behaviour. Fails closed on both consumers.
The `left join` + `coalesce(c.balance_native, 0)` placement is correct and its stated reason holds:
the coalesce sits on the column, **not** on the `sum()`, which is exactly what preserves the
zero-rows→NULL signal.

**AAL2.** `pfin.account`'s `account_update` carries `using (users_id = auth.uid()) with check
(users_id = auth.uid())` at `003:119-120`, re-declared at `025:219-233` with the per-user-conditional
`aal2` conjunct on **both** clauses. A new column inherits both. 102's claim that the designation is
aal2-fenced on read and write from the moment it exists is **true as written**. `003:124` grants
`select, insert, update` at table grain (no column-level ACLs anywhere), so no grant work was owed.

### Ruling A — the `acct_setup` opening row counts as YTD Paid (E11 item 2). **Not a fail-open. No objection.**

There is no privilege or tenant boundary in play: the value is the caller's own asserted figure in
the caller's own ledger, readable only by the caller. The failure mode is money-correctness, not
security, and its direction is *understate Funds Due* for a user whose opening balance is something
other than payments-already-made. **I do NOT require a `transaction_type = 'standard'` filter** —
adding one would force the roll-forward to be re-derived inside this function, which is the third
copy `056` was extracted to prevent, and the header's reading of AC 5a (*no-per-row-flag rule, not
an instruction to filter*) is the correct one. The DB comment states the consequence explicitly and
the UI hint (`TaxJurisdictionField.svelte:65`) tells the user *"its balance feeds the §2.5.3 YTD
Paid column"*. Discharged.

### Ruling B — NULL vs 0 (E11 item 1). **Endorsed, with a live consumer obligation. FLAG.**

NULL for "no ledger designated" / 0 for "designated and empty" is the right call and I endorse the
reasoning verbatim: collapsing them reports *not set up* as *nothing paid*, which is rider 0b's
overstated-Funds-Due half arriving as a plausible figure rather than an absent one.

**The residual is the consumer, and it is currently carried by nothing that can fail.** E11 carried
the obligation forward — *"consumers decide what NULL renders as (an explicit 'no ledger
designated' state, never `$0`)"* — but that obligation lives only in the execution log and in
`102`'s `comment on function`. Neither is a watcher. A single `?? 0` or `coalesce(…, 0)` in
SELF-262 / SELF-266 silently re-creates exactly the failure this design chose NULL to avoid, and it
will look like ordinary null-handling hygiene at review. **This is the zero-value-sentinel shape:
the default is where the meaning flips.**

**Requirement (flag, owner PM + team-lead, before SELF-262/266 merge — not before this one):** the
never-render-NULL-as-`$0` obligation lands as an explicit acceptance criterion on **both** SELF-262
and SELF-266, with a rendering test that fails if the figure renders as a currency zero when no
ledger is designated. An obligation with no watcher is discharged by nobody.

### Ruling C — "YTD Paid" has no year lower bound. **FLAG — new finding, pre-merge fix window.**

`fn_ytd_paid_per_jurisdiction(p_as_of, p_jurisdiction)` returns `fn_account_cash_as_of(p_as_of)`
for the designated ledger. That is a **balance since account inception**, not a year-to-date flow.
There is no lower date bound anywhere in the body (`102:401-405`).

Nothing in V1 drains a designated ledger at a year boundary, and the partial unique index makes
"one ledger per authority per user" a standing constraint — so a user cannot open a fresh ledger per
tax year without first clearing the old one. In tax year 2, `fn_ytd_paid_per_jurisdiction` therefore
returns *2026 payments + 2027 payments*. **Direction: overstates YTD Paid → understates Funds Due →
under-reserve.** That is the silent direction.

**I do NOT ask to re-open the shape.** R8's rider ruled it and marked it closed: *"YTD Paid is the
account-ledger balance as-of (Seam B Option A, PRD-verbatim, presupposed by the already-ruled Gate B
Option A `tax_jurisdiction` enum — NOT re-opened)."* This finding is downstream of that ruling, not
an objection to it.

**What I require is that the consequence be stated where the next reader looks.** The `comment on
function` answers *what a payment IS* exhaustively — sign, refund, inbound transfer, correction,
clamping, `is_tax_payment` — and never answers *what the YEAR in year-to-date is*. A reader who
checks the comment for the figure's semantics will find every question but this one answered, which
reads as *asked and settled* rather than *not asked*. This is the same hazard ADR-062 Decision 2
names for `false` on a non-Expense row.

**Blocking condition B1 (owner: Architect, pre-merge only).** Add to
`fn_ytd_paid_per_jurisdiction`'s `comment on function`, verbatim:

> NO YEAR LOWER BOUND, AND THE NAME OVERSTATES THE SCOPE: this is the ledger''s balance as of
> p_as_of since account inception, not a calendar-year flow. Nothing in V1 drains a designated
> ledger at a year boundary and account_tax_jurisdiction_uniq prevents a fresh ledger per tax year,
> so from the SECOND tax year onward this figure carries prior years'' payments forward — which
> OVERSTATES YTD Paid and therefore UNDERSTATES Funds Due, the under-reserving direction. The
> balance-as-of shape is F/CTO-ruled (sitting-log R8 rider, Seam B Option A, explicitly NOT
> re-opened); this clause records the consequence rather than the choice, so a later reader does not
> take the absence of a year bound as a question already asked and answered.

**Booking (owner: PM, not blocking):** V1 has no year-end settlement path for a designated ledger.
Whether V1 accepts multi-year carry-forward, or owes a drain/settle affordance, is a product call.

### Ruling D — create-then-UPDATE with no rollback on 23505-after-create. **No objection.**

`accounts/new/+page.server.ts:101-129` is the correct call and the code's own reason is the right
one. I add a second reason it does not state: `003:121` records **no DELETE policy and no DELETE
grant on `pfin.account`**, so a compensating rollback is not merely undesirable — it is not
available to `authenticated` at all. Deleting a genuine account to hide a conflict the user can
resolve on the account they already have would be the worse failure. Discharged.

**One dropped output, low.** The action returns `accountId` on both the 409 and the 422 branch
*"so the caller can route the user to it"* (`:107-108`, `:115`, `:127`), and
`new.server.test.ts:121-145` asserts it is returned — but `accounts/new/+page.svelte` never reads
`form.accountId`. The user is left on the create form with a field error and no route to the
account that was in fact created. An output column produced, tested, and never consumed. **flag
(low), owner Frontend.**

### Ruling E — manual-only refusal is app-layer only (E12). **Acceptable. I do NOT require a DB fence.**

The isolation boundary on this column is `users_id = auth.uid()` + the aal2 conjunct, and it is at
the DB, on every write, inherited by construction. "Only manual accounts may be designated" is a
**product-scope rule**, not an isolation rule: designating one's own provider-linked account changes
only one's own figures and reaches no other tenant. A DB CHECK would couple `102` to the
provider-link representation for no isolation gain, exactly as E12's losing side records.

The app-layer refusal (`[account_id]/+page.server.ts:620-642`) is well-shaped and I checked the two
things that usually go wrong with a read-then-write guard:
- It is **gated on "is a designation actually being set"** — `undefined` (untouched) and `null`
  (explicit clear) never trigger the extra read, so clearing a stale designation on an
  account that has since become linked still works.
- The read is **RLS-scoped** (`locals.supabase`, `.eq('account_id', accountId)`, `.maybeSingle()`)
  and **no-ops on a miss**, so a cross-tenant `account_id` produces no existence leak: the UPDATE
  below decides the outcome and silently touches zero rows, which is what this action has always
  done. It does not start distinguishing "not yours" from "nothing to change" here. Correct.

**One note, owner Architect (book, do not build).** The refusal is checked at *designation time*
only. A manual account designated `irs` that is **later** bound to a provider retains the
designation, and nothing observes it. E12 already carries the right hook — *"bookable if a provider
ever exposes a tax-authority ledger"* — this is the same booking approached from the other
direction, and it should be attached to whichever issue lands a manual→linked binding path.

---

## 3. Write path — Lock 14

- **Mass-assignment.** `.strict()` on all four schemas: server `manualAccountCreateSchema:103`,
  server `updateAttributesSchema:214`, and both client mirrors (`schemas/account.ts:89`, `:161`).
  Neither write path sends `users_id`; `updatePayload` is built key-by-key
  (`[account_id]/+page.server.ts:644-655`), never spread from `parsed.data`.
- **Typed input.** `z.union([z.enum(TAX_JURISDICTIONS), z.literal('')])` — an unrecognised non-empty
  string is **rejected**, never coerced to a clear. Values arrive via
  `Object.fromEntries(formData)`, so a duplicated field name yields the last string rather than an
  array, and a non-string fails the union. The numeric adversarial battery is **inapplicable** to an
  enum column; I do not require it here and say so explicitly so its absence is not read as a gap.
- **Client mirror never looser.** Field-for-field identical to the server, including both variants
  and their transforms; only the enum error messages differ. Lock 14 mirror discipline holds.
- **Three-way edit semantics.** `taxJurisdictionEditField` yields `'irs' | 'ftb' | null |
  undefined`, and the action includes the key **only** when not `undefined`
  (`:653-655`). Verified end-to-end on the UI side: `TaxJurisdictionField.svelte:58` renders under
  `{#if !hidden}` so a linked account's submit carries **no key at all**, and `openEditor()`
  (`[account_id]/+page.svelte:135`) seeds `editTaxJurisdiction` from the loaded row, so the "control
  shown but empty ⇒ silent clear" trap is closed on both sides. `ACCOUNT_COLUMNS`
  (`+page.server.ts:123`) selects the column, which is what makes the pre-fill real.
- **23505 → field error by constraint NAME, not code alone.** `isTaxJurisdictionConflict`
  (`[account_id]:143-145`, `new:32-34`) tests `err.code === '23505'` **and**
  `/account_tax_jurisdiction_uniq/i`. This is the shape I want: a future second constraint on
  `pfin.account` cannot be misclassified into this field. Checked first, before the generic
  envelope. Clean.
- **Client `locals.supabase` throughout.** No `service_role` anywhere on either path
  (`grep` over both files). ADR-011 D1 is not engaged by this PR.

**Lock 14 layer attribution — sub-note (owner: Architect, pre-merge, same edit as B1 if convenient).**
102's header names this surface's Lock 14 layers as *"the app-layer validation …, the RLS WITH CHECK
it already inherits from 003+025, and the DB-level partial unique index."* Decision 4's Lock 14
bullet enumerates *app-layer `.strict()` + mass-assignment prevention · numeric-input adversarial
battery · RLS WITH CHECK at DB layer · DB-trigger backstops*. **A unique index is not one of the
four**, and the numeric battery is inapplicable rather than absent. The claim is true about the
surface and slightly off about the vocabulary — the PR #368 class exactly. Suggested replacement for
that clause, verbatim:

> Its Lock 14 layers are the app-layer validation (Backend/Frontend `.strict()` + the enum union)
> and the RLS WITH CHECK it already inherits from 003+025. Decision 4's numeric-input adversarial
> battery is INAPPLICABLE to an enum column rather than absent, and the partial unique index below
> is a correctness fence rather than one of Decision 4's enumerated Lock 14 components — named here
> so it is not counted as one.

---

## 4. The `051` CoR

Signature-preserving (`fn_nav_composition(p_as_of date default current_date) returns jsonb`);
`stable` **explicitly re-declared** (R3 rider 7 — `CREATE OR REPLACE` resets volatility to the
language default, which would silently un-pin `079` and red its own V4 leg with no value changing);
ACL pair re-emitted; the two `0::numeric` tax literals unchanged in both the `buildups` object and
the `nav` expression; the exclusion realized as a **left-join anti-join against the shared helper**,
so a designated ledger the caller cannot see leaves the row IN, which is the pre-102 behaviour.
`fn_compute_nav` is not touched.

**Comment rewritten so it no longer asserts the broken identity.** Verified: the new text says the
identity *"IS DELIBERATELY BROKEN AND MUST NOT BE 'RESTORED'"* and states the exact difference. It
also correctly **declines to claim the §2.1.5 rendering of the exclusion exists** — *"it becomes
visible on the §2.1.5 surface only where that surface renders the exclusion (SELF-268 AC 10a), and
until it does, an unmarked ledger has no observer here."* That discharges the confirm I was asked
for: **nothing in this PR claims my §9.1 item 2 rendering requirement is met.** It is correctly
carried forward as owed.

**Other batteries' pins on `051` — checked mechanically, both hold:**
- `self227_investment_mv_verification.sql:298` pins
  `obj_description('pfin.fn_nav_composition(date)') like '%SELF-227%'`. The new comment retains the
  §2.1.6 SELF-227 audit-trace paragraph. Holds.
- `059_closure_reconciliation_fences.sql:349-355` (X6) pins that the **executable** text carries no
  `is_active`, stripping `--` comments first. The new body's leaf comment does contain the literal
  string `is_active` (`102:458`) — it is stripped by X6's `regexp_replace` before matching, so the
  leg holds. Worth recording that it holds *because* X6 strips comments, not because the string is
  absent.

**Flag (low), owner Architect, pre-merge only — the equality-leg enumeration stops short.** 102's
header says the divergence is safe *"which is why the existing self227 (12) and self228 (D2)
equality legs stay green on their own fixtures rather than being retired."* Two corrections:
1. **`051`'s own battery carries the same claim twice and is not named** —
   `051_fn_nav_composition_rls.sql:312-330`, legs **(F1)** (`nav == fn_compute_nav(as_of, TRUE)`)
   and **(F2)** (`… FALSE`). They are the most direct encoding of the identity 102 breaks, and a
   reader consulting this header to find every leg that encodes it will miss them.
2. **`self228` (D2) is not a `fn_compute_nav` equality leg.** Read at
   `self228_v1_1_close_gate.sql:428-436`, it compares `fn_nav_composition`'s nav to an
   independently-summed full-household total. It is affected by the same fixture condition, but
   calling it an *equality leg* alongside (12) mischaracterizes what it asserts.

All four stay green today, because no fixture designates an account and the column is nullable with
no default. The defect is in the header's completeness, and the header is unfixable after merge.
Suggested replacement for that clause, verbatim:

> — which is why the existing equality legs stay green on their own fixtures rather than being
> retired: `051`'s own (F1) / (F2) (`nav == fn_compute_nav(as_of, TRUE)` and `… FALSE`) and
> self227's (12). self228's (D2) is affected by the same fixture condition but asserts agreement
> with an independently-summed household total, not equality with `fn_compute_nav`. Every one of
> them holds only while no account in its fixture is designated; a fixture that designates one must
> re-derive them, not delete them.

---

## 5. Partial unique index

`create unique index if not exists account_tax_jurisdiction_uniq on pfin.account (users_id,
tax_jurisdiction) where tax_jurisdiction is not null` (`102:259-261`). Per-user (`users_id` leads),
per-jurisdiction, NULLs excluded so the undesignated majority is unconstrained. Correctly described
in its own comment as a **correctness fence, not an ADR-011 Decision 3 fence** — it constrains one
tenant's own rows against each other and involves no cross-tenant reference. That distinction is
stated twice (header and index comment) and both statements are right. The double-count chain it
prevents (second ledger → YTD Paid doubled → Funds Due understated → Realized understated → NAV
overstated, with no error at any step) is correctly reasoned. Clean.

---

## 6. Battery — 35 legs

Plan arithmetic checks out: `L1 6 · L2 3 · L3 10 · L4 1 · L5 1 · L6 2 · L7 1 · L8 6 · L9 4 · L10 1`
= 35, matching `select plan(35)`.

**Non-vacuity, checked leg by leg on the ones that matter:**
- **(L2b)** is non-vacuous *because both tenants hold `'irs'` simultaneously* — a leak-free assertion
  where the other tenant holds a different value would pass for the wrong reason. Correctly built.
- **(L2a)** is a top-level data-modifying CTE (`with upd as (update …) select is(…)`), not nested
  inside a scalar subquery — the form that actually executes. And it is paired with **(L2a-verify)**
  re-reading the row as `postgres`: *reported* zero rows and *touched* nothing are two claims, and
  the battery separates them. This is the shape I want and I am recording it as such.
- **(L3)** walks one account through undesignated → designated → reverted, observing **both**
  consumers at each state, and (L3f) **measures** the divergence (`fn_compute_nav − comp.nav =
  1500`) rather than arguing it from the comment. (L3g) pins `fn_compute_nav` unmoved across the
  designation. (L3j) proves the exclusion is a live read, not a one-way latch. Rider 0b is genuinely
  observed, not asserted.
- **(L4b)** is non-vacuous: `a_idx2` is designated with no checkpoint and no transactions, and 056's
  totality contract yields one row, so `sum(coalesce(…,0))` = 0 — distinguishable from L3a's NULL.
- **(L6a/L6b)** are a real boundary pair one step apart (same row, two `p_as_of` values), so L6a
  cannot pass because the row never landed.
- **(L8)** covers all three functions on `prosecdef` / `provolatile` / `proconfig` **and** the
  anon-denied / authenticated-granted pair. (L8e) is the watcher for R3 rider 7 — it reds if the
  `stable` re-declaration is ever dropped from a future `CREATE OR REPLACE`.

**Legs that cannot fail cleanly — two, both minor, neither blocking:**
- **(L9d)** is `select ok((select true from pg_proc where oid = '…'::regprocedure), …)`. If the
  signature moves, the **cast** raises and aborts the file rather than the leg returning false. The
  leg's own message says so explicitly, and 013's precedent is cited. Self-documented; a `pg_prove`
  run still exits non-zero. I do not require a change. I confirm the signature it pins is **correct**
  — `087:321-329` is 7-arg with `p_positions jsonb default '[]'::jsonb`, so the app's 6-arg call and
  this 7-arg regprocedure are both right.
- **(L9a)** filters `pg_enum`/`pg_type` on `t.typname` with **no `pg_namespace` join**. Only one
  such type exists today, so it passes for the right reason; a same-named type in another schema
  would make `array_agg` aggregate across both. `note`, owner QA, non-blocking.

**What I could not verify by inspection, stated rather than assumed:** I have no database in this
review and did not run the battery. **(L10)**'s hard-coded md5 `9917963f…` and **(L9c)**'s
`indexdef` regex are pass/fail only under execution. I did verify (L10) pins the right thing (the
`p_as_of date, p_active_only boolean` overload of `fn_compute_nav`, by
`pg_get_function_arguments`), and that 102 does not touch that function.

**Blocking condition B2 — the fenced lane has not run.** `gh pr list --head feature/self-267` returns
`[]`: **no pull request exists**, so `db-tests.yml` has never run against this branch. That workflow
auto-discovers `supabase/tests/rls/**` via `pg_prove --ext .pg --ext .sql -r`
(`db-tests.yml:140-144`), so the battery **will** be fenced once a PR exists — it is not outside the
fence, it simply has not run. Open the PR and require a green `db-tests` before merge. This is the
only evidence that can settle (L10) and (L9c), and per project discipline a local `psql` run is not
a substitute: `psql` exits 0 on a failed pgTAP plan, only a TAP-aware consumer exits 1.

---

## 7. Walk record

`docs/records/v14-execution/self267-walk.md` records legs A–G all SEEN, defects none. Leg B is the
one that matters and it is the right observation: mark → **both** figures move, measured before and
after, with the $1,000 divergence between the page's own headline ($3,891 = `fn_compute_nav`) and
its own Composition foot ($2,891 = `comp.gross_total`) seen on **one page at one moment**. That is
rider 0b observed rather than argued, and the interim divergence is correctly recorded as
expected-not-defect.

Leg E is load-bearing for §3 and was verified the right way — *"confirmed via accessibility tree —
not CSS-hidden, simply not rendered"*, with the DB re-read confirming `tax_jurisdiction` stayed NULL
through an unrelated attribute edit. Leg G confirms the absent-key-means-no-change rule on live
data. Leg C exercised the 23505 path **on the edit action**; the **create-then-UPDATE** 23505 branch
(`new/+page.server.ts:109-117`) was not walked — it is covered by `new.server.test.ts:121-134`, so
this is a `note`, not a gap.

---

## 8. Record-accuracy finding on the dispatch brief itself

**⚠ `E14` does not exist.** The brief cites *"execution-log E3/E11/E12/E14"* and *"an INTERIM
divergence accepted at E14."* Measured: `docs/records/v14-execution/log.md` on
`origin/meta/v14-execution-log` runs **E1 … E13** and stops (60 lines; `grep -n "^### E"` returns
thirteen headings). I searched **every** `refs/remotes/origin` ref that carries the file — E14
appears on none of them.

The ruling the brief attributes to E14 is **E3**, which places the `051` leaf-set exclusion in
SELF-267 rather than SELF-268 precisely so rider 0b's walk is observable — which is what makes the
headline/foot divergence an accepted interim state until SELF-268. I re-anchored to E3 and my
verdict does not rest on E14. Recorded because a verdict resting on a ruling that exists on no ref
is the failure my own Sec-Lock cross-check exists to catch, and because if E14 was authored
locally and never pushed, it is currently unrecorded.

E11 items 1–7 and E12 were read in full from the pushed ref and are honoured by the build as
written, including E11 item 2's explicit *"Flagged for Sec at joint review"* — ruled at §2 Ruling A.

---

## 9. Non-objections, stated explicitly

- **I do NOT require a `SECURITY DEFINER` function anywhere in this surface**, and none is proposed.
  The DEFINER allowlist (ADR-011 Decision 9) is **unchanged** by this PR. INVOKER is load-bearing
  here, not tidiness: DEFINER on either new function would enumerate or sum across every tenant.
- **I do NOT require a DB fence for manual-account-only designation** (Ruling E).
- **I do NOT require a `transaction_type` filter on the YTD-Paid primitive** (Ruling A).
- **I do NOT require the numeric-input adversarial battery** on this surface — inapplicable to an
  enum column.
- **I do NOT require an ADR amendment.** No §10 ledger change, no Decision 3 instance, no
  Decision 9 addition, no RT-26 allowlist addition, no CI fence change, no `secrets-manifest.yml`
  touch, no new pgsodium-encrypted column, no `service_role` write surface, no audit-class
  (Decision 2) write-surface change — `pfin.account_trans` is read via `056` and never written by
  this PR.
- **I do NOT object to the Lock 11 gloss** (§0), to the partial index's predicate as a third textual
  occurrence (§1), or to (L9d)'s abort-rather-than-fail shape (§6).
- **I do NOT require the walk to be re-run.** It named the same source tree as this review.

## 10. My own errors in this pass

None to report beyond the E14 correction at §8, which is a correction to the brief rather than to my
own prior findings. My pass-2 findings D-2 (i)/(ii)/(iii), M-3, F-1 caveat X-1 and §9.1 items 1 and
3 are all discharged by this build; §9.1 item 2 (the rendering) is correctly carried forward as owed
and this PR does not claim otherwise. **M-4 is NOT discharged here and the migration correctly says
so** rather than pretending to bound it.

---

## Verdict and conditions

**AMBER.** Clear on every mandatory surface. Three blocking conditions:

- **B1 — Architect, pre-merge only.** Add the year-lower-bound clause to
  `fn_ytd_paid_per_jurisdiction`'s `comment on function` (§2 Ruling C, text supplied verbatim).
  Fold in the Lock 14 layer-attribution clause (§3) and the equality-leg enumeration clause (§4) in
  the same edit — all three are `comment`/header text on a migration that cannot be amended after
  merge.
- **B2 — DevOps/team-lead.** Open the PR and require a green `db-tests` run. No CI has executed
  against this branch; (L10)'s md5 pin and (L9c)'s indexdef regex are unverifiable by inspection and
  a local `psql` run does not substitute.
- **B3 — PM + team-lead, before SELF-262/266 merge (not before this one).** The
  never-render-NULL-as-`$0` obligation lands as an explicit AC on both consumers with a failing
  watcher (§2 Ruling B).

Non-blocking: the dropped `accountId` on the create page (Frontend); the later-becomes-linked
booking (Architect); (L9a)'s missing namespace filter (QA); the create-path 23505 branch unwalked
(none — test-covered).

---

## Verdict line — 2026-09-04 · **GREEN at `6b973bf`**

Two re-reviews since the AMBER above, diffs only. All conditions discharged; no blocking finding
remains. Every measurement below was taken in the same turn it is written.

**`2c158e4` → `2dc8e53`.** B1 landed **byte-verbatim**. B2 discharged — PR **#605** opened and
`pgTAP RLS battery (supabase test db)` reported **SUCCESS**, which settles the two legs I could not
verify by inspection ((L10)'s hard-coded md5, (L9c)'s `indexdef` regex). The Lock 14 layer list and
the equality-leg enumeration landed verbatim. Architect's rewording of the shared-predicate heading
to **ZERO READ-PATH COPIES** — one executable home plus the index predicate named as structurally
non-routable, with the narrowing residual stated — is **better than the note I filed** and is
endorsed. The Frontend `accountId` note is discharged and its implementation names a hazard I had
not: a stranded user re-submitting would create a SECOND account.

**New blocking finding raised at `2dc8e53` (C1), now closed.** The rollover clause added beside my
B1 text told the user to *clear and re-designate* and did not say what that does to NAV. Clearing
returns the ledger to `fn_nav_composition`'s leaf set — the exclusion is a live read, not a one-way
latch, which this migration's own battery proves at **(L3i)/(L3j)** — so NAV would rise by every
payment ever made to that authority: the §9.1 / PM A-9 double-count re-entered through the sanctioned
path, silently, in the NAV-overstating direction. **The addition, not the verbatim text, was where
the falsifiable content lived.**

**`2dc8e53` → `6b973bf`. GREEN.**

- **Diff is one comment string.** `git diff -U0 2dc8e53 origin/feature/self-267 -- <migration> |
  grep -E "^[+-]" | grep -vE "^(\+\+\+|---)" | grep -vE "^[+-]--"` returns **exactly two lines** —
  the old and new `comment on function pfin.fn_ytd_paid_per_jurisdiction` literal. Zero function-body
  lines, zero DDL, zero ACL, zero index. Independent corroboration of the reported body md5 by an
  instrument that does not depend on locating the `$$` delimiters.
- **C1 landed byte-verbatim**, confirmed by fixed-string (`grep -F`) match of the full paragraph
  against the file at `origin/feature/self-267`.
- **Architect's two added factual claims were measured against the tree, not accepted.** Both hold,
  and one holds more strongly than claimed:
  - *"the `058` close gate REFUSES an account holding a non-zero cash balance (leg 2 of 3)"* —
    `058` raises `'account closure blocked: account % holds a non-zero cash balance (% native) as of
    % (leg 2 of 3: cash)'`. The leg count is **byte-accurate to the raise message**, not a
    recollection.
  - *"`049`'s as-of predicate drops a closed account from the §2.1.5 leaf set whatever its
    designation"* — `where (acc.closed_at is null or acc.closed_at::date > p_as_of)` sits inside
    `pfin.fn_account_unrealized_gl` (`059`, the live re-issue of `049`) and is **ungated**. It is
    additionally true of `fn_compute_nav` under `p_active_only`, so **closing moves the headline and
    the foot together and opens no new divergence** — a strengthening the clause does not claim.
- **CI at `6b973bf`:** `pgTAP RLS battery (supabase test db)` **SUCCESS**; RT-22 / RT-26 / RT-27 /
  TBC / TBC-node / gitleaks / secrets-manifest CI-production non-overlap all SUCCESS. The web-app,
  live-DB and two npm-audit lanes had not reported — the npm-audit fence is a repo-wide block being
  fixed separately and its change comes to Sec on its own.

### Open, non-blocking — recorded so none reads as discharged

1. **The drain METHOD decides whether the rollover preserves the invariant, and the comment does not
   say so.** Step 1 now instructs the user to drain the ledger before closing it. Only an
   Expense-class drain preserves the invariant; a transfer-drain lands the cash on an in-set leaf and
   NAV rises by the full amount. **I do NOT require this in `102`'s comment**, for two reasons
   stated so the non-requirement is not mistaken for an oversight: the mechanism is already carried
   by the clause immediately below it (*NAV rises by the whole of the cleared ledger's balance*), one
   inferential step away; and unlike C1 — which fired when the user followed the recommended
   procedure **correctly** — this fires only when the user records a transfer that did not happen,
   which the model is faithfully reflecting rather than causing. Owner: SELF-266 §2.5.3 copy plus the
   booked V2 settle/drain affordance.
2. **⚠ `E19b` exists on no pushed ref.** The residual in (1) was reported to me as *"ruled a product
   question (E19b)."* Measured on `origin/meta/v14-execution-log` @ `edfca6a`: the log's headings run
   `E1 … E20` with **no `E19b`**, and `grep -n "E19b"` over the file returns nothing. E14–E20 are now
   pushed and **E19 is present, accurate, and correctly records its own C1 correction** — the earlier
   E14 finding at §8 is fully discharged. But the ruling that disposes of (1) is **not recorded**,
   and "routed to E19b" reads as discharged while nothing holds it. `102` cites neither `E19` nor
   `E19b`, so no artifact ships a dangling pointer.
3. **My own error, prose only.** My B1 tightening was spliced with the original trailing comma
   consumed, which is correct — but my replacement introduced its own `so`, so the sentence now reads
   *"… cannot simply be added alongside the old one, **so** from the SECOND tax year onward …"* after
   an earlier *"…at a time, **so**…"*. Meaning is intact; it is a run-on I caused. Not worth a commit
   on its own; fold into any later touch of this comment if one occurs.
4. Carried from the AMBER above and unchanged: B3's never-render-NULL-as-`$0` watchers are owed at
   SELF-262 / SELF-266 and I have **not** verified them; the manual→linked designation drift is
   booked to Architect; `(L9a)`'s missing `pg_namespace` filter is booked to QA.

**Verdict: GREEN at `6b973bf`.** No veto, no blocking finding, no ADR amendment owed, no §10 ledger
movement, no Decision 3 instance, no `SECURITY DEFINER` allowlist change, no CI fence change.
