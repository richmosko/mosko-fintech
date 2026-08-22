# V1.3 (§2.3 Cash flow) — re-derived AC sets, landing-ready

**Baseline sha: `0491830`** (`origin/main`, 2026-08-22). Every schema identifier below was verified against the tree at this sha per **BACKLOG §7.19 AC 3** (*"every AC … that copies a schema identifier is re-verified against DDL … the sweep's baseline sha is recorded in the amendment list"*) and **AC 5** (the amendment list carries the baseline sha).

**Scope:** 14 issues — SELF-245/246/247 (promoted into V1.3 at sitting item 1) and SELF-248…258.

**How to apply:** each `## SELF-NNN` block below is **the text the issue will carry**. Title lines replace the issue title; each `### Acceptance criterion` list **replaces** the existing list in full — it is not an addendum. Apply verbatim.

**Sources merged.** Schema wording, signatures, predicates and gates: Architect (`architect-findings.md`). Product wording, PRD-traceable copy, and the drafted `+AC`s on 249 / 251 / 254 / 256: **PM (`pm-findings.md`)**, credited inline as *(PM)*. Sec's binding conditions on the SELF-248 fence: *(Sec)*.

---

## ⚠ Deltas between the two source files — flagged, not silently merged

Per the landing instruction, Architect's schema wording governs on conflict. Two conflicts and one citation defect:

1. **The D-1 reader's class-set — CONFLICT.** PM's D-2 memo (option B tradeoff) says the ruling means *"the D-1 shared reader takes a class-set for this surface (trivial under (iii))."* **It must not.** The reader emits classifiable-but-**unclassified** items with `cat` NULL, and a `where cat = any(p_cats)` filter **drops every NULL-`cat` row** (`NULL = any(...)` is never true) — which would take the S-2 banner's `N` to **zero on every surface, silently**, destroying the one-source property the extraction exists for. **Resolved: no class-set parameter.** The reader filters nothing by class; each surface partitions the emitted rows, and the section vocabulary lives in one shared constant module. PM's *product* conclusion (middle section = Transfer ∪ Equity, label "Other Cash Flows") is unaffected and is carried below.
2. **SELF-249's picker-disable trigger — CONFLICT (wording).** PM's drafted +AC disables the picker *"on rows outside the cash-flow domain (e.g. AcctSetup)"*. **`AcctSetup` is not a Cat and cannot be tested for.** The testable predicate is `classifiable()` (S-1). PM's copy constraint and cross-domain affordance text are carried **verbatim**; only the trigger is restated in schema terms.
3. **Citation defect, non-blocking.** PM's routing note cites *"ADR-044 Amendment 4 `::date`"*. **Measured: ADR-044 (`DECISIONS.md:1395–1498`) contains no Amendment section and no `::date` guidance.** The phrase `timestamptz::date` appears in its *hazard* paragraph describing the existing comparison — two real things wrongly paired. The ruled boundary form is the **half-open** `created_at < (D + 1)` (D-9), preferred over a `created_at::date <= D` cast because the cast is non-sargable and would forfeit any index on that column. It appears only in PM's routing note, not in any AC text, so nothing below inherits it.

---

## SELF-245 — `is_tax_payment` on the posting-prototype pair + F/CTO marking (§2.3.4)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title (re-scoped, sitting item 16 + PM concurrence):** *§2.3.4.c — `is_tax_payment` marker on the posting vocabulary + F/CTO marking pass (cash-flow seed half discharged at `041`/`084`)*

**Scope note (carry into the description):** the original seed deliverable is **already on `main`**. `041` seeded 27 cash-flow default rows in the ratified 5-class vocabulary (Expense 12 · Revenue 7 · Trade 4 · Transfer 4 · Equity 0) and `084` relocated them to `pfin.posting_prototype_default`, per-user copies carrying their original ids. The four-Cat vocabulary (`Income`/`Expenses`/`OtherCF`/`AcctSetup`), the `domain` column and `UNIQUE (users_id, domain, cat, sub_cat)` are all retired. What remains is the `is_tax_payment` marker and its population.

### Acceptance criterion

1. Migration adds `is_tax_payment boolean not null` — **no DEFAULT, no CHECK** — to **both** `pfin.posting_prototype` and `pfin.posting_prototype_default`. Order: add nullable → total backfill → `set not null`. The absence of a DEFAULT is what makes the column fail-closed: every INSERT must state the value.
2. Migration seeds two rows into `pfin.posting_prototype_default`, closing the Equity gap the §2.3.3 "Other Cash Flows" section depends on:
   - `Equity` / `Contribution` — `tax_relevant = true`, `tax_character = NULL`, `is_tax_payment = false`, `notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory'`
   - `Equity` / `Distribution` — `tax_relevant = false`, `tax_character = NULL`, `is_tax_payment = false`
   `tax_relevant = true` on Contribution is a **flag-for-review**, not a determination — the notes clause is what makes it honest and is part of the row, not a comment on it.
3. Migration **backfills already-provisioned users**: both new prototype rows are inserted into every existing `pfin.posting_prototype` row-set, and `is_tax_payment` is set on all existing rows. First-access provisioning **cannot** deliver either — `provisionCashflowPrototypes` is existence-guarded (`if (existing) return`), so a user with any prototype row never receives a later default-set addition. `077` is the precedent.
4. Migration header states the **ADR-057 provisioning-reach decision once, covering column and seed together**: this change reaches already-provisioned users **by explicit backfill**, because first-access provisioning cannot deliver it.
5. **Paired app-source change (same PR):** the cash-flow provisioning column set in `api/src/lib/server/queries/taxonomy.ts` is widened to include `is_tax_payment`. Without it the provisioning INSERT proposes NULL against a NOT NULL column and the branch — which is **fail-soft** — leaves a fresh signup with **zero** cash-flow prototypes and only a server log line. The same hazard was caught once already when `085` added `element` on the asset side.
6. **F/CTO marking pass:** tax-payment Sub-Cats get `is_tax_payment = true`. The enumeration covers **Expense-class prototypes only** — the two Equity rows enter pre-marked `false` and are not F/CTO's to enumerate. The enumeration principle is stated at marking time (estimated-tax and withholding payments; property-tax treatment decided explicitly).
7. `comment on column` on **each** of the two columns, **scoping the flag's meaning to Expense-class prototypes**, so a later unscoped reader does not read `false` on a non-Expense row as evidence the question was asked and answered for that class.
8. **§2.3.2's rollup still INCLUDES tax-payment Sub-Cats — only §2.3.4 excludes them.** *(PM — prevents the exclusion bleeding across surfaces.)*
9. QA battery (rides this migration): both seed rows present with `is_tax_payment = false` · a user provisioned **before** the migration has both rows after it · **a fresh signup receives the full cash-flow set including `is_tax_payment`, asserted by ROW COUNT** — the provisioning branch fails soft, so a broken path returns cleanly with zero rows and no error · `Equity` rows absent from the §2.3.4 expense series · the §2.3.3 "Other Cash Flows" section non-empty on both halves. `pg_prove`, never bare `psql`.

