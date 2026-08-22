# V1.3 (§2.3 Cash flow) — Architect AC-vs-tree feasibility audit

**Baseline.** `origin/main` at `04918304bb4d9c1b510c658551519cb577dfb7d8` (detached read in the architect worktree). Migrations `001`–`089` on the tree. Every schema identifier below was grepped or read in-file at this sha; no count or identifier is carried from recall.

**Standing.** This pass IS the §7.19 AC-3 discharge for the V1.3 promotion ("every AC in Linear-Backlog issues … that copies a schema identifier is re-verified against DDL … the sweep's baseline sha is recorded"). §7.19 names AC 3 as **not optional** at a milestone-rotation boundary.

**§10 3-axis cross-check** — performed against ADR-011 Decision 4 read verbatim and live before drafting. This memo introduces no catalogued instance, reorders none, changes no layer-attribution, and restates the catalogued list nowhere (Path B — referenced, not copied). No ledger change; not a §10 Sec trigger. ⚠ The §10 CATALOGUED set and the CI-FENCED set (`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`) are different sets and are not reconciled anywhere below.

**ADR-011 Decision 3** — read live. No AC below proposes a new FK-shaped column, so no new family label is claimed here. The one place the issue text *asserts* a D3 fence (SELF-246 AC5) is a mis-citation and is corrected in place; the two D3 fences the §2.3 surfaces actually sit behind (`account_trans_annotation.sub_cat_id`, `account_trans_split.sub_cat_id`) were RE-TARGETED at `084`, keeping their labels — read D3 live for the labels; none is restated here.

---

## 1. Classification summary

| Issue | Surface | Verdict |
|---|---|---|
| SELF-245 | cash-flow seed + `is_tax_payment` | **IMPOSSIBLE** (deliverable partly already shipped — needs a re-scope ruling) |
| SELF-246 | `pfin.cashflow_target` table + Lock-14 amendment | **DRIFT** (severe — the migration as specified does not apply) |
| SELF-247 | Lock 15 as-of-date app-layer mods | **IMPOSSIBLE** (premise falsified by shipped V1.2 code; surfaces a doc-vs-tree conflict) |
| SELF-248 | §2.3.1.a classify backend + vendor inference | **DRIFT** (severe — every AC clause touched; one false claim about a ratified lock) |
| SELF-249 | §2.3.1.b classify UI | **DRIFT** |
| SELF-250 | §2.3.2.a cross-account rollup backend | **IMPOSSIBLE** (read-substrate fork + schema-impossible signature) |
| SELF-251 | §2.3.2.b rollup UI | **DRIFT** |
| SELF-252 | §2.3.2 cash-flow targets editor | **DRIFT** (blocked on an unbuilt table whose own spec is drifted) |
| SELF-253 | §2.3.3.a per-account drill-down backend | **IMPOSSIBLE** ("OtherCF" has no successor class) |
| SELF-254 | §2.3.3.b drill-down UI | **DRIFT** |
| SELF-255 | §2.3.4.a Historical Expenditures backend | **IMPOSSIBLE** (`is_tax_payment` placement + normalization-basis contradiction) |
| SELF-256 | §2.3.4.b Historical Expenditures chart UI | **DRIFT** |
| SELF-257 | §2.3.5 close-gate RLS battery | **DRIFT** |
| SELF-258 | §2.3.x staleness ramp | **DRIFT** |

**CLEAN 0 · DRIFT 9 · IMPOSSIBLE 5.** (14 issues — SELF-245/246/247 promoted into V1.3 by F/CTO 2026-08-22 and audited here on the same terms.)

Zero CLEAN is the headline. All fourteen were drafted 2026-06-03, before `028` (the 5-class enum), before `032`–`039` (the GL), before `048` (account-level Sub-Cat drop), before `059` (`is_active` retirement), before `074` (the first Lock-14 table), and before `084`/`085` (the GL split and `element`). Not one issue survives the substrate it was written against.

⚠ **Two of the three promoted issues are IMPOSSIBLE for the same reason, and it is the opposite of the usual one:** their deliverables are *partly already built*. SELF-245's seed shipped at `041`/`084`; SELF-247's validation layer shipped at SELF-238/240. An AC whose every identifier is falsified reads as "unbuilt" and is the case where that reading is most likely wrong.

---

## 2. The drift generators

Seven families produce ~90% of the individual findings. Amending them once, at the family level, is cheaper than eleven independent rewrites — and it is what stops the same drift re-entering V1.4.

**G1 — The cash-flow vocabulary moved tables and changed values.**
`pfin.user_taxonomy.domain` was DROPPED at `084`. Cash-flow (posting) rows now live in **`pfin.posting_prototype`** (per-user, ids preserved, RLS + `025` aal2 clause, authenticated SELECT+INSERT only) and **`pfin.posting_prototype_default`** (global shared-read). `user_taxonomy` is the storage-classification spine only.
Every AC clause reading `pfin.user_taxonomy` + `domain = 'cashflow'` is schema-impossible. Every such clause is a mechanical re-target: table → `posting_prototype`, and the `domain` predicate is **deleted, not translated** — the table *is* the domain (ADR-058 Decision 4).

