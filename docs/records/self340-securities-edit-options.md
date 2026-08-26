*Sitting record for SELF-340 — the joint Architect + PM options brief F/CTO ruled on 2026-08-26 (the A+C-deferred package). [ADR-064](../../DECISIONS.md#adr-064) distills it; this file is the working analysis it distills, preserved verbatim as ruled-on.*

# SELF-340 — What does editing a trade mean? Joint options brief

**Status:** COMPLETE — awaiting F/CTO ruling. Joint: Architect (mechanism, §1–§6 + each option's *Mechanism*) + PM pm-340 (§6b Product ground + each option's *Product framing* + the PM lean block). Both leans converge on **A+C-deferred**; where they differ in strength, §5/lean-7 says so rather than smoothing it.
**Blocks:** PR #567 (held on Sec veto, F/CTO ruling 2026-08-26).
**Measured against:** `main` + PR #567 head `a016e7986a63613d2959050cdbf82860e89903c3`.
**Routing at ruling:** Sec joint-review MANDATORY (ADR-011 D2 immutable audit-class + financial calculations). QA battery extends with whichever option ships. ADR required for the ratified shape.
**Option labels (reconciled between Architect and PM):** **A** refuse · **B** carry (B1 unconditional / B2 field-conditional) · **C** a real securities-edit surface · **A+C-deferred** the combination.

---

# PART I — ARCHITECTURE (Architect)

## 1. The question is not "may a trade be edited". It is "which of four coupled numbers may move".

A securities fact on `pfin.account_trans` is **four numbers read by two different consumers**:

| column | who reads it | what it drives |
|---|---|---|
| `quantity` (+ `security_id`) | `fn_holdings_as_of` (`019`) | shares held → NAV, allocation, §2.2 surfaces |
| `cost_basis` | `fn_gl_entries` P2 / P5 / P6 / P7 / P10 / P11 (`084`) | book value → trial balance, §2.3 GL surfaces |
| `amount` | `fn_gl_entries` P1 | the cash leg |
| `price` | **nothing in V1** — `049`/`050` value from `pfin.eod_price`, never from `account_trans.price` |

`manualTransEditSchema` reaches exactly **one** of them (`amount`), plus date/vendor/description/sub_cat. So "edit a trade", as plumbed today, means *change the cash leg and nothing else*.

**Sec's veto names the `quantity` half. There is a second half, and it is worse, because it is silent.**

## 2. `reverseAndReplaceTrans` is not a reversal at the book layer

The step-(1) `select` list omits `cost_basis` and `price`; neither insert object carries those keys. So a reversal row carries `cost_basis = NULL` **by construction**. Evaluated against `084`'s live branch predicates for a BUY (`amount = −C`, `quantity = +Q`, `cost_basis = +C`):

| row | P1 cash | P2 position | contra |
|---|---|---|---|
| original | −C | **+C** (`quantity > 0`, not excluded) | P10 Suspense = −(−C + C) = **0** |
| reversal *(as written)* | +C | **SKIPPED** — P2 requires `cost_basis is not null` | **P8 Suspense = −(+C)** (`standard` ∧ `security_id` ∧ `quantity <= 0` ∧ no `lot_match`) |
| corrected *(cash-shaped)* | +A | — | P3 by cat |

The trial balance still sums to zero — **P8 absorbs it, so no watcher fires** — but `trade_position` keeps `+C` of book value for that security **forever**, while `fn_holdings_as_of` reports zero shares. **Holdings and the GL diverge, silently, permanently, in opposite directions.** The double-entry Σ=0 property that PRD §2.4.3 calls *"reconciled-by-construction"* cannot see it; only the V1.6 statement-vs-GL tie-out would.

Same divergence via a different route for an `acct_setup` opening position (`087`: `amount=0`, `quantity=+Q`, `cost_basis=+C`): the reversal emits **zero GL rows at all** — P1 skips on `amount=0`, P2 skips on null `cost_basis`, and the P5 opening-equity contra evaluates to `−(0 + 0) = 0` and is dropped by the final `amount_book <> 0` filter — while `−Q` shares leave holdings.

## 3. The affected class is `security_id IS NOT NULL`, across three of four fact-kinds

| `transaction_type` | writer | post-#567 behaviour |
|---|---|---|
| `standard` + security | `fn_create_manual_purchase` (`088`), provider ingest | **SUCCEEDS — destroys the position** (Sec's veto) |
| `acct_setup` + security | `fn_create_manual_account` opening positions (`087`) | **SUCCEEDS — destroys the opening position** |
| `corp_action` | `fn_create_stock_split` (`039`) | **SUCCEEDS — undoes the share restatement AND turns a book-neutral row into a cash row.** `manualTransEditSchema` *requires* a non-zero `amount`, so a split row cannot even be edited back into its own shape; ADR-033 Decision 2's binding book-neutrality AC is defeated from this path. |
| `basis_adjust` | *(no V1 writer)* | **FAILS CLOSED** — `034`'s `account_trans_basis_adjust_shape` CHECK requires `security_id IS NOT NULL AND cost_basis IS NOT NULL` on both new rows. |

`034` is the only DB fence in the family that watches this defect, and it watches one quarter of it.

## 4. A fence exists that observes the defect exactly — and the edit path swallows it

`084`'s `fn_account_trans_annotation_trade_constraints` s2a enforces `(security_id IS NOT NULL) ⟺ (cat = 'Trade')`. A Trade-categorized security row edited through this path produces a cash-shaped corrected row (`security_id NULL`) carrying the form's Trade `sub_cat_id` → **s2a raises**. But the annotation upsert is step (4), *after* the irreversible ledger INSERT, and its failure is `console.warn`-ed while the function returns `{ ok: true }`.

Post-fix, editing a Trade row: **destroys the position, refuses the classification, leaves the row Unsorted, and reports success.** The one watcher that sees this defect sits downstream of the point of no return. **This is a defect on the cash path too, independent of the ruling.**

## 5. Why this is a one-way door in the strongest available sense

Both new rows land on the `004` immutable ledger: no UPDATE, no DELETE, no TRUNCATE, for any role **including `service_role`** (triggers are not RLS). And V1 ships **no compensating write path**. The complete set of `account_trans` writers is:

`fn_create_manual_trans` (cash only — hard-codes `security_id NULL`) · `fn_create_manual_purchase` (BUY only, `quantity > 0`) · `fn_create_stock_split` (corp_action) · `fn_ingest_transactions` (provider bulk).

**There is no sell path. There is no `basis_adjust` writer. `pfin.lot_match` is write-dormant until M4-GL** (`032` ratified decision 1).

⚠ **And there is no skip, no delete, and no exclusion — for any row, cash or security.** PRD §2.4.3's *"Delete is implicit skip (Axis C1) … `skip_flag=true` … deleted/skipped view"* describes a primitive that **never shipped**. Measured: `skip_flag` appears in exactly one file in the tree, `004`, and **both occurrences are prose asserting its absence** (*"NO mutable reconciled_flag/skip_flag"*); zero occurrences in `api/src`. **ADR-032** (F/CTO-ratified 2026-07-25) eliminated the primitive: *"No `is_excluded` column; no data-layer cashflow-exclusion predicate."* So "delete and re-enter" is not a V1 remedy, was never built, and cannot be offered in refusal copy.

After a mis-edit there is nothing the user can do in-product and nothing an operator can do short of a schema-level intervention on an append-only table.

**Exposure to date — bound now complete; no cleanup is owed.** Three legs:
1. No reverse-and-replace pair can have landed since `d6b41cd5` (2026-07-27) — the path failed unconditionally.
2. Manual security rows could not exist before `087`/`088` (2026-08-21).
3. **Zero provider-ingested security rows exist** — `pfin.account_trans` holds no row with `security_id IS NOT NULL AND source_provider IS NOT NULL`, and all six security rows present are manual-origin with earliest `created_at` 2026-08-22, i.e. after the break. *(Read-only measurement by team-lead against the live local stack, 2026-08-26; predicate = `security_id` / `source_provider` on `account_trans`. Architect did not independently re-run it, and it is scoped to that stack — which is the only stack holding data, V1 being undeployed.)*

So the defective *combination* has never been reachable on any data. This is why the question is being **decided** now rather than **cleaned up** now, and it is the reason Option A costs nothing retroactively.

## 6. Two fields the options must treat as financially load-bearing

**`transaction_date` on a trade row — load-bearing by four independent mechanisms:**
- **Lot open date → tax character.** PRD §2.5.1 derives ST/LT from the lot's Open Date vs the sale's Close Date (>365 days → LT). A buy row's `transaction_date` **is** that Open Date.
- **Holdings anchor window.** `fn_holdings_as_of` = latest `holdings_checkpoint` ≤ as_of + Σ(`quantity`) **strictly after** the anchor date and ≤ as_of. A date edit can move the row across the anchor boundary → double-count or drop.
- **As-of inclusion.** Every historical NAV point is an as-of read; a date edit restates NAV history, not just today's figure.
- **Price-pick reordering.** `078` picks `price_date desc` then a source-rank where `manual_valuation` outranks every feed; `088`'s F4 hazard is that a companion price at the trade date restates *every prior lot* from that date forward.

Plus **split ex-date ordering** — reordering a trade across a `corp_action` restatement changes the share arithmetic.

**The `023` annotation overlay is mutable — but it is NARROWER on a security row, and it is not a remedy.** `084` fences it twice: **s2a** (`security_id IS NOT NULL ⟺ cat='Trade'`) means a security row's annotation **can only ever be a Trade cat** — it cannot be relabelled into a cash-flow category at all; **s2b** requires the Trade sub_cat's BTO/BTC/STC/STO direction to sign-align with `quantity`. So the overlay permits: a sign-consistent Trade sub_cat change, and a note edit. **It cannot fix an amount, a quantity, a cost basis, or the instrument.**

---

## 6b. Product ground (PM)

**1. The PRD makes no concrete trade-edit promise.** §2.4.3's opener says "adding and editing transactions on any account," but every concrete edit semantic in the story is cash-field carry-through (vendor / amount / date / Sub-Cat over `provider_txn_id`); the story's own title scopes to "cash and AcctSetup non-cash events"; and trades sit in the ADR-058/ADR-062 **mechanical posting vocabulary** — the §2.3 label-mapping footnote is explicit that Trade "takes no §2.3 narrative section," and the classify queue excludes it. The "reverse-and-replace" language is §2.3.1's cross-domain-corrections gloss (F/CTO rulings 2026-08-22), written in a *cash-domain* context. **Refusing security-row edits breaks no ratified product commitment.** The generic opener still needs scoping so §2.4.3 stops implying a promise it never spelled out — PM owes that amendment post-ratify (PM lean block, item 3) — and the same pass retires the stale Axis-C1 `skip_flag` / split-and-skip / deleted-skipped-view language PART I §5 falsifies. Both are instances of the standing PRD-predates-GL recalibration class.

**2. The remedy set is empty, and the overlay is not a remedy.** Per PART I §5 there is no delete, no skip, no exclusion, no sell, no basis-adjust — for any row; per PART I §6 the `023` Categorize overlay on a security row is fenced to Trade-cat-only, sign-consistent sub_cats plus the note — it adjusts classification *within* Trade and cannot fix an amount, quantity, cost basis, date, or instrument. Product copy must never imply otherwise.

**3. No parity obligation.** The incumbent is the Google-Sheets Finance_Report; its correction path was direct cell editing, and `docs/v1-parity-matrix.md` records **no trade-correction workflow feature** — there is nothing to have parity with. The immutable ledger deliberately trades free-form cell editing for auditability.

**4. No existing V2 candidate.** BACKLOG §5 stages no securities-edit surface. Nearest neighbor is "user-driven historical correction workflows" (V2+, NAV-import-scoped) — a distinct capability; C must not be folded into it.

**5. Archetype and population.** Manual trades are deliberate entries (§2.4.5 already names manual-entry integrity risk); mis-entry is an occasional-error case, not a workflow. But V1 is **general multi-user software with real public signup** — the dead end binds every tenant, not only the founding user. V1's product bar here: no silent destruction, honest copy, and a bounded window.

---


# The options

## Option A — REFUSE `security_id IS NOT NULL` at the write path

### Mechanism (Architect)

One predicate beside the existing reversal / double-edit / split-parent guards in `reverseAndReplaceTrans`, plus the UI mirror (`Edit` is currently rendered for every `!frozen` row — `TransactionRow.svelte`, no security-awareness). Exactly the shape sitting-log item 9a ratified for split parents. Refusing on `orig.security_id IS NOT NULL` covers `standard`+security, `acct_setup`+security and `corp_action` in one predicate; `basis_adjust` stays fenced by `034`.

**Ledger shape.** Unchanged. No migration, no DDL, no new FK-shaped column, no DEFINER.

**Fences that watch it.** The app guard is the only one, and a DB-layer twin is **not available**: both rows are individually legal — the defect is in *which pair the app composes*, not in a row shape. That is a real weakness of A, and it is the same one 9a already accepted (TOCTOU-narrow, single-user; booked).

**Failure mode under user error — the option's real cost, stated without softening.** A mis-entered purchase **cannot be fixed, at all**. Per §5: no delete, no skip, no sell path, no `basis_adjust` writer, dormant lot-matching. Per §6: the `023` overlay corrects classification and nothing about the money. **The only honest refusal copy is *"a recorded security transaction cannot be edited or removed in V1."*** Anything implying a workaround would be false.

⚠ A is not neutral on the status quo either: today's fail-closed is an **accident** (the NOT NULL violation PR #567 removes). **A ships the accident as a decision** — and, given §5, ratifies an unrecoverable dead end. That is what F/CTO would be accepting.

**What the battery must assert.** Refusal before any write, zero rows in `account_trans`, for each of the three fact-kinds **separately** (one fixture per kind — a single `standard` fixture leaves `acct_setup`/`corp_action` unproven); the unaffected cash path still succeeds; guard precedence against the reversal / double-edit / split guards; the UI mirror does not render `Edit` on a security row.

**Sec surface.** App-layer only; D2-adjacent; no new fence to review. Joint-review at the ruling.

### Product framing (PM)

**V1/V2/never: V1 — ship it now**, with this product shape:

- **No dead affordance.** Hide `Edit` on `security_id IS NOT NULL` rows (PART I: it currently renders on every `!frozen` row). A button that renders and then refuses reads as a bug; an absent button reads as a rule. `Categorize` stays visible so the row is not presented as fully inert — scoped per Product ground 2.
- **Honest copy, no false remedy.** The copy may claim only what is true: a recorded security transaction cannot be edited or corrected in V1; a correction surface is planned. No "re-categorize to fix it," no dates, no "contact support" theater.
- **What F/CTO is being asked to ratify** — stated at the strength PART I §5 puts it, which PM endorses **for A ruled alone**: *a mis-entered security transaction is permanent* — not "editing is unavailable for now." Under the **A+C-deferred package** the accurate ratify wording softens by exactly one clause: *uncorrectable for the window — with the mis-entered figures live in NAV/allocation/tax surfaces meanwhile — and correctable when C lands* (retroactive reach confirmed at PART I's Option C mechanism; what remains open is C's reversal **date semantics** — whether a correction repairs the window's history or only its future — ratified with C per PART I lean item 7). Either way it is ratified as a dead end, not inherited as an accident — PART I's Option A mechanism ("A ships the accident as a decision") is the right frame, and the decision should be visible in the ADR.
- **Why the dead end is acceptable to ship:** (a) **exposure is narrow and new** — manual security writers exist only since `087`/`088` (2026-08-21), no defective pair has ever landed, and provider-ingested trades are ground truth whose edits are the cash/classification kind that still works; (b) **the honest dead end beats the invisible corruption** — PART I §2's silent GL/holdings divergence has no watcher; a user who must re-ask is strictly better off than one whose books are quietly wrong; (c) **A is the only reversible option** (PART I lean item 4); (d) the window is **bounded by staging C** (A+C-deferred framing below).

## Option B — CARRY the position through

### Mechanism (Architect)

`corrected` inherits `security_id`, `quantity`, **`cost_basis`**, `price` from `orig`; only date/amount/vendor/description/sub_cat come from the form.

**B1 — unconditional carry. Incoherent; do not ship.** ⚠ Carrying `quantity` alone leaves `cost_basis` NULL on the corrected row → P2 skips → the position is restored in *holdings* and never re-added to the *book*: the same divergence as §2, in the opposite direction. So B must carry `cost_basis`. And once it does, the edited `amount` and the carried `cost_basis` are untied — for a `standard` BUY, **P10 plugs `−(amount + cost_basis)` to Suspense**, so every amount-edit on a trade silently books its own delta to Suspense. The user changes $1,000 → $1,050 and $50 lands in Suspense with no error and no refusal.

**The trap, stated mechanically:** `amount` is the cash leg, `cost_basis` is the book leg, and **V1 has no constraint tying them.** Any edit surface that moves one and not the other is *guaranteed* to mint a Suspense plug. Sec's "silently re-prices the lot" is this, at the GL layer.

**B2 — field-conditional carry. The only coherent form of B.** Carry all four security columns and refuse the fields that move them:
- **`amount` — must refuse** (the P10 plug above).
- **`transaction_date` — must also refuse**, per §6's four mechanisms. This was not anticipated in the dispatch's framing of B as "safe for non-amount edits".
- ⚠ The **reversal** must carry `cost_basis` **negated** too, or its own P2/P8 asymmetry re-creates the divergence the option exists to avoid.

That leaves the safe editable set on a trade as **`{vendor, description}`** — `sub_cat`/`note` already live on the mutable `023` overlay and need no ledger touch. **So B2 buys cosmetic-field edits on trades.** That is the honest size of the prize.

**Ledger shape.** Reversal and corrected both become full security-shaped mirrors. No migration is strictly forced — but the shape of every reversal row changes meaning, on a table where **no row can ever be corrected**.

**Fences that watch it.** `017`'s qty↔security CHECK passes either way. `084` s2a's biconditional now *passes* — which **removes the one downstream signal** that currently exists (§4). Nothing watches the Suspense plug.

**What the battery must assert.** That `fn_gl_entries` emits **no `suspense` row** for an edited trade. ⚠ Under B1 that leg **fails by construction** — B1 cannot pass its own test. Under B2 it passes, and the battery must additionally prove the refused-field set (`amount`, `transaction_date`) and the negated-`cost_basis` reversal.

**Sec surface.** Financial-calculation change → D2 + money-flow joint-review mandatory; re-opens `088`'s F4 valuation hazard.

### Product framing (PM)

**V1/V2/never: never, in either form.** B1 fails on PART I's mechanics (it cannot pass its own battery). B2's honest prize is `{vendor, description}` on a row class the user never even classifies — demand for relabeling a mechanical posting row is near zero, while the price is a money-path Sec review, a GL-divergence risk, and the loss of the `084` s2a downstream signal. **The dispatch anticipated date as a B2-safe field; PART I §6 measured it must-refuse on four independent mechanisms** (lot-open-date → ST/LT tax character, holdings anchor window, as-of NAV restatement, price-pick reordering; plus split ex-date ordering) — so B covers **none** of the three mis-entry classes this issue exists for (quantity, price, date). A partial promise that misses its own use case is worse product than a clean refusal: it teaches the user the edit surface is arbitrary. If vendor/description relabeling ever earns a surface, it is `023`-adjacent annotation work and must never be framed as "trade edit."

## Option C — a real securities-edit surface

### Mechanism (Architect)

**Smallest coherent version.** Extend `manualTransEditSchema` with `quantity` + `cost_basis`; `security_id` stays **non-editable** (changing the instrument is a different trade, not an edit). Move the whole reverse-and-replace into a DB function `pfin.fn_reverse_and_replace_trans(...)`, `SECURITY INVOKER`, `set search_path = ''`, so the `{reversal, corrected}` pair **and** the annotation carry commit as one transaction.

That last part is independently valuable and closes §4's swallowed fence: today the annotation upsert is a second statement whose failure is discarded, and `writeSplitSet` carries the same two-statement note in-file (`038` authored no RPC).

**Cost.** A new RPC on the money path (Sec joint-review); a Zod widening that is a Lock 14 mass-assignment surface (`.strict()` + the numeric battery both extend); a UI form presenting four coupled numbers without letting the user desynchronize them; QA legs per fact-kind.

⚠ **Sequencing problem C does not remove.** An edit surface for trades is **upstream of lot-matching**. Editing a sell with `lot_match` children orphans them exactly as editing a split parent orphaned split children (9a) — so C must ship its own refusal for matched sells. **C narrows A's guard; it does not retire it.**

**Ledger cross-check.** No new table or FK-shaped column → **Decision-3 family unchanged**. `SECURITY INVOKER` → **DEFINER allowlist unchanged**; Lock 11 read-composition is the default. **§10 catalogued ledger unchanged** — Decision 4 read verbatim before drafting; three axes clean (no instance added or reordered, no layer re-attributed, no surface becomes "four-layer"); a Lock 14 write-path is a *class* member and class membership is not a catalogued instance (ADR-042's own ruling, recorded at ADR-011 D3 #17 consequence (e)). ⚠ The §10 catalogued set and the CI-fenced set are different sets and are not reconciled here.

**Retroactive reach (answering PM's routed flag) — unconditional for window-entered rows, with one honest qualification.**

Nothing about a row's age or origin blocks a later reverse-and-replace: `004`'s matched-account fence requires only that the reversal share the target's `account_id`, and `replaces_trans_id` is a plain self-FK with no temporal predicate. The double-edit guard blocks only a *second* reversal of the same row — and a row refused during the window was never reversed, so it is fully eligible. Window-entered rows are in fact the **easy** case: with no sell path in V1 they can only be buys, opening positions or splits, none of which carry `lot_match` children, so C's matched-sell refusal never fires on them.

⚠ **Qualification: a correction is a re-post, not an erasure**, and whether the window's *history* is repaired turns on a date choice C must make — one today's code already makes silently. `reverseAndReplaceTrans` copies `orig.transaction_date` onto the reversal, i.e. it **back-dates**: every as-of read before the correction is rewritten. Keep that, and the window's NAV / allocation / tax history is restated as though the error never happened. Date the reversal at correction time instead, and the window's history keeps the wrong figures while only forward reads are right. **That is a ratify-level choice, not an implementation detail**, and it belongs as a fourth AC seed on C's staging entry.

**So PM's conditional resolves: the window-bounded ratify wording is the honest one** — *uncorrectable for the window, correctable when C lands* — provided C's date semantics are settled when C is specced.

### Product framing (PM)

**V1/V2/never: later V1.x, staged now — not this ruling, and not V2+ either.** Not V1-now: PART I's cost (new money-path RPC, Lock 14 Zod widening, a four-coupled-numbers form, per-fact-kind QA legs) against occasional-error frequency — and it would hold PR #567's walk-confirmed cash fix hostage. But the lean is **BACKLOG §7 staging as an M4-GL-adjacent GL-substrate milestone candidate, not §5 V2+**: (a) C's own dependencies — `lot_match` activation, the missing sale writer — land at M4-GL anyway (PART I's C sequencing + missing-sell-path note); (b) the refusal window should close inside V1's roadmap because the dead end binds every signup tenant. **The real decision F/CTO makes on C's placement is the acceptable length of the no-correction window** — V2+ placement is defensible only if that window is acceptable for all of V1.

**The missing sell path** (PART I's note under A): agreed it is a roadmap observation, not a candidate. Product addendum: even when `fn_create_manual_sale` exists, "record the offsetting sale" is an accountant's remedy, not a correction story — artificial trades on the ledger, realized-G/L side effects. C supersedes it as the user-facing answer; the sale path is wanted for its own sake (flagged in the PM lean block).

## A+C-deferred — refuse now, stage the surface

**Not a fourth architecture — the combination of A and C**, named separately because it is the likely ruling and F/CTO should weigh it as one thing: ship A's guard in PR #567's branch, stage C, and accept §5's dead end for the interval between them. Its mechanism is A's; its cost is A's cost bounded in time rather than accepted permanently; its risk is that the interval is not bounded by anything structural.

### Product framing (PM)

**This is the PM-recommended ruling, taken as one package** — and it should be ratified as one package, because its two halves justify each other: A's dead end is acceptable *because* C is staged with a named home; C's deferral is acceptable *because* A guarantees the interim is fail-closed rather than silently corrupting. Package contents:

1. **A ships now** (write-path refusal + UI mirror + honest copy per Option A framing); PR #567's cash-row fix merges with it.
2. **C is staged post-ratify** as a BACKLOG §7 entry — PM authors it: Source = the SELF-340 ruling + PART I's C mechanism sketch; AC seeds = `security_id` non-editable · reversal carries `cost_basis` negated · matched-sell refusal · annotation carry in one transaction · **reversal date semantics decided at ratify** (back-date restates the window's history as though the error never happened; correction-date keeps the window's wrong figures and repairs forward reads only — the ratify-level choice PART I's retroactive-reach analysis surfaces) (PART I lean item 6's two standing findings become ACs, not lore); Dependencies = M4-GL `lot_match` activation, manual-sale writer. If F/CTO rules V2+ instead, the same entry lands in §5 with the window-acceptance recorded — placement is the F/CTO call; entry content is identical either way.
3. **PRD §2.4.3 amendment** (PM-owed, after ratify, one pass): (i) scope the opener — in-place edit holds for cash rows; security-bearing rows are fenced: no in-place edit in V1, overlay available only within its `084` fence, correction surface per the ruled placement; (ii) replace the ADR-032-retired `skip_flag` / split-and-skip / deleted-skipped-view language with the current Lock-10/ADR-031/ADR-032 shape; (iii) add the fence to the story's V1/V2-boundary paragraph so it cannot re-litigate — **deferral-shaped wording, not a permanent non-goal** (a non-goal would contradict staging C).

---

## Architect's lean, with reasoning

**A now · C later · B never in its unconditional form.**

1. **The class is bigger than the veto found** — three fact-kinds, plus a silent GL/holdings divergence *in addition to* the position loss — and every member sits on an immutable ledger with an empty remedy set. When the blast radius is unrecoverable and no compensating writer exists, **fail closed is the defensible default.** That is the same reasoning that produced 9a for split parents days ago, on a **strictly smaller** hazard: orphaned split children are recoverable by re-splitting; a destroyed position is not.

2. **B2 buys almost nothing.** Remove `amount` (the P10 plug) and `transaction_date` (§6) and the safe set on a trade is `{vendor, description}` — cosmetic, adjacent to an overlay that is already mutable. Paying a money-path Sec review, a GL-divergence risk, and the loss of the `084` s2a signal for two cosmetic fields is a bad trade.

3. **C is the right eventual answer** and its mechanism is already half-specified: `088`'s row-shape rule ("a purchase is ONE row … BALANCED BY CONSTRUCTION") is exactly what an edit RPC must re-derive. It should not be squeezed into this PR.

4. ⚠ **ONE-WAY DOOR — the decision-relevant asymmetry.** Shipping B (either form) writes security-shaped reversal rows onto the immutable ledger; if the rule later changes, **those rows cannot be corrected** — reversing B is a data migration on a table that blocks UPDATE and DELETE for every role, i.e. not a migration but a rewrite. **A is the only option that is reversible**: a refusal writes nothing, so it can be lifted the day C lands, and every row that existed under it is still clean.

5. ⚠ **What A actually asks F/CTO to ratify.** Not "edit is unavailable for now" but **"a mis-entered security transaction is permanent."** §5 establishes there is no delete, no skip, no sell, no basis-adjust. That should be ratified explicitly, because refusal copy written on the assumption of a workaround would be false. ⚠ **Scope, per item 7:** "permanent" is the honest word for **A ruled alone**. Under **A+C-deferred** it softens to *uncorrectable for the window* — the wrong figures live in NAV / allocation / tax surfaces meanwhile — because C can reach window-entered rows. The two options ask F/CTO for different ratifications and should not be conflated.

6. **Two findings that stand regardless of which option wins:**
   - The **swallowed `084` s2a failure** (§4) — the annotation step reports success after a raise. A defect on the cash path too.
   - The **`cost_basis`-blind reversal** (§2) — if C ever lets a security row be reversed, the reversal must carry `cost_basis` negated, or it books to Suspense via P8.

7. **C's retroactive reach is not in doubt; its date semantics are.** Window-entered rows are fully correctable once C ships (Option C mechanism, above) — so PM's conditional resolves to the **window-bounded** ratify wording, not "permanent". What is unsettled is whether C's reversal **back-dates** — today's code does, silently — which decides whether a correction repairs the window's history or only its future. **Ratify that with C, not after it.**
8. **A finding for PM's half, surfaced by the gate:** PRD §2.4.3's delete/skip paragraph describes a primitive that never shipped and that ADR-032 retired. Whatever the ruling, that text is false today.

---

## PM lean + flags

**Lean: A+C-deferred as one package — A now (V1) · B1/B2 never · C staged now for the GL-substrate later-V1.x milestone · missing-sell-path noted for the roadmap.** This converges on Sec's original refuse-now recommendation; what this analysis adds is the product reasoning F/CTO asked for — no ratified promise is broken, the dead end is named and ratified at its true strength rather than inherited, and the refusal is the only reversible move on an immutable ledger.

Flags routed, not decided:
- **V1 has no way to record selling anything** (PART I §5) — a product-scope fact bigger than this issue. If the manual-sale path is not already inside the GL-substrate milestone's scope, it is a PRD-recalibration item for the standing pass. → team-lead / F/CTO visibility.
- **C's reversal date semantics** — back-date (window history restated as though the error never happened) vs correction-date (window history keeps the wrong figures; only forward reads repaired) — ratify-level, decided with C's spec, carried as an AC seed on the staging entry (PART I lean item 7). Retroactive reach itself is CONFIRMED (PART I Option C mechanism) and no longer open; the window-bounded ratify wording stands for A+C-deferred, "permanent" for A alone.
- The swallowed `084` s2a annotation failure reports success after a raise **on the cash path too** (PART I lean item 6) — user-facing "saved" that didn't fully save; product cares, fix is Backend/Sec territory.
- Server-side refusal is the control; the hidden button is UX. Sec already carries the UI mirror as defense-in-depth — endorsed, in that order.