**STRUCK as discharged** (recorded so the strike is not re-litigated): the original AC2 (seed four Cats with `domain='cashflow'`), AC3 (Sub-Cats), AC6 (idempotency via the retired UNIQUE) — all discharged at `041` + `084`. Original **AC4** (`tax_relevant`/`tax_character` for every cash-flow Sub-Cat) is **struck and deferred to V1.4** (§2.5.1 fuel; PM's mid-milestone tax inventory session is booked at close-out).

### Sec gate
**JOINT-REVIEW MANDATORY.** New column on the posting vocabulary, read by a money-path filter (§2.3.4), plus an ADR-057 provisioning-reach decision. Not a §10 trigger; **ADR-011 Decision 3 family +0** — neither column is FK-shaped (stated per column; `posting_prototype_default` carries no `users_id` at all). No new RLS policy, grant or function; the SECURITY DEFINER allowlist is untouched (read ADR-011 Decision 9 live).

### Dependencies
**Upstream:** none blocking. **Downstream:** SELF-255 (**hard gate** — AC6's marking pass must complete before §2.3.4 ships; an unmarked column means every tax-payment Sub-Cat silently enters the discretionary-expenses chart). **Dispatch position:** second, after SELF-246.

**Durable record:** a new ADR carries this decision (placement · fail-closed shape · the ADR-057 reach precedent · the SELF-255 gate); the migration header carries the authoring-time measurement trail.

---

## SELF-246 — `pfin.cashflow_target` settings table (Lock 14 family)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged. **Shape:** the Wave-4 ratify ("Option B with internal C" — one row per user, two named scalar columns, `UNIQUE(users_id)`) is **confirmed as ratified** (sitting item 17); the DDL below is a correction of the issue's specification, not a reshape.

### Acceptance criterion

1. Migration creates `pfin.cashflow_target`:
   - `id bigint generated always as identity primary key`
   - `users_id uuid not null default auth.uid() references auth.users (id) on delete cascade` — the `default auth.uid()` is load-bearing: it lets an authenticated INSERT omit the column and still pass the WITH CHECK
   - `income_target_annual numeric(20,4)` — nullable until the user sets one
   - `expense_target_monthly numeric(20,4)` — nullable until the user sets one
   - `created_at timestamptz not null default now()`, `updated_at timestamptz not null default now()`
   - `unique (users_id)` — one row per user; the `ON CONFLICT` target for the UPSERT write
2. **Two-sided CHECK on each amount column**, and the reason is stated in the migration header: a one-sided `>= 0` **admits NaN**, because NaN sorts above every non-NaN numeric. Form: `check (x is null or (x >= 0 and x <> 'NaN'::numeric))`, using the explicit-literal idiom of `014` / `053`. No invented upper bound — a dollar target has no natural ceiling, so `074`'s percentage bound is not copyable here.
3. `BEFORE UPDATE ... FOR EACH ROW EXECUTE FUNCTION pfin.fn_refresh_updated_at()` (the shared `001` trigger helper).
4. **RLS: four policies — SELECT, INSERT, UPDATE, DELETE — each `users_id = auth.uid()` AND-ed with the `025` aal2 step-up backstop conjunct, copied verbatim.** `pfin.cashflow_target` is a sensitive tenant-owned `pfin` table and is not one of `025`'s named exclusions.
5. **The DELETE policy ships with its own tenant clause and is never omitted** (SD-22 standing constraint): *no DELETE policy in the Lock-14 family may be trimmed, weakened, or omitted on the reasoning that the SELECT policy already covers it — that reasoning is confirmed false, not merely unproven*, measured by QA on `074` with a complementary corrupt-the-control pair.
6. Grants: `grant select, insert, update, delete on pfin.cashflow_target to authenticated`. Anon zero-grant (pfin schema USAGE is authenticated-only); service_role ungranted by construction (`008` grants per table, no default privileges).
7. **Unset is NULL, never a stored `0`** *(ruled sitting items 19 + 19a)*. A stored `$0` is a target — *"I intend to spend nothing"*; absence is *"I have not set one."* **The write is always an UPSERT setting the column to NULL — never a row DELETE.** ⚠ The SELF-242 precedent's *verb* does not transplant: `planning_target` is keyed per (user, Sub-Cat) so unset is a row DELETE, but this table carries **two independent scalars in one row**, and a row DELETE would unset **both** — a user clearing their income target would silently lose their expense target.
8. **Reader obligation, stated here because the writer can only deliver half of it:** a row that exists with both columns NULL and a row that does not exist **must never carry different meanings** — both are *"no targets set"*. Both states are reachable (never opened the editor vs set-then-cleared) and they arrive as **different result shapes** (zero rows vs one row of NULLs). Every reader treats them identically; see SELF-250 AC6.
9. UPSERT-in-place; settings are not audit-class and carry no edit-history rows (ADR-011 Decision 18).
10. Forward-compat fence: no JSONB columns; two named typed columns only.
11. **SD-22's obligations are discharged by this PR** — the matrix row already carries them and says so (*"NOTHING IN THIS CELL IS BUILT — every clause is an OBLIGATION ON THE V1.3 IMPLEMENTING PR"*). SD-22 was assigned to `pfin.cashflow_target` on 2026-08-16; **this issue does not create an SD entry.**
12. QA two-tenant pgTAP battery, `pg_prove` only: cross-tenant read/write/delete fail closed · owner reads own row · the **DELETE-policy leg written to isolate that policy's own clause** — omit the column filter, or corrupt both clauses and vary them independently, because a cross-tenant DELETE assertion written *with* a `WHERE` is satisfied by either policy · NaN and negative rejected on both columns · unset writes NULL and round-trips as NULL.

**STRUCK:** original AC1 (draft the ADR-011 D18 4→5 amendment) — **already landed on `main`**; the AC becomes *confirm D18's amended text names `cashflow_target`*. Original AC7 (new SD entry) — superseded by the 2026-08-16 SD-22 assignment. Original AC5's *"per Decision 3 family"* attribution — **struck as a mis-citation**: a `users_id → auth.users` tenant anchor is not a Decision-3 instance, and this table carries **no FK-shaped column** beyond it. **Family +0; no label claimed.**

### Sec gate
**JOINT-REVIEW MANDATORY.** Lock-14 family table: RLS + the `025` aal2 conjunct + the SD-22 DELETE-policy constraint. ⚠ **Carry the unset-mechanism deviation into the review explicitly:** Sec ruled the *principle* on the SELF-233/242 arc with a **row DELETE** as its mechanism, and this table's wide-row shape makes that verb wrong. Present it as a deviation from their own precedent rather than letting them meet it later as an unexplained divergence.

### Dependencies
**Upstream:** none blocking (`fn_refresh_updated_at` shipped at `001`; the SELF-233 hardening layer exists at `api/src/lib/server/validation/numeric.ts`). **Downstream:** SELF-250 (reads targets), SELF-252 (the editor). **Dispatch position: FIRST** — it has no upstream of its own and unblocks the most.

---

## SELF-247 — Lock 15 as-of-date app-layer fence (§2.3.3)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged. **Framing correction (carry into the description):** §2.3.3 is **not** the first surface to validate a client-supplied `as_of` — `api/src/lib/server/schemas/allocation.ts` + `userSuppliedAsOf` already exist for §2.2.2/§2.2.3. ⚠ **But no route wires them**: all four route loaders pass `serverTodayAsOf()`, and `api/src/routes/allocation/+page.server.ts:49` states *"NO `as_of` QUERY-PARAM SUPPORT YET."* The capability is built and unreached; this issue bounds it **before** it becomes reachable.

### Acceptance criterion

1. The existing shared as-of schema is **renamed surface-neutral and moved to its own module** — it now serves §2.2 and §2.3, and a schema named for one consumer sitting in that consumer's file is how a second consumer acquires a second copy. `resolveAllocationAsOf` moves with it; existing §2.2 call sites re-point. No behaviour change for them **except** the new bounds.
2. **Floor:** a single exported constant `= '2015-12-01'`, **with its derivation in the comment** — the earliest imported NAV history point (*"Dec-2015 NAV anchor"*, `DECISIONS.md:4666`; PRD Appendix B flag (c) at `:860`, which also records that **three of §2.1.3's five delta horizons are unsatisfiable at launch without those rows**; `api/src/lib/nav-boundary.ts:13`). Below it no NAV series exists. ⚠ The comment must also state that applying a NAV-derived floor to a **cash-flow** as-of is **a deliberate uniform bound, not a derivation** — §2.3 reads `account_trans`, and transactions can legitimately predate Dec-2015.
3. **Ceiling: INJECTED, never embedded.** The schema is a factory taking the already-resolved `D`; the caller passes the value it resolved once per request from `pfin.fn_server_today()` (ADR-044 Decision 2's resolve-once-and-thread rule). The clock's provenance — the **database** clock — is named at the constant. ⚠ **Any `new Date()` inside the validator is a defect, not a shortcut**: that is the Node clock, and it re-opens the two-clock hazard ADR-044 exists to close, with up to 26 hours of boundary-day disagreement between the validator and the query it guards.
4. Predicate: `FLOOR <= as_of <= D`, **both bounds inclusive**, evaluated on the already-shape-validated ISO string; out-of-range returns a field-level 400 in the SELF-233 structured-error shape with **user-meaningful copy** — this is V1's only user-supplied date, and the 400 path should be UI-unreachable because SELF-254's picker constrains the range, but the message must still read as an explanation. *(PM)*
5. The §2.3.3 endpoint consumes the schema for its optional `as_of` query parameter; absent → `pfin.fn_server_today()`, threaded, never defaulted in-function.
6. **AC3 of the original issue — the dual-column filter — is DISCHARGED by D-1**: it lands inside the shared §2.3 reader, written once, where `created_at` is available. This issue keeps only the app-layer validation half. ⚠ The predicate the reader writes is the **half-open** `transaction_date <= D AND created_at < (D + 1)` — see the ADR-011 Decision 19 amendment.
7. Adversarial battery: negative / future / out-of-range-past / non-date / SQL-injection-shaped / type-coerced / locale-formatted all rejected with a structured error. **Plus the two inclusive-boundary legs — exactly-floor accepted, exactly-`D` accepted** — which matter as much as the rejections, since an off-by-one there silently refuses today's own as-of.
8. The server-derived-only convention for §2.6 paths is documented by **extending the existing** `api/src/lib/server/validation/README.md`, carrying ADR-011 Decision 19's clause verbatim rather than paraphrasing it.
9. Naming: the parameter is `p_as_of` (the shipped §2.1/§2.2 convention), **not** Lock 15's `p_data_as_of`, which names a helper that never existed in that shape. The choice is settled once in the amendment-batch ADR and applied to both §2.3 signatures in one edit. *(PM + Architect)*
10. RT-25's catalog state is **verified before acting**, not assumed absent. ⚠ RT-25 is neither CI-fenced nor a §10 catalogued instance; adding or moving it would be a fence-boundary or ledger change respectively, and **neither is in this issue's scope**.

### Sec gate
**JOINT-REVIEW MANDATORY.** Parameter fence on a multi-tenant read; RT-25.

### Dependencies
**Upstream:** none blocking. **Downstream:** SELF-253 (consumes the validator). **Dispatch position:** third. Internal sequencing within the issue is build-time discretion.

---

## SELF-248 — §2.3.1.a Classify backend + recurring-vendor inference

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged. **Mechanism correction (carry into the description):** `pfin.account_trans.user_subcat_id` does not exist and cannot. `004`'s `fn_account_trans_block_mutation` raises on **UPDATE and DELETE for every role including service_role, with no column discrimination** — so the drafted justification (*"Lock 10 freezes financial-shape columns; classification is metadata-mutation"*) is **false against ADR-011 Decision 14**, not merely stale. The ratified carrier already ships: the mutable 1:1 annotation overlay `pfin.account_trans_annotation` (`023`, full authenticated CRUD), whose `sub_cat_id` FK re-targeted to `pfin.posting_prototype` at `084`, with reclassification history at `031`.

### The S-1 classifiability predicate — cited by five issues, defined once here

```
classifiable(row) := transaction_type = 'standard'          -- M1 (030:153)
                 AND security_id IS NULL                    -- M2 (084:1233 biconditional)
                 AND split_count = 0                        -- M4 (the split parent; children carry the categories)
                 AND is_reverse = false                     -- E1 (a)
                 AND (annotation IS NULL
                      OR annotation.journal_id IS NULL)     -- M3 (033:403)

in_queue(row)    := classifiable(row) AND effective_sub_cat_id IS NULL
```
…plus, at the child grain, every `pfin.account_trans_split` child with `sub_cat_id IS NULL`. The queue's unit is therefore **an unsplit transaction OR a split child** — "item", not "transaction".

### Acceptance criterion

1. `POST /api/transactions/:id/classify` **UPSERTs `pfin.account_trans_annotation`** on `trans_id` — INSERT when no annotation row exists, UPDATE of `sub_cat_id` when one does. The immutable ledger is never written.
2. Payload `{ sub_cat_id: number }` — `posting_prototype.id` is **bigint**, not UUID. Schema is Zod `.strict()` with `z.coerce.number().int().positive()`, `users_id` never read from the client (the `classification.ts` precedent). ⚠ A bigint crosses the wire as a **string**; the contract states which side coerces.
3. **Lock 10 is not violated because the ledger row is not written.** Integration test asserts a classify call leaves the `pfin.account_trans` row byte-identical, and that a direct UPDATE attempt raises.
4. **The endpoint REFUSES any write where `classifiable()` is false** — all four mechanical rules **plus `is_reverse` rows** — returning a typed error rather than writing an annotation that is either never read (M1, M4) or **actively wrong** (M3).
5. **Split parents:** refused per AC4. **Reversing a split parent is refused at the edit path**, and ⚠ **the refusal message states the cost**: *"this transaction is split; removing the split will discard its N line categories, which cannot be recovered."* Measured: `unsplitTrans` is a bare DELETE of the whole child set, and `031` has **no** split-child history table — the loss is unrecoverable, and a remedy that is lossy without saying so is worse than a refusal with no remedy.
6. Cross-tenant and cross-vocabulary rejection is **already DB-enforced** and is not re-implemented: the FK to `posting_prototype` makes a storage-side id unreachable, and `fn_account_trans_annotation_matched_sub_cat` (re-targeted at `084`, chain-resolved via `trans_id → account_trans.account_id → account.users_id`, NULL-safe fail-closed) refuses a cross-tenant prototype. The endpoint's job is to surface the raise as a 400.
7. `pfin.fn_suggest_subcat_for_vendor(p_vendor text) RETURNS bigint` — SECURITY INVOKER, STABLE, `set search_path = ''`. **No tenant parameter**: `pfin.account_trans` has no `users_id`, and tenancy resolves through RLS on the account chain. Returns the `sub_cat_id` of the most recent annotation on a prior transaction with matching `vendor`. **Ordering and matching are defined, not implied** *(PM)*: recency by the **annotation's** `updated_at` (not `transaction_date`); matching is exact, case-insensitive, on `account_trans.vendor`, and the AC states whether whitespace/punctuation normalize.
8. Null-safe: NULL when no prior matching vendor history; the UI handles NULL.
9. The manual-entry path's existing `fn_create_manual_trans(… p_sub_cat_id …)` (`038`) and this endpoint resolve to the **same** annotation row; this issue adds no second write path.
10. **DB fence (Sec-ruled option C, F/CTO-confirmed at sitting item 15) — a NEW function and trigger, not an edit to `084`'s:**
    - **Invariant:** `journal_id IS NOT NULL` ⇒ resolved `posting_prototype.cat NOT IN ('Revenue','Expense','Equity')`. This is exactly the fall-through set of `084:869–872`'s ordered `CASE`, derived from the defect rather than chosen. ⚠ **Not** "refuse a non-`Transfer` cat" — a `transfer_in_kind` journal's legs are security rows forced to `cat='Trade'` by the `084:1233` biconditional, so that formulation would refuse every in-kind transfer.
    - **Scoping — a STATE predicate on NEW, valid on both ops:** `before insert or update on pfin.account_trans_annotation for each row when (new.sub_cat_id is not null and new.journal_id is not null)`. ⚠ A transition-scoped `WHEN` referencing `OLD` is doubly wrong: a `WHEN` on `INSERT OR UPDATE` **cannot reference `OLD` at all**, and it would leave *classify-then-attach* open — that order changes only `journal_id`, never fires, and reaches the defect state.
    - **Placement:** its own `fn_..._journaled_cat_fence`. `084`'s trade-constraints function is not edited — it was re-targeted once already by a catalog-measured fan-out and carries a COMMENT that ships to `pg_description`.
    - **Sec's seven binding conditions:** (1) NULL-safe fail-closed — unresolvable prototype → `raise`, never a silent skip; (2) SECURITY INVOKER + `set search_path = ''`, no DEFINER, allowlist unmoved; (3) paired pgTAP battery under `pg_prove` covering **both orders** — classify-then-attach AND attach-then-classify — plus `lives_ok` controls for attaching a `Transfer`-classified leg and a `Trade`-classified in-kind leg, and a corrupt-the-control pair on the fence itself (⚠ a battery testing only one order cannot distinguish this fence from the transition-scoped one); (4) **existing-violation count reported in the migration PR** — rows with `journal_id is not null` and resolved `cat in ('Revenue','Expense','Equity')`; **non-zero → back to Sec before the fence lands**; (5) the app guard still ships in full, and the function COMMENT states **why M1/M4 stay app-layer** (measured never-read via P3's `where` at `084:885–886`) so a future reader neither "completes" the fence nor deletes it as arbitrary; (6) the UX consequence is named — attaching a journal to an already-Revenue/Expense/Equity-classified leg now fails, the frontend surfaces *reclassify-then-attach*, and the endpoint's typed error and the trigger's raise are distinguishable; (7) the fence lands at this PR under joint review.
11. Multi-tenant safety verified at SELF-257.

### Sec gate
**JOINT-REVIEW MANDATORY.** New function + a write path over a Decision-3-fenced column, plus the AC10 fence (ADR-011 D2 surface — financial-correctness data).

### Dependencies
**Upstream:** SELF-246 · SELF-245 · SELF-247 (dispatch order only). **Downstream:** SELF-249, and every §2.3 rendering surface.

---

## SELF-249 — §2.3.1.b Classify UI (inline on transaction lists)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. Transaction-list views gain a per-row Sub-Cat picker column.
2. Suggested-default rendering: rows with no override show the **`provider_category`** hint (`017:234`) in muted/ghost style; rows where `fn_suggest_subcat_for_vendor()` returns non-null show that suggestion muted; rows already classified show the current value solid. ⚠ Carry `017`'s own constraint verbatim: *"IMMUTABLE display hint only … all txns land Unsorted; NO auto-map / NO `provider_category`→`sub_cat` routing in V1."* The hint is a render, never a write. **Provider-agnostic wording throughout — "provider category", not "Plaid category"** *(PM, per ADR-037 and the PRD's own "provider's own category")*.
3. Click-into opens a cascading Cat × Sub-Cat picker sourced from `pfin.posting_prototype`. **No `domain` filter** — the column was dropped at `084` and the table *is* the domain.
4. Submit POSTs `{ sub_cat_id }` to SELF-248; success updates the row in place; failure surfaces an inline error.
5. Manual transaction entry inherits the same picker.
6. **Picker scope** *(PM's +AC, trigger restated in schema terms per delta 2):* the picker offers cash-flow posting-prototype buckets only. **On any row where `classifiable()` is false the picker renders disabled**, with affordance text pointing cross-domain corrections to the §2.4.3 edit / reverse-and-replace flow — the picker never moves a transaction across domains. **Copy constraint:** picker and queue copy **MUST NOT** promise that classifying a transfer makes it "cancel out" — a journal-less `Transfer` falls to **Suspense**, not a clean offset. *(PM, verbatim.)*
7. A split parent's row renders its **children's** Sub-Cats read-only and routes any edit to the existing §2.4.3 split editor; no parent-level picker is offered. The route target already exists (`038` Part A), so this is a link, not a build.
8. **Provenance carry — notes-rendering revival condition (generated at the D-3 seed ruling, lands here):** if this picker renders prototype `notes` as a description or tooltip, the `Equity / Contribution` seed row's note — *"potentially deductible; resolve per account type at the V1.4 tax inventory"* — becomes **user-visible internal-process language** in a field whose siblings are user-facing descriptions. Measured at `0491830`: no component or settings route renders `notes` today, so the mismatch is dormant. **If this issue renders notes, re-phrase that row's note for a user audience or move the review-flag off a user-facing field.**

### Sec gate
Not mandatory — UI over an already-fenced endpoint.

### Dependencies
**Upstream:** SELF-248. **Downstream:** SELF-250, SELF-253, SELF-255 (all consume classified items).

---

## SELF-250 — §2.3.2.a Cross-account rollup backend (+ the shared §2.3 reader)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title (scope note):** this issue also lands **the shared §2.3 reader** — V1.3's foundation piece, ruled at D-1 (iii). The reader is provisionally named `pfin.fn_cashflow_items(p_as_of date)`; **the name is not ratified and is fixed at implementation.**

### The shared reader — contract

SECURITY INVOKER (Lock 11 default; no DEFINER proposed), `stable`, `set search_path = ''`. Tenant isolation is **inherited** from RLS on `pfin.account` / `account_trans` / `account_trans_annotation` / `account_trans_split` under the caller's own session; a cross-tenant caller gets zero rows and fails closed. **No tenant parameter.** Input `p_as_of date`, threaded by the app, never defaulted in-function.

Emits **item-grain rows** over the `classifiable()` set — classified and unclassified alike: `item_kind` (`'transaction'` | `'split_child'`) · `item_id` · `trans_id` · `account_id` · `transaction_date` · `sub_cat_id` (**NULL = unclassified**) · `cat` · `sub_cat` · `amount_net` · `in_month`, `in_q1`…`in_q4`, `in_ytd`.

**The row set is deliberately the union of what §2.3 sums and what the S-2 banner counts.** Mechanically-excluded rows never appear; unclassified ones appear with NULL `cat`. Each surface derives both figures from one query — two counts of "how much is missing" cannot drift if there is only one query.

**The six rules, housed here and nowhere else:** (1) the S-1 predicate; (2) **split XOR** — `split_count > 0` → emit the children, else the parent, never both (`035`/`037`; `029`); (3) **E1 netting** — `amount_net = amount + Σ(amount of rows where replaces_trans_id = this trans_id and is_reverse)`, so a fully-reversed original nets to **0 inside its own Sub-Cat**, invariant under later reclassification; (4) **E3 LEFT JOIN** to `account_trans_annotation` — an inner join silently drops every row with **no annotation at all**, which per `017:188` is most of an ingested book; (5) the **S-3 period grammar**; (6) the **Lock 15 dual-column as-of**, half-open: `transaction_date <= D AND created_at < (D + 1)`.

**The S-3 period grammar** — every window inclusive and truncated at `D`: **Month** = `date_trunc('month', D)` → `D` (a partial month, not the whole calendar month) · **Q1–Q4** = quarter `k` of `year(D)`, `start(k)` → `least(end(k), D)` · **YTD** = Jan 1 of `year(D)` → `D`. The truncated quarters **partition YTD exactly**, so `ΣQ1..Q4 = YTD`. Columns are **not** disjoint (`Month ⊂ its quarter ⊂ YTD`), so a Total row sums **down** each column and never across.

### Acceptance criterion

1. `pfin.fn_cashflow_cross_account_rollup(p_as_of date)` exists and **composes on the shared reader, adding shaping only**. `p_users_id` and `p_scope` are **struck** — ⚠ `pfin.scope` **is not a type and does not exist** (`049` / `067` / `073`); `p_year` is struck (the year is `year(D)`). Returns `sections` (exactly 2 — Revenue + Expense) and `targets`.
2. Sub-Cat rows aggregate the reader's items whose `cat ∈ ('Revenue','Expense')`, grouped by `(cat, sub_cat)`, summing `amount_net` per period column via the reader's membership flags.
3. **Sign convention:** sign-normalized per section (Income inflow-positive, Expenses outflow-positive; contra entries net) — **never `abs()` per row** *(PM wording; Architect rationale)*. ⚠ `abs()` silently flips a genuinely negative bucket — a refund-heavy expense Sub-Cat, a contra-revenue month — to a positive figure. A row whose signed value opposes its section's normal balance renders with its real sign. State the reachable states the way ADR-061 Decision 3 does.
4. Per-section Total row sums each period column independently.
5. Section list is exactly `('Revenue','Expense')`. `Transfer`, `Trade` and `Equity` are excluded from **this** surface; `transaction_type <> 'standard'` rows are excluded by M1, upstream. **Section labels are product labels over the ratified 5-class vocabulary — Income → Revenue, Expenses → Expense — sourced from the shared section-map module, never typed into the function.**
6. `targets` block reads `income_target_annual` + `expense_target_monthly` from `pfin.cashflow_target`; **NULL when no targets are set.** ⚠ **Row-absent and all-columns-NULL are treated identically** — both mean "no targets set" (SELF-246 AC7/AC8's always-NULL-never-DELETE ruling makes both states reachable, and they arrive as different result shapes: zero rows vs one row of NULLs). A handler anticipating only one diverges — most likely by throwing on the absent row, or rendering a caption for a cleared target. *(Provenance: ruled at sitting item 19a on SELF-246; the obligation lands here because this is where it is honoured or quietly broken.)*
7. **No `skip_flag`, no `reconciled_flag`** — neither column exists and both were ruled unbuildable on the immutable ledger (**ADR-032**: a "skip" is a report-view `WHERE` filter, not stored state; `004`'s own comment names both). Reader-side exclusion is expressed by the section's class set.
8. Degenerate states stated explicitly: zero classified items · a Sub-Cat with no rows in a period (**`$0`, a real answer**) · unclassified items (**NULL `sub_cat_id`, excluded from sums and counted by the banner**). Unclassified is not zero and must not silently vanish.
9. Multi-tenant safety + the as-of behaviour verified at SELF-257.
10. Performance target re-derived against the shared reader once it exists; the drafted 500 ms p95 was set against a substrate that no longer exists.

### Sec gate
**JOINT-REVIEW MANDATORY** — the reader is **the** money-path for §2.3. **Brief to carry, assembled:** the **M3 finding** with its `084:869–872` ordered-`CASE` mechanism and what is already fenced (the `084` FK re-target, the Decision-3 matched-tenant trigger, the `084:1233` biconditional) · **the E1 netting invariant**, and that `transactions.ts:157–166`'s soft double-edit guard is now **money-load-bearing** (two reversals on one original would double-net) · **both-correct-not-equal**: §2.3's netted total and the GL's Suspense-offset total are each correct and are **not equal**, because a reversal carries no annotation and its GL contra falls to `Suspense` · the **rule-6 deviation** from Decision 19's verbatim predicate · the `023` full-CRUD grant behind the SELF-248 fence.

### Dependencies
**Upstream:** SELF-249 (classified items), SELF-246 (`cashflow_target`). **Downstream:** SELF-251, and SELF-253/255 which compose on the same reader.

---

## SELF-251 — §2.3.2.b Cross-account rollup UI

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. Page renders 2 sections in order: **Income** → **Expenses** (labels over Revenue / Expense per the §2.3 label-mapping footnote).
2. Section header captions render the section name plus the target value as inline text; a NULL target renders **without** an inline caption. ⚠ Example figures in the issue body are **illustrative only** and must not migrate into the PRD (redaction discipline). *(PM)*
3. Sub-Cat rows render flat — no Cat-group header rows, no Cat-level subtotals.
4. Six period columns: Month (visually emphasized), Q1, Q2, Q3, Q4, YTD.
5. Per-section Total row foots each table. Columns are not disjoint, so the Total sums **down** each column only.
6. **NO** actual-vs-target delta; **NO** colour-coding of overage; static rendering only.
7. "Edit cash-flow targets" routes to `/settings/cash-flow-targets` (SELF-252).
8. Empty states: zero-transaction user → "Add transactions via Onboarding" with onboarding CTA; zero-classified user → "Classify your transactions" with a CTA to the SELF-249 surface.
9. **Unclassified banner** *(PM's +AC, verbatim):* "Unclassified banner (S-2 ruling, F/CTO 2026-08-22; copy per 4a): when N > 0 for the rendered household/year scope, the page renders '**N items unclassified — classify**' with CTA routing to the SELF-249 classification surface; both section Total rows carry a 'partial — N unclassified' footnote, rendered iff N > 0 and computed in the same query as the total; banner and footnote absent at N = 0. N derives from Architect's `in_queue` predicate (architect-findings §5 item 3a) — single source with the §2.3.1 queue. Precedent: V1.2 loud-unpriced posture."
10. **Negative section totals render with their real sign** — the backend no longer `abs()`-normalizes per row, so a genuinely negative section total is reachable and must not be hidden or rendered as positive.
11. Staleness markers consumed from SELF-258.

### Sec gate
Not mandatory — render only.

### Dependencies
**Upstream:** SELF-250, SELF-252 (the Edit route target). **Soft:** SELF-258.

---

## SELF-252 — §2.3.2 Cash-flow targets editor (Settings shell, second occupant)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. `/settings/cash-flow-targets` renders within the SELF-242 Settings shell; nav shows Allocation (V1.2) and Cash-flow targets (V1.3) as enabled; V1.4+ remain placeholders.
2. Exactly two input fields — `income_annual` (currency-formatted) and `expense_monthly` (currency-formatted); both default to the existing `pfin.cashflow_target` row where present, **blank where the column is NULL**. ⚠ **An unset field renders empty, never as `$0`** — a stored `$0` is a target, absence is not, and SELF-251's caption branches on NULL.
3. Zod `.strict()` validates the payload exactly `{ income_annual?, expense_monthly? }`; mass-assignment of arbitrary fields is rejected via the SELF-233 shared layer. ⚠ **The schema and handler MUST distinguish an explicit `null` from an omitted key** — omitted means *leave alone*, `null` means *clear*. A handler treating both as "no change" makes unset unreachable through the UI.
4. Numeric adversarial battery via the shared `api/src/lib/server/validation/numeric.ts` helper: NaN / Infinity / currency-string / scientific-notation / locale-formatted all rejected with a field-level error. ⚠ **This is the RT-23-shaped app-layer half that `074` did NOT deliver** — Sec's own note: *"RT-23 IS NOT SATISFIED BY `074`."* It is owed here and is not inherited.
5. `POST /api/settings/cashflow-target` (at `api/src/routes/api/settings/cashflow-target/+server.ts`) **UPSERTs** `pfin.cashflow_target` on `users_id`, per the Lock 14 UPSERT-in-place pattern.
6. **Explicit unset per field** *(ruled, sitting items 19 + 19a)*: the editor offers an explicit unset that sends `null`, and the write **sets that column to NULL — it is never a row DELETE**. ⚠ The SELF-242 DELETE precedent's *verb* does not transplant: this table carries two independent scalars in one row, and a DELETE would unset **both**, so clearing an income target would silently lose the expense target. See SELF-246 AC7.
7. `updated_at` refresh fires via `pfin.fn_refresh_updated_at()`.
8. Submit redirects to `/cash-flow`, showing the updated inline target captions.
9. Multi-tenant safety per the SELF-242 pattern: writes are user-session-bounded; no `service_role` reach.

### Sec gate
**JOINT-REVIEW MANDATORY** — Lock-14 settings write path.

### Dependencies
**Upstream:** SELF-242 (Settings shell), **SELF-246** (the table — unbuilt until it lands), SELF-233 (write-path hardening). **Downstream:** SELF-250 (reads targets), SELF-251 (renders captions).

---

## SELF-253 — §2.3.3.a Per-account drill-down backend (Lock 15 client-toggle surface)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. `pfin.fn_cashflow_per_account(p_account_id bigint, p_as_of date)` exists and **composes on the shared §2.3 reader**, adding its account filter and section shaping only. ⚠ `p_account_id` is **bigint** (`pfin.account.account_id`, `003:92`), not UUID; `p_users_id`, `p_scope` and `p_year` are all **struck**; `DEFAULT CURRENT_DATE` is dropped — the app threads `D` (ADR-044's zero-round-trip variant stays ruled out).
2. Returns exactly **3 sections, in order: Income → Other Cash Flows → Expenses**, with class sets from the shared section-map module: `{'Revenue'}` · **`{'Transfer','Equity'}`** · `{'Expense'}`. ⚠ The middle section's name is **"Other Cash Flows"** — `OtherCF` is not a Cat and has no successor value; D-2 (B) rules its content as the Transfer ∪ Equity union. `Trade` appears in no section.
3. Account-scoped: only the named account's items; user-scoped via RLS on the reader.
4. **As-of semantics** are the reader's rule 6 — `transaction_date <= D AND created_at < (D + 1)`. ⚠ The **half-open** upper bound is deliberate and deviates from ADR-011 Decision 19's verbatim `created_at <= $1`: `created_at` is `timestamptz` and `$1` a `date`, so the literal form promotes to **midnight** and **excludes every row created on the as-of date itself** — with `D = today`, every transaction the user entered today. See the Decision 19 amendment.
5. Input validation per SELF-247's shared schema: `as_of` outside `[floor, D]` → 400 before SQL invocation.
6. Sign convention, Total foot row and flat Sub-Cat layout as SELF-250.
7. **No `targets` in the output** — targets are aggregate concepts attached to §2.3.2, not to single-account scopes.
8. Section-2 copy carries the honest transfer note: **classifying a transfer does not by itself make it cancel out** — a journal-less `Transfer` resolves to Suspense. *(PM)*
9. Multi-tenant safety + per-account ownership verified at SELF-257.
10. Performance target re-derived against the shared reader.

### Sec gate
**JOINT-REVIEW MANDATORY** — financial calculation plus a client-supplied date parameter on a multi-tenant read (RT-25).

### Dependencies
**Upstream:** SELF-250 (the shared reader), SELF-247 (the validator), SELF-249. **Downstream:** SELF-254.

---

## SELF-254 — §2.3.3.b Per-account drill-down UI

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. Page renders 3 sections in order: **Income → Other Cash Flows → Expenses** (the middle position is deliberate and unchanged; only the label is corrected). Section captions are simple labels — no target captions on this view.
2. Same 6-column structure, flat Sub-Cat rows and Total foot as §2.3.2.
3. **Account selector includes CLOSED accounts.** ⚠ `pfin.account.is_active` was **dropped at `059`** (ADR-042); the model is the dated `closed_at` (`058:74`). Closure is a dated bookkeeping event, and a closed account's drill-down renders its historical cash flow. *(PM's A-6 amendment removes the PRD source of the retired vocabulary.)*
4. As-of-date toggle in the toolbar; default = today; range constrained to `[floor, today]`. ⚠ **"today" must be the same clock the backend uses** — the database clock via `pfin.fn_server_today()`, threaded — or the boundary day is ambiguous by up to 26 hours (ADR-044).
5. Drill-from-§2.3.2 navigation: `from=cross-account-rollup` query param so the back-button returns to SELF-251 with state preserved.
6. A closed account renders a **"Closed"** badge with its closure date, **rendered UTC per ADR-043**. No `inactive` flag exists to read.
7. **Unclassified banner** *(PM's +AC, verbatim):* "Unclassified banner (S-2 ruling; copy per 4a): same rendering as SELF-251's with '**N items unclassified — classify**', scoped to the selected account + year + **the same as-of predicate as its table** — N counts *currently-unclassified* items within that as-of-filtered set, so banner and table agree under a historical as-of (classification state is current-state, not bitemporal); CTA routes to the classification surface filtered to that account. N from the `in_queue` predicate — single source; footnote iff N > 0, same query as the total."
8. Empty state: an account with no items in the rendered year shows "No transactions in [year] for this account."
9. Staleness markers consumed from SELF-258 if applicable.

### Sec gate
Not mandatory — render only.

### Dependencies
**Upstream:** SELF-253, SELF-251 (drill-from origin). **Soft:** SELF-258.

---

## SELF-255 — §2.3.4.a Historical Expenditures backend

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged. ⚠ **This issue carries TWO hard upstream gates** (below); neither is a follow-up.

### Acceptance criterion

1. `pfin.fn_historical_expenditures(p_as_of date)` exists and **composes on the shared §2.3 reader**. ⚠ `p_users_id` and `p_scope` are **struck** — `pfin.scope` is not a type and does not exist. Returns `(month_end date, expense_monthly_nominal numeric, expense_monthly_inflation_adjusted numeric, rolling_12mo_avg_inflation_adjusted numeric)`.
2. **Window:** the trailing **60 month-ends ending at `D`** — a rolling 5-year window, **not calendar-year-aligned** *(PM)*. ⚠ The reader's six period flags do **not** serve this surface; this function consumes the same row set and the same six rules and does its **own** month bucketing off `transaction_date`. Fewer rows where the user has less history; state explicitly whether a month with no expenses emits a **zero row or no row** — a missing row and a zero are different claims on a financial chart.
3. `expense_monthly_nominal` = Σ `amount_net` over the month for reader items where `cat = 'Expense'` **and** the resolved prototype's `is_tax_payment = false`. ⚠ `Trade`, `Transfer` and `Equity` are excluded by the class filter; `AcctSetup` is not a Cat and is excluded upstream by M1. **No `skip_flag`** — the column does not exist (ADR-032).
4. **Inflation normalization composes on the ratified CPI resolver — it does not re-derive one.** `pfin.fn_cpi_u_index_for_period(p_period date)` (`066`, eight columns, exactly one row always, STABLE, INVOKER) is called per month via a lateral, its `cpi_*` provenance columns carried through prefixed (the `067` pattern). ⚠ **There is no "cpi_today".** The basis is **`coverage_through`** — the last period the CPI store actually covers — matching `fn_nav_series_inflation_adjusted` (`067`), the §2.1.2 precedent this story cites. Re-deriving the gap policy locally is what ADR-049 Decision 4 exists to prevent.
5. `expense_monthly_inflation_adjusted` is **NULL — never zero** — when either CPI leg is absent or non-positive, and the CPI provenance columns accompany it so the NULL is legible.
6. `rolling_12mo_avg_inflation_adjusted` = sliding 12-month mean of the **inflation-adjusted** series ending at each row's `month_end`; NULL for the first 11 rows, **and NULL if any constituent month is NULL** — never a silently-short window.
7. Full-household default per ADR-004 Decision B; per-scope filtering is V2+.
8. Multi-tenant safety verified at SELF-257.
9. Performance target re-derived against the shared reader.

### GATES — both hard, both upstream

- **GATE 1 — the marking pass (D-3 / sitting item 2a, ruling (i)).** SELF-245 AC6's F/CTO marking enumeration must be **complete** before this ships. Until it is, every unmarked row reads `is_tax_payment = false`, so a genuinely tax-payment Sub-Cat lands silently inside the "discretionary expenses" chart — a wrong figure with no error and no marker. ⚠ **The gate is a sequencing commitment, not a mechanism**: nothing in the schema prevents this being built against an unmarked column.
- **GATE 2 — BACKLOG §7.14 ships FIRST (D-5 / sitting item 10).** `053`'s CHECK on `pfin.cpi_u_index.cpi_value` is **finiteness-only**, so a poisoned `0` or negative print reaches the deflator. This issue adds a **fourth** consumer of the CPI store; adding it over an un-fenced base table widens a known open hazard. ⚠ **The combined predicate must be FINITE and STRICTLY POSITIVE**, and the new constraint is **ADDITIVE** — `cpi_u_index_value_finite` survives by name. **A bare `> 0` written as a standalone replacement re-admits NaN AND Infinity**, both of which compare TRUE under numeric ordering. Sec's four binding conditions are read live from §7.14's own text.

### Sec gate
**JOINT-REVIEW MANDATORY** — financial calculation (a deflator) over a money-path reader.

### Dependencies
**Upstream:** SELF-250 (the shared reader), SELF-245 (**GATE 1**), BACKLOG §7.14 (**GATE 2**), SELF-249. **Downstream:** SELF-256.

---

## SELF-256 — §2.3.4.b Historical Expenditures chart UI

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. Chart renders on a dedicated route or as a panel adjacent to the §2.3.2 rollup (Visual Designer's call).
2. X-axis: month-end dates over the trailing 5 years. **Y-axis: $ in the purchasing power of `coverage_through`** — ⚠ **not "today's $"**; the basis is the last period the CPI store covers, matching §2.1.2's shipped basis. The chart carries the **dated basis line**: *"CPI-U through {coverage_through}"*.
3. Bar series: `expense_monthly_inflation_adjusted`.
4. Overlay line: `rolling_12mo_avg_inflation_adjusted`, drawn simultaneously (not toggled), visually distinct from the bars.
5. First 11 months render bars but no line; the axis range handles the partial line gracefully.
6. **The `066` consumer rendering rule, carried rather than re-derived:** `cpi_value IS NULL` → render **UNAVAILABLE with a reason** (§2.4.4's *"uncomputable is not stale"*); `is_carried AND period_was_due` → an **informational** carried-ness marker asserting the span, with a cause clause iff `nonpublication_on_record`; otherwise a plain figure. ⚠ **A consumer MUST NOT branch user-visible tiering on `gap_class`** — that column is operator-axis only.
7. User-configurable horizon NOT exposed; chart drill-down NOT exposed; authored-target line NOT exposed (all V2+).
8. Tooltip: month-end + nominal + inflation-adjusted + 12-month rolling average where available.
9. **Unclassified banner** *(PM's +AC, verbatim):* "Unclassified banner (S-2 ruling; copy per 4a): when N > 0 within the trailing 5-year window — **window-scoped only: an unclassified item carries no Cat, so the §2.3.4 Expenses/non-tax filter cannot apply to it** — banner renders adjacent to the chart title (staleness-badge placement parallel) reading '**N items unclassified — any of these may be expenses — classify**' with the same CTA; the copy MUST NOT claim the items are expenses. Chart caption carries 'bars partial — N unclassified' iff N > 0, computed in the same query as the series. N from the `in_queue` predicate — single source."
10. Empty state: zero-expense or zero-classified user sees "Classify your expense transactions to see your historical expenditures" with a CTA to the SELF-249 surface.
11. Staleness markers consumed from SELF-258.

### Sec gate
Not mandatory — render only.

### Dependencies
**Upstream:** SELF-255, SELF-220 (chart library pattern). **Soft:** SELF-258.

---

## SELF-257 — §2.3.5 RLS verification battery (V1.3 close-gate)

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged. **Close-gate: no V1.3 issue closes to the milestone until this battery passes.**

### Acceptance criterion

1. Battery covers every §2.3 backend surface — SELF-248, SELF-250 (**and the shared reader**), SELF-252, SELF-253, SELF-255. ⚠ The legs are **session-based two-tenant**, not parameter-injection: with `p_users_id` struck project-wide, the assertion is that **a cross-tenant caller under INVOKER + RLS sees zero rows and fails closed** (the SELF-244 precedent), not that an injected tenant id is rejected.
2. Per-account drill-down cross-tenant leg: tenant A passes a `p_account_id` (**bigint**) belonging to tenant B → zero rows via RLS on `pfin.account`.
3. **As-of multi-tenant safety:** with the as-of varied across the boundary, cross-tenant isolation holds; the date parameter does not widen the tenant fence.
4. Lock 15 input validation enforced at the route handler before SQL invocation: out-of-range, future and non-date inputs rejected. **Plus both inclusive-boundary legs — exactly-floor and exactly-`D` accepted.**
5. Full-household default verified for SELF-250 and SELF-255.
6. **STRUCK:** the drafted `p_scope = '{personal,trust}'::pfin.scope[]` leg — ⚠ **`pfin.scope` is not a type and does not exist.** Per-scope reporting is V2+; the leg is dropped rather than re-expressed, since `pfin.account.scope` is free text and no V1 surface filters on it.
7. **Sub-Cat forgery legs against `pfin.posting_prototype`** — the `#10` and `#13` matched-tenant fences were **re-targeted at `084`**, so the battery asserts against the posting vocabulary. **Add the leg the re-target created:** a `sub_cat_id` pointing at a **storage-side `user_taxonomy` id** now fails at the **FK**, not at the trigger.
8. Cash-flow target writes: tenant A cannot read or write tenant B's `pfin.cashflow_target` row. ⚠ The **DELETE leg must isolate the DELETE policy's own clause** — omit the column filter, or corrupt both clauses and vary them independently; a cross-tenant DELETE written *with* a `WHERE` is satisfied by either policy, so corrupting one and finding the test green proves the other sufficient, not the corrupted one redundant.
9. **Shared-reader rule legs — one per rule, tested once here rather than three times across the consumers:** the mechanical exclusion set (M1–M4 + `is_reverse`) · the split XOR at **both** grains · a fully-reversed original netting to **0 inside its own Sub-Cat**, and staying there after the original is reclassified · **the E3 case with a fixture that deliberately leaves rows un-annotated** — a fixture that annotates every row cannot catch it · `ΣQ1..Q4 = YTD` (the S-3 partition watcher, which fails immediately under untruncated calendar quarters) · **a row created ON the as-of date is INCLUDED** — the leg that catches the Decision 19 literal-predicate defect, and which no value assertion can catch.
10. SELF-248 fence legs per Sec's condition 3: **both orders** (classify-then-attach AND attach-then-classify), `lives_ok` controls for a `Transfer`-classified leg and a `Trade`-classified in-kind leg, and a corrupt-the-control pair on the fence itself.
11. Sec review pass recorded per the SELF-244 precedent.
12. Forward fence: **no `service_role` reach** in any §2.3 surface; all execute under `authenticated` per ARCH §4.1.
13. **`pg_prove`, never bare `psql`** — a pgTAP plan count enforces only through a TAP-aware consumer; `psql` exits 0 on a failing battery.

### Sec gate
**JOINT-REVIEW MANDATORY** — this issue *is* the RLS surface; the Sec verdict is an AC.

### Dependencies
**Upstream:** SELF-248, 250, 252, 253, 255 (must verify against built surfaces). **Dispatch position: LAST.**

---

## SELF-258 — §2.3.x staleness-framework ramp

*ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22); schema identifiers tree-verified at `0491830`. This AC list REPLACES the prior list in full.*

**Title:** unchanged.

### Acceptance criterion

1. SELF-251 (§2.3.2 rollup) invokes **`pfin.fn_aggregation_has_stale_constituent()`** at SSR and renders `<StaleConstituentBadge>` at section headers when stale items exist. ⚠ **The shipped function takes ZERO arguments** (`046:128`) and returns `table (is_stale boolean, stale_items jsonb)`, SECURITY INVOKER, STABLE — `p_users_id` and `p_scope` are both G4 artifacts and do not exist.
2. SELF-256 (§2.3.4 chart) invokes the same primitive and renders the badge adjacent to the chart title.
3. SELF-254 (§2.3.3 drill-down) invokes the primitive and renders the badge. ⚠ **Account-scoping is not expressible against a zero-argument function.** Either the badge is user-wide on this surface — **stated as such in the AC, so an over-broad marker is a decision rather than an accident** — or `046` gains an account-scoped sibling, which is a migration with its own owner and Sec touch, not an AC clause. **Decide and state which.**
4. Per-row staleness indicator: Sub-Cat rows in §2.3.2 / §2.3.3 whose contributing items include stale-provider-derived entries get a per-row icon + tooltip, per the Wave 2/3 precedent.
5. Badge tooltip lists stale account names with a "Re-authenticate" link to the connection-state view.
6. The ADR-013 D1 annotation lands at the code-consumption sites: *"§2.3.2 + §2.3.4 explicitly named in PRD §2.4.4's staleness-ramp list; §2.3.3 inherits per ADR-013 D1 illustrative-not-exhaustive."*

### Sec gate
Not mandatory — consumes an existing INVOKER primitive.

### Dependencies
**Upstream:** SELF-208, SELF-229, SELF-243 (framework), and SELF-251 / 254 / 256 (consuming surfaces). **Soft:** SELF-207.

---

## Dispatch order

**246 → 245 → 247 → 248 → 249 → 250 → 251 / 252 → 253 → 254 → 255 → 256 → 258 → 257 (close-gate last).**

Gates that cut across it: **SELF-255 waits on SELF-245's marking pass AND on BACKLOG §7.14.** **SELF-252 waits on SELF-246's table.** **SELF-250 lands the shared reader**, so 253 and 255 wait on it regardless of their own positions.

## Sec joint-review map

**Mandatory (9):** 245 · 246 · 247 · 248 · 250 · 252 · 253 · 255 · 257.
**Not mandatory (5):** 249 · 251 · 254 · 256 · 258.

No SECURITY DEFINER function is proposed anywhere in this set; Lock 11 SECURITY INVOKER read-composition is the default for every helper named above.