**G2 — The Cat vocabulary is `Revenue / Expense / Transfer / Equity / Trade`.**
`posting_prototype_class_chk` (`084`, successor to `028`'s constraint) constrains `cat` unconditionally to those five. **`Income`, `Expenses`, `OtherCF` and `AcctSetup` are not values in the schema and cannot be.** Measured on the seeded default set (`041`, relocated by `084`): 27 cash-flow rows — Expense 12, Revenue 7, Trade 4, Transfer 4, **Equity 0**. The PRD §2.3 prose still names the retired four; that is §7.19 PRD-sweep territory (PM), but the ACs derived from it are ours.
Mapping for the ACs: `Income` → `Revenue`; `Expenses` → `Expense`. **`OtherCF` has no successor** — see §5, decision item D2. `AcctSetup` is not a Cat at all: the non-cash lifecycle discriminator is `pfin.account_trans.transaction_type ∈ ('standard','acct_setup','basis_adjust','corp_action')` (`030`).
The user-facing labels can stay "Income"/"Expenses" via the §3.3 label-mapping-footnote precedent; what must change is the **predicate**, not necessarily the caption.

**G3 — Transaction classification is not a column on the ledger.**
`pfin.account_trans` is immutable: `fn_account_trans_block_mutation` (`004`) raises on **UPDATE and DELETE for every role**, service_role included, with no column discrimination whatever. `pfin.account_trans.user_subcat_id` does not exist and cannot be added-and-updated.
⚠ SELF-248's parenthetical — *"this UPDATE is NOT in scope of Lock 10 immutability (Lock 10 freezes financial-shape columns; classification is metadata-mutation)"* — **is false about a ratified lock, not merely stale.** Lock 10 / ADR-011 Decision 14 blocks the statement, not a column set. Flagging it explicitly because a false safety claim about a lock is exactly the kind of sentence that gets copied forward into a build.
The ratified home already exists and is already write-enabled: **`pfin.account_trans_annotation.sub_cat_id`** (`023`, 1:1 overlay, full authenticated CRUD, PK = `trans_id`) and **`pfin.account_trans_split.sub_cat_id`** (`029`, 1:many receipt split, writes un-dormed at `038`). Both FKs re-target to `posting_prototype` at `084`.

**G4 — `p_users_id` and `p_scope pfin.scope[]` are dead signature idioms.**
**`pfin.scope` TYPE DOES NOT EXIST** — `scope` is a free-text `text NOT NULL` column on `pfin.account` (`003:100`), an ADR-004 Decision B user label, not a type and not an isolation boundary. `059` and `067` both record the parameter's removal in their catalog comments. Per-scope reporting is V2+.
`p_users_id` is likewise dropped project-wide: helpers are SECURITY INVOKER and scope by `auth.uid()` through RLS. Passing a tenant id as a parameter is the shape the V1.2 reconciliation removed from five issues.
Affected: SELF-248 (fn signature), SELF-250, SELF-253, SELF-255, SELF-257 AC6, SELF-258 AC1.

**G5 — `skip_flag` / `reconciled_flag` were eliminated by name, with an ADR.**
ADR-032 (F/CTO-ratified 2026-07-25) kills the skip primitive outright: *"'skip' is presentation logic leaking into the data model."* `004`'s own comment names both columns as ones that "would violate immutability". A reader-side exclusion is a `WHERE cat <> …` at the query layer (ADR-032 Decision 3).
Affected: SELF-250 AC7, SELF-255 AC7. These clauses are **deleted**, not reworded — and the ADR-032 pointer replaces them so the next drafter does not re-derive the flag.

**G6 — split children, and the XOR the reader must honor.**
A parent with children must not be counted twice. `035`/`037` already establish the reader rule: compute `split_count` per parent; `split_count > 0` → count the children, else count the parent. `029` records the precedence as **"a txn is 023-single-categorized XOR split — an M4-GL read rule, NOT DB-enforced"**. Every §2.3 aggregate (SELF-250, SELF-253, SELF-255) must carry that branch explicitly, and every classify surface (SELF-248/249) must say what it does on a parent that already has children. No AC currently mentions splits at all.

**G7 — `pfin.account.is_active` was retired.**
Dropped at `059:700` per ADR-042; the successor is `closed_at timestamptz` (`058:74`) and the as-of predicate is `closed_at is null or closed_at::date > p_as_of`. SELF-254 AC3/AC6's `account.inactive` flag has no referent.

---

## 3. Per-issue findings and proposed amended wording

Wording below is a **proposal for the batch ratify sitting**, not an edit. Nothing has been written to Linear.

### SELF-245 — cash-flow seed + `is_tax_payment` · **IMPOSSIBLE** (re-scope; see decision item D3)

**The finding that decides this issue:** its primary deliverable is already on `main`. `041` seeded **27 cash-flow default rows in the ratified 5-class vocabulary** (measured on the seed INSERT: Expense 12 · Revenue 7 · Trade 4 · Transfer 4 · **Equity 0**), and `084` STEP 3 relocated them into `pfin.posting_prototype_default`, with the per-user copies carried to `pfin.posting_prototype` at their original ids. The provisioning path (`041`, ADR-036 B1) copies the default set into the per-user table on first access. Nothing in AC2/AC3/AC6 is left to build.

| AC | Falsified by | Proposed disposition |
|---|---|---|
| AC1 — add `is_tax_payment BOOLEAN NOT NULL DEFAULT FALSE` to `pfin.user_taxonomy` | G1 — `user_taxonomy` is the **storage** spine since `084`; tax-payment-ness is a property of a **posting prototype**. ⚠ And `DEFAULT FALSE` is the **fail-open** shape the ruling rejects. | **KEEP, re-targeted — ✅ RULED (D3).** Column lands on `pfin.posting_prototype` **and** `pfin.posting_prototype_default`, `085`-shaped: `set not null`, **no DEFAULT** (that absence is what makes it fail-closed), total backfill before the NOT NULL, `comment on column` on each. **Strike `DEFAULT FALSE` explicitly** in the amended text — it is the clause the ruling overturns, and a reader who remembers the old AC must see that it changed. Column type ✅ sub-ruled **A1** at item 2a: `boolean not null`, **no CHECK** — see D3. |
| AC2 — seed cash-flow rows for `Income / Expenses / OtherCF / AcctSetup` with `domain = 'cashflow'` | G1 + G2 — `domain` dropped at `084`; none of those four Cats is an expressible value under `posting_prototype_class_chk` | **STRIKE — discharged at `041` (+`084` relocation).** Record the discharge with the migration citation so the next reader does not re-derive it. |
| AC3 — Sub-Cats populated per F/CTO's existing-system taxonomy | already done at `041` (27 rows, verbatim port) | **STRIKE — discharged.** |
| AC4 — `tax_relevant` + `tax_character` populated per Sub-Cat | already done at `041` (both columns carried on every seeded row; `tax_character` FK to the ADR-024 registry per `011`) | **STRIKE — discharged (✅ confirmed at sitting item 19, measured at `041`).** Note for V1.4: the §2.5.1 ζ-2 consumer reads these from `posting_prototype`, not `user_taxonomy`. ⚠ PM's mid-milestone **tax inventory session is booked as V1.4 fuel** (§7 note at close-out) — **pointer only; the inventory itself does not live in this file.** |
| AC5 — F/CTO marks tax-payment Sub-Cats `is_tax_payment = TRUE` | column does not exist yet | **KEEP — and it is now a GATE, not a follow-up (✅ sub-ruled (i) at item 2a).** ✅ RULED: the **ADR-057 provisioning-reach decision is stated in the migration header** — *a change to the default set must decide SEPARATELY whether it reaches already-provisioned users; never assume first-access provisioning delivers it.* ⚠ **New AC, from D3's seam:** the marking pass is a **hard precondition on SELF-255 shipping**. ⚠ **Scope of the enumeration (item 16):** it covers **Expense-class** prototypes only — the two new `Equity` rows enter pre-marked `false` and are **not** F/CTO's to enumerate (rationale at D3). Until it completes, every unmarked row reads `false`, so a genuinely-tax-payment Sub-Cat lands silently inside the "discretionary expenses" chart — a wrong figure with no error and no marker. The column's fail-closed INSERT shape does not close this; only sequencing does. |
| AC6 — idempotent via `UNIQUE (users_id, domain, cat, sub_cat)` | `domain` dropped; the live uniques are `posting_prototype (users_id, cat, sub_cat)` and `posting_prototype_default (cat, sub_cat)` | **AMEND** to the live uniques — relevant only to the AC5 marking pass, since the seed itself is discharged. |
| AC7 — smoke-test: SELECT own cash-flow rows, not another tenant's | still valid, wrong table | **AMEND** — `posting_prototype` under `posting_prototype_select` (owner-scoped **AND** the `025` aal2 clause, per `084`). `posting_prototype_default` is global shared-read and is `025`-excluded under exclusion (i); a cross-tenant assertion against *that* table would be vacuous, so do not write one. |
| AC8 — "Sec advisory review … no joint-review-mandatory per SELF-231 posture" | the posture changed with the deliverable | **AMEND to joint-review MANDATORY.** SELF-231's advisory posture was for a seed. This issue now adds a **column to the posting vocabulary** that a money-path filter (SELF-255) reads, plus an ADR-057 provisioning-reach decision. |

**Proposed re-scoped title:** *"`is_tax_payment` on the posting-prototype pair + F/CTO marking (the cash-flow seed half is discharged at `041`/`084`)"*.

**Every input to this issue is now ruled — it is drafting-ready.** Placement on both tables · `is_tax_payment boolean not null`, **no DEFAULT, no CHECK** (A1) · total backfill before the NOT NULL · ADR-057 reach decision stated in the migration header · the F/CTO marking enumeration is a **hard precondition on SELF-255 shipping** ((i)) · durable record = a **new ADR** plus the migration header. Full spec at D3; nothing about this issue is open.

**Why IMPOSSIBLE rather than DRIFT:** the issue's scope shrinks from "seed the vocabulary" to "add one column and mark rows." That is an F/CTO scope call, not a rewording — and it changes what "SELF-245 done" means for the four issues that name it upstream.

Sec joint-review: **MANDATORY** (new column on the posting vocabulary; ADR-057 reach decision; consumed by a deflator-adjacent money path).

---

### SELF-246 — `pfin.cashflow_target` + Lock-14 amendment · **DRIFT** (severe)

Shape stands as ratified — ✅ **confirmed at sitting item 17** (decision item **D-4**); the GL rework does not touch it. **The DDL does not stand.** Each row below is a correction, not a redesign.

| AC | Falsified by | Proposed amended wording |
|---|---|---|
| AC2 — `users_id INTEGER NOT NULL REFERENCES auth.users(id)` | `auth.users.id` is **uuid**; the migration as written does not apply | `users_id uuid not null default auth.uid() references auth.users (id) on delete cascade`. ⚠ The `default auth.uid()` is not cosmetic — it is what lets an authenticated INSERT omit the column and still pass the WITH CHECK (`074`'s rationale, carried). |
| AC2 — `id SERIAL PRIMARY KEY` | project idiom since `001`; `084` relies on identity semantics repo-wide | `id bigint generated always as identity primary key`. |
| AC2 — `income_target_annual NUMERIC` / `expense_target_monthly NUMERIC` (untyped grain) | dollar-grain columns are `numeric(20,4)` project-wide (`004` `account_trans.amount`, `029` split `amount`) | `numeric(20,4)`, both nullable until set. |
| AC3 — `income_target_annual >= 0` + `expense_target_monthly >= 0`; "no upper-bound" | **a one-sided `>= 0` ADMITS NaN** | **Two-sided CHECK on each column, and the reason stated in the migration.** `074` measured this: a `numeric` typmod refuses ±Infinity at coercion ("numeric field overflow") so it never reaches the CHECK, but **NaN is storable in a constrained numeric and satisfies `>= 0`**, because NaN sorts above every non-NaN numeric. `074` closed it with an upper bound (100, a percentage). A dollar target has no natural ceiling, so the bound cannot simply be copied — the amended AC is: `check (x is null or (x >= 0 and x <> 'NaN'::numeric))`, using the `014`/`053` explicit-NaN idiom rather than an invented ceiling. ⚠ Do not "simplify" this to `>= 0` later; that is the exact regression. |
| AC4 — `BEFORE UPDATE … EXECUTE FUNCTION pfin.fn_refresh_updated_at()` | correct as written | **KEEP.** (`fn_refresh_updated_at` is a `001` SECURITY DEFINER allowlist entry — read ADR-011 Decision 9 live; this issue adds no allowlist entry.) |
| AC5 — "RLS: SELECT + INSERT + UPDATE + DELETE all gated by `users_id = auth.uid()`" | incomplete: **no `025` aal2 backstop clause** | **AMEND:** each of the four policies is `users_id = auth.uid()` **AND** the `025` aal2 backstop conjunct, copied **verbatim** (the `074`/`084` discipline — the clause is copied, never paraphrased). `pfin.cashflow_target` is a tenant-owned settings table and is not one of `025`'s named exclusions; ⚠ `user_settings` is (`025:179`, *"NON-NEGOTIABLE exclusion"* — policy recursion), which is precisely why these scalars get their own table rather than a column on it. |
| AC5 — "WITH CHECK enforces no cross-tenant pivot **per Decision 3 family**" | **mis-citation** | **STRIKE the D3 attribution.** A `users_id → auth.users` tenant anchor is not a Decision-3 instance — `074`'s own contract records that distinction, and `074`'s family member is `sub_cat_id`, which `cashflow_target` has no analogue of. `cashflow_target` carries **no FK-shaped column** beyond the anchor. **Family count +0; no label claimed.** The WITH CHECK is still required — it is an RLS clause, not a D3 fence. |
| — (missing) | SD-22 standing constraint | **New AC:** the **DELETE policy ships with its own tenant clause and is never omitted.** Sec's binding wording: *no DELETE policy in this family may be trimmed, weakened, or omitted on the reasoning that the SELECT policy already covers it — that reasoning is confirmed false, not merely unproven.* Measured by QA on `074` with a complementary corrupt-the-control pair. |
| — (missing) | `084` grant posture | **New AC:** `grant select, insert, update, delete on pfin.cashflow_target to authenticated`; **anon zero-grant** (pfin schema USAGE is authenticated-only); **service_role ungranted by construction** (`008` grants per table, no default privileges). |
| AC6 — UPSERT-in-place, no edit-history | correct (ADR-011 Decision 18) | **KEEP.** The `unique (users_id)` is the `ON CONFLICT` target. |
| — (missing) | ✅ **RULED, sitting item 19** — unset-is-NULL-never-0 | **New AC:** **an unset target is NULL; it is NEVER a stored `0`.** Sec's ruling on the SELF-233/242 arc, verbatim from `schemas/planning-target.ts:20–23`: *"'unset a target' MUST be a DELETE, never a POST of an explicit 0.00 — ADR-056 makes 0.00 a stored, DIFFERENT fact from row-absent, and a UI emulating unset with zero would silently destroy that distinction."* **A stored `$0` is a target — "I intend to spend nothing"; absence is "I have not set one."** The two must render differently (SELF-251 AC2 already keys its caption on NULL). ⚠ **THE MECHANISM DOES NOT TRANSPLANT** — ✅ ruled at item 19a: always-NULL-never-DELETE. See the shape note below. |
| AC7 — "SD matrix expansion: new SD entry … mirrors SD-23 pattern" | **superseded, not open** | **AMEND:** SD-22 was assigned to `pfin.cashflow_target` on 2026-08-16. Its cell already carries the obligations and says so: *"NOTHING IN THIS CELL IS BUILT — every clause is an OBLIGATION ON THE V1.3 IMPLEMENTING PR."* The AC becomes *discharge SD-22's obligations*, not *create an SD entry*. Also strike "mirrors SD-23" — SD-23 is `planning_target`'s row and was itself corrected in place at the ADR-056 reshape. |
| AC8 — write endpoint at `src/routes/api/settings/cashflow-target/+server.ts` | path prefix: the SvelteKit app lives under **`api/`** | `api/src/routes/api/settings/cashflow-target/+server.ts`. The shared hardening layer it reuses is real and in place: `api/src/lib/server/validation/numeric.ts` (`sanitizeDecimal`). |
| AC9 — Sec joint-review | correct | **KEEP.** |
| AC10 — "no JSONB columns; two named typed columns only" | correct and worth keeping | **KEEP.** |
| AC1 — ADR-011 Decision 18 amendment 4 → 5 tables | **already landed** | **AMEND to a verification step.** Decision 18's amended text and BACKLOG §5-A8's five-table working list already agree — Sec recorded the four-vs-five divergence as **RESOLVED** at the SD-22 assignment. The AC is now *confirm the amendment covers `cashflow_target` by name*, not *draft it*. |

**⚠ THE UNSET MECHANISM DIFFERS FROM ITS PRECEDENT, BECAUSE THE SHAPE DIFFERS — and copying the precedent literally would unset the wrong thing.** `pfin.planning_target` is **one row per (user, Sub-Cat)**, so *unset* is a **row DELETE** and row-absent IS the representation. `pfin.cashflow_target` is **one row per user carrying TWO independent scalars** (D-4's confirmed wide-row shape). **A row DELETE there unsets BOTH targets at once** — so a user clearing their income target would silently lose their expense target.

**The transplant is the PRINCIPLE, not the verb:**

- **Unset one target → write `NULL` to that column** on the existing row (an explicit unset, not an omitted field — see the mass-assignment note below).
- **Unset both → two NULLs. ✅ RULED (sitting item 19a): ALWAYS NULL, NEVER DELETE** — one representation, chosen so the writer has one verb and the reader has one shape. It also keeps `created_at`/`updated_at` continuity, which a DELETE would discard.
- **⚠ THE READER OBLIGATION THAT MAKES THE RULING TRUE, and it is the operative half:** *a row that exists with two NULLs and a row that does not exist must never carry different meanings.* The writer can only promise half of that — **the other half is enforced at the READ.** `pfin.cashflow_target` has no row for a user who has never opened the editor, and a two-NULL row for a user who set targets and cleared them. **Both mean "no targets set", and every reader must treat them identically.** SELF-250 AC6 (*"NULL if no targets set"*) is where this is either honoured or quietly broken: a `select … where users_id = auth.uid()` returning **zero rows** and one returning **one row of NULLs** are different result shapes in the driver, and a handler that only anticipates one of them will diverge — most likely by throwing on the absent row, or by rendering a caption for a cleared target. **Stated as an AC on SELF-250, not left to the implementation.**
- ⚠ **"Explicit unset" must be distinguishable from "field not sent."** SELF-252 AC3's payload is `{income_annual?, expense_monthly?}` with `.strict()` — under that schema an **omitted** key and a key sent as **`null`** are different intents (leave alone vs clear), and a naive handler treats both as "no change". **The endpoint must accept an explicit `null` and act on it**, or unset becomes unreachable through the UI.

**The `074` transplant, stated once so the implementing PR does not re-derive it:** per-domain table (never `user_settings`) · uuid `users_id default auth.uid()` + cascade · identity PK · four RLS verbs each AND-ed with the verbatim `025` aal2 conjunct · `fn_refresh_updated_at` BEFORE UPDATE trigger · UPSERT-in-place, no versioning · two-sided numeric CHECK · DELETE policy never omitted · **no D3 fence** (nothing to match). And the half `074` did **not** deliver, which must not be read as inherited: Sec's own note, *"RT-23 IS NOT SATISFIED BY `074`"* — the Zod `.strict()` mass-assignment fence and the numeric adversarial battery are owed at the endpoint, and they are SELF-252 AC3/AC4.

Sec joint-review: **MANDATORY** (Lock-14 family table; RLS + aal2 + the SD-22 DELETE-policy constraint). ⚠ **Carry the unset-mechanism deviation into that review explicitly (item 19a):** Sec ruled the *principle* on the SELF-233/242 arc with a **row DELETE** as its mechanism, and this table's wide-row shape makes that verb wrong. They should see the shape-driven deviation **as a deviation from their own precedent**, presented, rather than meet it later as an unexplained divergence.

---

### SELF-247 — Lock 15 as-of-date app-layer mods · **IMPOSSIBLE** (see decision items D6 + D7)

**Its framing premise is falsified by shipped code.** The issue calls §2.3.3 the *"first legitimate client-toggle as-of-date surface in V1"* and treats the app-layer hardening as net-new. Measured on the tree:

- `api/src/lib/server/time/asOf.ts` ships a branded `ZoneResolvedAsOf` type with exactly three minting sites, including **`userSuppliedAsOf()`** — a factory whose own header states: *"SELF-238 / SELF-240 (the §2.2.2 / §2.2.3 allocation backends) are the **FIRST live path**: their ratified AC8/AC6 require Zod-typed validation of a client-supplied `as_of`."*
- `api/src/lib/server/schemas/allocation.ts` ships `allocationAsOfSchema` — `.strict()`, ISO-shape regex, real-calendar-date refinement, optional-with-server-default — plus `resolveAllocationAsOf()`.
- `api/src/routes/allocation/+page.server.ts` consumes both. **A client-supplied `as_of` is live on the §2.2 allocation surface today.**

| AC | Falsified by / status | Proposed amended wording |
|---|---|---|
| AC1 — new Zod helper at `src/lib/server/validation/as-of-date.ts` rejecting non-date types, pre-`2015-12-01`, future dates, locale-formatted, coercion | **Mostly already built, in a different file, minus one clause.** `allocationAsOfSchema` + `userSuppliedAsOf` already deliver: non-date-type rejection, non-ISO/locale rejection (regex), coercion rejection (`z.string()`, no `coerce`), real-calendar-date, and `.strict()` mass-assignment. Path prefix is also wrong (`api/src/…`). | **AMEND to "extend, do not duplicate."** Add the **range bound** to the existing shared schema rather than authoring a second as-of validator — a second one is the drift `067`/`066` exist to prevent one layer down. See the gap below. |
| AC1 — the range `2015-12-01 ≤ as_of ≤ CURRENT_DATE` | ⚠ **NOT ENFORCED ANYWHERE TODAY.** Grepped: no `2015-12-01` constant exists in `api/src/`; `allocationAsOfSchema` has no lower or upper bound, and `userSuppliedAsOf` checks shape only. **The shipped §2.2 allocation surface accepts an arbitrary past or future `as_of` right now.** | **This is the issue's real live deliverable** — and it is a **Lock 15 V1-SHIP-BLOCK mod that is currently unmet on a merged surface**, not a V1.3 greenfield task. See decision item D6. |
| AC2 — endpoint at `src/routes/api/cashflow/account/[account_id]/+server.ts`, default `CURRENT_DATE` | path prefix (`api/src/…`); `[account_id]` is a **bigint**, not the UUID SELF-253 assumes | **AMEND** both. "Defaults to `CURRENT_DATE`" → defaults to `serverTodayAsOf()`, the existing factory; ⚠ that is the **Node** clock, and `CURRENT_DATE` is the **Postgres** clock. Decision 19 *"says nothing about WHICH SERVER"*; `asOf.ts`'s header names the same hazard. Pick one and name it. |
| AC3 — endpoint constructs the dual-column filter `transaction_date <= $1 AND created_at <= $1`; bound parameter only | The columns exist (`004:127` is the Lock 9-A `created_at`). ⚠ But **`pfin.fn_gl_entries` filters `transaction_date <= p_as_of` ONLY — it has no `created_at` leg.** | **AMEND + escalate.** If §2.3.3 composes on the GL reader (decision item D1 option B), this AC cannot be satisfied without changing a money-path function's predicate — its own migration, its own Sec joint-review. If §2.3.3 reads the ledger directly (D1 options A/C), the AC stands as written. **AC3 and D1 must be ruled together.** |
| AC4 — "SECURITY INVOKER composition helper signature extended with `p_data_as_of DATE`" | **No such helper exists for §2.3** — the §2.3 helpers are the unbuilt SELF-250/253/255 functions | **AMEND:** the parameter name and grain are set **at those functions' authoring**, not retrofitted here. And note the naming collision: Lock 15 calls it `p_data_as_of`; every shipped §2.1/§2.2 helper uses `p_as_of`. Pick one vocabulary in the ADR, not per-function. |
| AC5 — RT-25 adversarial battery: negative/future/non-date/injection/coercion/locale → 400 | the shape is right; the **future-date** leg is the one with no current control (see AC1) | **KEEP**, and add the leg that is actually missing: **out-of-range past** (pre-`2015-12-01`) and **future**. ⚠ Also state the venue rule: a pgTAP battery's plan count enforces only through a TAP-aware consumer — `pg_prove` exits 1, bare `psql` exits **0**. |
| AC6 — server-derived-only fence documented at `src/lib/server/validation/README.md` | **the file already exists** (`api/src/lib/server/validation/README.md`, documenting the `numeric.ts` battery) | **AMEND to "extend the existing README"**, correct the prefix, and carry Decision 19's clause verbatim rather than paraphrasing it. |
| AC7 — SD matrix + SECURITY §4.5 RT catalog updated with an RT-25 entry | RT-25 is named in ADR-011 Decision 19; verify its catalog state before drafting rather than assuming it is absent | **AMEND to a verify-then-act step.** ⚠ RT-25 is **not** in the CI-fenced RT set (`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`), and it is **not** a §10 catalogued instance. Adding or moving it would be a fence-boundary or ledger change respectively — neither is in this issue's scope, and the two sets must not be reconciled. |
| AC8 — Sec joint-review mandatory | correct | **KEEP.** |

Sec joint-review: **MANDATORY** (parameter fence on a multi-tenant read; RT-25; and — per D6 — a currently-unmet V1-SHIP-BLOCK on a merged surface).

---

### SELF-248 — §2.3.1.a classify backend + vendor inference · DRIFT (severe)

| AC | Falsified by | Proposed amendment |
|---|---|---|
| Description + AC1 — `UPDATE pfin.account_trans.user_subcat_id` | G3 (`004` blocks all UPDATE; column absent) | `POST /api/transactions/:id/classify` writes **`pfin.account_trans_annotation`** (`023`) via UPSERT on `trans_id` — INSERT if no annotation row, UPDATE of `sub_cat_id` if one exists. The immutable ledger is not touched. |
| AC1 payload `{user_subcat_id: UUID}` | `posting_prototype.id` is `bigint` | `{sub_cat_id: number}` — bigint. ⚠ A bigint crosses the wire as a **string** in the Postgres driver; the contract must state which side coerces. |
| AC2 — "Lock 10 immutability NOT violated: only `user_subcat_id` column UPDATEs" | G3 — false claim | Replace entirely: *"the ledger row is never written; an integration test asserts a classify call leaves `pfin.account_trans` byte-identical and that a direct UPDATE attempt raises."* Keep the test, invert its subject. |
| AC3 — forged-key validation against `user_taxonomy` / `domain='cashflow'` | G1; and the fence already exists in the DB | Target is `pfin.posting_prototype`; drop the `domain` predicate. The cross-tenant rejection is **already DB-enforced** by `fn_account_trans_annotation_matched_sub_cat` (re-targeted at `084`, chain-resolved via `trans_id → account_trans.account_id → account.users_id`, NULL-safe fail-closed) plus the FK to `posting_prototype`, which makes a cross-vocabulary reference structurally unreachable. The endpoint's job is to surface the raised exception as a 400, not to re-implement the check. |
| AC4 — `fn_suggest_subcat_for_vendor(p_users_id UUID, …) RETURNS UUID`; matches on `account_trans … users_id = p_users_id` | G4; `account_trans` has **no** `users_id` (tenancy via the account chain) | `pfin.fn_suggest_subcat_for_vendor(p_vendor text) RETURNS bigint`, SECURITY INVOKER, STABLE, `set search_path = ''`. Tenant scope is RLS through `account_trans` → `account_users`; no tenant parameter. Returns the `sub_cat_id` of the most-recent annotation on a prior transaction with matching `vendor` (case-insensitive). |
| — (missing) | S-1 + S-4 | **New AC — MANDATORY, ✅ RULED (sitting item 6a).** The endpoint **refuses any write where `classifiable()` is false** — all four mechanical rules **plus `is_reverse` rows** (E1 (a), item 8), not only the split parent — returning a typed error rather than writing an annotation that is either ignored (M1, M4) or **actively wrong** (M3, the ordered-`case` money defect at S-4). This generalises the split-parent refusal this row originally carried. The DB-fence half is **not** in this AC — it is routed as **D-8**. |
| — (missing) | `038` already ships `fn_create_manual_trans(… p_sub_cat_id …)` | **New AC:** the manual-entry path's existing `p_sub_cat_id` argument and this endpoint resolve to the same annotation row; the issue adds no second write path. |

Sec joint-review: **MANDATORY** (a new function + a write path over a D3-fenced column).

**SELF-248 — THE D-8 DB FENCE, DRAFTING-READY — ✅ `CONFIRMED` by F/CTO 2026-08-22 (sitting item 15): Sec's C′ / C″ / C‴ with all seven binding conditions, exactly as encoded below.**

**Sec's verdict (bounded consult, `temp/sec-v13-d7-d8.md`, read-only at `0491830`): option (A) is OUT, and (C) is chosen with three reformulations.** Sec **declines** to state that non-endpoint `authenticated` paths are out of V1's threat model — which was the exact condition I said (A) rested on — citing `023:414`'s `grant select, insert, update, delete … to authenticated`, the QA-measured Lock-14 precedent, and that **V1 ships public signup, so `authenticated` is a role many principals hold, not one trusted client**. No veto; a FLAG with binding conditions.

**⚠ SEVERITY NUANCE, from Sec, because it changes the argument's shape and I had not drawn it:** `023`'s four policies are all `wr_access`-JOIN scoped (`023:221`), so a writer reaches only their **own** rows. **This is NOT cross-tenant.** It is **silent financial-correctness corruption of the writer's own ledger**, reachable by any path that is not the SELF-248 endpoint. That is why it is a flag with conditions rather than a veto.

**⚠ THREE CORRECTIONS TO MY OWN D-8 PROPOSAL — recorded as corrections, not merged away:**

- **(C′) THE PREDICATE — mine was wrong.** I wrote *"refuse a non-`Transfer` cat when `journal_id IS NOT NULL`."* Sec: a `transfer_in_kind` journal's legs are **security rows**, and `084:1233`'s biconditional forces them to `cat = 'Trade'` — **so my predicate would refuse every in-kind transfer.** The correct invariant, and it is *derived from the defect rather than chosen*:
  > `journal_id IS NOT NULL` ⇒ resolved `posting_prototype.cat NOT IN ('Revenue','Expense','Equity')`

  The refused set is **exactly the fall-through set of the `084:869–872` ordered `CASE`** — which is what lets the function's own COMMENT explain itself.
- **(C″) THE SCOPING — mine was wrong twice.** I proposed `WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id`. Sec: **(i)** a `WHEN` clause on an `INSERT OR UPDATE` trigger **cannot reference `OLD` at all**; **(ii)** even if it could, it leaves one reachability order open — *attach-then-classify* fires and is refused, but **classify-then-attach changes only `journal_id`, never fires, and reaches the defect state.** Use a pure **STATE** predicate on `NEW`, valid on both ops:
  ```
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.sub_cat_id is not null and new.journal_id is not null)
  ```
  ⚠ **And my "B hazard" does not apply to this shape** — attaching a journal to a `Transfer`- or `Trade`-classified leg fires and **passes**; only Revenue/Expense/Equity + journaled raises, which is the defect state itself. Detach (`new.journal_id` NULL) is WHEN-skipped; note-only edits on a valid row fire and pass. **Sec also measured that `030:280–284` already ships `when (new.sub_cat_id is not null)`** — the very clause I flagged as hazardous — and it fires on journal-attachment UPDATEs today and passes, because it checks only the trade biconditional.
- **(C‴) THE PLACEMENT — a new function and trigger, NOT an edit to `084`'s.** Folding M3 into `fn_account_trans_annotation_trade_constraints` looks free (it already resolves the parent txn and `posting_prototype.cat` at `084:1209–1219`). Sec: don't — it was already re-targeted once at `084` (a fan-out **found by measuring the live catalog**, `084:1181–1183`), it carries a long behaviour-describing COMMENT that ships to `pg_description`, and edits move catalog assertions. A separate `fn_..._journaled_cat_fence` keeps attribution readable. **Cost: one extra `posting_prototype` lookup, only on writes where both fields are non-null.**

**SEC'S SEVEN BINDING CONDITIONS — carried into the AC set, not summarised away:**

1. **NULL-safe fail-closed** — unresolvable `posting_prototype` row → `raise`, matching `084:1222–1227`'s idiom. Never a silent skip.
2. **SECURITY INVOKER + `set search_path = ''`.** No DEFINER; the ADR-011 D9 allowlist does not move (read it live — Sec deliberately states no size, and neither does this document).
3. **Paired pgTAP battery, `pg_prove` only, never bare `psql`.** Legs must include **both orders** — classify-then-attach AND attach-then-classify — plus `lives_ok` controls for attaching a `Transfer`-classified leg and a `Trade`-classified in-kind leg. ⚠ **A battery testing only attach-then-classify cannot distinguish this fence from the transition-scoped one** — which is the whole point of (C″). Corrupt-the-control pair on the fence itself.
4. **Existing-violation count reported in the migration PR** — rows with `journal_id is not null` and resolved `cat in ('Revenue','Expense','Equity')`. **Non-zero → back to Sec before the fence lands.**
5. **The app guard (item 6a) still ships in full.** The DB fence covers **M3 only**. The function COMMENT must state **why M1/M4 stay app-layer** — measured never-read via P3's `where` at `084:885–886` — so a future reader neither "completes" the fence nor deletes it as arbitrary.
6. **UX consequence, named:** attaching a journal to an already-Revenue/Expense/Equity-classified leg now **fails**. Frontend must surface *reclassify-then-attach*, and **the endpoint's typed error and the trigger's raise must be distinguishable**.
7. **ADR-011 D2 surface** (financial-correctness data). The fence lands at the **surface-introducing PR (SELF-248)** under joint review; **Architect commits the ADR text.**

**Sec's explicit non-objections, recorded so nobody re-opens them:** no DB fence required for **M1** or **M4** (measured fail-silent; app guard sufficient) · **no** narrowing of `023`'s `authenticated` grant (revoking UPDATE breaks the classify path; column-level grants are a larger change with their own review — considered and declined) · **not (B)** (viable, but more surface than the measured defect needs, and it would amend `029`'s deliberately-soft precedence rule as a side effect) · **no veto** on either question.

**⚠ One attribution correction Sec made to my brief, worth keeping because I would otherwise repeat it:** the *"does not bound what other paths may send"* sentence lives in `docs/SECURITY/index.html:730`'s **Lock-14 settings-family DELETE-policy fence posture bullet** — which *names* SD-22 as one of four unbuilt family members. **It is not SD-22's own matrix row**, which is how I cited it.

### SELF-249 — §2.3.1.b classify UI · DRIFT

- **AC3** — "cascading picker with `domain = 'cashflow'` filter" → picker sources `pfin.posting_prototype` (Cat = the five-class enum, Sub-Cat free text); **the filter is deleted**, not translated (G1).
- **AC2** — the provider suggestion is feasible and already has a column: `pfin.account_trans.provider_category` (`017:234`). Re-word "Plaid category" → **`provider_category`** (provider-agnostic per ADR-027 R-12), and carry `017`'s own constraint verbatim into the AC: *"IMMUTABLE display hint only … all txns land Unsorted; NO auto-map / NO `provider_category`→`sub_cat` routing in V1."* The ghost-text default is a render, never a write.
- **AC6** — "AcctSetup transactions render with picker disabled": no `AcctSetup` Cat exists (G2). Re-anchor to the real discriminator: rows with `transaction_type <> 'standard'` (`030`) render the picker disabled.
- **New AC** (G6): a split parent's row renders its children's Sub-Cats read-only and routes the edit to the split editor rather than offering a parent-level picker.

Sec joint-review: not mandatory on its own (UI over an already-fenced endpoint).

### SELF-250 — §2.3.2.a cross-account rollup backend · **IMPOSSIBLE** (see decision item D1)

Beyond the substrate fork, the mechanical amendments:

- **Signature** `(p_users_id UUID, p_scope pfin.scope[], p_year INT)` → **`(p_as_of date)`**. `p_users_id` and `p_scope` struck (G4) — ⚠ `p_scope pfin.scope[]` is **schema-impossible**, not merely unidiomatic; `p_year` struck at sitting item 5a (the year derives from `year(D)` per the S-3 grammar). The surviving parameter is threaded by the app, never defaulted in-function (ADR-044 Decision 2). Full attribution table at **S-3**.
- **AC2** — "filtered by `user_subcat_id` resolved to Cat ∈ {Income, Expenses}" → resolved through the annotation/split overlay to `posting_prototype.cat ∈ ('Revenue','Expense')` (G1+G2+G3).
- **AC5** — "OtherCF EXCLUDED / AcctSetup EXCLUDED entirely" → the section list is `('Revenue','Expense')`; `Transfer`, `Trade` and `Equity` are excluded from *this* surface; `transaction_type <> 'standard'` rows are excluded (G2).
- **AC7** — `skip_flag` / `reconciled_flag` clauses **deleted** with an ADR-032 pointer (G5).
- **AC6 — new clause, ✅ RULED (item 19a):** the `targets` block treats **row-absent and all-columns-NULL identically** — both are *"no targets set"*. Per the always-NULL-never-DELETE ruling these are two reachable states of the same meaning (never-opened-the-editor vs set-then-cleared), and they arrive as **different result shapes from the driver** — zero rows vs one row of NULLs. A handler anticipating only one diverges, most likely by throwing on the absent row or rendering a caption for a cleared target.
- **AC3 sign convention** — "Income + Expenses both rendered positive (absolute value)" is a **money-correctness hazard of exactly the ADR-061 shape**: `abs()` over a signed aggregate silently sign-flips a genuinely negative bucket (an expense Sub-Cat net-negative from refunds; a contra-revenue month). ADR-061's ruling — *a negative total must not pass through un-gated* — transplants. Proposed replacement: presentation negates the credit-normal section by a **single sign convention applied to the section**, never `abs()` per row; a row whose signed value opposes its section's normal balance renders with its real sign. State the reachable-state table the way ADR-061 Decision 3 does.
- **New AC** (G6): the aggregate branches on `split_count` — children when present, parent otherwise. Absent this, every split transaction is double-counted.
- **New AC**: degenerate states stated explicitly — zero classified transactions, a Sub-Cat with no rows in a period, a NULL `sub_cat_id` (Unsorted-pending, which `023`/`029` both permit by design). Unsorted is not zero and must not silently vanish; ADR-049 Decision 4's non-silence discipline is the nearest precedent.

Sec joint-review: **MANDATORY** (financial calculation + multi-tenant read composition).

### SELF-251 — §2.3.2.b rollup UI · DRIFT

- AC1/AC2 section captions — keep the user-facing words "Income"/"Expenses" only if PM lands the §3.3-style label-mapping footnote; the underlying Cats are `Revenue`/`Expense` (G2). Naming the mapping in the AC is what stops the caption being read back as a predicate.
- AC2's illustrative figures ($120,000/year, $4,500/month) are placeholders in a repo where §7-era guidance redacts concrete $ values in PRD-facing prose; recommend genericizing.
- AC6/AC7/AC8 stand as written. AC9 depends on SELF-258 (see below).
- **New AC**: how a negative section total renders, per the SELF-250 sign ruling. A UI that can only render positives will hide the case the backend now surfaces.

### SELF-252 — §2.3.2 cash-flow targets editor · DRIFT (blocked)

The editor ACs are app-layer and largely sound. The problems are upstream and are stated at **§4** and **decision item D-4** (the target table's shape is ✅ confirmed-as-ratified at item 17; its **DDL** corrections are still owed). Editor-local amendments:

- **AC2** — "both default to existing `pfin.cashflow_target` row if present": the table is **UNBUILT** (grepped: zero occurrences of `cashflow_target` under `supabase/`, `api/`, `web/`). Blocked-by SELF-246, which is in **Backlog** in Platform / Cross-cutting — not in V1.3.
- **AC3/AC4** stand — and they are the RT-23-shaped app-layer half that `074` conspicuously did **not** deliver for `planning_target`. Carry the Sec note verbatim into the AC so it is not read as already-satisfied: *"RT-23 IS NOT SATISFIED BY `074`."*
- **New AC — ✅ RULED (sitting item 19): unset-is-NULL-never-0.** The editor must offer an **explicit unset** per field, sending `null` rather than `0` or an omitted key, and must render an unset field as **empty, never as `$0`**. A stored `$0` is a target; absence is not — and SELF-251's caption already branches on NULL, so a `0` written for "unset" would render as *"target $0/month"*. ⚠ ✅ **RULED (item 19a):** AC3's Zod payload `{income_annual?, expense_monthly?}` with `.strict()` **must distinguish an explicit `null` from an omitted key** — omitted means *leave alone*, `null` means *clear* — and the endpoint must act on the `null`. **The write is always an UPSERT setting the column to NULL; it is never a row DELETE** (see SELF-246's shape note for why the precedent's verb is wrong at this shape).
- **New AC** (SD-22 standing constraint, Sec, from the `074` corrupt-the-control measurement): `pfin.cashflow_target` ships a **DELETE policy carrying its own tenant clause**. *No DELETE policy in the Lock-14 family may be trimmed, weakened, or omitted on the reasoning that the SELECT policy already covers it — that reasoning is confirmed false, not merely unproven.*
- **New AC**: the numeric CHECK is **two-sided**, and the reason is stated. `074` measured it: `numeric(5,2)`'s typmod refuses ±Infinity before the CHECK sees it, but **NaN is storable in a constrained numeric and satisfies `>= 0`** (NaN sorts above every non-NaN numeric). A one-sided `>= 0` admits NaN. For dollar-grain columns the project idiom is `numeric(20,4)`, so re-derive rather than copy `074`'s bounds.
- **AC7** of SELF-246 ("new SD entry for cashflow_target") is **superseded, not open**: SD-22 was assigned to `pfin.cashflow_target` on 2026-08-16. Its matrix cell already carries the obligations and says so: *"NOTHING IN THIS CELL IS BUILT — every clause is an OBLIGATION ON THE V1.3 IMPLEMENTING PR."*

Sec joint-review: **MANDATORY** (Lock-14 settings write path).

### SELF-253 — §2.3.3.a per-account drill-down backend · **IMPOSSIBLE** (see decision item D2)

- **(d) answered: the Lock 15 claim is accurate.** ADR-011 Decision 19 reads verbatim: *"server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand monthly_report; **§2.3.3 drill-down is the ONLY surface where client toggle is legitimate**)"*. The issue quotes the operative clause correctly and applies it to the right surface. ⚠ One qualifier the issue does not carry: CHANGELOG records SELF-247 as *"Lock 15 V1-SHIP-BLOCK first legitimate client-toggle application"* — SELF-247 owns the validation helper, SELF-253 consumes it. That ordering is a hard dependency and SELF-247 is in Backlog, outside V1.3 (§4).
- **AC3 dual-column filter** — `transaction_date <= $1 AND created_at <= $1` is correct and `account_trans.created_at` exists (`004:127`, the Lock 9-A re-introduction). ⚠ But **`fn_gl_entries` filters on `transaction_date <= p_as_of` only** — it has no `created_at` leg. If the drill-down composes on the GL reader (decision item D1), the dual-column filter is **not available** without changing a money-path function. Naming this now because it is the seam where "as-of" quietly becomes two different as-ofs.
- **Signature** — → **`(p_account_id bigint, p_as_of date)`**. `p_account_id UUID` is wrong: `pfin.account.account_id` is **bigint** (`003:92`). `p_users_id` struck (G4); `p_year` struck at sitting item 5a; the `DEFAULT CURRENT_DATE` dropped per S-3's clock riders (ADR-044's zero-round-trip variant stays ruled out). Full attribution table at **S-3**.
- **AC1/AC6** — the three-section shape (Income / **OtherCF** / Expenses) cannot be expressed: see D2.
- **AC5** inherits SELF-250's sign ruling; **new AC** for `split_count` (G6).

Sec joint-review: **MANDATORY** (financial calculation + a client-supplied date parameter on a multi-tenant read; RT-25 parameter-bypass is the named RT).

### SELF-254 — §2.3.3.b drill-down UI · DRIFT

- **AC3 / AC6** — `account.inactive` has no referent (G7). Re-word to `closed_at` per ADR-042: the selector includes closed accounts for historical drill-down; the badge reads from `closed_at`, not a boolean.
- **AC1** — section order blocked on D2.
- **AC4** — the `[2015-12-01, today]` range is Lock 15 mod #2 verbatim and stands. ⚠ "today" is a **clock** claim: ADR-043/`061` pin the *database* TimeZone default, and Node and Postgres are two servers with two clocks (ADR-011 Decision 19 *"says nothing about WHICH SERVER"*). The AC must name which clock bounds the picker, or the boundary day is ambiguous by up to 26 hours.

### SELF-255 — §2.3.4.a Historical Expenditures backend · **IMPOSSIBLE** (see decision items D3 + D5)

- **AC2/AC3 `is_tax_payment` on `pfin.user_taxonomy`** — the column does not exist anywhere (grepped: zero occurrences). More importantly its ratified home is now the **wrong table**: tax-payment-ness is a property of a *posting prototype*, and posting prototypes left `user_taxonomy` at `084`. Placement is decision item D3.
- **AC4 normalization formula** — `nominal × (cpi_today / cpi_at_month_end)` is wrong twice, and the second is the load-bearing one:
  1. It **re-derives the CPI resolution locally**, which ADR-049 Decision 4 exists to prevent. The ratified resolver is `pfin.fn_cpi_u_index_for_period(p_period date)` — eight columns, exactly one row always, STABLE, INVOKER (`066`, superseding `064`'s six-column shape). Its return shape is **ratified, not provisional**: a change to the column set requires Sec re-review + F/CTO ratify + an ADR-049 amendment + a migration that re-issues the grant.
  2. **There is no "cpi_today".** The shipped precedent the AC claims to match — `fn_nav_series_inflation_adjusted` (`067`) — restates in the purchasing power of **`cpi_coverage_through`**, the last period the CPI store actually covers, and carries that as a dated basis line (*"CPI-U through {coverage_through}"*) on every path. So the AC's stated basis ("today's $") **contradicts the §2.1.2 basis it cites as its model**. This is a correctness finding, not a wording one.
  Proposed: the function composes `066` per month via a lateral, carries the `cpi_*` provenance columns through prefixed (the `067` pattern), returns **NULL — never zero** when either CPI leg is absent or non-positive, and carries `coverage_through` as the disclosed basis.
- **AC5 rolling average** — "NULL for first 11 rows" is right in shape; add: the rolling mean is over the **inflation-adjusted** series and is NULL if any constituent month is NULL, rather than silently averaging a short window.
- **AC6** — "OtherCF EXCLUDED entirely" has no referent (G2); the predicate is `cat = 'Expense'`.
- **AC7** — `skip_flag` deleted (G5).
- **AC1** — "~60 rows": state whether a month with no expenses emits a zero row or no row. A missing row and a zero are different claims on a financial chart; `066`'s non-silence discipline says pick one and say which.
- **Precondition, not optional:** BACKLOG §7.14 — `053`'s CHECK on `cpi_u_index.cpi_value` is **finiteness-only**, so a poisoned `0`/negative print reaches every deflator. Sec's four binding conditions apply, and condition (1) is the trap: **`> 0` alone re-admits NaN *and* Infinity** (both compare TRUE under numeric ordering). Adding a fourth CPI consumer without discharging §7.14 widens a known open hazard.

Sec joint-review: **MANDATORY** (financial calculation + a new column on a Lock-14-adjacent vocabulary table).

### SELF-256 — §2.3.4.b chart UI · DRIFT

- **AC2** — "Y-axis: $ in today's-$ purchasing power" → the basis is `coverage_through`, and the chart must render the dated basis line (§2.4.4). Inherits SELF-255's ruling.
- **New AC** — the `066` consumer rendering rule, carried rather than re-derived: `cpi_value IS NULL` → render UNAVAILABLE with a reason; `is_carried AND period_was_due` → informational carried-ness marker with a cause clause iff `nonpublication_on_record`; otherwise a plain figure. ⚠ And the prohibition: **a consumer MUST NOT branch user-visible tiering on `gap_class`** — that column is operator-axis only.
- AC1/AC4–AC10 stand.

### SELF-257 — §2.3.5 close-gate RLS battery · DRIFT

- **AC1** — "tenant-A-injects-tenant-B-`users_id` rejected" presupposes the `p_users_id` parameter G4 removes. The correct leg for INVOKER helpers is: a cross-tenant caller **sees zero rows and fails closed**, verified under the two-tenant fixture — not a rejected injection.
- **AC2** — `p_account_id` type (bigint).
- **AC6** — `p_scope = '{personal,trust}'::pfin.scope[]` is **schema-impossible** (G4). Either strike the leg or re-express it over `pfin.account.scope` as free text; per-scope reporting is V2+, so striking is the honest option.
- **AC7** — Sub-Cat forgery: the fences are `fn_account_trans_annotation_matched_sub_cat` and `fn_account_trans_split_matched_sub_cat`, both **re-targeted at `084`** and both chain-resolved. The battery must assert against `posting_prototype`, and must include a leg for the class the re-target created: a `sub_cat_id` pointing at a **storage-side `user_taxonomy` id** now fails at the FK, not at the trigger.
- **AC8** — add the SD-22 DELETE-policy leg, and use the **corrupt-the-control idiom** Sec specified: a cross-tenant DELETE assertion written *with* a `WHERE` is satisfied by either policy, so corrupting one and finding the test still green proves the other is sufficient — not that the corrupted one was redundant. Omit the column filter, or corrupt both clauses and vary them independently.
- **New AC**: `pg_prove`, not bare `psql` — a pgTAP plan count enforces only through a TAP-aware consumer; `psql` exits 0 on a failing battery.

### SELF-258 — §2.3.x staleness ramp · DRIFT

- **AC1** — `pfin.fn_aggregation_has_stale_constituent(p_users_id, p_scope)` is wrong: the shipped function (`046:128`) takes **zero arguments** and returns `table (is_stale boolean, stale_items jsonb)`, SECURITY INVOKER, STABLE. Both parameters are G4 artifacts.
- **AC3** — "scoped to a single account" is not expressible against a zero-argument function. Either the badge is user-wide on the drill-down (accept the over-broad marker and say so), or `046` gains an account-scoped sibling — which is a migration, an owner, and a Sec touch, not an AC clause.
- AC2/AC4/AC5/AC6 stand.

---

## 4. Sequencing — resolved, and what the promotion changes

**F/CTO ruled 2026-08-22: SELF-245, SELF-246 and SELF-247 are promoted into V1.3.** The scheduling gap this section originally reported is closed; what remains is the ordering it exposed.

They are named upstream by SELF-248, SELF-250, SELF-252, SELF-253 and SELF-255 — every backend issue in the milestone. Proposed dispatch order:

1. **SELF-246** (`cashflow_target` migration, corrected) — no dependencies of its own; unblocks SELF-250's `targets` block and all of SELF-252.
2. **SELF-245 (re-scoped)** — `is_tax_payment` on the posting-prototype pair + the marking pass; unblocks SELF-255. Gated on decision item D3.
3. **SELF-247 (re-scoped)** — the as-of range bound on the *existing shared* schema; unblocks SELF-253 AC4. Gated on D6, and its AC3 is gated on D1.
4. Then SELF-248 → 249 → 250 → 251/252 → 253 → 254 → 255 → 256 → 258, with **SELF-257 last** as the close-gate.

⚠ **SELF-247 is not purely upstream any more.** Its live deliverable (the range bound) applies to a **merged** surface — the §2.2 allocation route — so it is partly a *remediation* of V1.2, not only a prerequisite for V1.3. That changes who reviews it and when: see D6.

⚠ **SELF-245's re-scope changes what "done" means downstream.** Four issues name it as the source of the cash-flow vocabulary. If it is re-scoped to the column-plus-marking, those four must be told the vocabulary is already provisioned — otherwise the first one to run will look for a seed step that no longer exists and re-derive one.

## 5. Decision items for the batch ratify sitting

**S-1 — The classifiability predicate (classify-queue boundary) — ✅ RULED (b) by F/CTO 2026-08-22 (sitting item 3); predicate defined here.**

**The ruling, carried verbatim from `temp/v13-preflight/sitting-log.md`:** *"the classify queue holds ONLY rows outside the mechanical posting vocabulary (trades/transfers/splits arrive pre-answered by `posting_prototype`); §2.3 surfaces sum only cashflow-domain-annotated rows. The concrete predicate (which transaction_types) is Architect's to define in the amendment batch."*

⚠ **One translation before anything else.** The ruling says *"cashflow-domain-annotated rows"*. **There is no `domain` column** — it was dropped at `084` (generator G1). Reproducing that phrase in five ACs would re-introduce a retired predicate five times, which is the exact drift this pass exists to stop. What the clause means operationally is stated at **P5** below, and it turns out to need **no predicate at all**.

**This predicate is stated ONCE and cited, never restated.** SELF-248, SELF-249, SELF-250, SELF-253 and SELF-255 each cite *"the S-1 predicate"* by name. Four restatements would drift independently — the same extraction discipline behind the D1 hybrid lean, applied to a definition rather than to code.

**IT IS NOT INVENTED — IT IS THE ONE `fn_gl_entries` ALREADY USES.** `084:885` opens the P1 cash branch with `where t.transaction_type = 'standard' and t.security_id is null`. That is the GL's own cash-leg discriminator, and the predicate below is that line plus the two grain rules the GL also already applies. Grounding it this way is deliberate: a §2.3 predicate that disagreed with the GL's would make the cash-flow surfaces and the ledger tell different stories about the same row.

**MECHANICAL — pre-answered, NOT in the classify queue:**

| | Rule | Basis in the tree |
|---|---|---|
| **M1** | `transaction_type <> 'standard'` — i.e. `acct_setup`, `basis_adjust`, `corp_action` | `030:153` fixes the four-value vocabulary. Non-cash lifecycle events; §2.4 territory. **Excluded from every §2.3 surface entirely**, not merely from the queue. |
| **M2** | `security_id IS NOT NULL` — a securities row | `084:1233` enforces the **biconditional** `(security_id is not null) <> (cat = 'Trade')` → raise. So on any annotated row, a bound security **is** a Trade and an unbound one **is not** — DB-enforced, not a judgement. On an *un*annotated row the GL derives the postings from row shape alone (`088`: *"THE ROW SHAPE IS FORCED BY THE GL, not chosen"*), so the answer is the same either way. |
| **M3** | `account_trans_annotation.journal_id IS NOT NULL` — a leg attached to a journal group | `033:403` adds the column; `033:239` fixes `group_type in ('transfer','transfer_in_kind','compound')`. The clearing contra follows from group membership, and ADR-031 Decision 5's Σ=0 conservation offsets the group. |
| **M4** | `split_count > 0` — a split **parent** | `035`/`037`'s shipped reader rule, restated at `038`: `split_count > 0` → count the children, else the parent; `029`: *"a txn is 023-single-categorized XOR split"*. The parent is never classified; its **children** are. |

**P — THE CLASSIFY QUEUE (SELF-248/249).** A row is in the queue iff it is classifiable **and** not yet classified:

```
classifiable(row)  :=  transaction_type = 'standard'
                   AND security_id IS NULL
                   AND split_count = 0
                   AND is_reverse = false                          -- E1 (a), sitting item 8
                   AND (annotation IS NULL OR annotation.journal_id IS NULL)

in_queue(row)      :=  classifiable(row) AND effective_sub_cat_id IS NULL
```

plus, at the **child** grain: every `account_trans_split` child with `sub_cat_id IS NULL` is in the queue (`029` permits NULL — *"Unsorted-pending line (→ Suspense downstream)"*).

**P5 — WHAT §2.3 SUMS, and why it needs no vocabulary predicate.** Since `084` re-targeted both FKs (`account_trans_annotation.sub_cat_id` and `account_trans_split.sub_cat_id` → `pfin.posting_prototype(id)`, ON DELETE RESTRICT), **there is no other vocabulary a `sub_cat_id` can point at.** The ruling's *"cashflow-domain-annotated"* qualifier is therefore delivered **structurally, by the FK**, and the amended ACs must express it as a **join**, not as a filter:

> §2.3 surfaces sum rows whose effective `sub_cat_id` resolves to a `pfin.posting_prototype` row whose `cat` is in that surface's section set. No `domain` predicate exists, is needed, or may be written.

⚠ This is the second time the split paid a dividend by **deleting** a predicate rather than translating one (the first was `028`'s CHECK losing its disjunct at ADR-058 Decision 4). Both look like relaxations on a partial read and are not: a row cannot reach the FK's target without being posting vocabulary.

**EDGE ROWS THE PREDICATE DOES NOT DECIDE — flagged, not papered over.**

- **E1 — reverse-and-replace rows — ✅ RULED (a) (sitting item 8): EXCLUDED from the queue; §2.3 nets the pair structurally.** A reversal (`004`: `is_reverse = true`, `replaces_trans_id` set) of a cash transaction is `standard` with `security_id IS NULL` and no journal, so it satisfied `classifiable()` and landed in the user's queue as a second thing to categorise — with **nothing in the schema linking a reversal's annotation to its original's**, so a classified original beside an unclassified reversal meant **the expense never netted out**. **Ruled:** `is_reverse` rows are excluded from the queue (the predicate above now carries `is_reverse = false`) and are **never classified by anyone**; §2.3 readers net the pair **structurally through the `replaces_trans_id` join, inside the ORIGINAL's Sub-Cat** — which makes the netting invariant under any later reclassification of the original. Only the replacement row enters the queue. **The measured behaviour of the shipped flow, and the two consequences it exposes, are at E1-M below.**

- **E2 — `group_type = 'compound'` is excluded wholesale by M3 — ✅ RULED (sitting item 3b, default-and-notify): GATED AT THE FIRST CREATOR.** `transfer` and `transfer_in_kind` are genuinely non-cash-flow; **`compound` is undefined in the §2.3 context**, and if a compound journal can mix a Transfer leg with a genuine Expense leg, M3 silently drops the Expense from every §2.3 surface. **No behaviour changes today and M3 stands exactly as written** — no compound journal is constructed anywhere in the current tree, so narrowing M3 now would be a change with no case to justify it. The constraint spec and its watcher are at **S-2b** below.

- **⚠ E3 — "no annotation" and "annotation with NULL `sub_cat_id`" are two states, and only one of them is obvious.** An annotation row can exist to carry a `note` or a `journal_id` with `sub_cat_id` still NULL. Every §2.3 query must reach `account_trans_annotation` by **LEFT JOIN**; a naive inner join with `WHERE sub_cat_id IS NULL` **silently drops the rows that have no annotation at all** — which per `017:188` (*"All txns land Unsorted"*) is most of an ingested book. Fail-silent, value-plausible, and it would pass any test whose fixture annotates every row. **Not a ruling — a mandatory AC clause on 248/250/253/255 and a battery leg on 257.**
- **⚠ E4 — the queue's grain is not "per transaction," and the PRD says it is.** With M4, the unit is *an unsplit transaction* **or** *a split child*. PRD §2.3.1 reads *"each transaction is independently classified to a Sub-Cat … at the per-transaction level."* That passage is already on PM's amendment list (sitting item 3 routes it there); **this is the specific correction it needs**, so it is recorded here rather than left as "the passage amends accordingly."
- **E5 — a product consequence of M2, stated because someone will ask for the feature.** The `084:1233` biconditional means a row carrying `security_id` **must** be `Trade`. So a dividend classified `Revenue / Dividend` (`041` seeds it, described *"Dividend from a Stock or ETF"*) **cannot carry a `security_id`** — the fence raises. **Per-security income attribution is structurally unavailable in V1**, by a constraint that predates §2.3 and is not this milestone's to relax. Not an edge the predicate mis-decides; an edge the schema decides *for* it.

**DRAFTING-READY: how each issue cites this.**

| Issue | Cites |
|---|---|
| SELF-248 | `in_queue()` for the endpoint's refusal set; **E3** as a mandatory LEFT-JOIN clause; **E1** pending its ruling |
| SELF-249 | `classifiable()` for which rows render an enabled picker — **replaces AC6's "AcctSetup transactions"**, which names a Cat that does not exist (G2); M4 for the split-parent render |
| SELF-250 | **P5** for the sum set + M1–M4 for exclusions; **E3**; the `split_count` branch is M4, not a separate rule |
| SELF-253 | same as SELF-250, plus its own account filter and the D1/AC3 as-of coupling |
| SELF-255 | **P5** narrowed to `cat = 'Expense'` + the `is_tax_payment` gate (D3); M1–M4; **E3** |
| SELF-251 · 254 · 256 | **`in_queue()` applied per-surface** — the S-2 banner's `N`. **One source**, not three counts (sitting item 4) |
| SELF-250 · 253 · 255 · 256 | **the S-3 period grammar** — column windows, the em-dash rule, and the clock. One grammar (sitting item 5) |
| SELF-248 · 249 | **S-4**: `classifiable()` as a **write-path guard**, not only a render filter; and the **§2.4.3 reverse-and-replace flow** as the sanctioned cross-domain route (sitting item 6) |
| SELF-249 | **S-5**: the classify UI is **whole-item** at the queue grain; **splitting is not a §2.3 surface** — its venue is the shipped §2.4.3 split write path (`038` Part A: direct DML on `pfin.account_trans_split` under the locked child-lifecycle rule). ⚠ A **different** §2.4.3 mechanism from S-4's row above (sitting item 7) |
| SELF-257 | a battery leg per M-rule and per edge, incl. the **E3 fail-silent** case (a fixture that annotates every row cannot catch it) |

Sec joint-review: this predicate is **not itself a Sec surface** — it authors nothing. It becomes one at each consuming issue, all of which already carry the gate (§6). ⚠ But **E1 is Sec-visible**: an unnetted reversal is a money-correctness defect, and it should be named at the SELF-250 joint review whichever way it is ruled.

**S-2 — Unclassified-state rendering — ✅ RULED (b), loud exclusion (sitting item 4).**

**The ruling, verbatim:** *"Unclassified rows stay out of §2.3 sums; every §2.3 table carries the banner ('N transactions unclassified — classify') with a CTA into the §2.3.1 queue, totals footnoted as partial — the V1.2 loud-unpriced pattern applied. N derives from Architect's `in_queue` predicate (item 3a), one source."*

**`N` IS `in_queue()` APPLIED PER SURFACE, AND "PER SURFACE" IS THE LOAD-BEARING HALF.** *One source* does not mean *one number*. A banner whose scope differs from its table's scope is worse than no banner: it reports rows the reader cannot find, and the reader concludes the classify queue is broken. **Each surface counts `in_queue()` over exactly the row set its own table filters to** — same account filter, same period window, same as-of predicate. Stated per surface so it is not re-derived three times:

| Surface | `N` counts `in_queue()` rows … |
|---|---|
| **SELF-251** (§2.3.2 cross-account rollup) | across every account the user holds, within the **rendered year** — not all-time. A banner counting 2019 rows above a 2026 table sends the user to a queue where the rows are not visibly related to what they were reading. |
| **SELF-254** (§2.3.3 per-account drill-down) | scoped to the **named account**, the rendered year, **and the same as-of predicate the table uses** (`transaction_date <= as_of AND created_at <= as_of`). ⚠ If the banner ignores the as-of, a historical view reports rows that did not exist at that as-of — the exact retroactive-visibility hazard Lock 15 mod #1 re-introduced `created_at` to close. |
| **SELF-256** (§2.3.4 Historical Expenditures) | over the **5-year window**. ⚠ **And the copy cannot say "unclassified expenses"** — an unclassified row has no `cat`, so nothing knows whether it *would be* an Expense. The honest wording is *"N unclassified transactions — any of these may be expenses"*. Claiming the narrower thing would be the quiet dishonesty a loud-exclusion ruling exists to prevent. |

**Two consequences that follow from the predicate and belong in the ACs, not in UI review:**

- ⚠ **`N` is a count over a UNION OF TWO GRAINS** — unsplit transactions **and** split children (S-1's queue grain; edge **E4**). So the literal string *"N transactions unclassified"* is wrong whenever any split child is in the queue. **Proposed copy: "N items unclassified".** Flagging rather than silently rewording, because the ruling quotes the string.
- **"Totals footnoted as partial" must be unconditional-on-`N`, not decorative.** The footnote renders **iff `N > 0`**, and the total it foots is the same total the table sums — i.e. the footnote is derived from the same query, not from a second count. Two counts of "how much is missing" drift, and the drift is invisible because both look plausible.

**Not in scope:** option (c) remains the §5.3 V2 candidate per the ruling. The PRD half lands as amendment A-3 (PM).

Sec joint-review: **not triggered by S-2 itself** — it renders, it does not compute money. It rides the existing gates on the consuming issues.

**S-2b — The compound-journal §2.3 constraint (E2 ruled: gated at the first creator).**

**Attaches to:** whichever future issue **first writes a `pfin.journal` row with `group_type = 'compound'`**. No such path exists in the tree today, and no current V1.3 issue creates one. (⚠ Not §7.3 **G1** — that is `transfer_in_kind`, a different member of `033:239`'s three-value vocabulary.)

**What it must decide, all four, before its own merge:**

1. **May a compound journal's legs span accounting classes?** (a Transfer leg and a genuine Expense leg in one group). If no, M3 stays correct forever and this constraint closes.
2. **If yes — does M3 stay leg-blind or become per-leg?** Leg-blind (today) drops every leg of a compound group from §2.3. Per-leg would exclude only legs whose own prototype is `Transfer`/`Trade`. ⚠ **Per-leg is a BREAKING CHANGE to the S-1 predicate**, so every §2.3 consumer re-derives and every §2.3 total moves. That is an amendment to this findings pass's ruled predicate, not a local fix.
3. **Does the Σ=0 conservation law hold for compound groups?** ADR-031 Decision 5 selects it on `group_type='transfer'`. A compound group may not conserve, and if it does not, excluding its legs from §2.3 is not obviously the safe direction.
4. **Sec joint-review: MANDATORY at that issue** — changing M3 changes what every §2.3 money surface sums.

**The watcher, because a gate with no trigger is a note.** Nothing today would tell anyone the first creator has arrived. The gate becomes real with **one QA assertion: `pfin.journal` holds zero rows with `group_type = 'compound'`** — which goes red the moment such a path ships, in that PR, in front of the author who needs to read this. ⚠ A **watcher and not a CHECK constraint**, deliberately: the property is contingent and expected to change, so a constraint forbidding `compound` would block the legitimate future work this gate exists to *inform*. (Contrast the standing dead-leg rule, which bars a constraint over a property guaranteed by construction — a different case with the same surface shape.)

⚠ **Label provenance, stated so it does not harden.** *"S-2b"* is this document's local handle, coined here. **It is not a ratified identifier**, and it must not travel into a commit subject, a migration header or an issue title under that name — the canonical name comes from the issue it eventually attaches to. Recorded because a self-authored label has previously hardened into fact in this repo by exactly that route.

**S-3 — Period grammar × as-of — ✅ RULED (a) with three companions (sitting item 5); grammar defined here.**

**The ruling, verbatim:** *"Month = the month containing as-of date D. Companions: (1) YTD = Jan 1 of year(D) → D; (2) quarters not yet started relative to D render em-dash, NEVER $0; (3) 'today' is server-derived per Lock 15, ADR-044 two-clock discipline — which clock is Architect's call."*

**THE GRAMMAR — stated once; SELF-250, SELF-253, SELF-255 and SELF-256 cite it, none restates it.** Let `D` be the as-of date (server-derived — see the clock call below). Every window is **inclusive of both bounds** and **truncated at `D`**.

| Column | Window | Renders |
|---|---|---|
| **Month** | `date_trunc('month', D)` → `D` | value (partial month — **not** the whole calendar month) |
| **Q1–Q4** | quarter `k` of `year(D)`: `start(k)` → `least(end(k), D)` | value if `start(k) <= D`; **em-dash if `start(k) > D`** |
| **YTD** | `Jan 1 of year(D)` → `D` | value |

**Three properties that follow, and that a naive implementation breaks:**

1. **The truncated quarters PARTITION the YTD window exactly, so `ΣQ1..Q4 = YTD`.** That is a free correctness watcher on any §2.3 aggregate, and it **fails immediately** under the most likely wrong implementation — untruncated calendar quarters, where the current quarter overshoots `D` and the identity breaks by exactly the remainder of the quarter. **Proposed as a battery leg on SELF-257**, not merely as prose.
2. **The columns are NOT disjoint — `Month ⊂ its own quarter ⊂ YTD`.** So a Total row sums **down** each column and **never across**. Anyone adding Month to the quarters double-counts. Stated because the ACs say *"Total foot row sums the section's Sub-Cats across each period column"*, and *"across"* there means *"for each column independently"* — a sentence one comma away from meaning the wrong thing.
3. **`year(D)`, not the current year.** A §2.3.3 drill-down at `D = 2024-06-15` renders **2024's** Q1 full, Q2 truncated at Jun 15, Q3/Q4 em-dash, YTD = Jan 1 2024 → Jun 15 2024. The ruling's *"relative to D"* is doing all the work in that sentence.

**⚠ THE EM-DASH RULE HAS TWO SIDES, AND THE RULING STATES ONLY ONE.** *"Quarters not yet started render em-dash, NEVER $0"* is the first side. The second side is its inverse and is equally load-bearing: **a quarter that HAS started and simply had no transactions renders `$0`, and must NOT render an em-dash.** `$0` is a real answer — *"you spent nothing in Q1"* — and collapsing it to an em-dash hides information the user asked for. Two distinct states share one shape at the contract boundary, and a single `coalesce` erases the distinction:

```
start(k) >  D   ->  NULL      ->  renders em-dash   ("this period does not exist yet")
start(k) <= D   ->  0::numeric ->  renders $0        ("this period exists and is empty")
```

The **function returns NULL, never a fabricated zero, for the unstarted case**, and the **renderer** maps NULL → em-dash. Same discipline as `067` (*"NULL — never zero"*) and ADR-061's gate structure: the null-ness is computed **once**, from the window definition, and handed to the renderer — never re-derived at the render site.

**THE CLOCK — my call, as delegated: `pfin.fn_server_today()` (the DATABASE clock), threaded explicitly.**

**Rationale, one line as asked:** §2.3's as-of predicate includes `created_at <= D`, and `created_at` is `timestamptz` (`004:127`) — a `timestamptz`-vs-`date` comparison is evaluated **in the session TimeZone**, which is precisely the shape ADR-044 was written about, so its Decision 2 answer applies unchanged and no new ruling is needed.

Three riders, because the call carries obligations that are easy to drop:

- **⚠ The zero-round-trip variant stays RULED OUT, and §2.3 gives it a live case rather than an inherited one.** ADR-044 rejected letting `p_as_of` default to `current_date` inside the function, partly because *"headline and composition are two separate PostgREST requests, each defaulting independently, and a pair straddling midnight stops footing with no error."* **§2.3 has exactly that shape**: SELF-251 and SELF-254 each render a table **and** the S-2 banner `N`, and if those are two calls that each defaulted, the banner and the table could disagree across midnight. **The app resolves `D` once per request and threads it to every consumer, including the banner count.**
- **The value must be branded, which means a factory and not a cast.** `api/src/lib/server/time/asOf.ts` is explicit that **only its own casts may produce `ZoneResolvedAsOf`** — currently three, enumerable on purpose, with `grep -rn 'as ZoneResolvedAsOf' src/` as the review check. A DB-derived today arrives as a plain string, so adopting this call means **Backend adds one factory in that one file** (a `databaseTodayAsOf`-shaped sibling to `serverTodayAsOf`), not a cast at the §2.3 call site. Cheap, and it keeps the fence's enumerability intact.
- **⚠ This does NOT retire the `061` pin, and I am not declaring ADR-044's outstanding correction done.** ADR-044 Decision 3 is explicit that R2 guarantees *both sides of one comparison* use the same day but not **which** day, and nothing across containers; and it names the exact sentence a re-pointer owes — ***"the pin is no longer the app's within-comparison guarantee,"*** never *"the pin is no longer load-bearing."* That correction to `060` / the runbook / `asOf.ts` is recorded there as **outstanding**, and it is not this pass's to close.

**`p_year` IS STRUCK — ✅ RULED (sitting item 5a, default-and-notify).** SELF-250 took `p_year INT`; SELF-253 took **both** `p_year` and `p_as_of_date`. Under this grammar the year is `year(D)`, so `p_year` was redundant **and** a second parameter that could disagree with the first about the same fact — with nothing in either AC saying which wins for `p_year = 2025` against `D = 2026-03-01`. **Both signatures lose it; the year derives from `D`.**

Resulting signatures, with every strike attributed so no reviewer has to reconstruct which generator removed what:

| | Was | Is | Struck by |
|---|---|---|---|
| **SELF-250** | `(p_users_id UUID, p_scope pfin.scope[], p_year INT)` | **`(p_as_of date)`** | `p_users_id` + `p_scope` → **G4** (`pfin.scope` is schema-impossible; INVOKER scopes by `auth.uid()`); `p_year` → **item 5a** |
| **SELF-253** | `(p_users_id UUID, p_account_id UUID, p_year INT, p_as_of_date DATE DEFAULT CURRENT_DATE)` | **`(p_account_id bigint, p_as_of date)`** | `p_users_id` → **G4**; `p_account_id` retyped `uuid`→`bigint` (`003:92`); `p_year` → **item 5a**; the `DEFAULT CURRENT_DATE` → **S-3's clock riders** (ADR-044's zero-round-trip variant stays ruled out — the app threads `D`, the function does not default it) |

⚠ **SELF-250 keeps a parameter rather than becoming no-arg, and that is deliberate.** It is not a client toggle — Lock 15 reserves that for §2.3.3 — but ADR-044 Decision 2 requires the app to resolve `D` **once per request and thread it explicitly**, precisely so a table and its S-2 banner cannot default independently and straddle midnight. A no-arg §2.3.2 function would re-introduce the variant ADR-044 ruled out.

⚠ **The parameter's NAME is still open and is not settled here.** Lock 15 says `p_data_as_of`; every shipped §2.1/§2.2 helper uses `p_as_of`. The sitting log books that as *"settle once in the ADR at amendment time"* — so the shape above is written with the shipped idiom as a placeholder, and **whichever name the ADR picks must be applied to both rows in one edit**, not per-function.

Sec joint-review: **not triggered by the grammar itself.** It rides the existing gates on SELF-250/253/255. ⚠ The **clock** half is Sec-adjacent — it lands inside the Lock 15 as-of fence that SELF-247 owns and D6 has open — so it should be named at that review rather than assumed settled by this item.

**S-4 — Cross-domain correction — ✅ RULED (a) (sitting item 6). Answer: HALF discharged by construction; the other half needs an explicit write-path guard, and the reason is measured, not stylistic.**

**The ruling, verbatim:** *"Domain moves happen ONLY via the §2.4.3 edit / reverse-and-replace flow; the §2.3 picker stays strictly within the cashflow domain (matches the `023` fence; a domain move is a re-posting and reverse-and-replace is the ledger's sanctioned re-post). Costs one §2.3.1 pointer sentence telling the user where cross-domain fixes live."*

**HALF ONE — the literal claim IS discharged by construction. No additional constraint is needed for it.** *"Stays strictly within the cashflow domain"* means the picker cannot write a **storage-side** taxonomy id. Since `084` re-targeted `account_trans_annotation.sub_cat_id` to `pfin.posting_prototype(id)` ON DELETE RESTRICT, **there is no other vocabulary the column can reference** — a `user_taxonomy` id fails the FK. Two further DB fences ride along on the same write: the D3 matched-tenant trigger (chain-resolved to the annotation's owning tenant, NULL-safe fail-closed) and the trade biconditional at `084:1233` (`(security_id is not null) <> (cat = 'Trade')` → raise), which independently blocks classifying a cash row as `Trade` or a security row as anything else. **Cross-vocabulary, cross-tenant and cross-Trade are all structurally unreachable.** Nothing to add.

**HALF TWO — `classifiable()` is a READ-side predicate and NOTHING ENFORCES IT AT THE WRITE PATH.** This is the gap the ruling's framing does not reach, and it is easy to miss precisely because half one is so well fenced. Measured against the four mechanical rules:

| Rule | Can the 248 endpoint write an annotation on such a row? | What the GL then does |
|---|---|---|
| **M1** `transaction_type <> 'standard'` | **YES — unblocked.** No trigger objects (`security_id` NULL + a non-Trade cat satisfies the biconditional) | P3 is scoped `transaction_type = 'standard'` (`084:885`), so the value is **never read**. Fail-silent. |
| **M2** `security_id IS NOT NULL` | **NO — blocked** by the trade biconditional | n/a |
| **M3** journaled leg (`annotation.journal_id IS NOT NULL`) | **YES — unblocked** | ⚠ **NOT fail-silent. See below.** |
| **M4** split parent (`split_count > 0`) | **YES — unblocked.** `029` states the XOR is *"an M4-GL read rule, NOT DB-enforced here"* | P3 carries `and t.split_count = 0`; the children branch (P4) reads the **children's** cats. Fail-silent. |

**⚠ M3 IS A MONEY DEFECT, NOT A FAIL-SILENT ONE — and it is reachable today.** `fn_gl_entries`' P3 contra is a `case` evaluated **in order** (`084:869–872`): `Revenue` → `Expense` → `Equity` → `Transfer AND journal_id is not null` → else `Suspense`. A journaled transfer leg reaches `'Journal Clearing'` **only** by falling through the first three. **Write an `Expense` prototype onto that leg and it matches at the second branch instead** — the leg posts as an **Expense**, the journal's clearing contra never forms, and **a transfer between the user's own accounts appears as spending** in exactly the §2.3 surfaces this milestone builds. No error, no constraint, no log line. The read-side predicate says *"do not offer the picker here"*; nothing stops a client from POSTing it anyway.

**✅ RULED (sitting item 6a, default-and-notify): the SELF-248 endpoint refuses writes where `classifiable()` is false** — all four mechanical rules, generalising the split-parent refusal from M4-only. App-layer, in scope, cheap. Encoded as a mandatory AC in SELF-248's table above. **The DB-fence half is QUEUED as D-8** — hardening `029`'s deliberately-soft precedence rule is an options call with its own Sec review, and it is not folded in here.

**A second-order note on the same branch, since the picker can reach it.** `Transfer` **without** a `journal_id` falls to the `else` — **`Suspense`**, not a clean offset. So a user classifying an inter-account transfer through the §2.3 picker on a leg that was never journal-attached produces a Suspense entry rather than the netting ADR-032 Decision 2 describes. That is existing designed behaviour and not a defect of this milestone, but it is a **user-visible consequence of a picker action**, so §2.3.1's copy should not promise that categorising a transfer makes it "cancel out."

**THE SANCTIONED CROSS-DOMAIN ROUTE — §2.4.3 reverse-and-replace, and why the boundary is principled rather than a limitation to apologise for.** The picker changes a row's **classification**; a domain move changes a row's **facts** (a row ingested as cash that is really a securities trade needs a `security_id`, which the trade biconditional then *requires* be classified `Trade`). Facts on `pfin.account_trans` are immutable (`004`), so the only way to change them is ADR-032's ratified path (b): **reverse-and-replace** — a reversal row plus a replacement row, with `source_provider`/`provider_txn_id`/`import_hash` staying on the original only. Added to the citation table for SELF-248/249, and it is what the ruling's *"one §2.3.1 pointer sentence"* must point at.

⚠ **And it collides with an open item.** That pointer sends users to a flow which, per **E1** (queued for F/CTO at item 3c), currently drops **both** halves of the reverse-and-replace pair into the classify queue with no link between them. **S-4's sanctioned route is E1's unresolved case** — so the §2.3.1 pointer sentence should not be written before E1 is ruled, or it will document a route that produces two unclassified rows where the user expected one correction.

Sec joint-review: **MANDATORY at SELF-248** — the M3 finding is a money-flow defect on the classify write path, and it should be named explicitly at that review rather than left to be re-derived. Half one (the FK / matched-tenant / biconditional fences) is worth stating there too, so the reviewer can see what is already held and what is being added.

**D-8 — Should `classifiable()` ALSO be a DB fence on `account_trans_annotation` writes? (SELF-248) — ✅ RULED (sitting item 15): YES, option (C) as Sec reformulated it.**

**Outcome:** Sec's bounded consult ruled **(A) out** — they declined to state that non-endpoint `authenticated` paths are outside V1's threat model, which was the sole condition (A) rested on — and chose **(C)** with three reformulations (**C′** predicate, **C″** scoping, **C‴** placement), each of which **corrected my own formulation**. F/CTO confirmed 2026-08-22. **The drafting-ready spec, the three corrections and the seven binding conditions live with SELF-248 in §3** — this item records the decision and does not restate them. The options analysis below is retained as the record of what was weighed.

**What is already ruled and is not re-opened by this item:** the app-layer guard ships (item 6a). D-8 asks only whether a second layer is added beneath it.

**SELF-CONTAINED CONTEXT (inlined for a cold reader — everything below is restated here so this section can be read alone).**

`classifiable()` is the §2.3 read-side predicate ruled at sitting item 3 and extended at item 8. It decides which ledger rows the §2.3 classify UI may offer and which the §2.3 surfaces may sum:

```
classifiable(row) := transaction_type = 'standard'      -- M1: not acct_setup / basis_adjust / corp_action (030:153)
                 AND security_id IS NULL                -- M2: not a securities row (084:1233 biconditional)
                 AND split_count = 0                    -- M4: not a split PARENT (its children carry the categories)
                 AND is_reverse = false                 -- E1: not a reverse-and-replace reversal row
                 AND (annotation IS NULL
                      OR annotation.journal_id IS NULL) -- M3: not a leg attached to a journal group (033:403)
```

**Rows are classified by writing `pfin.account_trans_annotation.sub_cat_id`** — a per-transaction overlay on the immutable `account_trans` ledger (`023`), whose `sub_cat_id` FK re-targeted to `pfin.posting_prototype` at `084`.

**THE MONEY DEFECT (M3), shown rather than cited.** `pfin.fn_gl_entries`' P3 cash-flow contra branch selects the ledger account with an **ordered `CASE`** (`084:869–872`):

```
case when flow_class = 'Revenue'  then 'Revenue'
     when flow_class = 'Expense'  then 'Expense'
     when flow_class = 'Equity'   then 'Equity'
     when flow_class = 'Transfer' and journal_id is not null then 'Journal Clearing'
     else 'Suspense' end
```

A journaled transfer leg reaches `Journal Clearing` **only by falling through the first three branches**. Writing an `Expense` prototype onto that leg matches at the **second** branch instead — the leg posts as an **Expense**, the journal's clearing contra never forms, and **a transfer between the user's own accounts appears as spending** on every §2.3 surface. No error, no constraint, no log line.

**What is already fenced on this write path ("half one"), so the reviewer sees held-versus-added:** cross-**vocabulary** writes are unreachable (the `084` FK targets `posting_prototype`, and a storage-side `user_taxonomy` id fails it); cross-**tenant** writes are refused by the Decision-3 matched-tenant trigger, chain-resolved via `trans_id → account_trans.account_id → account.users_id`, NULL-safe fail-closed; cross-**Trade** writes are refused by the `084:1233` biconditional `(security_id is not null) <> (cat = 'Trade')`. **M1, M3 and M4 are fenced by none of these.**

**Why the question is live rather than theoretical.** `023` grants `authenticated` **full CRUD** on `account_trans_annotation`. An app-layer refusal at one endpoint therefore does not bound what other paths may send — a direct PostgREST call under `authenticated`, a future bulk-import path, a second client. **The repo has already measured this exact shape once**: the SD-22 DELETE-policy note records that *"the SELF-242 endpoint's own `.eq('users_id', …)` predicate is an app-layer control and does not bound what other paths may send"*, and QA demonstrated the bypass with a corrupt-the-control pair. The M3 case is money-visible, so the same reasoning applies with more force here, not less.

**Options.**

- **(A) App guard only** — status quo after item 6a. Zero new DB surface, zero risk to existing flows. **Cost:** the money defect (M3) remains reachable by any path that is not that endpoint, and the bypass is not hypothetical — see above.
- **(B) A BEFORE INSERT OR UPDATE trigger on `account_trans_annotation` enforcing `classifiable()`.** Fail-closed on every path. **Cost, and this is the part a naive implementation gets wrong:** the annotation row carries `sub_cat_id`, `note` **and** `journal_id`, and **journal attachment happens by UPDATE-ing `journal_id` on this same row** (`037:643` already carries a trigger reacting to those transitions). A trigger scoped the obvious way — `WHEN sub_cat_id IS NOT NULL`, mirroring `030`'s trade-constraints fence — would fire on that attachment UPDATE, see `journal_id IS NOT NULL` on NEW, evaluate M3 as true, and **raise: journal attachment becomes impossible for any already-classified leg.** The fence must instead be scoped to *"the classification itself is changing"* (`WHEN new.sub_cat_id IS DISTINCT FROM old.sub_cat_id`). **B is viable; it is not a transplant of an existing fence's shape.** It also hardens `029`'s explicitly-soft rule (*"PRECEDENCE (soft) … an M4-GL read rule, NOT DB-enforced here"*), which is a ratified position and should be amended deliberately rather than by side effect.
- **(C) A narrow DB fence on the money case only** — refuse a `sub_cat_id` whose `cat` is not `Transfer` when `journal_id IS NOT NULL`, leaving M1 and M4 to the app guard. **Rationale:** M3 is the only rule whose violation is measured to be money-visible; M1 and M4 are fail-silent by measurement (P3 is scoped `transaction_type = 'standard'` and carries `and t.split_count = 0`, so the value written is never read). Smallest fence that covers the demonstrated defect, leaves `029`'s soft rule soft, and needs only the lookup the existing fences already perform. **Cost:** it fences one rule and not a class, so a future reader may not see why the other three are unfenced — the header has to say it, and a partial fence that does not explain itself invites either removal or over-extension.

**My lean was (C)**, on the ground that the fence should sit where the measurement put the hazard — and I held it loosely, on the stated condition that **(A) is defensible only if someone is willing to state that the non-endpoint paths are out of V1's threat model**, a Sec judgement rather than an architecture preference. ⚠ **That condition resolved: Sec declined to make the statement, so (A) fell.** ✅ **The direction was right and my three formulations of it were not** — see the C′/C″/C‴ corrections with SELF-248 in §3. Retained as written so the reasoning that led here stays legible.

**What Sec's SELF-248 review brief must carry** (per item 6a, recorded so it is not reassembled from three places): the **M3 finding** with its `084:869–872` ordered-`case` mechanism; **what half one already fences** (the `084` FK re-target, the D3 matched-tenant trigger, the `084:1233` trade biconditional) so the reviewer can see what is held versus what is being added; the **`023` full-CRUD grant** that makes the app guard bypassable; and the **B-scoping hazard** above, so it is not discovered during implementation.

**S-5 — Split vs assignment granularity — ✅ RULED (a) (sitting item 7). All five seams ruled.**

**The ruling, verbatim:** *"The V1.3 classify UI is whole-item; splitting stays in the shipped §2.4.3 flow (`038` split write, per-child `p_sub_cat_id`); split children classify independently in the queue (already accommodated by the S-1 predicate + the 'N items' grain). No new UI. Mixed transactions take two steps in two places, stated honestly in the PRD."*

**VERIFICATION OF THE THREE PREREQUISITES — two were already present, one was NOT.** Checked against the file rather than assumed:

| Prerequisite | State | Where |
|---|---|---|
| M4 split-parent exclusion | ✅ **already in** — not re-added | S-1's mechanical table (M4) + cited for SELF-249 and SELF-250 in the citation table |
| Child-grain queue membership | ✅ **already in** — not re-added | S-1's `in_queue` block (the child-grain clause) + edge **E4** + S-2's *"N items"* grain note |
| §2.4.3 as the **split venue** | ❌ **WAS MISSING — added this turn** | see below |

**⚠ WHY THE THIRD WAS MISSING, AND WHY IT IS NOT A DUPLICATE OF WHAT WAS THERE.** The file already cited §2.4.3 three times — all of them for **reverse-and-replace**, the sanctioned **cross-domain** route (S-4). **§2.4.3 hosts two different mechanisms, and S-4 and S-5 point at different ones:**

- **reverse-and-replace** (ADR-032 path (b)) changes a row's **facts** on the immutable ledger — a reversal row plus a replacement row. That is S-4's route.
- **the split write path** (`038` Part A) changes **how one row's amount is apportioned** — children on `pfin.account_trans_split`, parent untouched. That is S-5's venue.

Reading the existing §2.4.3 citation as covering both would have sent a builder to the wrong mechanism. Recorded because the two are one PRD section apart and read as interchangeable in a summary.

**⚠ ONE CORRECTION TO THE RULING'S OWN WORDING, flagged because copying it verbatim would generate a schema-impossible AC.** The ruling says *"`038` split write, **per-child `p_sub_cat_id`**"*. Measured: **`038` authors exactly one function** — `fn_create_manual_trans` (`038:276`) — and its `p_sub_cat_id` is the **parent's annotation** category, not a per-child anything. **There is no split RPC and no per-child parameter.** Split children are written by **direct table DML** under `grant insert, update, delete on pfin.account_trans_split to authenticated` (`038:269`), governed by the locked child-lifecycle rule (CREATE a balanced set · REPLACE atomically · UNSPLIT), with `029`'s deferred Σ=parent constraint trigger rejecting any unbalancing mutation at COMMIT. The child's category is the `sub_cat_id` **column** on `029`, not a function argument. **Both halves of the phrase name something real; the compound does not exist.**

**WHAT "WHOLE-ITEM" MEANS PRECISELY — and it is not "whole-transaction".** The classify UI's unit is the **S-1 queue grain**: an unsplit transaction **or** a split child. So a split parent is never the unit, and a split child is a first-class unit. ⚠ This is why the ruling's own word is *item* and not *transaction*, and it lines up exactly with the S-2 banner copy correction (*"N items unclassified"*) — **the same grain, named consistently in both places.** Neither is a wording preference; both are E4.

**AC consequences — no new surface, so these are constraints on existing ACs rather than additions:**

- **SELF-249** — the split-parent row renders its **children's** Sub-Cats read-only and routes any edit to the existing §2.4.3 split editor, offering no parent-level picker. Already carried as a G6 AC on that issue; S-5 ratifies it rather than changing it. **"No new UI" means the route target must already exist** — it does (`038` Part A shipped), so this is a link, not a build.
- **SELF-248** — unchanged. The write-path guard ruled at item 6a already refuses M4 parents; S-5 adds nothing to it.
- **PRD (PM)** — *"mixed transactions take two steps in two places, stated honestly"* is a §2.3.1 copy obligation, and it composes with the **two other** §2.3.1 copy constraints already routed to PM: the E4 grain correction, and the S-4 *"transfers do not necessarily cancel out"* constraint. ⚠ **Three separate constraints now land on one PRD passage** — worth PM handling them as one edit rather than three, or the later ones will read as contradicting the earlier.

Sec joint-review: **not triggered.** S-5 authors nothing, changes no write path, and adds no surface; it rides the gates already on SELF-248/249.

**E1-M — The shipped reverse flow, MEASURED (F/CTO rider question, sitting item 8).**

Every claim below is read from the tree at `0491830`, with `file:line`. Nothing here is from recall.

**THE SHIPPED FLOW** is `reverseAndReplaceTrans` in `api/src/lib/server/queries/transactions.ts:138`. It writes the `{reversal, corrected}` pair as **one bulk INSERT** into `pfin.account_trans` (`transactions.ts:212`), then does a follow-up annotation upsert.

**ANSWER (1) — the annotation / `sub_cat_id` on a reversal: the shipped flow writes NONE, and that matches E1 (a) exactly. No reconciliation is owed.**

- The `reversal` object (`transactions.ts:170–181`) sets `account_id`, `transaction_date`, `amount` (negated), `vendor`, `description`, `transaction_type`, `security_id`, `quantity` (negated), `is_reverse: true`, `replaces_trans_id`. **It contains no annotation write of any kind.**
- The annotation upsert is at `transactions.ts:229–234` and is gated on `newId`, which is taken from `inserted.find((r) => r.is_reverse === false)` (`transactions.ts:227`) — **the corrected row**. The reversal is structurally excluded from being its target.
- The function's own header states the design: *"The corrected row's category/note is a follow-up `023` annotation upsert"* (`transactions.ts:132–134`).

> **Quotable:** *the shipped reverse-and-replace flow never writes an annotation for the reversal row. E1 (a)'s requirement that reversals carry no `sub_cat_id` is already true of the code as merged; the amendment orders no reconciliation, only an exclusion the readers must honour.*

**ANSWER (2) — `journal_id` on a reversal: it CANNOT have one, and the pair does NOT net inside the journal.**

- `journal_id` is a column on **`pfin.account_trans_annotation`**, not on `account_trans` (`033:403`). Since the flow writes no annotation for the reversal, **a reversal cannot carry `journal_id`** — it is never a journal member. This is structural, not a policy.
- **ADR-031 D5's Σ=0 conservation is NOT violated.** `fn_journal_close_balance` computes membership as `join pfin.account_trans_annotation ann on ann.trans_id = at.trans_id where ann.journal_id = new.journal_id` (`037:551–557`). The reversal is outside that join, so the group still sums to zero over its original legs. **The reversal does not break the law; it sits outside it.**
- ⚠ **But the check is close-time-only and is never re-evaluated.** It runs in a BEFORE UPDATE trigger on `pfin.journal` at open→closed (`037:515`). Nothing re-checks a journal after it closes.
- ⚠ **And the closed-journal membership freeze does not fire either.** `fn_account_trans_annotation_freeze_closed` (`037:633`) rejects INSERT/UPDATE/DELETE on an annotation whose journal is closed — **it guards annotation writes, and the reversal writes none.** So **a leg of an already-CLOSED, balanced journal can be reversed, and neither guard fires.** The journal remains closed and balanced over a leg whose economic effect has been reversed outside it.

**WHAT THE GL CONTRA `CASE` DOES WITH THE PAIR** (`084:864–887`, P3, evaluated in order):

| Row | `flow_class` | Branch taken | `entry_account` | `amount_book` |
|---|---|---|---|---|
| **Original**, journaled transfer leg | `'Transfer'` **and** `journal_id` not null | `084:872` | **`Journal Clearing`** | `-amount` |
| **Reversal** | **NULL** (no annotation → the `left join posting_prototype` at `084:786` yields nothing) | falls through to the `else` at `084:873` | **`Suspense`** | `-(-amount)` = `+amount` |

> **Quotable:** *a reversal of a journaled leg is not in the journal and cannot be. The group's Σ=0 still holds over its original members, so ADR-031 D5 is not violated — but the reversal's own contra falls through the ordered `CASE` to **Suspense**, leaving a permanent Suspense residual equal to the reversed amount. The pair posts `Journal Clearing` / `Suspense`, not a netted pair.*

**⚠ TWO CONSEQUENCES OF (a) THAT THE MEASUREMENT EXPOSES — neither blocks the ruling; both need a home.**

1. **§2.3 and the GL will disagree about where a reversal sits, and this is not confined to journaled legs.** *Any* reversal of a classified cash row carries no annotation, so its GL contra is `Suspense` — while E1 (a) has §2.3 net it **inside the original's Sub-Cat**. So a §2.3 Expense total is net-of-reversals and the GL's Expense account is not, differing by exactly the reversed amounts with an offsetting Suspense balance. **E1 (a) is a §2.3 READER rule; the GL has a different, already-shipped treatment, and nothing reconciles them.** That is fine as long as nobody ties the two together — but **BACKLOG §7.24 item 3 books a totals-equality watcher at a GL seam, and §5.3 books a GL-native P&L**, and both would surface this as a discrepancy. **Recommend booking it now** rather than discovering it at that watcher.
2. **An existing soft guard becomes load-bearing for money correctness.** The double-edit guard at `transactions.ts:157–166` refuses reversing an already-reversed row, and the code says of itself: *"Not a hard DB constraint — TOCTOU-narrow, single-user; a partial-unique index on `replaces_trans_id` would harden it (Architect flag)."* Under (a)'s structural netting, **two reversals pointing at one original would double-net the §2.3 figure** — so what was edit hygiene is now a money invariant. ⚠ **Recommend promoting the flagged partial-unique index on `replaces_trans_id` (where `is_reverse`) from a code comment to a migration**, and doing it in the same wave as the §2.3 readers rather than after them.

**Sec:** SELF-250's joint review names the netting invariant explicitly (item 8). It should also carry consequence (1) — that §2.3's netted total and the GL's Suspense-offset total are both correct and are not equal — so the reviewer is not left to derive it from a discrepancy later.

**D1 — The §2.3 read substrate, ruled jointly with 247-AC3 — ✅ RULED (iii), the hybrid (sitting item 9).**

**The ruling, verbatim:** *"ONE extracted §2.3 reader over `account_trans` housing every reader rule once (S-1 predicate · split XOR · E1 netting join · E3 LEFT JOIN · S-3 period grammar · the Lock 15 dual-column as-of filter); 250/253/255 compose on it, adding only their own shaping. `fn_gl_entries` untouched. **247-AC3 lands INSIDE the shared reader for free**. One battery leg on 257 covers the rules once. The reader is V1.3's real foundation piece, landing with SELF-250."*

⚠ **PROVISIONAL NAME — `pfin.fn_cashflow_items(p_as_of date)`.** Coined here as a working handle. **Not ratified**; it must not travel into a commit subject, a migration header or an issue title under this name until the SELF-250 amendment fixes it. (Same discipline as the S-2b label: a self-authored name has hardened into fact in this repo by exactly that route.)

**CONTRACT.** SECURITY INVOKER (Lock 11 default — no DEFINER proposed), `stable`, `set search_path = ''`. Tenant isolation is **inherited** from RLS on `pfin.account` / `account_trans` / `account_trans_annotation` / `account_trans_split` under the caller's own session; a cross-tenant caller gets zero rows and fails closed. No tenant parameter (G4).

Input: **`p_as_of date`, threaded by the app, never defaulted in-function** (ADR-044 Decision 2's zero-round-trip variant stays ruled out; S-3's clock call: `pfin.fn_server_today()` is the source).

Emits **ITEM-GRAIN rows** — one per item in the `classifiable()` set, classified or not:

| Column | Notes |
|---|---|
| `item_kind text` | `'transaction'` \| `'split_child'` — the S-5 "whole-item" grain, named in the data |
| `item_id bigint` | `account_trans.trans_id` or `account_trans_split.id` |
| `trans_id bigint` | the owning transaction, on both kinds |
| `account_id bigint` | for SELF-253's filter |
| `transaction_date date` | for SELF-255's own bucketing (see below) |
| `sub_cat_id bigint` | **effective** classification; **NULL = unclassified** |
| `cat text`, `sub_cat text` | from `pfin.posting_prototype`; NULL when unclassified |
| `amount_net numeric(20,4)` | signed, **net of reversals** |
| `in_month`, `in_q1`…`in_q4`, `in_ytd` boolean | S-3 period membership, computed once |

**⚠ THE ROW SET IS THE UNION OF WHAT §2.3 SUMS AND WHAT THE S-2 BANNER COUNTS — deliberately, and it is what makes "one source" true rather than aspirational.** Mechanically-excluded rows (M1–M4, `is_reverse`) never appear. Classifiable-but-unclassified rows appear **with NULL `cat`**. So each surface derives both figures from one query: sum `where sub_cat_id is not null`, count `where sub_cat_id is null`. Two counts of "how much is missing" cannot drift if there is only one query.

**THE SIX RULES, EACH WITH ITS CITATION — housed here and nowhere else:**

| # | Rule | Where it comes from |
|---|---|---|
| 1 | **S-1 predicate** — `transaction_type='standard'` · `security_id IS NULL` · `split_count=0` · `is_reverse=false` · `(annotation IS NULL OR annotation.journal_id IS NULL)` | S-1 (item 3) + E1 (item 8); grounded on `084:885`, `030:153`, `084:1233`, `033:403`, `035`/`037` |
| 2 | **Split XOR (grain emission)** — `split_count > 0` → emit the **children**; else emit the **parent**. Never both | `035`/`037` reader rule; `029` *"a txn is 023-single-categorized XOR split"* |
| 3 | **E1 netting join** — `amount_net = amount + Σ(amount of rows where replaces_trans_id = this trans_id and is_reverse)`. A fully-reversed original nets to **0** and stays inside its **own** Sub-Cat, invariant under later reclassification | E1 (a), item 8 |
| 4 | **E3 LEFT JOIN** — reach `account_trans_annotation` by LEFT JOIN. An inner join silently drops every row with **no annotation at all**, which per `017:188` (*"All txns land Unsorted"*) is most of an ingested book | S-1 edge E3 |
| 5 | **S-3 period grammar** — windows inclusive and truncated at `D`; the flags computed once | S-3 (item 5) |
| 6 | **Lock 15 dual-column as-of** — `transaction_date <= D AND created_at < (D + 1)` | ADR-011 D19 — ⚠ **corrected, see below** |

**⚠⚠ RULE 6 DEVIATES FROM LOCK 15'S VERBATIM TEXT, AND IT MUST — MEASURED, NOT REASONED.** Decision 19 states the filter as `transaction_date <= $1 AND created_at <= $1`. `created_at` is `timestamptz` (`004:127`) and `$1` is a `date`, so Postgres promotes the date to **midnight** and the predicate **excludes every row created ON the as-of date itself**. Measured on the live local stack (`supabase_db_mosko-fintech`, `postgres`, read-only, session `TimeZone=UTC`):

```
current_date::timestamptz          -> 2026-08-22 00:00:00+00
now() <= current_date              -> false      <- a row created TODAY fails the ADR's predicate
now() <  current_date + 1          -> true
```

For `D = today` that means **every transaction the user entered today disappears from every §2.3 surface** — silently, with a correct-looking total. The reader therefore writes the **half-open** upper bound `created_at < (D + 1)`. ⚠ **This is a deviation from a ratified ADR text, not a build detail: it needs an ADR-011 Decision 19 amendment**, and it must not be landed as a quiet implementation choice. Routed. *(The promotion is session-zone-sensitive, which is precisely why S-3's clock call put `D` on the database clock.)*

**WHAT EACH SURFACE ADDS ON TOP — shaping only, no rules:**

| Surface | Shaping |
|---|---|
| **SELF-250** §2.3.2 | filter `cat in ('Revenue','Expense')`; group by `(cat, sub_cat)`; `sum(amount_net) filter (where in_q1)` etc. per column; Total row per section; `N` = count where `sub_cat_id is null`; targets from `pfin.cashflow_target` |
| **SELF-253** §2.3.3 | same, **plus** `account_id = p_account_id`; section set per **D-2** (still open); **no** targets |
| **SELF-255** §2.3.4 | filter `cat = 'Expense'` **and** the D-3 `is_tax_payment` gate; ⚠ **buckets by month itself off `transaction_date`** — see below |
| **SELF-247** | AC3 is discharged **inside** the reader; the issue keeps only the app-layer validation half |

**⚠ ONE HONEST LIMIT: the six period flags do NOT serve §2.3.4.** SELF-255 needs ~60 monthly buckets over a 5-year window, not Month/Q/YTD. It consumes the same **row set and the same six rules**, and does its **own** month bucketing off `transaction_date` within a window that still ends at `D`. Stating it because "one reader" invites the assumption that every surface gets its periods from it, and SELF-255 does not.

**REVERSING A SPLIT PARENT — ✅ RULED (a) (sitting item 9a, default-and-notify): REFUSE AT THE WRITE PATH.** `reverseAndReplaceTrans` refuses reversing a **reversal** (`transactions.ts:152`) but does **not** check `split_count`. Unfenced, rule 2 emits the **children**, rule 1 excludes the reversal, and rule 3 has **no emitted item to net against** — the reversal vanishes from §2.3 entirely. **Ruled: refuse, with a message pointing the user at unsplit-first-then-reverse.** One predicate beside one that already exists. (Rejected: pro-rata across children — invents an apportionment the user never authored; emit-the-parent-as-a-netting-item — re-introduces the double-count rule 2 prevents.)

**⚠⚠ THE REMEDY IS LOSSY, AND SILENTLY SO. MEASURED — the refusal message MUST say it.**

- `unsplitTrans` (`transactions.ts:314`) is a **bare `DELETE` of the entire child set** — `.from('account_trans_split').delete().eq('account_trans_id', transId)`. No confirmation, no snapshot, no report of what was removed. **Every child's `sub_cat_id` is destroyed with the row.**
- **And it is unrecoverable: there is no history table for split children.** `031_reclass_history.sql` creates **only** `pfin.account_trans_annotation_history` and contains **zero** occurrences of "split" (grepped). So the **1:1** annotation's reclassifications are audited (immutable, append-only, `031`) and the **1:many** split children's are **not audited at all**.
- So "unsplit first, then reverse" tells the user to **discard N categorisations they authored**, and today nothing tells them that. After the unsplit the parent is also unclassified (M4 meant it never carried a classification), so it lands in the S-2 banner's queue — a second surprise.

**Encoded as two AC obligations, not one:** (a) SELF-248/the edit path **refuses** reversing a split parent; (b) **the refusal message states the cost explicitly** — *"this transaction is split; removing the split will discard its N line categories, which cannot be recovered"* — because a remedy that is lossy and does not say so is worse than a refusal with no remedy at all.

**⚠ A finding beyond this edge, surfaced by the same measurement and worth its own home:** `023` annotation reclassifications are audited by `031`; `029` split-child reclassifications are **not**, and `writeSplitSet`'s REPLACE path (`transactions.ts:275–285`) also clears the whole set by bare DELETE before re-inserting. **That is an audit-coverage asymmetry across two halves of the same classification feature**, and ADR-011 Decision 2's audit-class discipline is the frame it should be judged under. **Recommend booking it** — it is not V1.3's to fix, but V1.3 is where it becomes visible, because §2.3 is the first surface that makes those classifications valuable.

**SELF-257 BATTERY LEG — one leg per rule, over the reader, and that is the point of extracting it.** Rules 1–6 get tested once rather than three times: the mechanical exclusion set; the split XOR at both grains; a fully-reversed original netting to 0 **inside its own Sub-Cat** and staying there after the original is reclassified; **the E3 case with a fixture that deliberately leaves rows un-annotated** (a fixture that annotates every row cannot catch it); `ΣQ1..Q4 = YTD` (S-3's free watcher); and **a row created ON the as-of date being INCLUDED** (the rule-6 correction — this leg is what would have caught the ADR's literal predicate). Run under `pg_prove`, never bare `psql`.

**Sec gate — the reader is THE money-path for §2.3; joint review lands at SELF-250 with the assembled brief:** the **M3 finding** (`084:869–872` ordered `CASE`; an `Expense` prototype on a journaled leg posts as spending) and what half one already fences (`084` FK re-target · D3 matched-tenant trigger · `084:1233` biconditional) · the **E1 netting invariant** and that `transactions.ts:157–166`'s soft double-edit guard is now **money-load-bearing** (two reversals on one original double-net) · **both-correct-not-equal**: §2.3's netted total and the GL's Suspense-offset total are each right and are not equal · the **rule-6 deviation** from Decision 19's verbatim text · and the **`023` full-CRUD grant** behind **D-8**.

**AC deltas that cite the reader:** SELF-250 gains *"composes on the shared reader; adds shaping only"* and loses its own statements of rules 1–6; SELF-253 the same plus its account filter, and **AC3 becomes a reference** rather than an implementation; SELF-255 the same plus its own month bucketing, stated as a deliberate exception; SELF-247 keeps only the app-layer validation half, with AC3 marked discharged-by-D-1.

⚠ **`fn_gl_entries` is untouched — and that is a decision with a consequence, not a saving.** §2.3 and the GL now compute over the same ledger by two independent readers. They agree on the rules only because the same rules were written into both; **nothing enforces that they stay agreed.** The both-correct-not-equal finding (E1-M consequence 1) is the first instance of them differing on purpose. **Recommend the §7.24 item 3 totals-equality watcher be scoped to know about this reader** when it is built, rather than discovering the §2.3-vs-GL delta as a failure.

**D-5 — §2.3.4 vs BACKLOG §7.14 — ✅ RULED (sitting item 10): §7.14 SHIPS FIRST, as a hard precondition on SELF-255.**

**The marking-gate pattern, applied a second time.** D-3's `is_tax_payment` marking enumeration is already a hard precondition on SELF-255 shipping (item 2a, ruling (i)). **§7.14 is now a second one on the same issue.** Stated together so neither is discovered as a surprise: **SELF-255 has two gates, both upstream, both hard.**

**Encoded as a gate AC on SELF-255's amended set:** *"§2.3.4 does not ship until BACKLOG §7.14's `053` positivity fence has landed. SELF-255 adds a fourth consumer of the CPI store; adding it over an un-fenced base table widens a known open hazard rather than inheriting a closed one."*

**THE FENCE SPEC NOTE — the one thing that must not be paraphrased into `> 0`.**

`053` today carries `cpi_u_index_value_finite` — a **finiteness-only** CHECK rejecting `NaN` and `±Infinity`. §7.14's binding conditions are **referenced live from §7.14's own text, not restated here** (Sec's four; read them there). The single point this note exists to pin:

> **The COMBINED predicate on `pfin.cpi_u_index.cpi_value` must be FINITE **and** STRICTLY POSITIVE.** The new constraint is **ADDITIVE** — `cpi_u_index_value_finite` **survives by name** and is never replaced. ⚠ **A bare `> 0` written as a standalone replacement re-admits NaN AND Infinity**, because both compare TRUE under Postgres numeric ordering. The finiteness half is what bars them; the positivity half is what bars `0` and negatives. **Neither alone is the answer, and the failure mode of getting this wrong is a poisoned deflator, not an error.**

**Idiom alignment** — the same explicit-literal form used in this pass's SELF-246 NaN clause and in `053`/`014`: compare against `'NaN'::numeric` / `'Infinity'::numeric` explicitly rather than trusting an ordering intuition. Two places in this document now depend on the same non-obvious fact; they should read the same way.

**⚠ VEHICLE — settled at the AC-landing step, both shapes recorded (per item 10):**

- **Shape 1 — §7.14 becomes its own promoted Linear issue.** Own PR, own Sec joint-review, own battery; SELF-255 declares a blocked-by. **Cost:** a promotion and a milestone slot for a Platform-class hardening item inside a feature milestone.
- **Shape 2 — an AC-family inside SELF-255.** No promotion; the fence rides 255's PR. **Cost:** it buries a Sec-conditioned hardening item inside a feature issue's ACs, and if 255 slips or is descoped the fence slips with it.

**I do have a lean: Shape 1** — one line, and it is the whole argument: **a precondition that lives inside the thing it gates is not a precondition.** Shape 2's cost is not extra work, it is that the gate stops being one.

**D-9 — Lock 15's dual-column predicate is defective in ratified text.** *(QUEUED for F/CTO at sitting item 9a — an ADR-011 Decision 19 amendment, drafted in the amendment batch. NOT taken here.)*

**The defect, and the measurement, carried verbatim so the amendment can attach it without re-running anything.** ADR-011 Decision 19 states the filter as `transaction_date <= $1 AND created_at <= $1`. `pfin.account_trans.created_at` is `timestamptz` (`004:127`) and `$1` is a `date`, so Postgres promotes the date to **midnight in the session zone** and the predicate **excludes every row created ON the as-of date itself**.

Measured on the live local stack — container `supabase_db_mosko-fintech`, database `postgres`, read-only `SELECT` as `postgres`, session `TimeZone=UTC`, 2026-08-22:

```
select current_date::timestamptz;        -> 2026-08-22 00:00:00+00
select now() <= current_date;            -> false      -- a row created TODAY fails the ADR's predicate
select now() <  current_date + 1;        -> true
```

**Consequence with `D = today`: every transaction the user entered today disappears from every §2.3 surface** — silently, behind a total that looks correct. **The corrected predicate is the half-open `created_at < (D + 1)`**, which is what the D-1 shared reader's rule 6 writes.

⚠ **Why this is an amendment and not a build fix.** The reader deviating from a ratified ADR text without that text changing leaves the ADR asserting a filter the code does not use — and the next author to implement an as-of surface will read the ADR, not this reader. **Fixing the code and leaving the ADR is how the defect gets re-introduced somewhere else.** The amendment should also carry the reason the error is invisible: **no value assertion catches it** — the totals are internally consistent, merely computed over a row set missing one day. **The only thing that catches it is a battery leg asserting that a row created ON the as-of date is INCLUDED**, which is why that leg is in the SELF-257 list.

⚠ **Scope check before the amendment is drafted:** Decision 19's predicate is quoted in **SELF-247's own description** and may be quoted elsewhere. The amendment must sweep for the literal string rather than fixing only the ADR — a byte-exact quote of a corrected source is still wrong if the quote was taken before the correction.

**D-9 — ADR-011 Decision 19 amendment — ✅ AUTHORIZED (sitting item 14): ONE combined amendment, its own PR, Architect commits.**

Two edits in one amendment because they touch the same Decision and would otherwise be two PRs against one paragraph. **Separate from the D-6 bound work** — a bound is not a filter, and that PR is app-source while this one is ADR text.

**EDIT 1 — the predicate correction (Architect).**

Decision 19's **Locked option** paragraph states the filter as `transaction_date <= $1 AND created_at <= $1`. `pfin.account_trans.created_at` is `timestamptz` (`004:127`) and `$1` is a `date`, so Postgres promotes the date to **midnight in the session zone** and the predicate **excludes every row created ON the as-of date itself**.

**Evidence block — attach verbatim; it is runnable and re-checkable.** Container `supabase_db_mosko-fintech`, database `postgres`, read-only `SELECT` as `postgres`, session `TimeZone=UTC`, 2026-08-22:

```
select current_date::timestamptz;   -> 2026-08-22 00:00:00+00
select now() <= current_date;       -> false     -- a row created TODAY fails the ADR's predicate
select now() <  current_date + 1;   -> true
```

**Corrected text:** the half-open upper bound — `transaction_date <= $1 AND created_at < ($1 + 1)`. With `D = today` the defective form silently drops **every transaction the user entered today**, behind a total that looks correct.

⚠ **The amendment must also record WHY the error is invisible**, or the next reader will assume tests would have caught it: **no value assertion catches this.** The totals are internally consistent — merely computed over a row set missing one day. Only a battery leg asserting *a row created ON the as-of date is INCLUDED* catches it, which is why that leg is in the SELF-257 list and in the D-1 reader's battery.

**THE LITERAL-STRING SWEEP — measured, not guessed.** `grep -rn 'created_at <= \$1'` across the tracked tree (excluding `node_modules`, `.git`, `temp/`) returns **exactly one hit**:

| Target | Where | Action |
|---|---|---|
| `DECISIONS.md:4738` | the Decision 19 **Locked option** paragraph itself | corrected by Edit 1 |
| **SELF-247's Linear description** | quotes the filter verbatim from Decision 19 | ⚠ **not in the repo — route to the liaison.** A byte-exact quote of a corrected source is still wrong if it was taken before the correction |

No occurrence exists in `docs/`, `supabase/migrations/`, `api/src/` or the workflow artifacts — the predicate has never been implemented, which is why this is a correction before first use rather than a defect in shipped code.

**EDIT 2 — the D-7 scope qualifier (Sec's finding, reading (A); commit-ready text below).**

Sec's verdict: reading **(A)**, confidence HIGH, **no (B) fence-exceeded finding** — the clause is kept, not retracted, and gains an explicit §2.6 scope qualifier plus a named joint-review trigger on the wiring event.

⚠ **THE TEXT BELOW IS COMMITTED BYTE-FOR-BYTE. NO PARAPHRASE, NO RE-FLOW, NO RE-WRAPPING.** It was extracted programmatically from `temp/sec-v13-d7-d8.md` rather than retyped, precisely to remove the transcription surface. It appends to ADR-011 Decision 19 **after the Cross-references paragraph**.

**[Amendment 2026-08-22 — scope clarification, NO behavior change (Sec-reviewed at the V1.3 pre-flight sitting).** The clause "§2.3.3 drill-down is the ONLY surface where client toggle is legitimate" is a statement about the **PRD's V1 as-of-toggle inventory**, stated as the rationale for the §2.6 server-derived-only fence it shares a parenthetical with. It scopes **which PRD story authorises a user-facing historical as-of control**, and it remains true as written: §2.3.3 is still the only V1 story carrying one (PRD `story-2-3-3`, "V1 also includes an **as-of-date toggle** on this view"); `story-2-2-2` and `story-2-2-3` carry none. It does **not** speak to client-supplied dates that are not as-of toggles — a chart window (`chart_start` / `chart_end`), or a manual account's opening-balance date (`p_as_of_date`), both of which are live and neither of which is an instance. **SELF-238 / SELF-240 did not exceed it:** AC8 / AC6 delivered a validated `as_of` **capability** (`api/src/lib/server/schemas/allocation.ts`; `userSuppliedAsOf`) that no route wires — both allocation loaders pass `serverTodayAsOf()`, and `userSuppliedAsOf` has no caller outside that schema module and its tests (measured 2026-08-22 at `0491830`). **Standing condition:** the PR that first wires an `as_of` query parameter onto a §2.2 surface is **Sec-joint-review-mandatory** and must at that PR either implement this Decision's app-layer DATE range battery (upper bound: no future dates; the `2015-12-01` floor to be re-derived or retired — it has no referent anywhere in the current tree) or record why it does not.**]**

**Ordering within the amendment:** Edit 1 first (it corrects the *Locked option* paragraph), Edit 2 appended after *Cross-references*. They do not overlap and neither depends on the other.

**A COUPLED CORRECTION THAT DOES NOT BELONG IN THIS PR — routed to Backend.** Sec's premise correction: `api/src/lib/server/time/asOf.ts`'s header calls SELF-238/240 the *"FIRST live path"*, and **"live" is false** — the factory and schema exist; no route wires them. Sec's requested wording: **correct to "the first path to VALIDATE one — not wired to any route as of `0491830`"**. ⚠ **CORRECTED — an earlier draft of this line rendered that sha as `0491833` and flagged it as Sec's to verify. It was MINE.** Measured on the source: `temp/sec-v13-d7-d8.md` contains `0491830` three times and `0491833` zero times. I introduced the corruption by **retyping** the line by hand — in the same pass where I extracted Sec's ADR text programmatically precisely to avoid retyping. The discrepancy I reported did not exist; the sitting log's item 15a repeats it and needs the same correction. ⚠ **It is a one-line source edit, not an ADR edit** — fold it into whichever PR touches that file first, **likely SELF-247's first PR** per item 12a. It must not ride the ADR amendment: mixing a source correction into a decision-text PR is how a reviewer loses track of which claim was ratified.

⚠ **AND IT IS THE CORRECTION THAT MATTERS MOST, because I got it wrong from that same header.** I asserted the §2.2 client as-of was live — reading `resolveAllocationAsOf` at `allocation/+page.server.ts:50` as a call site when it sits **inside the comment explaining why it is not wired**. The stale header is exactly what a future reader will find, which is why Sec routed it as a correction rather than a note.

**Sec's residual FLAG, carried not closed:** the `2015-12-01` floor **has no referent anywhere in the tree** (`grep -rn "2015-12-01" api/src supabase/migrations` → no match), and Sec explicitly does **not** require it — *"Architect's call whether to re-derive or retire it. Stated as uncertainty, not as a requirement."* ⚠ **This sits in tension with D-6 (C), which was ruled with the floor.** The tension is small and worth naming rather than resolving silently: **D-6 mandates a constant Sec declines to require and whose derivation no artifact records.** Two dispositions — (a) keep it and record its derivation in the constant's comment (what "NAV anchor floor" refers to, measured, not asserted), or (b) retire it and bound only the ceiling. **My lean is (a)**: a floor with a recorded derivation is cheap, and an unbounded past as-of on a money surface is the kind of input nobody wants to defend later. **Recorded as an open item, not taken.**

**Sec's separate FLAG, deliberately NOT attributed to Decision 19** (their words, and the discipline is right): `routes/accounts/new`'s `as_of_date` is a **live** client-supplied date on a **write** path with no future-date guard app-side or DB-side. ⚠ **Same field name as Decision 19's `as_of_date`, different parameter** — an opening-balance event date, not a point-in-time read parameter. Attributing it to Decision 19 would be a false composite. **Routed to PM/Architect as its own scope call**, not folded here.

**D-2 — §2.3.3's middle section — ✅ RULED (B) (sitting item 11): `Transfer ∪ Equity`, labelled "Other Cash Flows".**

**HOW THE CLASS SET IS EXPOSED — my spec's call: NOT as a reader parameter. Section membership is SHAPING, and it stays out of `fn_cashflow_items`.**

⚠ **The argument is decisive rather than stylistic, and it is worth stating because a `p_cats text[]` parameter is the obvious first design.** The D-1 reader's row set is deliberately *the union of what §2.3 sums and what the S-2 banner counts* — classifiable-but-**unclassified** items are emitted **with NULL `cat`**. A `where cat = any(p_cats)` filter inside the reader **drops every NULL-`cat` row**, because `NULL = any(...)` is never true. **The banner's `N` would go to zero on every surface, silently, and "one source" would become one source for the total and no source for the count.** A class-set parameter does not merely duplicate a filter — it destroys the property the extraction was for.

So: the reader emits `cat` / `sub_cat` and filters nothing by class. **Each surface partitions the emitted rows**: `cat is not null and cat = any(<section set>)` for its sections, `cat is null` for `N`.

**WHERE THE SECTION VOCABULARY LIVES — one shared constant module, on the `usEquitySubCats.ts` precedent.** That file already establishes the exact shape this needs: a Backend-owned server module holding a vocabulary **DDL-copied verbatim from `041`**, existing so *"the list can never drift between"* its two consumers, and carrying its own instruction to *"read live if this ever needs re-verifying, never trust a copy of a copy."* The §2.3 section map gets the same treatment — **one module, three consumers (SELF-250, SELF-253, SELF-254), no surface restating a class set.**

⚠ **PROVISIONAL NAME — `cashflowSections.ts`.** Coined here as a working handle; **not ratified**, and it must not reach a commit subject or an issue title until the AC-landing step fixes it. (Standing lesson; same treatment as `fn_cashflow_items` and S-2b.)

Its content is the section map itself:

| Surface | Section | Class set | Label |
|---|---|---|---|
| §2.3.2 (SELF-250/251) | 1 | `{'Revenue'}` | Income |
| §2.3.2 | 2 | `{'Expense'}` | Expenses |
| §2.3.3 (SELF-253/254) | 1 | `{'Revenue'}` | Income |
| §2.3.3 | 2 | **`{'Transfer','Equity'}`** | **Other Cash Flows** |
| §2.3.3 | 3 | `{'Expense'}` | Expenses |

`Trade` appears in **no** section on either surface — it is excluded from §2.3 entirely, and by M2 a `Trade`-classified row cannot be a cash row anyway.

**SELF-253 / SELF-254 AC DELTAS.**

- **SELF-253** AC1: *"returns JSONB with `sections` (exactly 3 — Income + OtherCF + Expenses, in that order)"* → **exactly 3 sections in the order Income → Other Cash Flows → Expenses, their class sets taken from the shared section map, never restated in the function.** AC6's *"OtherCF INCLUDED here"* → *"the `Transfer ∪ Equity` section is included here and is absent from §2.3.2 — the asymmetry the PRD calls intentional, now expressed in classes that exist."*
- **SELF-254** AC1: *"3 sections in PRD verbatim order: Income → OtherCF → Expenses (NOTE OtherCF in middle position)"* → same order, middle section **labelled "Other Cash Flows"**, label sourced from the shared module rather than typed into the component. The *"NOTE … middle position"* parenthetical stands — it was right about position and only wrong about the name.

**A-10 — THE MAPPING TABLE (co-owned with PM; PM owns the PRD prose, I own the class-set column).** Cited from measurements already taken in this pass — `028` for the ratified enum, `041` for the seeded row counts — **not re-measured**:

| PRD name (pre-GL) | Post-GL class set | Basis |
|---|---|---|
| **Income** | `{'Revenue'}` | `028` ratified enum (`Revenue`, *was* `Income`); `041` seeds **7** Revenue Sub-Cats |
| **Expenses** | `{'Expense'}` | `028` (`Expense`, *was* `Expenses`, singular); `041` seeds **12** Expense Sub-Cats |
| **OtherCF** | **`{'Transfer','Equity'}`** | `028` dissolved `OtherCF` → Transfer / Trade / event-axis; D-2 (B) rules the §2.3.3 membership as Transfer ∪ Equity |

**And one row that is NOT a mapping, which the table must say so nobody supplies one:** **`AcctSetup` maps to no class at all.** It was never a flow class — the non-cash lifecycle discriminator is `pfin.account_trans.transaction_type ∈ ('standard','acct_setup','basis_adjust','corp_action')` (`030:153`), and those rows are excluded from §2.3 by **M1**, upstream of any section map.

**⚠ THE FINDING D-2 (B) CARRIES, AND IT IS A DATA GAP RATHER THAN A DESIGN ONE: HALF THE RULED CLASS SET IS UNSEEDED.** Measured earlier in this pass against `041`'s seed: the 27 cash-flow default rows are **Expense 12 · Revenue 7 · Trade 4 · Transfer 4 · Equity 0**. So today:

- **"Other Cash Flows" renders Transfer rows only.** The section is correct and non-empty, so this is not a blocker.
- **But no user can classify anything as `Equity`**, because the picker sources `pfin.posting_prototype` and there is no Equity prototype to choose. The class is expressible in the CHECK and unreachable in the UI.
- `028`'s own ratified map intended otherwise — it records `Equity (Contribution/Distribution)` with *"Distribution demoted from a top-level class to Equity::Distribution"* — and **PRD §2.3.1's own OtherCF example is "IRA-Contribution"**, which is Equity-shaped, not Transfer-shaped. **So the seed, not the ruling, is what is behind.**

**Two dispositions, and this one is genuinely PM's or F/CTO's rather than mine:** **(a)** add `Equity / Contribution` + `Equity / Distribution` to the default set as a seed delta — ⚠ which is an ADR-057 reach decision, exactly like D-3's, and should ride the same migration if both land in this milestone; or **(b)** ship `Equity` as a structurally-available, empty class in V1 and say so in the PRD, so the absence reads as scope rather than as an omission. **Recorded, not taken.** ⚠ Whichever is chosen, the §2.3.3 section is correct either way — this decides whether the user can *reach* half of it.

**D3 — Where does `is_tax_payment` live? (SELF-245, SELF-255) — ✅ RULED by F/CTO 2026-08-22 (sitting item 2).**

⚠ **RESTORED 2026-08-22 after an editing error deleted this block.** The D-2 encoding replaced the span between the old `D2` and `D4` headings, and **D3 sat inside that span**. Reconstructed in full from the authored text; no content is knowingly lost, and the restoration is recorded rather than made silently so a reader who noticed the gap learns what happened.

**The ruling, carried verbatim from `temp/v13-preflight/sitting-log.md`:** *"Option A re-confirmed — to be recorded repo-durably this time (the original ratify existed only in a Linear description). Placement: both `posting_prototype` + `posting_prototype_default`, `085`-shaped (named CHECK, no helpful DEFAULT, fail-closed), with the ADR-057 provisioning-reach decision stated in the migration header."*

**Encoded shape** (what the migration must realize):

- Column on **both** `pfin.posting_prototype` and `pfin.posting_prototype_default` — the `085` pair discipline: the per-user table and its provisioning source get the same column, or provisioning copies a row that cannot satisfy the target's constraint.
- **`set not null`, no DEFAULT.** ⚠ These are two different guarantees and neither substitutes for the other — `085`'s own header is explicit: *a CHECK is fail-OPEN on NULL … the CHECK does NOT make the column total; `set not null` does.* **The absence of a DEFAULT is what delivers "fail-closed"**: every INSERT must state the value, so a user-authored prototype (V2 taxonomy-CRUD; `084` already grants `authenticated` INSERT) errors rather than landing silently discretionary.
- **Backfill is total by construction** before `set not null` — an unconditional `else` branch, `085`-shaped, with the map stated in the header and its judgement half labelled as a judgement.
- **ADR-057 provisioning-reach decision stated in the migration header**, not discovered later: a change to the default set must decide **separately** whether it reaches **already-provisioned** users; first-access provisioning does not deliver it retroactively.
- **Decision 3: family +0, stated per column.** Neither column is FK-shaped — no FK, no reference to any relation, no array of ids; on `posting_prototype_default` there is no `users_id` at all. There is no referenced row, therefore no tenant to match; no matched-tenant validation is owed and none is authored. (Per `085`'s rule that the check is run and stated **per column**, because `084`'s Amendment 1 records the check not actually having been run on the second table of a pair.)
- **No new RLS policy, no new grant, no new function.** `posting_prototype` already carries the `025` aal2 conjunct on its policies (`084`); `posting_prototype_default` is `025`-excluded under exclusion (i) as global shared-read. Adding a column changes neither, so no aal2 clause obligation is triggered and none is authored. SECURITY DEFINER allowlist untouched — read ADR-011 Decision 9 live.

**§10 3-axis cross-check** (re-run live against ADR-011 Decision 4 at this sha, per the apply-migration Step 0 every-time rule): no catalogued instance added, reordered or renumbered; no layer-attribution moved; the catalogued list is linked, not restated. **No ledger change** — not a §10 Sec trigger. It routes to Sec on other grounds (below).

**THE `085` CHECK CLAUSE IS SUPERSEDED — ✅ sub-ruled A1 (sitting item 2a, default-and-notify).** Naming the superseded claim explicitly, per the visible-supersession rule: item 2 read *"`085`-shaped (**named CHECK**, no helpful DEFAULT, fail-closed)"*. **Item 2a removes the named CHECK.** The reason it was raised and the reason it was removed are the same fact: `085`'s `element` is **`text`**, and its CHECK is what bounds a text column to two values — load-bearing there. **On a `boolean` a named CHECK is a control that cannot fire**, because once `not null` holds the domain is already exactly `{true,false}`, and the project has a standing line against constraints over by-construction properties.

**RULED SHAPE — A1:** `is_tax_payment boolean not null`, **no DEFAULT, no CHECK**, on both tables. *"`085`-shaped"* therefore means the **discipline** — NOT NULL + no DEFAULT + total backfill before the NOT NULL + mirrored pair + `comment on column` on each — not a literal instruction to emit a constraint.

**Considered and rejected, recorded so they are not re-derived** (both were live at the flag-back):

- **(A2) a two-valued `text` vocabulary** (`check (… in ('tax_payment','discretionary'))`). Literally `085`-shaped, all three of item 2's clauses would apply, and extensible — a later withholding-vs-estimated-payment split would be a CHECK edit rather than a type change. **Rejected** because it renames the concept away from `is_tax_payment` across every downstream AC and the original Linear ratify, and widens a column for a fact that is binary today. ⚠ If a third tax-payment class ever becomes a requirement, **A2 is the migration path** — a `boolean → text` widening, not an in-place CHECK edit. Recorded so that author knows the option was weighed, not missed.
- **(A3) `boolean` + a named CHECK anyway**, satisfying item 2's letter. **Rejected** — it ships a leg that cannot fail, and a dead constraint reads to a later reviewer as a live guarantee.

**THE FILTER-LEVEL SEAM — ✅ sub-ruled (i) (sitting item 2a, default-and-notify).** The column being fail-closed at INSERT does **not** make SELF-255's filter fail-closed. That filter is `is_tax_payment = FALSE`; with the backfill landing every row `false` pending F/CTO's marking enumeration (AC5), **every genuinely-tax-payment Sub-Cat would silently enter the discretionary-expenses chart** — no error, no marker, a wrong figure that looks right.

**RULED — (i): the marking enumeration is a HARD PRECONDITION on SELF-255 shipping.** Encoded as a gate AC on SELF-245 AC5 rather than as a follow-up booking — a follow-up is precisely what would let SELF-255 ship first. ⚠ **SELF-255 now carries TWO hard upstream gates** — this one and §7.14's positivity fence (**D-5**, item 10).

**Rejected — (ii) a third "undecided" state**, letting the chart render UNAVAILABLE-with-a-reason per the §2.4.4 non-silence discipline. It is the more defensive design and it was a real option (it also argued for A2). **Rejected** because it puts an *undecided* value into a vocabulary every consumer must branch on forever, to express a condition that is temporary by construction — the honest statement is that the **data** is not ready, not that the **type** is wrong. ⚠ The trade this accepts, stated so it is not discovered later: **the gate is a sequencing commitment, not a mechanism.** Nothing in the schema prevents SELF-255 being built against an unmarked column; the AC is the only thing enforcing it, so it must survive into the issue text rather than living only here.

**DRAFTING-READY SPEC — the whole shape in one place, so the amendment batch does not reassemble it from four paragraphs.**

| | |
|---|---|
| Column | `is_tax_payment boolean not null` — **no DEFAULT, no CHECK** |
| Tables | `pfin.posting_prototype` **and** `pfin.posting_prototype_default`, mirrored |
| Order | add nullable → total backfill → `set not null` (the `085` sequence; the NOT NULL is safe *because* the backfill is total, not hopefully) |
| Backfill | unconditional `else`, `085`-shaped; the judgement half labelled as a judgement in the header |
| Comments | `comment on column` on **each** of the two columns |
| Decision 3 | **family +0**, stated **per column** (neither is FK-shaped; `posting_prototype_default` has no `users_id` at all) |
| RLS / grants / functions | **none added or changed.** `posting_prototype` already carries the `025` aal2 conjunct (`084`); `posting_prototype_default` is `025`-excluded under exclusion (i). DEFINER allowlist untouched — read ADR-011 Decision 9 live |
| §10 | no ledger change; catalogued list linked, never restated (Path B) |
| ADR-057 | the provisioning-reach decision — does this default-set change reach **already-provisioned** users? — is **answered in the migration header**, not deferred |
| Gate | F/CTO's marking enumeration is a hard precondition on **SELF-255** shipping; the AC must land in the issue text, not only here |
| Durable record | a **new ADR** (placement · fail-closed shape · A1 · ADR-057 reach precedent · the SELF-255 gate) **+** the migration header carrying authoring-time provenance |

**THE EQUITY SEED — ✅ RULED (a) (sitting item 16): `Equity / Contribution` + `Equity / Distribution`, riding this migration.**

Per `028`'s ratified map — *"Equity (Contribution/Distribution … Distribution demoted from a top-level class to Equity::Distribution)"* — and closing the D-2 gap where the ruled `Transfer ∪ Equity` section had **zero** seeded Equity Sub-Cats (measured: `041`'s 27 cash-flow rows are Expense 12 · Revenue 7 · Trade 4 · Transfer 4 · **Equity 0**).

**WHICH TABLES THE SEED WRITES — measured, because post-`084` the answer is not the one `041` gives.**

- **`pfin.posting_prototype_default`** — the two new rows land here. `084` moved the cash-flow half of `taxonomy_default` into this table; `041`'s own seed statement targets `taxonomy_default` and is **the wrong target now**.
- **`pfin.posting_prototype`** — needs an explicit **backfill for already-provisioned users**, and this is not optional. Provisioning is **app-side**, in `api/src/lib/server/queries/taxonomy.ts`'s `provisionCashflowPrototypes`, and it is **existence-guarded**: `if (existing) return; // already provisioned — nothing to do.` **A user with even one `posting_prototype` row never receives a later default-set addition.** So a seed-only migration reaches **new signups only**. `077`'s precedent is the shape to copy — it shipped its default-set delta *with* the already-provisioned-user backfill.
- This is exactly what **ADR-057** requires be decided rather than assumed, and it is the **same single reach ruling** that covers D-3's column: **one statement in the migration header answering both** — *this change reaches already-provisioned users, by explicit backfill, because first-access provisioning cannot deliver it.*

**⚠ A PAIRED APP-SIDE EDIT THIS MIGRATION FORCES — and the repo has already been bitten by it once.**

`taxonomy.ts` builds its INSERT from an explicit column list. The **cashflow** branch uses
`DEFAULT_PROVISION_COLUMNS = 'cat, sub_cat, tax_relevant, tax_character, display_order, notes'`. **`is_tax_payment` is not in it**, and D-3's column is **NOT NULL with no DEFAULT** — so after the migration the provisioning INSERT proposes a NULL and **violates the constraint**. The branch is **fail-soft** (`console.error(... 'upsert failed (fail-soft)'); return`), so the visible outcome is **a fresh signup silently receiving ZERO cash-flow prototypes**, with nothing but a server log line.

⚠ **This is a repeat of a caught hazard, not a new one.** That file's own comment records the same thing happening when `085` added `element` on the asset side — the shared constant *"would either omit the new NOT NULL column (blocks provisioning for every fresh signup — Decision 3's F4 finding)"* — which is why the two branches now hold **separate** column sets. **The cashflow set must be widened by this migration's paired PR.** Recorded here because a migration author reading only `supabase/migrations/` will not find it.

**THE TWO SEED ROWS.**

| `cat` | `sub_cat` | `tax_relevant` | `tax_character` | `is_tax_payment` |
|---|---|---|---|---|
| `Equity` | `Contribution` | **`true`** ✅ | `null` ✅ | **`false`** ✅ |
| `Equity` | `Distribution` | `false` ✅ | `null` ✅ | **`false`** ✅ |

`display_order` continues `041`'s sequence; `notes` per `041`'s descriptive convention.

**✅ CONFIRMED at sitting item 19:** `tax_character = NULL` on **both** rows; `Equity / Distribution` `tax_relevant = false`.

✅ **RULED at sitting item 20: `Equity / Contribution`.`tax_relevant = true`, WITH the notes rider.** The tension it resolves: a retirement contribution can be tax-relevant (deductible) or not (Roth / non-deductible), and the seed carries **one** value for a Sub-Cat covering both. `true` is the safe direction — it makes the row **surface for review** in the V1.4 §2.5.1 tax computation rather than disappear from it, and a false negative there is silent while a false positive is merely examined.

**The rider is what makes `true` honest, and it is part of the ruling, not a note on it.** The seed row's `notes` states:

> *"potentially deductible; resolve per account type at the V1.4 tax inventory"*

so the flag reads **flag-for-review**, never **always-deductible**. ⚠ Without it, a V1.4 consumer meeting `tax_relevant = true` on this row has no way to know the value was a deliberate over-inclusion rather than a determination.

⚠ **SURFACE NOTE — measured, and it is a dormancy rather than a problem.** `notes` **is copied to every provisioned user's row** (it is in the cashflow branch's `DEFAULT_PROVISION_COLUMNS`), and `041`'s other notes are **user-facing descriptive copy** (*"Dividend from a Stock or ETF"*). This rider is **internal-process language in a field whose siblings are descriptions.** Measured today: **no component or settings route renders `notes`** — grep over `api/src/lib/components/` and `api/src/routes/settings/` returns nothing — so the mismatch is **DORMANT, not live**. **Revival condition, named so it is not rediscovered as a bug:** the first surface to render prototype `notes` — **SELF-249's cascading Cat × Sub-Cat picker is the plausible first candidate**, a description or tooltip being the natural addition — makes this string user-visible. At that PR, either re-phrase it for a user audience or move the review-flag to a channel that is not user-facing.

**The D-3 seed spec is complete.** No value in it remains open.

**⚠ `is_tax_payment` ON THE EQUITY ROWS — DECISION TAKEN, with rationale (item 16 authorised taking it).** **They enter pre-marked `false`, and F/CTO's AC5 marking enumeration does NOT need to cover them.** Two independent reasons, and the second is the one that makes it safe rather than merely convenient:

1. **The value is TRUE, not inert.** Under `028`'s ratified class definitions, `Equity` is owner Contribution/Distribution — capital movements, not tax payments. `false` is a correct statement about these rows, not a placeholder.
2. **And it is unreachable by the only consumer.** SELF-255's filter is `cat = 'Expense' AND is_tax_payment = false`; an `Equity` row is excluded by the first conjunct before the flag is read.

⚠ **The obligation this creates:** the column's `comment on column` must **scope the flag's meaning to Expense-class prototypes**, so a future unscoped reader does not treat `false` on a non-Expense row as evidence the question was asked and answered for that class. Without that sentence, pre-marking is the kind of convenience that reads as a claim later.

**BATTERY LEGS FOR THE SEED** (QA; ride D-3's battery rather than a separate one):

- both rows present in `posting_prototype_default` after apply, with `is_tax_payment = false`;
- **a user provisioned BEFORE the migration has both rows after it** — the backfill leg, and the one that fails if the migration seeds the default set only;
- **a fresh signup receives the full cash-flow set INCLUDING `is_tax_payment`** — the leg that catches the `taxonomy.ts` column-list omission above. ⚠ It must assert **row count**, not just absence of error: the branch is fail-soft, so a broken provisioning path returns **cleanly with zero rows**;
- `Equity` rows are **absent** from SELF-255's expense series (the `cat = 'Expense'` conjunct), proving the pre-marking is unreachable rather than merely unused;
- the D-2 §2.3.3 "Other Cash Flows" section renders **Transfer ∪ Equity** and is non-empty on both halves.

⚠ **Provenance to carry into the ADR verbatim, not upgraded.** Item 2 was an **F/CTO ruling**; items 2a (A1 and (i)) were ruled **under the default-and-notify protocol with the F/CTO reversal window open until the amendment batch lands**. Those are two different strengths of authority and the ADR must record them as such. A ratify against a description that overstates its own authority is the failure this note exists to prevent — and if the window closes without reversal, that closure is itself the event the ADR dates, not the drafting.

**Durable-record vehicle — my call, as delegated: a NEW ADR, plus the migration header.** Reasoning, stated because the alternatives are defensible:

- The ruling carries **three separable decisions**, and the third is a **reusable precedent rather than a fact about this column**: ADR-057's reach rule currently has **no worked example**, and this is the first default-set change that has to answer it. A precedent needs an anchor a future reader can find by subject.
- A **migration header alone** is insufficient for that role, and the repo says so about itself: `084` and `085` both instruct readers that a header records **authoring-time provenance**, is a **dated artifact**, and must not be read as live state. It is the right home for the measurement trail; it is the wrong home for the standing rule.
- A **catalog comment** cannot carry it either — apply-migration Step 1.5(a)/(b): no counts, no enumerations, and no present-tense claim the reader cannot check from `\d+`.
- **An amendment to ADR-058 was the closest alternative** and I rejected it: ADR-058's subject is the split, it already carries an Amendment 1 whose corrections a citer can transmit unnoticed, and burying a provisioning-reach precedent inside it makes the precedent unfindable by anyone not already reading about the split.
- Scope of the ADR: the placement, the fail-closed no-DEFAULT shape, A1, the ADR-057 reach answer, and the SELF-255 sequencing precondition. It supersedes nothing; it **records repo-durably what previously existed only in a Linear description**, which is the ruling's own stated motivation.

Sec joint-review: **MANDATORY** — new column on the posting vocabulary, read by a money-path filter, plus a provisioning-reach decision. Not a §10 trigger, not a Decision-3 trigger; it routes on the money-path and vocabulary grounds.

**D-4 — `cashflow_target`'s wide-row shape — ✅ CONFIRMED AS RATIFIED by F/CTO 2026-08-22 (sitting item 17). Not reopened.**

The Wave-4 ratify (*"Option B with internal C"*) gives **one row per user, two named columns, `UNIQUE(users_id)`**. Nothing in the GL rework touches it, and **SD-22 has been classified against exactly that shape** — so a reshape would have invalidated a Sec classification as a side effect. **Confirmed: the shape stands as ratified.**

⚠ **What this confirmation does NOT bless — stated because "the shape is fine" is one step from "SELF-246 is fine".** SELF-246's **DDL is still wrong** and its corrections are unchanged by this item: `users_id` **uuid** with `default auth.uid()` (the issue says `INTEGER`, which does not apply against `auth.users.id`), `bigint generated always as identity` rather than `SERIAL`, `numeric(20,4)` grain, the **two-sided NaN-explicit CHECK**, the four RLS policies each AND-ed with the verbatim `025` aal2 conjunct, the **DELETE policy that may never be omitted** (SD-22 standing constraint), the grant posture, and the struck Decision-3 mis-citation. **Those are amendments to the DDL, not a reshape of the design** — the full list is with SELF-246 in §3.

⚠ **And the one-way-door framing this item carried was real, not decorative:** reopening the shape **after data lands** would need a data migration. Confirming it now is what closes that door safely, and it is why this was worth an explicit ruling rather than silent assent.

**D5 — Does §2.3.4 ship before or after BACKLOG §7.14?** — ⚠ **SUPERSEDED by the ruled `D-5` above (sitting item 10): §7.14 ships FIRST.** Heading retained so a reader who remembers this open question sees it answered rather than removed; the live text is at `D-5`.

§7.14 is the `053` positivity CHECK with four binding Sec conditions. SELF-255 adds a fourth consumer of the CPI store. Ship §7.14 first (Sec's own guidance on that item is *no-later-than, earlier is better*), or accept a fourth consumer over an un-fenced base table and say so out loud.

---

**D-6 — Lock 15 mod #2's range bound — ✅ RULED (C) (sitting item 12): bound the EXISTING shared schema, rename it surface-neutral, plus a QA watcher on the §2.2 route.**

**THE SPEC.**

⚠ **PROVISIONAL NAMES** — `asOfSchema` (the renamed export) and `schemas/asOf.ts` (its new home). Coined here; **not ratified**, and neither may reach a commit subject or an issue title until the AC-landing step fixes them. Standing lesson.

**Rename and move.** `allocationAsOfSchema` in `api/src/lib/server/schemas/allocation.ts` becomes surface-neutral and moves to its own module: it now serves §2.2 **and** §2.3, and a schema named for one consumer sitting in that consumer's file is how a second consumer ends up with a second copy. `resolveAllocationAsOf` moves with it. Existing §2.2 call sites re-point; no behaviour changes for them **except** the new bounds.

**The floor — ✅ RULED KEPT (sitting item 15a, default-and-notify), WITH ITS DERIVATION RECORDED.** `AS_OF_FLOOR = '2015-12-01'`, exported from the same module. Sec measured that the value has **no referent anywhere in the tree** and explicitly declined to require it — *"Architect's call whether to re-derive or retire it"* — and item 15a resolves that within the D-6 (C) ruling as made: **keep it, and put the derivation in the constant's comment** rather than restating Lock 15's phrase and calling it a citation.

**THE DERIVATION, measured so the comment states a fact rather than a phrase.** *"NAV anchor floor"* is not free-standing — it is defined in the same ADR:

- `DECISIONS.md:4666` — *"CPI-U historical import via `pfin_back_etl` … back to **Dec-2015 NAV anchor** per PRD §2.1.3"*. **The anchor IS Dec-2015**, named there.
- `DECISIONS.md:860` — PRD Appendix B flag (c): *"V1 imports the existing Google Sheet's monthly NAV history (**Dec-2015 forward**) so the 5-Year horizon in §2.1.3 is meaningful at launch"* — and the same paragraph records that **three of §2.1.3's five delta horizons are unsatisfiable at launch without those imported rows.** That is the floor's *purpose*, not just its value.
- `api/src/lib/nav-boundary.ts:13` — *"the imported Dec-2015-forward history landed at calendar month-end by construction."*

So the comment should say: **the earliest imported NAV history point; below it no NAV series exists, so an as-of there would render §2.1/§2.2 over an empty series.**

⚠ **AND IT MUST NAME WHERE ITS SUFFICIENCY COMES FROM, because the constant is now SHARED.** The derivation above is **NAV-shaped**. §2.3 reads `pfin.account_trans`, not `nav_daily`, and **transactions can legitimately predate Dec-2015** (the incumbent import is not bounded by the NAV anchor). So applying this floor to a **cash-flow** as-of is a **deliberate choice — one uniform bound across surfaces — not a derivation.** The comment must say that in a sentence, or a later reader will assume the floor was derived for §2.3 too and either extend it somewhere it does not hold or delete it as unjustified. ⚠ Measured earlier in this pass: **no `2015-12-01` constant exists anywhere in `api/src/` today** — this declaration is net-new, not a re-point. The shape follows `nav-boundary.ts`'s stated principle for the adjacent cron boundary: *"an ARCHITECTURE-EXPOSED VALUE ONLY … never inferred client-side"* — a date that gates a money surface gets one declared home.

**⚠ THE CEILING CANNOT BE HARD-CODED, AND THE OBVIOUS IMPLEMENTATION IS THE WRONG ONE.** The ruling says the ceiling is server-derived per the S-3 clock ruling — and **S-3 put the clock in the DATABASE** (`pfin.fn_server_today()`). **Zod validates synchronously in the Node process and cannot consult the database.** So:

> **The ceiling is INJECTED, not embedded.** `asOfSchema(maxAsOf)` is a factory taking the already-resolved `D`; the caller passes the value it resolved once per request from `pfin.fn_server_today()` (ADR-044 Decision 2's resolve-once-and-thread rule, which the request already obeys). **The clock is named at the constant**: the ceiling's provenance is the database clock, recorded in the module comment beside the parameter.

⚠ **The natural wrong implementation is `.max(new Date())`** — that is the **Node** clock, and it silently re-opens the two-clock hazard ADR-044 exists to close, with a boundary-day disagreement of up to 26 hours between the validator and the query it guards. `asOf.ts`'s own header names this hazard for exactly this reason. **A reviewer should treat any `new Date()` inside the validator as a defect, not a shortcut.**

**Predicate, stated once so three ACs cite rather than restate it:** `AS_OF_FLOOR <= as_of <= D`, both bounds inclusive, evaluated on the already-shape-validated ISO string; out-of-range → a field-level 400 in the SELF-233 structured-error shape.

**THE QA WATCHER — owner QA; my call on placement, with one part I am NOT deciding.**

- **Schema-level legs → the schema module's own test file** (`allocation.test.ts` today; it moves with the schema). That file already holds this schema's other legs — absent, valid, invalid-calendar-date, non-ISO, coerced, NaN/Infinity, over-length, `.strict()` — so the two new bounds legs belong beside them, not in a new file. **Legs: below-floor rejected · above-`D` (future) rejected · exactly-floor accepted · exactly-`D` accepted.** The two boundary-inclusive legs matter as much as the rejections: an off-by-one here silently refuses today's own as-of.
- **Route-level leg — the one that actually watches the shipped §2.2 surface** — asserts that `/allocation` rejects an out-of-range `as_of` rather than trusting that the schema is wired in. ⚠ **This is exactly the coverage class BACKLOG §7.25 item 3 books as an open QA scope call** (*"Route-loader (`+page.server.ts`) test-coverage precedent"*). **I am not resolving that precedent inside a D-6 encoding.** Two honest options for QA: piggyback this one leg and let it set the precedent by accident, or ship the schema legs now and let the route leg land with §7.25 item 3. **Flagging rather than choosing, because a precedent set as a side effect is the thing that item exists to prevent.**

**SELF-247's AMENDED AC — the V1.2-remediation half, stated explicitly rather than folded into a V1.3 task.**

> **AC (new, V1-SHIP-BLOCK):** the `[2015-12-01, D]` bound lands on the **shared** as-of schema — the one `api/src/lib/server/schemas/allocation.ts` already exports and which the §2.3 threading will consume. Lock 15 mod #2's range is a ratified **V1-SHIP-BLOCK** and is **unimplemented in the only client-supplied-as-of validator that exists** (`allocationAsOfSchema` carries no bound; `userSuppliedAsOf` re-checks shape only). The AC is discharged when the bound is enforced on the shared schema, so **both** the §2.2 capability and the §2.3 path inherit it — they are one schema.

> ⚠⚠ **CORRECTED 2026-08-22 — MY PREMISE WAS FALSE, and the correction is left visible rather than rewritten away.** I asserted, here and in three other places, that a client-supplied `as_of` is **live** on the merged §2.2 route. **It is not.** Sec measured it and I re-measured independently at `0491830`: `grep -rn "serverTodayAsOf\|userSuppliedAsOf" api/src/routes` returns **four loaders, all passing `serverTodayAsOf()`**, and `api/src/routes/allocation/+page.server.ts:49` states it in the file — ***"NO `as_of` QUERY-PARAM SUPPORT YET."*** **My error was reading a grep hit inside a comment as a call site** — `resolveAllocationAsOf` appears at `allocation/+page.server.ts:50` **inside the comment explaining why it is NOT wired**. The capability (schema + factory) is built; **no route reaches it**.
> **What this changes:** the D-6 fence is **PRE-EMPTIVE, not remediation of a live gap.** Sec's wording is the accurate one — *"harmless while unreachable; it is a fence gap the moment the query param is wired."* Option (C) still stands as ruled; what was wrong was my **urgency framing**, not the design. The "V1.2 remediation" characterisation below is withdrawn.
> **What it does NOT change:** the bound still belongs on the shared schema before the param is wired, and Decision 19's standing condition (Sec's amendment text) makes the wiring PR the Sec-joint-review trigger.


⚠ **SEQUENCING RECOMMENDATION WITHDRAWN (sitting item 15a).** This paragraph previously read that the AC made part of SELF-247 *"a V1.2 fix riding a V1.3 issue"* and recommended it **ship in 247's first PR** so an unmet V1-SHIP-BLOCK would not inherit V1.3's schedule. **Its premise — a live, unmet SHIP-BLOCK on a merged surface — is gone** (the capability is unreached; see the correction above). Team-lead's item-12a ruling built on that premise is withdrawn with it, and **247's internal sequencing returns to build-time discretion.** Left visible rather than deleted: a recommendation that was acted on and then invalidated should be findable by whoever acted on it.

**Interaction with D-9:** both touch the same as-of path — D-6 bounds the parameter, D-9 corrects the predicate it feeds. They are independent fixes (a bound is not a filter) and should land as separate, separately-reviewable changes; bundling them would make one PR carry both a ratified-text amendment and a shipped-surface remediation.

**D6 — Lock 15 mod #2's range bound is a V1-SHIP-BLOCK that is currently UNMET on a merged surface. (SELF-247)** — ⚠ **SUPERSEDED by the ruled `D-6` above (sitting item 12): option (C).** Heading retained so a reader who remembers this open question sees it answered rather than removed; the live text is at `D-6`.

Decision 19 fixes the range as a **V1-SHIP-BLOCK**: *"app-layer DATE input validation battery (Zod `.date()` + tightened range `2015-12-01 ≤ as_of_date ≤ CURRENT_DATE` per NAV anchor floor + no future dates)"*. Measured on the tree: **no `2015-12-01` constant exists in `api/src/`**, `allocationAsOfSchema` carries no bound, and `userSuppliedAsOf()` checks shape only. The **capability** — `allocationAsOfSchema` + `userSuppliedAsOf` — carries no floor and **no future-date ceiling**. ⚠ **It is not wired to any route** (see the correction under the SELF-247 AC above): the fence is pre-emptive, and Sec's framing is the accurate one — *"harmless while unreachable; it is a fence gap the moment the query param is wired."*

Options: **(A)** add the bound to the existing `allocationAsOfSchema` and rename it to a surface-neutral `asOfSchema`, so §2.2 and §2.3 share one validator and one constant — closes the merged-surface gap and satisfies SELF-247 in one edit. **(B)** author a separate §2.3 validator per SELF-247's AC1 as written and leave §2.2 unbounded — cheapest, and it leaves a ratified V1-SHIP-BLOCK unmet on a shipped surface while a second copy of the same rule drifts beside it. **(C)** (A), plus a QA leg on the §2.2 route so the bound has a watcher on the surface that has been running without it.
**My lean: (C).** ⚠ Whichever is chosen, the constant is a **clock** claim — `CURRENT_DATE` is Postgres's, `serverTodayAsOf()` is Node's, and `asOf.ts`'s own header names the two-clocks hazard. The ceiling must say which clock bounds it.

**D7 — Lock 15's "ONLY surface" clause and the tree disagree. (SELF-247, SELF-253)** *(doc-vs-tree conflict — §7.19 class (b); F/CTO disposes, Sec informed)*

**SELF-CONTAINED CONTEXT (inlined for a cold reader — this section can be read alone).**

**The ratified text, quoted with the surrounding clause reading (A) depends on.** ADR-011 Decision 19 (Lock 15 / Flag #13) lists among Sec's nine mods:

> *"server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand monthly_report; **§2.3.3 drill-down is the ONLY surface where client toggle is legitimate**)"*

The emphasised clause is unqualified **inside a parenthetical whose subject is §2.6**. That placement is the whole of the disagreement below.

**The tree.** `api/src/lib/server/time/asOf.ts` ships a branded `ZoneResolvedAsOf` type whose minting sites are deliberately enumerable, one of which is `userSuppliedAsOf()`. Its own header states:

> *"SELF-238 / SELF-240 (the §2.2.2 / §2.2.3 allocation backends) are the **FIRST live path**: their ratified AC8/AC6 require Zod-typed validation of a client-supplied `as_of`."*

`api/src/lib/server/schemas/allocation.ts` ships `allocationAsOfSchema` + `resolveAllocationAsOf`. ⚠⚠ **CORRECTED — an earlier draft of this section said the §2.2 route "consumes both" and that a client `as_of` is LIVE. It is not.** Independently re-measured at `0491830`: all four route loaders pass `serverTodayAsOf()`, and `allocation/+page.server.ts:49` states ***"NO `as_of` QUERY-PARAM SUPPORT YET"*** — `resolveAllocationAsOf` appears at `:50` **inside the comment explaining why it is not wired**. **The capability is built; no route reaches it.** Sec's own finding is the same, and it is load-bearing: *"live" is the word a (B) finding would have rested on.*

⚠ **The capability is also UNBOUNDED**: no `2015-12-01` constant exists in `api/src/`, and `allocationAsOfSchema` carries **no floor and no future-date ceiling**. Unreachable today, and a fence gap the moment a query param is wired — ruled separately at **D-6** (option C). D-7 asks a different question: not whether the toggle is bounded, but whether it was permitted at all.

ADR-011 Decision 19 states, unqualified: *"§2.3.3 drill-down is the ONLY surface where client toggle is legitimate."* But `asOf.ts`'s `userSuppliedAsOf` header records §2.2.2/§2.2.3 as the **first live client-supplied-`as_of` path**, shipped under SELF-238/240's ratified AC8/AC6 — and it is merged.

Readings: **(A)** the clause is scoped by its own parenthetical (which is about `data_as_of` on §2.6 monthly-report paths) and §2.2's `as_of` was never in its scope — in which case the ADR text is imprecise and gets a clarifying amendment, no behaviour changes. **(B)** the clause meant what it says and SELF-238/240 exceeded it — in which case §2.2's toggle needs a ratify-after-the-fact or a removal. **(C)** the clause was true when written and the V1.2 allocation work superseded it without amending it — the ordinary supersession case, which gets an in-place retraction rather than a correction.
**My lean: (A)**, on the plain reading that the sentence sits inside a §2.6 fence clause — **but I am not the right party to rule it**, because (B) would mean a merged surface exceeded a ratified fence, and that is Sec's and F/CTO's call, not mine. ⚠ Supersession and drift look identical on a partial read and call for opposite treatments; this is exactly that fork.

## 6. Sec joint-review gate map (visible at dispatch, not discovered at PR)

| Issue | Mandatory? | Trigger |
|---|---|---|
| SELF-245 (re-scoped) | **Yes** | new column on the posting vocabulary; ADR-057 provisioning reach |
| SELF-246 | **Yes** | Lock-14 family table; RLS + aal2 + DELETE-policy standing constraint (SD-22) |
| SELF-247 | **Yes** | as-of parameter fence; RT-25 |
| SELF-248 | **Yes** | new function + write path over a D3-fenced column |
| SELF-249 | No | UI over a fenced endpoint |
| SELF-250 | **Yes** | financial calculation + multi-tenant read composition |
| SELF-251 | No | render only |
| SELF-252 | **Yes** | Lock-14 settings write path |
| SELF-253 | **Yes** | financial calculation + client-supplied date on a multi-tenant read (RT-25) |
| SELF-254 | No | render only |
| SELF-255 | **Yes** | financial calculation (deflator) + new column |
| SELF-256 | No | render only |
| SELF-257 | **Yes** | it *is* the RLS surface; Sec verdict is an AC |
| SELF-258 | No | consumes an existing INVOKER primitive |

Any function proposed below as SECURITY DEFINER routes to Sec joint-review by itself — **none is proposed**. Lock 11 SECURITY INVOKER read-composition is the default for every helper named in this memo.

---

## 7. Answers to the five specific questions

**(a) Does SELF-248/249's transaction Sub-Cat assignment model survive instrument-routed cash and split postings? — NO, on three counts, and one of them is a false claim about a lock.**
The model assumes a mutable `user_subcat_id` column on `pfin.account_trans`. That column does not exist, and `004`'s `fn_account_trans_block_mutation` blocks **UPDATE and DELETE for every role including service_role, with no column discrimination** — so the issue's parenthetical justification ("Lock 10 freezes financial-shape columns; classification is metadata-mutation") is false about ADR-011 Decision 14, not merely stale. The ratified home is the `023` annotation overlay (1:1, full CRUD) and the `029` split children (writes un-dormed at `038`), both of whose `sub_cat_id` FKs re-target to `posting_prototype` at `084`. Instrument-routed cash does **not** touch this path — it is an allocation-of-*balances* concern (`fn_subcat_market_value`), and §2.3 classifies *transactions*. Split postings **do**: nothing in either issue mentions splits, so as drafted a split parent can be classified at the parent level and then double-counted by every downstream aggregate. The `035`/`037` `split_count` XOR reader rule must be carried into both issues.

**(b) Does SELF-250's rollup depend on SELF-333 landing first? — REFUTED. No dependency, in either direction.**
SELF-333 re-bodies `pfin.fn_subcat_market_value`'s cash leg so non-liability cash routes to the seeded `Cash` / "Cash Balances" bucket **by name**, mirroring `081`'s liability route. Its substrate is `pfin.user_taxonomy` (the **storage** spine) reached through the `022` `user_asset_category` junction, and it answers "what allocation bucket does this cash *balance* belong to". SELF-250 aggregates *transactions* classified through `account_trans_annotation`/`account_trans_split` into `pfin.posting_prototype` (the **posting** vocabulary) and answers "what did the user spend, by Sub-Cat, by period". **Since `084` these are two different tables with disjoint id ranges** — a §2.3 rollup cannot reach the row SELF-333 fixes, and SELF-333 cannot reach a posting prototype. Dependency direction: **none**. The real blocking upstream for SELF-250 is SELF-246 (`cashflow_target`, unbuilt) and the D1 substrate ruling.

**(c) Does `074`'s `planning_target` pattern transplant to `cashflow_target`? — Partly. Two of the three halves transplant; the D3 half does not apply at all.**
- **Lock-14 half — transplants cleanly.** Per-domain table (not `user_settings`; `025` names `user_settings` a NON-NEGOTIABLE exclusion from the aal2 backstop because of policy recursion, so it is the wrong home for step-up-fenced tenant data). RLS on all four verbs `users_id = auth.uid()`, each **AND-ed with the `025` aal2 clause**; `users_id uuid not null default auth.uid() references auth.users(id) on delete cascade`; `bigint generated always as identity` PK; `fn_refresh_updated_at` BEFORE UPDATE trigger; UPSERT-in-place, no versioning (ADR-011 Decision 18).
- **D3 fence half — does NOT transplant, and must not be invented.** `074`'s fence is on `sub_cat_id` (the family member); `cashflow_target` has no FK-shaped column other than the `users_id` tenant anchor, which `074`'s own contract records as *not* a family member. SELF-246 AC5's "per Decision 3 family" is a mis-citation to correct. **Family count +0.**
- **App-layer half — owed, and `074` is the cautionary precedent.** Sec's own note on RT-23: *"RT-23 IS NOT SATISFIED BY `074`"* — the DB half shipped, the Zod `.strict()` + numeric adversarial battery did not. SELF-252 AC3/AC4 are that half; they must not be read as inherited.
- **Two carries `074` paid for.** (i) The numeric CHECK is **two-sided because of NaN** — `numeric(5,2)`'s typmod refuses ±Infinity before the CHECK, but NaN is storable and satisfies `>= 0`; re-derive for `numeric(20,4)` rather than copy the bounds. (ii) The **DELETE policy standing constraint** (SD-22, measured by QA with a corrupt-the-control pair): no Lock-14 DELETE policy may be omitted on the reasoning that SELECT covers it.
- **Is it the right shape?** Yes — ✅ **confirmed as ratified at sitting item 17** (D-4). The wide row is untouched by the GL rework; what needs fixing is SELF-246's DDL, not the design.

**(d) Does SELF-253's Lock 15 client-toggle claim match Lock 15's text? — YES, verbatim.**
ADR-011 Decision 19 reads: *"§2.3.3 drill-down is the ONLY surface where client toggle is legitimate"*, in the same clause that fences §2.6 to server-derived-only. SELF-253 quotes it accurately and applies it to the right surface. Three riders the issue does not carry: (i) SELF-247 owns the validation helper SELF-253 AC4 consumes — now promoted into V1.3, so the dependency is intra-milestone, but still an ordering constraint; (ii) **the "ONLY surface" clause is falsified by the tree** — §2.2.2/§2.2.3 already ship a client-supplied `as_of` (see decision item D7), so SELF-253 is not the first such surface and SELF-247's own framing to that effect is wrong; (iii) Decision 19's dual-column filter is available on `account_trans` (`created_at` exists at `004:127`) but **is not implemented in `fn_gl_entries`**, which filters `transaction_date` only — so the D1 substrate choice and the Lock 15 requirement are coupled.

**(e) Does the CPI substrate provide what SELF-255's AC assumes? — It provides more than the AC asks for, and less than the AC's formula needs.**
Shipped and ratified: `pfin.fn_cpi_u_index_for_period(p_period date)` (`066`, superseding `064`'s six-column shape) returns exactly one row always, eight columns, STABLE + INVOKER, with carry/non-publication/due/coverage provenance and a **ratified return shape** whose column set cannot change without Sec re-review + F/CTO ratify + an ADR-049 amendment + a grant-re-issuing migration. `pfin.cpi_u_nonpublication` (`063`) records observed non-publications. `fn_nav_series_inflation_adjusted` (`067`) is the composition precedent.
What the AC assumes and cannot have: **there is no "cpi_today" scalar**, and the shipped §2.1.2 basis the AC claims to match is **`coverage_through`**, not today. So AC4's formula both re-derives the gap policy locally — which ADR-049 Decision 4 exists to forbid — and states a normalization basis that contradicts its own cited precedent. `067` is also NAV-series-shaped: a spending series needs its own composition over `066`, inheriting `067`'s guards (strictly-positive both legs, **NULL never zero**, provenance columns carried, `gap_class` never user-visible) rather than re-deriving them. And BACKLOG §7.14 is a live precondition: `053`'s CHECK is finiteness-only, and Sec's binding condition (1) is the trap — **`> 0` alone re-admits NaN *and* Infinity**.

---

## 8. What this pass did not cover

- **PRD §2.3 prose itself.** §2.3.1/§2.3.2/§2.3.3 still name Income / Expenses / OtherCF / AcctSetup as data-model Cats. That is the §7.19 PRD sweep (PM lead), and it is the generator behind G2. Amending the ACs without amending the PRD leaves the next drafter reading the same false premise.
- **ARCH §-level sweep** (§7.19 AC 2, Architect). Not attempted here; this pass is AC-vs-DDL only.
- **Frontend component-inventory feasibility** for SELF-249/251/254/256 — UX/Visual territory.
- **Performance ACs** (`500ms/400ms/600ms/800ms p95`) were not evaluated; they were authored against a substrate that no longer exists and should be re-derived once D1 settles.
