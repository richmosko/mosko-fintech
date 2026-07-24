# DECISIONS.md

Architectural Decision Records for mosko-fintech. Each entry captures a non-obvious choice: what was decided, what was considered, why.

## Format

mosko-fintech uses **two ADR patterns** per the policy locked at ADR-009 Decision 8. The pattern fits the decision shape; both patterns are first-class.

### Consolidation pattern

Used for: synthesis work, canonical-reference layers, multi-Decision territory establishment. Examples: ADR-002, ADR-008, ADR-009.

**Structure:**

- **Date** / **Status** / **Phase** preamble
- **Context** — multi-paragraph framing of what surfaces the ADR and what's at stake
- **Decisions** — numbered subjects (`### Decision 1 — <title>`, `### Decision 2 — <title>`, etc.), each with structured content (decision itself + rationale + alternatives considered + cross-references)
- **Consequences** — downstream phase implications, pending tasks, supersession notes, ADR housekeeping

### Terse pattern

Used for: one-off decisions, simple supersessions, isolated choices that don't warrant consolidation ceremony.

**Structure:**

```
### YYYY-MM-DD — <short decision title>
**Decision:** <one sentence>
**Why:** <one or two sentences>
**Alternatives considered:** <bullets>
**Approved by:** <name>
**Supersedes:** <ref to prior decision, if any>
```

### Common conventions (apply to both patterns)

- **One ADR per H2 heading**, numbered sequentially.
- **Newest at top** (this file is read by scrolling down through history).
- **Immutable once accepted.** Supersede via a new entry rather than rewriting an old one. Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNN`, `Deprecated`.
- **Cross-references** to other ADRs use `ADR-NNN` (e.g., "supersedes ADR-005"). Cross-references to PRD / WORKFLOW / SECURITY use anchor refs (e.g., `docs/PRD/index.html#sec-4-5`, `docs/SECURITY/index.html#rt-13`).

---

## ADR-031 — Event-sourced double-entry general ledger as a derived layer over the immutable `account_trans` ledger

**Date:** 2026-07-23
**Status:** Accepted (F/CTO-ratified 2026-07-23; amended 2026-07-23 by Amendment 1 below — settle-before-import conventions)
**Phase:** Phase 6+ (post-V1 substrate — GL/accounting layer over the `015`–`023` ingest substrate).
**Approved by:** *pending F/CTO ratify.* Design papers: `temp/double-entry-design-v2.md` (current model, supersedes `temp/double-entry-approach-c-migration.md`). Security conditional-GREEN (no veto) 2026-07-23 — conditions binding on M1-evt + M2 (Decision 7).
**Pattern:** Consolidation (multi-Decision territory: an accounting-model layer spanning event semantics, account model, classification, valuation, and the GL engine). Amends [ADR-025](#adr-025) (see Amendment 1) and extends [ADR-011](#adr-011) Decision 3.

### Context

The `015`–`023` ingest substrate (ADR-027) gave us an immutable transaction ledger (`pfin.account_trans`, `004`/`017`), a universal asset registry (`pfin.asset`, `016`), a per-user taxonomy (`pfin.user_taxonomy`, `009`), a mutable annotation overlay (`account_trans_annotation`, `023`), and a market-value net-worth engine (`fn_compute_nav`, `019`). The F/CTO asked how much double-entry bookkeeping is latent in that schema and what it would take to make it double-entry-native.

The finding: the schema is **single-entry storage with a latent two-*leg* event model** — a securities BUY already carries both `amount=−cash` and `quantity=+shares` on one row (`017`), and the `(account_id, security_id)` grain is already a subsidiary ledger that `fn_holdings_as_of` (`019`) rolls forward — but there is no account-class dimension, no normal-balance flag, no journal/contra structure, and no virtual-account concept. Three design rounds converged on a model that delivers a genuine double-entry general ledger **as a derived layer**, without rewriting the immutable ledger and without a stored `journal_entry`/`journal_line` structure. This ADR records that model (Decisions 1–5), the rejection of the classic journal-lines alternative (Decision 6), the Security posture (Decision 7), the Decision-3 / ledger impact (Decision 8), and the migration plan (Decision 9).

The single most consequential reframe (Decision 1) is that **`account_trans` immutability is an audit control over raw FACTS, not a freeze on our interpretation** — which reopens and amends [ADR-025](#adr-025)'s "the ledger is immutable, so `transaction_type` permanence is good" justification (see Amendment 1).

### Decision 1 — Facts vs. interpretation: the ledger is event-sourced; immutability protects facts, not classification

**Decision:** Treat `pfin.account_trans` as an **event-sourced store of raw facts** the source asserts (`amount`, `quantity`, `transaction_date`, `security_id`, `account_id` — `004`/`017`). Its immutability (the `004` UPDATE/DELETE/TRUNCATE triple-fence) is a **tamper-evidence audit control over those facts**. **Interpretation** — flow-class/category, open-vs-close designation, lot-matching, transfer grouping — is a **separate, MUTABLE layer** (the `023` overlay + the new structures below). Current state (position, cost basis, value, NAV) is a **roll-forward of dated events** (`fn_holdings_as_of`, `019`). **Economic adjustments** (return-of-capital, mark-to-market, depreciation) are **new dated transactions, not edits**; only genuine source *errors* use reverse-and-replace (`is_reverse` + `replaces_trans_id` + the `#2` matched-account fence, `004`).

**Why:** Conflating "tamper-proof audit trail" with "our interpretation is final" was the error in the earlier framing. Permanence is correct for facts (a buy is a buy) but a *cost* for anything inferred — on **import there is no buy-to-open vs buy-to-close distinction** (open/close needs position inference, which can be wrong), so a frozen inferred designation would be a defect. The freeze spectrum: **provider raw facts** (immutable audit) → **app-generated structural** e.g. `acct_setup` (defensibly immutable — creation is app-controlled) → **inferred interpretation** (open/close, category, lot-match — MUST be mutable).

**Amends [ADR-025](#adr-025).** ADR-025 justified `transaction_type`-as-an-immutable-column with "the ledger is immutable → permanence is good." This ADR corrects the *scope* of that permanence: `transaction_type` stays frozen-per-row **but its vocabulary is restricted to fact-level event kinds**; inferred designations move to the mutable overlay. See **Amendment 1** for the six preserved commitments; Security consult applies because it concerns the semantics of the audit control.

### Decision 2 — Account model: three buckets, calculated subsidiary accounts, manual accounts (A/R + A/P), hierarchical escape hatch

**Decision:** The GL operates over **three clearly-separated buckets**:
1. **Real accounts** — assets + liabilities, institution-linked OR manual (`fn_create_manual_account`, `013`). Carry real balances, count in NAV. Assets debit-normal; liabilities credit-normal. Asset-vs-Liability is the one accounting class already in the schema (`account_type='liability'`, `003:96–99`).
2. **Imputed flow-contras** — Income / Expense / Equity: the other side of a flow, **derived in the GL view** from the row's class (Decision 3). Never stored.
3. **Suspense** — a single virtual should-be-zero account; nonzero = unclassified activity = the to-do list.

**Subsidiary accounts are calculated, uniform across all account types:** `(account_id, security_id)` is the sub-ledger (`security_id IS NULL` = cash sub-account; each distinct `security_id` = a holding), already rolled forward by `fn_holdings_as_of` (`019`). Terminology: `pfin.asset` (`016`) is the instrument **registry** (definitions), not positions; positions are derived. Real-estate / personal-holdings manual accounts carry a `security_id`-referenced per-user asset (`asset_type='real_estate'`/`'private'`, `pricing_source='manual_valuation'`, `016`) with `quantity=1`, valued by a manual `eod_price` — one `fn_compute_nav` code path for cash, stocks, and a house.

**Manual accounts resolve the old "virtual/composite account" question.** **A/R (Accounts Receivable)** = a real *manual asset* account for money that is yours but not in your possession (escrow, deposits, cash-in-transit) — debit-normal, counts in NAV, kept **separate from Suspense** (A/R is a real claim; Suspense is an unclassified-error bucket). **A/P** = the mirror manual liability. The only genuinely virtual/derived accounts are the imputed flow-contras + Suspense.

**Hierarchical accounts — additive, deferred escape hatch (`M-hier`).** A nullable self-referential `parent_account_id` on `pfin.account` turns the flat list into a chart of accounts: **class/normal-balance inherit down** (a child of "Accounts Receivable" *is* A/R), **balances roll up** (parent shows aggregate; children collapse beneath). `parent_account_id = NULL` = today's flat behavior, unchanged — so it lands **only if the account count ever warrants it**, with no rearchitecture. It sits on the mutable account structure (fits Decision 1). Gate: Decision-3 same-tenant self-FK fence + Sec joint-review.

**Why:** the buckets keep real balances, derived contras, and the error-signal strictly separated; manual accounts are the cheap, already-built home for every synthetic balance we thought needed virtual structure; hierarchy de-risks the one ergonomic bet (Decision 6) without committing to it now.

### Decision 3 — Category-as-class: the top-level cashflow Category IS the accounting class; no `flow_class` / no `normal_balance` column

**Decision:** Constrain the **cashflow-domain** `user_taxonomy.cat` (`009:155`, today free text with no CHECK) to the fixed enum `{Income, Expense, Transfer, Distribution, Equity}` via a **domain-conditional CHECK**; `sub_cat` stays free text. The Category **is** the class marker — **no separate `flow_class` column**. Normal-balance **derives** from the class (Income/Equity credit-normal; Expense/Distribution debit-normal) — **no `normal_balance` column**. Class always top-level (`Transfer::Internal`, never `OtherCF::Transfer`). Asset-allocation cats (`domain='asset'`) stay free. Of the 5: four → imputed contras; **Transfer → a real↔real link** (both legs real; no contra). The transaction's category lives on the mutable overlay `account_trans_annotation.sub_cat_id → user_taxonomy` (`023`), 1:1.

**Why:** the accounting class of a discretionary cash flow *is* its top-level category — a separate normalized column (the earlier proposal) was redundant with the category the user already assigns. Enforcing it at the taxonomy grain (not the account grain) is correct: an account holds flows of many classes; the *category* is what carries a fixed class.

**Sketch:**
```sql
alter table pfin.user_taxonomy add constraint user_taxonomy_cashflow_class_chk
  check (domain <> 'cashflow' or cat in ('Income','Expense','Transfer','Distribution','Equity'));
```

**Event-class vs. flow-class partition (the reconciliation).** Two vocabularies exist: the **event-kind FACT** (`transaction_type`, immutable ledger) and the **flow-class INTERPRETATION** (cat, mutable overlay). They are partitioned by **axis** so **every row has exactly one authoritative class source**: structural events (`acct_setup`→Opening-Balance-Equity; `basis_adjust`→contra by `reason`; `security_buy/sell`→balance-sheet-internal or realized-gain-to-equity; `dividend_cash`→Income) take their class from the event kind and **never consult the cat**; discretionary `cash_flow` rows take their class from the cat. Open/close (BTO/STC/BTC/STO) is **inferred → mutable overlay** (the raw fact is only "bought/sold N shares"). This partition is the Amendment-1 / M1-evt surface (Decision 7 binding conditions).

### Decision 4 — Dual book/market valuation; `basis_adjust` events; Unrealized-Gains equity line (F/CTO quick-locks)

**Decision:** Keep **two** balance sheets: (a) **book-value accounting** (historical cost, realized-only) — the double-entry that sums to zero; (b) **market-value net worth** (`fn_compute_nav`, `019`, unrealized-inclusive). The gap is a single **Unrealized-Gains equity line**: **`net worth = book equity + unrealized gains`** *(F/CTO quick-lock: book-value-primary confirmed sound — a historical-cost realized-only book is what balances; unrealized MTM is properly an equity overlay)*. This is **NOT multi-book** — cost basis, accumulated depreciation, and market value are just attributes every position carries (one entity, two valuation lenses).

**`basis_adjust` event type.** Depreciation / return-of-capital / wash-sale / corporate-action are **new dated `basis_adjust` transactions** whose magnitude rides the **`cost_basis` column, NOT `amount`** (a book adjustment moves no cash): `security_id`=asset, `quantity=0`, `amount=0` (except return-of-capital, which also carries `amount`=cash), **`cost_basis`=signed delta**, `transaction_type='basis_adjust'`, **`reason` ∈ {depreciation, return_of_capital, wash_sale, corporate_action}**. The GL imputes the contra by `reason` (depreciation → Dr Depreciation-Expense / Cr book-value reduction → Retained Earnings; RoC → cash leg + basis reduction, no income contra). **One `cost_basis` roll-forward** = original cost + Σ(basis_adjust deltas); **accumulated depreciation = derived** (filter `reason='depreciation'`, no separate column); **recapture survives** (`recapture = min(gain, accumulated_depreciation)`); at sale `gain/loss = proceeds − effective_cost_basis → Equity/Retained Earnings`.

**F/CTO quick-lock (confirm):** this **widens `cost_basis`'s role** from "per-lot/aggregate *acquisition* basis" (`017:175,253`) to "signed basis-*delta* per basis-affecting event." Semantic widening of an existing column, not a new column; `fn_compute_nav` values on market `eod_price` (not `cost_basis`), so the NAV path is unaffected — the book-value GL is the new consumer.

**Why:** depreciation touches book value, not market price; a personal net-worth app wants both the market NAV it already computes and a balancing book ledger, reconciled by one equity line rather than a second set of books.

### Decision 5 — The GL engine: imputed contras + `journal_group_id` grouping + virtual scratch/Suspense; `Σ=0` at group-close

**Decision:** The general ledger is a **derived `SECURITY INVOKER` read helper** (`fn_gl_entries`, Lock 11 like `fn_compute_nav`) that images each real row into a balanced debit/credit pair: the stored leg is the real (sub-)account; the other leg is imputed from the class (Decision 3) or resolved via grouping. **N-legged entries come from GROUPING real rows, not a stored journal-line table:** a `journal_group_id` on the mutable `023` overlay ties N real `account_trans` rows with `Σ=0`, backed by a `pfin.journal_group` parent (`group_type ∈ {transfer, transfer_in_kind, compound}`, `status ∈ {open, closed}`). A **virtual scratch/Escrow account, unified with Suspense**, is the universal counter-leg for "the matching leg hasn't arrived yet." **Balance (`Σ=0`) is enforced at group-CLOSE, not insert** — open groups park residual in per-tenant scratch/Suspense; closed groups must balance.

**Mixed cash/security balance (the reconciliation):** the group invariant is checked in **the GL view's value space**, not raw `amount`, with `group_type` selecting the conservation law — `transfer` → cash `Σ(amount)=0`; `transfer_in_kind` → per-`security_id` `Σ(quantity)=0`; `compound` → GL-projected value at the transaction-time `price` (`017`), snapshotted deterministically at close (never re-valued).

**Storage-enforced balancing is folded in, not needed as a per-row control:** the GL emits balanced pairs by construction → the trial balance zeroes by construction → the only imbalance is unclassified → Suspense. A hard balance control exists only at group-close (above), which is the feed-compatible home for it.

**Header-comes-AFTER-the-lines (the structural insight):** feed-sourced legs arrive independently/asynchronously and are grouped **post-hoc** on the overlay. Classic journal-lines (header-first: author a balanced entry as a unit) **fights feed-sourced reality** — grouping is not merely lighter but structurally correct here. (This is the basis for Decision 6.)

**Sketch:**
```sql
create table pfin.journal_group (
  group_id bigint generated always as identity primary key,
  users_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  group_type text not null check (group_type in ('transfer','transfer_in_kind','compound')),
  status text not null default 'open' check (status in ('open','closed')),
  description text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table pfin.account_trans_annotation add column journal_group_id bigint references pfin.journal_group(group_id);
-- matched-tenant leg fence (Decision-3 #12) + Σ=0-at-close trigger — see Decision 7/8.
```

### Decision 6 — Classic Approach B (stored `journal_entry`/`journal_line`) REJECTED; the C→B "ladder" retired

**Decision:** Do **not** build a classic header-first journal-entry / journal-line structure. Adopt grouping + manual accounts + imputation + `basis_adjust` (Decisions 2–5) as the **permanent** model. The earlier "C→B graduation ladder" framing is **retired**: there is no ladder to climb — grouping + manual accounts is a *better* model for this domain, not a cheaper approximation of B.

**Stress-test result (could not break "B never needed" within personal-app scope):** every candidate breaker — depreciation, accrued interest/accruals, N-legged compound entries (house purchase), reserves/provisions, opening balances, inter-category reclass, and the hardest all-synthetic-legs case — is absorbed by the model: `basis_adjust` events, A/R/A/P manual accounts, the Escrow/clearing grouping, manual-account-as-stored-virtual-balance, `acct_setup`→OBE, and mutable overlay edits, respectively. **Classic B's only unique capability is header-first atomic authoring of a balanced entry with hand-entered synthetic legs** — which is exactly the thing that fights async feed-sourced legs.

**Honest residual + escape hatch:** the model bets manual-accounts-as-virtual-balances scale ergonomically (they do at personal scale — a handful of A/R/A/P/escrow/reserve accounts; imputed contras + derived roll-forwards scale for free). The bet is de-risked by the additive **hierarchical-accounts escape hatch** (Decision 2 / `M-hier`), which organizes an arbitrarily larger set under a few parents with no rearchitecture. The thesis would only *truly* fail on a pivot the personal-app scope explicitly excludes: a **small-business bookkeeping suite** (thousands of short-lived deferred-revenue schedules, multi-entity consolidation with elimination entries) — and even then hierarchy pushes the ceiling well past any personal need.

**Alternatives considered:**
- **Approach A (views-only, no class dimension):** too thin — a balancing GL needs *some* class + normal-balance dimension; A provides no home for it. Superseded by Decision 3 (class at the taxonomy grain).
- **Approach B (stored header-first `journal_entry`/`journal_line`):** rejected as above — wrong shape for feed-sourced data; its differentiators are covered by grouping (atomic multi-leg), manual accounts + hierarchy (organization/synthetic balances), and imputation (contras). Multi-book / eliminations (a B-adjacent capability) assessed **never needed** for a single-economic-entity-per-tenant app (distinct from Decision 4's book-vs-market dual valuation, which is NOT multi-book).

### Decision 7 — Security posture: conditional-GREEN (no veto, 2026-07-23); binding conditions; joint-review-mandatory at M1-evt + M2

**Decision:** Security assessed the two Sec-gated reconciliations 2026-07-23 — **both conditional-GREEN, no veto.** The event-sourcing reframe (Decision 1) is **audit-sound**: the `004` triple-fence never protected interpretation, so moving classification to the mutable overlay costs nothing from tamper-evidence, and `transaction_type` stays frozen-on-ledger. **§10 stays 3 · SECURITY DEFINER allowlist stays 3** (every new function/fence is INVOKER). The following conditions are **binding**, each **joint-review-mandatory** at author time with a non-vacuous two-tenant pgTAP battery.

**Binding on M1-evt (event/flow-class partition + Amendment 1):**
1. **Mandatory append-only reclassification history** over the GL-routing-relevant overlay columns (cat, open/close, lot-match) — an **INSERT-only side table with its own immutability fence** (mirror `004`), **NOT** an in-place `jsonb` column (jsonb is itself UPDATE-able → not tamper-evident). Classification drives money-routing, so this is a requirement, not polish. `transaction_type` needs none (frozen already).
2. **NULL-cat fail-safe** — a `cash_flow` row with NULL/Unsorted cat routes to **Suspense**, never a silent default class.
3. **Fact-level-only `transaction_type` vocabulary is a durable invariant** — no inferred value (open/close) may ever become a `transaction_type` value.
4. **Lot-matching buy-reference FK = a NEW Decision-3 instance** — a sell referencing its matched buy `trans_id` is a self-referential tenant-scoped FK (like `replaces_trans_id` `#2`) → matched-account/matched-tenant fence required; evaluate + count at that migration.
5. **The append-only history table is itself a new write surface** → ships with its own immutability fence + two-tenant test (residual).

**Binding on M2 (grouping fence + mixed-unit balance) — one standing VETO trigger:**
1. **Matched-tenant leg fence** — `BEFORE INSERT OR UPDATE` on `account_trans_annotation` WHEN `journal_group_id IS NOT NULL`, resolving the leg's tenant via the `023` chain (`trans_id → account_trans.account_id → account.users_id`) and requiring `= journal_group.users_id`; NULL-safe fail-closed, INVOKER, `set search_path=''`. A clone of the shipped `#10` sub_cat fence. **= Decision-3 instance `#12`** (Sec numbering sign-off at M2).
2. **Virtual scratch/Suspense MUST be strictly per-tenant — a shared/global scratch is a hard VETO.** It carries parked balances; a global singleton cross-contaminates NAV *and* leaks another tenant's unreconciled activity. Instantiate as a per-tenant `pfin.account` row (`fn_create_manual_account`, `013`, already `users_id`-scoped).
3. **`users_id` code-binding under any privileged path** — `default auth.uid()` is fine for V1 user-authored grouping under `authenticated`; if any feed/worker path ever creates groups under `service_role`, bind `users_id` in code from the validated session (ADR-027 clause-(t)), never column-default/client-body.
4. **UPDATE policy `WITH CHECK (users_id = auth.uid())`** on `journal_group` — no cross-tenant close/reopen, no `users_id` reassignment.
5. **C6 exposure-gating (ADR-023)** — two-tenant RLS battery proves cross-tenant read+write fail closed *before* grant; `service_role` gets nothing in V1.
6. **NAV/GL must include the per-tenant Suspense residual in net worth** — parked money in an open group must not silently drop out of NAV.
7. **`compound` group_type snapshots GL-projected value deterministically at close** (transaction-time `price`, `017`), never re-valued (a re-valued check lets a closed group silently un-balance later).

Group open/close (Recon #3) is Sec-sound, not a security risk (open-group residual sits in the tenant's own per-tenant Suspense; folded into M2 conditions 6–7). Book-value-primary (Recon #4) is Sec-neutral (F/CTO quick-lock, Decision 4).

### Decision 8 — Decision-3 / ledger impact: two new instances forward-flagged; §10 and DEFINER ledgers flat

**Decision:** The model adds **two new Decision-3 (cross-tenant FK-bypass) instances**, both matched-tenant-fenced with Sec numbering sign-off at their migration: **`journal_group_id` (labeled `#12`)** (Decision 7 M2 cond 1) and **the lot-matching buy-reference FK** (Decision 7 M1-evt cond 4; label assigned at its migration). Both extend [ADR-011](#adr-011) Decision 3 (currently 11 labeled instances / 9 DDL-realized). The `M-hier` `parent_account_id` self-FK (Decision 2), if built, is a third same-tenant fence (evaluated at `M-hier`). **All other ledgers flat: §10 catalogued-instance ledger stays 3 (RT-22 + RT-26 + RT-27); SECURITY DEFINER allowlist stays 3** — every new function and fence is `SECURITY INVOKER`.

### Decision 9 — Migration plan (reference, not commitment) + the ordering-vs-backfill one-way-door

**Decision:** The model realizes as additive migrations, each independently shippable and reversible-while-empty (reference sequence, not a lock):

`M1` (Category-as-class CHECK; no `flow_class`) → `M1-evt` (event-class vocabulary refactor + Amendment 1; **Sec conditional-GREEN conditions binding**) → `M2.5` (split-child table `account_trans_split`, 1:many, Σ=parent — the everyday receipt split, ranked above depreciation) → `M2` (`journal_group` + `journal_group_id` + matched-tenant fence + scratch/Suspense; **joint-review-mandatory**) → `M3-basis` (`basis_adjust` event + `reason`) → `M4-GL` (`fn_gl_entries` INVOKER GL/trial-balance helper: book-value double-entry + market/Unrealized-Gains + imputed contras + Suspense + group + split reads) → `C+` (formalize the SD-12 monthly-report snapshot to freeze Income Statement / Balance Sheet / Statement of Equity, incl. book/market split — spec-locked, build-pending) → `M-hier` (deferred hierarchical accounts, build only if account count warrants).

**ONE-WAY DOOR:** the **category→class map**, the **event-class vocabulary + ADR-025 semantics**, the **grouping/pairing rule**, and the **basis-delta convention** all **imprint on the incumbent transaction import** — settle them (F/CTO ratify + Sec where flagged) **before the export imports**. The column/CHECK/table adds, the `M4-GL` view, and the `C+` snapshot formalization are additive/read-only and can land anytime.

**What is untouched:** `account_trans` FACT columns + the `004` immutability triple-fence (only `transaction_type`'s *vocabulary* is refactored + `reason` added); `fn_compute_nav`/`fn_holdings_as_of` (`019`, reused not rewritten); signed `amount`/`quantity` (R-7); the SECURITY DEFINER allowlist (stays 3).

### Consequences

- **Amends [ADR-025](#adr-025)** — see **Amendment 1** (immutability of `004` is an audit control over raw facts, not a freeze on classification; `transaction_type` fact-level-only). ADR-025's three components (`sub_cat_id` FK, AcctSetup discriminator, `is_active` reuse) are otherwise unchanged.
- **Extends [ADR-011](#adr-011) Decision 3** — two new forward-flagged instances (`journal_group_id` `#12` + lot-match buy-reference FK); numbering sign-off at each migration. §10 (Decision 4) unchanged at 3; DEFINER allowlist (Decision 9) unchanged at 3.
- **Retires the v1 "C→B graduation ladder"** (Decision 6) — grouping + manual accounts is the permanent model; classic B is not a planned future state.
- **Pending F/CTO quick-locks:** book-value-primary (`net worth = book equity + unrealized gains`) + the `cost_basis` role-widening (Decision 4).
- **Joint-review-mandatory** at `M1-evt` and `M2` (Decision 7); paired non-vacuous QA two-tenant pgTAP at every fence + the GL view.
- **Handoffs:** Architect authors the migrations; QA authors the `supabase/tests/` two-tenant pgTAP batteries (incl. the append-only reclassification-history immutability test); Backend applies via `supabase migration up` after CI fixture-seed verification, then builds the GL/statement UI; DevOps wires any new CI fixture rows.
- **Cross-references:** `temp/double-entry-design-v2.md` (design of record); [ADR-027](#adr-027) (the `015`–`023` substrate this layers over); [ADR-011](#adr-011) D1/D2/D3/D4/D9 + Lock 11; [ADR-023](#adr-023) C6; [ADR-025](#adr-025) (amended); [ADR-022](#adr-022)/[ADR-024](#adr-024) (CHECK-vs-registry for `transaction_type`/`reason`); `004`/`009`/`012`/`013`/`016`/`017`/`019`/`023` migrations.

### ADR-031 — Amendment 1 (2026-07-23): settle-before-import category / event conventions

**Context.** ADR-031 Decision 9 flagged four conventions that **imprint on the incumbent transaction import** as a one-way-door — the category→class map, the event-class vocabulary, the grouping rule, and the basis semantics — to be settled *before* backfill. The F/CTO ratified them 2026-07-23 (`temp/settle-before-import-conventions.md`). This amendment records the refinements they make to ADR-031 Decision 3 (the class enum + the event/flow-class partition), Decision 4 (`reason` home), Decision 5 (grouping naming), and Decision 9 (the event vocabulary). **Sec re-confirmed GREEN-with-conditions 2026-07-23** on the item-2 partition refinement (Cat-driven `Trade` — Sec: it *tightens* the partition) + the item-9 V2 deferral, no veto; two binding conditions (A on item 2, B on item 9) fold in below and attach to the M1-evt / M2 joint-review gates (ADR-031 Decision 7).

**The refinements are additive to the model's shape** (Decisions 1–2, 5–8 stand); they sharpen the *vocabulary* Decisions 3/4/9 left at first-cut granularity, and they settle three items ADR-031 had left open (shorts, ticker renames, the `reason` home).

**1 — The cashflow class enum is 5: `Revenue · Expense · Transfer · Equity · Trade`.** Refines Decision 3's `{Income, Expense, Transfer, Distribution, Equity}`:
- **Income → Revenue** (double-entry naming); **Expenses → Expense** (singular).
- **Distribution demoted** from a top-level class to **`Equity::Distribution`**, symmetrical with **`Equity::Contribution`** (Opening-Balance stays imputed via `acct_setup`).
- **`Trade` added** as a top-level class (securities buy/sell — item 2).
- Dissolved top-level cats: `OtherCF` (→ Transfer / Trade / event-axis) and `AcctSetup` (→ the `acct_setup` / `corp_action` / `basis_adjust` event-types).
- Enforcement unchanged from Decision 3: a **domain-conditional CHECK** on `user_taxonomy.cat` (`domain='cashflow'` only); `sub_cat` free; normal-balance derived from the class (Revenue/Equity credit-normal; Expense debit-normal; Transfer real↔real; Trade self-balancing).

**2 — `Trade` is a top-level Cat with sub-cats `BTO / STC / STO / BTC`; the open/close designation lives IN the Cat, on the mutable overlay — NOT a separate `open_close` column.** **This SUPERSEDES the Decision-3 / Recon-#1 detail that "securities rows carry NULL cat + a separate open/close designation."** A securities row is now categorized like any other row — via the Cat — so there remains exactly **one mutable class source per row** (the Cat), and the earlier two-column split (NULL cat + a designation field) is dropped. Two constraints:
- **(a) Consistency:** `security_id` present ⟺ Cat = `Trade` (a securities row *must* be a Trade; a Trade *must* carry a `security_id`). Because `security_id` lives on the immutable ledger (`004`/`017`) and the Cat on the overlay (`023`/`009`), this is enforced at the **write boundary** (Backend/trigger), not a single-table CHECK.
- **(b) Sign-alignment (new, F/CTO):** the Trade sub-cat must match the sign — **`BTO`/`BTC` ⟹ `quantity > 0`** (buy, `amount < 0`); **`STC`/`STO` ⟹ `quantity < 0`** (sell, `amount > 0`). Enforced in the **UI** (fast feedback — the F/CTO's ask) **and** at the **write boundary** (authoritative — the UI is not the integrity boundary); a mismatch is an **error**, not a silent accept.
- **Buy-vs-sell stays DERIVED** from `sign(quantity)` — no explicit `security_buy`/`security_sell` event type (item 4).
- **Sec Condition A (binding on M1-evt — GREEN-with-conditions 2026-07-23): both Trade constraints are TRIGGERS, not CHECKs.** Both (a) consistency and (b) sign-alignment are **cross-table** — `security_id`/`quantity` on the immutable ledger (`004`/`017`), `cat`/`sub_cat` on the mutable overlay (`023`) — so a single-table CHECK cannot span them. Realize both as a **`BEFORE INSERT OR UPDATE` trigger on `account_trans_annotation`**, resolving `security_id`/`quantity` via `trans_id → account_trans`, NULL-safe fail-closed, `SECURITY INVOKER`, `set search_path = ''`. **The UPDATE path is load-bearing:** editing the Trade sub-cat (e.g. BTO→STO) on a frozen-quantity row must **re-validate against the frozen fact on every overlay edit**, or the invariant rots. SECURITY DEFINER allowlist stays 3; these two fences are **Decision-3-neutral** (no cross-tenant dimension). Orthogonal note: Recon-#1 condition #4 (the **lot-matching buy-reference FK** = a new Decision-3 instance) **stands** — open/close is the *designation* (Cat-carried, item 2), whereas *which buy a sell closes* is a separate FK requiring its own matched-account fence; the two are distinct.

**3 — `Transfer ⟺ tax-neutral` (definitional rule).** A Transfer is *by definition* a movement with **no tax event** (no basis established, no gain/loss recognized): `Transfer::Cash` (cash between accounts) and `Transfer::Asset` (**in-kind holding moves only**, e.g. move 100 AAPL Fidelity→Schwab). An actual **purchase or sale is a `Trade`, never a Transfer** — this rule is the test that separates the two.

**4 — Lean event vocabulary: `transaction_type ∈ { standard, acct_setup, basis_adjust, corp_action }`.** SUPERSEDES Decision 9 / ADR-025 Amendment 1(c)'s first-cut fact-level list (`cash_flow`/`security_buy`/`security_sell`/`security_transfer`/`basis_adjust`/`dividend_cash`/`acct_setup`). **Buy/sell is derived** from `sign(quantity)`, so no explicit security-movement types are needed; `standard` carries **both cash flows and trades** (class from the Cat), and the three structural types are **NULL-cat** (class from the type):
- `standard` — cash flows + trades; class from Cat; trades self-balance + realized gain/loss on close.
- `acct_setup` — opening balances (was Add/Remove-Item) → Opening-Balance-Equity contra.
- `basis_adjust` — cost-basis-only moves (item 6).
- `corp_action` — splits / swaps / ticker renames (item 5).
- **NULL-cat fail-safe unchanged** (Decision 7 M1-evt cond 2): a `standard` cash row with NULL Cat routes to **Suspense**; a structural row with NULL Cat is *correct* (class from the type). **Fact-level-only invariant unchanged** (ADR-025 Amendment 1(c)): no inferred value becomes a `transaction_type` value — and note the open/close *designation* now lives in the Cat (item 2), fully on the mutable overlay, consistent with that invariant.

**5 — `corp_action` covers splits + swaps + ticker renames — ALWAYS a dated transaction, NEVER a registry rename.** A rename would retroactively falsify as-of-date holdings, violating the event-sourcing principle (Decision 1); a dated event preserves the timeline. Both the old and new tickers persist as **distinct registry assets** (`pfin.asset`, `016`); `metadata.action` records the kind (`split` = quantity restatement, **no GL**; `swap`/`ticker_change` e.g. FB→META = basis carryover, no gain / no equity). *(Resolves ADR-031's open item Q-D.)*

**6 — `basis_adjust` carries `metadata.reason ∈ { depreciation, return_of_capital, wash_sale }` (routing-relevant).** Refines Decision 4: `corporate_action` is removed from the `reason` set (it is now its own `corp_action` event type, item 5), leaving the three tax/book reasons. Row shape unchanged (Decision 4): `security_id`=asset, `quantity=0`, `amount=0` except return-of-capital which carries `amount`=cash, `cost_basis`=signed delta. Contra by reason unchanged (depreciation → Dr Depreciation-Expense / Cr book-value; return_of_capital → cash + basis reduction, no income).

**7 — Shorts: store uniform, present derived.** A short is stored as a **negative-quantity holding** (`quantity = −N`, value `−N × price`) — uniform with every other holding, no new stored account type or valuation path. The **GL view reclassifies any holding with `quantity < 0` as an imputed `Securities Sold Short` liability** (at `|qty| × price`, marked to market — the GAAP "Securities Sold, Not Yet Purchased" home). `STO` imputes `Dr Cash / Cr Securities-Sold-Short`; `BTC` imputes `Dr Securities-Sold-Short / Cr Cash + Realized Gain/Loss`. (Margin interest, if any, is a normal `Expense`.) *(Resolves ADR-031's open item Q-B.)*

**8 — Naming (ratified).** `journal_id` (**was `group_id`** — SUPERSEDES Decision 5's `pfin.journal_group.group_id` + the `023.journal_group_id` column naming; the Decision-3 instance formerly labeled `journal_group_id` `#12` is now the `journal_id` FK, numbering unchanged). `metadata` jsonb (**was a `reason text` column** — SUPERSEDES Decision 4's `reason text CHECK(...)` sketch; the `reason` is now `metadata.reason`, and corp-action details are `metadata.action`).

**9 — `reason` / reclassification-history DEFERRED to V2 (F/CTO scope call).** The mutable overlay fields (Cat, Trade sub-cat, `metadata`) stay **freely editable** in V1. This **NARROWS Sec's binding condition #1** (ADR-031 Decision 7 M1-evt cond 1 — the append-only reclassification-history table) to a **V2 deferral**: Sec flagged it as a *should*, not a veto, and the **monthly-report snapshot** (SD-12, ADR-031 Decision 9 `C+`) already freezes point-in-time truth for tax-audit reconstruction, so per-cell change-forensics is a low-value single-user nicety.
- **Sec Condition B (binding — GREEN-with-conditions 2026-07-23): the deferral is COUPLED to the snapshot shipping in V1 as a genuine immutable freeze.** The V2 deferral is valid **only if the monthly-report snapshot (`C+`) ships in V1 as an immutable, point-in-time freeze** — audit-class posture with its **own immutability fence like `004`**, NOT a re-derivable view over the live overlay (a re-derivable snapshot would defeat the reconstruction guarantee that is the entire rationale for the deferral). **If the `C+` snapshot migration slips to V2, the reclassification-history condition MUST be reopened** — this dependency is recorded explicitly so the two do not defer silently. `metadata.reason` / `metadata.action` inherit the same no-forensics gap, **accepted for V1 under the same snapshot rationale** (the frozen `transaction_type` carries primary routing; `metadata` is a sub-discriminant). **Re-confirm at M1-evt** (the item-2 Cat-driven partition + this deferral-with-Condition-B are the two Sec re-confirm items).

**What this amendment supersedes (summary):**
- **ADR-031 Decision 3 enum** `{Income, Expense, Transfer, Distribution, Equity}` → **`{Revenue, Expense, Transfer, Equity, Trade}`** (item 1).
- **ADR-031 Decision 3 / Recon-#1** "securities rows carry NULL cat + a separate open/close designation" → **Cat-driven `Trade`** (open/close in the Cat sub-cat; still one mutable class source; consistency + sign-alignment write-boundary-enforced) (item 2).
- **ADR-031 Decision 9 / ADR-025 Amendment 1(c)** first-cut fact-level vocabulary → **lean 4-value `{standard, acct_setup, basis_adjust, corp_action}`** (buy/sell derived) (item 4).
- **ADR-031 Decision 4** `reason text` column + the 4-value reason set → **`metadata.reason` jsonb** with `{depreciation, return_of_capital, wash_sale}` (`corporate_action` promoted to the `corp_action` event type) (items 6, 8).
- **ADR-031 Decision 5** `journal_group` / `group_id` naming → **`journal_id`** (item 8).
- **Narrows ADR-031 Decision 7 M1-evt binding condition #1** (append-only reclassification-history) → **V2-deferred**, Sec re-confirm at M1-evt (item 9).

**Unchanged.** The model's shape (Decisions 1, 2, 5–8), the Sec conditional-GREEN posture and the M2 grouping conditions (Decision 7 binding on M2 stand in full), the ledger flatness (§10 stays 3 · SECURITY DEFINER allowlist stays 3 — all new fns/fences INVOKER, incl. the two new item-2 Trade-constraint triggers per Condition A, Decision 8), the two forward-flagged Decision-3 instances (the `journal_id` FK, still `#12`; the **lot-matching buy-reference FK stands** — per Sec Condition A it is orthogonal to the Cat-carried open/close designation, evaluated with its own matched-account fence at its migration), and the migration sequence + the settle-before-import one-way-door (Decision 9) all stand.

**Cross-references:** `temp/settle-before-import-conventions.md` (the ratified record) + `temp/double-entry-transaction-column-map.md` (worked examples, Tables 1–2); [ADR-031](#adr-031) Decisions 1/3/4/5/7/9 (amended above); [ADR-025](#adr-025) + Amendment 1 (the `transaction_type` fact-level invariant this vocabulary conforms to); [ADR-022](#adr-022)/[ADR-024](#adr-024) (CHECK-vs-registry for the `transaction_type` + `cat` enums); `004`/`009`/`012`/`016`/`017`/`023` migrations.

---

## ADR-030 — Auth-3b Slice 2: MFA recovery codes — `service_role`-forced recovery + the `026` store (SELF-291)

**Date:** 2026-07-22 · **Status:** Accepted (F/CTO-ratified 2026-07-22 — Opt A + leans #2–#6 + #7 SELF-288 stays open; the `026` migration returns for **Sec joint-review** — the `service_role`-grant surface — before merge; the ADR-016 amendment + RT-26 allowlist edit land with Slice 2b) · **Phase:** 6

**Context.** Slice 1 (ADR-029, `025`) shipped the aal2 backstop + the MB-1 downgrade guard. Slice 2 delivers **MFA recovery codes** (the lost-phone path) — SELF-288's recovery-codes portion (SELF-288's password-reset portion stays open per F/CTO #7). The design question was whether recovery can avoid a new privileged surface. It cannot.

**Capability-verify of record (local stack — GoTrue v2.189, PG 17.6; throwaway probes, cleaned up):**
- **CV-R1 = BLOCKED.** An `aal1` session `mfa.unenroll()` of a **verified** factor returns `422 insufficient_aal` — *"AAL2 required to unenroll verified factor."* (Verified against the exact state: fresh password login with a verified factor → `AAL {current: aal1, next: aal2}`.)
- **service_role admin `deleteFactor` of a verified factor = SUCCESS** (the supported removal path).
- **service_role has `BYPASSRLS` but no grant on `pfin.user_settings`** (024 granted it nothing) — a grant is required for the recovery downgrade.

**Decision.**

1. **Recovery is a `service_role` surface BY CONSTRUCTION** — three independent forcings, each sufficient: (a) the MB-1 guard (`025`) blocks an `authenticated` aal1 session from lowering `mfa_policy`, and a recovering user is `authenticated`+`aal1`; (b) CV-R1 = BLOCKED → the factor-removal (which is *required* — else GoTrue keeps `nextLevel=aal2` and the Slice-1 fail-closed app guard still blocks the user) can only be done by `service_role` admin `deleteFactor`; (c) the recovery-code hashes are `service_role`-only. So **conditional-lock #4 (ADR-029 / design-spec §9) resolves to Opt (ii) `service_role`** — not because CV-R1 "failed" but because no design escapes `service_role` for the GoTrue removal. Rejected alternatives: a DEFINER RPC for the downgrade (still needs `service_role` for the GoTrue leg AND adds a 4th DEFINER entry — strictly worse); a DEFINER RPC mutating `auth.mfa_factors` directly (brittle/unsupported/Sec-veto).

2. **The `026` store — `pfin.mfa_recovery_code`, `service_role`-only.** One row per issued code: `users_id` (tenant-anchor FK → `auth.users`, `ON DELETE CASCADE`), `code_hash` (app-side bcrypt/argon2 — the DB holds only the hash, never plaintext), `batch_id`, `used_at` (NULL = unspent; the one-time double-spend guard), `created_at`. **RLS enabled with ZERO authenticated policy/grant → default-deny at the authenticated tier** (mirrors `linked_source_sync_audit`); the hashes never reach the direct PostgREST API. `service_role` SELECT/INSERT/UPDATE (redemption reads+consumes; issuance inserts); anon/authenticated zero. No function authored — DEFINER allowlist stays 3.

3. **The recovery downgrade grant.** `026` grants `service_role` **`select (users_id)` + `update (mfa_policy)` on `pfin.user_settings`** (least-privilege — the downgrade only). *Refinement of the ratified "update(mfa_policy) only":* the `select (users_id)` is **required** for the recovery UPDATE's `WHERE users_id=$1` (Postgres needs SELECT on WHERE-referenced columns; `update(mfa_policy)` alone raises `permission denied for table user_settings` — verified empirically). `service_role` still cannot read `mfa_policy` or write any column but `mfa_policy` (both confirmed on the local stack). The MB-1 guard exempts `service_role` (`current_user <> 'authenticated'`), so the privileged downgrade passes.

4. **Redemption flow (`/mfa/recover`, aal1-reachable — Slice 2b).** verify (app-side constant-time compare vs the live hashes) → **consume** (`UPDATE used_at WHERE used_at IS NULL` — one-time) → **downgrade** (`mfa_policy → 'none'`, `service_role`, guard-exempt) → **admin `deleteFactor`** (remove the dead factor; idempotent) → **notify** → redirect to re-enroll. **Recovery mints NO aal2** — it removes the dead factor + downgrades intent so the user is `aal1`-sufficient, then re-enrolls the normal way (the ADR-029 §3 reframe, realized). `used_at IS NULL` is the double-spend guard; commit consume+downgrade before the admin delete (retry the delete on transient failure — it must succeed for access to restore).

5. **Issuance & posture (ratified leans).** Auto-issue a batch at first TOTP enrollment **+** on-demand regenerate from `/settings/security` (aal2-gated; supersedes the prior batch). **10 codes**, high-entropy, **display-once**. **Rate-limit** redemption (**5 failures / hour / user → temporary lockout** + attempt logging). **notify-on-every-MFA-change** (enroll / disable / factor-removal / regenerate) is **app-sent** (GoTrue has no native MFA-change email); the hooks + templates build now (testable vs the local Mailpit), **prod delivery deploy-gated on Auth-1 SMTP** wiring.

**§10 / ADR-016 sequencing (the sharp one-way-door).** The Slice-2b recovery **endpoint** is a **4th RT-26 `service_role` allowlist surface** → an **ADR-016 amendment** (per ADR-016 D2's durably-ratified-addition convention) + a `scripts/ci/rt26-allowlist.txt` edit. **That change lands with Slice 2b (the `api/src` endpoint code), NOT with `026`** — `026` adds no `api/src` service_role code; it is a DB-ACL grant only. **§10 3-axis (Path B — reference [Decision 4](#adr-011); read VERBATIM before drafting):** the §10 catalogued count **stays 3** (RT-22 / RT-26 / RT-27) at BOTH steps — `026` touches no catalogued surface (a `service_role` DB-ACL grant is DB-layer, NOT the RT-26 code-layer `SUPABASE_SERVICE_ROLE_KEY` literal — same reasoning as `008`), and the Slice-2b RT-26 allowlist growth 3→4 endpoints is an **intra-instance** ADR-016 amendment, not a new catalogued instance or a layer re-attribution. (i) numbering unchanged; (ii) layer-attribution unchanged; (iii) Decision 4 linked, not restated. **DEFINER allowlist stays 3** (no function). **Decision-3 unchanged** (`026`'s only FK is the tenant anchor `users_id`).

**Slice 2b build contract (sketch — Backend/Frontend author it).** `/mfa/recover` (aal1-reachable — the Slice-1 `hooks.server.ts` guard exempts `/mfa`; **confirm the prefix covers `/mfa/recover`**): a `service_role` endpoint doing verify→consume→downgrade→admin `deleteFactor`→notify. Issuance: the display-once codes UI at enrollment + a `/settings/security` regenerate. The RT-26 allowlist + ADR-016 amendment land here. QA: the `026` default-deny assertion (authenticated reads/writes 0) pairs now; the end-to-end lost-phone→re-enroll, one-time-use/double-spend, and brute-force-lockout batteries pair with 2b.

**Alternatives considered.** (privilege surface) Opt B DEFINER-RPC + service_role — rejected (§ Decision 1). Opt C DB-internal GoTrue mutation — rejected. (table RLS) owner-readable — rejected (exposes bcrypt hashes to a stolen aal1 session; needlessly widens the surface; the count UI is served by a server endpoint instead). (downgrade grant) broad `update` — rejected for column-scoped least-privilege.

**One-way-door status.** The **4th RT-26 allowlist surface** (Slice 2b) is the one-way-door — an RT-26 expansion is Sec-load-bearing and costly to walk back once code depends on it (ADR-016 amendment gates it). The `026` table + grants are **not** one-way doors (droppable/revocable; no data migration either direction).

### Amendment 1 (2026-07-22) — recovery-code hashing algo-of-record = `scrypt` (lands with Slice 2b)

**Amends Decision 2 / Decision 5** (the app-side hashing choice). F/CTO chose to **drop the `bcryptjs` dependency in favour of Node's built-in `crypto.scrypt`** (supply-chain minimization); Sec blessed it. **Algo-of-record is `scrypt`.** *The merged `026` column comment (and this ADR's Decisions 2/5 + Alternatives) say "app-side bcrypt/argon2" — that wording predates this amendment and is descriptive, not load-bearing; the algo-of-record is `scrypt`.* Per Sec's lean (adopted): **no dedicated re-comment migration** — this amendment carries the algo-of-record truth; a one-line `comment on column` fix piggybacks onto a future `028` only if one lands for other reasons.

- **Algorithm:** Node built-in `crypto.scrypt` (async form), in the Slice-2b `mfa-recovery.ts` helper (no third-party hashing dependency).
- **Parameters (Sec-ratified):** `N = 16384 (2^14)`, `r = 8`, `p = 1`, `keylen = 32`; a **16-byte CSPRNG salt per code**. The salt **and** the params are stored **with each hash** and **versioned** (a params/format tag persisted alongside the digest) so a future parameter change cannot break verification of already-issued codes. (The `026` `code_hash text` column holds the composed `version$params$salt$digest` string — no schema change needed.)
- **Rationale (Sec).** For **80-bit CSPRNG one-time codes** stored `service_role`-only and rate-limited (`027`), the KDF choice is cryptographically near-irrelevant — the `2^80` input entropy dominates any hash-speed advantage an attacker could get. Given that, `scrypt` is chosen because it is **memory-hard** (stronger vs GPU/ASIC than bcrypt), **NIST SP 800-63B-acceptable**, and **RFC-7914-standardized**; **dropping the dependency is the deciding supply-chain win** (one fewer transitive-dependency attack surface in a security-critical path).
- **Verification:** **constant-time** via `crypto.timingSafeEqual` over fixed-length (`keylen`) digests — re-derive per-code using that code's stored salt+params, compare with `timingSafeEqual`, and **no early return** across the ≤10 candidate hashes (so the redemption endpoint leaks neither which code matched nor whether any matched, beyond the boolean result the rate-limiter already gates).
- **Sequencing:** lands with the **Slice-2b app PR** (alongside the ADR-016 Decision 3 factory amendment + the endpoint code). **Sec verifies the implementation at the app-PR hard-gate**; the C2 `docs/SECURITY/index.html` entry (Sec-authored) also documents the algo-of-record + params.
- **Ledgers FLAT:** a hashing-algo documentation change authors no function, no migration, no RLS/grant, no reference column — **§10 stays 3 · DEFINER stays 3 · Decision-3 unchanged.**

**Cross-references.** [ADR-029](#adr-029) (Slice 1 backstop + MB-1 guard; the §3 no-aal2-minted reframe realized here; Slice-2 invariants) · [ADR-016](#adr-016) (RT-26 service_role allowlist — the 4th-surface amendment lands with Slice 2b) · [ADR-011](#adr-011) Decision 1 (privileged-context-write — the `service_role` grants) / Decision 4 (§10 ledger — stays 3) / Decision 9 (DEFINER allowlist — stays 3) / Decision 3 (FK-bypass family — unchanged) · `008` (the layer-attribution precedent for a `service_role` DB-ACL grant) · SELF-288 (recovery-codes portion delivered here; password-reset portion stays open) · design spec `temp/auth-3b-slice2-recovery-design.md`.

---

## ADR-029 — Auth-3b aal2 step-up backstop: per-user-conditional DB/RLS enforcement of MFA step-up (SELF-291, Slice 1 / migration `025`)

**Date:** 2026-07-21 · **Status:** Accepted (F/CTO-ratified 2026-07-21; MB-1 fix = Option A folded into `025` + Decision 6, F-ADR1 folded into Decision 5, both F/CTO-ratified 2026-07-21; the authored `025` returns for **Sec re-review** of the guard DDL + amended Decision 5 before merge) · **Phase:** 6

**Context.** Auth-3 (SELF-286, migration `024`) shipped the MFA substrate ONLY: `pfin.user_settings` with a per-user `mfa_policy IN ('none','totp','passkey')`, plus a fail-soft app reporter. It deliberately deferred the **enforcement** of step-up. The gap Auth-3b closes is Sec's **C2 hard gate**: `pfin` is directly reachable via PostgREST + the public anon key (C6), and base RLS checks `users_id = auth.uid()` but **not** `aal`. So an `aal1` session (password entered, TOTP not yet completed) can read — and write — the user's OWN financial rows through the direct data API. App-layer step-up (a route guard in `hooks.server.ts`) enforces **nothing** on that direct surface; against the password-compromise threat TOTP exists to counter, **the DB `aal` clause is the only layer that actually enforces step-up there.** Empirically capability-verified on the pinned local stack (PG 17.6, GoTrue v2.189.0) before authoring; full design at `temp/auth-3b-design-spec.md`.

**Decision.** Enforce step-up at the DB/RLS layer via a **per-user-conditional aal2 backstop clause**, ANDed into the RLS of the **14 sensitive tenant-owned `pfin` tables** (migration `025`, `ALTER POLICY`).

1. **Per-user-conditional, NEVER blanket.** The clause gates the READER's own declared `mfa_policy`, not the row: a user who declared `totp`/`passkey` must present an `aal2` JWT; every other user (`none`, or no settings row) is unaffected. A blanket `aal2` requirement would lock out `none` users — rejected. Factor-agnostic over the aal2-capable set: the clause references the full `{'totp','passkey'}` set even though **`'passkey'` is deferred from the V1 stored domain** (Decision 7) — so passkey (SELF-289) rides the identical clause with zero change when Auth-6 re-adds it. Canonical clause (COALESCE null-safe):
   ```sql
   (coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none')
      not in ('totp','passkey')
    or (auth.jwt() ->> 'aal') = 'aal2')
   ```

2. **INLINE, no helper function (posture crux; empirically decided).** The clause is inlined into each policy — NOT delivered via a helper. `EXPLAIN` shows the inline form as `InitPlan 1` (the `user_settings` subquery evaluated ONCE per statement, index scan on `user_settings_pkey`). An equivalent `STABLE SECURITY INVOKER` SQL helper is **NOT inlined by the planner because `set search_path=''`** (mandatory function discipline) **disables SQL-function inlining** → it evaluates **per row**. So inline is both faster (single-eval) AND authors no DB object, keeping the **SECURITY DEFINER allowlist at 3 by construction**. The DRY cost (the clause repeats across policies) is accepted: for a security predicate, the exact expression being visible in every policy is an auditability feature. A DEFINER helper (which would move the allowlist 3→4) is rejected — it spends a Sec-gated slot to bypass an RLS read we WANT RLS-scoped, and is also per-row.

3. **Reads + writes scope.** The clause is ANDed into the `USING` of every authenticated read policy AND into the write policies (`INSERT ... WITH CHECK`, `UPDATE ... USING + WITH CHECK`, `DELETE ... USING`) on the authenticated write paths. The password-compromise threat enables destructive WRITES (fabricated transactions, manual-account creation, manual-valuation tampering, annotation deletion), not just reads — gating reads-only would leave that half open. Tables whose only writer is `service_role` (RLS-bypassing) or a DEFINER trigger, or that are V1 write-dormant, have no authenticated write policy to clause (stated per-table in `025`).

4. **COALESCE null-safety (AC-clause amendment).** The SELF-291 AC's verbatim clause — a bare `(select mfa_policy ...) not in ('totp','passkey')` — has a **NULL-lockout bug**: a user with NO settings row yields `NULL not in (...)` = NULL → the row is filtered → the un-enrolled/lazy-provisioned user is locked out of their OWN data at aal1. Because `024` provisioning is LAZY, a row can be legitimately absent at first read. The ratified fix wraps the subselect in `coalesce(...,'none')` (probe test T4: missing-row + aal1 → row VISIBLE). The migration encodes the COALESCE form; the AC clause text is superseded by it.

5. **Deliberate layer-posture asymmetry.** The DB backstop **fails OPEN** on a missing/`none` policy (coalesce → 'none' → reads/writes allowed) — because the universal tenant RLS still fully fences the user, and the backstop enforces only the POSITIVE assertion "this user DECLARED totp/passkey." The app-layer step-up guard (Auth-3b Backend, `hooks.server.ts`) is the COMPLEMENT and **fails CLOSED** on indeterminate MFA state (unknown/missing ⇒ requires step-up), keying primarily off GoTrue's `getAuthenticatorAssuranceLevel()`. Two layers, two postures, on purpose: the DB enforces a positive declaration; the app refuses to guess. **[F-ADR1 amendment, 2026-07-21 — Sec MB-1.]** The fail-OPEN-on-`none` posture is sound **only because `mfa_policy` cannot be adversarially downgraded to `'none'` at aal1 on the direct data API.** Absent that, an aal1 attacker with a stolen password would `PATCH mfa_policy → 'none'` and the coalesce would then read `'none'` → the backstop opens on all 31 policies (a self-defeating control variable). What makes the posture sound is **Decision 6 (the MB-1 downgrade guard)**; this Decision 5 must be read WITH Decision 6, never alone.

6. **MB-1 downgrade guard (Sec BLOCK; F/CTO-ratified Option A, 2026-07-21).** A `BEFORE UPDATE` trigger on `pfin.user_settings` (`fn_user_settings_block_mfa_downgrade`, in `025`) blocks the **authenticated tier** from lowering `mfa_policy` **out of the aal2-capable set `{'totp','passkey'}`** unless the session is `aal2` (`raise insufficient_privilege`). "Weaken" = `OLD IN {'totp','passkey'} AND NEW NOT IN {'totp','passkey'}` — mirroring the backstop's gated set exactly. **Free at aal1** (not weakenings): enrollment `none→totp` (a user must turn MFA on before they can ever reach aal2), and any non-`mfa_policy` edit. **[Under the Decision 7 domain tightening]** lateral `totp→passkey` — assurance-neutral in principle, and the guard still (correctly) does not treat it as a weakening — is now **impossible to store in V1**: the tightened CHECK rejects `'passkey'` with `23514` *before* the guard's decision matters (guard passes → CHECK rejects). So V1's only legal downgrade is `totp→none` (blocked at aal1). The guard nonetheless keeps referencing the full `{'totp','passkey'}` set so Auth-6 re-adds `passkey` with zero guard change. **Tier-scoped to `current_user = 'authenticated'`** so it gates ONLY the untrusted direct-API surface: the trusted server-side downgrade channel (`service_role` recovery — Slice-2 invariant 1/2b) and admin/seed/migration (`postgres`) carry no `aal` JWT and MUST remain able to downgrade; the aal2 self-service disable (Slice-2 invariant 2a) passes via the aal2 check directly. **A trigger is REQUIRED (not an RLS `WITH CHECK`)**: `WITH CHECK` sees only NEW, never the OLD→NEW transition, so it cannot distinguish "downgrade from totp" from "already `none`, editing an unrelated column." **Posture:** `SECURITY INVOKER`, reads only OLD/NEW/`current_user`/`auth.jwt()` (no table read → no recursion with the `user_settings` RLS it guards), `set search_path=''` — **NOT a DEFINER allowlist entry; allowlist stays 3.** No DELETE vector (024 grants authenticated no DELETE + no DELETE policy; the only DELETE is the `auth.users` cascade under `postgres`); `ON CONFLICT DO UPDATE` upserts fire BEFORE UPDATE triggers, so the upsert-downgrade vector is covered. *(Note — a considered refinement of the literal BLOCK spec: the `authenticated`-tier scoping was added by the Architect so the guard is consistent-by-construction with the ratified Slice-2 server-side-downgrade invariants rather than blocking them; flagged for Sec re-review.)*

7. **V1 `mfa_policy` stored-domain tightening — defer `'passkey'` (F/CTO-ratified 2026-07-21).** `024` shipped `check (mfa_policy in ('none','totp','passkey'))`; `025` PART 3 tightens the **stored** domain to `('none','totp')` (drop/re-add the `user_settings_mfa_policy_check` constraint). Rationale: the totp-vs-passkey distinction is unused for V1 enforcement (aal2 is factor-agnostic — the backstop gates on `aal`, not factor type); the legitimate app only offers `none|totp` until Auth-6; and `'passkey'` being a *legal* value was the ONLY thing that made an attacker's aal1 lateral `totp→passkey` flip possible. Tightening makes that flip a **schema-level `23514` rejection** (empirically confirmed) — the concern vanishes *below* the guard rather than being handled by it. **Best-of-both:** the stored value can't be `'passkey'` in V1 (CHECK), yet the `025` backstop clause AND the MB-1 guard both keep referencing the full `{'totp','passkey'}` set, so Auth-6/SELF-289 re-adds `'passkey'` with a one-line additive CHECK widen and **zero change to the enforcement machinery** (ADR-022 additive — NOT a one-way door). Safe on greenfield (no existing `'passkey'` row can exist — 024 defaults `'none'`, no app/seed/migration writes it). *(This reverses the design-spec §2.3 earlier "include passkey now" lean → the strict-minimal option, on F/CTO's ruling.)* Ledgers flat (a CHECK tighten authors no function/RLS/reference-column): §10 stays 3, DEFINER stays 3, Decision-3 unchanged.

**Isolation invariant (SELF-291 AC#6).** Tenant isolation = the universal RLS predicate (`users_id = auth.uid()` or its rd_access/wr_access-JOIN equivalent), enforced on every table INDEPENDENT of MFA. The aal2 conjunct is ANDed with (never replaces) the pre-existing tenant predicate, so cross-tenant access still fails closed at every aal. A user's `mfa_policy` bounds only THEIR OWN step-up risk and can never weaken another tenant's fence. MFA strength ⟂ tenant isolation.

**Alternatives considered.** (a) INVOKER helper — rejected (per-row; `set search_path=''` defeats inlining; a function to maintain). (b) DEFINER helper — rejected (allowlist 3→4, Sec-gated, still per-row, bypasses an RLS read we want scoped). (c) app-layer-only enforcement (the Auth-3 §3 defer) — rejected for Auth-3b: it enforces nothing on the direct PostgREST surface (Sec's C2 gate). (d) reads-only scope (AC-literal) — rejected in favor of reads+writes (closes the destructive-write half). (e) blanket `aal2` — rejected (locks out `none` users). (f) an on-signup DEFINER provisioning trigger to guarantee the row exists — rejected already at `024` (D3 lazy provisioning); the COALESCE form makes a guaranteed row unnecessary.

**§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate the numbered list; Decision 4 read VERBATIM before drafting).** `025` introduces ZERO catalogued §10 instances; the ledger stays at **3** (RT-22 first / RT-26 second / RT-27 third — the count moved 2→3 at the ADR-027 amendment (hh) / SELF-212 flip, 2026-07-19). Adding an aal-claim RLS predicate touches NONE of the three: (i) numbering unchanged — RT-22 / RT-26 / RT-27; (ii) layer-attribution unchanged — no PDF-worker infra-credential surface (RT-22), no `SUPABASE_SERVICE_ROLE_KEY` code-layer surface (RT-26 — this is a DB-RLS-predicate change under the `authenticated` tier; service_role is neither granted nor referenced), no app→worker credential-admission network surface (RT-27); (iii) Decision 4 linked, not restated. **DEFINER allowlist stays 3** (the MB-1 guard, Decision 6, is a `SECURITY INVOKER` trigger fn — reads no table, not a DEFINER entry). **Decision-3 family unchanged** (`025` adds no reference column — it only ANDs a predicate + a guard trigger; the inline subselect reads `user_settings` on the tenant anchor `users_id = auth.uid()`, an own-row read). *(Drift-catch note: the SELF-291 memo, the design-spec draft, and the build brief all carried a stale "§10 ledger = 2"; the pre-draft verbatim read of Decision 4 caught the count as 3 and corrected it here + in the `025` header before merge.)*

**Slice boundary.** This ADR + `025` (backstop + MB-1 guard) are **Slice 1** (the enforcement unit: backstop + guard + the enrollment/step-up/reconciliation app flow + QA aal1/aal2 battery — all ship together so enrollment never precedes enforcement). **Slice 2** (SELF-291 recovery codes — a `pfin.mfa_recovery_code` store + redemption; absorbs SELF-288's recovery-codes portion) is a same-milestone follow-slice landing before TOTP GA.

**Slice-2 recovery invariants — LOCKED as design constraints (F/CTO-ratified 2026-07-21; NOT built here).**
1. `mfa_policy` downgrade + GoTrue factor-removal are **server-side (`service_role`) only** — EXCEPT the normal aal2 self-service path (2a). *(The MB-1 guard's `authenticated`-tier scoping already permits `service_role` server-side downgrades directly at the DB layer — Decision 6.)*
2. A downgrade/factor-removal is permitted when **EITHER (2a)** the session is already **aal2** (the user does it themselves — standard GoTrue unenroll-at-aal2; the Decision 6 guard allows this directly; **no server process, no backup code**), **OR (2b)** a **verified one-time backup code** is presented (the lost-phone path, executed server-side). **Never** on a bare aal1 session with neither.
3. **Notify the account owner (email) on every MFA change** — disable, factor removal, new enrollment (defense-in-depth against a chaos actor: even if a gate held, the real user finds out fast).

**Consequence:** (2b) pre-loads the design-spec §9 conditional-lock #4 toward the **`service_role` fallback (Opt ii / an ADR-016 amendment)** for the **backup-code path specifically**; **CV-R1** (can a user self-remove a *verified* factor at aal1?) remains the open Slice-2 build-time capability-verify **only for the (2b) path** — the (2a) aal2 self-service disable is standard GoTrue and needs no CV-R1. Flagged, not pre-committed.

**One-way-door status.** NOT a one-way door — the clause is additive to and removable from each policy with no data migration either direction; a posture/timing call, not a schema lock.

**Cross-references.** [ADR-011](#adr-011) Decision 4 (§10 ledger — unchanged) / Decision 9 (DEFINER allowlist — stays 3) / Decision 3 (FK-bypass family — unchanged) / [Lock 11](#adr-011) (SECURITY INVOKER read-composition — the backstop clause authors no function; the MB-1 guard, Decision 6, is the one SECURITY INVOKER trigger fn, consistent with the INVOKER default) · [ADR-024](#adr-024) (`user_settings` / `mfa_policy` substrate this enforces) · SELF-286 / Auth-3 (`024` substrate; the deferred enforcement now built) · SELF-289 (passkey — rides the identical clause) · SELF-288 (recovery-codes portion absorbed into Slice 2) · `docs/SECURITY/index.html` §4.5 (the aal1/aal2 QA battery dimension; the RT-class posture entry AC#5) · design spec `temp/auth-3b-design-spec.md`.

---

## ADR-028 — Plaid Link CDN forced-exception to the no-third-party-fetch convention + per-route CSP allowlist (SELF-212)

**Date:** 2026-07-19 · **Status:** Accepted (F/CTO-ratified 2026-07-19; Sec CSP-entry review clean) · **Phase:** 6

**Context.** The mosko-fintech convention (ADR-009 Decision 5 sub-decision 3; CLAUDE.md "no CDN" for `docs/_assets/`) is **no third-party fetch at view time** — vendored assets only (e.g. `mermaid.min.js` is vendored, "matches mosko-fintech's fintech security posture"). SELF-212's Plaid Link onboarding introduces the first app-runtime surface where this convention **cannot** be honored: **Plaid Link mandates loading its client from `https://cdn.plaid.com`** (`https://cdn.plaid.com/link/v2/stable/link-initialize.js`). Plaid does not support self-hosting/vendoring the Link initializer — its ToS + integrity model require the live CDN artifact (out-of-band security/compatibility updates + the institution-OAuth handshake). This is **distinct from Mermaid**, which *could* be vendored (pure render library, no live dependency) so the project chose to; Plaid Link *cannot* — the exception is **forced by the vendor, not a convenience preference.**

**Decision.** Accept a **scoped, forced exception** to the no-third-party-fetch convention for `cdn.plaid.com`, loaded ONLY on the Plaid Link onboarding surface, **gated by a per-route Content-Security-Policy allowlist** so every other third-party origin stays denied by default. Sec's blessed **minimal** directive set (verified against live Plaid docs; supersedes the earlier floated over-broad `*.plaid.com` wildcard, REJECTED):

```
script-src      'self' 'nonce-<per-response>' https://cdn.plaid.com/link/v2/stable/link-initialize.js
style-src       'self' 'nonce-<per-response>'
style-src-elem  'self' 'nonce-<per-response>'
style-src-attr  'unsafe-inline'                      # vendor-forced; documented residual (CSP-4)
frame-src       https://cdn.plaid.com
connect-src     'self' <plaid-host>                  # <plaid-host> tracks PLAID_ENV tier: sandbox.plaid.com (non-prod) / production.plaid.com (prod) (CSP-3)
```

`script-src` pins the **exact Link initializer path** (not the whole origin) + a per-response nonce; `connect-src` is a **single explicit Plaid host tracking the `PLAID_ENV` tier** (`sandbox.plaid.com` / `production.plaid.com`), not a wildcard.

**Acceptance conditions (Sec-bound).**
- **CSP-1 — per-route scoping MANDATORY.** Scoped to the Plaid Link onboarding route ONLY; an app-global relaxation on dashboard / financial surfaces is a **Sec veto**.
- **CSP-2 — `script-src` nonce, NOT `'unsafe-inline'`.** Realized via SvelteKit `csp: { mode: 'nonce' }` (per-response nonce).
- **CSP-3 — `connect-src` Plaid host gated on `PLAID_ENV` (Plaid API tier), NOT build mode.** *[Amended 2026-07-19 / #12, F/CTO-ratified — gating basis corrected from build-mode to `PLAID_ENV` tier.]* The single `connect-src` Plaid host tracks the live Plaid tier, resolved server-side in the CSP hook from `PLAID_ENV` (a non-secret env var; fail-safe → `sandbox.plaid.com`): `https://sandbox.plaid.com` when `PLAID_ENV !== 'production'`, `https://production.plaid.com` when `=== 'production'`. **Rationale — build-mode ≠ Plaid-tier under the V1.0 posture:** V1.0 runs the Plaid *sandbox* tier on a *production* build (`PLAID_ENV=sandbox` default; production tier post-SELF-212, F/CTO-gated per `api/CLAUDE.md` / `workers/CLAUDE.md`). Gating on build mode would emit only `production.plaid.com` on a V1.0 prod build → CSP-block sandbox Link's connection → broken onboarding; gating on `PLAID_ENV` keeps the host correct across the sandbox→production tier flip.
- **CSP-4 — `style-src-attr 'unsafe-inline'` documented as a vendor-forced residual.** Plaid Link requires inline style attributes; scoped to `style-src-attr` only (`style-src`/`style-src-elem` stay nonce-gated).

**Alternatives considered.** (a) Vendor/self-host the Link initializer — REJECTED (unsupported + ToS-restricted; breaks Link's OAuth handshake + out-of-band security updates). (b) No CSP, just load the script — REJECTED (abandons defense-in-depth; the CSP allowlist keeps every non-Plaid origin denied). (c) Server-side proxy of Link — REJECTED (Link is a browser drop-in managing the institution OAuth redirect in-browser; not a supported integration mode).

**§10 / ledger impact.** **§10 catalogued ledger UNCHANGED by ADR-028** — the Plaid CDN/CSP is a **frontend browser-fetch surface**, not a §10 privileged-context/credential-admission instance; it touches neither RT-22 nor RT-26 nor RT-27, and triggers no Decision-4 3-axis cross-check. **RT-28 (MEDIUM, normal RT catalog entry — NOT §10-catalogued):** Sec elects a new RT catalog entry for the CSP test hook (per-route CSP present + correctly scoped + nonce-mode; QA-owned); RT-28 is a standard RT-catalog surface distinct from the §10 catalogued-instance ledger and does not move the §10 count. DEFINER / Decision-3 untouched (frontend-only).

**Cross-references.** ADR-009 Decision 5 sub-decision 3 (the no-third-party-fetch convention this scopes an exception to) · [ADR-027](#adr-027) (s) (worker-owns-exchange — the Plaid *secret* stays worker-side; Link in the browser handles only the public-token flow, never the secret) + (hh) (the SELF-212 app→worker handoff; the browser-side Link surface feeds the `public_token` into the (hh) relay) · SECURITY §4.2 (external-API posture — Sec adds a Plaid-Link browser-fetch/CSP posture bullet) + §4.5 (RT-28 row).

---

## ADR-027 — Data-aggregation provider strategy: build a provider-agnostic pluggable ingest abstraction (not single-Plaid, not rent-Quiltt); provider SELECTION deferred to empirical test

**Date:** 2026-07-08
**Status:** **Accepted.** F/CTO ratified the pivot + the holdings landing target (Option B — new `pfin.asset`) on 2026-07-08; Sec joint-review **GREEN** (AMBER→GREEN 2026-07-08 — retention-limb carve-out added, see Component (2) + Sec gate).
**Phase:** Phase 6 Build Loop (aggregator-strategy pivot; gates the Onboarding/Plaid + SELF-200 track). Authors **no migration and no schema change** — architecture-shape lock only.
**Approved by:** F/CTO ratified 2026-07-08 — the **pivot** (build the provider-agnostic pluggable abstraction) + the **holdings landing target** (Option B: new purpose-built `pfin.asset` at `015`; `holdings_checkpoint` untouched). Sec joint-review GREEN 2026-07-08. Still OPEN by design: OWD-1 interface contract, OWD-2 map-straight-in-vs-raw-staging + `pfin.asset` column shape/mutability, and provider selection (downstream gate i).
**Pattern:** Material architectural pivot with one-way-door aspects. Longer than the ADR-024/025/026 short pattern because it (a) reverses a prior scoped direction (SELF-197 Plaid-Link-specific) and (b) carries two one-way-door surfaces needing named options. Provider selection is **explicitly OPEN** — a named downstream gate, not part of this lock.

---

### Decision — build a provider-agnostic, pluggable ingest abstraction ourselves

V1 sources financial data through **one internal ingest interface** that routes each institution to whichever provider serves it best, behind a shared per-provider adapter contract, with **CSV/OFX import + manual entry (SELF-201, shipped) as first-class providers** — not as fallbacks bolted onto a Plaid-shaped core. We **build the thin abstraction ourselves + plug in cheap providers**, rather than (a) rent a multi-aggregator SaaS or (b) bet the core on a single Plaid-specific OAuth integration.

**This ADR locks the ARCHITECTURE (the abstraction shape). It does NOT lock which concrete providers win** — see "Downstream gates" §(i). The F/CTO chose to author this ADR *before* the empirical provider tests complete, so provider selection is sequenced after this lock, not inside it.

**Rationale — why no single aggregator suffices (the forcing function).** Empirical testing against F/CTO's real accounts (`temp/simplefin-test.mjs`) + research (`temp/aggregator-strategy-memo.md`) established that **no general aggregator reliably returns complete Fidelity *transactions***. Fidelity ended screen-scraper access 2023-10-01 and routes consumer data through Akoya; Plaid and MX are not Akoya partners (blocked/degraded path); even the sanctioned Akoya path (Finicity/Yodlee) has per-account-type transaction gaps. Empirically SimpleFIN/MX returned Fidelity **holdings + balances cleanly across all 5 accounts** but **transactions on only 1 of 5** (known ~55-day activity absent, no error surfaced). **This is a Fidelity-exposure limitation, not a provider bug** — so no single vendor choice fixes it; the architecture must assume per-institution heterogeneity and a guaranteed-complete manual/import path.

**Rationale — why build-thin beats rent-Quiltt at this scale.** Quiltt (multi-aggregator abstraction as a service) is $100/mo (1 aggregator) → $500/mo (multi-aggregator routing), and its Akoya path inherits the same Fidelity transaction gaps. The recommended cheap mix — SnapTrade (free, 1 user) + SimpleFIN ($1.50/mo) or Plaid + CSV/OFX import + manual — is **≈ $1.50/mo**. At single-user / 2–3-provider scale, we are building the ingest normalization regardless, so the SaaS abstraction layer buys nothing but recurring cost and a vendor dependency on the exact coverage gap we can't accept. Quiltt + Yodlee/Finicity (enterprise, $1K–$50K+/mo) are ruled out on cost.

**Rationale — why manual/import must be first-class.** Fidelity's own export (CSV always; QFX/OFX most account types) is the **only guaranteed-complete transaction source**. If import/manual are afterthoughts, the app has no reliable path for its largest real account. Making them peer providers under the same interface means the routing table, dedup, and the classification flow (Unsorted / SELF-200) treat an imported transaction identically to an API-fetched one.

---

### One-way-door surfaces (F/CTO ratify required)

Two surfaces are one-way doors; both get named options below. **Neither is resolved to code by this ADR** — this ADR commits to the *architecture* and flags the shapes for slow decision.

- **OWD-1 (SOFT / code-layer) — the per-provider adapter interface contract.** The method signatures each adapter satisfies + the normalized DTO types they return. Reversible with effort (refactor across all adapters + call sites), **no data migration** to change → soft. Once ≥2 adapters + the ingest caller depend on it, changing it is a multi-file refactor.
- **OWD-2 (HARDER / data-layer) — the normalized internal ingest shape + its landing tables.** How provider `holdings[]` / `transactions[]` map into the persisted pfin ledger, the dedup key, and whether a raw-staging buffer exists. Reversing a persisted-shape choice after data lands requires a **data migration** → harder. This is the surface to decide slowly.

---

### Component (1) — the pluggable provider interface (OWD-1, soft one-way door)

Each provider is an **adapter** satisfying one internal contract. The contract's method surface (illustrative, not yet locked): `connect()` / credential-store (provider handshake → persist an SD-03-class credential handle), `fetchBalances()`, `fetchHoldings() → holdings[]`, `fetchTransactions(range) → transactions[]`. Manual and CSV/OFX-import are adapters too (their `connect` is a no-op / file-parse; their `fetch*` read user-entered or parsed rows). Routing is **per-institution** (a stored mapping from institution → which adapter serves it).

**Where the abstraction lives — three shapes (Architect lean: Option A):**

- **Option A (lean) — one `linked_source` table + per-provider adapter code.** A single generic table models each connected source (`provider` kind discriminator + credential handle + institution ref + sync-state), and per-provider adapter modules in code implement the shared interface. **`linked_source` is a NEW concept — no such table exists today** (the closest is `007 pfin.plaid_items`, which is Plaid-specific). *Why:* mirrors the ADR-022/025 "closed, code-coupled set → discriminator" rule (provider kinds are code-coupled — each new provider ships adapter code anyway); one table + code polymorphism is the boring, low-surface shape; `plaid_items` becomes either the Plaid adapter's private detail or is folded into `linked_source` at the `015` migration. *Cost:* the discriminator + credential-handle shape is a schema commitment (feeds OWD-2); folding vs. keeping `plaid_items` is a sub-decision.
- **Option B — per-provider tables + a thin routing layer.** Keep `plaid_items`; add `snaptrade_connection`, `simplefin_connection`, … each with its own shape; route in code. *Why:* explicit, no premature abstraction, each provider's native fields modeled faithfully. *Cost:* table sprawl (one per provider), and the "one interface" lives only in code with no data-layer expression — drift-prone as providers grow; contradicts the single-routing-table instinct.
- **Option C — two-table `linked_source` + `linked_account`.** `linked_source` = the connection/credential; `linked_account` = each institution account under a source, FK'd to `pfin.account`. *Why:* richer normalization — models the real 1-source→N-accounts fan-out (the Fidelity case: 1 connection, 5 accounts) explicitly; clean home for per-account sync-state. *Cost:* more schema up front; `linked_account → pfin.account` is a **matched-tenant FK** → a **NEW Decision-3 instance** (see ledger note); heavier first migration.

**OWD-1 flag:** the interface *contract* (signatures + DTO types) is the soft one-way door regardless of which table shape wins — lock the contract deliberately, because every adapter binds to it.

### Component (2) — per-provider credential storage (reuse `007`/`008` Vault-native pattern)

Each provider credential — SimpleFIN Access URL, SnapTrade token, Plaid access token — is an **SD-03-class credential** (`docs/SECURITY/index.html#sd-03`: "credential-class storage protection", stricter than any financial-data class because compromise yields downstream institution access). The `007`/`008` Vault-native pattern **generalizes on the STORAGE limb**: store each credential as a Supabase Vault secret (`vault.secrets`, Vault-managed authenticated encryption at rest), referenced by a `uuid` handle on the source row (the `007 pfin.plaid_items.access_token_secret_id` shape — ciphertext never on the tenant row; decrypt only via a `service_role`-only view). The originally-locked pgsodium mechanism was proven non-viable on the pinned PG-17 stack (ADR-011 Decision 8 Option-2 amendment, SELF-196); Vault-native is the confirmed pattern.

**Carve-out (Sec AMBER condition) — the retention / orphan-cleanup limb does NOT generalize by-construction.** Storage + the C3/C4/C6 fences carry over, but the credential-retention / no-orphaned-credential-material guarantee is a **bespoke `007` mechanism that must be RE-REALIZED per credential-bearing table** — it is not auto-inherited. In `007` it is the `AFTER DELETE` backstop `pfin.fn_plaid_items_cleanup_vault_secret` (`007` line 318 — **SECURITY INVOKER, allowlist +0**, `set search_path = ''`) which deletes the backing `vault.secrets` row on any Item-delete path: **cleanup-or-fail-closed → no orphaned credential BY CONSTRUCTION** (`007` lines 278–290 — any exception in an `AFTER DELETE` trigger aborts the cascade, so every deleting role yields no orphan; this closes the `auth.users` deletion-cascade orphan). It is paired with **revoke-then-delete ordering** (the `/item/remove` path reads the token via the decrypt view + revokes at Plaid BEFORE deleting the row, `007` lines 313–316) and an explicit **no-DEFINER-default posture** (`007` lines 307–311 — the GDPR/user-deletion erasure routine runs the cleanup under `service_role`; it MUST NOT reach for a DEFINER trigger, which would reintroduce the un-revocable-grant regression Sec ruled against, `007` lines 284–287). **Each per-provider credential-bearing table (`linked_source`-style or per-provider) must author its own such backstop** — INVOKER, allowlist +0 (no-DEFINER-default), cleanup-or-fail-closed on every delete path incl. the user-deletion cascade, plus its provider's revoke-then-delete ordering. This is the pattern-of-record being **carried, not auto-inherited** (RT-02 `bounded-Item-active-only` retention is the SECURITY anchor).

**This confirms, not decides:** the SELF-197 `015`-style Vault write-path wrapper is **not Plaid-specific** — it just re-aims at whichever credential the adapter presents. No new DEFINER function is implied (the `007`/`008` posture used `service_role` grants + a view, not a DEFINER fn; DEFINER allowlist stayed 3). Any new credential column on a `linked_source`-style table inherits C3/C4 (credential handle withheld from `authenticated`; decrypt view `service_role`-only) + C6 exposure-gating (ADR-023 — two-tenant RLS battery before grant), **and must re-realize its own retention / orphan-cleanup backstop per the carve-out above** (INVOKER, +0, cleanup-or-fail-closed on every delete path incl. user-deletion cascade + revoke-then-delete + no-DEFINER-default).

### Component (3) — normalized ingest mapping (OWD-2, harder one-way door)

Adapters emit normalized `holdings[]` / `transactions[]`; a mapper writes them into the pfin ledger with **dedup** (provider + provider-native id key, so re-sync and import-overlap don't double-count) and **blank-symbol description-fallback** (sweep/money-market positions with no ticker route to the Unsorted classification flow, SELF-200). Transactions land in `pfin.account_trans` — which is **immutable (`004`) + audit-class**, carries the `012` `transaction_type` discriminator, and is written today via the `013` `fn_create_manual_account` INVOKER write-composition RPC + `014` NaN CHECK. An ingest write path must respect that immutable-ledger posture (no update-in-place; corrections are new rows) and is the natural extension of the ADR-026 atomic write-composition precedent.

**[SUPERSEDED 2026-07-13 — see Amendment 1(a)/(b) below]** **Holdings landing target — RESOLVED (F/CTO ratified Option B, 2026-07-08).** Adapter-emitted `holdings[]` land in a **NEW purpose-built `pfin.asset` ingest table authored at `015`** (no `pfin.asset` table exists in `001`–`014`). **`pfin.holdings_checkpoint` (`005`) is explicitly OUT OF SCOPE as the ingest target** — it is a reconciliation-subsystem append-only audit-class table (SD-17) with the wrong semantics for a provider-sync current-holdings write: (i) its `symbol text not null` (`005` line 268) conflicts with the blank-symbol sweep/money-market fallback; (ii) it has no INSERT write path (its intended writer, the reconciliation_event fan-out trigger, is deferred to the V1.3 reconciliation-usage wave per `005` lines 128–129); and (iii) `005` **deliberately declined a `source_event_id` provenance FK to hold the cross-tenant FK-bypass family flat** (`005` lines 39–40, 56–60), which provider-source attribution would reopen. A dedicated `pfin.asset` table keeps the reconciliation audit-class semantics clean and gives the ingest path purpose-built columns (symbol nullable + description + quantity + market_value + cost_basis + purchase_price + source-attribution + provider-native-id for dedup + synced_at). The two tables stay **cleanly decoupled for V1** — no `asset`↔`holdings_checkpoint` link is in scope. **Named `015`-design sub-decisions (not pinned here):** the table name (`asset` vs `holding`) and its mutability posture (append-only snapshot vs upsert-current-state) — the latter feeds the Decision-2 audit-class question in the Sec gate.

**Where the normalized shape lives — three shapes (Architect lean: Option A for V1 simplicity, revisit B if reprocessing need appears):**

- **Option A (lean) — map straight into `pfin.account_trans` (transactions) + `pfin.asset` (holdings) with a source-attribution column + dedup key.** No staging table; adapters → DTO → mapper → the two landing tables in one path. *Why:* least schema, reuses the shipped immutable-ledger + `013` write-composition machinery for transactions and writes holdings straight into the new `pfin.asset` table; boring. *Cost:* no raw-payload audit/replay buffer — a provider-format bug is caught only after normalization; re-processing means re-fetching.
- **Option B — raw-staging table (`raw_ingest`) → transform → `pfin.account_trans` + `pfin.asset`.** Land the raw provider payload first (append-only), normalize in a second step. *Why:* reprocessability + provider-response audit trail + decouples fetch from normalize (a mapper bug is fixable without re-hitting the provider — valuable while provider coverage is in flux). *Cost:* an extra table + a transform step + its own RLS/exposure-gating; more surface for a single-user app.
- **Option C — normalized DTO in code only (no persisted intermediate), single mapper writes to `pfin.account_trans` + `pfin.asset`.** *Why:* keeps the normalized shape as a code contract (composes with OWD-1's DTO types), no third persisted shape to migrate later. *Cost:* the normalized shape is un-inspectable post-hoc; overlaps A's no-audit-buffer cost without A's simplicity of a source-attribution column.

**OWD-2 flag:** the persisted normalized shape + dedup key + the `pfin.asset` column set are the harder one-way door (reversing after data lands = data migration). The landing *target* is resolved (new `pfin.asset` at `015`, per above); the map-straight-in-vs-raw-staging choice + the `pfin.asset` column shape + its mutability posture remain to be decided slowly at the `015` design.

---

### Downstream gates named (NOT resolved here)

1. **(i) Empirical provider tests → provider-selection decision.** SnapTrade (Fidelity developer-API Activities endpoint — highest-upside untested path; gated by a Fidelity-connector application) and Plaid-PAYG (request Fidelity Investments access → `/investments/transactions/get` — reliability uncertain/in-flux) are **unproven for Fidelity transactions**. Provider selection is a separate F/CTO decision *after* these tests. This ADR's abstraction is designed to make that decision swappable, not to pre-judge it.
2. **(ii) PM §2.4/§2.5 re-scope.** PRD §2.4.1 (`docs/PRD/index.html#story-2-4-1`) currently bakes **Plaid Link** into onboarding verbatim ("`/link/token/create` … Plaid Link opens … `/item/public_token/exchange`"); §2.4.4 bakes Plaid re-auth. These need re-scoping to **per-provider connect flows** (automated-where-possible + import/manual-where-not). PM-owned; Architect consult.
3. **(iii) Sec SD-03 per-provider credential re-review.** Each new provider credential (SnapTrade token, SimpleFIN Access URL) is a new SD-03-class admission surface → Sec re-review per provider (parallel to the §4.6 V2-ship-gate per-provider-consult posture). The RT-26 `SUPABASE_SERVICE_ROLE_KEY` allowlist + the RT-02 credential-never-surfaces posture apply per provider.
4. **(iv) Migration(s) to author the `linked_source`/adapter substrate.** Next free migration number is **`015`**. Any FK from a `linked_source`-style table to a tenant-scoped row (e.g. Option C's `linked_account → pfin.account`) is a **NEW Decision-3 matched-tenant instance** authored at that migration — forward-flagged, not pre-counted here.

---

### Supersession bookkeeping

- **SELF-197 (Plaid Link + token exchange + the `015` Vault wrapper) as scoped is SUPERSEDED** — the integration shape is now the provider-abstraction, not a Plaid-specific OAuth flow. The `007`/`008` Vault credential-storage pattern + the SELF-196 capability-verify lesson **survive** (they generalize per Component (2)).
- **SELF-212 (Plaid production sales call) likely MOOT** — provider selection may not include Plaid-Investments at all; revisit after gate (i).
- **SELF-200 (auto-Unsorted classification)** stays valid and is a **consumer** of this abstraction (the blank-symbol / new-symbol fallback), unblocked once the ingest mapping (OWD-2) is designed.
- **`plaid_items` (`007`)** is not discarded — it either becomes the Plaid adapter's private storage or folds into `linked_source` at `015` (a sub-decision under Component (1)).

---

### §10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate the numbered list)

Zero catalogued §10 instances touched; ledger stays at **2** (RT-22 + RT-26). (i) numbering RT-22 first / RT-26 second — unchanged; (ii) layer-attribution — this ADR authors no code and no migration, adds no infra-credential (RT-22) or `SUPABASE_SERVICE_ROLE_KEY` code-layer allowlist (RT-26) surface; the per-provider service_role write paths, when built, are governed by RT-26 *in web-app source*, not by this ADR; (iii) Decision 4 linked, not restated. Forward-note: the `015` substrate migration + each adapter's server route will each carry their own §10 3-axis cross-check at authoring time.

### Ledgers (explicitly untouched)

This ADR authors **no migration and no schema change**, so: **SECURITY DEFINER allowlist stays 3** · **§10 catalogued-instance ledger stays 2** (RT-22 + RT-26) · **Decision-3 cross-tenant FK-bypass family stays 5** (canonical). Migrations `001`–`014` live; next free number `015`. **Forward-flags for the `015` substrate (evaluated + counted at that migration — NOT pre-counted here):** (a) `pfin.asset.account_id → pfin.account` is a **SOLE tenant anchor → NOT a Decision-3 instance** (same reasoning as `holdings_checkpoint.account_id` / `account_trans.account_id` — no second anchor to mismatch); (b) BUT a `pfin.asset.sub_cat_id → pfin.user_taxonomy` (allocation tagging) or a `pfin.asset.linked_source_id → linked_source` FK — both sides per-user — WOULD be a **NEW matched-tenant Decision-3 instance**; (c) any FK in the `linked_source`/`linked_account` substrate that references a tenant-scoped row is likewise a **NEW Decision-3 instance**. All forward-flagged, none pre-counted.

### Sec gate

**joint-review-mandatory** — external-API + credential-class (SD-03) + money-ingest surface, plus the OWD-1 interface-contract one-way door. Triggers: (1) SD-03 per-provider credential storage generalization (Component 2); (2) the provider-abstraction as the new canonical external-API ingest surface (supersedes the Plaid-specific §4.2 framing); (3) forward — the **`015` `pfin.asset` migration**: **C6 exposure-gating is mandatory** ([ADR-023](#adr-023) — the SECURITY §4.5 two-tenant RLS battery must prove cross-tenant read+write fail closed **before `pfin.asset` is granted**, since it is internet-facing the moment it is exposed under the Data API), plus a new-SD-class assignment (holdings-ingest data), plus — **conditionally** — a [Decision 2](#adr-011) immutable-audit-class trigger **IF and only if** the `015` design gives `pfin.asset` an append-only/immutable posture (the mutability sub-decision); an upsert-current-state posture does not trigger Decision 2; (4) forward — each `015`+ adapter migration re-triggers joint-review (new DEFINER fn? new matched-tenant FK per the Decision-3 forward-flags above? new credential column?); (5) forward — the **per-credential-table retention / orphan-cleanup obligation** (Sec AMBER carry-over, Component 2 carve-out): every per-provider credential-bearing table must ship its own `AFTER DELETE` cleanup-or-fail-closed backstop (INVOKER, allowlist +0, no-DEFINER-default) covering **every delete path incl. the `auth.users` user-deletion cascade** + its provider's revoke-then-delete ordering — verified at the credential table's joint-review, not assumed inherited from `007`. **NOT a new DEFINER function** and **no ledger change** in this ADR (architecture-shape only). Sec joint-review returned **GREEN** 2026-07-08 (AMBER→GREEN once the retention-limb carve-out landed).

### Related

- `temp/aggregator-strategy-memo.md` — the research memo (provider landscape + pricing + empirical results + recommended architecture + open tests) this ADR ratifies.
- [ADR-011](#adr-011) Decision 1 (privileged-context-write — the service_role write transport) / Decision 8 + [Lock 4 Vault-native amendment](#adr-011) (SELF-196 — the credential-storage mechanism that generalizes) / [Decision 3](#adr-011) (cross-tenant FK-bypass family — forward-flag for the substrate FKs) / [Lock 11](#adr-011) + [ADR-026](#adr-026) (INVOKER write-composition — the ingest-write precedent).
- [ADR-023](#adr-023) (pfin API exposure + **C6 exposure-gating** — binds every new substrate table) + [ADR-016](#adr-016) (RT-26 allowlist — binds each provider's service_role route).
- [ADR-025](#adr-025) / [ADR-026](#adr-026) (SELF-201 manual-account create path — **manual entry is a shipped first-class provider**, the universal fallback).
- `007_plaid_platform_schema.sql` + `008_pfin_service_role_grants.sql` (the Vault-native per-provider credential pattern) · `005_reconciliation_event_family.sql` (`pfin.holdings_checkpoint` — the reconciliation audit substrate, explicitly **NOT** the ingest target; holdings land in the new `pfin.asset` at `015` per Option B).
- PRD [§2.4.1](docs/PRD/index.html#story-2-4-1) / [§2.4.4](docs/PRD/index.html#story-2-4-4) / [§2.5](docs/PRD/index.html#sec-2-5) — the Plaid-Link-baked stories PM re-scopes (gate ii).
- `docs/SECURITY/index.html#sd-03` (credential class) + `#rt-02` (token never surfaces) + `#rt-26` (service_role allowlist) — the Sec surfaces each provider re-review touches.
- SUPERSEDES the SELF-197 Plaid-Link-specific scope.

---

### Under-specified / needs an F/CTO or PM decision before the abstraction can be designed further

1. **[SUPERSEDED 2026-07-13 — see Amendment 1(a)/(b) below]** **Holdings landing table — RESOLVED (F/CTO ratified Option B, 2026-07-08).** A **new purpose-built `pfin.asset` ingest table at `015`**; `pfin.holdings_checkpoint` (`005`) stays the untouched reconciliation audit substrate (out of scope as the ingest target — see Component (3)). Cleanly decoupled for V1 (no `asset`↔`holdings_checkpoint` link). Residual `015`-design sub-decisions (name `asset` vs `holding`; append-snapshot vs upsert-current mutability posture) are named, not blocking this ADR.
2. **Provider selection (F/CTO, after gate i).** SnapTrade and Plaid-PAYG are unproven for Fidelity transactions. The abstraction is swappable by design, but the *first* concrete provider set to build adapters for needs a call once the empirical tests run.
3. **`plaid_items` disposition (F/CTO + Architect).** Fold `007 plaid_items` into `linked_source`, or keep it as the Plaid adapter's private table? Sub-decision under Component (1) Option A-vs-B.
4. **§2.4/§2.5 re-scope ownership + timing (PM).** The Plaid-Link-baked PRD stories are a PM re-scope; sequence it relative to the empirical tests (re-scope now to "per-provider connect" generically, or after providers are chosen?).
5. **Import scope for V1 (PM).** CSV/OFX import is named first-class here, but its V1 shape (which formats, single-account vs. bulk, dedup-against-existing) isn't specified — a PM V1/V2 boundary call (note §2.4.2 already defers *bulk import of accounts* to V2; per-account transaction import is a distinct question).

---

### Amendment (2026-07-13 / Phase 6 Build Loop, `015`–`021` ingest/valuation substrate)

The `015` design grew from a holdings-landing table into the full V1 holdings/valuation/allocation/net-worth data model (design-for-ratify `temp/015-ingest-substrate-design.md`, §16 R-1…R-19 ratified 2026-07-13; Architect spec `temp/015-architect-design-spec.md`; Sec GREEN `temp/015-sec-review.md`). This amendment supersedes the parts below; the pivot decision + provider-abstraction + Component (2) credential pattern all stand. (Authoring note: this is a single atomic amendment block covering the whole `015`–`021` substrate; migration `015` authors surfaces (a)/(e)/(g) [the `linked_source` fold + Decision-3 #6] — the valuation/holdings surfaces (b)/(c)/(c-cash)/(d) describe later migrations `016`–`019` and ride this block per the ADR-027 §13 schema+valuation amendment design.)

**(a) `pfin.asset` RE-SCOPED — holdings-landing table → UNIVERSAL asset registry (R-1/R-9/R-16).** `pfin.asset` (`016`) is now one row per distinct asset of EVERY type — securities, ETFs, funds, bonds, real estate, vehicles, metals, collectibles, crypto, **currency** — carrying identity + an `asset_type` CHECK + a **`pricing_source`** discriminator (`market_feed`/`spot_feed`/`fx_feed`/`manual_valuation`; derivatives + `depreciation_model` = V2). G1 hybrid: nullable `users_id` (`NULL` = global/market rows; `=uuid` = per-user physical rows), partial-uniques `unique(symbol) where users_id is null` + `unique(users_id, name) where users_id is not null`. It holds **definition + pricing, NOT position**.

**(b) Holdings DERIVED, not landed — SUPERSEDES Component (3)'s "holdings_checkpoint out of scope" (R-2).** Provider `holdings[]` snapshots land in **`pfin.holdings_checkpoint` (`005`)** — `018` activates its service_role provider-write-path (append-only preserved; `symbol` NOT NULL relaxed for blank-symbol; `security_id` FK deferred V1.3). Holdings (quantity) are **derived**: V1 = ledger summation (`fn_holdings_as_of`, complete/backfilled) or the current `holdings_checkpoint` snapshot; V1.3 = Lock 9 cost-basis cascade (incomplete history). `pfin.asset` is therefore NOT the holdings-ingest table Component (3) described — that framing is superseded.

**(c) VALUATION layer added (R-4/R-5).** `value(asset, date) = quantity × price`, computed-never-stored via the Lock 11-named **`fn_compute_nav`** (INVOKER read-composition; `005` deferred it pending `eod_price`). **`pfin.eod_price` (the `005`-named prerequisite) lands partially in V1** (`019`): physical assets have no provider snapshot so their value can ONLY come from `eod_price` manual valuations (forces the manual leg into V1); FMP via `pfin_back_etl` makes the market leg cheap. Sparse-price **LOCF** — latest `price_date ≤ as_of` per asset. Currencies are global `asset_type='currency'` rows whose `eod_price` = the FX rate to USD-base (USD ≡ 1.00), reusing the same `qty × price` machinery (R-16). **`eod_price` is MUTABLE (OWD-E, F/CTO-ratified 2026-07-13):** manual valuations are revisable estimates (overlay-side), NOT audit-ledger (that role is `account_trans`/`004`); point-in-time reproducibility, if ever needed, lands as a net-worth SNAPSHOT (`monthly_report_account_snapshot` shape), not as append-only pricing. **Sec AMBER #4 fence binds at authoring** (`019`): authenticated UPDATE WITH CHECK own-only (`users_id = auth.uid()` on the referenced asset) + an `asset_id`-re-pointing fence (a manual row cannot be re-aimed at another asset); DELETE own-only. `market_feed`/`fx_feed`/`spot_feed` global rows stay service_role-written.

**(c-cash) UNIFORM cash-as-asset valuation (F/CTO-ratified 2026-07-13).** CASH is the global USD `asset_type='currency'` entry (NO separate `'cash'` type; `'cash'` dropped from the R-9 vocab); cash categorizes as "Cash" uniformly via a `020` junction row on the currency-asset. **Cash VALUE = Σ(`account_trans.amount`) [running balance], NOT qty×price:** pure-cash txns carry `quantity=0, security_id=NULL` (`017` `CHECK (quantity=0 OR security_id IS NOT NULL)`); a securities BUY carries BOTH `amount=−cash` and `quantity=+shares`. So `net_worth = Σ(amount)×fx [cash] + Σ(qty×price×fx)(security_id IS NOT NULL) [securities] − liabilities`. §7 dual-path: complete/backfilled → `Σ(amount)`; aggregator/incomplete → the new `pfin.account_balance_checkpoint` snapshot (the cash analog of `holdings_checkpoint`, `018`). `account.sub_cat_id` (`012`) is DORMANT under this uniform model (no V1 consumer; leave-dormant, NOT retired — D3 stays 5→10).

**(d) BACKFILL + the V1/V1.3 net-worth boundary (R-3/R-8).** Spreadsheet → asset-registry seed + `account_trans` import via the import adapter; per-account **`account.backfill_cutover_date`** arbitrates import (`≤`) vs aggregator (`>`), manual orthogonal (`source_provider='manual'`). **V1 net worth = CURRENT (all asset types) + AS-OF-DATE (backfilled accounts).** **V1.3 = cost-basis lots + realized-gains (Lock 9 cascade) + cross-source reconciliation + incomplete-history + derivatives contract math.**

**(e) R-14 credential store FOLD — resolves Component (1)'s plaid_items sub-decision + Under-specified item 3 (= FOLD).** The provider-agnostic credential store is **`pfin.linked_source`** (`015`), which **absorbs `007 plaid_items`** via drop-and-recreate (empty table; OWD-C in the spec). Plaid is one `provider` value. Detail + the preserved `007` Vault properties are in the ADR-011 Lock 4 amendment (Amendment 2). Supersedes the bookkeeping line *"`plaid_items` … either becomes the Plaid adapter's private storage or folds into `linked_source`"* → **it folds.**

**(f) OWD-1 / OWD-2 resolved.** OWD-1 (adapter contract) → **R-13** provider-agnostic Holding/Transaction DTO union ratified (soft, refine at build). OWD-2 (normalized ingest shape) → **Option A map-straight-in** (no raw-staging): adapters → DTO → `fn_ingest_transactions` (R-15, INVOKER authenticated bulk RPC) → immutable `account_trans` + registry/`holdings_checkpoint`; the `pfin.asset` column set is the universal-registry shape above; `account_trans` stays immutable, `holdings_checkpoint` append-only, the registry mutable-current.

**(g) Ledgers — Decision-3 family 5 → 10 (SUPERSEDES §Ledgers "stays 5").** The `015`–`021` batch adds +5 (matched-tenant ×3: `account.linked_source_id` [#6, `015`], `user_asset_category.sub_cat_id` [#8, `020`], `account_trans_annotation.sub_cat_id` [#10, `021`]; novel global-OR-matched-tenant fence ×2 sites, ONE Sec-design: `account_trans.security_id` [#7, `017`], `user_asset_category.asset_id` [#9, `020`]). `eod_price.asset_id` = sole-anchor (Decision-3-ADJACENT write-authz fence, reviewed, NOT counted). `holdings_checkpoint.security_id` deferred → 11 at V1.3. **DEFINER allowlist stays 3; §10 ledger stays 2.** Per-migration Decision-3 evaluation + Sec joint-review at each of `015`–`021` (`015` lands #6).

---

### Amendment (2026-07-15 / `019` — FMP-free valuation model; NARROWS R-4). F/CTO-ratified; Sec joint-review-mandatory (this amendment + the fn_compute_nav valuation semantics + the eod_price privileged-write posture note).

**Supersedes** the parts of (c) ("FMP via `pfin_back_etl` makes the market leg cheap") + (d) ("V1 net worth = CURRENT (all asset types) + AS-OF-DATE (backfilled accounts)") + **R-4** as originally ratified ("eod_price + FMP historical backfill in V1"). Everything else in (a)–(g) stands (the universal registry, the MUTABLE eod_price / OWD-E, the Sec AMBER #4 write-authz fence, the Decision-3 5→10 family, the `015`–`018` migrations already on main).

**(h) FMP FULLY OUT OF V1 — R-4 narrowed.** Rationale (F/CTO): FMP prices only **equities** — bonds/CDs/options/futures/crypto have no clean FMP feed, but the aggregator **`holdings_checkpoint.balance`** (per-position provider valuation, `005`) covers **ALL asset classes**; and F/CTO's spreadsheets already hold monthly historical prices, so historical valuation is a **seed script, not an ETL job**. FMP therefore buys nothing in V1. **V1 `eod_price` population = manual valuations (authenticated OWD-E) + F/CTO's historical-sheet seed only.** The `eod_price` service_role global-write GRANT **stays DEFINED** (a re-runnable seed/backfill may use it; forward-compat) but is **FMP-UNUSED in V1**. **FMP historical backfill + automated market/fx pricing → V2 "Stock Research."**

**(i) VALUATION PRECEDENCE = Rule A (time-aware per-leg COALESCE), realized in `019` `fn_compute_nav`.** Per account, per leg: the **provider snapshot (LOCF ≤ as_of) WINS when one exists; else the ledger compute.** SECURITY leg = `COALESCE(Σ holdings_checkpoint.balance [latest ≤ as_of per symbol] × fx, Σ fn_holdings_as_of qty × eod_price_LOCF × fx)`; CASH leg = `COALESCE(account_balance_checkpoint.balance [latest ≤ as_of], Σ(amount ≤ as_of)) × fx`. Never double-counts (COALESCE selects one source per leg); a manual/import account never has snapshots → always ledger; a historical as_of before an aggregator account connected has no snapshot ≤ as_of → falls to ledger. `fn_compute_nav` **does NOT read `linked_source_id` / `backfill_cutover_date`** — Rule A supersedes the earlier per-account discriminator; those columns govern **ingest dedup** (import `≤` cutover / aggregator `>`), not valuation. `fn_holdings_as_of` is re-grained to `(account_id, security_id, quantity)` to support the per-account choice. **Liabilities are uniform R-7 signed** (owed = negative; NO `account_type` branch — provider checkpoint balances are R-7-normalized at ingest, an adapter contract). All valuation reads are Lock 11 SECURITY INVOKER → caller-RLS-scoped.

**(j) Q3 — same security across multiple aggregator accounts + symbol-vs-asset_id resolution: NO conflict, NONE forced in V1.** F/CTO's case: AAPL held in both a Fidelity and a Schwab account, each provider implying a value/qty. Under Rule A, **each aggregator account self-values by its OWN per-account `holdings_checkpoint.balance`** — the two accounts contribute **two balances, SUMMED** (fn_compute_nav's SECURITY leg is per-account, then summed). Aggregator holdings **never route through `eod_price`**, so no shared/derived price exists and the "which implied price wins" conflict **does not arise in V1**. This is also *more accurate*: each provider snapshots at a different instant, so summing the two real balances is exact, whereas unifying to one derived price would mis-value one account. The two valuation paths are **disjoint per COALESCE branch**: aggregator = balance-direct (`holdings_checkpoint.balance`, symbol-keyed, provider-valued, never touches `eod_price`/`asset_id`); ledger = `account_trans.security_id → asset_id → eod_price` (asset_id-keyed, never touches `holdings_checkpoint.symbol`). **`eod_price` in V1 is written ONLY by manual/seed (non-provider)** → at most one price per `(asset, date, source)` and no provider contention; historical pre-connection NAV (ledger branch) uses the seeded price, which is **one canonical price per (asset, date) shared across all accounts** holding that asset. **No provider→`eod_price` cross-fill/derivation in V1.** `holdings_checkpoint.security_id` FK stays **deferred to V1.3** (→ Decision-3 11 then). **V1.x follow-up (NOT V1):** auto-cross-fill (borrow a provider's implied price to value a same-security MANUAL holding) is the only place a multi-provider tiebreak (latest-snapshot / provider-priority) is needed; the `unique(asset_id, price_date, source)` grain already accommodates per-provider implied-price rows, requiring only an additive `source`-vocab entry when built (ADR-022 additive). **One precise nuance recorded (Architect sanity-check of the above — not a V1 hole):** the ledger-branch LOCF subquery selects the latest `price_date ≤ as_of` **source-agnostically** (no source filter/priority); V1 is safe because a given ledger-branch asset has effectively ONE price source in practice (physical = `manual_valuation`; backfilled equity = seeded), so no same-date cross-source collision occurs — and the source-priority tiebreak is exactly the deferred V1.x auto-cross-fill work, not a V1 gap.

**(k) `eod_price.price` SEMANTIC = AS-TRADED (non-split-adjusted) close** (fold-in of the split-adjustment one-way-door, F/CTO-ratified 2026-07-15). Fixed-forever, never retroactively recomputed → matches the as-traded immutable `account_trans` quantity ledger (point-in-time NAV = as-traded qty × as-traded price). V1 manual/seed prices are **as-entered = as-traded by construction**. Split-adjusted series + the FMP `non-split-adjusted` endpoint + split-as-ledger-event (a legal `account_trans` row today: `quantity=+Δ, amount=0, security_id set` — purely additive, does NOT touch `017`) are **deferred to V2 Stock Research**; adjusted close is derivable then from as-traded + split events, so it is never stored (storing it would make a historical price mutate on refetch, breaking point-in-time reproducibility).

**(l) V1 net-worth boundary — narrowed.** V1 = **CURRENT net worth** (provider balance for aggregator accounts, all asset classes + manual/ledger for non-aggregator) + **as-of-date to the depth the seed/manual `eod_price` + ledger history supports**. Automated market-price history → V2. **Direct cost of FMP-out (on record):** a manual/import/backfilled security with no `eod_price` row contributes **0** ("needs valuation" — visible, never a silent failure) until manually priced or seeded; aggregator securities are covered by `holdings_checkpoint.balance`.

**Ledgers UNCHANGED — no new tables/FKs/elevated functions:** §10 = 2 · DEFINER allowlist = 3 · Decision-3 = 7 (at `019`). This amendment is `fn_compute_nav` + `fn_holdings_as_of` bodies (CREATE OR REPLACE) + comments + this ADR — no migration file beyond `019`, no `eod_price` grain change. **Sec privileged-write posture note (for joint-review):** the `eod_price` manual-owned WITH CHECK fence constrains **authenticated only**; the superuser seed and service_role bypass RLS (trusted, Decision 1 privileged-context-write — identical posture to global market rows). Not a gap; recorded for Sec.

> **⚠️ SUPERSEDED 2026-07-15 by the "uniform roll-forward" amendment below.** The (h)–(l) FMP-free-but-Rule-A model above was itself an intermediate ratify; F/CTO subsequently ratified the uniform roll-forward model (below), which changes (i) valuation to `qty × eod_price` uniformly (no balance-direct), (j) provider→`eod_price` to CORE V1 (provider-implied population) with source-priority tiebreak CORE (not V1.x), and (h)/(l) to keep FMP out only as a *future higher-priority source* (provider-implied fills the V1 floor). Sub-point (k) as-traded semantic is reframed to "best-available price observation." FMP-OUT and the eod_price MUTABLE/OWD-E/grain decisions STAND.

### Amendment (2026-07-15 / `019` — UNIFORM ROLL-FORWARD valuation model; supersedes (h)–(k) above). F/CTO-ratified; Sec joint-review-mandatory (Decision-3 #11 fence extension + the read-composition + the source-priority logic + the provider-implied write path).

F/CTO ratified a single durable valuation model ("won't rearchitect this") that supersedes both Rule A and the FMP-free framing:

**(m) UNIFORM `qty × eod_price`.** `value = quantity × eod_price(as_of)` for EVERY account type — NO balance-direct path, NO aggregator-vs-ledger COALESCE, ONE formula (comprehensibility + future-proofing is the explicit rationale). Realized in `019` `fn_compute_nav` (rewrite).

**(n) ROLL-FORWARD quantity/balance.** `qty = latest holdings_checkpoint (per (account, security_id), ≤ as_of; the SCOPING ANCHOR) + Σ(account_trans STRICTLY AFTER that checkpoint's as_of_date, ≤ as_of)`; no checkpoint → Σ all. Same for cash (`account_balance_checkpoint` anchor + Σ later amounts). Realized in `019` `fn_holdings_as_of` (rewrite, now returns `(account_id, asset_id, quantity)`) + `fn_compute_nav`'s cash leg.

**(o) PROVIDER-IMPLIED PRICING + SOURCE-PRIORITY (CORE V1 — supersedes the (j) V1.x deferral).** `eod_price` is populated from the provider-IMPLIED price (`holdings_checkpoint.balance ÷ quantity`) + manual + future FMP/APIs. The **WORKER materialises** provider_implied rows (Backend/Worker deliverable — resolves symbol→`security_id`, auto-registers global assets, writes `eod_price(asset_id, date, 'provider_implied', balance÷qty)` via the existing `service_role` grant). When multiple sources price the same `(asset, date)`, a **source-priority heuristic** selects one — **the accuracy-upgrade path**: provider_implied is the always-available FLOOR (NOT a true EOD close — mid-day snapshot); an exact source dropped in later at higher priority upgrades every asset it covers with zero rearchitecture. **Order (ratified): `manual_valuation > exact_feed (market_feed/spot_feed/fx_feed) > provider_implied`. Selection = D-FIRST: latest `price_date ≤ as_of` wins across sources; a same-date tie is broken by source rank. HARDCODED rank** (a source has no per-value metadata → does not clear the ADR-024 promote-to-table bar; a registry, if ever, is global shared-read reference like `tax_character` → NOT Decision-3). **Vocab:** one generic `'provider_implied'` added to the `eod_price` source CHECK (additive per ADR-022; not per-provider).

**(p) SD-A1 — `holdings_checkpoint.security_id` FK UN-DEFERRED into V1.** The uniform model keys checkpoint quantity by asset, so the symbol→asset resolution the FK provides is required now (was V1.3). Realized in `019`: nullable FK → `pfin.asset` + the NOVEL global-OR-matched-tenant fence `fn_holdings_checkpoint_security_asset` (BEFORE INSERT, INVOKER, load-bearing under the service_role provider-sync path; mirrors `017`). **Decision-3 family COUNT 7 → 8; the realized instance's CANONICAL LABEL is #11 (novel-fence site 3), NOT #8** — `018`'s committed header + (g) above already pre-label `holdings_checkpoint.security_id` as "canonical 11 / deferred V1.3", and `015`/`017`/`018` forward-enumerate #8/#9/#10 as the `020`/`021` instances, so pulling this fence into V1 realizes #11 early WITHOUT renumbering any committed instance (no drift). Canonical enumeration is in `019`'s header. **Sec numbering sign-off mandatory** (D3 extension). The WORKER symbol→`security_id` resolution (auto-registration of global assets) becomes a load-bearing invariant; an unresolved symbol → `security_id` NULL → that position is unvalued (drops from NAV) until resolved.

**(q) eod_price SEMANTIC reframe (supersedes (k) as-traded framing):** `eod_price` = **"best-available price observation per (asset, date, source), source-priority-resolved"** — provider_implied rows are `balance÷qty` (an implied mid-day average, NOT a true EOD close); manual/seed/FMP rows are as-entered / as-traded. As-traded (non-split-adjusted) + split-as-ledger-event stay V2 (derivable then; never stored).

**(r) DOUBLE-COUNT EDGES → V1.3.** The strictly-after boundary leaves residual sync-lag/clock-skew edges (a txn dated ≤ checkpoint the balance doesn't yet reflect → under-count; dated > checkpoint the balance already reflects → double-count); self-corrects at the next sync for pure-aggregator. Audit-robust fix = **V1.3 reconciliation (Lock 9, txn↔checkpoint-date matching)** — documented in the `019` fn comments + here, NOT built now.

**Ledger deltas:** **Decision-3 7 → 8** (the #11 fence). **§10 stays 2** (the worker provider_implied write uses the already-allowlisted service_role provider-sync consumer + the existing `019` grant — no new RT-26 file, DB-ACL only). **DEFINER stays 3** (the new fence is INVOKER; no new DEFINER; the read fns INVOKER). **eod_price GRAIN unchanged** (OWD-A `unique(asset_id, price_date, source)` holds — `provider_implied` slots in by source; source vocab additive per ADR-022). `019` grows the `holdings_checkpoint.security_id` ALTER + fence + the two fn rewrites + the source-vocab CHECK; no migration file beyond `019`. **Credit-union thread RESOLVED** — mixed-mode (balance snapshot + rolled-forward txns) is now core. **FMP stays OUT of V1** (future higher-priority source; provider_implied is the floor). Worker provider-implied write = a downstream Backend/Worker deliverable.

### Amendment (2026-07-16 / gate (i) — provider SELECTION RESOLVED). F/CTO-ratified. Resolves the "Downstream gates §(i)" left explicitly OPEN at this ADR's authoring.

**Decision: Plaid PRIMARY + SimpleFIN FALLBACK + import/manual (SELF-201); SnapTrade DROPPED; Teller INVALIDATED.** Routing stays per-institution behind the `015 linked_source` interface (Component (1) Option A).

- **Plaid = primary** (banks + cards + **brokerages incl. Fidelity**). The round-3 production probe (2026-07-15/16, F/CTO's real accounts) cleared all four feature cells: bank/card transactions + balances (Cap One 191, Schwab checking 262/2yr, Wells) and — the round-2 Fidelity blocker now **RESOLVED** — Fidelity end-to-end: investment transactions **551** (IRA 215 / CASH 123 / HSA 28 / PORTFOLIO 185, ≈ SnapTrade's 550), holdings on all Fidelity + Schwab accounts (incl. individual bonds), + the Fidelity Visa. Best data quality (`personal_finance_category` + merchant enrichment + `investment_transaction_id`/`cancel_transaction_id` → the immutable-ledger correction model + `security_id`).
- **SimpleFIN = fallback** (banks/cards Plaid drops). Flat **$1.50/mo**; caught **Synchrony** where Plaid was transiently down. Thinner data (`mcc`-only categorization).
- **SnapTrade DROPPED.** Its round-2 rationale (Fidelity coverage Plaid couldn't do) is gone — Plaid now matches it (551 ≈ 550). Brokerage-only + **holdings endpoints return HTTP 410 on the F/CTO's key tier** ("no longer available for your account") → strictly redundant with Plaid; a second brokerage integration is unjustified. `snaptrade-*` probes retired.
- **Teller INVALIDATED** — service shutting down.

**Pricing — Plaid bills per ITEM, not per connected account** (corrected 2026-07-16 vs the billing docs, `https://plaid.com/docs/account/billing/`). Transactions + Investments are subscription fees per Item (per institution login) as long as a valid `access_token` exists; Investments = Holdings $0.18 + Investment-Transactions $0.35; no proration/base/minimum. F/CTO's 10 real accounts = **5 Items** → Fidelity (card + 4 investment) $0.83 + Schwab (checking + brokerage) $0.83 + Cap One / Wells / Synchrony $0.30 each = **$2.56/mo (~$31/yr)** on PAYG, or **$0** under the 10-Item Trial cap (Trial Items are lifetime-cumulative — `/item/remove` does NOT refund the slot). **Cost scales with institutions, not account count** — the original "8 vs 16 accounts" axis barely moves the bill.

**Empirical findings folded into the worker/adapter build:**
- **Plaid sign convention is inverted** (positive = money OUT) → flip to R-7 `positive=inflow` at ingest.
- **`CUR:USD` cash sweeps** returned as holdings = the uniform cash-as-currency-asset model (already handled).
- **Fixed-income "symbols" are CUSIP-ish / descriptive strings** (`CILH4422711`, `US Treasury Bill - 3.52%…`), NOT clean tickers → symbol→`asset` resolution needs a CUSIP/`security_id`-keyed path for bonds, not ticker-only. A registry-design input.
- **Credit-card history is issuer-capped** (Cap One ~3mo, Fidelity Visa ~1mo), NOT a config limit — Schwab checking returned the full 2yr under the same `days_requested: 730`, and `days_requested` is locked at Item creation with no documented widen-in-place path → **card backfill comes from the F/CTO's spreadsheet**, not the API.

**Consequence:** gate (i) CLOSED. The worker build (SELF-197 successor) targets a **Plaid adapter + SimpleFIN adapter** behind `linked_source`. **SELF-212 (Plaid production sales call) now truly MOOT.** Gate (ii) (PM §2.4/§2.5 per-provider-connect re-scope) unchanged. This is a provider-selection call — **no schema, ledgers untouched.** Full empirical record: `temp/aggregator-strategy-memo.md`.

### Amendment (2026-07-17 / credential-admission slice — worker-owns-exchange invocation-path lock; Sec SC-3 condition C7). F/CTO-ratified; Sec SC-3 GREEN-with-conditions (endorsed worker-owns-exchange as security-superior). Pins the `connect()`/`revoke()` credential-admission architecture ahead of Backend's build (in flight same-PR). Design memo: `temp/provider-sync-credential-admission-design.md`.

The `ProviderAdapter.connect()` credential-admission path (the biggest remaining SD-03 surface) was a **one-way door**: which tier owns the Plaid `public_token`→`access_token` exchange + the `vault.create_secret` + the `INSERT pfin.linked_source` privileged write. F/CTO ratified **worker-owns-exchange** on Architect recommendation; Sec SC-3 endorsed it as the security-superior split. This amendment locks it (SC3-C7). The `015` substrate (the credential store + decrypt view + retention backstop + the `unique(provider, external_connection_id)` dedup index + the `account` link columns) is the whole DB surface — this slice is worker CODE against that shipped contract, so it authors **no migration**.

**(s) CREDENTIAL-ADMISSION SPLIT = worker-owns-exchange (the one-way door, LOCKED).** The **worker** (`workers/provider-sync/`, Node/TS) performs the Plaid `/item/public_token/exchange`, the `vault.create_secret(<access_token>)`, and the `INSERT pfin.linked_source` — all under `SET LOCAL ROLE service_role` (the ADR-023 write-identity-of-record; login role `authenticator` per the ADR-019 note). **api/src is a THIN browser-facing relay** (SECURITY §4.1 — it owns the browser edge + the session) that passes ONLY the short-lived, single-use `public_token` to the worker; **the raw `access_token` NEVER enters the app tier and never leaves the worker/Vault.** Rejected: app-owns-exchange (would place the Plaid client secret + a service_role vault-write into the browser-facing tier — a wider RT-26 credential surface + credential-handling split across two tiers). §4.1 and SC-3 **compose** — the app owns the edge, the worker owns the credential; the worker never faces the browser. Reversal = relocating the Plaid secret + the service_role vault-write across the app/worker boundary + re-attributing RT-26 → one-way, hence ratified slowly.

**(t) `ownerUserId` SERVER-SESSION-DERIVED (ADR-LOCK — Sec SC3-C1; NOT design-memo-only).** Admission runs as RLS-bypassing `service_role`, where `auth.uid()` is NULL, so `linked_source.users_id` will NOT self-stamp from its column default — `connect(setup)` MUST supply `ownerUserId` explicitly, bound in code (Decision 1 clause (d), resolved-tenant-in-code). **On the app-relay path (SELF-212), `ownerUserId` derives EXCLUSIVELY from the server-validated session** (`auth.uid()` in `src/hooks.server.ts` / `+server.ts`), **NEVER from the client request body.** This in-code binding is the **SOLE tenant-correctness control** under service_role admission — a wrong value = a cross-tenant credential (the single highest-stakes point in the slice). Defense-in-depth secondary catch: the downstream account-mapping slice's shipped `fn_account_matched_linked_source` (Decision-3 #6) fence rejects linking an account to a source whose `users_id` mismatches — a catch, not the primary control.

**(u) ADMISSION = inline `service_role` SQL, NO DB function (DEFINER stays 3).** `vault.create_secret` + `INSERT linked_source` are issued as inline SQL from the worker under `SET LOCAL ROLE service_role`, in ONE atomic transaction (no orphaned never-referenced secret). NOT a DB function: a DEFINER admission fn would be a 4th allowlist entry for zero gain (service_role already holds Vault access + the `015` INSERT grant) — the ADR-026 / `022`-Option-B DEFINER anti-pattern. **`revoke(ref)` = read `pfin.decrypted_source_credential` (service_role-only view) → Plaid `/item/remove` → THEN `DELETE linked_source`** (which fires the `015` `fn_linked_source_cleanup_vault_secret` retention backstop). **TENANT-SCOPED (defense-in-depth over the design's bare `source_id`):** `revoke` takes `{ sourceId, ownerUserId }` and BOTH the decrypt-view read and the `DELETE` filter `users_id = ownerUserId`, so under RLS-bypassing service_role a wrong/foreign `sourceId` reads + deletes 0 rows rather than touching another tenant's source (the (t) in-code tenant-binding applied to the revoke path). **Revoke-then-delete, ABORT-on-provider-revoke-failure** — deleting-anyway orphans a live, un-revocable Plaid Item (the exact regression the `015` fail-closed backstop is designed to prevent); `ITEM_NOT_FOUND`/already-removed → treat as revoke-success → proceed (makes revoke idempotent + crash-safe). **Re-admission** (credential rotation on the same Item) = UPDATE the existing row + `vault.update_secret` reusing the SAME secret handle (creating a new secret + swapping the handle would orphan the old vault row — the retention trigger fires on DELETE, not UPDATE); dedup key = the shipped `unique(provider, external_connection_id)`. `connect()` returns `{ sourceId, accounts }` refs but does NOT write `pfin.account` — account-mapping is a separate downstream slice.

**(v) DEV-CLI-FIRST, SANDBOX-GATED (Sec SC3-C2); relay deferred to SELF-212 (SC3-C6).** The V1.x build driver is a worker-side **dev CLI** taking a sandbox `public_token` — it **enforces `PLAID_ENV=sandbox` and is NEVER the production admission path.** The api/src browser-relay + the app→worker handoff mechanism (a bounded short-lived DB handoff row vs. a direct invocation; **NOT a new inbound worker HTTP surface without a forcing function**) are **deferred to the SELF-212 frontend wave**, which carries its own forward Sec-review (SC3-C6). SELF-212 was marked MOOT only for the Plaid *production sales call*; the app-relay *admission mechanism* it now anchors is a distinct, live forward surface. **[Back-annotation 2026-07-19 / amendment (hh): the app→worker handoff mechanism deferred here is RESOLVED at amendment (hh) below = Option C (internal private-network-only HTTP). The "NOT a new inbound worker HTTP surface without a forcing function" guard was SATISFIED (the forcing function held — see (hh)), F/CTO-ratified 2026-07-19; this deferral clause is thereby discharged, not overturned.]**

**Ledger — FLAT (this slice authors no migration; the `015` substrate is the whole DB surface):** **no migration** · **DEFINER allowlist stays 3** ((u) — inline SQL, no DEFINER fn) · **§10 catalogued stays 2** (RT-22 + RT-26; `vault.create_secret` / `pfin.decrypted_source_credential` are platform-owned per `015`; the worker reaches service_role via direct-Postgres `PFIN_DB_PASSWORD`, off the RT-26 code-layer allowlist — same layer-attribution as PR #1 / the login-role capability pass) · **Decision-3 family stays 8 operational, UNCHANGED** — `connect()` writes no FK-shaped column; it does NOT write `account.linked_source_id` (that is the separate account-mapping slice, which exercises the shipped #6 fence, NOT a new instance). **§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate the numbered list):** (i) numbering — RT-22 first / RT-26 second, count unchanged at 2; (ii) layer-attribution — all service_role reach in this slice is DB-ACL / direct-Postgres, NOT the RT-26 code-layer `SUPABASE_SERVICE_ROLE_KEY` literal (identical reasoning to `008`/`015`/the login-role pass) and NOT the RT-22 PDF-worker container fence; (iii) Decision 4 linked, not restated.

**Cross-refs:** [ADR-023](#adr-023) (service_role write-identity-of-record — the worker admits AS service_role, unchanged) · the [ADR-019](#adr-019) login-role note (login role = `authenticator`, NOINHERIT broker) · SECURITY §4.1 (browser-facing surfaces = api/src) · `015` CONTRACT ADMISSION + RETENTION blocks (the mechanism this pins the invocation path onto). Sec SC-3 joint-review GREEN-with-conditions (C1/C2/C6/C7 above); no worker code merges without the SC-3 sign-off on the build PR.

### Amendment (2026-07-18 / account-mapping slice — INVOKER/tenant write + structural dedup `021`). F/CTO-ratified all Architect leans (incl. Q5 = the structural index, deferred to Architect recommendation). Sec joint-review-mandatory (Q1 write-identity + Q5 dedup migration + the Decision-3 #6-fence exercise; in flight same-PR). Design memo: `temp/provider-sync-account-mapping-design.md`.

The account-mapping slice writes the `pfin.account` rows for the `ProviderAccountRef[]` that `connect()` returned (setting `linked_source_id` + `provider_account_id`), making the shipped `resolveAccountIds()` map (mapper.ts) non-empty so the ingest path becomes functionally reachable. `connect()` stays refs-only (the (u) seam). This is the write analogue of the ADR-026 `fn_create_manual_account` INVOKER precedent, and the deliberate posture-contrast with the credential-admission (s)/(u) service_role write.

**(w) WRITE-IDENTITY = `withTenant` (authenticated / INVOKER), NOT `service_role` (Q1 — the crux).** Unlike credential-admission (forced to `service_role` by the Vault write), account-mapping has NO privileged-only operation, so the DB — not the caller — enforces the tenant stamp: `pfin.account`'s `account_insert` RLS `WITH CHECK (users_id = auth.uid())` + `DEFAULT auth.uid()` (003) make the row's own `users_id` **un-forgeable** (cannot be stamped to a foreign tenant); the `fn_account_matched_linked_source` #6 fence composes with RLS (a foreign source is invisible → raise); the `fn_grant_creator_access` AFTER-INSERT DEFINER trigger auto-grants the correct tenant. This is exactly the shipped `resolveAccountIds` read-identity + the ADR-026 `013` INVOKER posture ("create path needs no service_role"). Written as **inline worker SQL under one `withTenant` transaction — no DB function, no RPC** (reusing `013` was rejected: it forces an `acct_setup` opening-balance row and does not set the link columns), so **DEFINER allowlist stays 3**. Security-boundary + Sec-load-bearing, but **REVERSIBLE** (a role choice in code, `withTenant` vs `withServiceRole`) — NOT a data-migration one-way door. Residual: the tenant still rests on the caller passing the right `ownerUserId` to `forTenant()`, but a mis-bind writes for *that* tenant and the #6 fence then requires *that same* tenant to own the source — so account-mapping is the **DB backstop for a mis-stamped admission** ((t) secondary catch).

**(x) CREATE-NEW; DEFER manual↔linked RECONCILIATION to SELF-212 (Q2).** This slice always creates a new `pfin.account` row per not-yet-mapped provider account. Manual↔linked merge, "which accounts to import", and the `backfill_cutover_date` arbiter (stays NULL here) are **user choices** deferred to the SELF-212 frontend wave. Auto-matching a provider account to an existing manual account (SELF-201) is rejected for this slice: a false match merges distinct accounts irreversibly (no `authenticated` hard-delete — 003), so it needs a user-confirmation flow. "Already mapped" dedup (skip re-create) IS in scope ((z)); "merge with a manual account" is NOT.

**(y) REQUIRED NON-PROVIDER COLUMNS (Q3).** `account_type` = a Plaid `type`/`subtype` → 003 CHECK map (`depository`→`depository`; `credit`/`loan`→`liability`; `investment`→`investment` **except** the retirement-subtype allowlist [401k/403b/457b/ira/roth/roth 401k/sep ira/simple ira/pension/retirement, …]→`retirement`; unrecognized `type`→`manual_other` fallback). The allowlist is realized **completely** against Plaid's investment-subtype vocabulary in `PlaidAdapter.PLAID_RETIREMENT_SUBTYPES` (code authoritative for exact membership — additionally covers 401a/roth ira/sep/simple/keogh/sarsep/tsp, all unambiguous retirement plans; the ADR enumeration is illustrative, not a closed set). `crypto`/`real_estate` are NOT auto-assigned (no clean Plaid signal → reachable only via the SELF-212 override). `scope` + `tax_treatment` cannot be derived from Plaid → **slice-wide provisional operator CLI defaults** (`--scope`, `--tax-treatment`) + a `retirement→tax_deferred` nudge; ALL flagged PROVISIONAL / operator-overridable / frontend-corrected. A mis-mapped `account_type` or wrong provisional `tax_treatment` is a **data-quality** issue (feeds valuation/tax bucketing), **not** a security surface. The provider-specific type map lives in `PlaidAdapter.mapAccountType`; the write orchestration is provider-agnostic in `src/ingest/accountMapper.ts` (pure `buildAccountRows` + `landAccounts`, mirroring the mapper.ts split).

**(z) IDEMPOTENCY = structural partial UNIQUE INDEX at `021` (Q5 — the mild one-way door, RATIFIED).** `CREATE UNIQUE INDEX account_linked_source_provider_uidx ON pfin.account (linked_source_id, provider_account_id) WHERE linked_source_id IS NOT NULL` + `ON CONFLICT DO NOTHING` in `landAccounts`. Chosen over the app-level SELECT-guard for **structural, TOCTOU-free** dedup consistent with `015`'s `linked_source_provider_conn_uidx`. It **pins the reconciliation model** (the mild one-way door): one canonical `pfin.account` row per `(source, provider account)` — a re-map is a no-op, never a second row; the SELF-212 remove/re-add-connection UX must honor this (reactivate via `is_active`, not a new row). Reversing (modelling connect/disconnect history as multiple rows) would need `DROP INDEX` + a dedup/merge migration. Manual accounts are exempt (partial predicate; `linked_source_id` NULL). **RENUMBER:** this takes migration `021`; the planned allocation-junction migration shifts `021`→`022` (append-only sequential; landed `001`–`020` unchanged) — recorded here + in `temp/015-ingest-substrate-design.md` §16.

**(aa) BUILD DRIVER + INTERFACE (Q5-driver / Q6).** Build driver = a sandbox-gated worker dev CLI **`admit --map`** (connect → map in one run consuming `connect()`'s returned refs; mirrors `admit.ts`; production onboarding goes through the SELF-212 relay, never a CLI). Interface = new `src/ingest/accountMapper.ts` (`buildAccountRows` pure builder + `landAccounts` writer + `mapAccounts` orchestrator) + `PlaidAdapter.mapAccountType`; the `ProviderAdapter` interface is **unchanged** — `connect()` stays refs-only, mapping is NOT folded onto the adapter.

**Ledger (this slice — MIGRATION +1):** **migration `021`** (partial UNIQUE index — pure constraint; no function, no RLS, no new column, no FK, no trigger) → **migrations `001`–`021`** (was `020`) · **DEFINER allowlist stays 3** ((w) — inline INVOKER worker SQL, no function authored) · **§10 catalogued stays 2** (RT-22 + RT-26; the write path is authenticated-tier INVOKER — no `service_role`, so the RT-26 code-layer `SUPABASE_SERVICE_ROLE_KEY` allowlist is untouched; `021` is a table index) · **Decision-3 family stays 8, UNCHANGED** — `021` adds NO FK-shaped column: `provider_account_id` is TEXT (not a FK → not D3), `linked_source_id` already carries canonical instance #6 (`fn_account_matched_linked_source`, `015`) which the mapping write EXERCISES, not creates. **§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate the numbered list; Decision 4 read verbatim before drafting):** (i) numbering — RT-22 first / RT-26 second, count unchanged at 2; (ii) layer-attribution — authenticated INVOKER write + a table index; no RT-22 (infra-credential-presence) or RT-26 (code-layer allowlist) surface touched; (iii) Decision 4 linked, not restated.

**Cross-refs:** [ADR-026](#adr-026) (`fn_create_manual_account` INVOKER write-composition — this account-mapping write is its provider-linked analogue; `013` NOT reused) · [ADR-023](#adr-023) (pfin API-exposure; the write path uses no service_role) · migration `021` (`021_account_linked_source_dedup.sql`) · migrations `003` (account RLS `WITH CHECK` + `fn_grant_creator_access` DEFINER trigger) + `015` STEP 7/8 (the `linked_source_id`/`provider_account_id` link columns + the Decision-3 #6 fence) · the credential-admission amendment (s)–(v) above (the `connect()`-refs-only seam this consumes). **Sec joint-review-mandatory** on (w) write-identity + (z) dedup migration + the #6-fence exercise; **QA two-tenant pgTAP battery same-PR** (duplicate-INSERT-fails + cross-tenant-link-fails-closed + owner-positive; not a vacuous green); no worker code or `021` merges without Sec sign-off.

### Amendment (2026-07-18 / SimpleFIN credential-admission slice 3a — 2nd provider adapter). F/CTO-ratified; Sec SC-3 GREEN-with-conditions (SC-3 review of 3a; caught + corrected the `external_connection_id` digest-input inconsistency → full-URL digest). Design memo: `temp/provider-sync-scheduler-simplefin-design.md`. **Slicing:** the scheduler/SimpleFIN PR-#2 bundle splits into **3a = SimpleFINAdapter** (this amendment; new-provider credential admission, SC-3) + **3b = the sync scheduler** (Coolify-cron enumerate-and-drive; a later amendment). This is the write-up for 3a.

SimpleFINAdapter is the 2nd `ProviderAdapter` impl behind `pfin.linked_source` (routing is per-institution per ADR-027; SimpleFIN = banks/cards). No migration — `provider='simplefin'` is a shipped `015` discriminator and the credential substrate (Vault handle + decrypt view + retention backstop + the `unique(provider, external_connection_id)` index) is the whole DB surface.

**(bb) CREDENTIAL MODEL = Access-URL-in-Vault; worker-owns-exchange INHERITED (ADR-027 (s)/(t)/(u)).** SimpleFIN's onboarding is **setup-token → claim-POST → Access URL** (a reusable read credential that embeds basic-auth; one-time claim, 403 on re-claim). The setup token is the short-lived-single-use analogue of Plaid's `public_token`; **the Access URL is the long-lived credential (SD-03-class), stored ONLY in `vault.secrets`** (ciphertext), referenced by the `linked_source.credential_secret_id` uuid handle (withheld from `authenticated`) — RT-02 structural, identical to Plaid. The **worker** does the claim POST + `vault.create_secret(<Access URL>)` + `INSERT linked_source` inline under `SET LOCAL ROLE service_role`, in ONE atomic transaction (mirrors (u), no orphaned secret); `ownerUserId` bound in code (Decision 1 (d); the app-relay path (SELF-212) hands only the setup token, never the Access URL). `SourceRef.accessToken` = the full Access URL; `fetch*` splits its embedded auth into an Authorization header. **No DB function → DEFINER stays 3.**

**(cc) `external_connection_id` = SHA-256(FULL normalized Access URL) — auth INCLUDED (Sec SC-3 catch) + C5 high-entropy assumption (LOAD-BEARING).** SimpleFIN has no stable provider connection id (unlike Plaid's `item_id`), so `external_connection_id` (the `unique(provider, external_connection_id)` dedup key) = a SHA-256 digest of the **full normalized Access URL**. **The full URL is digested, NOT auth-stripped host+path:** `external_connection_id` participates in the GLOBAL unique index + is readable by the owning tenant, and an auth-stripped host+path digest is both lower-entropy AND collision-prone — two tenants behind ONE SimpleFIN bridge would collide → the 2nd admission is rejected + a cross-tenant timing leak (the Sec SC-3 catch that reversed the design memo's original §2(a) wording). The auth segment is the per-credential-unique high-entropy component. **C5 (stated explicitly, load-bearing):** storing a *credential-derived* digest on a client-readable column is safe **only under the assumption that the Access URL is high-entropy** — combined with SHA-256 preimage-resistance (the digest cannot be inverted to the credential) + `external_connection_id` being RLS-scoped to owner. A future low-entropy-credential provider must NOT silently inherit this pattern — hence C5 is named, not assumed. Stable digest → re-admitting the same (dev-CLI-cached) Access URL hits the shipped re-admission UPDATE path; a fresh setup-token claim yields a new URL → a new connection (the accepted duplicate edge, as Plaid's fresh-Link). **MILD ONE-WAY DOOR:** the digest scheme is persisted into `linked_source` rows + the shipped index; re-keying later needs a backfill.

**(dd) C7 REVOKE RESIDUAL — SimpleFIN connections cannot be programmatically revoked.** SimpleFIN exposes no `/item/remove` equivalent, so `revoke(ref)` = the tenant-scoped LOCAL delete only: `DELETE pfin.linked_source WHERE source_id=$1 AND users_id=$ownerUserId` (fires `fn_linked_source_cleanup_vault_secret` → destroys our stored Access URL in Vault). **Local removal destroys OUR stored Access URL but the credential remains valid at the SimpleFIN Bridge until user action there.** This is a documented product residual, NOT a code gap — the Plaid abort-on-revoke-failure hard-gate (u) does not apply (there is no provider revoke call to fail). **C6 (deferred):** the user-facing warning UX ("removing this connection here does not revoke it at SimpleFIN — revoke at the Bridge") defers to the SELF-212 frontend wave. **This C7 residual is recorded in both this ADR and the SECURITY known-residuals surface** (§4.2 credential posture — Sec-authored addition, routed at 3a).

**Ledger — FLAT (3a authors no migration):** **no migration** (`provider='simplefin'` + the `015` substrate are shipped) · **DEFINER allowlist stays 3** ((bb) — inline service_role SQL, no DEFINER fn) · **§10 catalogued stays 2** (RT-22 + RT-26; SimpleFIN's service_role reach is the same direct-Postgres `PFIN_DB_PASSWORD` transport, off the RT-26 code-layer allowlist; the Access URL is a worker-held provider credential, NOT a Supabase key) · **Decision-3 family stays 8** (SimpleFINAdapter writes `linked_source` — `users_id` sole anchor, not D3; no FK-shaped column). **§10 3-axis (Path B — reference [Decision 4](#adr-011), do not restate; Decision 4 read verbatim before drafting):** (i) numbering RT-22 first / RT-26 second, unchanged at 2; (ii) layer-attribution — direct-Postgres service_role (identical to Plaid `008`/`015`/the (s)/(u) admission), no RT-26 key literal, no RT-22 container surface; (iii) Decision 4 linked, not restated.

**Cross-refs:** the credential-admission amendment (s)/(t)/(u) above (worker-owns-exchange + inline-service_role admission + in-code tenant-binding — all INHERITED by SimpleFIN) · [ADR-011](#adr-011) Decision 1 (privileged-context-write) / Lock 4 Vault-native amendment (the credential-storage mechanism) / [Decision 4](#adr-011) (§10, unchanged) · `015` `linked_source` + `decrypted_source_credential` + `fn_linked_source_cleanup_vault_secret` + the `unique(provider, external_connection_id)` index. **Sec SC-3 joint-review-mandatory** on (bb)/(cc) credential admission + the C7 residual; QA 3a = admission-atomicity live-DB test (G3) + duplicate-global-asset edge (SC-4). No SimpleFIN credential code merges without SC-3 sign-off. The 3b scheduler + the SC-2 holdings-determinism resolution ride a later amendment.

### Amendment (2026-07-18 / sync scheduler slice 3b). F/CTO-ratified (SC-2 = FLAT, verified against `018`/`019`); Sec joint-review on the SC-2 disposition + the privileged per-source enumeration/isolation path (NOT SC-3 — the scheduler adds no new credential surface). Design memo: `temp/provider-sync-scheduler-design.md`. This is the 3b write-up; it completes the PR-#2 bundle (3a adapter + 3b scheduler).

The scheduler is the Coolify-cron entrypoint that drives the shipped `syncProviderData` (mapper.ts) per active `linked_source` across both shipped adapters (Plaid + SimpleFIN). No migration — it enumerates + invokes shipped code; the whole DB surface (`linked_source`, `decrypted_source_credential`, `linked_source_sync_audit` `scheduled_poll`, the `018`/`019` snapshot + valuation substrate) is live.

**(ee) SC-2 HOLDINGS SAME-DAY-DUP = FLAT (accept harmless accumulation; determinism already shipped). `fn_holdings_as_of` determinism = CONFIRMED.** The scheduler automates retries, and `landHoldings` appends a `holdings_checkpoint` row with NO `ON CONFLICT` (contrast `landBalances`' `DO NOTHING`) — so a same-day re-sync writes a 2nd snapshot per `(account, security, as_of_date)`. This is HARMLESS because **both read paths already tie-break deterministically by `checkpoint_id desc`**: `fn_holdings_as_of` (`019`, `distinct on (account_id, security_id) … order by as_of_date desc, checkpoint_id desc`) + `holdings_checkpoint_latest` (`018`, same) → the newest snapshot always wins; the superseded row is never surfaced. This is the intended immutable-snapshot-ledger + deterministic-latest-overlay pattern the `015`–`019` substrate is built on. **Rejected: (b) structural same-day dedup (a `022` unique constraint + `ON CONFLICT`)** — `holdings_checkpoint` is IMMUTABLE (`005` triple-fence blocks UPDATE for ALL roles incl. service_role), so only `DO NOTHING` is possible → a same-day **corrected** quantity (intraday re-snapshot) would be silently DROPPED; and nullable `security_id` (blank-symbol holdings) makes a unique index miss those rows anyway. (b) would trade a harmless superseded row for a dropped legitimate correction — a **write-model one-way door** that fights the append-and-supersede design. F/CTO ratified (a) FLAT.

**(ff) SCHEDULER SHAPE = single Coolify-cron `poll` entrypoint, per-source failure isolation.** One entrypoint (`workers/provider-sync/src/cli/poll.ts`), invoked by a **native Coolify cron container** (NOT an in-app timer — workers/CLAUDE.md), per run: SELECT active `linked_source` (service_role; `connection_status <> 'revoked'`) → **per source, SEQUENTIAL + FAILURE-ISOLATED** (its OWN `TenantBoundClient.forTenant(config, row.users_id)` binding + its own try/catch — one gappy/revoked source never aborts the fleet nor leaks into another source's audit/state row): resolve the credential via `decrypted_source_credential` → dispatch by `row.provider` (Plaid | SimpleFIN) → `fetch*` → shipped `syncProviderData` → `INSERT linked_source_sync_audit (source='scheduled_poll', provider_event_id=NULL, detail=<counts + errlist>)`; on error, record in the audit `detail` + transition `connection_status` via `linked_source_state_history`, continue. Sequential is correct (TBC `max:1`; provider `fetch*` are network calls OUTSIDE the DB txns → no `statement_timeout` pile-up; SimpleFIN's 90-day cap bounds payload). **Txn policy = full trailing-window (~89d) + the shipped `(source_provider, provider_txn_id)` dedup, NO cursor** (idempotent + self-healing; poll-provider cursors are a known fragility). Discord failure routing via the incumbent Coolify→Discord (cax21). Per-provider cron containers stay deferred (the scale answer; unjustified at single-user volume).

**(gg) FLAG-2 V1-NOW CASE-NORMALIZE (rides 3b, code-only, FLAT).** `resolution.ts` canonicalizes `symbol` + `cusip` to `.trim().toUpperCase()` on the global-asset SELECTs + the INSERT stored value (the ON CONFLICT arbiter then matches the canonical stored form). This closes the cross-provider case-dup vector (Plaid `voo` vs SimpleFIN `VOO` minting duplicate global `pfin.asset` rows) — data-quality, NOT isolation (the `016`/`019` global-OR-owned fences hold). It rides 3b because the scheduler is what first AUTO-REGISTERS SimpleFIN globals (3a was dev-CLI-only; `resolution.ts` UNCHANGED at 3a per Sec C8). **The V1.x structural backstop — expression partial-unique indexes `unique(upper(symbol)) where users_id is null` + `unique(upper(cusip)) where users_id is null and cusip is not null` (covering ALL global-asset writers: the `016` seed + resolution + the future FMP backfill) — is DEFERRED to a separate later migration, batched with the next asset-registry-touching migration (Architect authors + assigns the number at scheduling; Sec joint-review; ledger-light — no FK/§10/DEFINER).** NOT authored here.

**Ledger — FLAT (3b authors no migration):** **no migration** (SC-2 = FLAT read-already-deterministic; the scheduler is code; the Flag-2 V1-now fix is code-only) · **DEFINER allowlist stays 3** (no function authored) · **§10 catalogued stays 2** (RT-22 + RT-26; the scheduler's service_role reach — the enumeration SELECT + decrypt-view read + the `syncProviderData` `withServiceRole` leg — is the shipped direct-Postgres `PFIN_DB_PASSWORD` transport, off the RT-26 code-layer allowlist; no new credential surface) · **Decision-3 family stays 8** (no FK-shaped column; the scheduler writes only `linked_source_sync_audit` — source_id/users_id anchors, not D3). **§10 3-axis (Path B — reference [Decision 4](#adr-011), do not restate; Decision 4 read verbatim before drafting):** (i) numbering RT-22 first / RT-26 second, unchanged at 2; (ii) layer-attribution — direct-Postgres service_role (identical to `008`/`015`/the (s)/(u)/(bb) admission paths), no RT-26 key literal, no RT-22 container surface; (iii) Decision 4 linked, not restated.

**Cross-refs:** [ADR-019](#adr-019) Decision 17 / [Lock 13](#adr-011) (the Coolify cron topology — the `poll` cron is the same native-Coolify-cron mechanism as the `workers/etl/` poll + the `monthly_report` Gate F cron; Discord routing) · the (s)/(t)/(u)/(bb)–(dd) admission amendments (the credential paths the scheduler consumes via `decrypted_source_credential`) · `018`/`019` (the deterministic read paths `holdings_checkpoint_latest` + `fn_holdings_as_of`; the `005` immutability triple-fence that makes (b) impossible) · mapper.ts `syncProviderData` (the shipped landing orchestration). **Sec joint-review** on the SC-2 disposition + the per-source enumeration/isolation path; **QA G2** = the `land*` / guard-#3 live-DB integration test (needs the DevOps live-DB CI lane) + the Flag-2 case-mismatch coverage; **DevOps** = the Coolify cron container definition + schedule (lean: daily) + env + Discord + the live-DB CI lane. No 3b code merges without Sec + QA sign-off.

### Amendment (2026-07-19 / SELF-212 frontend-connect wave — app→worker handoff mechanism RESOLVED = Option C internal private-network HTTP; RT-27 catalogued; §10 2→3 PERFORMED). F/CTO-ratified 2026-07-19; **Sec SC3-C6 GREEN-with-conditions** (C6-1…C6-7 + CO-REVIEW ADDENDUM CA-1…CA-6). Design memo: `temp/self212-app-worker-handoff-design.md`; Sec review: `temp/self212-sec-c6-review.md`; DevOps b-i spike: `temp/self212-devops-c6-1-spike.md`. This resolves the (v) handoff-mechanism deferral (back-annotated at (v) above).

**(hh) HANDOFF MECHANISM = Option C — internal, private-Docker-network-only HTTP endpoint on `workers/provider-sync/` (RESOLVES the (v) deferral).** api/src stays the thin browser-facing relay per (s); it opens a server-to-server call to a small HTTP server on the worker, **bound to the private Docker network only (never a public Coolify Domain), shared-secret-authenticated**, carrying a session-derived `ownerUserId`. The worker runs the (s)/(u) admission synchronously and returns `{sourceId, accounts}`. **The (v) guard "NOT a new inbound worker HTTP surface without a forcing function" was SATISFIED — the forcing function held (F/CTO-concurred; Sec GREEN):** (1) leg-1 `link_token` create needs a synchronous RPC channel regardless — per (s) the Plaid secret is worker-only, so `/link/token/create` (a stateless mint) is *also* a worker-tier op api/src must relay, and a DB-row round-trip for a stateless mint is pure over-engineering; (2) the single-use `public_token` (~30-min) atomicity is cleanest synchronous — Option C's success/fail-known-immediately avoids the token-burn-in-a-dead-zone the DB-row shape must engineer around. **Rejected:** Option A (in-process library call) — foreclosed by (s) (collapses the tier, puts the Plaid secret + service_role reach into the browser-facing SvelteKit process = app-owns-exchange re-badged); Option B (bounded DB handoff row) — the (v)-preferred fallback, viable but costs a handoff-table migration + a persistent LISTEN worker + a status/TTL-reaper lifecycle + an awkward leg-1; Sec did NOT veto C→B. **ONE-WAY-DOOR reversal cost:** the choice sets the worker's inbound-surface posture + the RT-27/§10 attribution + the app/worker trust-boundary; reversal = topology change + Sec re-review + removing RT-27 from the §10 ledger + a handoff-table migration — hence ratified slowly.

**Mitigations — LOCKED as build conditions (Sec C6-1…C6-7, refined by CO-REVIEW CA-1…CA-6):**
- **C6-1 network-exposure/config layer (VETO-if-unmet; the §10-3rd-instance limb) — DevOps b-i mechanism (supersedes Sec's original "bind assertion" per CAVEAT-2):** (a) Backend startup **fail-closed opt-in** — the admission listener refuses to boot unless `ADMISSION_PRIVATE_ONLY=true` AND every Coolify public-route signal is absent; (b) a **public-route env tripwire** keyed on pattern/prefix match (`SERVICE_FQDN_*`, `COOLIFY_*URL*`, `COOLIFY_*FQDN*`, `ADMISSION_PUBLIC_URL`), **verified against the running Coolify version's injected var names at deploy — NOT a hardcoded exact-name list** (CA-1), catching the UI-Domain regression a committed lint cannot see; (c) a **committed `workers/provider-sync/docker-compose.yaml`** (Coolify Compose build pack; precedent `workers/etl/docker-compose.yaml`) with the admission port `expose:`-only (never `ports:`, no proxy/Host label), fenced by a **dual-mode `fence-admission-bind` CI job** (house `fence-rt22`/`fence-rt26`/`secrets-nonoverlap` shape); (d) **positive golden fixtures for BOTH exposure vectors** — published `ports:` host-map AND Traefik `Host()`/Coolify-domain label each trip the fence (CA-5); (e) a **deploy-time external-reachability NEGATIVE smoke test** (admission FQDN not publicly reachable; runbook §10) as the empirical backstop (CA-2). In-container `0.0.0.0` bind is required for sibling reach and is NOT the control (CAVEAT-2). **DevOps b-i adopted (CA-3);** b-ii (Dockerfile build pack) is a weaker fallback that, if chosen, means C6-1 is not met as a multi-layer fence → RT-27's §10-catalogued status flagged weak, requiring a separate F/CTO override.
- **C6-2 auth layer:** `WORKER_ADMISSION_SHARED_SECRET` (256-bit), Coolify project-scoped shared var referenced by both api/src + the worker (one rotation edit point), **constant-time compare + fail-closed on absent/mismatch** (CA-6), on BOTH legs; **NOT `SUPABASE_SERVICE_ROLE_KEY`** → **RT-26 attribution UNCHANGED** (worker service_role reach stays direct-Postgres `PFIN_DB_PASSWORD`, off the RT-26 code-layer allowlist); secrets-manifest `production_only`, disjoint from `ci_only`.
- **C6-3 tenant layer (VETO-if-unmet; highest stakes per (t)/SC3-C1):** `ownerUserId` derived EXCLUSIVELY from `auth.uid()` (validated session in `hooks.server.ts`/`+server.ts`), sent in the POST body over the authed private channel, **never browser-sourced**; the worker accepts no browser-reachable tenant field (sound because C6-1's private bind makes the worker unreachable by the browser by construction). `fn_account_matched_linked_source` (Decision-3 #6) stays wired as the downstream secondary catch — it does NOT prevent the wrong-tenant credential write, so the in-code binding remains the SOLE primary control per (t).
- **C6-4 atomicity layer:** leg-2 stays the (u) ONE atomic service_role txn; never retry a burned `public_token`; on post-exchange admission failure the worker attempts `/item/remove` before surfacing (else audits for manual revoke — no orphaned live Item); a retried admission for the same Item lands on the (u) re-admission UPDATE via `unique(provider, external_connection_id)`.
- **C6-5 logging layer:** redact `public_token` / `access_token` / shared-secret / tenant-with-PII in both tiers; browser error responses carry no internal detail (mirror SELF-197 AC); QA/DevOps log-scrub assertion.
- **C6-6:** BOTH legs behind the SAME private-bind + shared-secret; leg-1 not "less protected" for being stateless (it mints link_tokens against our Plaid client = a cost-abuse vector if exposed); leg-1 tenant scoping (if any) also session-derived.
- **CA-4 same-Coolify-project precondition (security-relevant, folded INTO RT-27 mitigation):** api/src + provider-sync MUST be co-located in one Coolify project (shared Docker network) for internal DNS `http://provider-sync:PORT` to resolve; cross-project placement breaks internal reach AND induces the exact public-domain "fix" regression §10 fences → runbook §7 deploy-precondition + §10 smoke assertion.
- **C6-7 (forward, not ship-block):** admission emits a same-transaction audit row when the audit-log infra lands (forward-hook comment now), consistent with the ratified ADR-026 A2 deferred-audit posture.

**SELF-197 RE-SCOPE (in place, not split):** the old in-app `/api/plaid/item/exchange` (app-tier exchange) is **SUPERSEDED** by (s) — api/src never exchanges. `link_token` create **relocates to the worker** (Plaid secret is worker-only). api/src becomes a **credential-LESS thin relay** for both legs (session-validate → derive `ownerUserId` → shared-secret POST to the worker); it holds no Plaid or service_role secret. SELF-197's original "encrypt-on-insert / consumer-filter" framing is already absorbed by the shipped `015` Vault-native substrate + (u).

**Ledger — §10 catalogued 2 → 3 (RT-27 appended, PERFORMED at F/CTO ratify 2026-07-19); DEFINER stays 3; Decision-3 stays 8.**
- **New catalogued instance RT-27** (network-exposure/config layer — inbound credential-admission channel; HIGH + V1-SHIP-BLOCK, parallel to RT-26; the tenant-binding limb per C6-3 is critical-adjacent per (t)). Threat: the cron-only/zero-inbound provider-sync worker gains an inbound HTTP surface (leg-1 mint + leg-2 exchange+admit); vectors = public-domain exposure / forged co-network caller / forged-or-echoed `ownerUserId` / token-secret log leakage. Multi-layer mitigation = C6-1 (network/config) + C6-2 (auth) + C6-3 (tenant) + C6-4 (atomicity) + C6-5 (logging). **The catalogued instance IS the enforced network-exposure/config bind-fence limb (C6-1), not the container** — its §10-catalogued status is predicated on b-i delivering the multi-layer property.
- **DEFINER stays 3** — Option C authors no DB function; admission is inline `service_role` SQL per (u).
- **Decision-3 stays 8** — the handoff adds no FK-shaped column; `linked_source.users_id` is the sole tenant anchor.

**§10 3-axis cross-check (KEEP-at-canonical-anchor — [Decision 4](#adr-011) IS the canonical home for the catalogued numbered list; performed against Decision 4 read verbatim; the flip was PERFORMED at F/CTO ratify 2026-07-19):** (i) instance-numbering — RT-22 first / RT-26 second / **RT-27 third** (appended; existing ordering undisturbed); (ii) layer-attribution — RT-27 = **network-exposure/config layer**, a NEW layer distinct from RT-22 (infrastructure-credential-presence) and RT-26 (code-layer); **RT-22 + RT-26 attributions UNCHANGED**; conflation guard — the catalogued-instance *count* (2→3) is ORTHOGONAL to the per-surface "three-layer defense" language (RT-27 does NOT make any surface "four-layer"); (iii) canonical-structure — Decision 4's "Catalogued §10 instances at V1" numbered list amended in place to append RT-27 third; the three-classes bullets + Privileged-context-surfaces bullet + three-layer composition definitions UNCHANGED. SECURITY §4.5 carries the RT-27 row; SECURITY §4.2 an inbound-admission-channel posture bullet; ADR-008 §4.5 index amended (RT-27 + RT-28) per the SELF-212 index amendment.

**Cross-refs:** (s)/(t)/(u)/(v) above (worker-owns-exchange + in-code tenant-binding + inline-service_role admission + the deferred fork this discharges) · [ADR-011](#adr-011) Decision 4 (§10 ledger — moved 2→3 here) / Decision 1 (privileged-context-write) · [ADR-016](#adr-016) (RT-26 allowlist — attribution UNCHANGED) · SECURITY §4.1 (browser edge = api/src) / §4.2 / §4.5 (RT-27 row) · `015` admission substrate · [ADR-026](#adr-026) A2 (deferred same-transaction audit — C6-7 forward-hook) · **ADR-028** (the Plaid Link CDN forced-exception + per-route CSP for the browser-side Link surface that feeds the `public_token` into this relay) · ADR-008 SELF-212 index amendment (indexes RT-27 in the §4.5 catalog). **Handoffs:** DevOps (compose + fence + goldens + secret + smoke), Backend/worker (startup assertion + constant-time secret check + session-only tenant + post-exchange `/item/remove` + log redaction), QA (golden fixture + two-tenant cross-binding test + log-scrub assertion).

**(hh.1) SELF-279 (tracked follow-up #14, PR #175) — recurring CA-2 reachability probe SHIPPED (closes the SECURITY RT-27 forward reference; HARDENS (hh)'s RT-27 network-exposure limb; §10 ledger UNCHANGED).** *Date: 2026-07-19. Status: Accepted (F/CTO-ratified within Option B active-probe; Sec joint-review GREEN — 4 conditions C1–C3 + F1 cleared).* [**Label note:** this is the next ADR-027 amendment; written `(hh.1)` rather than the scheme-sequential double-letter `(ii)` to avoid a visual collision with the roman-numeral `(i)/(ii)/(iii)` sub-item markers used throughout ADR-027 (e.g. the (i)–(iv) list + the §10 3-axis lists) — cosmetic disambiguation per the SELF-279 brief's invitation; `(hh.1)` also reads as the semantic child of (hh), whose surface it hardens.] SELF-279 delivers the recurring reachability probe that SECURITY RT-27's "Known post-deploy residual" forward-named as "a tracked post-merge hardening" — **the "recurring reachability" string lives in SECURITY §4.2/§4.5, NOT in (hh); this note INTRODUCES the runtime behavior fresh, it does not quote (hh).** **What shipped:** a recurring, `@daily`-poll-folded (an isolated, non-fatal pre-loop step in the provider-sync `poll` entrypoint per (ff)), `/healthz`-fingerprint EXTERNAL reachability probe against DevOps-pinned candidate FQDNs; a positive detection (a `200 {status:ok}` admission-app fingerprint reached from OUTSIDE the private network — NOT bare reachability, so a proxy/CDN 200 page cannot trip it) raises a Discord alert (via the already-plumbed `DISCORD_WEBHOOK_URL`) + a durable structured log line. It **runtime-complements** RT-27's existing DEPLOY-time CA-2 negative smoke: deploy-smoke = go/no-go gate at deploy; recurring probe = drift-detector for a public Coolify Domain assigned days AFTER deploy (the stale-env residual, coollabsio/coolify #8912/#6124). **First worker→Discord egress:** SELF-279 is provider-sync's first outbound call not to Plaid/SimpleFIN/pfin — a trust-boundary egress Sec joint-reviewed; the payload carries ONLY the probed public URL + fingerprint + UTC timestamp (no token/secret/`ownerUserId`/tenant row — structurally, an outbound GET to a public URL holds no tenant credential). **Fail-SAFE (not fail-closed):** probe error + webhook failure are log-and-continue; the probe adds NO new non-zero-exit path (the poll exit-code contract is intact) — contrast the admission server's CA-1 boot tripwire, which fail-CLOSES (different surface, different severity). **Accepted residual (RF-3, F/CTO-ratified):** an arbitrary custom (non-pattern) subdomain an operator could assign is NOT enumerable by an active probe (it tests only the FQDNs it is told about); accepted per the multi-layer posture (the CA-1 pattern-match tripwire + the CA-5 committed-Compose lint + PR review cover the config vectors), and even within that residual the endpoint stays shared-secret-authed — authenticated-reachable, not an unauth breach. **Ledger — UNCHANGED (§10 count stays 3; DEFINER stays 3; Decision-3 untouched):** this HARDENS the already-catalogued RT-27 instance (its network-exposure/config layer, limb (a)(iii) CA-2) with a recurring RUNTIME complement to the existing deploy-time smoke — SAME instance, SAME layer, NO new catalogued entry, NO new layer (no surface becomes "four-layer"; RT-22 + RT-26 attributions untouched). No DB function (it is an outbound HTTP GET) → **no new SECURITY DEFINER**. No FK-shaped column → **Decision-3 untouched**. No `SUPABASE_SERVICE_ROLE_KEY` / no `@supabase/supabase-js` (the probe never touches the DB) → **RT-26 allowlist UNCHANGED**. **Reversibility — TWO-WAY DOOR** (contrast (hh)'s one-way door): every choice is reversible via an env/config change or a code revert; adds no schema, no migration, no ARCH surface lock. **New env (non-secret):** `ADMISSION_PROBE_PUBLIC_URLS` (comma-list, presence=enabled, unset ⇒ log-only no-op); the only secret (`DISCORD_WEBHOOK_URL`) already exists (`production_only`) — secrets-manifest non-overlap UNAFFECTED. **Cross-refs:** SECURITY §4.2 posture bullet + §4.5 RT-27 row (both updated to SHIPPED at SELF-279 + the RF-3 residual) · [ADR-011](#adr-011) Decision 4 (§10 ledger — NO move; stays 3) · (ff) (the `poll` entrypoint this folds into) · (hh) (the RT-27 surface this hardens). **Handoffs:** Backend (`src/http/reachabilityProbe.ts` + `src/notify/discord.ts` + poll invocation), DevOps (`.env.example` + `docker-compose.yaml` plain key), QA (network-free unit tests). Sec joint-review-mandatory (new egress + scrub guarantee + false-positive logic + §10 no-move confirmation) — routed before merge.

**(jj) OQ-2 — SimpleFIN IN-APP ADMISSION LEG (SELF-281): a SECOND route on the shipped RT-27 admission fence + the provider-agnostic connect seam. NO new fence, NO new §10 instance, NO migration — TWO-WAY DOOR.** *Date: 2026-07-20. Status: Accepted (F/CTO-ratified RF-1 / RF-2 / RF-3; Sec joint-review-mandatory on the leg + the RT-27/C7 annotation, routed before merge).* [**Label note:** written `(jj)`, skipping the scheme-sequential `(ii)` to avoid the roman-numeral `(i)/(ii)/(iii)` collision (same disambiguation the `(hh.1)` label note records); `(jj)` is a NEW top-level amendment — a distinct provider's admission leg — NOT a child-hardening of `(hh)` (contrast `(hh.1)`, which hardened `(hh)`'s own surface), hence a fresh letter rather than `(hh.2)`. Its three `RF-` flags are OQ-2's own, distinct from the SELF-279 `RF-3` recorded at `(hh.1)`.] OQ-2 delivers the in-app SimpleFIN connect flow that (bb)/(cc)/(dd) built the credential substrate for but left dev-CLI-only. It reuses the shipped `SimpleFINAdapter.connect()` wholesale and **ADDS A ROUTE to the (hh) RT-27 admission fence — it does NOT open a new fence.**

**Structural asymmetry (drives the whole leg):** Plaid = 2 legs (mint `link_token`, then exchange `public_token`); **SimpleFIN = 1 leg** — the user pastes a one-time SimpleFIN Bridge **setup token** (base64 claim URL), and admission is `setup_token → claim → Access URL → Vault admit`. There is **no SimpleFIN `link_token` analogue** (no pre-mint handshake) and **no `/item/remove` recovery** (SimpleFIN exposes no programmatic revoke — the (dd) C7 residual).

**Routes (both reversible internal names):** worker `POST /admission/simplefin/claim` (sibling to (hh)'s `/admission/exchange`; passes the SAME C6-2 shared-secret gate that fronts every non-`/healthz` path — covered by construction) + browser relay `POST /api/simplefin/connect` (credential-less; session-derived `ownerUserId`; Zod `.strict()` body with **NO tenant key** — the (t)/SC3-C1 mass-assignment fence). Response shape identical to the Plaid exchange leg (`{success, accounts}`); the leg routes to the **SAME shipped attributes mapping slice** — no new mapping leg. **Sub-decisions (all reversible, NOT one-way doors):** sibling route vs generalizing `/admission/exchange` with a `provider` discriminator (recommend sibling — leaves the Sec-reviewed Plaid `.strict()` body untouched); `/api/simplefin/connect` naming (recommend mirror the shipped `/api/plaid/*` shape); lifting the shared api/src transport to `src/lib/server/providers/` (Backend-owned — either placement holds only the shared secret → stays OFF the RT-26 allowlist).

**Frontend seam — RF-1 = Option A (F/CTO-ratified):** a provider-picker on `accounts/connect` routing to sibling per-provider components (existing `PlaidLinkConnect` + new `SimpleFINConnect`); the Option-B registry defers to a 3rd-provider forcing function (picker→registry is a data-migration-free later refactor). **RF-2 = accept the V1.x scope cut (F/CTO-ratified):** V1.x ships **paste-a-Bridge-token**; a SimpleFIN token-broker (mint setup tokens via our own SimpleFIN app credentials) defers to V2+ (new worker credential + a mint leg; no data-migration cost to add later). **RF-3 = ship the revoke-at-Bridge warning copy (F/CTO-ratified):** the connect flow surfaces "removing the connection here does not revoke access at the SimpleFIN Bridge — revoke there to fully terminate," closing the (dd) C7 residual's **warning-UX limb** (SECURITY §4.2 C7 updated to SHIPPED). The underlying credential-posture residual (no programmatic revoke; local-delete-only) persists — RF-3 closes the UX limb, not the structural residual.

**C6-1…C6-6 map (the SimpleFIN leg inherits RT-27's limbs (a)–(e); ONE divergence):** C6-1 network-exposure — SAME private-bind listener + tripwire + config-lint fence (the leg is a route on the already-private endpoint); C6-2 auth — SAME `WORKER_ADMISSION_SHARED_SECRET` gate (constant-time, fail-closed, fronts all non-`/healthz` paths by construction); C6-3 tenant — `ownerUserId` session-derived, `.strict()` rejects a body-supplied tenant, the worker re-validates the uuid, `connect()` re-asserts before any admission write; C6-5 logging — `connect()` scrubs every provider/HTTP error, setup token + Access URL never logged (the (dd) leak-vector posture carries in full, incl. the `new URL()` F1 `.input`-leak wrapped in try/catch → a generic non-credential message). **DIVERGENCE — C6-4 atomicity:** one atomic `withServiceRole` txn (shipped in `connect()`), but **NO `/item/remove` recovery — and it needs none:** a failed SimpleFIN admission creates no live revocable provider grant (the claim yields a read-only Access URL, not a live liability); a burned setup token (403 already-claimed) maps to a typed 400 `setup_token_invalid` (the client obtains a fresh token from the Bridge — the analogue of "re-run Link"), every other failure (DB/Vault/network/unknown) stays 5xx (fail-safe: a server failure is never dressed as client-correctable).

**Ledger — UNCHANGED (§10 count stays 3; DEFINER stays 3; Decision-3 UNCHANGED; RT-26 allowlist UNCHANGED; NO migration):**
- **§10 catalogued stays 3** (RT-22 first / RT-26 second / RT-27 third). The SimpleFIN leg is a **SECOND ROUTE on the already-catalogued RT-27 surface**, NOT a new catalogued instance. Auth stays `WORKER_ADMISSION_SHARED_SECRET`, NOT `SUPABASE_SERVICE_ROLE_KEY` → **RT-26 allowlist + attribution UNCHANGED**; RT-22 untouched; **no surface becomes "four-layer"** (the leg inherits limbs (a)–(e); it adds no limb).
- **DEFINER stays 3** — no DB function; admission is the shipped `SimpleFINAdapter.connect()` inline `withServiceRole` transport.
- **Decision-3 UNCHANGED** — no FK-shaped column; the SimpleFIN admission writes `linked_source` with `users_id` the sole tenant anchor (the recent ADR-027 clauses carry the operational "8"; the canonical enumeration per [Decision 3](#adr-011) enumeration-pass resolution = 5; OQ-2 adds NO instance to either count).
- **NO migration** — `provider='simplefin'` + the `015` credential substrate are shipped; this is why OQ-2 is a **two-way door** (every sub-decision above is a reversible internal choice; no schema, no ARCH surface lock).
- **Backend build-time refinement (not a redesign):** a narrow `SetupTokenInvalidError` discrimination in `SimpleFINAdapter.connect()` for the client-correctable 400 (today it throws a generic scrubbed 403 for already-claimed).

**§10 3-axis (Path B — reference [Decision 4](#adr-011), do not restate the numbered list; Decision 4 read verbatim before drafting):** (i) numbering — RT-22 first / RT-26 second / RT-27 third, unchanged at 3 (SimpleFIN leg = a second route on RT-27, not a new instance); (ii) layer-attribution — RT-27 network-exposure/config layer unchanged, RT-22 + RT-26 attributions untouched, no surface becomes "four-layer"; (iii) Decision 4 linked, not restated. **SECURITY disposition = KEEP-at-canonical-anchor + extend:** the §4.5 RT-27 row (the canonical admission-surface anchor) keeps the Plaid leg-1/leg-2 clauses VERBATIM and ADDS a SimpleFIN leg-S clause; the §4.2 RT-27 posture bullet extended likewise; §4.2 C7 updated to SHIPPED (RF-3).

**Cross-refs:** (hh) (the RT-27 admission fence + Option-C mechanism this adds a route to) · (bb)/(cc)/(dd) (the SimpleFIN credential model + the C7 revoke residual — INHERITED) · (aa) (the shipped attributes mapping slice this reuses) · [ADR-011](#adr-011) Decision 4 (§10 ledger — NO move; stays 3) / Decision 1 (privileged-context-write) · [ADR-016](#adr-016) (RT-26 allowlist — UNCHANGED) · SECURITY §4.2 (C7 revoke-residual → SHIPPED + the RT-27 posture bullet) / §4.5 (RT-27 row KEEP+extend). **Handoffs:** Frontend (provider-picker + `SimpleFINConnect.svelte`), Backend (`/api/simplefin/connect` relay + worker `/admission/simplefin/claim` route + `admitSimplefin` deps method + `serve-admission.ts` wiring + the `SetupTokenInvalidError` discrimination), QA (admission test battery extension — NOT the RLS battery; no migration), DevOps (no action — no new secret/container/inbound surface; confirm-only at PR review). **Sec joint-review-mandatory** on the leg (the C6 map) + the RT-27/C7 SECURITY annotation (§10-ledger-adjacent, D4) — a "review + annotate" review, not a "new fence" one. No SimpleFIN admission code merges without Sec sign-off.

---

## ADR-026 — SELF-201 manual-account create path: `fn_create_manual_account` SECURITY INVOKER write-composition RPC (migration `013`) + audit-log same-transaction discipline deferred (A2, conscious deviation)

**Date:** 2026-07-06
**Status:** Accepted
**Phase:** Phase 6 Build Loop (SELF-201 / §2.4.2 manual non-Plaid account onboarding; migration `013`).
**Approved by:** F/CTO ratified **Option A** (Architect-authored INVOKER write-composition RPC) + **A2** (defer the same-transaction audit-log to a dedicated audit-infra issue) — per the Backend decision gate `temp/self-201-backend-plan.md` §1 + §1.1. Sec joint-review + QA pgTAP gate merge.
**Pattern:** Short pattern (one function + one pattern-precedent + one documented deferral).

**ADR-home note (not a one-way door).** New short-pattern ADR (mirrors [ADR-025](#adr-025)'s feature-decision home). The write-composition-under-INVOKER pattern is a new, reusable convention worth codifying here; reversible ADR-home choice, flagged not gated.

**Decision — atomic INVOKER write-composition RPC.** SELF-201 AC#2 requires the `account` row and its AcctSetup opening-balance `account_trans` row to be created together. `pfin.fn_create_manual_account(p_name, p_account_type, p_scope, p_tax_treatment, p_initial_value numeric, p_as_of_date date, p_sub_cat_id bigint DEFAULT NULL) RETURNS bigint` — **SECURITY INVOKER**, `set search_path = ''`, body = `INSERT pfin.account RETURNING account_id` → `INSERT pfin.account_trans (transaction_type='acct_setup', transaction_date=p_as_of_date, amount=p_initial_value)` → `RETURN account_id`. Called via `locals.supabase.schema('pfin').rpc('fn_create_manual_account', {...})`.

**Why an RPC (atomicity forcing function).** `locals.supabase` runs each `.insert()` as its own PostgREST transaction, so two client calls are not atomic — a mid-way failure orphans the account. App-level compensation is **structurally blocked**: `authenticated` has no DELETE grant/policy on `pfin.account` (`003` — soft-delete only via `is_active`), so an orphan cannot be reversed by the client. A single INVOKER RPC whose body is one transaction is the correct all-or-nothing shape on the immutable audit-class ledger.

**Why INVOKER, not DEFINER (allowlist stays 3).** Every write the function composes is one the caller is already entitled to make, and RLS validates each as the caller: `account_insert` WITH CHECK (`users_id = auth.uid()`, defaulted — un-forgeable, NOT a parameter); the `AFTER INSERT` `fn_grant_creator_access` (`003`, DEFINER) seeds the `account_users(rd,wr=true)` creator-grant row in the same transaction before statement (2); `account_trans_insert` wr_access-JOIN (`006`) is satisfied by that row; `fn_account_matched_sub_cat` (`012`, BEFORE INSERT) fails closed on a cross-tenant `p_sub_cat_id` even through the RPC. No elevation is needed → **not a new [Decision 9](#adr-011) DEFINER allowlist entry** (stays 3). The create path needs **no `service_role`** (anon-key client + RLS + INVOKER). This is the **write analogue of the [Lock 11](#adr-011) INVOKER read-composition helpers** (`fn_compute_nav` / `fn_compute_tax_liability` / `fn_render_monthly_report`) — the reusable precedent for future multi-write paths (tax, reverse-and-replace).

**Alternatives considered:**
- **B — sequential supabase-js inserts + app-level compensation.** Fastest, no migration, pure Backend surface. **Rejected:** non-atomic on the immutable audit-class ledger (the exact partial-write the discipline forbids), and compensation is structurally blocked (no DELETE on `account`) so an orphan cannot be reversed without either adding a DELETE grant `003` intentionally withheld or leaving a phantom `is_active=false` account with no bootstrap row.
- **C — trigger-synthesized AcctSetup row (C1) / DEFINER RPC (C2).** C1 couples ledger synthesis to account DDL with no clean column to carry the amount (ugly). C2 uses elevation that is not needed (anon+RLS+INVOKER suffices) and would expand the Sec-veto DEFINER allowlist for nothing. **Rejected.**

**Audit-log A2 deferral (conscious documented deviation).** `api/CLAUDE.md` mandates a same-transaction audit-log per state change (Decision 1 / [Lock 4 mod #5](#adr-011)), but the audit-log table + its DEFINER insert-helper (the 3rd, still-**unauthored** DEFINER allowlist entry) do not exist — so **no V1 path emits audit rows today** (account / account_trans / reconciliation all already ship without it; the discipline is currently vacuous V1-wide). Rather than bootstrap cross-cutting audit infra as a side-effect of the first manual-account form, the audit insert is **deferred** to a dedicated audit-infra issue (SELF-201 Task #7); `fn_create_manual_account` ships with a **forward-hook comment** marking where the same-transaction audit row lands when the infra arrives. The immutable `acct_setup` row already provides V1 creation provenance. This mirrors the `006` mod #1 documented-forward-fence deferral shape. **F/CTO-ratified; Sec concurrence at joint-review.**

**API-surface note (mild one-way door).** `pfin` is API-exposed ([ADR-023](#adr-023) `[api] schemas`) and the function is EXECUTE-granted to `authenticated`, so it is callable via PostgREST at `/rpc/fn_create_manual_account`. Its parameter names + types are an API contract — renaming/retyping a param later is a breaking change (adding a new DEFAULTed param is additive-safe). Signature fixed to match the Backend call site. `anon` denied: `REVOKE EXECUTE FROM PUBLIC` + `GRANT EXECUTE TO authenticated`.

**§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011)).** Zero catalogued §10 instances; ledger stays **2** (RT-22 + RT-26). Authenticated-tier INVOKER write-composition; no infra-credential (RT-22) or `SUPABASE_SERVICE_ROLE_KEY` allowlist (RT-26) surface touched (create path uses no service_role); Decision 4 linked, not restated. **Decision 3:** `013` adds no FK-shaped column — it passes `p_sub_cat_id` through into the account INSERT where `012`'s canonical-#5 fence validates it; family **unchanged at 5**.

**Sec gate:** **joint-review-mandatory** — a new function on a money-write path that INSERTs the immutable audit-class ledger ([Decision 2](#adr-011)-adjacent), the A2 audit-deferral concurrence, and confirmation the create path needs no `service_role`. **NOT a new DEFINER function** (INVOKER — DEFINER allowlist stays 3); §10 ledger unchanged (2). Paired QA two-tenant pgTAP battery gates merge ([ADR-023](#adr-023) C6).

**Cross-references:**
- SELF-201 / `supabase/migrations/013_fn_create_manual_account.sql` — the RPC this ADR documents. Prereqs: `003` (account + account_insert RLS + fn_grant_creator_access), `004` (account_trans immutable ledger), `006` (account_trans rd/wr_access-JOIN RLS + GRANT), `012` (transaction_type + sub_cat_id + matched-tenant trigger).
- [ADR-025](#adr-025) — the `012` schema foundation this create path consumes.
- [ADR-011](#adr-011) [Lock 11](#adr-011) (INVOKER read-composition — this is the write analogue) + [Decision 9](#adr-011) (DEFINER allowlist, unchanged at 3) + Decision 1 / [Lock 4 mod #5](#adr-011) (same-transaction audit-log — deferred) + [Decision 4](#adr-011) (§10, unchanged) + [Decision 3](#adr-011) (family unchanged at 5).
- [ADR-023](#adr-023) (`pfin` API exposure — makes the RPC a PostgREST surface) + C6 (exposure-gating QA pairing).
- `temp/self-201-backend-plan.md` §1 (atomicity options A/B/C) + §1.1 (audit A1/A2 fork).

**Handoffs:** QA authors the `supabase/tests/` two-tenant pgTAP battery (cannot create for another `users_id`; cross-tenant `p_sub_cat_id` fails closed; the acct_setup row lands under wr_access; atomic rollback on injected failure). Backend calls the RPC from `actions.default` after `supabase migration up` + CI fixture-seed verify. The deferred audit-log infra is SELF-201 Task #7.

**Amendment (2026-07-06 / Sec Lock-14 FLAG remediation; migration `014`).** Sec flagged that because the `013` RPC is API-exposed (EXECUTE-granted to `authenticated`; `pfin` in `[api] schemas` per [ADR-023](#adr-023)), a direct PostgREST `/rpc/fn_create_manual_account` call **bypasses the app-layer Lock-14 Zod numeric-sanitization battery** — so a value invariant on `account_trans.amount` must be fenced at the DB layer, not only in app code. Remediation: migration `014_account_trans_amount_finite.sql` adds `CHECK (amount <> 'NaN'::numeric)` on `pfin.account_trans.amount` (role-agnostic — `service_role` bypasses RLS but not CHECK constraints; and load-bearing because the ledger is immutable, so a NaN row can never be UPDATEd out and poisons every SUM/NAV). **Scope = NaN-only, empirically verified:** `numeric(20,4)` stores `'NaN'` but **already rejects `±Infinity` at coercion** (precision overflow — "a field with precision 20, scale 4 cannot hold an infinite value"), so an Infinity guard would be dead code (revisit only if the column type ever loosens to bare `numeric`). The DB CHECK is the **defense-in-depth counterpart** to the app-layer Zod battery — both layers stand. Placement = companion migration `014` (single-purpose; a table-level invariant protecting every write path to `amount`, not RPC-specific), same PR/branch as `013`. Ledgers unchanged (§10 = 2; DEFINER allowlist = 3; Decision 3 family = 5). QA adds a NaN-reject assertion; Sec joint-review confirms the NaN-only scope.

---

## ADR-025 — SELF-201 manual-account schema foundation: `account.sub_cat_id` matched-tenant FK (Decision-3 canonical instance #5) + AcctSetup discriminator on `account_trans` (Option B, one-way-door)

**Date:** 2026-07-05
**Status:** Accepted (amended 2026-07-23 by [ADR-031](#adr-031) — see Amendment 1 below)
**Phase:** Phase 6 Build Loop (SELF-201 / §2.4.2 manual non-Plaid account onboarding; migration `012`).
**Approved by:** F/CTO ratified 2026-07-05 — **Option B** for the AcctSetup discriminator (one-way-door ratify gate); `sub_cat_id` **NULLABLE** + matched-tenant trigger + `is_active` reuse ratified as recommended-defaults; and the **Decision-3 canonical-#5 enumeration** (the deferred enumeration pass — see Decision 3 below). Design paper: `temp/self-201-012-design.md`.
**Pattern:** Short pattern (schema-foundation for one issue; three components + a Decision-3 enumeration-pass amendment). Companion to [ADR-022](#adr-022)/[ADR-024](#adr-024) (CHECK-vs-table) and an enumeration extension of [ADR-011](#adr-011) Decision 3.

**ADR-home note (not a one-way door).** This is authored as a new short-pattern ADR (feature-decision home, mirroring [ADR-024](#adr-024)'s shape) PLUS an in-place amendment to [ADR-011](#adr-011) Decision 3's canonical enumeration (where the count-grain annotation lives and where line-718 pointed the enumeration pass). Dual-surface is deliberate: ADR-025 carries the feature rationale; ADR-011 Decision 3 stays the canonical family-enumeration home. The ADR-home choice is reversible (ADRs cross-reference / supersede), so it is flagged, not gated.

**Component (1) — `pfin.account.sub_cat_id → pfin.user_taxonomy(id)`: Decision-3 CANONICAL instance #5.** SELF-201 AC#1's manual-account form captures a Sub-Cat assignment. Both sides are per-user (`account.users_id` and `user_taxonomy.users_id`), so a PG FK (existence-only, silent on RLS) would let a user tag their account with another tenant's Sub-Cat — the exact chain attack [Decision 3](#adr-011) fences. Realization = `BEFORE INSERT OR UPDATE` trigger `fn_account_matched_sub_cat` (SECURITY INVOKER, NULL-safe fail-closed, `set search_path = ''`), mirroring `fn_account_trans_matched_account` (`004`) and **extended to cover UPDATE** because SELF-236 (§2.2.1.c reassignment) is an UPDATE path. A single-row CHECK cannot subquery the referenced row; Decision 3 permits a trigger where PG cannot express the constraint declaratively. `sub_cat_id` is **NULLABLE** (NULL = untagged / Unsorted-pending: Plaid-synced accounts carry none, SELF-200 auto-Unsorted may assign after insert; NOT NULL would force a tag on every account-creating path and couple each to taxonomy-row-existence-at-insert — the boring/reversible call is nullable, tighten later cheaply), `ON DELETE RESTRICT`. Matched-**domain** (`user_taxonomy.domain = 'asset'`) is left to the app-layer dropdown filter in V1, not trigger-enforced (the `account_type='liability'` tagging question is a net-worth-modeling ambiguity not baked into a DB trigger under uncertainty; a one-line addition later if desired). SECURITY DEFINER allowlist **unchanged at 3** (the trigger is INVOKER).

**Component (2) — AcctSetup discriminator on `pfin.account_trans`: Option B (ONE-WAY DOOR).** SELF-201 AC#2: submit creates one `account_trans` row flagged AcctSetup, dated to the user bootstrap-date, carrying the initial value. `account_trans` is immutable (`004` — UPDATE/DELETE/TRUNCATE blocked for all roles), so **the discriminator is permanent per-row** and the vocabulary is load-bearing for the deferred `004` investment/event-detail expansion — hence a one-way door. **Chosen: `transaction_type text not null default 'standard' check (transaction_type in ('standard','acct_setup'))`.** Names the event class → generalizes to the deferred expansion via a one-line `CHECK` alter; sits exactly where [ADR-022](#adr-022)'s rule points (closed, code-coupled set → `TEXT+CHECK`); [ADR-024](#adr-024) supplies the clean promote-to-registry path IF a value ever needs per-value metadata (none today — routing lives in code). No speculative values. `is_reverse` stays orthogonal (a modifier, not an event class). `ALTER TABLE ADD COLUMN` is safe on the immutable table (DDL, not a row mutation — the block-mutation trigger fires on UPDATE/DELETE row ops, not DDL).

- **Alternatives (Option B chosen):** **A — `is_acct_setup boolean`:** minimal/cheapest, but a boolean-per-event-class sprawls (V2 transfer/split/dividend → column pile-up on an immutable table). **C — `transaction_type` FK → registry table:** premature per [ADR-022](#adr-022)/[ADR-024](#adr-024) — `transaction_type` behavior lives in code, no per-value metadata need yet; a registry would be an empty abstraction today (the case ADR-022 rejected for `account_type`). **D — native PG `enum`:** rejected for the same `ALTER TYPE … ADD VALUE` one-way-door reason ADR-022/ADR-024 rejected it.

**Component (3) — `is_active` reconciliation (NO DDL).** SELF-201 AC#3 names `pfin.account.inactive BOOLEAN DEFAULT FALSE` + `WHERE inactive = FALSE`. But `003` already ships `is_active boolean not null default true` — opposite polarity, same semantics, already the documented soft-delete anchor. **Reconciled: reuse `account.is_active`; aggregation filters `WHERE is_active = TRUE`; NO new `inactive` column, NO DDL** (a second inverted-polarity boolean would be a redundant, drift-prone duplicate). AC-vs-as-built correction recorded in the `012` header (mirrors the `009` header's reconciliation prose). Backend-contract note, not schema.

**§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate).** `012` introduces **zero** catalogued §10 instances; ledger stays at **2** (RT-22 + RT-26). (i) numbering RT-22 first / RT-26 second — unchanged; (ii) layer-attribution — authenticated-tier RLS/FK/column work, no infra-credential (RT-22) or `SUPABASE_SERVICE_ROLE_KEY` allowlist (RT-26) surface touched; `008`'s service_role DB-ACL posture untouched (no new service_role grant); (iii) Decision 4 linked, not restated. The matched-tenant trigger + the immutable-table column are not §10 catalogued instances (separate-ledger de-conflation, per the SELF-187 DEFINER-allowlist precedent).

**Sec gate:** **joint-review-mandatory** — three triggers: (1) [Decision 3](#adr-011) family extension incl. the canonical-#5 **numbering sign-off** (the enumeration pass); (2) immutable audit-class table modification ([Decision 2](#adr-011) — adding `transaction_type` to `account_trans`); (3) the one-way-door vocabulary. Paired QA two-tenant pgTAP battery gates merge per [ADR-023](#adr-023) C6 (owner-tag PASS / cross-tenant INSERT+UPDATE fail-closed / NULL allowed / `transaction_type` CHECK-reject / discriminator immutability). SECURITY DEFINER allowlist **unchanged (3)**; §10 ledger **unchanged (2)**.

**Cross-references:**
- SELF-201 / `supabase/migrations/012_account_sub_cat_and_acct_setup.sql` — the migration this ADR documents. Prereqs: `003` (account + RLS/GRANTs), `009` (user_taxonomy FK target + FORWARD-POINTER), `004` (account_trans immutable ledger + the mirrored matched-account trigger).
- [ADR-011](#adr-011) Decision 3 (cross-tenant FK-bypass family — **enumeration extended 4→5 here**) + [Decision 2](#adr-011) (immutable audit-class) + [Decision 9](#adr-011) (DEFINER allowlist, unchanged) + [Decision 4](#adr-011) (§10 ledger, unchanged).
- [ADR-022](#adr-022) (code-coupled→CHECK rule Option B applies) + [ADR-024](#adr-024) (promote-to-registry escape hatch; supersedes its line-65 "family 7→8" reference to this FK — see the Decision 3 amendment).
- [ADR-023](#adr-023) C6 (exposure-gating QA two-tenant pairing).
- SELF-200 (auto-Unsorted) + SELF-236 (§2.2.1.c Sub-Cat reassignment — the UPDATE path the trigger covers).

**Handoffs:** QA authors the `supabase/tests/` two-tenant pgTAP battery (Architect does not edit `tests/`); DevOps owns the CI fixture-seed row (`account.sub_cat_id` + a per-tenant `user_taxonomy` row); Backend applies `012` via `supabase migration up` after CI fixture-seed verification, then builds the SELF-201 full-stack form.

### ADR-025 — Amendment 1 (2026-07-23): `transaction_type` immutability is scoped to FACTS, not classification (per [ADR-031](#adr-031) Decision 1)

**Context.** ADR-031 Decision 1 reframes `account_trans` immutability as an **audit control over raw FACTS, not a freeze on our interpretation**. This corrects the *scope* of ADR-025 Component (2)'s justification — "`account_trans` is immutable (`004`) so the discriminator is permanent per-row … hence a one-way door." That reasoning stands for a **fact-level** `transaction_type`, but permanence is a *cost* for anything inferred (open/close, category, lot-match), which must be mutable. This amendment records the corrected scope. Security consult applies (semantics of the audit control); Sec conditional-GREEN 2026-07-23 (ADR-031 Decision 7).

**The core reframe.** Immutability of `pfin.account_trans` (`004`) is a **tamper-evidence control over the raw facts the source asserts** (amount, quantity, date, security, account). **Classification and interpretation** — the flow-class/category, open-vs-close designation, and lot-matching — do **NOT** live on the immutable ledger; they live on the mutable overlay (`account_trans_annotation`, `023`, + the ADR-031 structures) and are freely correctable. `transaction_type` remains on the immutable ledger **only because, and only insofar as, it names a FACT** (the event kind the source asserts).

**Six preserved commitments (binding on the M1-evt vocabulary refactor):**
- **(a) `transaction_type` stays frozen-per-row on the immutable ledger** — the `004` UPDATE/DELETE/TRUNCATE triple-fence is untouched; a fact-level value is permanent by design (Component (2) permanence rationale is retained *for facts*).
- **(b) TEXT + CHECK, not enum / not registry** — ADR-022's code-coupled→CHECK rule and ADR-024's promote-to-registry escape hatch continue to govern; the vocabulary widens via one-line `CHECK` alters (additive, ADR-022).
- **(c) Fact-level-only vocabulary (the new invariant)** — the `transaction_type` vocabulary admits only event kinds the source asserts (`cash_flow`, `security_buy`, `security_sell`, `security_transfer`, `basis_adjust`, `dividend_cash`, `acct_setup`, …). **No inferred value (open/close designation) may ever become a `transaction_type` value** — inferred designations live on the mutable overlay. Standing rule.
- **(d) One-way-door — settle the vocabulary before the incumbent import** — the fact-level vocabulary imprints on backfilled transactions; ratify it (F/CTO + Sec) before the export imports (ADR-031 Decision 9).
- **(e) Reverse-and-replace + the `#2` matched-account fence remain the SOLE fact-correction path** — a genuine source-fact error is corrected by an invalidate-and-replace pair (`is_reverse` + `replaces_trans_id`, `004`), never an in-place edit; interpretation errors are corrected on the mutable overlay, not here.
- **(f) SECURITY DEFINER allowlist stays 3 · §10 catalogued-instance ledger stays 3** — the vocabulary refactor and the overlay designation column are INVOKER/authenticated-tier; no privileged surface, no §10 instance (separate-ledger de-conflation, per the SELF-187 DEFINER-allowlist precedent).

**Unchanged.** ADR-025 Components (1) `sub_cat_id` matched-tenant FK (Decision-3 `#5`), (2) the AcctSetup discriminator = Option B `transaction_type`, and (3) `is_active` reuse stand as accepted. This amendment scopes the *permanence justification* of Component (2); it does not alter the discriminator choice or the migration (`012`).

**Cross-references:** [ADR-031](#adr-031) (Decisions 1, 3, 7 — the double-entry model, the event/flow-class partition, the Sec conditions); [ADR-011](#adr-011) Decision 2 (immutable audit-class) + Decision 3 (`#2` matched-account fence, the lot-match `#13`-pending instance) + Decision 4 (§10 ledger) + Decision 9 (DEFINER allowlist); [ADR-022](#adr-022)/[ADR-024](#adr-024).

---

## ADR-024 — `tax_character` promoted to a global value-registry table (Option C hybrid); routing stays hardcoded (g-1), routing-metadata columns deferred to V2 (g-2)

**Date:** 2026-07-04
**Status:** Accepted
**Phase:** Phase 6 Build Loop (SELF-231 follow-up; migration `011`).
**Approved by:** F/CTO ratified **Option C** 2026-07-04 (F/CTO-raised the question: `009` modeled `tax_character` as `text + CHECK`, which makes value-additions an `ALTER` and gives no join/lookup; F/CTO's instinct was the incumbent's lookup-table shape). Options paper: `temp/self-231-tax-character-shape-options.md`.
**Pattern:** Short pattern (single schema-shape decision + named options). Companion/light-refinement to [ADR-022](#adr-022) — does NOT overturn it.

**Decision.** `pfin.user_taxonomy.tax_character` (5 ADR-006 Axis-2 values) is promoted from the `009` inline `text CHECK (…)` to an FK into a **new GLOBAL value-registry table `pfin.tax_character`** (migration `011`). The registry uses the **value string as the natural-key PK** (`code text primary key` + `label` + `notes` + `display_order` + timestamps); `user_taxonomy.tax_character` stays `text`, nullable, now `REFERENCES pfin.tax_character(code) ON DELETE RESTRICT`. **V1 builds the value registry ONLY — NO routing-metadata columns.** The §2.5.1 `tax_character` → §2.5.2 schedule routing stays **hardcoded ([PRD flag g-1](docs/PRD/index.html#app-b-2-5-g))** in the (unbuilt) §2.5.3 engine; the data-driven **routing-metadata columns are the deferred V2 [(g-2)](docs/PRD/index.html#app-b-2-5-g) additive `ALTER TABLE ADD COLUMN`.** `domain` stays `text + CHECK` (stable binary; unchanged).

**Why Option C (hybrid).** F/CTO's challenge to `009`'s CHECK is legitimate on two axes ADR-022 itself names: (1) `tax_character` **carries per-value metadata** (the enum→schedule routing) — ADR-022's own stated trigger for promoting a taxonomy to a lookup table is "the first need for per-value metadata"; and (2) a data-driven routing table is **already the planned V2 promotion** per PRD flag (g): (g-1) hardcoded V1 → (g-2) data-driven V2. Because `009` has **zero consumers** (V1 app unbuilt, seed unrun, engine unbuilt), the conversion is a **clean `ALTER` with no backfill NOW**; the same conversion after V1 ships would rewire a built engine + live seed + built form. Option C captures the cheap-now half (FK integrity + joinable value list + a committed non-personal home for label/notes + F/CTO's table instinct) while **deferring the one genuine one-way door** — the routing-metadata **column shape** — to V2, when the engine is built and multi-state routing scope (which will likely reshape single-column routing into per-jurisdiction routing) is known. The Federal routing per value is already locked (PRD §2.5.2), so the V2 columns are not blind — but multi-state is the residual reshape Option C sidesteps.

**Relationship to ADR-022 — refines, does not overturn.** ADR-022's rule (code-coupled → CHECK; user-extensible → table) stands. `tax_character` values ARE code-coupled and closed (not user-extensible) — so ADR-022 correctly predicted CHECK. This ADR promotes it to a table not on the *extensibility* axis but on ADR-022's *own* secondary trigger — **per-value metadata** (label/notes now; routing metadata at V2). `account_type`'s ruling is **untouched**: its per-type behavior still lives entirely in code with no metadata surfaced as data, so no `account_type` lookup table is earned (its BACKLOG.md §5 V2 promote-trigger stands). The distinction is exactly ADR-022's "the contrast is the whole point": `account_type` = code-coupled, no data-metadata → CHECK; `tax_character` = code-coupled **but** metadata-carrying → registry table with routing deferred.

**Alternatives considered:**
- **A — keep `text + CHECK`, defer the whole table to V2 (g-2).** Zero work now, fully reversible, PRD/ADR-022-literal. Rejected as the primary only because it forgoes the cheap moment: the eventual text→FK conversion is paid later *with consumers attached* (built engine + live seed + built form). Entirely defensible; was the close second.
- **B — build the table NOW WITH routing-metadata columns (pull g-2 fully forward).** Matches the incumbent `tax_cat` (which carried `tax_as_ordinary` / `tax_as_cap_gain` / `tax_as_sec_1246` booleans). Rejected: commits V1 to a routing-**column shape** that is a **MEDIUM one-way door** — V2 multi-state + new enum values will likely reshape it — and deviates from the documented (g-1) V1 lean. Option C gets ~80% of B's value at ~40% of the one-way-door risk.
- **D — native PG `enum`.** Rejected for the same reason [ADR-022](#adr-022) rejected it for `account_type`: `ALTER TYPE … ADD VALUE` is a one-way door (no removal/reorder; transactional restrictions) and gives no metadata/join.

**Tenancy / RLS posture (Sec-reviewed).** `pfin.tax_character` is **GLOBAL shared-read** reference data: `RLS ENABLE` + a `using (true)` SELECT policy for `authenticated` + `grant select` — every tenant reads the same 5 rows (mirrors the incumbent `pfin.tax_cat` `USING (true)`). This is the **FIRST global `using (true)` shared-read table in the greenfield `pfin` schema** (`001`–`010` are all `users_id`-scoped) — a small posture **precedent**. No write policy / no write grant (bootstrap-seeded canonical data; adding a value is a code event, not a user data event). anon zero-grant (schema-usage denial, [ADR-023](#adr-023) C2). service_role ungranted.

**Decision-3 clearance.** The new FK `user_taxonomy (per-user) → tax_character (GLOBAL)` is **CLEARED — no matched-tenant obligation**: `tax_character` carries no `users_id`/tenant anchor, so there is no cross-tenant row to leak and nothing to validate. [Decision 3](#adr-011) family unchanged. This is distinct from the pending **SELF-201 `account.sub_cat_id → user_taxonomy(id)`** FK, which IS matched-tenant-**MANDATORY** (both sides per-user) — evaluated at that migration, not here. **[SUPERSEDED 2026-07-05 on the count only — the "7"/"7→8" figures here were the pre-resolution operational count; the SELF-201 FK landed at `012` as [Decision 3](#adr-011) CANONICAL instance #5 per [ADR-025](#adr-025) + the Decision 3 enumeration-pass resolution. The clearance verdict for THIS FK (`tax_character`, no matched-tenant obligation) is unchanged.]**

**Sec gate:** **joint-review-mandatory (advisory; low veto-likelihood)** — two triggers: (1) first global `using (true)` shared-read posture in `pfin`; (2) the Decision-3 clearance sign-off (new FK-shaped column). Paired QA pgTAP battery (shared-read + FK-integrity variant) gates merge per [ADR-023](#adr-023) C6. **§10 ledger unchanged (2 — RT-22 + RT-26); DEFINER allowlist unchanged (3).**

**Expansion path (the deferred V2 g-2 work).** V2 adds the routing-metadata columns as an additive `ALTER TABLE pfin.tax_character ADD COLUMN …` (e.g. a per-jurisdiction routing shape informed by multi-state scope) + rewires the §2.5.3 engine to JOIN instead of hardcode. Because V1 consumed no routing columns, this is additive — no reshape of consumed columns.

**Cross-references:**
- SELF-231 / `supabase/migrations/011_tax_character_registry.sql` — the migration this ADR documents; `009_user_taxonomy.sql` (the CHECK being promoted); `010_user_taxonomy_notes.sql` (orthogonal; `011` lands after it).
- [ADR-022](#adr-022) — the code-coupled-vs-user-extensible rule this ADR refines (per-value-metadata trigger); `account_type` ruling untouched.
- [ADR-006](#adr-006) Axis 2 (`tax_character` enum, 5 values + Federal routing) + [ADR-004](#adr-004) Decision C (`user_taxonomy`) — the taxonomy substrate.
- [PRD flag (g)](docs/PRD/index.html#app-b-2-5-g) (g-1 hardcoded V1 / g-2 data-driven V2 routing) + PRD §2.5.2 locked Federal routing.
- [ADR-011](#adr-011) Decision 3 (cross-tenant FK-bypass family — clearance) + [ADR-023](#adr-023) C6 (exposure-gating QA pairing).
- Incumbent `pfin.tax_cat` (`../pfin_dash/sql/schema/schema.sql`) — the global shared-read + routing-boolean precedent Option C mirrors (minus the deferred routing columns).

---

## ADR-023 — pfin data-access role-of-record: expose `pfin` to the Data API + least-privilege `service_role` grants (Option A)

**Phase:** 6 (Build Loop — SELF-196 Plaid platform; foundational data-access transport). **Approved by:** F/CTO ratified **Option A** 2026-07-03; Sec recommended A with 4 blocking + 2 structural conditions (C1–C6 below).

**Context.** Backend's SELF-196 clean-apply re-verify measured that `service_role` holds **no** `USAGE` on schema `pfin` and no table grants — the pfin ACL was `{postgres=UC, authenticated=U}`. `service_role` is `BYPASSRLS=true`, but ACL is checked independently of RLS, so bypassing RLS does not bypass schema USAGE / table GRANTs. Consequence: the [ADR-011](#adr-011) **Decision 1 "writes execute under `service_role`" pattern was non-functional pfin-wide** (couldn't read the 007 decrypt view — making its mod #1 grant inert — or write `plaid_items`/`account_trans`), yet `authenticated` already held grants (003/006) implying pfin was meant to be reachable. Separately, `pfin` was **not** in `[api] schemas` (`public, graphql_public` only), so nothing reached pfin via the Supabase Data API. The transport (how the app reaches pfin for reads+writes) was never pinned.

**Decision — Option A.** Add `pfin` to `[api] schemas`; the app reaches pfin via **supabase-js/PostgREST + native RLS** (Decision 5 RLS-default-trust): reads under `authenticated`+RLS; privileged writes under `service_role` (BYPASSRLS); workers keep their direct `TenantBoundConnection` (Lock 13, unaffected). Migration `008_pfin_service_role_grants.sql` grants `service_role` `USAGE` + **least-privilege per-table** writes (plaid_items S/I/U/D; plaid_item_state_history + plaid_sync_audit + account_trans S/I; account S — NOT blanket `GRANT ALL`; account I/U deferred to SELF-197). **`008` is the first migration making the Decision-1 read/write transport functional end-to-end.** Near-forced rationale: RT-26 exists precisely because `SUPABASE_SERVICE_ROLE_KEY` is used in web-app source = supabase-js = PostgREST, which requires pfin be exposed.

**Two-layer fence.** (outer) `anon` holds **zero** grants on every pfin relation (measured) — denied at the schema-USAGE layer; (inner) RLS on every pfin table (`users_id=auth.uid()` / `account_users`-JOIN). Exposure to the Data API changes neither.

**Alternatives considered.** **B — keep pfin API-hidden; all access via direct Postgres connections** (server routes hand-roll a pg pool + `set local role authenticated` + jwt claim): rejected — heavier, error-prone, diverges from the RLS-default-trust convenience the schema was built for. **C — DEFINER RPCs in `public` for writes + exposed views for reads**: rejected — DEFINER allowlist explosion (every write path a DEFINER fn), contradicts the narrow-allowlist discipline.

**Sec conditions (recorded).** **C1** exposure-readiness artifact (per-table RLS + policy proof) reviewed before exposure — `temp/self-196-c1-exposure-readiness.md`. **C2** anon zero-grant outer fence (measured). **C3** `plaid_items.access_token_secret_id` stays withheld from the `authenticated` grant (007 column-scoped SELECT; 008 re-asserts the REVOKE). **C4** `pfin.decrypted_plaid_access_token` stays `service_role`-only. **C5** `authenticated` write surfaces are WITH-CHECK user-write tables — **correction to the "none" premise: there are 4** (account I/U; account_trans I; reconciliation_event I; reconciliation_event_trans I), all WITH-CHECK-fenced (intended, safe under exposure). **C6 (structural, standing):** every pfin table is internet-facing the moment it is granted → the [SECURITY §4.5](docs/SECURITY/index.html#sec-4-5) two-tenant RLS battery is now **EXPOSURE-gating** — no pfin relation ships (or is granted in a migration) without a two-tenant test proving cross-tenant read+write fail closed.

**Consequences.** `supabase/config.toml` gains `pfin` in `[api] schemas`; `008` lands the grants; both this PR. `plaid_sync_audit` is deny-by-default (RLS-on, 0 policies, service_role-only) — QA asserts authenticated+anon get 0 rows. No table is `FORCE ROW LEVEL SECURITY` (not required; owner/`service_role` bypass is not an API surface). **Ledgers unchanged:** SECURITY DEFINER allowlist **3** (008 is pure grants, no function), §10 catalogued-instance ledger **2** (RT-22/RT-26 — 008's service_role reach is a DB-ACL posture change, NOT RT-26's code-layer service_role-*key* allowlist), Decision-3 family flat (no FK columns). This is a **one-way-door posture change** (pfin becomes a public-API surface) — F/CTO-ratified; Sec joint-review gates merge.

**Cross-references:** [ADR-011](#adr-011) Decision 1 (privileged-context-write) / Decision 5 (Supabase Auth + native RLS) / Decision 8 (Lock 4 Plaid, Option-2 amendment); [ADR-015](#adr-015) + [ADR-016](#adr-016) (RT-26 service_role-key allowlist); migrations `007` + `008`; [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) + [§4.5](docs/SECURITY/index.html#sec-4-5). C1 artifact: `temp/self-196-c1-exposure-readiness.md`.

**Amendment (2026-07-13 / `015` fold).** The credential store this ADR references as `plaid_items` generalizes to **`pfin.linked_source`** (ADR-027 pivot / ADR-011 Lock 4 amendment; R-14 fold). Reference updates, posture UNCHANGED: (i) the `008` least-privilege `service_role` grant model (S/I/U/D on the credential store) now applies to `linked_source` (re-established at `015` on the generalized tables — the `008` grants on the dropped Plaid tables vanish with them); (ii) **C3** `linked_source.credential_secret_id` stays withheld from the `authenticated` grant; (iii) **C4** `pfin.decrypted_source_credential` stays `service_role`-only; (iv) **C6** exposure-gating (two-tenant RLS battery before grant) binds every new `015`–`021` table. **C5 count forward-note:** the batch adds authenticated WITH-CHECK user-write surfaces (`user_asset_category` CRUD `020`, `account_trans_annotation` CRUD `021`, `eod_price` manual-valuation INSERT `019`) — each WITH-CHECK/fence-gated, safe under exposure; the exact C5 count is updated in Sec's paired SECURITY-doc pass, not pinned here. (`015` itself adds NO new authenticated write surface — `linked_source` writes are service_role-only.)

---

## ADR-022 — `account_type` as `TEXT + CHECK`, not a lookup table: code-coupled taxonomies use CHECK, user-extensible taxonomies use tables (terse pattern)

**Date:** 2026-06-30
**Status:** Accepted
**Phase:** Phase 6 Build Loop (documents a SELF-187 / `003` modeling choice already authored; no code change).
**Approved by:** F/CTO (2026-06-30 — asked why `pfin.account.account_type` is a `TEXT + CHECK` enumeration rather than a `pfin.account_type` lookup table; this records the answer, which was not written down).

**Decision.** Fixed, **code-coupled** taxonomies are modeled as `TEXT + CHECK` enumerations; **user-extensible** taxonomies get lookup tables (seeded at V1 bootstrap; CRUD UI gated to V2). `pfin.account.account_type` (SELF-187 / migration `003`) is the former — `TEXT NOT NULL CHECK (account_type IN (…))` over the 7 PRD §2.1.5 net-worth-grouping members, **not** a `pfin.account_type` lookup table.

**Why.** `account_type` is a **closed, code-coupled** set, not user-extensible reference data. Per [ADR-002 §1.9](#adr-002) each type carries bespoke V1 handling — credit-card → Plaid Transactions; loan → Plaid accounts endpoint; brokerage cash-sweep → "cash" allocation bucket; options/derivatives → "derivatives" bucket; crypto → Plaid-exchange ingest path; DRIP dividend/`buy` split — and the type drives ingest path + NAV grouping ([PRD §2.1.5](docs/PRD/index.html#story-2-1-5)) + asset-allocation bucket + income treatment. Adding a type is therefore a **code event, not a data event**: a lookup table buys nothing, because you cannot add a row without also adding the handling code that makes the type mean anything. Membership is fixed to PRD §2.1.5 verbatim — `depository`, `investment`, `retirement`, `crypto`, `manual_other`, `real_estate`, `liability` (display labels "manual/other" + "Real Estate" normalized to snake_case in `003`). `TEXT + CHECK` over a PG `enum` avoids the `ALTER TYPE` one-way-door — expansion is a one-line `CHECK` alter.

**The principle is applied deliberately, not by oversight — the user-extensible pattern IS used where it fits.** `scope` is free-text ([ADR-004 Decision B](#adr-004) — "scopes are user-defined ownership labels"); the asset Cat/Sub-Cat taxonomy is a user-scoped lookup-table set (`user_taxonomy`, [ADR-004 Decision C](#adr-004)) seeded at V1 bootstrap with the V1-seed / V2-CRUD-UI split. Those are genuinely user-extensible reference data with no per-row handling code; `account_type` is not. The contrast is the whole point: pick CHECK vs table by whether the taxonomy is code-coupled or user-extensible.

**Alternatives considered:**
- **`pfin.account_type` lookup table (FK from `account`)** — rejected for V1. It earns its keep only once a type needs **per-type metadata** (display label, icon, default `tax_treatment`, Plaid-product mapping, sort order); today all of that lives in code per §1.9, so a V1 table would be an empty abstraction (7 rows, no columns beyond the name, no row addable without code). The incumbent Google-Sheet `Account Types` reference sheet ([ADR-002](#adr-002) Master-sheet inventory) is **deliberately codified as a CHECK** in V1 rather than transcribed into a table.
- **PG `enum` type** — rejected. `ALTER TYPE … ADD VALUE` is a one-way-door (values can't be removed/reordered; transactional restrictions in some PG versions); `TEXT + CHECK` expansion is a trivially-reversible one-line alter.

**Expansion path.** Add a type today = a `CHECK` alter + the handling code the type needs anyway. Promote to a `pfin.account_type` lookup table later = a contained migration (create table + seed the 7 rows + swap `CHECK` → FK + backfill). The promotion trigger is the **first need for per-type metadata**; a V2 follow-up assessment ("promote `account_type` to a lookup table") is queued in `BACKLOG.md` §5 (PM-owned) as the deferred trigger.

**Cross-references:**
- SELF-187 / `supabase/migrations/003_account_and_account_users.sql` — the `account_type TEXT + CHECK` this ADR documents.
- [ADR-002](#adr-002) §1.9 (per-account-type handling boundaries) + [PRD §2.1.5](docs/PRD/index.html#story-2-1-5) (the 7-member NAV grouping = the CHECK membership).
- [ADR-004](#adr-004) Decision B (`scope` free-text) + Decision C (`user_taxonomy` lookup tables; V1-seed / V2-CRUD) — the user-extensible contrast.
- `BACKLOG.md` §5 V2 follow-up (promote-`account_type`-to-lookup-table assessment) — PM-owned; the deferred promotion trigger.

**No Sec gate:** documents an existing `CHECK` constraint; introduces no DEFINER / RLS / §10 / secrets surface.

---

## ADR-021 — V1 greenfield deployment posture: build on a new VPS; `pfindash.com`/cax21 is reference-only; Postgres 17 by choice

**Date:** 2026-06-29
**Status:** Accepted
**Phase:** Phase 6 entry (Build Loop) — recorded at the start of base-table migration work (SELF-187+).
**Pattern:** Short pattern (single posture decision + named options; resolves an ADR-020 carried follow-up and amends the deployment framing that [ADR-011](#adr-011) Decision 10 + Decision 17 reference).

**Context.**

V1 has been carrying an implicit assumption — inherited from the project's origin on F/CTO's incumbent infrastructure — that the live `pfindash.com` deployment (self-hosted Supabase on Coolify on the Hetzner **cax21** box in Germany, the same box that runs the `pfin_back_etl` Python ETL) is the V1 deploy target. Phase 5 close ([ADR-020](#adr-020)) surfaced the friction concretely: the `config.toml major_version = 17` carried follow-up was filed as "confirm vs cax21 prod before Phase 6 base-table work," and a read-only `SHOW server_version` against the live cax21 box on 2026-06-29 returned **15.8** — a mismatch against `supabase/config.toml` line 42 (`major_version = 17`). Under the Supabase-CLI "local `config.toml` must match the linked remote" rule, that mismatch would be a defect *if* cax21 were a remote we depend on.

F/CTO resolved the framing by **decision rather than measurement**: V1 is **greenfield**, built from scratch on a **new virtual server** at deploy time. The incumbent `pfindash.com`/cax21 deployment is a **reference, not a deployment dependency** — F/CTO is comfortable tearing down everything on `pfindash.com` and standing up a fresh instance when V1 is ready to ship. Under this posture the cax21 `15.8` measurement is **moot**: there is no remote we depend on yet, so the CLI match-rule does not bind us, and **Postgres 17 is the chosen forward target by choice** (`config.toml` line 42 is therefore correct *by intent*, not by prod-match). The from-scratch stand-up will be documented in **the deployment runbook** (`docs/deployment-runbook.md`, exact path per DevOps — skeleton drafted in parallel at this entry).

The load-bearing meta-principle this ADR exists to capture: **do not rely on a working existing deployment.** Every V1 artifact, migration, and CI fence is authored to stand up a fresh environment from repo state alone.

### Decision — Option A: greenfield from scratch on a new VPS; incumbent is reference-only; PG 17 by choice

V1 deploys to a **new, clean virtual server** provisioned at ship time, from repo state alone, per the deployment runbook. `pfindash.com`/cax21 is retained as **reference material only** (architecture precedent, the `pfin_back_etl` source now in-repo at `workers/etl/` per [ADR-019](#adr-019), and historical config) and carries **no runtime or data dependency** for V1. Postgres **17** is the forward database target by choice; `supabase/config.toml major_version = 17` stands as correct-by-intent.

### Options considered

- **(A) Greenfield from scratch on a new VPS [CHOSEN].** Provision a clean VPS at deploy time; stand up Supabase + the V1 container topology from repo state per the runbook; pick PG 17 as the forward target.
  - *Why it fits:* Matches reality — V1 was designed (PRD/ARCH/SECURITY/migrations) as a from-scratch build, not a retrofit onto a running system. Removes the CLI match-rule constraint and the `15.8`-vs-`17` friction entirely. Lets us choose the PG major version on technical merit (17 > 15.8) rather than inheriting prod's version. Forces the deployment to be fully documented and reproducible (runbook), which is the correct V1 discipline anyway. No risk of corrupting or destabilizing F/CTO's live incumbent during V1 iteration.
  - *Cost:* A fresh stand-up is net-new operational work at ship time (provision VPS, install Coolify/Supabase, seed, configure secrets, point DNS). Requires a real deployment runbook to exist before ship (now a tracked Phase 6/7 dependency). Incumbent's accumulated config (working Coolify→Discord notification routing, env-vars, deploy history) does not carry forward automatically — it must be re-created or re-derived from repo + runbook.
  - *What it makes harder later:* Little. If F/CTO ever wants to *consolidate* onto the cax21 box later, that's a forward migration, not a reversal.

- **(B) Deploy onto / adopt the incumbent cax21 box in-place.** Treat cax21's running Supabase as the V1 remote; link the CLI to it; deploy V1 alongside `pfin_back_etl` on the existing box.
  - *Why it might be right:* Zero new-infra cost (cax21 is paid-for, €9.50/mo, with substantial headroom per the `reference_hetzner_cax21` memory); reuses the working Coolify→Discord routing and existing env-var setup; fastest path to a running V1.
  - *Cost:* Binds V1 to the incumbent's state — including PG **15.8**, which would force `config.toml` back to `major_version = 15` and forgo PG 17. Any V1 iteration risks the live incumbent (and `pfin_back_etl`'s production ingestion sharing the box). Couples V1's fate to a deployment whose history predates the project's discipline — the antithesis of "do not rely on a working existing deployment."
  - *What it makes harder later:* One-way-ish — once V1 data lives on the incumbent, *separating* it (to a clean box, or to fix the box) becomes a data migration under load.

- **(C) In-place PG 15 → 17 major-version upgrade of the incumbent.** Keep cax21 as the target but `pg_upgrade` it (or dump/restore) from 15.8 to 17 first, then deploy V1 against the upgraded box.
  - *Why it might be right:* Preserves the paid-for box while getting PG 17; reconciles `config.toml = 17` against a real remote.
  - *Cost:* A major-version upgrade of a box that's running `pfin_back_etl` in production is a high-risk operation (downtime, rollback planning, extension-compatibility audit) for **zero V1 benefit** — V1 doesn't need the incumbent's data. Highest-effort, highest-risk option; inherits all of Option B's coupling problems *plus* an upgrade hazard.
  - *What it makes harder later:* Same coupling one-way-door as (B), reached via a riskier path.

### One-way doors — F/CTO ratify status

- **The greenfield posture itself is ratified by F/CTO today (2026-06-29).** It is a *low-reversal-cost* direction: choosing not-to-depend-on the incumbent is cheap to hold and cheap to revisit (consolidating onto cax21 later would be a forward decision, not an undo).
- **Genuine one-way door #1 — PG 17 migration-authorship lock-in.** Once base-table migrations (SELF-187+) are authored against PG 17 and begin using any 17-specific or 17-default behavior, *downgrading* the forward target to 15.x would require a compatibility audit and possibly rework of authored DDL. This is the reversible-with-cost edge. **F/CTO has ratified PG 17 as the forward target by choice** — recording it here so the lock-in is explicit, not implicit.
- **Genuine one-way door #2 — destructive teardown of `pfindash.com`.** Actually tearing down the live incumbent (vs. merely not depending on it) is *destructive and irreversible* for that environment's data. F/CTO has signalled comfort with teardown, but the **execution** of teardown is an operational step to perform only at deploy time, deliberately, after confirming nothing reference-worthy is lost. Flagging it so it is never done as an incidental side-effect of V1 stand-up. (Operational; tracked alongside the W0b Coolify repoint + `pfin_back_etl` archive carried follow-up.)

### §10 attribution discipline preservation

ADR-021 introduces **zero** new catalogued §10 instances and amends **no** layer attribution. 3-axis cross-check (Path B — reference-not-absorb; [ADR-011](#adr-011) Decision 4 is linked, not restated):

- **(i) Instance-numbering.** The catalogued §10 ledger stays at its V1 commitment — RT-22 first, RT-26 second; count **unchanged at 2**.
- **(ii) Layer-attribution.** RT-22 stays the **infrastructure-credential-presence** layer — its fence is the *absence* of `SUPABASE_*` env-vars and a Postgres client in the **PDF-worker container Dockerfile**, a property of the container image regardless of which VPS hosts it. Moving the deploy target from cax21 to a new VPS is a host change, not a layer or attribution change; RT-22's CI target (the Dockerfile) is untouched. RT-26 stays the code-layer `SUPABASE_SERVICE_ROLE_KEY` allowlist fence on the V1-web-app server-side source — host-independent.
- **(iii) Verbatim-vs-paraphrase.** This ADR does not enumerate Decision 4's catalogued numbered list; it links to Decision 4 as the canonical anchor.

Sec joint-review is **not** independently required for this ADR (no auth/RLS/secrets/Plaid/financial-calc surface; §10 ledger unchanged by-construction). The §10 cross-check is recorded pre-emptively per the mandatory draft-time discipline.

### Consequences

- **Resolves the [ADR-020](#adr-020) `config.toml major_version = 17` PROVISIONAL carried follow-up** — by *decision* (greenfield + PG 17 by choice), not by measurement. The cax21 `SHOW server_version = 15.8` reading is recorded for the record and then declared moot; no `config.toml` change. (Team-lead owns the MILESTONES Pending-block update closing this follow-up; this ADR does not edit MILESTONES.)
- **Amends the deployment *framing*** referenced by [ADR-011](#adr-011) Decision 10 (greenfield-reconciliation amendment — already migration-layer-correct under greenfield) and Decision 17 / Lock 13 (the 3-container topology, whose `reference_hetzner_cax21` framing now reads as reference-only). The Lock 13 **runtime topology** (web app + PDF worker + `workers/etl/` Python ETL + monthly_report cron) is **unchanged** — it stands up on the new VPS exactly as specified; only the *host* is no longer the incumbent box.
- **ARCH §5 Deployment Topology becomes reference-only in its incumbent framing** (see recommendation below).
- **Creates a Phase 6/7 dependency:** a real deployment runbook (`docs/deployment-runbook.md`, per DevOps) must exist and be validated before V1 ship. The incumbent's working Coolify→Discord routing + env-var setup must be re-derived from repo + runbook, not assumed-inherited.
- **Reinforces the meta-principle "do not rely on a working existing deployment"** across all V1 CI fences and migrations — they must stand up a fresh environment from repo state alone.

### ARCH §5 recommendation (flag only — NOT edited in this branch)

**Recommend a follow-up ARCH §5 refresh.** The Phase-3 ARCH §5 Deployment Topology content frames deployment around the incumbent cax21 box (Hetzner ARM, Coolify, the box that also runs `pfin_back_etl`). Under ADR-021 that framing is now **reference-only**: the *topology* (3-container + cron) is correct, but the *host* is a new greenfield VPS, not cax21. Suggested scope for the refresh (own PR, Architect-led, after this ADR lands): (1) reframe the cax21 references as "reference precedent" rather than "deploy target"; (2) add a forward pointer to `docs/deployment-runbook.md`; (3) state PG 17 as the chosen DB target with the greenfield rationale; (4) re-check ARCH §5's trust-boundary inventory reads host-neutrally (it should — boundaries are container/credential properties, not host properties). This is **not touched in this branch** per the team-lead's instruction; flagged here and in the report-back for F/CTO to schedule.

### Cross-references

- [ADR-020](#adr-020) — Phase 5 close; resolves its `config.toml major_version = 17` PROVISIONAL carried follow-up by decision.
- [ADR-011](#adr-011) Decision 10 — greenfield-reconciliation amendment (migration-layer `users_id` instantiation). This ADR records the *deployment-posture* counterpart of the same greenfield reality; Decision 10 stands unchanged.
- [ADR-011](#adr-011) Decision 17 / Lock 13 — 3-container runtime topology; **runtime topology unchanged**, host reframed to a new VPS. The `reference_hetzner_cax21` framing reads as reference-only under this ADR.
- [ADR-019](#adr-019) — `pfin_back_etl` absorbed into the monorepo at `workers/etl/`; the archived `pfin_back_etl` repo and cax21 box are jointly the "reference, not dependency" precedent this ADR generalizes to the whole deployment.
- [ADR-011](#adr-011) Decision 4 — §10 catalogued-instance ledger; **unchanged by-construction** (referenced, not amended).
- `reference_hetzner_cax21` + `reference_pfin_back_etl` + `feedback_greenfield_no_existing_deployment_dependency` memories — the durable record of the reference-only reframe.
- `docs/deployment-runbook.md` (per DevOps) — the from-scratch stand-up procedure this posture depends on.

**Approved by:** F/CTO (2026-06-29 — greenfield posture + PG 17 forward-target-by-choice ratified at Phase 6 entry; the two genuine one-way doors above recorded explicitly).

---

## ADR-020 — Phase 5 close-gate + Phase 6 entry approval (terse pattern)

**Date:** 2026-06-29
**Status:** Accepted
**Approved by:** F/CTO (2026-06-29; explicit sign-off on Phase 5 exit → Phase 6 entry after the Step 9 exit-criteria walk + SELF-186 smoke-test PASSED).

### Decisions

1. **Phase 5 (Workshop Setup) ✅ Complete 2026-06-29.** All 7 WORKFLOW.md exit criteria PASS: (C1) new task assignable end-to-end without ad-hoc setup — SELF-186 demonstrated; (C2) CI passes on clean checkout — 8/8 checks green; (C3) branch protection prevents direct push to main — configured (Decision 2); (C4) agent definitions exist for all 10 roles with explicit Linear permission scope; (C5) Phase 0.5 defs refined + re-signed-off (Steps 2–3, PRs #101–#103); (C6) owner can invoke any agent by name; (C7) agent + Linear issue ID → read/work/status/comment verified end-to-end on SELF-186. Mosko extensions: §10 attribution discipline preserved (every Phase 5 surface CLEAN; no new catalogued claim — ledger stays 2 = RT-22 + RT-26; grain-count reconciliation carried); SD-15 + RT-15 implicit gaps closed (Step 4 W2/W3); BACKLOG §7 → Linear milestone-rotation rehearsal completed (Step 7); SELF-186 V1.0 first-implementation smoke-test PASSED. 9 steps landed across PRs #97–#116; `phase-5-workshop-setup` team torn down 2026-06-25 per [ADR-003](#adr-003).

2. **Branch protection on main configured (closes exit-criterion C3).** Discovered **absent** during the Step 9 exit walk — "branch protection on main" was a stated convention (`CLAUDE.md`) that had never been enforced. Configured via `gh api`: require a PR before merge + the 7 always-run `security-scan` status checks (strict / branches-up-to-date) + **0 required approvals** (solo-dev — a required human review is impractical when the author can't approve their own PR) + **`enforce_admins = true`** (no direct push to main, including F/CTO; self-merge after green CI). The path-filtered `db-tests` (pgTAP) job is intentionally **not** a required context — requiring it globally would deadlock doc-only PRs that don't trigger it; it still runs + is reviewed on migration PRs. Validated live: SELF-186 (first `feature/*` PR) merged through the gate.

3. **SELF-186 greenfield reconciliation — Option A ratified ([ADR-011 Decision 10 amendment](#adr-011)).** The literal "rename `tenant_id` → `users_id` across V1 user-data tables" was unsatisfiable: the incumbent `pfin` schema has no `tenant_id` (20 tables, none), and the rename was a naming decision already swept to `users_id` in the Step-4-close prose; the "Phase 3 DDL rename" never happened (greenfield). `001_pfin_foundation.sql` therefore **instantiates** the `users_id = auth.uid()` convention rather than renaming built DDL: `create schema pfin` + `pfin.fn_refresh_updated_at()` SECURITY DEFINER helper (1 of the 2 locked Decision-9 allowlist entries; `set search_path = ''`). Sec joint-review GREEN. Options B (rename against incumbent snapshot) + C (schema-only, vacuous Sec leg) rejected.

4. **Phase 6 (Build Loop) entered 2026-06-29.** Meta-process M2 (Implement + Verify) continues per [ADR-009](#adr-009) Decision 2. Phase 6 consumes the locked PRD + ARCH + SECURITY + DESIGN + the Linear V1.0–V1.4 inventory + BACKLOG §7, executing V1 issues through the now-validated build loop (Architect/Backend/Frontend → QA/Sec joint-review → DevOps CI → branch-protected PR → F/CTO ratify; milestone-rotation per [ADR-017](#adr-017) Decision 2). First foundational migration `001_pfin_foundation` is live; SELF-187+ base-table migrations build on it.

### Carried follow-ups (into Phase 6)

- **`fence-tbc` integrity gap** (Sec Step 8 finding) — non-enforcing on the real ETL tree; fix when TBC lands at Wave 6 (folded into ETL CI coverage).
- **§10 attribution-streak grain reconciliation** (MILESTONES "25+/31+" grain vs fresh Sec count — pick one canonical grain).
- **`config.toml major_version = 17` PROVISIONAL** — confirm vs cax21 prod before Phase 6 base-table work.
- **BLS ARCH↔code reconcile** (Architect) — ARCH §5 "free/open" vs ETL code requiring `BLS_API_KEY`.
- **`role:qa` + `role:devops` Linear labels absent** — create at each role's first Phase 6 issue (F/CTO action); 3 mosko issues in NO-PROJECT bucket (cosmetic).
- **W0b operational** — F/CTO-executed Coolify repoint + `pfin_back_etl` archive.

### Cross-references

- [ADR-018](#adr-018) — Phase 4 close + Phase 5 entry approval (the prior phase-gate this mirrors).
- [ADR-003](#adr-003) — team teardown convention (`phase-5-workshop-setup` torn down 2026-06-25).
- [ADR-009](#adr-009) Decision 2 — Phase 6 outer category; M2 (Implement + Verify) continues.
- [ADR-011](#adr-011) Decision 10 amendment — SELF-186 greenfield reconciliation; Decision 9 — the 2-entry DEFINER allowlist `001` instantiates from.
- [ADR-017](#adr-017) Decision 2 — milestone-rotation (rehearsed at Step 7; operational at first real rotation).
- WORKFLOW.md Phase 5 Lessons learned subsection (8 durable patterns codified at this close).

---

## ADR-019 — Polyrepo → monorepo topology consolidation; `pfin_back_etl` absorbed at `workers/etl/`

**Date:** 2026-06-16
**Status:** Accepted
**Phase:** Phase 5 Step 4 W0 (monorepo topology migration; predecessor W1 — PR #104 mosko-fintech + paired PR #14 pfin_back_etl — both merged)
**Pattern:** Short pattern (single decision; topology consolidation that amends — does not invalidate — [ADR-011](#adr-011) Decision 17 / Lock 13)

**Context.**

[ADR-011](#adr-011) Decision 17 / Lock 13 locked the V1 hybrid background-worker topology at 2026-05-26 with `pfin_back_etl` as an **incumbent sibling repo** — its own GitHub repo at `github.com/richmosko/pfin_back_etl` + its own Coolify application + (as of Phase 5 Step 4 W1) its own paired CI workflow carrying the production-mode `TenantBoundConnection` (TBC) grep fence. Phase 5 Step 4 W1 (PR #104 + paired PR #14) operationalized the cross-repo TBC fence: production-mode ran against the actual Python tree in `pfin_back_etl`'s CI; inversion-mode (golden-fixture, expects-violation) ran against the vendored fixture in mosko-fintech's CI; the two were kept in sync by the **paired-PR convention** + a vendored-copy header banner — both F/CTO-discipline-at-paired-PR-time, with no automated drift detection at V1.

W1 ran that pattern end-to-end and proved its durable cost: every Python-source change requires a paired PR; vendored-copy drift is caught only by F/CTO attention at paired-PR-time; Phase 5 Step 4 W2 + W3 + Phase 6 build-loop would compound the friction across all future Python-source touches. W0 retires the friction by-construction by folding the `pfin_back_etl` source into the mosko-fintech monorepo at `workers/etl/` (sibling to the existing `workers/pdf-render/`). The fold is a **fresh import** (working tree at `origin/main` `f047e88`; NOT a git-subtree merge — history-preservation cost exceeds benefit at V1 scale per F/CTO ratify on shape β.2); the `pfin_back_etl` GitHub repo stays archived as historical reference.

This is a **one-way door** on the ADR-home axis: every downstream surface (ARCH §5/§6/§6.1, devops.md, `scripts/ci/README.md`, future PRs) links to wherever this decision lives as canonical; moving it later requires a migration-pass across every linked surface. F/CTO ratified the five sub-decisions below against the Architect leans.

### Decision — consolidate to monorepo at `workers/etl/`; record via new short-pattern ADR; CI consolidates to one dual-mode TBC job

The migration is a **source-organization** change, not a **runtime-topology** change. The five ratified sub-decisions:

1. **ADR shape → Option C (hybrid).** This decision lands as new short-pattern **ADR-019** (clean, independently-linkable canonical home for the topology-shift meta-decision); [ADR-011](#adr-011) Decision 17 gains a one-sentence reciprocal annotation pointing here. The **new-ADR-extends-a-prior-Decision-17-sub-territory** relationship follows the [ADR-015](#adr-015) precedent — ADR-015 extends Decision 17 without invalidating it via a **one-directional** cross-reference housed inside ADR-015 (Decision 17 itself was never annotated under ADR-015). The reciprocal **Decision 17 → ADR-019 back-annotation is a new navigation aid introduced at W0**, not part of the ADR-015 precedent: W0 adds the back-pointer so a reader landing on the closed Decision 17 finds the topology-consolidation reference in place. Option A (new ADR only) was rejected as leaving Decision 17 silently stale; Option B (in-line amendment to the closed Decision 17, no new ADR) was rejected per the [ADR-016](#adr-016) precedent against re-opening a closed canonical anchor.

2. **CI restructure → Option A (extend the existing job to dual-mode).** mosko-fintech's `security-scan.yml` `fence-tbc-inversion` job is renamed `fence-tbc` and gains a production-mode step running the TBC grep fence against `workers/etl/`, alongside the existing inversion-mode step — production + inversion in **one job**, matching the established `fence-rt22` pattern (production-mode + inversion-mode in a single job). Both modes run on every PR; fail-closed discipline preserved. Option B (a new sibling production-mode job) was rejected as introducing a "one job per mode" variant that diverges from the established RT-22 convention without a forcing function. The `pfin_back_etl`-side `security-scan-tbc.yml` workflow retires (the paired-PR pattern retires with it).

3. **§10 attribution-annotation surface → Option A (ADR-019 § only).** The topology-shift annotation lives in this ADR's "§10 attribution discipline preservation" subsection below; **[ADR-011](#adr-011) Decision 4 is NOT amended.** W0 is structurally not an attribution-drift catch (the case Decision 4's maintenance-annotation CHANGELOG was designed to absorb) — it is a topology shift that preserves Decision 4's content by-construction. Option B (append a bullet to Decision 4's CHANGELOG annotation) was rejected as conflating topology-shift annotations with drift-catch entries; Option C (both surfaces) was rejected on the same sync-cost grounds as sub-decision 1's Option B. This mirrors the [ADR-016](#adr-016) shape: §10 catalogued-instance ledger stays UNCHANGED by-construction; the new ADR annotates discipline preservation in-§.

4. **Coolify config-change → Option A (in-place reconfigure; delete-recreate named fallback).** Operational (W0b); not part of this ADR's artifact scope. The existing `pfin_back_etl` Coolify application is reconfigured in-place to point at `github.com/richmosko/mosko-fintech` with **Base Directory** `workers/etl/`, preserving deploy history + env-vars (5+ secrets stay in place). DevOps drafts the numbered recipe; delete-recreate is the named fallback if the source-repo-change UI surfaces undocumented behavior.

5. **`pfin_back_etl` repo decommissioning → Option A (minimal archive).** Operational (W0b); not part of this ADR's artifact scope. README banner pointing at the monorepo + GitHub archive-flag (read-only mode) + no visibility-tier change.

### §10 attribution discipline preservation

ADR-019 introduces **zero** new catalogued §10 instances. [ADR-011](#adr-011) Decision 4 is referenced here by canonical link only — its catalogued numbered list, Privileged-context-surfaces bullet, and three-layer composition definitions are not restated (Path B — drop-enumeration-let-link-carry, per the frame that this ADR REFERENCES rather than ABSORBS Decision 4's canonical content). Cross-check across the three drift axes:

- **(i) Instance-numbering.** Decision 4's catalogued §10-instances list stays at its V1 commitment — RT-22 first, RT-26 second; the ledger remains fully discharged at V1 per the 2-instance original commitment recorded at [ADR-018](#adr-018) / Phase 4 close. W0 adds no catalogued instance.
- **(ii) Layer-attribution.** RT-22 stays the infrastructure-credential-presence layer (its CI target is the PDF-worker Dockerfile — unchanged by W0). RT-26 stays the code-layer fence on the V1-web-app server-side source surface (`src/**` + repo root — unchanged by W0). TBC stays at the Privileged-context-surfaces bullet as the code-layer `TenantBoundConnection` class + CI grep fence — **explicitly not a catalogued §10 instance**; W0 only retargets its CI invocation from a cross-repo Python tree to the monorepo path `workers/etl/`, which is a path change, not a layer or attribution change.
- **(iii) Verbatim-vs-paraphrase.** This ADR does not enumerate Decision 4's catalogued numbered list verbatim; it links to Decision 4 as the canonical anchor (Path B).

Streak: the §10 attribution-discipline CLEAN streak (26+ consecutive surfaces at W1 close) extends to 27+ at W0 close by-construction. Sec joint-review verifies the three-axis cross-check at W0a-3 lock.

### Considered alternatives

- **(a) Continue the cross-repo paired-PR pattern** — rejected: W1 proved the friction (every Python-source change needs a paired PR; vendored-copy drift detection is manual); Phase 5 Step 4 W2 + W3 + Phase 6 build-loop would compound the cost across all future Python-source touches.
- **(b) Git-subtree merge (preserve `pfin_back_etl` history in the monorepo)** — rejected per F/CTO ratify on shape β.2: history-preservation cost exceeds benefit at V1 scale; fresh import is simpler and the old repo stays archived as the historical reference.
- **(c) Amend [ADR-011](#adr-011) Decision 17 in-line without a new ADR** — rejected per the [ADR-016](#adr-016) precedent: re-opening a closed canonical anchor risks discipline drift; a new short-pattern ADR is the established convention for amendments that extend without invalidating the prior Decision (the exact shape [ADR-015](#adr-015) set).

### Cross-references

- [ADR-011](#adr-011) Decision 17 / Lock 13 — the hybrid 3-container topology this ADR consolidates the source-organization of. **UNCHANGED structurally**; carries a one-sentence annotation pointing here. The 3-container runtime topology + full Lock 13 mod inventory (#1–#10) all stand.
- [ADR-011](#adr-011) Decision 4 — §10 defense-in-depth ledger. **UNCHANGED by-construction**; this ADR's "§10 attribution discipline preservation" subsection carries the cross-check; Decision 4 is referenced by link only.
- [ADR-015](#adr-015) — SvelteKit framework lock; the precedent for a **new ADR extending a prior Decision 17 sub-territory** while the topology + Lock 13 mod inventory stand unchanged. ADR-015's cross-reference to Decision 17 is **one-directional** (housed inside ADR-015; Decision 17 was not annotated). ADR-019 follows that extends-relationship; the reciprocal **Decision 17 → ADR-019 back-annotation is a new navigation aid W0 introduces**, not part of the ADR-015 precedent (sub-decision 1 Option C).
- [ADR-016](#adr-016) — RT-26 allowlist enumeration; the precedent for "rejected an α Decision-4 amendment in favor of a new short ADR that annotates discipline preservation in-§ while Decision 4's catalogued ledger stays UNCHANGED." ADR-019 follows this shape (sub-decisions 1 + 3).
- [ADR-017](#adr-017) — compact-ledger conventions; W0 close lands one CHANGELOG `vX.YY` entry + one 1-sentence MILESTONES Recent-activity pointer per Decision 1.
- WORKFLOW.md Phase 5 Step 4 — W0 insertion + sub-wave restructure (W0 → W1 already-merged → W2 → W3).
- `reference_pfin_back_etl` memory — updated to note the source now lives in-repo at `mosko-fintech/workers/etl/` (no longer a sibling repo); historical-reference framing for the archived `pfin_back_etl` GitHub repo preserved.

### Consequences

**Unchanged by ADR-019:**

- 3-container runtime topology on Hetzner cax21 (V1 web-app + PDF worker + Python ETL container + monthly_report cron container). Monorepo is a source-organization change; the runtime stays three separate containers / three Dockerfiles / three processes.
- All Lock 13 mods (#1–#10) — PDF-render contract, PDF-worker zero-DB-isolation, TBC, same-transaction audit-log, Puppeteer/audit hardening posture.
- §10 catalogued-instance ledger ([ADR-011](#adr-011) Decision 4) — RT-22 first, RT-26 second; TBC at the Privileged-context-surfaces bullet; numbered list unchanged.
- Container **display name** `pfin_back_etl` (the Coolify container / runtime identity) — only its **source location** changes.
- ARCH §5 trust-boundary inventory composition (the rows stand; the Python-source-path framing retargets to `workers/etl/`).

**Changed by ADR-019:**

- Source location: `github.com/richmosko/pfin_back_etl/` → `mosko-fintech/workers/etl/`.
- CI pattern: cross-repo paired-PR (mosko-fintech W1 + `pfin_back_etl` paired PR) retires; single-PR shape going forward. TBC fence runs production-mode + inversion-mode in one `fence-tbc` job in mosko-fintech `security-scan.yml`; `pfin_back_etl`-side `security-scan-tbc.yml` retires.
- `scripts/ci/README.md` retires the `Cross-repo TBC posture` subsection (replaced with a shorter `Single-repo TBC posture (post-W0)` subsection); the §10 catalogued-instance ledger cross-reference subsection + the RT-22 / RT-26 subsections stay unchanged. The vendored-copy + source-of-truth-header conventions retire (no second repo to vendor into).
- Coolify application reconfigures (in-place; delete-recreate fallback) to point at the monorepo with Base Directory `workers/etl/` (W0b operational).
- `pfin_back_etl` GitHub repo archives with a README banner pointing at the monorepo (W0b operational).

**Sequencing:** W0 lands before W2 (SD-15 `fn_mask_acct_number` migration — topology-agnostic) + W3 (QA two-tenant + parity fixtures + RLS battery — RT-15 parity-fixture framing retargets from "`pfin_back_etl` test-environment posture" to "`workers/etl/` test-environment posture" at W3 ratify; no fixture-shape change). Landing W0 first means W2 + W3 reference post-migration `workers/etl/` paths directly.

**Approved by:** F/CTO (2026-06-16 — ratified all five sub-decisions against the Architect leans, per the W0 monorepo-migration plan ratify gate; Sec joint-review on the Decision 4 cross-check + ADR-019 at W0a-3 lock).

---

### Amendment (2026-07-17 / Phase 6 Build Loop — provider-sync worker: additive Node/TS sibling `workers/provider-sync/`, direct-Postgres transport)

**Status:** Accepted. F/CTO ratified Option B (Node/TS) + the direct-Postgres transport condition 2026-07-17, per `temp/provider-sync-worker-devops-memo.md` (DevOps) + `temp/provider-sync-worker-design.md` §5 (Architect). Sec-consult mandatory on the net-new Node TBC-equivalent fence + the transport (RT-26-confinement) decision.
**Discipline:** dated **extend**, not a rewrite (the ADR-015 supersede/extend shape ADR-019 itself follows). The accepted decision + its five sub-decisions + the §10-preservation subsection above stand UNCHANGED; this amendment **extends** the runtime topology from 3 → 4 background-worker containers and records the first DB-touching Node worker. **This is additive — NOT a re-litigation of the polyrepo→monorepo consolidation.**

**What this amendment records:**

1. **Additive sibling worker.** `workers/provider-sync/` (Node/TS) joins `workers/etl/` (Python) + `workers/pdf-render/` (Node) as a **third worker module**, deployed as a **4th Coolify unit** — native-cron-triggered, independent deploy/restart/resource ceiling, Discord failure routing (the same mechanism as the `workers/etl/` poll + the `monthly_report` Gate F cron). It hosts the ADR-027 provider-sync ingest worker (Plaid + SimpleFIN adapters → the shipped `pfin` landing tables; design memo `temp/provider-sync-worker-design.md`).

2. **Correction to the design-memo "2nd language" framing.** Option B does **NOT** introduce a second worker language — `workers/pdf-render/` is already Node, so the monorepo is already bilingual. What B newly introduces is the **first *DB-touching* Node worker** (`pdf-render` deliberately has **zero** DB reach — that is exactly the RT-22 posture). *That* — a Node worker that reaches `pfin` — is the precise trigger for the new Node TenantBoundConnection-equivalent fence in (4).

3. **DIRECT-POSTGRES transport (the load-bearing constraint — keeps RT-26 confined; NO ADR-016 amendment).** `workers/provider-sync/` writes to `pfin` via a **direct Postgres driver** (`postgres`/`pg` + `PFIN_DB_PASSWORD`) through a **Node TenantBoundConnection-equivalent** (`TenantBoundClient`) that binds `users_id` in code per [Lock 13 mod #3](#adr-011) / [Decision 1](#adr-011) clause (d) — it does **NOT** use `@supabase/supabase-js` + `SUPABASE_SERVICE_ROLE_KEY`. This mirrors the incumbent `workers/etl/` Python posture exactly. **Consequence:** the worker never touches the literal `SUPABASE_SERVICE_ROLE_KEY`, so **RT-26 stays confined to `api/src/`** ([SECURITY §4.1](docs/SECURITY/index.html#sec-4-1); [ADR-016](#adr-016)) — **no RT-26 allowlist entry, no ADR-016 amendment.** (Adding a 4th+ RT-26 allowlist surface would be a deliberate one-way-door per ADR-016 D2; the transport choice avoids it by-construction.) *Role note:* the worker's DB role holds the `service_role` **grants** the `pfin` substrate already issues (e.g. the `020` `pfin.asset` INSERT/SELECT grant, the `018`/`019` snapshot + `eod_price` grants) — RT-26 fences the SERVICE_ROLE_**KEY** (the PostgREST API credential), not the `service_role` Postgres role reached via a direct password connection.

4. **TBC discipline generalizes to a second implementation (the one net-new security surface).** [Lock 13 mod #3](#adr-011)'s tenant-binding-in-code discipline is now satisfied by **two enforced implementations, one per DB-touching worker language**: Python `TenantBoundConnection` (`fence-tbc`, production-mode over `workers/etl/`) + Node `TenantBoundClient`-equivalent (**net-new `fence-tbc-node`**, production-mode over `workers/provider-sync/src/`). Each is a fail-closed **dual-mode** fence (production + inversion, paired golden-fixture) mirroring the established `fence-tbc` / `fence-rt22` shape. `fence-tbc-node` is authored by **DevOps** and is the **entire net-new CI security surface** of this amendment; **Sec-consult mandatory** (it touches TBC mechanics). No DB-touching worker code merges before its fence is CI-enforced (with the paired inversion fixture proving it catches a real violation).

5. **Rationale for a separate worker over extending `workers/etl/` (ranked).** (i) **Operational isolation (primary driver):** per-user provider account sync (Plaid/SimpleFIN — tenant-scoped, credential-lifecycle-bearing, its own cadence) and system-wide economic-data batch ETL (BLS/FMP) are two genuinely-independent ingest concerns. A dedicated container gives provider-sync an independent deploy/restart/failure boundary — a provider-sync bug cannot take down the FMP/BLS poll, and vice versa. One-worker-one-purpose is the boring-correct topology; folding them into `workers/etl/` (the CI-cheaper Option A) would couple them at the deploy/restart/failure boundary — the real hidden cost. (ii) **Engineering quality:** Node/TS gives the Plaid first-class Node SDK + SimpleFIN plain-fetch, **shares the adapter DTO types with the SvelteKit app** (one source of truth, less drift), and **reuses the proven `.mjs` provider probes** (`temp/plaid-test.mjs` / `temp/simplefin-test.mjs`) directly. The 4th container is negligible on the greenfield host (cax21-class: 8 vCore / 16 GB, ample headroom). Option A (extend Python `workers/etl/`) was the CI-cheaper fallback (no `fence-tbc-node`, no ADR-019 amendment) but was rejected on the coupling + re-implement-in-Python costs.

6. **Secrets-manifest (DevOps-operational).** `SIMPLEFIN_TOKEN` enters `secrets-manifest.yml` as a **`production_only`** entry (Plaid + DB-password secrets already enumerated); any QA test analogue takes a distinct `SIMPLEFIN_TOKEN_TEST` name in `ci_only` (distinct-naming keeps the sets disjoint; `secrets-nonoverlap` runs unchanged).

**Topology delta:** background-worker runtime containers **3 → 4** (web app + `workers/etl/` Python ETL + `workers/pdf-render/` Node PDF + **`workers/provider-sync/` Node provider-sync**). This **extends** the "Unchanged by ADR-019: 3-container runtime topology" consequence above (dated 2026-06-16) — the reader landing on [ADR-011](#adr-011) Decision 17 / Lock 13 reaches this extension via the existing Decision 17 → ADR-019 back-annotation (no new edit to the closed Lock 13 anchor — the [ADR-016](#adr-016) don't-reopen-a-closed-anchor precedent; the container count is extended here in ADR-019 where the topology-consolidation home already lives). All Lock 13 mods (#1–#10) stand; RT-22's PDF-worker zero-DB posture is UNCHANGED and — flagged explicitly — **does NOT extend to `provider-sync/`** (a DB-touching worker is the opposite posture; pointing the zero-DB Dockerfile audit at it would be a category error).

**§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011); do NOT restate the catalogued numbered list; Decision 4 read verbatim before drafting).** This amendment introduces **zero** new catalogued §10 instances; the ledger stays at **2** (RT-22 + RT-26).
- **(i) Instance-numbering** — RT-22 first, RT-26 second; unchanged.
- **(ii) Layer-attribution** — RT-22 stays the infrastructure-credential-presence layer (PDF-worker Dockerfile; unchanged — and explicitly does NOT extend to the DB-touching provider-sync worker). RT-26 stays the code-layer `SUPABASE_SERVICE_ROLE_KEY` fence **confined to `api/src/`** — the direct-Postgres transport (3) is precisely what keeps it there (no `workers/` RT-26 surface). TBC stays at the **Privileged-context-surfaces bullet** as the tenant-binding code-layer discipline + CI grep fence — **explicitly NOT a catalogued §10 instance**; it is now realized by two implementations (`fence-tbc` + `fence-tbc-node`), a count-of-implementations change, NOT a new catalogued instance or a layer re-attribution (identical de-conflation to W0's "TBC explicitly not a catalogued §10 instance").
- **(iii) Verbatim-vs-paraphrase** — Decision 4 is linked, not restated; this amendment is not the canonical anchor.

**Ledgers:** §10 catalogued-instance ledger **stays 2** · SECURITY DEFINER allowlist **stays 3** · Decision-3 family **unchanged** (this amendment authors no migration and no schema — the `020` `pfin.asset` grant is its own migration/PR). **No ADR-016 amendment** (RT-26 confined by the transport choice). The §10 attribution-discipline CLEAN streak extends by-construction at this amendment's lock.

**Cross-references (this amendment):**
- [ADR-027](#adr-027) — the provider-sync ingest abstraction this worker implements; `temp/provider-sync-worker-design.md` (the OWD-1/OWD-2 build memo) + `temp/provider-sync-worker-devops-memo.md` (the location/language + CI-fence analysis this amendment ratifies).
- [ADR-011](#adr-011) Decision 17 / [Lock 13](#adr-011) mod #3 — the hybrid worker topology (3 → 4 containers) + the TBC discipline (now two enforced implementations). [Decision 1](#adr-011) clause (d) — tenant-binding-in-code for the privileged writer. [Decision 4](#adr-011) — §10 ledger, unchanged.
- [ADR-016](#adr-016) — RT-26 allowlist; **not amended** (transport keeps RT-26 confined to `api/src/`). [SECURITY §4.1](docs/SECURITY/index.html#sec-4-1) — the RT-26 allowlist home.
- `020_asset_global_write_path.sql` — the `pfin.asset` service_role grant the worker consumes (separate migration/PR); `reference_pfin_back_etl` memory — the direct-Postgres `TenantBoundConnection` precedent this Node worker mirrors.

**Approved by:** F/CTO (2026-07-17 — Option B Node/TS + direct-Postgres transport, against the DevOps + Architect leans). Sec-consult mandatory on `fence-tbc-node` + the RT-26-confinement transport decision; DevOps authors `fence-tbc-node` + the Coolify 4th-unit config; Architect owns this amendment's authorship.

#### Login-role note (2026-07-17, same day — capability-verified addendum to item 3)

**Status:** Accepted — F/CTO ratified **(b) connect as `authenticator`** + Sec conditions C1–C4 (Sec veto GREEN-with-conditions: recommend (b); (c) declined as day-one, tracked below as V1.x hardening). Architect capability-smoke GREEN on the local stack (migrations `001`→`020`), per `temp/provider-sync-login-role-capability.md`.

**What this pins.** Item 3 above named "the worker's DB role" without fixing WHICH Postgres **login** role opens the direct-Postgres connection. `fn_ingest_transactions` (`017`) is SECURITY INVOKER / RLS-enforced / `authenticated`, while the snapshot + `eod_price` + global-asset writes (`018`/`019`/`020`) are `service_role`-privileged — so `TenantBoundClient` must `SET LOCAL ROLE` to **both** `authenticated` (INVOKER ingest) and `service_role` (privileged path) on one connection. The pinned **sole login role for provider-sync is `authenticator`** — Supabase's `NOINHERIT` PostgREST broker (member of `anon`/`authenticated`/`service_role`), whose entire purpose is per-request `SET ROLE`. Env-contract: `PFIN_DB_USER=authenticator` + `PFIN_DB_PASSWORD` = the authenticator password (`production_only`; DevOps owns the `.env.example` / secrets-manifest delta). This resolves the `SET LOCAL ROLE` dual-mode requirement ADR-019 left unpinned ("PFIN_DB_PASSWORD + Node TenantBoundClient" named no login role).

**Why `authenticator` over (a) `GRANT authenticated TO service_role`.** `service_role` is `NOLOGIN` + no password + `rolinherit`/`BYPASSRLS` (measured on the Supabase-managed role set) — so (a) additionally requires turning the BYPASSRLS role into a password-accepting `LOGIN` role (attack-surface expansion) and runs **privileged-by-default** (a forgotten `SET LOCAL ROLE` downgrade would run with RLS bypassed — fail-open). `authenticator` is `NOINHERIT` → **fail-closed** (zero ambient privilege until an explicit `SET ROLE`) with zero role-graph mutation. Smoke on one `authenticator` connection: INVOKER ingest under `authenticated` (RLS WITH CHECK + the `017` #11-fence — the novel global-OR-matched-tenant `security_id` gate — both fail closed cross-tenant), privileged `holdings_checkpoint`/`eod_price` writes under `service_role`, and the NaN / `qty_requires_security` CHECKs + the security fence all fire role-agnostically under the `service_role` RLS-bypass.

**Write-identity UNCHANGED (x-ref [ADR-023](#adr-023)).** Privileged writes still execute **AS `service_role`** via `SET LOCAL ROLE`; `service_role` remains the write role-of-record. Only the **connection/login** role is pinned here — a distinct axis from the write identity. No code change to `TenantBoundClient.ts` (it already `SET LOCAL ROLE`s both paths); no migration, no DDL for (b).

**§10 3-axis (Path B — reference [Decision 4](#adr-011); catalogued numbered list NOT restated; Decision 4 read verbatim before drafting).** Zero new catalogued instances. **(i) Instance-numbering** — RT-22 first, RT-26 second; untouched. **(ii) Layer-attribution** — a Postgres **login-role name** in an env var is not the `SUPABASE_SERVICE_ROLE_KEY` literal, so RT-26's `api/src/`-confined code-layer fence + `scripts/ci/fence-tbc-node.sh` LEG-2 zero-hit are unaffected; RT-22 (PDF-worker Dockerfile) untouched; TBC stays the Privileged-context-surfaces bullet. **(iii) Verbatim-vs-paraphrase** — Decision 4 linked, not restated; this note is not the canonical anchor.

**Ledgers (correct baseline, all flat):** §10 catalogued-instance ledger **stays 2** (RT-22 + RT-26) · SECURITY DEFINER allowlist **stays 3** (a login role is not a DEFINER function) · Decision-3 family **stays 8 operational** (per (p) above: `019`'s #11 fence took the family 7→8; the canonical-body count stays 4 pending the reconciliation pass) — this note authors no FK-shaped column, so the family is flat.

**Condition C2 — V1.x hardening follow-up (tracked here in-repo; no separate PR).** A dedicated `NOINHERIT` login role **`pfin_worker`** (member of `authenticated` + `service_role` only — drops `authenticator`'s inert `anon` membership; decouples the worker's credential from PostgREST's authenticator-password rotation) is the tighter end-state. Declined as day-one (`authenticator` satisfies the capability with zero new surface); **forward-flagged as V1.x hardening — Sec-joint-review-mandatory when adopted** (authoring a new role is a role-graph change + needs a managed password).

**Approved by:** F/CTO (2026-07-17 — (b) `authenticator` + Sec conditions C1–C4, against the Architect lean). Sec veto check GREEN-with-conditions; Architect authors this note now + (on C2 adoption) the `pfin_worker` role migration under Sec joint-review. Lands in the provider-sync worker PR alongside the DevOps `.env.example` / secrets-manifest delta; Architect + Sec joint-review gates merge.

---

## ADR-018 — Phase 4 close-gate + Phase 5 entry approval (terse pattern)

**Date:** 2026-06-04
**Status:** Accepted
**Approved by:** F/CTO (2026-06-04; in-band "ratify both" after Step 9 synthesis surfaced Phase 4.5 disposition + V1.0 first-implementation-issue identification gates).

### Decisions

1. **Phase 4 (Project Scoping) ✅ Complete 2026-06-04.** All 6 WORKFLOW.md exit criteria PASS + mosko-specific §10 SD+RT coverage extension DISCHARGED per Architect Task #30 verdict at `temp/phase-4-sd-rt-coverage.md` (21/21 active SD + 25/25 active RT covered; 0 hard gaps; 2 implicit gaps SD-15 + RT-15 routed to Phase 5 Step 4 by-construction closure). 107 V1 issues total decomposed (89 Linear SELF-181 → SELF-269 V1.0–V1.4 + 18 BACKLOG.md §7 V1.5 + V1.final). Cumulative PRD §2 trace 32/32 stories. Both V1 catalogued §10 instances (RT-22 + RT-26) ship V1 per [ADR-011 Decision 4](#adr-011) catalogued-instance ledger; **Decision 4 catalogued-instance ledger fully discharged at V1 per the 2-instance original commitment**. Settings area ramp 4/4 closed; Lock 14 family 5/5 closed.

2. **Phase 4.5 (Agentic Flow Ramp) SKIPPED.** F/CTO ratified Architect recommendation: skip Phase 4.5 because Phase 4 execution materially exercised the agentic loop (89 Linear issues + 18 BACKLOG.md §7 entries + 4 one-way-door ratify gates + 3 cross-draft conflicts resolved + 5 brief-drift catches + 2-teammate independent verification at boundaries — all under full team-mode discipline across 6 Waves). Phase 4.5's original purpose (fluency-building via throwaway practice feature) is moot given Phase 4 establishes the same fluency on real V1 work. Remaining fluency gaps surface in Phase 5+ production work, not synthetic practice. **WORKFLOW.md Phase 4.5 section preserved** as historical scaffold; not deleted (could re-activate if Phase 5+ surfaces unforeseen fluency gaps).

3. **SELF-186 ratified as V1.0 first-implementation-issue + Phase 5 close-gate exercise.** Per Architect Phase 5 detailed-steps Step 9 mosko extension. SELF-186 = B1 Apply migration `001_users_id_rename.sql`. Rationale (Architect-recommended; F/CTO ratified): (a) smallest end-to-end issue post-Wave-1-scaffolding (Wave 1 A1-A5 SELF-181–185 are themselves Phase 5 Step 1 verification work, not appropriate as close-gate validation targets); (b) exercises full migration pattern (Architect drafting → Backend execution → Sec joint-review on RLS predicate updates → DevOps CI fixture spin-up → F/CTO ratify); (c) foundational unblock cascade — SELF-186 ships `users_id` rename that ALL downstream V1.0 RLS work consumes (SELF-187/188/189/190 + Onboarding SELF-196-209 + Net Worth SELF-210/211); (d) exercises Architect → Backend → Sec → DevOps → F/CTO loop; subsequent V1.0 issues exercise the alternate Backend → Frontend → QA → Sec → DevOps → F/CTO loop. Alternatives rejected per Architect protocol: SELF-196 (too broad — multi-table + pgsodium), SELF-211 (too deep in stack), SELF-201 (too many simultaneous patterns).

4. **Phase 5 (Workshop Setup) entered 2026-06-04.** CoS lead with DevOps + Architect + Sec + PM consult. 9-step detailed-steps subsection drafted by Architect at Phase 4 Step 9 close and landed in WORKFLOW.md Phase 5 section. Bootstrap order DevOps → Backend → Frontend → QA per WORKFLOW.md verbatim intentional bootstrapping moment. Phase 5 exit-gate streak target: 35+ consecutive CLEAN §10 surfaces through Phase 5 close.

### Cross-references

- [ADR-003](#adr-003) — Phase 4-scoping team teardown + Phase 5-workshop-setup team creation.
- [ADR-009](#adr-009) Decision 2 — Phase 4 sits under P outer category; Phase 5 sits under I+V outer category. Meta-process M1 ✅ COMPLETE; M2 (Implement + Verify) becomes Active at Phase 5 entry.
- [ADR-011](#adr-011) Decision 4 — catalogued-instance ledger fully discharged at V1 per 2-instance original commitment.
- [ADR-013 P5](#adr-013) — Settings area ramp 4/4 closed at V1.5.
- [ADR-017](#adr-017) Decision 2 — BACKLOG.md §7 → Linear milestone-rotation rehearsal lands at Phase 5 Step 7.
- WORKFLOW.md Phase 4 Lessons learned subsection (12 durable patterns codified at v1.45 close).
- `temp/phase-4-sd-rt-coverage.md` (gitignored Architect coverage verdict; cited as Criterion 6 evidence).
- `temp/phase-4-step-9-pm.md` (gitignored PM exit-criteria walk + lessons-learned source).
- `temp/phase-5-detailed-steps.md` (gitignored Architect Phase 5 9-step draft source).

---

## ADR-017 — Compact-ledger conventions: MILESTONES Recent activity 5-entry + Linear current+next-milestone scope

**Date:** 2026-06-03
**Status:** Accepted
**Approved by:** F/CTO (2026-06-03; in-band call after Phase 4 Step 5 Wave 5 close per the [v1.45 CHANGELOG entry](CHANGELOG.md#v145--2026-06-03)).

### Context

Two compact-ledger conventions drifted across Phase 4 Step 5 (Waves 1–5):

1. **`MILESTONES.md` Recent activity** drifted into multi-paragraph density (1500+ words per Wave-closure entry across Waves 1–4) despite the [ADR-009 Decision 6](#adr-009) auto-load contract framing `MILESTONES.md` head as the *compact* ledger anchor with detail living in `CHANGELOG.md`. By Wave 4 close the auto-loaded section had ballooned to ~6000 words of in-context-ledger content per session.
2. **Linear scope** drifted from the [ADR-009 Decision 7](#adr-009) feature-flow scheme `[PRD → BACKLOG.md → Linear ≤200 hot → Linear: Done → MILESTONES.md Completed]` into direct PRD → Linear population at Phase 4 Step 5, bypassing the `BACKLOG.md` intermediate staging layer. 89 V1 issues across V1.0–V1.4 + Platform V1.x landed in Linear directly across Waves 1–5; `BACKLOG.md` never functioned as the V1 work-spec staging home the scheme intended.

Neither drift caused functional failure (the ≤200 hot cap wasn't hit; sessions still loaded MILESTONES head), but both compounded session-context bloat and weakened the repo-versioned V1 work-spec discipline the project conventions were designed to preserve.

### Decisions

**Decision 1 — MILESTONES.md Recent activity: 5-entry compact convention.**

`MILESTONES.md` Recent activity section narrows to:

- **Last 5 entries** (not "last 7 days"). 5 is enough to give recent-context grounding without becoming a parallel changelog.
- **1 sentence per entry**. Names the deliverable + key F/CTO ratify + headline metric (e.g., "11 Linear issues SELF-X→SELF-Y; PR #N").
- **`CHANGELOG.md` pointer for detail.** Each entry ends with `Detail: [CHANGELOG vN.NN](CHANGELOG.md#vNNN--YYYY-MM-DD)`.

Restores the [ADR-009 Decision 6](#adr-009) compact-ledger auto-load contract: MILESTONES head is the lightweight pointer; CHANGELOG is the authoritative per-version detail home. When a Wave/Step/Phase closes, its dense narrative lands in the next CHANGELOG.md `vX.YY` entry; the MILESTONES Recent activity head gets a 1-sentence pointer added (and the oldest entry rotates out if already at 5).

The drifted Waves 1–4 entries get rewritten as 1-sentence pointers at v1.45 close; the dense detail absorbed into [CHANGELOG v1.45](CHANGELOG.md#v145--2026-06-03). Going forward, Wave closures land 1 CHANGELOG entry + 1 1-sentence MILESTONES pointer.

**Decision 2 — Linear scope: current milestone + next milestone only; everything else in BACKLOG.md.**

The [ADR-009 Decision 7](#adr-009) feature-flow scheme stands, but the Linear-hot threshold narrows from `≤200 hot` to **current milestone + next milestone**:

- **Linear holds:** the milestone currently being implemented (Phase 5+ active work) + the next milestone in sequence (planning queue) + Platform / Cross-cutting V1.x (foundational substrate, always active).
- **`BACKLOG.md` holds:** all other planned milestones, with full issue specs at the same Source / Acceptance criterion / Dependencies granularity that Linear would have. `BACKLOG.md` functions as the durable repo-versioned V1 work-spec.
- **Promotion mechanism:** when implementation of the current milestone completes, the next milestone rotates into "current" and the milestone after it gets promoted from `BACKLOG.md` to Linear ("next"). Promotion = creating Linear issues from the `BACKLOG.md` specs verbatim, then marking the `BACKLOG.md` entries as "Promoted to Linear at SELF-N" (durable historical reference).

**Going-forward only.** Existing V1.0–V1.4 issues already in Linear (89 issues; SELF-181 → SELF-269) stay in Linear; no retroactive export. Milestone rotation handles them as implementation begins at Phase 5 (current = V1.0; next = V1.1; V1.2–V1.4 + future milestones flow through BACKLOG.md once they're far enough out). Wave 6 (V1.5) onward lands new issue decompositions in `BACKLOG.md` rather than Linear.

**Rationale for narrowing the cap.** The original `≤200 hot` framing in ADR-009 Decision 7 was a practical-limit framing (Linear free-tier-adjacent). The current+next-milestone framing is a *discipline* framing: BACKLOG.md functions as the durable V1 work-spec independent of any Linear pricing/cap consideration, and active workspace clutter stays low. The narrower scope honors the spirit of Decision 7's feature-flow scheme (`PRD → BACKLOG → Linear → Done`) more strictly than the `≤200 hot` framing did in practice.

### Consequences

- **`MILESTONES.md`** head shrinks by ~6000 words at v1.45 close; SessionStart hook auto-load context bloat correspondingly drops.
- **`CHANGELOG.md`** absorbs the Phase 4 Step 5 detail at v1.45; future Wave closures append a CHANGELOG entry + MILESTONES 1-sentence pointer.
- **`BACKLOG.md`** header updated to reflect the new scheme; existing V2 deferred content (§5.1–§5.7) preserved; new "V1 staging queue" framing added for going-forward Wave content.
- **`CLAUDE.md`** updated to reflect both conventions in the read-first guidance.
- **Wave 6 (V1.5)** dispatches into `BACKLOG.md` not Linear. Implementation Phase 5 entry triggers V1.0 promotion-to-Linear-active (already there) + V1.1 promotion-to-Linear-next.
- **Cross-reference.** This ADR refines [ADR-009 Decision 6](#adr-009) (compact-ledger auto-load) + [ADR-009 Decision 7](#adr-009) (feature-flow scheme). It does NOT supersede those decisions — both still hold; this ADR narrows their thresholds.

---

## ADR-016 — V1 RT-26 service_role allowlist surface enumeration

**Date:** 2026-05-31
**Status:** Accepted
**Phase:** 3 (ARCH §7 Integration Points lock + same-PR companion edits to SECURITY §4.2 webhook-allowlist annotation bullet + ARCH §4.1 RT-26 allowlist anchor narrative + ARCH §7.1 endpoints 2 + 3 + 9)

**Context.**

The [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) Webhook-allowlist annotation convention — landed at Sec joint-review of [ADR-011](#adr-011) Decision 4 / §10 defense-in-depth meta-pattern — verbatim: *"allowlist additions require Sec-consult + ADR amendment at the surface-introducing lock."* The convention's design intent is to catch allowlist drift at the surface that introduces it: a §4.1 allowlist entry added without an ADR is exactly the failure mode the convention is designed to prevent.

[ARCH §7 Integration Points](docs/ARCH/index.html#sec-7) lock at this PR introduces **two new service_role allowlist surfaces** beyond the existing canonical first (the Plaid webhook handler from [ADR-011](#adr-011) Decision 1 / Lock 4 / Decision 8): the Plaid `/item/public_token/exchange` server-side route at [ARCH §7.1 endpoint 2](docs/ARCH/index.html#sec-7-1) (credential-class admission surface for [SD-03](docs/SECURITY/index.html#sd-03) access tokens at first-onboarding-time) and the Plaid `/item/remove` server-side route at [ARCH §7.1 endpoint 3](docs/ARCH/index.html#sec-7-1) (SD-03 retention enforcement surface anchoring `bounded-Item-active-only` per [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) + §4.6). ADR-016 is the **surface-introducing lock** that the webhook-allowlist annotation convention requires; it enumerates the three V1 allowlist surfaces, captures the per-surface tier-posture rationale, and ratifies the convention as durable for future allowlist additions.

ADR-016's scope is **internal-to-RT-26 surface enumeration**. The §10 catalogued-instance ledger ([ADR-011](#adr-011) Decision 4) is unchanged by ADR-016 — the catalogued numbered list, the Privileged-context-surfaces bullet, and the three-layer composition definitions all stand. The webhook-allowlist annotation convention is a SECURITY §4.2-internal discipline operating within the RT-26 catalogued-instance scope; expanding the allowlist composition is **not** a new §10 catalogued-instance claim.

### Decision 1 — V1 RT-26 service_role allowlist composition is three named surfaces

All three are SvelteKit `+server.ts` route handlers on the V1 web-app container; all three reference `SUPABASE_SERVICE_ROLE_KEY` under the [ARCH §4.1](docs/ARCH/index.html#sec-4-1) allowlist-glob enumeration (`src/routes/**/+server.ts`); each carries a distinct tier-posture rationale tied to the surface's role in the Plaid integration.

- **Canonical first allowlist entry — Plaid webhook handler** at `src/routes/api/plaid/webhook/+server.ts`. The privileged-context-write surface per [ADR-011](#adr-011) Decision 1; composes [RT-05](docs/SECURITY/index.html#rt-05) critical-severity signature verification + `plaid_webhook_id` UNIQUE idempotency gate per Lock 4 mod #3 + same-transaction audit-log discipline per Decision 1 / Lock 4 mod #5; service_role required for the Plaid-event-driven write path (no user-session JWT; tenant correctness bound in code via explicit `users_id` lookup at the Plaid Item ID per Lock 4 mod #2; matched-tenant validation at the DB layer composes orthogonally). The [ARCH §3.1](docs/ARCH/index.html#sec-3-1) flow carries the full sequence narrative.
- **Canonical second allowlist entry — Plaid `/item/public_token/exchange`** at `src/routes/api/plaid/onboard/+server.ts` (or equivalent per Phase 5 routing convention). The credential-class admission surface for [SD-03](docs/SECURITY/index.html#sd-03) Plaid access tokens — this single endpoint is where V1's tenant-bound Plaid credential-class data enters V1's storage envelope at first-onboarding-time. Service_role posture inherits from the SD-03 storage-class write-path stricture per [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) — credentials are categorically stricter than even high-tier financial-data classes per §4.2 verbatim; the encrypt-and-insert path against `pfin.plaid_items.access_token_encrypted` (encrypted `BYTEA` via Supabase Vault / pgsodium per Decision 8 / Lock 4) requires service_role for the Vault key access bound by [Lock 4 mod #1](#adr-011). The [ARCH §7.1 endpoint 2](docs/ARCH/index.html#sec-7-1) paragraph carries the per-endpoint behavioral contract.
- **Canonical third allowlist entry — Plaid `/item/remove`** at `src/routes/api/plaid/revoke/+server.ts` (or equivalent per Phase 5 routing convention). The SD-03 retention enforcement surface anchoring the `bounded-Item-active-only` retention commitment per [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) + §4.6 (on Item-deletion, V1 calls Plaid `/item/remove` server-side to revoke the access token at Plaid before deletion-class operations against the local credential row — never silently delete-local-without-revoking-Plaid-side). Service_role posture required to read `vault.decrypted_plaid_access_token` per [Lock 4 mod #1](#adr-011) before invoking Plaid `/item/remove` (the decrypted access token must be presented to Plaid in the revoke call). The [ARCH §7.1 endpoint 3](docs/ARCH/index.html#sec-7-1) paragraph carries the per-endpoint behavioral contract.

**Rationale — why allowlist-shaped (not wrapping-shaped) at three entries.** The §4.1 allowlist-shaped fence design ([SECURITY §4.2](docs/SECURITY/index.html#sec-4-2)) catches new server routes that reach for raw `SUPABASE_SERVICE_ROLE_KEY` at PR-time by failing the grep fence closed against any file path outside the allowlist; allowlist additions are deliberately a higher-friction event (require Sec-consult + ADR) so the friction is what makes the convention work. Three V1 entries is the right scope for V1 — Plaid is the dominant V1 integration per [PRD §2.1–§2.4](docs/PRD/) and exhausts the V1 credential-class surface; adding more would require either a new integration surface (V2 trajectory) or a refactor that splits an existing endpoint (Phase 5+ detail design).

**Rationale — why service_role posture inherits from SD-03 storage-class write-path stricture for entries 2 + 3.** [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) verbatim: *"credentials get categorically stricter handling than even high-tier financial-data classes because compromise yields direct unauthenticated access to a downstream system."* The credential-class admission surface (entry 2) and the credential-class retention enforcement surface (entry 3) are both write paths against SD-03's storage column under pgsodium-encrypted-BYTEA shape; the encrypt key access and the decrypt-view access are both bound to service_role by [Lock 4 mod #1](#adr-011). Same posture rationale as entry 1 (the webhook write path under Decision 1's privileged-context-write discipline) — credentials are categorically stricter; the allowlist composition reflects the categorically-stricter discipline rather than introducing a new tier-posture rationale per entry.

**Rationale — why §10 catalogued-instance ledger stays unchanged.** Decision 4 catalogues §10 *instances* (defense-in-depth mechanisms operating at multiple layers); the catalogued numbered list names mechanisms by their layer-distinctness — RT-22's infrastructure-credential-presence layer differs in kind from RT-26's code-layer allowlist CI grep fence. Expanding RT-26's allowlist composition from 1 to 3 entries does NOT introduce a new layer-distinct mechanism — all three entries operate within RT-26's existing code-layer scope under the same CI grep fence. ADR-016 is the right home for the surface-enumeration claim; Decision 4 is the wrong home for it. The 6-consecutive-surface CLEAN §10 attribution streak (per Sec commendation at the §7 joint-review) depends on this distinction; ADR-016 preserves it by-construction.

**Alternatives considered.**

- **(α) Amend [ADR-011](#adr-011) Decision 4 catalogued-instances bullet** — extend the RT-26 entry to enumerate the three surfaces inline. Rejected at F/CTO ratify: conflates a surface-enumeration expansion with a §10 catalogued-instance claim; Decision 4's catalogued numbered list discipline is load-bearing (Sec's 6-consecutive-surface CLEAN streak depends on it staying clean); the (β) shape carries the same delivery at lower discipline cost. Architect's pre-lean was (β); paraphrasing drift in team-lead summary briefly reversed to (α); F/CTO ratify restored (β) on second look.
- **(γ) No same-PR ADR; defer allowlist enumeration to Phase 5 or to §4.1 update-only** — rejected at Sec joint-review per [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) Webhook-allowlist annotation convention verbatim (*"allowlist additions require Sec-consult + ADR amendment at the surface-introducing lock"*). The §7 lock IS the surface-introducing lock; the convention's design intent fails open if the ADR slips.
- **(δ) Inline the three-surface enumeration at ARCH §4.1 + SECURITY §4.2 without an ADR** — rejected at Sec joint-review per the same convention citation. ADR is the artifact that makes the decision durably committed; without it, future allowlist amendments lose the precedent shape.

### Decision 2 — Webhook-allowlist annotation convention is ratified durable

Future RT-26 allowlist additions beyond the three enumerated in Decision 1 require Sec-consult + ADR amendment at the surface-introducing lock — by amendment to ADR-016 (preferred for V1 single-PR additions) or by new ADR (for batched additions or convention shifts). The convention's catalogued-allowlist home is [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) Webhook-allowlist annotation bullet; ADR-016 is the version-1 enumeration consumed by §4.2.

**Rationale.** The convention pre-existed as wording inside SECURITY §4.2 but had no canonical-ADR home until ADR-016. Ratifying it durably here means future allowlist additions inherit the precedent shape (Sec-consult + ADR amendment), and the §4.2 bullet's "allowlist additions require" clause has a concrete enforcement record to point at. Without this ratification, the convention is text in a security artifact; with it, the convention is a project commitment with a precedent.

### Decision 3 — 4th V1 RT-26 surface: the Supabase admin-client factory (MFA recovery, SELF-291 Slice 2b)

**Date:** 2026-07-22 · **Status:** Accepted (amendment to ADR-016 per Decision 2's durably-ratified addition convention; lands with the Slice-2b app PR where the `service_role` key first appears in `api/src`; Sec joint-review-mandatory — the 4th RT-26 surface).

The V1 RT-26 allowlist adds a **4th** surface: `api/src/lib/server/supabase-admin.ts` — a single `service_role` client factory, the sole `SUPABASE_SERVICE_ROLE_KEY` reference in `api/src`. **Tier-posture rationale:** MFA recovery is a `service_role` surface **by construction** ([ADR-030](#adr-030) — the MB-1 guard blocks the aal1 `mfa_policy` downgrade; CV-R1 BLOCKED means only `service_role` admin `deleteFactor` can remove the lost factor; the `026` recovery-code hashes are service_role-only). Unlike surfaces 1–3 (reserved Plaid routes that delegate to the worker via `WORKER_ADMISSION_*`), this is the first *actual* key usage in `api/src`, and it is deliberately a **factory** (one audited key-home) rather than per-route references, so the allowlist grows by exactly one entry and future service_role surfaces reuse the factory instead of adding entries. Tenant correctness for the factory's callers is bound **in code** (explicit `users_id` filter on every query — `service_role` BYPASSRLS, so the WHERE is the tenant fence; the [Decision 1](#adr-011) code-side-binding discipline; `users_id` comes only from the validated session, never the request body). **§10 catalogued-instance ledger UNCHANGED at 3** (RT-22/RT-26/RT-27) — an intra-RT-26 allowlist-composition expansion, not a new layer-distinct mechanism (same reasoning ADR-016 D1 used for the 1→3 expansion). Registry: append `api/src/lib/server/supabase-admin.ts` to `scripts/ci/rt26-allowlist.txt`.

**§10 3-axis cross-check ([Decision 4](#adr-011) read verbatim before drafting):** ledger stays **3**; (i) numbering RT-22 first / RT-26 second / RT-27 third unchanged; (ii) layer-attribution unchanged — RT-26 stays the code-layer allowlist grep fence, RT-22/RT-27 untouched; (iii) Path B (Decision 4 linked, not restated). **DEFINER allowlist stays 3** (no function authored). **Decision-3 FK-bypass family unchanged** (`026`/`027`'s only FK is the tenant anchor `users_id`). This IS an allowlist addition, so Decision 2's "allowlist ADDITION → Sec-consult + ADR amendment" gate applies and is satisfied by this amendment landing in the same PR as the factory + the `rt26-allowlist.txt` entry.

**Cross-references.**

- [ADR-030](#adr-030) — Auth-3b Slice 2 MFA recovery: the `service_role`-by-construction rationale + the `026`/`027` stores this factory reaches; the 4th-surface one-way-door flagged there lands here.
- [ARCH §7.1](docs/ARCH/index.html#sec-7-1) endpoints 2 + 3 + 9 — per-endpoint behavioral contracts naming the three allowlist entries; consumes ADR-016's enumeration as the §4.1 allowlist composition at V1.
- [ARCH §4.1](docs/ARCH/index.html#sec-4-1) — V1 server-source surface allowlist anchor. ADR-016's three-surface enumeration is consumed by the §4.1 allowlist composition (file-path-glob scope is `src/routes/**/+server.ts`; the three specific entries are named within that glob).
- [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) Webhook-allowlist annotation bullet — receives the same-PR sub-edit naming the three allowlist entries with per-entry rationale.
- [ADR-011](#adr-011) Decision 1 — privileged-context-write discipline; canonical first allowlist entry (Plaid webhook handler) is rooted here. ADR-016 references Decision 1 for entry 1's mechanism anchor.
- [ADR-011](#adr-011) Decision 4 — §10 defense-in-depth meta-pattern; the catalogued §10 instances ledger. **UNCHANGED by ADR-016.** ADR-016 references Decision 4 once to anchor "RT-26's §10 catalogued-instance home stays Decision 4" without restating Decision 4's catalogued numbered structure.
- [ADR-011](#adr-011) Decision 8 / Lock 4 — Plaid integration locks (Vault/pgsodium column-level encryption on `pfin.plaid_items.access_token_encrypted` + webhook handler explicit `users_id`-binding + idempotency via `plaid_webhook_id` UNIQUE + pgsodium decrypt-view permission scoped to service_role per Lock 4 mod #1). ADR-016 references Lock 4 mod #1 for the service_role posture rationale on entries 2 + 3.
- [ADR-015](#adr-015) — SvelteKit framework lock; anchors the `src/routes/**/+server.ts` server-source surface as the V1 web-app container's route-handler surface. ADR-016's three entries are SvelteKit `+server.ts` route handlers under §4.1's allowlist-glob enumeration that ADR-015 unblocked.
- Sec joint-review at the §7 lock (2026-05-30) — load-bearing finding (a)1 ratifying the allowlist composition at three entries; (c)1 SECURITY §4.2 sub-edit verbatim wording; provenance of ADR-016's surface enumeration + tier-posture rationale.

**Consequences.**

- **Same-PR companion edits.** ADR-016 lands alongside (i) [ARCH §7](docs/ARCH/index.html#sec-7) v2 application (replaces template scaffolding at lines 497–512); (ii) [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) webhook-allowlist annotation bullet expansion per (c)1 verbatim wording; (iii) [ARCH §4.1](docs/ARCH/index.html#sec-4-1) RT-26 allowlist anchor narrative gains the three named entries (cohesion update with ADR-016).
- **Future RT-26 allowlist additions** require Sec-consult + ADR amendment at the surface-introducing lock per the webhook-allowlist annotation convention (durably ratified by Decision 2). Likely future surfaces: V2 multi-user invite flow allowlist entries; V2+ live-tax-API ingestion service_role write paths per [Decision 19 / Lock 15](#adr-011) cross-tenant FK-bypass family forward-pointer; any Phase 5 detail-design surface that introduces a service_role write path. Amendment to ADR-016 is preferred for V1 single-PR additions; new ADR is preferred for batched additions or convention shifts.
- **[ADR-011](#adr-011) Decision 4 catalogued §10 ledger is UNCHANGED.** The catalogued numbered list, the Privileged-context-surfaces bullet, and the three-layer composition definitions all stand; ADR-016 does NOT modify Decision 4. The 6-consecutive-surface CLEAN §10 attribution streak holds at ADR-016 lock per the pre-emptive cross-check performed at draft time.
- **Phase 5 audit-hook table completion** (per [ARCH §7.1](docs/ARCH/index.html#sec-7-1) Phase 5 detail-design item (a)) carries the per-endpoint audit-hook commitments for the three allowlist surfaces; Sec-consult-mandatory at the Phase 5 audit-hook lock per [SECURITY §4.6](docs/SECURITY/index.html#sec-4-6) V2-ship-gate inventory convention.
- **No other ADRs superseded or amended.** [ADR-011](#adr-011) Decisions 1 / 4 / 8 / 17 + Locks 4 / 13 all compose unchanged; [ADR-015](#adr-015) (framework lock) + [ADR-014](#adr-014) (design system) + [ADR-008](#adr-008) (Sec canonical-reference layer establishment) all stand.

**Approved by:** F/CTO (2026-05-31 — in-conversation ratification of (β) new short ADR shape against the (α) Decision 4 amendment alternative; Architect's pre-lean restored as F/CTO ratify; Sec's joint-review at the §7 lock supplied the verbatim mod (a)1 + (c)1 wording that ADR-016 consumes for the enumeration + rationale).

**Amendment (2026-07-13 / `015` fold — citation-drift correction, no allowlist-composition change).** The three RT-26 allowlist entries' credential-store references update for the `plaid_items` → `pfin.linked_source` fold (ADR-027 / ADR-011 Lock 4 amendment), AND the pre-existing pgsodium-BYTEA framing is corrected to Vault-native (already stale via SELF-196 / the 2026-07-03 Lock-4 Option-2 amendment, fold-independent).

**§10 3-axis cross-check (this amendment touches RT-26 territory; Decision 4 read verbatim before drafting):** ledger stays **2**; (i) numbering RT-22 first / RT-26 second unchanged; (ii) layer-attribution unchanged — RT-26 stays the code-layer allowlist, RT-22 untouched; (iii) Path B. **Allowlist count stays 3** — this updates the credential-store object NAMES the three existing entries reference; it **adds no entry**, so Decision 2's "allowlist ADDITION → Sec-consult + ADR" gate is not tripped. Citation-drift class.

- **Entry 2 (credential admission):** the write path is no longer *"encrypt-and-insert against `pfin.plaid_items.access_token_encrypted` (encrypted `BYTEA` via Supabase Vault / pgsodium)"* → it is **`vault.create_secret(...)` under `service_role` + INSERT the `uuid` handle into `pfin.linked_source.credential_secret_id`** (Vault-native; ciphertext never on the pfin row). The route re-scopes per-provider (ADR-027 gate ii, PM) but the SD-03 service_role posture is unchanged.
- **Entry 3 (retention/revoke):** reads **`pfin.decrypted_source_credential`** (was `vault.decrypted_plaid_access_token`) before the per-provider revoke-then-delete.
- **Cross-ref to Lock 4:** *"Vault/pgsodium column-level encryption on `pfin.plaid_items.access_token_encrypted`"* → **"Vault-native secret-per-token on `pfin.linked_source.credential_secret_id` (`vault.secrets` handle); pgsodium-BYTEA superseded per the 2026-07-03 Option-2 amendment."**
- **Unchanged:** allowlist COUNT stays 3; the three surfaces stay SvelteKit `+server.ts` handlers under the ARCH §4.1 `src/routes/**/+server.ts` glob; §10 ledger stays 2; this is a citation-drift correction, NOT an allowlist addition (Decision-2 gate not tripped).

**Paired Sec-doc follow-up (Sec-owned, doc-flow branch — NOT same-PR-migration, per the `006` mod #4 doc-artifact-separate-flow precedent):** SECURITY §4.2 + the SD-03 matrix + RT-02 + RT-05 carry the same `plaid_items`/`decrypted_plaid_access_token` + pgsodium-BYTEA references; Sec authors that HTML doc-update as a required tracked follow-up.

---

## ADR-015 — Frontend framework + styling lock (SvelteKit + no Tailwind)

**Date:** 2026-05-29
**Status:** Accepted
**Phase:** 2 (Step 10 — tokens-as-code consumption format closes; closes the [ADR-012](#adr-012) Phase 2 ↔ Phase 3 framework-coupling touchpoint) + 3 (Tech-Stack §4 framework ratify; precondition for the concrete file-glob enumeration that [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) RT-26 audits against)

**Context.** Phase 3 Architect produced a 3-option framework brief (Next.js App Router / Remix (React Router v7 framework mode) / SvelteKit) with constraint-by-constraint satisfaction tables against the Lock-13 topology + Lock-13 mod #1 PDF-render contract + Supabase JS RLS-forwarding + [ADR-014](#adr-014) token consumption, plus a ranked Architect lean of **Remix > Next > SvelteKit** weighted on solo-maintainer multi-week-gap mental load and Phase-6 AI-coding-agent fluency. F/CTO ratified **SvelteKit** in-conversation on engineering-merit grounds (verbatim: *"Better structural engineering decision"*) against the Architect lean; subsequently ratified **no Tailwind**. The choice closes the [ADR-012](#adr-012) Phase 2 ↔ Phase 3 coupling and unblocks Phase 2 Step 10 (tokens-as-code). Sec's verify-pass on the RT-26 / [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) framework-agnostic `SUPABASE_SERVICE_ROLE_KEY` fence (PR #62) caught the missing-ADR process gap — a grep for "SvelteKit"/"Svelte" across `DECISIONS.md` / `docs/` / `MILESTONES.md` / `WORKFLOW.md` returned zero matches despite the in-conversation ratification. ADR-015 is the artifact that makes the decision committed-real and anchors the RT-26 obligation that the concrete server-source file-glob list lands in ARCH §4 at framework ratify.

**Locked option.**

- **Frontend framework:** **SvelteKit (Svelte 5)** for the V1 web app container in the [ADR-011](#adr-011) Decision 17 hybrid 3-container topology. **Canonical server-source surfaces (the RT-26 audit scope — see Consequences):** `+server.ts` (route handlers — e.g., `/api/plaid/webhook`, `/internal/pdf-render`); `+page.server.ts` (SSR data loading per route); **`+layout.server.ts`** (layout-level data loading + auth gates); `src/hooks.server.ts` (centralized Supabase session forwarding + auth refresh); and **`src/lib/server/**/*.ts`** (SvelteKit's server-only-module convention, enforced at import time by Vite — the natural home for shared server-side helpers including database-client factories, and therefore the surface where service-role drift is most likely under a "DRY up the codebase" refactor if uncovered by the fence). Build via Vite; deploy as a small Node server in its Coolify container on the existing Hetzner cax21.
- **Styling:** **No Tailwind.** [ADR-014](#adr-014)'s two-tier CSS-custom-properties token taxonomy (`--color-*` primitives → `--c-*` semantic aliases) is consumed natively via Svelte's component-scoped `<style>` blocks; `tokens.css` is imported globally in `src/app.css`. Component styles use `var(--c-*)` directly; no utility-class transformation layer.

**Rationale.** F/CTO weighted **engineering merit** above the Architect's prioritization criteria. The specific structural wins:

- **Lock 13 mod #1 PDF-render contract** (Puppeteer → V1 app `/internal/pdf-render` → SECURITY INVOKER read-composition helper): SvelteKit's `+server.ts` / `+page.server.ts` surfaces are **SSR by default** — no `dynamic = "force-dynamic"` opt-out knob to remember (Next.js's structural disadvantage on this contract) and no caching-defaults flip exposure.
- **[ADR-014](#adr-014) token consumption is 1:1.** Svelte's idiomatic styling pattern *is* component-scoped CSS + CSS custom properties — exactly the shape [ADR-014](#adr-014) locked. No transformation layer (no Style Dictionary export, no Tailwind `@theme` round-trip, no design-token JSON intermediate). The framework gets out of the way.
- **Smallest container footprint** of the three options (~60–120 MB idle versus ~80–150 MB Remix and ~200–400 MB Next.js); meaningful on a shared cax21 (16 GB) running `pfin_back_etl` + V1 app + PDF worker + Supabase concurrently.
- **Lowest framework ceremony** for Supabase RLS forwarding: centralized in `hooks.server.ts`; one place to get the user-session-JWT-forwarding pattern right, one place to audit.
- **No Tailwind** falls out naturally — adding Tailwind on top of [ADR-014](#adr-014)'s already-finished CSS variables would reintroduce the double-bookkeeping (utility classes + CSS vars) and the framework-ceremony that the SvelteKit choice is structurally optimizing away.

The Architect lean was **Remix > Next > SvelteKit**, weighted on three different axes: (i) solo-maintainer multi-week-gap mental load (Remix's two-primitive loader/action model is the smallest mental surface); (ii) Phase-6 AI-coding-agent fluency (React-based options are materially better-represented in current LLM training corpora than Svelte 5, whose runes API is new); (iii) React-ecosystem availability (shadcn/ui, Radix, broad component-library pool). **F/CTO accepted these costs explicitly** in ratifying SvelteKit — the engineering-merit wins were weighted above the agent-fluency / ecosystem / multi-week-gap criteria, with the caveat that Phase-6 build-loop velocity will pay a real ramp-up cost on UI work that should be tracked at Phase 6 entry.

**Alternatives considered.**

- **Next.js (App Router)** — the React-ecosystem default; widely-adopted full-stack framework. Pro: largest React ecosystem; deepest AI-coding-agent fluency; widest StackOverflow/AI-coder surface. Con: four overlapping data-flow paradigms (RSC, client components, server actions, route handlers) — real cognitive load; `/internal/pdf-render` requires explicit `dynamic = "force-dynamic"` opt-out (Next 15 caching-defaults flip); framework churned hard 2023–2025 (Pages → App Router rewrite; Next 14→15 default flips); highest lock-in (RSC code doesn't port). Rejected: structural ceremony + lock-in outweigh ecosystem depth at solo-maintainer scale.
- **Remix (React Router v7 framework mode)** — the **Architect's recommended lean**. Pro: two-primitive (loader + action) SSR-by-default model is the smallest mental surface that satisfies the Lock 13 mod #1 contract; preserves React ecosystem (shadcn/ui, Radix, agent fluency); lowest migration cost of the three; less ceremony than Next for the Supabase JWT-forwarding path (no middleware-vs-route split). Con: mid-rebrand doc fragmentation from the Nov 2024 Remix → React Router v7 merge; smaller starter/template pool than Next; AI-coding-agent fluency somewhat behind Next (improving). Rejected by F/CTO: SvelteKit's structural engineering merit weighted above Remix's mental-load / agent-fluency advantages.
- **SvelteKit (Svelte 5)** — **selected.** (Detail above.)

Long-list also-considered (rejected at framing): Nuxt (Vue) — same shape as SvelteKit but adds a Vue-ecosystem mismatch; Astro — content-site shape, not the right fit for ~45 interactive authenticated screens; Plain Express + HTMX — gives up the design-system component model that [ADR-014](#adr-014) consumes; Vite-SPA + separate Express SSR layer — hand-rolled split, more moving parts with no upside.

**Cross-references.**

- [ADR-014](#adr-014) — Phase 2 design system (two-tier `--color-*` → `--c-*` CSS-custom-properties token taxonomy). ADR-015's "no Tailwind" + SvelteKit's native scoped-CSS pattern make [ADR-014](#adr-014)'s `tokens.css` the canonical consumption format directly; this composition closes Phase 2 Step 10 (tokens-as-code).
- [ADR-012](#adr-012) — Phase 2 + Phase 3 parallel execution. The frontend-framework choice was [ADR-012](#adr-012)'s single hard coupling touchpoint between Phase 2 (design tokens format) and Phase 3 (Tech Stack §4); ADR-015 closes that coupling and unblocks Phase 2 closure.
- [ADR-011](#adr-011) Decision 17 / Lock 13 — hybrid 3-container topology. Decision 17's committed text leaves the V1 web app's framework neutral (verbatim: *"V1 app retains Plaid webhook handler + in-app render path"*); the working locks log used Next.js as a placeholder shape. ADR-015 **extends** Decision 17 by anchoring that V1 web-app container as SvelteKit; the topology + worker disciplines + Lock 13's mod inventory all stand unchanged.
- [ADR-008](#adr-008) + [ADR-011](#adr-011) Decision 4 (§10 defense-in-depth) — anchor for the [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) RT-26 framework-agnostic `SUPABASE_SERVICE_ROLE_KEY` fence (PR #62). RT-26's "concrete file-glob enumeration locked in ARCH §4 at framework ratify" obligation now has its precondition (framework ratify = ADR-015); [ARCH §4.1](docs/ARCH/index.html#sec-4-1) enumerates the SvelteKit-specific allowlist: `src/routes/**/+server.ts`, `src/routes/**/+page.server.ts`, `src/routes/**/+layout.server.ts`, `src/hooks.server.ts`, `src/lib/server/**/*.ts`, plus the explicit worker-entry codepaths.
- Architect's 3-option ratification brief (in-pane, 2026-05-29) — the structural-comparison source for the Alternatives Considered section above.

**Consequences.**

- **Phase 2 Step 10 (tokens-as-code) closes.** `tokens.css` IS the consumption format; imported globally in `src/app.css`; component `<style>` blocks use `var(--c-*)` natively per Svelte idiom. No transformation layer, no intermediate format. Visual Designer notification follows once ADR-015 + ARCH §4 land.
- **ARCH §4 Tech Stack write-up is next.** Populates the Frontend framework + Styling rows of the §4 table; carries the Alternatives Considered material above into the "alternatives" cells; enumerates the concrete SvelteKit server-source file-glob allowlist that RT-26 / [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) audits against: `src/routes/**/+server.ts`, `src/routes/**/+page.server.ts`, `src/routes/**/+layout.server.ts`, `src/hooks.server.ts`, `src/lib/server/**/*.ts`, plus the explicit worker-entry codepaths.
- **[ADR-011](#adr-011) Decision 17's "V1 app" container is now anchored as SvelteKit.** ADR-015 **extends** Decision 17 — the hybrid 3-container topology, privileged-context-write disciplines, and Lock 13's full mod inventory all stand unchanged.
- **Phase 6 agent-fluency cost accepted explicitly.** SvelteKit is materially less-represented in AI-coding-agent training corpora than React-based options; Svelte 5's runes API (2024) further widens the fluency gap. Phase-6 build-loop velocity will pay a ramp-up cost on UI work versus a Remix or Next baseline. Phase 6 entry lessons-learned should track the realized impact to inform future framework-class decisions; if the cost lands materially higher than expected, ADR-015 is in-principle reversible (UI-layer rewrite; DB/RLS/worker code is portable) — but reversal is a one-way-door-shaped cost and not the planning baseline.
- **Lock 13 mod #1 `/internal/pdf-render` contract satisfied** by SvelteKit's `+server.ts` / `+page.server.ts` SSR-by-default surfaces. The Puppeteer → V1 app authenticated-tier-JWT hop holds; no caching/`dynamic` knob to misconfigure.
- **No other ADRs superseded or amended.** [ADR-005](#adr-005) (settings store) / [ADR-013](#adr-013) (Phase 2 UX) / [ADR-014](#adr-014) (Phase 2 design system) compose unchanged.

**Approved by:** F/CTO (2026-05-29 — in-conversation ratification of SvelteKit on engineering-merit grounds against Architect's Remix lean; subsequent in-conversation ratification of "no Tailwind"; Sec's verify-pass on RT-26 / [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2) caught the missing-ADR process gap and triggered this drafting; Sec's review against the draft surfaced two amendments — audit-scope glob completeness + Decision-17 "extends not supersedes" framing — applied at v2 before F/CTO ratify).

---

## ADR-014 — Phase 2 design system: foundation, two-tier tokens, and the `docs/DESIGN/` home

**Date:** 2026-05-29
**Status:** Accepted
**Phase:** 2 (Steps 6–9 — UX→Visual handoff, palette/typography/dark checkpoint, design-system spec, token taxonomy; consumes [ADR-013](#adr-013) flows + decisions; Step 10 tokens-as-code remains gated on the Phase-3 frontend-framework choice per [ADR-012](#adr-012))

**Context.** With the §2 flows locked + the P1–P6 walk-through decisions in [ADR-013](#adr-013), Phase 2 proceeded through wireframes (Step 4, low-fi HTML), the UX→Visual handoff (Step 5; ~45 screens + a consolidated component inventory incl. INV-3: breadcrumb / action-menu / chart-granularity chip-group), the mandatory palette/typography/dark-mode checkpoint (Step 7), the full design-system spec applied across all 6 clusters (Step 8), and the token taxonomy (Step 9). **Output format = HTML route** (F/CTO call): the Visual Designer applies real palette/type/spacing to the wireframe HTML, reviewed in-browser; CSS custom properties serve as the framework-agnostic token layer (the ADR-012 intermediate). **Figma MCP is connected as the escalation path** if HTML proved insufficient (it didn't). **No Claude Design (claude.ai/design) bridge exists from Claude Code** — it's a browser-only interactive tool with no MCP/API (confirmed via the Anthropic announcement + this session's tooling), so it was not usable for agent-driven design here. Working artifacts (the live palette switcher, walkthrough decks, the decisions log) live in gitignored `temp/`; this ADR is the committed decision record.

**Decisions.**

### Decision 1 — Visual foundation (locked at the Step 7 checkpoint)
- **Palette = Restrained Semantic (B), refined.** Semantic green/red (`--c-pos`/`--c-neg`) scoped to **actual performance only** (NAV Δ, unrealized G/L); the §2.3 non-goal fence holds in the visual layer — **zero value-color on `$ReAlloc`/`%Target`/target captions**, no progress bars / gauges / over-under / variance / target-lines anywhere. Pop comes from a vivid blue accent + a restrained indigo secondary applied to **chrome only** (active nav, hero focal surface, chart line/fill, chips, badges).
- **Typeface = Inter + JetBrains Mono** (chosen over Geist+Geist Mono / Satoshi+IBM Plex for readability); **Hybrid (Type 3)** — Inter for hero NAV + UI, JetBrains Mono for tabular numerics. Self-host at Step 10.
- **Attention hue = Canary-Yellow `#FFEF00`** (chosen over neon-orange `#FFAD00` + true-yellow `#eaea00` via a 3-way live A/B/C). Intensity/contrast-managed (text/border darker for WCAG-AA on white + fill); reserved for staleness/re-auth only; distinct from the negative-performance red + the accent.
- **Dark mode = plan-for** — dark tokens authored now (proven via a Light/Dark toggle), ship light-first, dark fast-follow; ~one token block + a contrast pass, no V1 gate.

### Decision 2 — Canvas: barely-cool, with card elevation (resolving the "lost windows")
The canvas is a **barely-cool near-white** (`--color-neutral-25`, ≈`#fafcfe`) — reads essentially white, cool (not cream/warm). Card surfaces stay **pure white**, so the per-story bordered "window" regions pop again via gentle fill-contrast + a light shadow + their cool border. (A prior over-correction to a literal pure-white canvas had set canvas == surface, flattening the cards; the barely-cool canvas restores the distinction while honoring F/CTO's "cooler white, not cream" intent — the warmth F/CTO had objected to was the attention token + a cached stylesheet, not the canvas.)

### Decision 3 — Two-tier token architecture (the Step-9 taxonomy)
Tokens are structured in two tiers so **no raw hex sits on a semantic token** (every value is discoverable + traceable to a named primitive — closing the recurring "I can't find the token for that value" problem):
- **Tier 1 — primitives (`--color-*`):** named raw values, the only place hexes live (a cool-neutral ramp + blue/indigo/canary/green-red ramps + alpha tokens).
- **Tier 2 — semantic aliases (`--c-*`):** every role aliases a primitive via `var(--color-*)` (e.g. `--c-canvas: var(--color-neutral-25)`, `--c-surface: var(--color-white)`, `--c-attn-solid: var(--color-canary-500)`). The dark theme re-aliases the same semantic names to dark-side primitives — no new hexes in the dark block.

### Decision 4 — Committed home = `docs/DESIGN/` (resolves the [ADR-013](#adr-013) flow-artifact-home follow-up)
A new top-level **`docs/DESIGN/`** artifact (4th alongside `docs/PRD/` / `docs/ARCH/` / `docs/SECURITY/`) is the permanent home for Phase 2 (UX & Design) outputs: the **design system** (`tokens.css` / `screen.css` / `design-system-spec.md` / styled-screen HTML), the **UX flows** (`flows/`), and the **wireframes** (`wireframes/`). NOT folded into PRD (requirements = Phase-1 input) or ARCH (technical architecture = Phase 3) — ARCH **cross-references** `docs/DESIGN/` for the frontend/tokens coupling. Matches the project's HTML-doc + serve-docs/comments convention.

**Consequences.**

- **`docs/DESIGN/` is established + populated** in this PR (the design system + flows + wireframes migrated out of gitignored `temp/`). Working/review-only artifacts (the palette switcher, walkthrough decks, the Phase-2 decisions log) stay in `temp/`.
- **Step 10 (tokens-as-code) remains gated on the Phase-3 frontend-framework choice** (per [ADR-012](#adr-012)). The framework-agnostic token taxonomy (Decision 3) is complete; the framework-specific token export lands at Step 10 once Phase 3 picks the framework. Phase 2 cannot fully close until then — it sits at the ADR-012 framework-coupling pause.
- **Phase 3 ARCH consumes the frontend-framework coupling point + cross-references `docs/DESIGN/`** for the UI/token surface.
- **Follow-up (path-normalization):** the migrated `flows/*.md` + `wireframes/*.md` retain some `temp/phase-2-*` internal cross-references (informational prose) that should be normalized to `docs/DESIGN/`-relative paths in a cleanup pass; the design-system HTML/CSS itself uses clean relative links.
- **Composes with** [ADR-013](#adr-013) (Step-3 flow decisions) + [ADR-012](#adr-012) (parallel execution + framework coupling). Per-decision detail + the full option history live in the gitignored `temp/phase-2-decisions-log.md`.

**Approved by:** F/CTO (2026-05-29 — Step 7 foundation locked via the palette/type/dark/attn checkpoint; design system reviewed + approved at Step 8; two-tier tokens + barely-cool canvas + `docs/DESIGN/` home ratified across the closing review).

---

## ADR-013 — Phase 2 Step 3: UX/design decisions (staleness-marking principle + 6 walk-through decisions)

**Date:** 2026-05-28
**Status:** Accepted
**Phase:** 2 (Step 3 walk-through lock; consolidates the UX/design decisions from the 6-cluster flow drill + 2-sitting F/CTO walk-through; drives Step 4 wireframing + supplies Phase 3 ARCH consumption inputs)

**Context.** Phase 2 (UX & Design) ran in parallel with Phase 3 per [ADR-012](#adr-012). Phase 2 Step 2 drilled all six PRD §2 user-story clusters into flow documents in dependency order (§2.4 cross-cutting → §2.1 net worth → §2.2 asset allocation → §2.3 spending/income → §2.5 estimated taxes → §2.6 monthly report/convergence), each closed via UX draft → PM traceability consult → (Security Reviewer where security-load-bearing) → F/CTO ratification. The drill produced one ratified global principle (D1) mid-stream and surfaced six parked cross-cutting decisions (P1–P6). Step 3 was a full 2-sitting F/CTO walk-through (sitting 1: §2.4/§2.1/§2.2/§2.3; sitting 2: §2.5/§2.6) followed by a one-at-a-time decision pass. The flow documents + per-cluster consult records are working artifacts at `temp/phase-2-flows-*.md` + `temp/phase-2-decisions-log.md` (gitignored per `feedback_working_artifacts_temp_not_docs`); this ADR is the committed, decision-grade consolidation — and the durable bridge for the Phase-3 ARCH handoffs the gitignored logs would otherwise not carry forward.

**Decisions.**

### Decision 1 — D1: staleness-marking surface scope is illustrative, not exhaustive (GLOBAL)
The §2.4.4 non-silent-staleness commitment's enumerated surface list is **illustrative**. Governing rule: **every derived aggregation that consumes stale-account data carries the staleness marker; aggregations are never silently presented as fresh** — including surfaces the §2.4.4 list omits (headline NAV, delta panel, reference dates, `nav-asof-timestamp`, §2.2.3 sub-allocation, §2.3 rollup/drill, §2.5 tax tables, §2.6 report sections). Applies globally; downstream clusters do not re-litigate. Ratified 2026-05-27 (expands a locked commitment's realized surface set → F/CTO ratification). Security Reviewer concurred: strictly-more-conservative, no new attack-surface category.

### Decision 2 — P1: app-level navigation = persistent left sidebar
Always-visible left nav for the ~6 surfaces + Settings. Chosen for the density-first desktop power-user archetype; scales as destinations grow; needs a collapse affordance for narrow viewports. (Over top-tabs / hub-and-spoke drill-down.)

### Decision 3 — P2: Net Worth information hierarchy = number-first, dense single-canvas
Headline NAV + deltas lead → 60-mo trend → composition table, all co-visible on one scrolling canvas; no within-surface sub-tabs (surface-switching is the sidebar's job). (Over trend-first / breakdown-first.)

### Decision 4 — P6: Cash Flow information hierarchy = category×period table (PRD-faithful)
The Income/Expenses × {Month/Q1–Q4/YTD} rollup anchors the surface; per-account drill-down + Historical Expenditures chart secondary. (Over transaction-stream / calendar.)

### Decision 5 — P3: new-symbol classification surfacing = hybrid
The allocation table's `Unsorted` row shows unclassified symbols in-context AND deep-links to a dedicated classification queue for bulk work. (Over queue-only / inline-only.) Consistent with onboarding's New-Symbol-Classification-Queue.

### Decision 6 — P4: re-auth/staleness banner = top chrome bar, conditional, clean-when-healthy
Banner sits in the top chrome (above content, right of the sidebar). **"Persistent" = conditional-persistent:** appears ONLY when a re-auth-required or staleness condition exists; while live it shows on EVERY surface, does not auto-dismiss, and cannot be casually dismissed until the underlying issue resolves. **When healthy → no banner (clean chrome); absence-of-banner = all good.** No always-on health chip (the §2.4 connection-status-chip is not used as an always-present healthy-state indicator; per-account sync status remains available on the Accounts Hub on demand).

### Decision 7 — P5: planning-value editing affordance = settings-UI only (all four)
A dedicated Settings area is the **sole** edit + storage home for all four user-authored planning values: §2.2 allocation `%Target`, §2.3.2 income/expense targets, §2.5.2 tax brackets, §2.6 owner-id header. **No inline editing anywhere** (F/CTO chose pure settings-UI over the best-of-both settings-UI+§2.2-inline option). Supersedes UX's §2.2 inline-cell lean — `alloc-target-edit` routes to Settings. Storage = ADR-005 / Lock-14 settings-store family.

**Consequences.**

- **Step 4 wireframing consumes these directly:** sidebar shell + conditional top-chrome banner + a Settings area housing all 4 planning-value editors (no inline target editing) + single-canvas Net Worth + table-anchored Cash Flow + Unsorted-row→queue deep-link.
- **Phase-3 ARCH handoffs (consolidated here so they survive the gitignored logs):**
  - **A1–A3 (inactive-Plaid lifecycle, from §2.4 PM-1/Sec):** inactive suspends the scheduled-poll for the Item (A1); webhook signature verification (RT-05) + SD-14 state-history recording CONTINUE for inactive Items, only the user-facing surface is suppressed (A2); inactive does NOT delete the SD-03 token (retain per `bounded-Item-active-only`), revoke-on-inactive is NOT V1, V2 un-share = Plaid `/item/remove` + token deletion (A3). Compose with [ADR-011](#adr-011) Decision 8 + Decision 1 (§6 privileged-context-write).
  - **A4 (wash-sale, from §2.5 PM-2):** the §2.4.3 sell-transaction gains a user-marked wash-sale flag + user-entered disallowed-loss field; the Lock-10 immutability mechanism (mutable-annotation vs reverse-and-replace) is Architect/Sec's call under [ADR-011](#adr-011) Appendix-B flag (j); validation: disallowed-loss ≤ realized loss on the transaction + tenant-scoped.
  - **H1 (planning-value write-path):** all four P5 surfaces inherit the Lock-14 settings-store fence (Zod `.strict()` mass-assignment + numeric adversarial battery + tenant-scoping); the §2.2 `%Target` write is a per-Sub-Cat **keyed array** → the Sub-Cat key must be validated against the seeded taxonomy (no forged/cross-tenant key); §2.5.2 brackets are multi-row keyed.
  - **H2 (as-of-date):** §2.3.3 (client-toggle) + §2.6 (server-derived) reuse one Lock-15 mechanism; tenant-isolation independent of the date filter; RT-25.
  - **`nav-asof-timestamp` (Lock-8-derived):** Architect confirms `pfin.nav` exposes a usable last-current-NAV-computation timestamp + sets the stale-materialization warning threshold.
  - **RT-13 tracks D1:** widening the staleness surface set widens RT-13's verification scope — every newly-realized staleness surface inherits the requesting-tenant-scoped credential-state-resolution requirement (Phase-3 + Phase-6 PR-review fence).
  - **§2.6 injection invariants:** INV-1 — plain-text-only commentary/owner-id is security-load-bearing (the V2+ markdown path is a security-surface expansion requiring a Sec re-touch, NOT a harmless refinement); INV-2 — output-encoding must span HTML view + PDF export and couples to Appendix-B flag (a) (PDF render-path open). RT-11 (commentary) + RT-12 (owner-id) land at the mandatory §4 Sec authoring.
  - **Seed-content recommendation:** the cash-flow taxonomy seed should include a catch-all "Uncategorized" Sub-Cat (→ [ADR-004](#adr-004) / Architect Phase-3 bootstrap) so every transaction always sits in a visible bucket (keeps the §2.3 "no review queue" decision robust).
- **Follow-up — Phase 2 flow-artifact committed home:** the six flow documents remain in gitignored `temp/`; their committed home (e.g., a `docs/UX/` artifact) is an open decision, naturally resolved when wireframes + design system land. Tracked, not blocking.
- **No supersession.** Composes with [ADR-011](#adr-011) (Phase-3 input surface) + [ADR-012](#adr-012) (parallel execution). Per-cluster bullet-level detail lives in the gitignored `temp/phase-2-*` working files.

**Approved by:** F/CTO (2026-05-28, via the Step 3 walk-through: 2-sitting flow review signed off + P1–P6 decided one-at-a-time; D1 ratified 2026-05-27 during the drill).

---

## ADR-012 — Parallel Phase 2 (UX & Design) + Phase 3 (Technical Architecture) execution

**Date:** 2026-05-27
**Status:** Accepted
**Phase:** Phase 1 → Phase 2 + Phase 3 transition (R-outer-frame sequencing under [ADR-009](#adr-009) Decision 2)

**Context.** Phase 1 (Product Definition) closed 2026-05-26 with all 16 substantive architectural locks ratified + candidate P3 disposed + Lock 9 amended (per [ADR-011](#adr-011)). The R/P/I+V outer frame per ADR-009 Decision 2 places mosko's Phases 1 + 2 under the template's "Research" outer category; Phase 3 (Technical Architecture) opens the "Plan" outer category. At phase-transition invocation, three sequencing options for Phase 2 vs Phase 3 were available: (1) Sequential R-strict — fully close Phase 2 before opening Phase 3; (2) Defer-Phase-2 — open Phase 3 immediately, Phase 2 lands post-ARCH or alongside Phase 4; (3) Parallel execution — open both phases concurrently with explicit coordination at coupling touchpoints.

PRD §2 already locks 32 V1 user stories at decision-grade clarity, so Phase 3 has a complete requirements surface independent of Phase 2 flows. ADR-011 + the 13 Phase 3 carry-over tasks give Architect a fully-loaded immediate work surface. Phase 2 deliverables (flows + wireframes + design system + tokens) have no upstream blockers either — PRD §2 is their input. The only hard coupling point between the two phases is frontend framework choice (Phase 3 Architect deliverable) ↔ design tokens format (Phase 2 Visual Designer deliverable); both can begin work independently and converge at the framework-choice gate.

**Decision.** Open Phase 2 and Phase 3 concurrently per option 3 (parallel execution). Architect leads Phase 3 ARCH drafting from PRD §2 + ADR-011 + locks log + 13 carry-overs; UX Designer + Visual Designer lead Phase 2 flows → wireframes → design system → tokens from PRD §2. Both phases work in separate team contexts (`phase-3-arch-drafting` + `phase-2-ux-design`, created at their respective work openings); coordination touchpoints are explicit at the framework-choice ↔ design-tokens-format coupling. Both phases close together at the Phase 4 (Project Scoping) entry gate — Phase 4 consumes both ARCH HTML and the design-system spec. If one phase finishes before the other, the further-along phase marks ✅ Complete in its own section but the WORKFLOW.md header pointer remains at "Phase 2 + Phase 3 (parallel)" until both close.

**Why.** PRD §2 + ADR-011 already provide both phases with fully-specified inputs; serializing them adds calendar without unlocking new information. The chain-attack-catch density observed in Phase 1 Step 4 (Sec found 8 catches Architect missed at joint reviews — see [ADR-011](#adr-011)) suggests Phase 3 will benefit from F/CTO bandwidth focused on architectural decisions; parallelizing Phase 2 reduces idle-Phase-2-roster cost without diluting that bandwidth (Phase 2 lead agents — UX + Visual Designer — don't compete with Architect or Sec for F/CTO review cycles). The decision-by-Phase-4 gate provides a natural convergence point.

**Alternatives considered.**

- **Sequential R-strict (option 1).** Rejected — tightest R-outer-frame discipline but trades calendar for no information gain; Phase 3 inputs are already complete at PRD §2 + ADR-011. The R-outer-frame discipline per ADR-009 Decision 2 is a grouping convention, not a hard sequencing constraint — phases within the same outer category can overlap when their input surfaces are independent.
- **Defer-Phase-2 (option 2).** Rejected — defers a planning artifact without surfacing a forcing function. Phase 2 deliverables eventually need to land before Phase 5 (Workshop Setup) regardless; deferring creates a downstream cliff rather than spreading the work. Visual Designer's "mandatory palette + typography F/CTO checkpoint" gate also benefits from early scheduling.

**Coordination expectations.**

- **Coupling touchpoint:** Architect's frontend framework choice (Phase 3) ↔ Visual Designer's design tokens format (Phase 2). Visual locks the abstract tokens taxonomy (framework-agnostic) without Architect input; tokens-as-code finalization waits on the framework-choice gate, with a framework-agnostic intermediate-format fallback (Style Dictionary / W3C design-tokens JSON) available at F/CTO's call if Phase 3 slips substantially.
- **Team-mode coordination:** Phase 2 + Phase 3 create separate teams (`phase-2-ux-design` + `phase-3-arch-drafting`) per [ADR-003](#adr-003); team-lead (main session) bridges them. Cross-team coordination at the coupling touchpoint routes through team-lead, not direct peer-to-peer (per the Step 4 synthetic-team routing-discipline lesson — see ADR-011 Decisions 1-4 Consequences + WORKFLOW.md Phase 1 Step 4 lessons-learned).
- **Decision-by-Phase-4 gate:** both phases close before Phase 4 (Project Scoping) opens. If one phase lags, Phase 4 waits. No partial-Phase-4 entry under one-phase-only closure.
- **Pointer convention:** WORKFLOW.md header current-phase pointer stays at "Phase 2 + Phase 3 (parallel)" until both phases close. Individual phase sections advance their own Status independently.
- **Sec re-consult discipline:** Phase 3 architectural surfaces inherit the Step 4 Sec joint-review pattern (chain-attack-catch density warrants mandatory Sec re-consult at every surface lock per [ADR-011](#adr-011) Decision 4 §10 defense-in-depth fencing). Phase 2 does not require Sec re-consult (no security-load-bearing surface in flows / wireframes / tokens).

**Cross-references.**

- WORKFLOW.md §"Phase 2 — UX & Design" + §"Phase 3 — Technical Architecture" — both phase sections receive Detailed-steps subsections at this phase-transition PR (drafted by UX + Visual Designer teammates + Architect teammate in team `phase-2-3-entry` on 2026-05-27).
- [ADR-009](#adr-009) Decision 1 (team-lead as main session) + Decision 2 (R/P/I+V outer frame).
- [ADR-011](#adr-011) — Phase 3 input surface (16 locks + 4 meta-patterns + 13 carry-overs).
- [ADR-003](#adr-003) — team-mode coordination conventions inherited by Phase 2 + Phase 3 team setup.
- `docs/handoff-prompts.md` § Phase-transition prompt — invoked to produce this ADR + WORKFLOW.md updates + MILESTONES update.

**Approved by:** F/CTO (2026-05-27, via phase-transition sequencing chooser at session start; locked option 3 "Run Phase 2 and Phase 3 in parallel" against options "Defer Phase 2; invoke Phase 3 now" and "Fast-track Phase 2 first (sequential)". 9 substantive flags from teammate drafts ratified at-recommend across the walk-through.).

---

## ADR-011 — Phase 1 Step 4 architectural drilling: 16 lock decisions + 4 project-convention meta-patterns

**Date:** 2026-05-26
**Status:** Accepted
**Phase:** 1 (Step 4 lock; consolidates 16 architectural decisions + 4 cross-cutting project-convention meta-patterns ratified during the active drilling cycle 2026-05-25 → 2026-05-26; lands the canonical-reference layer for Phase 3 implementation work; Phase 3 entry gate)

**Context.** Phase 1 Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate per [ADR-009](#adr-009) Decision 2) executed an active drilling cycle against the 16 substantive architectural flags + 3 candidate-P flags surfaced at Pass 1 framing (`temp/step-4-arch-overview-pass-1.md`). Per Architect's wave sequencing, the 16 flags drilled across 5 waves: Wave 1 (Flag #1 RLS baseline + alphanumeric track P1/P2/E1a/E2 + Flag #3 taxonomy + Wave 1 step 2 Flag #10/#12 NAV+CPI); Wave 2 (Flag #4 reconciliation + Flag #5 manual-entry); Wave 3 (Flag #6 snapshot store + Flag #7 snapshot-vs-live render); Wave 4 (Flag #8 workers + Flag #9 settings + Flag #13 as-of-date); Wave 5 (Flag #11 cost feasibility — synthesis drill last). Each lock followed the project pattern: Architect drills A/B/C options + lean; Sec joint review on architecturally Sec-load-bearing surfaces; F/CTO ratifies with mods. The cycle produced 16 locks closed + candidate P3 (FMP/stock-screening incumbent-exceeds-V1) resolved as V1-default + Lock 9 amended at Lock 15 (re-introduces `account_trans.created_at` as IMMUTABLE post-INSERT).

Drilling output: 16 lock entries totaling ~1200 lines of locked architectural commitment with full Sec-mod inventory at the authoritative state file `temp/step-4-locks-log.md` (gitignored per `feedback_working_artifacts_temp_not_docs`). Sec found 23+ V1-ship-blockers across reviews including 4 instances of the cross-tenant FK-bypass attack family + 8 distinct chain-attack catches that Architect's drills missed but Sec's joint-review surfaced. 13 Phase 3 carry-over tasks booked in team task tracker `phase-1-step-4` (Tasks #11/#13/#15/#16/#17/#20/#26/#29/#32/#33/#34/#35/#36) with full per-lock Sec-mod implementation descriptions. 8 locks-log meta-patterns identified across the drilling cycle — 4 emerged as project-convention candidates ratified at Step 4 close per Decisions 1-4 below.

This ADR establishes the canonical-reference layer for the 16 locks at the consolidation scale appropriate for Phase 3 consumption — bullet-level per-lock content elaborates at the locks log; ADR-011 captures the decision shape, rationale, and cross-flag implications at the granularity Phase 3 ARCH drafting (Phase 3) + Phase 5 migration design + Phase 6 PR review will consume. Bullet-level commitments at PRD/SECURITY HTML artifacts remain mutable through future revisions if the canonical references hold steady; new architectural commitments require ADR-011 amendment or supersession.

**Decisions.**

### Decision 1 — Privileged-context-write discipline for non-JWT writes (project-convention meta-pattern §6)

For all non-JWT writes (webhook handlers + cron workers + scheduled-poll workers + future privileged contexts), V1 commits to a four-clause discipline ratified across Locks 4 + 7 + 11 + 13:

- **(a)** Ingress under no JWT (writer is not a user session).
- **(b)** Writes execute under `service_role` (bypasses RLS by design at the DB layer).
- **(c)** Tenant correctness derives from code, not RLS (RLS can't help when there's no JWT; explicit `users_id` binding at the entry boundary).
- **(d)** Explicit audit log captures the tenant-resolution chain (forensic-detectability when the code's tenant-decision goes wrong).

**Origin:** Lock 4 mod #6 (Plaid webhook handler). **Confirmed reusability:** Lock 7 NAV worker; Lock 11 monthly_report cron mod #2; Lock 13 `pfin_back_etl` worker architecture (concretized as `TenantBoundConnection` class + same-transaction audit-log per Lock 13 mods #3 + #4). **Forward applicability:** Lock 9 dedup writes (Plaid sync path); any V2+ privileged-context-write surface emerging.

**Why ADR-able:** four consecutive locks surfaced the same discipline; expected to recur at every future privileged-context surface. Names the pattern so future surfaces can be evaluated against it without rediscovering. New V1 or V2 privileged-context surface MUST adopt the four-clause discipline at design time.

**Cross-references:** Locks 4 / 7 / 11 / 13. `temp/step-4-locks-log.md` §6 meta-pattern. Sec confirmed reusability at every joint flag review.

### Decision 2 — Immutable + INSERT-new-version discipline for audit-class surfaces (project-convention meta-pattern §7)

For all audit-class surfaces (financial-correctness data + compliance-attestation-bearing tables), V1 commits to immutable rows at the policy/trigger layer + INSERT-new-version regeneration where corrections are required. Pattern ratified across Locks 9 + 10 + 11:

- Rows are append-only at the RLS policy + DB-trigger layer (UPDATE/DELETE blocked across both `authenticated` AND `service_role` roles).
- "Updates" become NEW rows with explicit relationship to predecessor (FK or status ENUM).
- Audit trail is the table itself; no separate audit table needed.
- Composes with §6 privileged-context-write discipline — service_role contexts still can't UPDATE due to DB-trigger layer.

**Surfaces ratified:**
- **Lock 9 (reconciliation_event + reconciliation_event_trans):** append-only RLS; tamper-proof audit trail.
- **Lock 10 (account_trans):** immutable rows; edits via reverse-and-replace INSERT (`is_reverse BOOLEAN` + `replaces_trans_id` FK).
- **Lock 11 (monthly_report):** immutable per row; regeneration via INSERT-new-version with `generation_status` ENUM (draft → final → superseded); partial UNIQUE on `(users_id, target_month) WHERE generation_status = 'final'`.

**Why ADR-able:** §SECURITY §4.6 audit-log retention commitment held by-construction (no UPDATE means no audit gap); money-correctness failure modes (silent drift, silent cascade-skip) eliminated by immutability; cross-tenant chain attacks (Decision 3 below) close cleanly via matched-account WITH CHECK + immutability of the chain.

**Cross-references:** Locks 9 / 10 / 11. `temp/step-4-locks-log.md` §7 meta-pattern. Lock 12 Decision 16 below strengthens to fence tenant anchor (`users_id`) + audit-load-bearing columns (`target_month`, `account_id`), not merely value columns.

### Decision 3 — Cross-tenant FK-bypass attack family + matched-tenant validation (project-convention meta-pattern §8)

Any FK-shaped reference column (single FK, self-FK, INTEGER[] array element) that crosses an isolation boundary requires **explicit matched-tenant validation** — DB-level WITH CHECK constraint (single columns) or BEFORE INSERT/UPDATE trigger (array elements PostgreSQL can't express declaratively). PostgreSQL FK constraints are silent on RLS: the constraint validates the referenced row exists; it does NOT validate the referenced row is within the referring user's isolation scope. Without explicit matched-tenant validation, FK-shaped columns create chain-attack surfaces that defeat RLS protection at the schema layer.

**Canonical family = eleven labeled instances (#1–#11), nine DDL-realized after migration `023`; #3 + #4 canonically-locked but DDL-deferred to V1.3+; the labels are non-contiguous — #11 was realized EARLY at `019` (distinct provenance, outside the `015`–`023` (g) batch).** This enumeration is authoritative going forward; the historical operational running tallies ("7 → 8", "5 → 10", "10", "11") are the pre-reconciliation grain and are **superseded** — see the SELF-284 fold-in resolution below. Per instance: FK column → target · migration (or **UNREALIZED**) · fence pattern · one-line provenance. Fence patterns are three classes — (P1) **matched-tenant, local anchor** (referring row has its own `users_id`; `new.users_id` equality, 012-shape); (P2) **novel global-OR-matched-tenant** (referenced `pfin.asset` is valid IFF GLOBAL [`asset.users_id IS NULL`] OR owned [`asset.users_id` = the referring tenant]); (CR) **chain-resolved matched-tenant/account** (referring row has no own `users_id`; the fence JOINs the account chain to resolve the owning tenant). Every fence is SECURITY INVOKER + `set search_path = ''` + NULL-safe fail-closed (allowlist stays 3 — no DEFINER).

- **#1 — Lock 9 mod #1:** `pfin.reconciliation_event_trans (event_id, account_trans_id)` → junctions `pfin.account_trans` · migration `005` · **CR** matched-**account** (`fn_reconciliation_event_trans_matched_account`, BEFORE INSERT; no own `users_id` — matches the two referenced rows' `account_id`) · append-only reconciliation join.
- **#2 — Lock 10 mod #2:** `pfin.account_trans.replaces_trans_id` self-FK → `pfin.account_trans` · migration `004` · **CR** matched-**account** (`fn_account_trans_matched_account`, BEFORE INSERT; account_trans has no own `users_id`, tenant via `account_id → account_users`-JOIN) · reverse-and-replace edit chain.
- **#3 — Lock 11 mod #9:** `pfin.monthly_report.included_reconciliation_event_ids INTEGER[]` → `pfin.reconciliation_event` · **UNREALIZED — V1.3+** (monthly_report not yet migrated) · **P1** matched-tenant array-element BEFORE INSERT/UPDATE trigger (validates every array element's `reconciliation_event.users_id` = row's `users_id`; monthly_report has own `users_id`).
- **#4 — Lock 12 Architect-spec + mod #2:** `pfin.monthly_report_account_snapshot.account_id` → `pfin.account` · **UNREALIZED — V1.3+** · **P1** matched-tenant trigger + parent-immutability extension fencing `monthly_report.users_id` UPDATE post-creation.
- **#5 — SELF-201 / [ADR-025](#adr-025):** `pfin.account.sub_cat_id` → `pfin.user_taxonomy(id)` · migration `012` · **P1** matched-tenant, local anchor (`fn_account_matched_sub_cat`, BEFORE INSERT OR UPDATE, INVOKER, NULL-safe; both sides per-user) · first genuine post-authoring addition (deferred enumeration pass, F/CTO-ratified 2026-07-05).
- **#6 — [ADR-027](#adr-027) (g) / R-14 fold:** `pfin.account.linked_source_id` → `pfin.linked_source(source_id)` · migration `015` · **P1** matched-tenant, local anchor (`fn_account_matched_linked_source`; mirrors `012`; both per-user) · realizes `007`'s deferred FORK-B (Plaid item link, generalized provider-agnostic).
- **#7 — [ADR-027](#adr-027) (g):** `pfin.account_trans.security_id` → `pfin.asset(asset_id)` · migration `017` · **P2** novel global-OR-matched-tenant, site 1 (`fn_account_trans_security_asset`, BEFORE INSERT; account_trans resolves tenant via the account chain) · investment ledger over `016`'s G1 hybrid registry.
- **#8 — [ADR-027](#adr-027) (g):** `pfin.user_asset_category.sub_cat_id` → `pfin.user_taxonomy` · migration `022` · **P1** matched-tenant, local anchor (junction has own `users_id`; 012-shape) · allocation junction.
- **#9 — [ADR-027](#adr-027) (g):** `pfin.user_asset_category.asset_id` → `pfin.asset` · migration `022` · **P2** novel global-OR-matched-tenant, site 2 · allocation junction (referenced asset is global-OR-owned).
- **#10 — [ADR-027](#adr-027) (g):** `pfin.account_trans_annotation.sub_cat_id` → `pfin.user_taxonomy` · migration `023` · **CR** matched-tenant (`fn_account_trans_annotation_matched_sub_cat`, BEFORE INSERT OR UPDATE; annotation has no own `users_id` — resolves via `trans_id → account_trans → account.users_id`; C-NOTE shape (a), Sec-ratified) · transaction annotation overlay; LAST label of the (g) `015`–`023` 5→10 batch.
- **#11 — [ADR-027](#adr-027) (p) / SD-A1:** `pfin.holdings_checkpoint.security_id` → `pfin.asset` · migration `019` (realized **EARLY** — was slated V1.3) · **P2** novel global-OR-matched-tenant, site 3 (`fn_holdings_checkpoint_security_asset`, BEFORE INSERT; mirrors `017`, load-bearing under the service_role provider-sync write path) · distinct provenance, OUTSIDE the (g) batch — the uniform-valuation model pulled it into V1 without renumbering any committed label.

**Why ADR-able:** four consecutive flags surfaced the pattern; default-discipline lowers the cognitive load on Sec reviews (forces explicit consideration at design time rather than catching ad-hoc per surface). Composes with §6 + §7 + §10 to form a defensive layer on top of RLS. Any new V1 or V2 surface introducing a FK-shaped reference column (including INTEGER[] arrays) MUST include matched-tenant validation in its DDL.

**Cross-references:** Locks 9 / 10 / 11 / 12. `temp/step-4-locks-log.md` §8 meta-pattern. Decision 16 below (Lock 12) strengthens the family with tenant-anchor-immutability extension. Decision 19 below (Lock 15 / Flag #13) confirms NOT a new instance at V1 (settings-table writes are user-session-bounded; FK-bypass becomes live only at V2+ live-tax-API ingestion under service_role).

**Instance-count grain annotation (2026-07-02 / Phase 6 Build Loop, SELF-190 doc-followup).**

Decision 3's canonical enumeration above ("Four V1 instances locked" — Lock 9 mod #1 · Lock 10 mod #2 · Lock 11 mod #9 · Lock 12, each ordinally numbered *first* / *second* / *third* / *fourth* at Decisions 13 / 14 / 15 / 16; Locks 14 + 15 explicitly declined to add per Decisions 18 + 19) is UNCHANGED by this annotation. Recorded here is a count-grain discrepancy surfaced at Sec joint-review of migration `006` (SELF-190):

- **Canonical count = 4.** The FK-bypass family instances locked at ADR-011 authoring are exactly the four enumerated above; each is ordinally numbered in its originating Decision. No fifth-or-later instance is enumerated anywhere in `DECISIONS.md`.
- **The "7" is an un-reconciled operational count, NOT canonical.** A family count of "7" appears in the Phase-6 migration headers (`004` "Sec-pinned at 7"; `005` "stays 7 … would push 7→8"; `006`), in the Architect + Security-Reviewer agent definitions, in `supabase/CLAUDE.md`, and in the `spawn-sec-joint-review` skill — but no artifact *enumerates* three instances beyond the canonical four.
- **Provenance is partly a family-conflation.** The additions cited operationally (Wave-5 SELF-259 / SELF-261) do not resolve to Decision-3 instances: SELF-259 is a **Lock 14 per-domain _settings_ table** migration whose own scope note reads "Family stays at 5" — a distinct family (`planning_target` + `tax_bracket_schedule` + `tax_bracket_row` + `owner_identification`), not the FK-bypass family — and SELF-261 (`transaction_annotation`) is an unbuilt Wave-5 backlog item nowhere numbered as a Decision-3 instance. The "7" is thus contaminated by conflation of the Lock-14 settings-family-of-5 with this cross-tenant FK-bypass family.
- **Reconciliation is deferred (Option B), tracked.** Full `4 → N` reconciliation — should genuine post-authoring FK-bypass instances exist (candidates to *evaluate*, not asserted: any Wave-2–5 FK-shaped cross-tenant column, e.g. SELF-261 `transaction_annotation` → `account_trans`; `user_taxonomy` FK references at SELF-234 / SELF-248) — requires an Architect enumeration pass (ADR authorship) numbering each addition with locking provenance, then Sec joint-review and F/CTO ratify. This annotation is the truthful interim record, not the reconciliation itself; it asserts no specific N beyond the locked 4.

**Maintenance note.** Decision 3's canonical "Four V1 instances locked" enumeration stays UNCHANGED until an Architect enumeration pass lands the numbered additions under Sec joint-review; downstream "7" references should be read as operational-not-canonical until then.

**Enumeration-pass resolution (2026-07-05 / Phase 6 Build Loop, SELF-201 / migration `012` / [ADR-025](#adr-025)).** The deferred Architect enumeration pass called for above has now landed its **first genuine post-authoring addition: canonical instance #5** — `pfin.account.sub_cat_id → pfin.user_taxonomy(id)` (both sides per-user; the exact chain attack Decision 3 fences; realized as `fn_account_matched_sub_cat` BEFORE INSERT OR UPDATE trigger at `012`). F/CTO-ratified 2026-07-05; Sec numbering sign-off at the `012` joint-review. Consequences for the grain notes above: (a) the canonical enumeration is now **Five**, not Four (see the numbered list at the top of this Decision); (b) "Canonical count = 4" reads **canonical count = 5** as of this resolution; (c) the contaminated operational "7 → 8" is **superseded** — #5 is the truthful next canonical instance, and downstream "7"/"8" references (incl. [ADR-024](#adr-024)'s line noting the pending SELF-201 FK as "family 7→8") should be read as the pre-resolution operational count, now corrected to canonical #5. The Lock-14-settings-family-of-5 conflation that inflated the operational "7" is NOT part of this family and is not renumbered here. Further genuine FK-bypass instances continue to extend the canonical count by the same enumeration-pass discipline (number + locking provenance + Sec sign-off).

**Enumeration fold-in resolution (2026-07-20 / Phase 6 Build Loop, SELF-284).** Following the same enumeration-pass discipline, the full canonical family has now been folded into the numbered list at the top of this Decision (#1–#11). Since the 2026-07-05 resolution above, instances #6–#11 were locked with provenance in [ADR-027](#adr-027) (g) (#6–#10, the `015`–`023` batch) + [ADR-027](#adr-027) (p) / SD-A1 (#11, `holdings_checkpoint.security_id`) and realized across migrations `015`/`017`/`019`/`022`/`023`; migration `023` (SELF-283) landed the last label (#10), at which point **all 11 canonical labels carry a stable assignment with locking provenance** — the precondition for this fold-in (it is NOT a convergence-to-completion point: #3 + #4 remain DDL-unrealized). Each instance in the folded list was re-verified against its migration header at authoring (FK column, target, migration number, fence function, fence pattern). **Consequences:**

- **(a) Canonical enumeration is now Eleven** (#1–#11), with **nine DDL-realized after `023`** (#1, #2, #5, #6, #7, #8, #9, #10, #11) and **two DDL-deferred to V1.3+** (#3 + #4, the `monthly_report` + `monthly_report_account_snapshot` family — canonically-locked at Locks 11 + 12, no migration yet; their exact trigger functions are authored when monthly_report is migrated).
- **(b) The operational running tally is RETIRED.** The historical figures — "7 → 8" (2026-07-02 grain annotation), the "5 → 10 fully realized / total 10" framing (which silently OMITTED #11 and was corrected 3× during `022`/`023`), and the standalone "10"/"11" tallies in migration headers/agent-defs/`supabase/CLAUDE.md` — were the pre-reconciliation operational grain, inflated by the Lock-14-settings-family-of-5 conflation flagged above. They are **superseded by the canonical #1–#11 enumeration**, which is authoritative going forward. Downstream artifacts should read the canonical enumeration, not any residual operational count.
- **(c) Labels are non-contiguous by realization order.** #11 (`019`) realized before #8/#9 (`022`) and #10 (`023`); the label ordering follows locking provenance (ADR-027 (g) pre-enumerated #6–#10; (p) pulled #11 into V1 early), NOT migration order — no committed label was renumbered, so no drift was introduced.

The enumeration-pass discipline stands unchanged: further genuine FK-bypass instances extend the canonical count by number + locking provenance + Sec sign-off. The 2026-07-02 grain annotation + the 2026-07-05 enumeration-pass resolution above are retained as the historical ledger of how the count was reconciled; the numbered list at the top of this Decision is the canonical content.

### Decision 4 — Defense-in-depth fencing across surface boundaries + schema-level orthogonality awareness (project-convention meta-pattern §10)

V1 commits to defense-in-depth fencing for security-load-bearing surfaces — fence at MULTIPLE layers simultaneously rather than at any single layer. Three classes of surface accumulated across Locks 13 + 14 + 15:

- **Privileged-context surfaces (Lock 13):** fence at code (`TenantBoundConnection` class + CI grep fence) + CI (no raw `psycopg2.connect()` outside the class) + JWT shape (authenticated-tier-only; dedicated signing key; nonce replay protection) + **infrastructure-credential-presence** (no `SUPABASE_*` env vars in PDF worker container; no Postgres client installed in Dockerfile — preserves Lock 12 mod #1 read-path-only fence by-construction against future-optimization regressions).
- **User-facing direct DB write surfaces (Lock 14):** fence at app-layer (Zod `.strict()` schema validation + mass-assignment prevention; `users_id` from `auth.uid()` not `req.body`) + numeric-input adversarial battery (NaN/Inf/currency-string regex/overflow/scientific-notation/locale-formatted reject) + RLS WITH CHECK at DB layer + DB-trigger backstops (monotonicity; `updated_at` UPDATE-refresh).
- **Schema-level orthogonality awareness (Lock 15 catch on Lock 9):** drop-column corrections MUST be evaluated against ALL downstream PRD commitments, not just the immediate-driver concern. Lock 9 correction #3 dropped `account_trans.created_at` for event-date immutability — orthogonal to row-insertion-time semantics needed by Lock 15 / Flag #13 §2.3.3 retroactive-edit-historical-view commitment.
- **Catalogued §10 instances at V1 (Phase 3 sec-3 addendum, 2026-05-29):** RT-22 (Lock 13 / Decision 17 — PDF worker container credential audit; infrastructure-credential-presence layer; first catalogued instance) + RT-26 (SECURITY §4.2 V1-web-app `SUPABASE_SERVICE_ROLE_KEY` allowlist CI grep fence; code-layer instance on the V1-web-app server-side source surface; framework-agnostic — concrete file-glob enumeration locked in [ARCH §4.1](docs/ARCH/index.html#sec-4-1) at framework ratify; second catalogued instance, HIGH severity + V1-SHIP-BLOCK posture obligation) + RT-27 ([ADR-027](#adr-027) amendment (hh) / SELF-212 — app→worker credential-admission inbound channel; **network-exposure/config layer** — private-network-bind enforcement of the Option-C admission endpoint; **third catalogued instance**, HIGH severity + V1-SHIP-BLOCK posture obligation; catalogued at F/CTO ratify 2026-07-19). **§10 catalogued-instance count = 3** — RT-22 first / RT-26 second / RT-27 third. **RT-22 + RT-26 layer-attributions UNCHANGED** (infrastructure-credential-presence / code-layer respectively); the per-surface three-layer defense language (code + JWT-shape + infrastructure-credential-presence) is UNCHANGED — no surface becomes "four-layer"; the 2→3 is a catalogued-instance-count move, not a per-surface layer-count.
<!-- §10 COUNT-MOVE FLIP-POINT — PERFORMED at F/CTO ratify of ADR-027 amendment (hh) / SELF-212, 2026-07-19: the Catalogued §10 instances list above was moved 2→3 by appending RT-27 third (RT-22 first / RT-26 second / RT-27 third = network-exposure/config layer; RT-22 + RT-26 attributions UNCHANGED; per-surface three-layer language UNCHANGED — no surface became "four-layer"). Canonical count now reads 3. Sec §10 3-axis cross-check clean at the flip (Decision 4 read verbatim). Cross-ref: ADR-008 SELF-212 index amendment (indexes RT-27 in the §4.5 catalog). -->

**Why ADR-able:** the same chain-attack pattern (catching multiple-layer failures) keeps surfacing. Sec found 8 chain-attack catches across the drilling cycle that Architect's drills missed — defense-in-depth is the discipline that makes catches possible at design time rather than at attack time. Composes with §6 (privileged-context-write) + §7 (immutable INSERT-new-version) + §8 (cross-tenant FK-bypass).

**Cross-references:** Locks 13 / 14 / 15. `temp/step-4-locks-log.md` §10 candidate meta-pattern (further-strengthened at Lock 15 schema-level orthogonality). Sec re-pings at every Phase 3 / Phase 6 multi-layer-surface review verify the discipline holds.

**§10 attribution-discipline CHANGELOG (as of 2026-06-01, post-PR-77).**

Decision 4's canonical structure above (Three classes of surface + sub-bullets + Catalogued §10 instances at V1 numbered list) is UNCHANGED by this CHANGELOG annotation. The 3 attribution-discipline drift catches discharged across the Phase 3 ARCH streak are logged here; each catch was surgically fixed in the originating PR + composed into the discipline state below.

- **PR #65 / v1.37 — instance-numbering drift class.** Drift: §10-catalogued-instance numbering attributed incorrectly at a v1 draft surface (canonical ordering per the Catalogued §10 instances bullet above is RT-22 first, RT-26 second). Discharge: surgical wording correction same-PR; memory `feedback_decision_4_instance_ledger_cross_check` codified with instance-numbering scope.
- **PR #66 / v1.38 — layer-attribution drift class.** Drift: §4 Auth row mis-attributed the JWT-shape-layer role (the Auth row supplies the JWT shape consumed by the layer per the Privileged-context-surfaces bullet above + [SECURITY §4.2](docs/SECURITY/index.html#sec-4-2); the layer itself is the RLS predicate at the DB layer). Discharge: Sec v2-mod verbatim wording reshape ("Auth row supplies the JWT shape that the JWT-shape-layer of the §10 three-layer defense consumes"); memory broadened to cover both drift dimensions (instance-numbering + layer-attribution).
- **PR #74 / v1.44 — §8.5 four-layer paraphrase drift class.** Drift: §8.5 paraphrased the four-class composition above where a Decision-4 link would suffice. Discharge: Path B (drop-enumeration-let-link-carry) v2-fix shape codified as sub-discipline at memory `feedback_decision_4_instance_ledger_cross_check`; Path A (verbatim-enumeration-restore) named as the alternative shape when a §-surface ABSORBS-and-restates canonical content for reader convenience; Path B preferred when §-surface section-hint frames REFERENCES-not-ABSORBS.

**Discipline state.** §10 attribution discipline holds CLEAN for **10 consecutive surfaces** on the full three-axis basis (instance-numbering + layer-attribution + V1-SHIP-BLOCK-axis-orthogonality codified at PR #72) — PR #65 / #66 / #67 / #68 / #69 / #71 / #72 / #74 §8 / §9 / PR-A row #4 v2. Path B preference operates with a **6-application track record** (PR #74 §8.5 codification + PR #76 §9 row #5 by-default + PR-A row #4 surgical fixes at §3 line 196 + §4 Auth row line 365 + this CHANGELOG annotation itself + the row #4 audit work). Sec independently verifies the streak at every Phase 3 §-surface joint-review.

**Maintenance note.** Future §10 attribution-discipline drift catches append as new bullets in this CHANGELOG annotation; Decision 4's canonical structure above (Three classes + sub-bullets + Catalogued §10 instances numbered list) stays UNCHANGED by CHANGELOG additions. The annotation is the operational ledger; Decision 4 is the canonical content.

### Decision 5 — Lock 1 / Flag #1: Multi-tenant + RLS Option A (Supabase Auth + native RLS)

**Locked option:** Option A — Supabase Auth + native RLS as V1 baseline + selective Option C overlay deferred to Phase 3 detail design on RT-02 (Plaid Items table) + RT-05 (webhook handler) critical-severity surfaces. **Rationale:** Option A satisfies every PRD/SECURITY lock at zero incumbent-switching cost; Option B portability benefits not load-bearing for single-tenant V1 invite-only-V2 trajectory; selective C-on-A captures financial-correctness blast-radius wins on critical-severity RT surfaces without universal-wrapper maintenance tax.

**Cross-references:** locks-log Lock 1; PRD §1.4 + §7.3; SECURITY §4.1 axis (i); ADR-008 Decision 1 axis (i) baseline; sets foundational RLS stance under which all downstream locks land.

### Decision 6 — Lock 2 / Flag P2: account_users V1-dormant; preserve as-built schema

**Locked option:** Option A — document `account_users` table + `fn_grant_creator_access` trigger + `rd_access`/`wr_access` flags as V1-dormant. PRD §7.3 adds additive bullet acknowledging the dormant per-account ACL primitive. V1 UI does not expose sharing or invitation flows. V2 invite-only expansion enables the UI surface against this scaffolding without a data migration. F/CTO-added guardrail: `feedback_incumbent_exceeds_v1_review` memory established (when incumbent code/schema exceeds V1 PRD commitment, promote to a P-flag with options + ADR; do NOT auto-accept via selective adoption).

**Cross-references:** locks-log Lock 2; PRD §7.3; ADR-008 Decision 1 Axis (i); composes with Lock 3 E1a-B RLS-shape decision. Memory `feedback_incumbent_exceeds_v1_review`.

### Decision 7 — Lock 3 / Flag E1a: account_trans RLS shape (Option B — account_users.rd_access-JOIN)

**Locked option:** Option B — `account_users.rd_access`-JOIN at SELECT; `wr_access` at INSERT/UPDATE/DELETE WITH CHECK. F/CTO override of Architect's Option A lean (created_by-direct) — exercises multi-user RLS infrastructure at V1 so V2 sharing-UI lands against an RLS pattern already in production. Sec blessed with 3 V1-SHIP-BLOCK mods + 1 advisory: (1) tighten `account_users` UPDATE policy via column-level `REVOKE UPDATE; GRANT UPDATE (nickname, notes)` mirroring `user_profile` pattern (without it, tenant A can re-tenant their `account_users` row to tenant B — full cross-tenant R/W leak); (2) elevate `fn_grant_creator_access()` to `SECURITY DEFINER` + verify it fires under V1 RLS; (3) write-path WITH CHECK uses `wr_access`, not `rd_access`; (4) advisory SECURITY annotation noting V1 exercises V2 sharing-shape ACL.

**Cross-references:** locks-log Lock 3; Task #11 Phase 3 carry-over (E1a Sec mods + E1b NULL bug). Sec's load-bearing catch: `account_users` UPDATE-policy cross-tenant-pivot bug — latent under Option A; active under Option B — would have shipped silently.

### Decision 8 — Lock 4 / Flag #2: Plaid integration (Option C — pragmatic hybrid)

**Locked option:** Option C — Supabase Vault/pgsodium column-level encryption on `plaid_items.access_token_encrypted` BYTEA + denormalized token storage + Express/Next webhook signature verification via Plaid SDK HMAC + dedup hybrid (partial-unique-index `(account_id, plaid_transaction_id)` + existing `(account_id, import_hash)`) + append-only `plaid_item_state_history` table (V1 audit-retention commitment per §4.6 requires it). **Sec's 6 mods** (3 V1-SHIP-BLOCK + 3 advisory): (1) pgsodium decrypt-view permission scoped to service_role only + Vault key-management Phase 3 lock; (2) webhook handler explicit `users_id`-binding from `plaid_items.users_id` lookup at the Plaid Item ID; (3) webhook idempotency via `plaid_webhook_id` UNIQUE; (4) ItemUpdate event-state classification mapped to 4-class credential-error enum per §2.4.4; (5) §SECURITY §4.2 webhook-bypass-risk annotation; (6) **privileged-context-write discipline established** (§6 meta-pattern origin). E1a-B dependency: Plaid Items table inherits `account_users.rd_access`-JOIN shape.

**Cross-references:** locks-log Lock 4; Task #13 Phase 3 carry-over (Plaid Sec mods). Sec's load-bearing catch: pgsodium-default-decrypt-view permission gap — would have defeated RT-02 (Plaid Item table RLS critical-severity test) entirely.

**Amendment (2026-07-03 / Phase 6 Build Loop, SELF-196 / migration `007`) — encryption MECHANISM moves from pgsodium-column-BYTEA to Vault-native secret-per-token.** The Option-C locked mechanism ("Supabase Vault/pgsodium column-level encryption on `plaid_items.access_token_encrypted` BYTEA + decrypt-view") proved **non-viable on the pinned greenfield PG-17 stack** at first authoring. **Backend's measured findings** (clean-apply smoke on 001→006): (i) `pgsodium 3.1.8` is *available but not installed*, and (ii) the UUID-keyed pgsodium AEAD overload the decrypt-view requires is **execute-denied for BOTH `service_role` AND `postgres`** — it is owned by `supabase_admin` and granted only to `pgsodium_keyholder`/`pgsodium_keyiduser`; `service_role` holds execute only on a *different* (bigint key_id) overload. pgsodium is additionally **deprecated by Supabase in favor of Vault**. Architect surfaced 3 options with tradeoffs (all Lock-4-adjacent one-way doors): **Option 1** — pgcrypto symmetric + Vault-held master key, *keep* BYTEA (smallest reopen; proven round-trip on-stack); **Option 2** — Vault-native secret-per-token + `uuid` reference, *drop* BYTEA (chosen); **Option 3** — `create extension pgsodium` + a SECURITY DEFINER wrapper for the UUID overload (rejected — adds a DEFINER allowlist entry 3→4 and re-adds the deprecated pgsodium path = durability one-way-door risk). **F/CTO ratified Option 2 on 2026-07-03** on greenfield-sunk-cost-nil + stronger-design grounds (structural credential isolation — the token lives only in `vault.secrets`, never on the `pfin` row; no hand-rolled crypto; Vault is Supabase's forward direction).

**What Option 2 amends** (capability-driven; product behavior — encrypted at-rest token storage, decrypt only under `service_role` — is **identical EXCEPT the retention lifecycle, which moves from cascade-by-construction (drop the row → drop the in-row ciphertext) to requiring explicit secret cleanup** (the token now lives in `vault.secrets`, decoupled from the row lifecycle — hence the backstop trigger below)): (1) `pfin.plaid_items.access_token_encrypted BYTEA NOT NULL` → **`access_token_secret_id uuid NOT NULL`** (a `vault.secrets` handle; ciphertext lives in Vault). Admission via `vault.create_secret(...)` under `service_role` at onboarding (SELF-197). (2) The decrypt view is **`pfin.decrypted_plaid_access_token`** (a `service_role`-only view that JOINs `vault.decrypted_secrets` to `pfin.plaid_items`, exposing only the per-Item token keyed by `(item_id, users_id)` — tenant-gating baked into the view shape per Sec) — **named `pfin.*` not `vault.*`** because `has_schema_privilege('postgres','vault','CREATE')` is FALSE (a migration cannot create objects in the platform-owned vault schema). Sec's original load-bearing catch is preserved **by-construction**: the decrypt surface is `service_role`-only (REVOKE public/anon/authenticated) and structurally scoped to Plaid-item secrets. **Ledger impacts — all UNCHANGED:** SECURITY DEFINER allowlist stays **3** (Option 2 authors no function for the crypto path — Vault fns are platform-owned; the join-view is not a function); the §10 catalogued-instance ledger stays **2** (RT-22 + RT-26 per Decision 4 — the mechanism swap adds/re-attributes no catalogued instance); the Decision 3 FK-bypass family is **flat** (`access_token_secret_id` → `vault.secrets` is a platform-managed *global* secret store, not a `pfin` tenant-scoped FK). **New retention obligation** (Sec AMBER-required at joint-review): the Vault secret lifecycle is decoupled from the row, and `pfin.plaid_items.users_id` is `ON DELETE CASCADE` from `auth.users` — so a user deletion cascade-deletes the row but not the secret, orphaning credential material via a path the SELF-197 `/item/remove` code never sees. `007` adds an `AFTER DELETE` backstop trigger `fn_plaid_items_cleanup_vault_secret` (**SECURITY INVOKER — allowlist stays 3**) that ensures **no orphan by construction via cleanup-or-fail-closed**: if the deleting role holds `DELETE` on `vault.secrets` (`service_role` `/item/remove`, `postgres` admin) it deletes the backing secret; a role with `vault` USAGE but no `vault.secrets` DELETE hits a **legible by-design `insufficient_privilege`** guard message; and a role lacking `vault` USAGE — the real `supabase_auth_admin` GoTrue auth.users-cascade role (`has_schema_privilege('supabase_auth_admin','vault','usage')=false`, measured) — hits a raw `permission denied for schema vault` at the guard's name-resolution, before the custom RAISE. **All three fail-closed → the cascade aborts → no orphan by construction** (the load-bearing invariant); deletion is blocked until Items are removed first (consistent with 004's `account_trans` `ON DELETE RESTRICT` posture). **Safety is structural** — any exception inside an AFTER DELETE trigger aborts the cascade, so no-orphan holds regardless of which error fires; the `has_table_privilege` check + legible message are a legibility optimization for name-resolvable roles, **not** the safety mechanism (remove them and safety still holds — the DELETE itself would raise). Broadening `supabase_auth_admin`'s vault grant just to prettify a rare admin-only path is not worth the posture change. **Sec ruling (SELF-196): fail-closed is CORRECT, not a deferred question** — the SECURITY DEFINER auto-clean alternative would be a **security regression** (deleting the local token while the Plaid Item stays live = an un-revocable grant); Sec would veto the DEFINER trade, so INVOKER + fail-closed stands at allowlist 3. **GDPR-erasure forward-note:** when user-facing deletion lands, the erasure routine MUST enumerate the user's Items → `/item/remove` each (revoke-at-Plaid + `service_role` secret-delete) → THEN delete `auth.users` — which cleans under `service_role` **without** needing DEFINER; the GDPR follow-up must not default to DEFINER (it would reintroduce the un-revocable-grant regression). The Plaid-side revoke (read token → revoke at Plaid → delete row) remains the SELF-197 `/item/remove` hard-gate. **This is a one-way door** (stored secret references bind to the Vault mechanism). Direction F/CTO-ratified 2026-07-03; the authored DDL + this amendment return for **Sec joint-review + F/CTO final sign-off before merge**. AC #2/#3 wording deltas routed to PM for the courtesy nod + Linear update. Detail: migration `007_plaid_platform_schema.sql`.

**Amendment (2026-07-13 / Phase 6 Build Loop, `015` — credential store generalized `plaid_items` → `pfin.linked_source`, R-14 fold).** Per ADR-027's aggregator pivot, the Vault-native credential store generalizes from the Plaid-specific `plaid_items` to a **provider-agnostic `pfin.linked_source`**. The 2026-07-03 Option-2 Vault-native mechanism above is UNCHANGED in every security property — only the table generalizes:

- **Fold mechanism = drop-and-recreate** (`015`): `plaid_items` is EMPTY (Plaid never launched), so `015` DROPs the 4 empty Plaid objects (decrypt view → `plaid_item_state_history` → `plaid_sync_audit` → `plaid_items`) and CREATEs `linked_source` fresh — a single legible canonical shape, zero data-migration cost. NOT a data one-way-door (empty); the load-bearing part is this ADR set landing same-PR.
- **Property preservation** (all from `007`, generalized): `access_token_secret_id` → **`credential_secret_id uuid` (nullable** — manual/import sources carry no Vault secret) WITHHELD from the `authenticated` GRANT (RT-02 structural); `pfin.decrypted_plaid_access_token` → **`pfin.decrypted_source_credential`** (`service_role`-only JOIN view, per-source secret keyed by (source_id, users_id, provider)); `plaid_item_state_history` → **`linked_source_state_history`** (append-only triple-fence; A.4 shape = normalized `status_class` + raw `provider_error_code`); `users_id` sole anchor / direct-owner RLS (NOT Decision-3); **provider discriminator** + `provider_metadata jsonb` (Plaid `plaid_item_id`/sync-cursor/`item_status` → generic `external_connection_id` / `connection_status` / jsonb).
- **Retention backstop — `fn_linked_source_cleanup_vault_secret` (SECURITY INVOKER, allowlist +0), with the A.3 refinement Sec VETTED SAFE:** gate the `has_table_privilege('vault.secrets','DELETE')` check + the secret delete on **`old.credential_secret_id IS NOT NULL`**. This preserves the exact `007` fail-closed-on-auth-cascade property for credentialed rows (secret non-null → guard fires → `supabase_auth_admin` lacks vault usage → cascade aborts → no orphan) AND removes the spurious block for credential-less (manual/import) sources (no vault row exists → clean no-op). Per ADR-023's retention-limb carve-out, `linked_source` **RE-REALIZES** its own backstop (not inherited) and **carries the `007` forward-notes into its comments**: GDPR-erasure no-DEFINER-default + per-provider revoke-then-delete ordering.
- **Decision-3:** `account.linked_source_id → linked_source` (both per-user) is a **NEW matched-tenant instance** (fence `fn_account_matched_linked_source`, `012` shape) — this realizes `007`'s deferred FORK-B (`account.plaid_item_id → plaid_items`), never in the canonical baseline → correct +1 (family instance #6). **Ledgers: DEFINER stays 3, §10 stays 2, Decision-3 5 → 10 across the batch (`015` lands #6).**
- **`linked_source_sync_audit`:** `007 plaid_sync_audit` **also folds here** (`015`, A.5 fold-now — F/CTO-ratified 2026-07-13 + Sec GREEN review #7): generalized to a multi-provider sync audit (add `provider` discriminator; `plaid_webhook_id` → `provider_event_id UNIQUE` idempotency gate), preserving service_role-only + append-only triple-fence. No second Plaid-named orphan is left against the superseded provider model.

### Decision 9 — Lock 5 / Flag E2: acct_number storage class

**Locked option:** Option B — Preserve as-built `acct_number` column on `pfin.account` with masked-rendering convention (4-char suffix display only; full value never user-facing). SD-15 entry NEW (medium tier; tenant-scoped; indefinite). Sec mods (3 advisory): (1) Phase 3 ARCH masked-rendering helper implementation; (2) Phase 6 PR-review fence on full-value disclosure surfaces; (3) §SECURITY §4.6 PCI-DSS scope posture sub-section (V1 not PCI-DSS-scope since `acct_number` is masked-only; V2+ unmasking surface triggers PCI consult).

**Cross-references:** locks-log Lock 5; Task #15 Phase 3 carry-over (E2 Sec mods). New SD-15 entry per §SECURITY §4.4 expansion.

**Amendment (2026-06-25 / Phase 5 Step 4 W2, PR #106):** SD-15 masked-rendering helper implemented as `pfin.fn_mask_acct_number(text)` (migration `002`). Ratified **Option A — pure `IMMUTABLE`/`STRICT` string transform, SECURITY INVOKER default (NOT SECURITY DEFINER)**: it reads no tables and needs no elevated privilege, so it is the masking *primitive*, not the privilege boundary. The "full value never user-facing" guarantee is enforced at app-layer rendering + the Phase-6 PR-review fence on full-value-disclosure surfaces (Sec mod #2 above; QA authors the disclosure-fence test). **Consequence:** the V1 SECURITY DEFINER allowlist is corrected **3→2** (only `fn_refresh_updated_at` + the audit-log insert helper remain DEFINER) — dropping a pure function *tightens* the elevated-privilege surface (Sec-confirmed improvement, not a weakening). Correction applied verbatim across `architect.md` + `backend-engineer.md` + `security-reviewer.md` agent defs. Detail: [CHANGELOG v1.48](CHANGELOG.md#v148--2026-06-25).

**Amendment (2026-06-29 / Phase 6 Build Loop, SELF-187 / migration `003`) — SECURITY DEFINER allowlist extended 2 → 3.** The V1 allowlist gains a third entry: **`fn_grant_creator_access`** — the `pfin.account` `AFTER INSERT` creator-grant trigger, locked to `SECURITY DEFINER` at [Decision 7](#adr-011) / Lock 3 mod #2 (V1-SHIP-BLOCK): *"elevate `fn_grant_creator_access()` to `SECURITY DEFINER` + verify it fires under V1 RLS."* This was a pre-existing Decision-7 lock that the earlier "exactly 2" enumeration (this Decision 9 + the `001` header + `supabase/CLAUDE.md`) did not capture; SELF-187 reconciles it. **DEFINER rationale:** it keeps the V1-dormant `pfin.account_users` ACL table write-locked to this single system trigger (authenticated holds SELECT only for the Lock-3 `rd_access`-JOIN read path) rather than granting `authenticated` a direct INSERT on the dormant table; the INVOKER alternative would open a user-facing write path = a Decision-3-adjacent exposure. **Committed allowlist = 3** (`fn_refresh_updated_at` + the audit-log insert helper + `fn_grant_creator_access`); of these, **authored in migrations so far = 2** (`fn_refresh_updated_at` @ `001` + `fn_grant_creator_access` @ `003`) — the audit-log insert helper remains unauthored. This is **distinct** from the 2026-06-25 "3 → 2" correction above (that dropped `fn_mask_acct_number`, a pure transform; a different transition — not reopened here). The §10 catalogued-instance ledger is a **separate** ledger and is **unchanged at 2** (RT-22 + RT-26 per Decision 4) — the DEFINER-allowlist 2→3 is NOT a §10 change. Reconciled across `supabase/CLAUDE.md` + `architect.md` + the `001` forward-pointer (this PR); `backend-engineer.md` + `security-reviewer.md` reconciliation routed to team-lead (cross-agent-file scope). Authored DDL returns to Sec for 2nd full joint-review.

### Decision 10 — Lock 6 / Flag P1: users_id schema rename

**Locked option:** Sweep `tenant_id` → `users_id` across all V1 user-data tables. PRD §1.4 + §7.3 + SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1 axis (i) ratify the new name. F/CTO-driven rename for V1 single-user-V1 + multi-tenant-from-day-one shape clarity (the column anchors to `auth.users(id)` — `users_id` is the literal semantic; `tenant_id` was a generic shape that implied a tenant table that V1 doesn't have). Phase 3 implementation does the actual DDL rename; PRD/SECURITY/ADR text updates align in Step 4 close PR.

**Cross-references:** locks-log Lock 6; Task #16 Phase 3 carry-over (P1 schema rename + PRD/Sec adoption). Affects all V1 RLS predicates per axis (i).

**Amendment (2026-06-28 / Phase 5 Step 4 close-gate, SELF-186 — greenfield reconciliation).** The `tenant_id` → `users_id` rename was resolved at the **artifact-design layer** in the Step 4 close PR (PRD §1.4 + §7.3 + SECURITY §4.1 + §4.4 + ADR-008 swept the convention). V1 schema is **greenfield** — there is no incumbent built DDL carrying a `tenant_id` column to rename. The foundational migration `001_pfin_foundation.sql` (this close-gate; `pfin` schema + `fn_refresh_updated_at`) therefore **INSTANTIATES** the `users_id = auth.uid()` convention by-construction (documented in the `001` header as documented-convention-only) rather than renaming any built DDL. This annotation reconciles 4 SELF-186 AC clauses that were drafted against a "rename built DDL" assumption now invalid under greenfield (the closed Decision 10 stands; this annotates how it lands at the migration layer):
- **(1) "rename `tenant_id` → `users_id`" clause** — *unsatisfiable as written* under greenfield (no `tenant_id` DDL exists to rename). Reconciled as: `001` instantiates the column-name convention; **documented-convention-only at `001`** (no base table in `001` carries the column).
- **(2) "`tenant_id` gone / no `tenant_id` remains" clause** — *vacuously satisfied* under greenfield (the name was never instantiated in code). **Documented-convention-only at `001`**; the standing CI/grep posture that no migration introduces a `tenant_id` column carries it going forward.
- **(3) "`users_id` is the only RLS-reference column" clause** — the *substantive* clause; **MOVES to the first base-table migration**, where the actual `users_id = auth.uid()` RLS policies + paired table-level GRANTs land. `001` creates no base tables / no policies, so it can only document the convention in its header (which it does) for base-table migrations to inherit.
- **(4) "copy-restored schema snapshot" clause** — *N/A* under greenfield (no incumbent snapshot to copy-restore-then-rename). Reconciled as: foundational author-from-scratch; clause retired for `001`.

`001` adds `fn_refresh_updated_at` — **1 of the 2** locked SECURITY DEFINER allowlist entries per Decision 9 above (allowlist count **unchanged at 2**: `fn_refresh_updated_at` + the audit-log insert helper). **[Forward-pointer 2026-06-29 — superseded by SELF-187 / `003`: the DEFINER allowlist is extended to 3 with `fn_grant_creator_access` per the Decision 9 SELF-187 amendment. The "2" here is the point-in-time count at the `001` close-gate.]** `001` introduces **no** §10 catalogued instance (ledger **unchanged at 2**: RT-22 + RT-26 per Decision 4 above) and **no** Decision 3 FK-shaped column (matched-tenant-validation family count unchanged). New SECURITY DEFINER function ⇒ Sec joint-review-mandatory before landing.

### Decision 11 — Lock 7 / Flag #3: taxonomy migration (Option A — V1 user_taxonomy with seed-only V1)

**Locked option:** Option A — single `pfin.user_taxonomy` table (per-user user-editable taxonomy); V1 seed-only (no UI for taxonomy CRUD); V2+ taxonomy-CRUD-UI as expansion. Two-level Cat × Sub-Cat for asset (§2.2.1) + cash-flow (§2.3.1) + `tax_relevant` boolean + `tax_character` enum per ADR-006 Axis 2. V1 bootstrap seeds from F/CTO's existing-system taxonomy. Sec posture: user-scoped RLS standard; no novel surface. Architect Phase 3 picks the precise DDL shape (single table vs split asset/cashflow tables — Phase 3 decision per App B §2.2 (a) + §2.3 (a)).

**Cross-references:** locks-log Lock 7; Task #17 Phase 3 carry-over (taxonomy migration Option A). Per ADR-006 + ADR-004 Decision C.

### Decision 12 — Lock 8 / Wave 1 step 2 / Flag #10 + #12: NAV + CPI ingestion

**Locked option:** Combined drill — NAV materialized per-month rows in `pfin.nav` (worker computes month-end; Lock 11 monthly_report reads as O(1) lookup) + CPI-U historical import via `pfin_back_etl` (incumbent BLS API integration; back to Dec-2015 NAV anchor per PRD §2.1.3). NAV worker established §6 privileged-context-write discipline reusability (confirmed Lock 4's Plaid webhook pattern extends cleanly to cron workers). Sec mods (2 advisory): (1) NAV materialization tenant-binding follows Lock 4 mod #6 pattern; (2) CPI ingestion is read-only public-data; no new SECURITY surface.

**Cross-references:** locks-log Lock 8; Task #20 Phase 3 carry-over (Wave 1 step 2 Sec mods). `reference_pfin_back_etl` memory.

### Decision 13 — Lock 9 / Flag #4: dedup + reconciliation (Addendum 2 + Lock 9-A amendment per Lock 15)

**Locked option:** Per-transaction explicit reconciliation via `pfin.reconciliation_event_trans` join table (replaces date-range derivation); statement-blessed values on `reconciliation_event` (`statement_balance` + `statement_quantity`); multi-dimension reconciliation support (single trans linked to multiple events); NAV via `eod_price` lookup at read time (no stored NAV column); naming sweep drops `_cents` suffix; trigger logic fix on `holdings_checkpoint`; drop denormalized flags (`is_plug` BOOLEAN — Sub-Cat is discriminator; `mode VARCHAR(4)` — not load-bearing). **F/CTO correction #3 dropped `account_trans.created_at`** (per-transaction model handles retroactive inserts by construction) — **AMENDED at Lock 9-A per Lock 15 (Decision 19 below)**: correction #3 was scope-narrow (addressed event-date immutability); did NOT anticipate §2.3.3 retroactive-edit-historical-view use case. **Lock 15 mod #1 V1-SHIP-BLOCK re-introduces `account_trans.created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` IMMUTABLE post-INSERT** (inherits Lock 10 mod #8 trigger pattern). **Sec's 6 mods + 1 advisory + 1 hardening + 1 forward-fence** including V1-SHIP-BLOCK on append-only RLS + matched-account WITH CHECK (Decision 3 above first instance); cost-basis cascade concurrency control via `SELECT ... FOR UPDATE` row-lock; SD-matrix expansion 14→19 (SD-16 reconciliation_event HIGH + SD-17 holdings_checkpoint medium + SD-18 reconciliation_event_trans low); RT-16 + RT-17 HIGH; §4.6 four-surface audit-family annotation. **ADR-008 amendment required** at Step 4 close documenting Lock 9 correction #3 partial-reversal rationale + SD-00 row light addendum for re-introduced `created_at`.

**Cross-references:** locks-log Lock 9 + Lock 15; Task #26 Phase 3 carry-over (Flag #4 Sec mods + per-transaction reconciliation model). Sec's load-bearing catch: cross-tenant link attack via `reconciliation_event_trans` (FK enforcement silent on RLS).

### Decision 14 — Lock 10 / Flag #5: account_trans immutable + reverse-and-replace

**Locked option:** `account_trans` rows immutable post-INSERT; edits via reverse-and-replace pattern (`is_reverse BOOLEAN` + `replaces_trans_id` FK self-reference; matched-account WITH CHECK per Decision 3). RLS-default-deny on UPDATE + DB-trigger blocking UPDATE across both `authenticated` AND `service_role` (Lock 10 mod #8 pattern — referenced by Lock 14 mod #9 trigger reuse + Lock 15 mod #1 trigger extension). Sec's 10 mods including SD-00 immutability addendum + RT-18 immutability invariant suite + cross-flag chain-attack catch on `replaces_trans_id` self-FK (Decision 3 second instance). §7 immutable + INSERT-new-version discipline ratified at this lock (Decision 2 above).

**Cross-references:** locks-log Lock 10; Task #29 Phase 3 carry-over (immutable account_trans + 10 Sec mods + RT-18). Sec's load-bearing catch: `replaces_trans_id` self-FK cross-account replacement attack.

### Decision 15 — Lock 11 / Flag #6: monthly_report snapshot store (Option B — minimal + read-time composition)

**Locked option:** Option B — minimal report-identity table (`monthly_report` with `included_reconciliation_event_ids INTEGER[]` + `generation_status` ENUM draft/final/superseded) + composition at read time (joins `holdings_checkpoint` + `eod_price` + `account_trans` + `tax_character` + `pfin.nav` at render); immutable + INSERT-new-version regeneration with partial UNIQUE `(users_id, target_month) WHERE generation_status = 'final'`. **Sec's 9 mods** (3 V1-SHIP-BLOCK + 6 advisory) including: V1-SHIP-BLOCK SECURITY INVOKER on read-time composition (no DEFINER bypass); V1-SHIP-BLOCK cron tenant-binding discipline (§6 meta-pattern instance per Decision 1); V1-SHIP-BLOCK immutable INSERT-new-version regeneration (Decision 2 instance — hard-overwrite UPDATE would lose `included_reconciliation_event_ids` + `owner_header_at_generation` history); SD-12 row revision (HIGH; reference IDs + user-input; financial values composed at read time); RT-19 read-time composition tenant-scoping; **mod #9 V1-SHIP-BLOCK `INTEGER[]` matched-tenant trigger** (Decision 3 third instance — INTEGER[] columns can't carry FK constraints on array elements; cross-tenant `reconciliation_event_id` population is real audit-trail-integrity leak).

**Cross-references:** locks-log Lock 11; Task #32 Phase 3 carry-over (monthly_report + 9 Sec mods + RT-19). Sec's load-bearing catch + project-convention consolidation: §7 immutable + INSERT-new-version discipline explicitly named at this lock; INTEGER[] matched-tenant trigger pattern as Decision 3 third instance.

### Decision 16 — Lock 12 / Flag #7: snapshot-vs-live render-path composition (Option A — sibling child table)

**Locked option:** Option A — sibling per-account snapshot child table `pfin.monthly_report_account_snapshot (monthly_report_id, account_id, acct_name_at_generation)` + matched-tenant validation trigger on `account_id` (Decision 3 fourth instance); RLS via parent FK chain; single SECURITY INVOKER composition helper called from all three entry paths (in-app render + PDF export + historical-month view); live-staleness join reads `plaid_items.state` direct (NOT `plaid_item_state_history`); β′ resolution from v1.30 verify-pass binds banner stale-account-name strings to requesting tenant's snapshot only. **Sec's 8 mods** (3 V1-SHIP-BLOCK + 5 advisory) including: V1-SHIP-BLOCK SECURITY INVOKER read-path-only fence on composition helper; V1-SHIP-BLOCK **immutability trigger extended to fence parent `users_id` + `target_month` UPDATE on monthly_report** (chain-attack via parent re-tenant orphaning child snapshot rows from original tenant — Sec's 5th chain-attack catch); V1-SHIP-BLOCK service_role bypass DB-trigger on child table; ON DELETE RESTRICT (not CASCADE); SD-12 child sub-class addendum; RT-13 amendment (SECURITY INVOKER read-path-only fence verification); new RT-20 HIGH (fourth-instance FK-bypass + service_role bypass + parent immutability extension).

**Cross-references:** locks-log Lock 12; Task #33 Phase 3 carry-over (child table + 8 Sec mods + RT-20 + RT-13 amendment). Sec's load-bearing catch: immutability trigger MUST fence the tenant anchor itself (`users_id`) + audit-load-bearing columns (`target_month`, `account_id`), not merely value columns — strengthens Decision 2 (§7) and Decision 3 (§8) jointly.

### Decision 17 — Lock 13 / Flag #8: background-worker architecture (Option C — hybrid)

**Locked option:** Option C — hybrid worker location: `pfin_back_etl` (Python on Coolify; incumbent extended) hosts monthly-report cron + Plaid scheduled-poll + NAV + BLS + FMP; V1 app retains Plaid webhook handler + in-app render path; NEW Node PDF worker container (Puppeteer browser-context-per-render hitting V1 app render URL with short-lived signed JWT under user-session identity). Lock 12 mod #1 read-path-only fence preserved by-construction (HTTP-via-V1-app) + by-infrastructure (Sec mod #2 — no Supabase credentials in PDF worker container). **Sec's 10 mods** (4 V1-SHIP-BLOCK + 6 advisory) including: V1-SHIP-BLOCK PDF worker JWT shape (authenticated-tier-only; dedicated signing key; 60s freshness; nonce replay); V1-SHIP-BLOCK PDF worker no-direct-DB-access infrastructure fence (no `SUPABASE_*` env vars; no Postgres client installed; **§10 meta-pattern instance per Decision 4 — infrastructure-credential-presence layer**); V1-SHIP-BLOCK `TenantBoundConnection`-only CI fence (compile-time complement to runtime SQL-log assertion); V1-SHIP-BLOCK same-transaction audit-log discipline (`emit_audit_log()` on same `conn` in same SERIALIZABLE tx); Puppeteer browser-context-per-render hardening (system-fonts-only fence + Chromium flags `--disable-features=BackgroundFetch,ServiceWorker,BackgroundSync` + cache-disable + per-render PDF metadata clear); **mod #8 cross-language audit-log schema-as-contract** via new `pfin.plaid_sync_audit` table with `source` ENUM discriminator; RT-21 HIGH (PDF worker JWT verification) + RT-22 medium (PDF worker container credential audit); RT-09 + RT-10 amendments. §6 privileged-context-write discipline concretized as `TenantBoundConnection` class.

**Cross-references:** locks-log Lock 13; Task #34 Phase 3 carry-over (`pfin_back_etl` extension + V1 app `/internal/pdf-render` endpoint + Node PDF worker + 10 Sec mods). Sec's load-bearing catch: infrastructure-credential-absence as defense-in-depth layer (future-regression-fence) — §10 meta-pattern (Decision 4) first formal instance. `reference_pfin_back_etl` + `reference_hetzner_cax21` memories.

**[Annotation 2026-06-16 — see [ADR-019](#adr-019) for polyrepo → monorepo topology consolidation; Decision 17's 3-container runtime topology + Lock 13 mod inventory all stand unchanged.]**

### Decision 18 — Lock 14 / Flag #9: settings store (Option B — per-domain tables fully split)

**Locked option:** Option B — four per-domain tables (`pfin.planning_target` + `pfin.tax_bracket_schedule` + `pfin.tax_bracket_row` + `pfin.owner_identification`); greenfield (no incumbent settings tables in `pfin_dash`); UPSERT-in-place + `updated_at`; no edit-history rows (settings NOT audit-class); `tax_year SMALLINT` from V1 day-one for forward-compat-additive multi-year history (V1 reads `EXTRACT(YEAR FROM CURRENT_DATE)` for §2.5.3 in-app + `EXTRACT(YEAR FROM target_month)` for Lock 11 cron — year-boundary-correctness pattern). **Sec's 9 mods** (2 V1-SHIP-BLOCK + 7 advisory) including: V1-SHIP-BLOCK strict typed-input validation + mass-assignment prevention (§10 meta-pattern instance per Decision 4 — user-facing layer); V1-SHIP-BLOCK numeric-input sanitization battery (NaN/Inf/currency-string regex/overflow/scientific-notation/locale-formatted reject); bracket-row monotonicity DB-trigger; schedule+rows replace-all SERIALIZABLE; SD-04 + SD-11 revisions + new SD-23 planning_target medium; RT-23 + RT-24 medium; `updated_at` UPDATE-refresh trigger via `pfin.fn_refresh_updated_at()` (Sec addendum mod #9 post-initial-ratify); forward-compat fence (no JSONB blobs in settings store under any future surface). **NOT a new instance of §8 cross-tenant FK-bypass family at V1** — settings writes are user-session-bounded; chain becomes live only at V2+ live-tax-API ingestion under service_role (Sec re-consult mandatory at that adoption with Lock 12 mod #2-pattern fence becoming V1-SHIP-BLOCK).

**Cross-references:** locks-log Lock 14; Task #35 Phase 3 carry-over (4 per-domain tables + Zod `.strict()` endpoints + monotonicity + `updated_at` triggers + 9 Sec mods + RT-23 + RT-24 + SD-23). Sec's load-bearing catch: app-layer mass-assignment + numeric adversarial battery at the FIRST user-facing direct DB write path outside §2.4 — §10 meta-pattern (Decision 4) user-facing-surface instance.

### Decision 19 — Lock 15 / Flag #13: as-of-date semantics (Option A — app-layer parameter threading) + Lock 9 amendment

**Locked option:** Option A — app-layer parameter threading; V1 app validates request → bound parameter `$as_of_date`; SQL query uses dual-column filter `transaction_date <= $1 AND created_at <= $1`; SECURITY INVOKER composition helper signature extends with `p_data_as_of DATE`; Lock 13 worker entry gains `data_as_of` as second parameter (cron derives last-day-of-prior-month; on-demand derives CURRENT_DATE or end-of-target_month). **Sec's 9 mods** (2 V1-SHIP-BLOCK + 7 advisory) including: V1-SHIP-BLOCK **Lock 9 amendment — re-introduce `account_trans.created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` IMMUTABLE post-INSERT** (reverses Lock 9 F/CTO correction #3 partially; correction #3 was scope-narrow on event-date immutability; did NOT address row-insertion-time semantics required for §2.3.3 retroactive-edit-historical-view); V1-SHIP-BLOCK app-layer DATE input validation battery (Zod `.date()` + tightened range `2015-12-01 ≤ as_of_date ≤ CURRENT_DATE` per NAV anchor floor + no future dates); server-derived-only fence for §2.6 paths (NO client-asserted `data_as_of` for cron + on-demand monthly_report; §2.3.3 drill-down is the ONLY surface where client toggle is legitimate); Lock 11 mod #2 audit-log shape extension with `data_as_of DATE` field; PDF worker JWT integrity (NO `data_as_of` claim; V1 app reads frozen value from audit-log row); new RT-25 medium (parameter-bypass adversarial input; closes Sec Task #23 forward-looking comment #1). **§10 schema-level orthogonality awareness** (Decision 4 third class) ratified at this lock — drop-column corrections must evaluate against all downstream PRD commitments.

**Cross-references:** locks-log Lock 15 + Lock 9 amendment annotation; Task #36 Phase 3 carry-over (Lock 9 schema amendment + V1 app Zod date-input + SECURITY INVOKER signature + Lock 13 worker `data_as_of` + Lock 11 audit-log extension + PDF worker JWT integrity + 9 Sec mods + RT-25). **ADR-008 amendment** documented per Decision 13 above (Lock 9 correction #3 partial-reversal). Sec's load-bearing catch (8th chain-attack catch this Step): schema-level orthogonality cascade.

### Decision 20 — Lock 16 / Flag #11: cost feasibility (Outcome 1 — confirm ≤$50/month) + candidate P3 disposition (V1-default)

**Locked outcome:** Outcome 1 — V1 fits ≤$50/month under all 15 prior locks; no PRD revision; ADR-002 §6.0 + PRD §7.1 stand. **Cost projection (Architect drill v1.1 after F/CTO clarifications):** fixed-cost section (Plaid per-account-locked + FMP starter + BLS free) $5-$45/mo; already-paid baseline (Hetzner cax21 €9.50/mo per `reference_hetzner_cax21`) $10/mo; feature-dependent (VPS upgrade if needed) $0-$10/mo; **V1 total $15-$65/mo; mid-range ~$35/mo** comfortably under target. Architecture confidence HIGH. **FMP path (a) — keep starter plan** at V1; (b) free-tier + (c) Yahoo/Google scrape captured as V2+ cost-saving levers in BACKLOG. **Candidate P3 disposition (FMP/stock-screening incumbent-exceeds-V1):** V1-default — `pfin_back_etl` ingestion continues unchanged; stock-screening tables accumulate in `pfin_dash`; NO V1 UI surface; V2+ trajectory item in BACKLOG. **PM consult + Sec review SKIPPED** (no scope-cut to vet under Outcome 1; no architectural re-touch; no V1-SHIP-BLOCK security surface introduced). **[Annotation 2026-05-29 — Phase 3 entry gate:** the deferred candidate-P3 PM consult was performed at Phase 3 entry and **confirms the V1-default disposition** ("no V1 UI for FMP/stock-screening; ingestion continues"), closing the skipped-consult gap per the `incumbent-exceeds-V1` guardrail. Disposition unchanged. PM routed two in-band Phase 3 review flags (document the `pfin`↔`pfin_dash` schema boundary in the ingestion architecture; Sec sign-off that the FMP ingestion role cannot reach `pfin` tenant data).**]** **Phase 3 entry-gate tasks:** Plaid production-tier monthly minimum confirmation (sales/onboarding call BEFORE V1 ships); Hetzner cax21 stress-test under full Lock 13 stack; first-quarter actual cost-tracking; V2+ spend-cap / API-quota alerting (PRD §7.1 + App B §7 (a)).

**Cross-references:** locks-log Lock 16; no new Phase 3 task booked (cost-observability operationalized via Phase 3 entry-gate tasks above as Architect Phase 3 implementation work). `reference_hetzner_cax21` + `reference_pfin_back_etl` memories. BACKLOG.md entries: V2+ FMP cost-saving levers (b) + (c); V2+ stock-screening UI surface.

**Consequences.**

- **PRD §1.4 + §7.3 + SECURITY §4.1 axes (i)–(iv) + §4.4 SD matrix + ADR-008 Decision 1 absorb the `tenant_id` → `users_id` rename per Decision 10.** Step 4 close PR sweeps the convention; Phase 3 DDL implementation does the actual column rename.
- **Phase 3 ARCH drafting consumes ADR-011 + the 13 Phase 3 carry-over Tasks** as the V1-mandatory implementation surface. Each task carries its full Sec-mod inventory; Sec re-pings at Phase 3 lock to verify all V1-SHIP-BLOCK mods landed. Phase 3 sequencing: Task #26 (Lock 9 reconciliation; touches schema territory) precedes Task #36 (Lock 15 Lock-9-amendment); Task #32 (Lock 11 monthly_report cron read of owner-id) follows Task #35 (Lock 14 settings table creation).
- **Phase 5 migration design + Phase 6 PR review consume ADR-011 + §SECURITY HTML updates** for V1-mandatory enforcement: every migration touching a SD-NN class implements the storage-protection-class commitment; every PR review against a security-load-bearing surface verifies the §10 defense-in-depth fencing discipline holds (Decision 4); Security Reviewer agent mandatory on every PR touching auth/data/Plaid/secrets per the agent definition.
- **Phase 7 incident handling inherits ADR-008 Decision 4 baseline** (F/CTO-level incident-log primitive at V1; V2 onboarding triggers ramp). No Lock 15 supersession.
- **ADR-008 amendment** for Lock 9 correction #3 partial-reversal: SD-00 row light addendum documents the re-introduced `account_trans.created_at` column per Lock 15 mod #1. Amendment lands at Step 4 close §SECURITY HTML edits PR (PR 2 of 4 in the close-work sequence).
- **§SECURITY HTML edits queued for Step 4 close (PR 2):** SD matrix 14→23 expansion (SD-14 plaid_item_state_history; SD-15 acct_number; SD-16 reconciliation_event HIGH; SD-17 holdings_checkpoint; SD-18 reconciliation_event_trans; SD-12 monthly_report HIGH + child sub-class addendum per Decision 16; SD-23 planning_target per Decision 18; +2 Lock 13 SD entries per Decision 17; SD-04 + SD-11 revisions per Decision 18; SD-00 immutability addendum + Lock 15 created_at addendum per Decisions 14 + 19); RT catalog +10 entries (RT-16 + RT-17 per Decision 13; RT-18 per Decision 14; RT-19 per Decision 15; RT-20 per Decision 16; RT-21 HIGH + RT-22 per Decision 17; RT-23 + RT-24 per Decision 18; RT-25 per Decision 19); RT-13 + RT-09 + RT-10 amendments; §4.2 + §4.3 + §4.6 annotations.
- **PRD HTML edits queued for Step 4 close (PR 3):** §7.3 V1-dormant `account_users` bullet per Decision 6; `users_id` sweep per Decision 10.
- **BACKLOG.md + WORKFLOW.md + MILESTONES.md queued for Step 4 close (PR 4):** BACKLOG entries for V2+ FMP cost-saving levers (b) + (c) + V2+ stock-screening UI surface per Decision 20; V2+ live-tax-API ingestion privileged-context-write surface trajectory per Decision 18; WORKFLOW.md lessons-learned subsection capturing the 8 Sec-load-bearing catches + meta-pattern discovery cycle; MILESTONES.md Phase 1 → complete state + phase-transition prompt invocation per `docs/handoff-prompts.md`.
- **ADR-011 supersedes nothing.** Composes alongside ADR-002 / ADR-003 / ADR-004 / ADR-008 / ADR-009 as the canonical-reference layer for Phase 3 architectural consumption. Per-lock bullet-level rationale lives at `temp/step-4-locks-log.md` (gitignored authoritative state file); ADR-011 captures the decision-grade content at the granularity Phase 3 + Phase 5 + Phase 6 + Phase 7 will consume.
- **Future ADR housekeeping.** When Phase 3 architectural decisions warrant ADR-011 extensions (e.g., per-tenant-key-derivation mechanism for `tenant-scoped-with-app-encryption` classes lands; ARM-tier Postgres tuning under Hetzner cax21 stress-test surfaces a posture refinement), those decisions land at `docs/ARCH/index.html` per ADR-002 §6.0 + §8.0 + Phase 3 territory, not as ADR-011 amendments. When Phase 6 PR-review lessons surface meta-pattern refinements (e.g., a fifth chain-attack family Architect missed but Sec caught), those land as ADR-011 amendments adding to Decisions 1-4 or as new ADR. **ADR-011 canonical-reference layer is intentionally narrow + amendable**; the locks-log meta-patterns plus the 16 per-lock Decisions are the V1-canonical architectural commitments.

**Approved by:** F/CTO (2026-05-26, across the active drilling cycle 2026-05-25 → 2026-05-26 via 16 lock ratifications + 3 mod-set amendments at Locks 14 / 15 / cost-feasibility reframe + candidate P3 disposition).

---

## ADR-010 — Adopt comments-sidecar feature from project_template

**Date:** 2026-05-24
**Status:** Accepted
**Phase:** 1 (Step 4 prep; adopted via [ADR-009](#adr-009) selective-adoption framework)

**Context.** `richmosko/project_template` shipped a per-section HTML doc review feature across four PRs (#8 / #9 / #10 / #11 on the upstream repo, 2026-05-23): an on-disk `docs/<DOC>/comments.md` sidecar with `## §<section-id>` anchors mapping to `<section id="...">` in the HTML doc, a `/refine-doc` skill that walks the sidecar and applies each comment to the matching section (removing addressed comments as it goes), a local Python stdlib HTTP server (`scripts/serve-docs.py`) with a JSON comments API, an in-browser JS widget that lets reviewers add comments inline while reading the doc, and a `/serve-docs` skill that backgrounds the server under the Claude session. The feature is designed for single-user solo review (no author attribution, no threading) and gitignores the sidecar so PR history stays clean. Implementation summary lives at `~/Projects/project_template/temp/comments-implementation.md`.

mosko-fintech is at Phase 1 Step 4 (Architect ratification of PRD content; Phase 3 entry gate) with PRD content migrated to `docs/PRD/index.html` (PR #45) and `docs/SECURITY/index.html` carrying the V1 security canonical reference. Step 4 review is the immediate near-term use case for per-section commenting; Phase 3 ARCH drafting and ongoing SECURITY refinement are downstream use cases.

**Decision.** Adopt the comments-sidecar feature wholesale via two PRs:

1. **Pass 1** (this PR) — convention + `/refine-doc` skill (hand-edit authoring path). Establishes the `comments.md` format, the gitignore entry, the `/refine-doc` skill, and the WORKFLOW.md `Doc review loop` section. Validates the convention via hand-editing before investing in the UX layer.
2. **Pass 2** (next PR) — Python local server (`scripts/serve-docs.py` + `serve-docs.sh`) + JS widget (`docs/_assets/comments.{js,css}`) + `/serve-docs` skill + HTML asset wiring in `docs/PRD/index.html` and `docs/SECURITY/index.html`. Adds the in-browser inline-authoring UX; both passes write to the same on-disk format.

**Why.** Selective-adoption candidate per [ADR-009](#adr-009) Decision 8 (template-as-seed-not-constraint policy): solved problem upstream, modest footprint (~8 new files + 6 edits across 2 PRs), aligns cleanly with mosko's existing `docs/<DOC>/index.html` artifact set and `/start-doc-update` + `/finish-doc-update` skills (PR #42). Strategic timing favors landing before Step 4 review so Architect comments flow through the widget rather than scattering across chat context. Single-user assumption from the upstream design holds for mosko's solo-Founder shape.

**Alternatives considered.**

- **Bundle into one PR.** Rejected — the pass-1 / pass-2 split mirrors upstream's incremental landing pattern and provides a validation checkpoint between the markdown-convention layer and the JS/Python UX layer. Two atomic PRs each independently revertible.
- **Hand-edit-only port (skip Pass 2).** Rejected — per upstream implementation notes, the inline widget is the feature's main UX value-add ("the amazing UX layer") and pays off immediately for solo review. Hand-edit-only would land a working but lower-UX version and likely require the same Pass 2 work later anyway.
- **Defer to Phase 3 (after `docs/ARCH/index.html` is drafted so all three docs get the feature day-one).** Rejected — PRD review at Step 4 is the more pressing use case; ARCH will get the feature automatically once Phase 3 drafts its content. Deferring would forfeit the Step 4 review benefit without a corresponding gain.
- **Merge `comments.css` into the existing `docs/_assets/style.css`.** Rejected — keeping `comments.css` separate matches the upstream `doc.css` + `comments.css` split, produces a cleaner diff (no churn to `style.css` which was lock-edited in PR #38), and makes the feature's CSS surface inspectable in isolation. Two extra `<link>` lines per HTML doc is a trivial cost.

**Adaptations from upstream.**

- **Section-ID examples** in `refine-doc/SKILL.md` use mosko's `sec-N` + `appendix-X` scheme rather than template's semantic IDs (`goals`, `non-goals`). Functional behavior unchanged — section IDs are read from the DOM at runtime and the server-side regex `^[a-z][a-z0-9-]*$` accepts both schemes.
- **`/merge-pr` references dropped** in the suggested PR flow. mosko has no `/merge-pr` skill; merges go through the GitHub UI or `gh pr merge --squash <pr#>`.
- **WORKFLOW.md `Doc review loop` section** rewritten to reference mosko-specific section IDs, phases (Step 4 / Phase 3), and the absence of `/merge-pr`. Pass status note added to make the two-PR landing visible to future readers.

**Approved by:** F/CTO (2026-05-24, via PR plan ratification before PR 1 execution).

**Cross-references:** [ADR-009](#adr-009) Decision 8 (selective-adoption framework). Upstream implementation notes: `~/Projects/project_template/temp/comments-implementation.md` (not in this repo). Template-feedback log location: `temp/project_template_feedback.md` (for any deviations worth contributing back upstream — note that mosko's `<section id>` scheme is one such candidate, since the template's semantic-IDs convention is less mechanically robust than mosko's numeric scheme for handling section renames).

---

## ADR-009 — Selective adoption of richmosko/project_template patterns

**Date:** 2026-05-23
**Status:** Accepted
**Phase:** 1 (Step 4 prep; lands the selective-adoption convention before Phase 3 entry; structural choices for the entire R/P/I+V outer frame going forward)

**Context.** mosko-fintech was bootstrapped through Phases 0 and 0.5 with project-internal conventions: an 8-numbered-phase workflow model, multi-Decision ADR consolidation pattern, monolithic markdown source-of-truth files (`PRD.md`, `WORKFLOW.md`, `DECISIONS.md`), `chief-of-staff` as a spawnable orchestrator subagent, an explicit Visual Designer role separate from UX, and a `/ship-branch` skill encoding mosko-specific PR conventions. By the close of Phase 1 Step 3.5 (v1.30; PR 11), the project had accumulated 14 weeks of locked work across 30+ PRs: a full PRD spanning §1–§8 with three Appendices (114-entry forward-pointer index + 32-entry story trace index), eight accepted ADRs (ADR-002 through ADR-008), and a 298 KB WORKFLOW.md that exceeded Read's 256 KB byte limit (segment-reads only).

F/CTO surfaced `richmosko/project_template` (a reusable Claude Code starter template authored by the same person, distinct from but referenced during mosko-fintech's bootstrap) as a candidate framework for adoption. The template ships an R/P/I/V four-phase model, a nine-specialist roster, an HTML doc-generation pipeline (`/generate-prd` / `/generate-archdoc` / `/generate-secdoc`), a feature-flow scheme (PRD → BACKLOG → Linear → MILESTONES), a `/start-doc-update` + `/finish-doc-update` doc-update flow, and a SessionStart hook that auto-loads only a compact MILESTONES.md head section.

The brainstorm question: does mosko-fintech adopt the template's conventions wholesale, partially, or not at all? Wholesale adoption would invalidate the 14 weeks of locked Phase 1 work (PRD section schema, ADR pattern, agent roster, branch conventions all differ). No adoption would forgo the template's genuine improvements (compact-ledger auto-load model, feature-flow scheme, doc-update skill flow, HTML doc shape with Mermaid). The middle path — **selective adoption with explicit deviations preserved as load-bearing** — emerged early and became the framing throughout. F/CTO formalized the philosophy as `feedback_seed_not_constraint`: "project templates are seed material, not constraints; default to selective adoption + project-specific additions; capture meaningful deviations as feedback to the template repo."

The brainstorm executed across three sessions (2026-05-21 / 2026-05-22 / 2026-05-23) and produced 17 locked structural decisions/sub-decisions. Mid-brainstorm, F/CTO surfaced a layered-persistence question — "are all these decisions getting logged somewhere?" — that produced a working brainstorm log at `temp/template-adoption-brainstorm.md` (gitignored; per `feedback_working_artifacts_temp_not_docs`) and a new memory `feedback_brainstorm_logging` codifying the convention. Six template-feedback entries also accumulated in `temp/project_template_feedback.md` for eventual upstream contribution to `richmosko/project_template`.

This ADR consolidates the 17 brainstorm entries into 9 named Decisions that become canonical references for Phase 3+ work. The bullet-level conventions (CSS class taxonomy, branch-prefix mapping, filename pattern, etc.) elaborated below remain mutable through future revisions if the canonical references hold steady. New convention categories require ADR-009 amendment. This ADR supersedes nothing; it lands the selective-adoption convention as a parallel consolidation alongside ADR-002 / ADR-003 / ADR-004 / ADR-008.

**Decisions.**

### Decision 1 — Agent roster lock

The mosko-fintech agent roster is **main session (acting as team-lead) + 9 specialist subagents**:

| Role | Source | Notes |
|---|---|---|
| **team-lead** | Main session itself (not spawnable) | Absorbs orchestration responsibilities formerly held by spawnable `chief-of-staff` |
| `product-manager` | Both mosko + template | Name aligned |
| `architect` | Both | Name aligned |
| `seceng` | Renamed from mosko's `security-reviewer` | Template-aligned name |
| `ux-designer` | Both | Name aligned; scope is flows + IA only |
| `visual-designer` | **mosko-specific addition** | Owns design tokens, typography, color, spacing; runs palette/typography F/CTO checkpoint; flags missing components back to UX |
| `frontend-lead` | Template (new to mosko) | Phase 5+ |
| `backend-lead` | Template (new to mosko) | Phase 5+ |
| `qa-engineer` | Template (new to mosko) | Phase 5+ |
| `devops-engineer` | Template (new to mosko) | Phase 5+ |

**Dropped from prior roster:**

- **Spawnable `chief-of-staff` subagent.** With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, the main session is addressable like any teammate, so the parallel-orchestration argument for a separate CoS subagent doesn't hold. Removes a confusing duplication where the main session was already operating as CoS and could also spawn one.

**Skipped from template's roster:**

- **`implementation-lead`** (template's CLI / library / ML / data-pipeline generalist). Not applicable to mosko-fintech's full-stack web app shape.

**Visual Designer kept as mosko-specific because** the role encodes load-bearing discipline: a mandatory palette-and-typography checkpoint with the F/CTO before design-system lock, and a "flags missing components back to UX rather than designing around them" boundary that breaks the moment one head holds both roles. The template's single `ux-designer` doesn't encode this discipline. The deviation is logged to the template-feedback log (`temp/project_template_feedback.md` entry: "Visual Designer as a project-specific extension for trust-driven domains") for potential upstream contribution once Phase 2 actually exercises the role.

### Decision 2 — Phase model under R/P/I+V outer frame

Mosko-fintech keeps its 10 numbered phases (0, 0.5, 1, 2, 3, 4, 4.5, 5, 6, 7) and **groups them under template's R/P/I+V outer categories** as a non-destructive labeling addition:

| Outer category (template) | Mosko phases | Notes |
|---|---|---|
| _(Meta-bootstrap)_ | 0, 0.5 | No template equivalent; pre-Research |
| **Research** | 1, 2 | PRD + UX/Visual |
| **Plan** | 3, 4, 5 | Technical Architecture + Project Scoping + Workshop Setup |
| **Implement+Validate** | 4.5, 6, 7 | Agentic Flow Ramp + Build Loop + Deploy & Iterate |

**Linear hierarchy correction:** template's actual hierarchy is **Project → Milestone → Feature** (three scales of the same I↔V loop mechanic). **Sprint is an orthogonal pacing wrapper, not a hierarchy level** — sprint boundaries are bookkeeping events, not I↔V gates.

**Mosko's V1.0 / V1.1 / V1.final / V2 sub-version structure** (PRD §8 / ADR-004) maps to template milestones (Linear Projects). Materialization deferred to Phase 4 (Project Scoping) per ADR-004's "specific sub-version sequencing remains Phase 4 work" and per Decision 7's M1 issue "(c) Populate product milestones."

**Rationale.** Non-destructive: all existing Phase 1 work, ADRs, memory references stay intact. Mosko's finer-grained phases preserve setup-side discipline (PRD vs UX vs ARCH are different activities with different agents); template's R/P/I+V is a clean outer frame for cross-project comparison. Phase 4.5 sits under I+V as "the first I+V loop is a learning loop with throwaway feature as deliverable"; Phase 7 sits under I+V as "ongoing I+V at project scale — V1 done, plan V2."

### Decision 3 — Document format scheme

**HTML format** for product / architecture / security artifacts (diagram-dense, structured-data):

- `docs/PRD/index.html` — converted from `PRD.md` (single-file initial; Layout 1 per-§ split deferred)
- `docs/ARCH/index.html` — new (Phase 3 surface; scaffolded in PR A from template's ARCH.html seed)
- `docs/SECURITY/index.html` — new (receives migrated PRD §4 content per Decision 4)

**Markdown format** for state-ledger and process artifacts (text-shaped, append-only, edit-heavy):

- `MILESTONES.md` — new compact state ledger (auto-loaded per Decision 6)
- `WORKFLOW.md` — conventions (existing; consult-on-demand)
- `DECISIONS.md` — ADRs (existing; consult-on-demand)
- `CHANGELOG.md` — new per-version execution history (consult-on-demand; populated by task #10 extraction)
- `BACKLOG.md` — new (receives migrated PRD §5 content per Decision 4; also serves as Linear overflow queue)
- `docs/MILESTONE-FRAMING.md` — new (receives migrated PRD §8 content per Decision 4)
- `CLAUDE.md` — existing conventions

**Subdirectory shape for HTML docs.** Each top-level HTML doc lives in `docs/<DOC>/` with `index.html` as entry point. Multi-file split (Layout 1 — per-§ files like `01-overview.html`, `02-user-stories.html`, etc.) is the **eventual** target if `index.html` becomes unwieldy; **single-file initial conversion** for now. The subdirectory shape future-proofs growth without preemptive multi-file complexity.

**Rationale.** HTML wins for the artifacts that carry diagrams and structured data (PRD with matrices + 114-entry App B; ARCH with system diagrams; SECURITY with threat models). Markdown wins for artifacts that are text-shaped and edit-heavy (state ledgers, ADRs, changelog). HTML conversion scope is PRD-only for the immediate work; ARCH/SECURITY land via PR A scaffolding + Phase 3 drafting; future state-ledger conversions decided independently per `feedback_orthogonal_decisions`.

### Decision 4 — PRD section schema with relocations

**Mosko's §1–§8 PRD section schema is preserved verbatim.** No new sections are added during the conversion (no dedicated Acceptance Criteria section, no Risks / Open Questions section — both deferred for future consideration if/when they earn their place).

**Three §-relocations** during the conversion (PRD §-stubs become thin pointers to the relocated content):

| Mosko § | Content | Destination |
|---|---|---|
| **§4 Security and compliance posture** | 14-entry SD matrix + 15-entry RT catalog + 6 posture sub-§ | `docs/SECURITY/index.html` |
| **§5 V2 deferred candidates** | ~18 V2 candidates from ADR-002 §2.0 + later additions | `BACKLOG.md` |
| **§8 V1 milestone framing** | V1 sub-version convention + drop-replace migration + Phase 4 handoff | `docs/MILESTONE-FRAMING.md` |

**Sections that stay in PRD verbatim:** §1 Overview, §2 V1 user stories (§2.1–§2.6 archetypes), §3 Success metrics, §6 Out-of-scope, §7 Constraints (§7.1–§7.3), Appendix A (deferred), Appendix B (114 forward-pointers), Appendix C (32 story traces).

**Rationale.** The §1–§8 schema reflects 30+ PRs of deliberate editorial work (Step 3 + Step 3.5); restructuring would re-displace exactly the work the conversion is preserving. The three relocations target sections that will grow over time (Security artifacts as V2 expands; milestone framing touched at every release cycle; V2 candidates accumulate) — separating them into dedicated artifacts is forward-planning at low cost. §5 → BACKLOG.md is template-faithful: forward-looking scope waiting for promotion to Linear is exactly what BACKLOG.md is for in template's feature-flow scheme (Decision 7).

### Decision 5 — HTML doc conventions

Conventions for HTML docs (PRD, ARCH, SECURITY):

**Asset structure** (`docs/_assets/`):

- `style.css` — shared CSS across all HTML docs
- `mermaid.min.js` — **vendored Mermaid runtime, NOT CDN-loaded.** Matches mosko-fintech's fintech security posture (no third-party fetch at view time). Offline-works.

**Filename convention:**

- Number prefix: two-digit zero-padded (`01-`, `02-`, … `08-`)
- Slug: kebab-case, semantic, slugified from §-title
- Appendices: explicit `appendix-a.html`, `appendix-b.html`, `appendix-c.html`
- Index: `index.html` reserved for landing page / TOC (entry point)
- Cross-doc pattern extends: `docs/ARCH/index.html`, `docs/SECURITY/index.html`

**Cross-reference shape:**

- **§-heading anchor IDs:** explicit short IDs from §-numbering (`id="sec-4-5"`, `id="sec-2-4-5"`).
- **Data-entry anchor IDs:** explicit short IDs from existing nomenclature (`id="sd-12"`, `id="rt-13"`, `id="adr-008"`, `id="app-b-rt-13"`).
- **Incidental content anchor IDs:** slugify-derived from heading text.
- **Path style:** relative + anchor. Within-file: `#anchor`. Cross-file within `docs/PRD/`: `02-user-stories.html#sec-2-4-5`. Cross-doc HTML→HTML: `../ARCH/index.html#sec-3-2`. Cross-doc HTML→MD: `../../DECISIONS.md#adr-008` (GitHub-renderable).
- **No `<base href>`.** Anchor IDs are file-agnostic — same `sec-4-5` works whether in `index.html` or `04-security.html` after a multi-file split.
- **Forward-pointer pattern:** §-cell side inline `<a class="forward-pointer" href="#app-b-rt-13">[App B-RT-13]</a>`; App B entry side `<li id="app-b-rt-13" class="active architect-phase-3">…</li>`. Bidirectional navigability.
- **Voting markers / lock markers:** semantic spans — `<span class="vote alpha">Q-S4 α</span>`, `<span class="lock-marker">§4.5 locked 2026-05-18</span>`. CSS color-coding optional polish.

**Structured-data representation:**

- **HTML `<table>`** for fixed-column data: §4.4 sensitive-data matrix (14 rows × 8 cols), §4.5 RLS test catalog (15 rows × 7 cols).
- **Semantic `<ul>` with `<li id="...">`** for variable-content indexed entries: Appendix B (114 entries), Appendix C (32 entries).
- **CSS class taxonomy** (locked vocabulary):
  - **Status:** `.active`, `.resolved`
  - **Classification (5-tag from PR 10):** `.architect-phase-3`, `.sec-v2-implementation`, `.architect-sec-joint`, `.boundary-note`, `.closure-trace`
  - **Tier (§4.4):** `.tier-credential`, `.tier-high`, `.tier-medium`
  - **Severity (§4.5):** `.severity-critical`, `.severity-high`, `.severity-medium`

**Build approach:** no build step initially (option i — accept duplication of headers/footers across files). Promote to templating (build pipeline) only if multi-file adoption expands beyond a single split.

### Decision 6 — Compact-ledger auto-load architecture

**Adopt template's compact-ledger auto-load pattern.** Session-start auto-load reduces to a compact state ledger only; all heavy artifacts become consult-on-demand.

**New auto-load set** (3 files; ~150 lines total):

| File | Mechanism | Purpose |
|---|---|---|
| `CLAUDE.md` (root) | Claude Code built-in | Project conventions, reading order |
| `~/.claude/.../memory/MEMORY.md` | Claude Code built-in | Memory index |
| `MILESTONES.md` (new) | SessionStart hook (read top section above `## Roadmap` cutoff per template's awk pattern) | Compact state ledger: current phase, active feature, milestone summary |

**Removed from auto-load** (all become consult-on-demand):

- `WORKFLOW.md` — was forced-read by re-orient protocol
- `DECISIONS.md` — same
- `PRD.md` / `docs/PRD/index.html` — same
- `ARCHITECTURE.*` — same (when it exists)
- `docs/handoff-prompts.md` — heavily simplified or retired; per-session orient protocol drops; Phase-transition prompts (explicitly invoked) preserved

**Rationale.** Three of six auto-read files exceeded Read's limits at brainstorm time (`WORKFLOW.md` 305 KB byte-limit; `DECISIONS.md` 37K-token-limit; `PRD.md` exceeded both). The previous "always know everything important" auto-load was already silently degraded — segment-reads only. Template's pattern (load slim "where are we" snapshot; consult depth only when work requires it) is the correct shape at the current artifact scale.

**SessionStart hook modification:** modify `.claude/settings.json` to read MILESTONES.md head via template's awk-then-stop pattern (`awk '/^## Roadmap/{exit} {print}' MILESTONES.md`); drop the heavy re-orient protocol that forced reads of WORKFLOW + DECISIONS + PRD + ARCH.

### Decision 7 — Template feature-flow scheme + initial milestones

**Adopt template's feature-flow scheme now** (not deferred to Phase 5 entry):

```
[PRD §2 User Stories]       ← intent (32 stories per Appendix C; never deleted)
        ↓ (Plan phase: stories sized + milestone-tagged)
[BACKLOG.md]                ← overflow queue, ordered by milestone, FIFO promotion
        ↓ (sprint boundaries, /sync-backlog promotes batch)
[Linear (≤200 hot)]         ← active set under work
        ↓ (features finish)
[Linear: Done]              ← /merge-pr marks status; /cleanup-linear archives
        ↓ (mirrored locally)
[MILESTONES.md → Completed] ← snapshot of done features
```

**Initial milestones** (defined in MILESTONES.md):

| Milestone | Status | Gate | Initial issues |
|---|---|---|---|
| **M0 — Research** | Active (virtually done) | PRD locked at end of mosko Phase 1 (after Step 4 ratifies) | Step 3 + Step 3.5 PRs retro-tagged as M0 issues |
| **M1 — Plan** | Pending | ARCH + SECURITY docs locked at end of mosko Phase 3 | (a) Draft ARCHITECTURE; (b) Draft SECURITY (largely landed via ADR-008); (c) Populate product milestones in MILESTONES.md — notes point to `docs/MILESTONE-FRAMING.md`; (d) further granularity TBD |

**Product milestones (V1.0 / V1.1 / V1.final / V2-X) get defined LATER** as the output of M1's issue (c) — the "populate product milestones" work that converts MILESTONE-FRAMING.md's conceptual framing into actual Linear Projects.

**Skill suite phasing:**

- **Adopt now:** `/setup-linear-team` (adapted — must seed M0/M1 meta-process milestones first, NOT PRD §2 stories), `/sync-backlog`, `/cleanup-linear`, `/open-doc`, BACKLOG.md, MILESTONES.md.
- **Adopt at Phase 3 entry:** `/generate-archdoc` (adapted for mosko's existing 87 App B forward-pointers + ADR-008 axes), `/generate-secdoc` (adapted).
- **Adopt at Phase 6 entry:** `/start-feature`, `/finish-feature`, `/merge-pr`.
- **Skip:** `/generate-prd` (PRD already drafted; import mode N/A given conversion path).

**Rationale.** M0 is virtually done — defining it now makes Phase 1 closure cleaner and provides a retro-anchor for Step 3 / 3.5 work. M1 is the natural framing for Phase 3 (ARCH/SEC); the "populate product milestones" issue under M1 makes the deferred Phase 4 (Project Scoping) work explicit and tracked. Adopting feature-flow scheme now (not Phase 5) means Linear + BACKLOG.md infrastructure becomes load-bearing for M1 sub-issue tracking, not just future implementation work.

### Decision 8 — ADR format hybrid policy

**Two ADR patterns are supported in DECISIONS.md going forward:**

- **Consolidation pattern** (mosko's existing — ADR-002 / ADR-008 style): Context → Decisions (numbered multi-Decision structure) → Consequences. Use for: synthesis work, canonical-reference layers, multi-Decision territory establishment.
- **Terse pattern** (template's): `Decision / Why / Alternatives considered / Approved by / Supersedes`. Use for: one-off decisions, simple supersessions, isolated choices.

**Examples:**

- **This ADR (ADR-009):** consolidation pattern. Nine distinct Decisions across roster / phase model / format / schema / conventions / architecture / process — the natural fit for synthesis.
- **ADR-002 / ADR-008:** consolidation pattern (canonical-reference layers).
- **Hypothetical future "use Tailwind for styling":** terse pattern (one-off styling choice).

**Policy location.** `DECISIONS.md` preamble. The hybrid policy is documented in a Format section explaining both patterns and when each applies. The preamble lands as part of this ADR's commit.

**Rationale.** Honors mosko's existing convention (consolidation has proven valuable for canonical-reference work at ADR-002 / 008); allows lean ADRs when work doesn't warrant ceremony. Per `feedback_seed_not_constraint`: template provides the terse pattern as a baseline; mosko preserves the consolidation pattern where it adds value.

### Decision 9 — Doc-update skill flow

**Replace mosko's `/ship-branch`** with template's two-step `/start-doc-update` + `/finish-doc-update` (adapted for mosko).

**`/start-doc-update` adaptation** — phase-prefix map (sub-option 3 hybrid; outer-category names):

| Doc edited | Branch prefix |
|---|---|
| `docs/PRD/*` | `phase/research-<slug>` |
| `docs/ARCH/*`, `docs/SECURITY/*` | `phase/plan-<slug>` |
| Future implementation code | `phase/iv-<slug>` |
| `MILESTONES.md`, `DECISIONS.md`, `BACKLOG.md`, `CHANGELOG.md`, `docs/MILESTONE-FRAMING.md`, `WORKFLOW.md`, `CLAUDE.md`, `.claude/agents/*`, `.claude/skills/*` | `meta/<slug>` |

State-ledger files **lumped under `meta/`** (not split into separate `state/` per template's pattern) — single prefix simpler; doc edited is in the slug.

**`/finish-doc-update` adaptation:**

1. **SSH→HTTPS fallback** ported from retired `/ship-branch` per `feedback_ssh_push_fallback`: per-use-authorization HTTPS temp-switch when SSH push fails; restore origin to SSH after.
2. **Commit format** `docs(<outer>): <subject>` matching the prefix — e.g., `docs(research): add §3.4 metric`, `docs(plan): refine RLS catalog`, `docs(meta): update CLAUDE.md reading order`.
3. **PR body shape** — ported mosko's elaborate shape (Summary / Motivation / Files changed / Test plan / Follow-ups) **replacing template's lean shape.** F/CTO consistently found the richer shape useful for PR review; going lean would be a regression.

**`/ship-branch` retirement:**

- Delete `.claude/skills/ship-branch/`.
- `feedback_ssh_push_fallback.md` memory updated to reference `/finish-doc-update` as the primary path.
- Old branches using legacy `phase/<N>-<descriptor>` or `workflow/<descriptor>` convention stay legacy (no rename); new branches use the adapted convention.

**Rationale.** Template's two-step flow covers branch creation (which mosko did manually) — phase-prefix auto-detection is genuine value-add. Adopting both halves of template's flow lets mosko stop maintaining two competing push+PR paths. Mosko-specific load-bearing pieces (SSH fallback, elaborate PR body) port cleanly into the adapted `/finish-doc-update`.

**Consequences.**

- **ADR-009 supersedes nothing; extends existing convention by selective adoption.** ADR-002 / ADR-003 / ADR-004 / ADR-005 / ADR-006 / ADR-007 / ADR-008 all stand. ADR-009 is parallel to ADR-002 / ADR-003 in shape (consolidation pattern across multiple subjects); parallel to ADR-008 in role (canonical-reference layer for the cross-template-adoption decisions).

- **Phase 3 entry consumption** (Step 4 ratifies → Phase 3 opens). Architect drafts `docs/ARCH/index.html` using template's 9-section ARCH.html seed (adapted with mosko-specific additions: multi-tenant architecture surface per ADR-008 axes i/ii/iii; RLS implementation consuming §4.5 RT catalog; sensitive-data storage architecture consuming §4.4 SD matrix; snapshot regeneration architecture per ADR-008 axis vi; Plaid integration architecture). Architect consumes the 87 active App B forward-pointers + §4.4 + §4.5 + §8 → Phase 4 handoff anchor. Cross-refs use Decision 5's conventions.

- **Phase 4 (Project Scoping) materializes product milestones.** V1.0 / V1.1 / V1.final / V2-X get defined from PRD §8 / `docs/MILESTONE-FRAMING.md` / ADR-004 and become Linear Projects per Decision 7's feature-flow scheme. M1's issue (c) is the trigger.

- **Phase 5+ build work** uses adapted `/start-feature` + `/finish-feature` + `/merge-pr` (Phase 6 entry per Decision 7's skill phasing). `/start-doc-update` + `/finish-doc-update` already active for all doc work per Decision 9.

- **Phase 7 incident handling** per ADR-008 Decision 4 (F/CTO-level incident-log primitive at V1; ramp to formal incident-response shape at V2-trajectory) — unchanged by this ADR.

- **Pending execution tasks** (post-ADR-009 work; tracked at task IDs):
  - **#7** Compact MILESTONES.md ledger (load-bearing for Decision 6; blocks #11 + #15).
  - **#10** Extract changelog from WORKFLOW.md to CHANGELOG.md (orthogonal per `feedback_orthogonal_decisions`; independent timing).
  - **#11** Implement compact-ledger auto-load model (Decision 6 mechanics; blocked by #7).
  - **#12** Migrate PRD §4 → `docs/SECURITY/index.html` (Decision 4; part of PR B).
  - **#13** Migrate PRD §5 → `BACKLOG.md` (Decision 4; part of PR B).
  - **#14** Migrate PRD §8 → `docs/MILESTONE-FRAMING.md` (Decision 4; part of PR B).
  - **#15** Populate MILESTONES.md with M0 + M1 + retro-tag issues (Decision 7; blocked by #7; part of PR C).
  - **#16** Adopt template feature-flow scheme (Decision 7).
  - **#17** Adapt doc-update skills + retire `/ship-branch` (Decision 9; lands on its own `meta/` branch).

- **PR sequence for PRD conversion** (locked per Decision 4's migration staging — Shape B): **PR A** (scaffolding — `docs/PRD/`, `docs/SECURITY/`, `docs/ARCH/`, `docs/_assets/`, skeleton files, conventions locked visibly) → **PR B** (content migration — PRD §1/§2/§3/§6/§7/appendices to HTML; §4/§5/§8 migrations; cross-ref retargeting; archive `PRD.md`) → **PR C** (architectural shift mechanics — populate MILESTONES.md; modify SessionStart hook; simplify/retire `handoff-prompts.md`; update CLAUDE.md). Driver: main session (team-lead) — pure mechanical work, no scope decisions left.

- **Memory updates landed during this brainstorm** (durable behavioral feedback for future sessions):
  - **Updated:** `feedback_subagent_relay_format.md` ([CoS]: → [team-lead]:; roster label refresh); `feedback_ssh_push_fallback.md` (`/ship-branch` → `/finish-doc-update`); `user_role.md` (CoS removed; reading order refreshed); `feedback_main_anchored_orient.md` (auto-read file list refreshed); `feedback_working_artifacts_temp_not_docs.md` (brainstorm-log + template-feedback-log added as examples).
  - **Added:** `feedback_seed_not_constraint.md` (templates are seed not constraint); `feedback_orthogonal_decisions.md` (don't fold orthogonal decisions back into parent framing); `feedback_brainstorm_logging.md` (substantive brainstorms log to temp/ before ADR synthesis).
  - **MEMORY.md index** updated with three new entries.

- **Template-feedback log entries** surfaced for upstream contribution to `richmosko/project_template` (in `temp/project_template_feedback.md`):
  - Visual Designer as a project-specific extension for trust-driven domains.
  - HTML preview methodology should be a per-project decision.
  - Mermaid loading strategy (CDN vs. vendored) should be a template option.
  - Subdirectory structure for HTML docs (`docs/PRD/`, `docs/ARCH/`, `docs/SECURITY/`).
  - Seed default M0 (Research) + M1 (Plan) milestones in template's MILESTONES.md.
  - Distinguish CHANGELOG.md (execution log) from DECISIONS.md (architectural log).

- **ADR-009 canonical-reference immutability boundary.** The nine Decisions are immutable as canonical references for downstream work. Bullet-level conventions inside Decisions (CSS class taxonomy, filename patterns, branch-prefix mappings, etc.) remain mutable through future PRD / ARCH / SECURITY / WORKFLOW revisions if the canonical references hold steady. **New canonical references** (new branch-prefix categories, new file-format categories, new roster roles, new phase categories, new ADR pattern variants) **require ADR-009 amendment.**

- **WORKFLOW.md changelog entry** lands at integration-pass time documenting ADR-009 acceptance + execution-task creation + memory updates + brainstorm log archival path. The changelog entry itself moves to `CHANGELOG.md` upon task #10 execution per Decision 3.

- **Future ADR housekeeping.** When Phase 3 architectural decisions land (V1 stack choices; per-tenant key derivation for `tenant-scoped-with-app-encryption` classes; webhook signature verification mechanism; etc.), those land at ARCHITECTURE.md per ADR-002 §6.0 + ADR-008's Phase-3-territory framing, NOT as ADR-009 amendments. When V2-scoping work surfaces additional template-adoption patterns (additional skills; additional roster roles), new ADRs amend ADR-009. The selective-adoption convention itself (template-as-seed-not-constraint per `feedback_seed_not_constraint`) is intentionally narrow and amendable; the substantive content evolves at the consuming-artifact level.

---

## ADR-008 — Phase 1 Step 3 §4 lock: V1 security posture canonical reference

**Date:** 2026-05-18
**Status:** Accepted
**Phase:** 1 (Step 3; lands the canonical Sec reference layer for PRD §4 Security and compliance posture; closes ADR-002 §7.0 missing-content gaps #4 + #6 + partial close of #5)

**Context.** PRD §4 (Security and compliance posture) was the largest single task in Phase 1 Step 3, drafted with Security Reviewer as primary author for the first time (prior Sec engagements were six at-lock pass-with-comments verdicts on PM-authored §2 sections — §2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6). §4 consolidates material accumulated across §2.4 → §2.6 lock entries: seven Phase 3 RLS test candidates surfaced at §2.6 lock plus seven additional V1-mandatory test surfaces surfaced at gate-B catalog-completion scan (§2.4 + §2.5 + §3 elevations); a thirteen-class sensitive-data inventory plus the explicit baseline class (SD-00) and the cross-cutting derivative-persistence annotation (SD-13); six canonical Sec axes elevated through the six §2.x at-lock passes; three §7-side forward-pointers per §7 routing flag (e); two §3-side Sec routing flags per §3 (d) + (e); accumulated V2-ship-gate Sec-consult flags from §5.4 + §5.6 + §7.1; and the three Q3 self-flags Sec surfaced at gate 1 as required for §4 lock (data retention, availability/uptime, incident handling — closes ADR-002 §7.0 gaps #4 + #5-partial + #6).

The §4 drafting executed under the four-stage two-stage-hybrid drafting pattern ratified at Q4 D-A per the §4 structure proposal gate (pattern divergence (ii)): gate-1 structure proposal; gate-A §4.4 sensitive-data matrix column-shape ratification (Q-Col1 / Q-Class-ID / Q-Tier / Q-Storage / Q-Retention-N); gate-B §4.5 RLS test catalog column-shape + severity-rubric ratification (Q-Catalog-Count / Q-RT-Ord / Q-RT-Col1 / Q-RT-Cat / Q-Sev / Q-Special-Cases); stage-2 row drafting for both consolidation tables; stage-3 posture bulk-closeout for §4.1 + §4.2 + §4.3 + §4.6; stage-4 ADR-008 confirm-or-revise + integration-pass prep. F/CTO ratified 21-for-21 Sec-lean across all gates with zero overrides.

The locked §4 content lands material that will be cited at Phase 3 architecture decisions, Phase 5 migration design, Phase 6 PR review (Security Reviewer mandatory on every PR touching auth / data handling / external APIs / secrets / financial calculations per the Security Reviewer agent definition), and Phase 7 incident handling. ADR-grade canonicality matters for that consumption surface in a way it didn't for §6 (which forward-pointed to ADR-002 §3.0 verbatim) or §7 (which forward-pointed to ADR-002 §6.0 + §1.4 + §5.7). This ADR documents the canonical-reference layer §4 establishes; the bullet-level posture commitments live at PRD §4.1 / §4.2 / §4.3 / §4.6 and remain mutable through future PRD revisions if the canonical references hold steady.

**Decisions.**

### Decision 1 — Six canonical Sec axes as the V1-authoritative set

The V1 security posture is anchored on six canonical Sec axes elevated through the six §2.x at-lock passes (§2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6) and consolidated at §4.1 + §4.3:

- **Axis i — `tenant_id` is the V1 isolation boundary.** Every user-data table carries a `tenant_id` column; every read against a user-data table is RLS-enforced at the database policy layer; multi-tenant infrastructure exercised on the single-user-V1 test path per ADR-002 §1.4. **PRD home: §4.1 bullet 1.**
- **Axis ii — Multi-scope ownership is a tenant-scoped data attribute, NOT an isolation boundary.** The ownership-scope label per ADR-004 Decision B is a `scope` column on user-data rows; scope filtering happens at the application query layer above the RLS boundary. Sixth-consecutive-instance canonical formulation across §2.1.7 → §2.6.6. **PRD home: §4.1 bullet 2.**
- **Axis iii — `tax_treatment` is an inclusion-filter attribute, NOT an isolation boundary.** Same shape as axis ii but for the §2.5 tax-domain attribute per ADR-002 §1.6. Tri-axis query parameterization (`tenant_id × scope × tax_treatment × date`) is the canonical V1 query-shape envelope. **PRD home: §4.1 bullet 3.**
- **Axis iv — Write-path RLS symmetry: write paths inherit the tenant-scoping the read paths enforce.** No V1 write path bypasses the tenant-scoping the read path enforces; manual-entry write paths carry elevated integrity risk distinct from but downstream of the write-path-RLS commitment. **PRD home: §4.1 bullet 4.**
- **Axis v — Staleness-live-read cross-tenant signal leak as new verification surface.** The §2.6.5 live-join-at-render-time pattern (join from snapshot's `account_id` to live §2.4.4 credential-error state) must resolve under requesting-tenant identity, never cross-tenant. **PRD home: §4.3 bullet 1.**
- **Axis vi — Snapshot store as derivative-persistence surface.** Derivative-persistence surfaces inherit storage-protection-class of most-protected source class AND are independently Sec-flaggable for retention-sprawl + blast-radius-widening + render-time-staleness-join compound risk. **PRD home: §4.3 bullet 2 (concrete SD-12 instance) + §4.3 bullet 3 (SD-13 cross-cutting axis).**

The set is closed at V1. New axes surface through V2-scoping work or through Phase 3 / Phase 6 / Phase 7 lessons-learned only via new ADR amendments to ADR-008; PRD §4 body revisions cannot add canonical axes without an ADR-008 amendment.

### Decision 2 — Fourteen-entry sensitive-data classification matrix as V1 canonical classification

PRD §4.4 lands the V1 sensitive-data classification matrix as fourteen entries (SD-00 through SD-13) in §2-traceability order. The column shape (8 columns: Class ID / Class name / Source-§ / Sensitivity tier / Storage protection class / Retention posture / V1-acceptable disclosure surfaces / Phase 3 forward-pointer ID) is canonical at V1 and binds future class additions to the same column shape. Closed-enum columns are:

- **Sensitivity tier (3 values):** `credential` / `high` / `medium`. Three-level rubric per Q-Tier α — matches V1 spread without false-precision tiers for non-existent classes.
- **Storage protection class (4 values):** `credential-class` / `tenant-scoped-with-app-encryption` / `tenant-scoped` / `tenant-scoped-derivative`. Per Q-Storage α — the `tenant-scoped-derivative` value exists specifically for the §2.6-elevated derivative-persistence axis (axis vi).
- **Retention posture (4 values):** `indefinite` / `bounded-Item-active-only` / `bounded-N-day-rolling` / `indefinite-with-V2-cold-storage-rollover`. Per Q3a Option α; the `bounded-N-day-rolling` value applies to SD-02 Plaid Item-state metadata with **N = 90 days** per Q-Retention-N α.

**Cross-cutting annotation cell convention:** rows that are cross-cutting axis annotations rather than concrete classes (SD-13 at V1) use `—` in sensitivity-tier, storage-protection-class, and retention-posture cells; the V1-acceptable-disclosure-surfaces cell carries the axis-as-posture narrative. SD-13 is the only V1 instance; convention applies forward to any future cross-cutting axis annotation at V2+ expansion.

The matrix is closed at V1. New classes surface through V2-scoping work or Phase 3 / Phase 6 / Phase 7 lessons-learned via ADR-008 amendments; new closed-enum values require ADR-008 amendment. Class additions through PRD revision alone (without ADR-008 amendment) are not permitted.

### Decision 3 — Fifteen-entry Phase 3 RLS test catalog as V1-mandatory test surface

PRD §4.5 lands the V1-mandatory RLS test catalog as fifteen entries (RT-01 through RT-15; RT-07 reserved-vacant per stage-2 row-drafting consolidation rationale; 14 active populated tests). **[COUNT SUPERSEDED 2026-07-19 / SELF-212 Phase-6 index amendment — the "fifteen entries / RT-01–RT-15 / 14 active" figure captured the V1-lock snapshot; live tally now defers to §4.5 (highest-ID RT-28) / §4.4 (highest-ID SD-23); see the ADR-008 SELF-212 amendment at the end of this ADR. The immutability *discipline* is unchanged — only the frozen count is reconciled.]** Ordering is §2-traceability: §2.4-elevated = RT-01 through RT-05; §2.5-elevated = RT-06 (+ RT-07 vacant slot); §2.6-elevated = RT-08 through RT-14; §3-elevated cross-cutting = RT-15. The column shape (7 columns: Test ID / Surface / Test description / Test category / Source-§ / Severity if violated / Related Class IDs) is canonical at V1 and binds future test additions to the same column shape. Closed-enum columns are:

- **Test category (6 values):** `read-path-RLS` / `write-path-RLS` / `worker-context-isolation` / `input-sanitization` / `race-condition` / `test-environment-posture`. Per Q-RT-Cat α — surfaces the actual mechanism distinctions V1 spans.
- **Severity if violated (3 values):** `critical` / `high` / `medium`. Per Q-Sev α — three-tier rubric parallel to sensitivity-tier discipline.

**V1-block threshold: `critical` severity only.** A `critical` severity test failure or unimplemented test blocks V1 ship; expected V1 critical-severity count = 2 (RT-02 Plaid Item table RLS; RT-05 webhook signature verification). A `high` severity test failure during V1 development is a release-blocker for the V1.x patch release introducing the regression but does not block V1 from shipping if the test was passing at V1 ship; post-ship regression triggers immediate-fix patch release. A `medium` severity test is V1-final-targeted with known-issue tickets acceptable at V1 ship.

The catalog is closed at V1. New tests surface through V2-scoping work or Phase 3 / Phase 6 / Phase 7 lessons-learned via ADR-008 amendments. The bidirectional cross-reference between §4.4 Phase 3 forward-pointer ID column and §4.5 Related Class IDs column is structurally enforced at row-drafting time and validated at stage-2 cross-reference pass.

### Decision 4 — V1 retention / availability / incident-handling posture as baseline (closes ADR-002 §7.0 gaps #4 + #5-partial + #6)

PRD §4.6 lands three V1 posture commitments that close ADR-002 §7.0 missing-content gaps:

- **Data retention posture (closes gap #5 jointly with §2.6.4 χ-1).** Per Q3a Option α. Class-by-class per §4.4 retention-posture column with the canonical values per Decision 2 above. Snapshot-side retention lives at §2.6.4 χ-1 (indefinite per F/CTO lock); non-snapshot retention lives at §4.4 + §4.6. **No user-facing delete-my-data control as V1 surface** — Q3a Option γ rejected at gate 1 as over-shaped for single-user V1.
- **Availability/uptime posture (closes gap #6).** Per Q3b Option α. V1 commits to **best-effort uptime, no SLO**. The V1 user-facing availability story is the §2.4.4 non-silent-staleness commitment — when data is stale, the user is told at every consuming surface. Architect Phase 3 sizes infrastructure-side uptime without PRD-locked numeric per §7.2 + §3 (a) routing.
- **Incident-handling posture (closes gap #4 jointly with the rest of §4).** Per Q3c Option α. V1 commits to an **incident-log file at the F/CTO level**; no on-call rotation, no severity rubric beyond §4.5 Sev-α, no postmortem template at single-user V1. **V2-trajectory ramp to formal incident-response shape if/when the second user lands per §7.3 invite-only forward-compat.**

The three posture commitments are V1 baselines, not specifications. V2-trajectory expansion of any of the three (delete-my-data surface; uptime SLO; formal incident-response shape) requires new ADR or ADR-008 amendment.

### Decision 5 — Two pattern divergences from PM-led default ratified at §4 drafting

The §4 drafting executed under two pattern divergences from the quadruple-confirmed PM-led bulk-closeout pattern (§3 → §5 → §6 → §7):

- **Pattern divergence (i) — Hybrid format.** §4.4 sensitive-data matrix and §4.5 RLS test catalog use markdown tables, not bullet enumeration. Posture sub-sections (§4.1 / §4.2 / §4.3 / §4.6) use the Q2 F-A ratified bulleted-with-framing shape mirroring §5 / §6 / §7. **Rationale:** Phase 3 / Phase 5 / Phase 6 / Phase 7 consume matrices and test catalogs as structured data, not prose; tables are grep-able, can be diffed at V2-expansion, and can be cross-referenced by ID from prose sub-sections.
- **Pattern divergence (ii) — Two-stage hybrid drafting pattern.** Per Q4 D-A. Posture sub-sections bulk-closeout in one body bundle (stage 3); §4.4 and §4.5 draft individually with per-table ratify gates on column shape + severity rubric (gates A + B before stage-2 row drafting). **Rationale:** matrix column-shape decisions (78 / 105 cells per table) are upstream-of-row-drafting and warrant ratification before content drafting, not implicit bundling into body-bundle acceptance.

Future Sec-primary-author sections (none queued in Phase 1; possible at Phase 3 or Phase 6 for ARCHITECTURE.md / migration-design content) may reuse or extend these pattern divergences via reference to ADR-008 Decision 5.

**Consequences.**

- **PRD §4 traces to ADR-008** as the canonical-reference anchor. Future readers seeking the canonical axes / classification matrix / test catalog / severity rubric / retention-availability-incident posture should read ADR-008; §4 body content elaborates the canonical references with bullet-level posture commitments and cross-references to upstream sections.
- **Phase 3 RLS implementation work consumes ADR-008 + §4.5** as the V1-mandatory test surface. Every RLS migration PR cites the relevant RT-NN test(s); Security Reviewer joint-PR-review per §4.1 axis-iv write-path RLS symmetry policy and per the Security Reviewer agent definition's "mandatory reviewer on every PR" scope. Critical-severity tests (RT-02 + RT-05) are V1-ship-blockers per Decision 3; Sec hard-line preserved.
- **Phase 5 migration design + Phase 6 PR review consume ADR-008 + §4.4** as the V1 sensitive-data classification. Every migration touching a §4.4 class implements the storage-protection-class commitment for that class; every PR review against a §4.4 class verifies the V1-acceptable disclosure surfaces commitment holds.
- **Phase 7 incident handling consumes ADR-008 Decision 4** as the V1 incident-handling baseline. F/CTO-level incident-log primitive lives at V1; V2 onboarding triggers the ramp to formal incident-response shape per Decision 4.
- **ADR-008 supersedes nothing; consolidates and extends.** Parallel to ADR-002 / ADR-003 / ADR-004 consolidation shape, distinct from ADR-005 / ADR-006 / ADR-007 surgical-amendment shape. ADR-008 closes ADR-002 §7.0 gaps #4 + #6 + partial-#5 without amending ADR-002's text — the closure is documented in ADR-002 §7.0's traceability surface at integration-pass time (Appendix A absorption deferred to future housekeeping PR per §4 routing flag (o); closure documentation lives at §4 routing flag (o) + §4.6 retention/availability/incident-handling bullets).
- **ADR-008 establishes the immutability-after-acceptance boundary for canonical-reference material.** The six axes, the 14-entry matrix, the 15-entry catalog **[the "14-entry matrix" + "15-entry catalog" COUNT figures SUPERSEDED 2026-07-19 / SELF-212 Phase-6 index amendment — live tally at §4.5 (RT-28) / §4.4 (SD-23); see the ADR-008 SELF-212 amendment below. The immutability *discipline* here (structure / rubric / closed-enum value sets / the "new canonical references require ADR-008 amendment" rule) is UNCHANGED — only these two frozen counts are reconciled.]**, the three closed enums (sensitivity tier / storage protection class / retention posture) and the two closed enums in §4.5 (test category / severity), the N = 90 day Item-state retention window, and the three posture commitments (retention / availability / incident-handling) are immutable canonical references. Bullet-level posture commitments at PRD §4.1 / §4.2 / §4.3 / §4.6 remain mutable through future PRD revisions if canonical references hold steady. New canonical references (new axes, new classes, new tests, new enum values, new posture commitments) require ADR-008 amendment.
- **Eleven active routing flags + five boundary notes at §4 lock.** Architect Phase 3 surfaces are: RLS implementation across §4.5 catalog (a); SD-03 Plaid access-token storage shape (b); webhook signature verification (c) Sec/Architect joint; encryption-at-rest evaluation per `tenant-scoped-with-app-encryption` classes (d) — SD-07 sole V1 instance; Item-state metadata 90-day rolling prune mechanism (e); audit-log architecture (f); cron worker tenant-context binding (g); PDF worker tenant-isolation (h); snapshot regeneration race condition (i) Sec/Architect joint; parity-fixture storage and test-environment plumbing (j) Sec/Architect joint. Sec-led V2-ship-gate inventory consolidates four V2-trajectory items (k). Boundary notes (l) through (p) document cross-reference closures.
- **No supersession of any prior ADR.** ADR-002 §1.4 multi-tenant primitive stands; ADR-002 §1.6 tax_treatment three-way tagging stands; ADR-002 §1.7 cost-basis + lot-level deferral stands; ADR-002 §7.0 missing-content gaps #4 + #6 close + #5 partial-close per Decision 4; ADR-002 §8.0 routing flags stand and extend per §4 routing flags (a)–(k); ADR-004 Decision B multi-scope ownership stands and operationalizes at axis ii; ADR-005 settings store stands and operationalizes at SD-04 storage; ADR-006 bracket-aware input layer stands and operationalizes at SD-04 / SD-05 / SD-06 classification; ADR-007 TLH reclassification stands and operationalizes at §4.6 V2-ship-gate inventory item (iii) shared-link delivery §6 advisor-axis re-litigation note.
- **WORKFLOW.md v1.17 changelog entry** lands at integration-pass time documenting §4 lock + ADR-008 acceptance + Sec-lean 21-for-21 track + pattern divergences (i) + (ii) + (iii) all ratified + four-stage two-stage-hybrid drafting pattern executed + §4 closes all Phase 1 Step 3 inventory + Sec posture canonical-reference layer established.
- **Future ADR housekeeping.** When V2-scoping work surfaces (V2 onboarding of the second user per §7.3; V2-trajectory items from §5.4 / §5.6 / §7.1 hitting V2-implementation; V2 derivative-persistence surfaces from §5 deferred candidates), the V2-ship-gate Sec-consults per §4.6 V2-ship-gate inventory produce new ADRs amending ADR-008 (new classes; new test surfaces; new enum values). When Phase 3 architectural decisions warrant Sec posture extensions (e.g., per-tenant-key-derivation mechanism for `tenant-scoped-with-app-encryption` is locked by Architect), those decisions land at ARCHITECTURE.md per ADR-002 §6.0 + §8.0 + Phase 3 territory, not as ADR-008 amendments. When Phase 7 incident-handling lessons surface posture revisions (e.g., the F/CTO incident-log primitive ramps to formal shape pre-V2), those land as ADR-008 amendments to Decision 4. **The ADR-008 canonical-reference layer is intentionally narrow and amendable**; the bullet-level posture content lives at PRD §4 and evolves through PRD revisions if the canonical references hold steady.

### Amendment (2026-07-19 / SELF-212 Phase-6 — RLS-test-catalog index amendment + stale-count reconciliation; lands the owed Lock-9 ADR-008 amendment)

This is the ADR-008 index amendment **flagged-required at Lock 9 ([ADR-011](#adr-011) Decision 13) but never landed in ADR-008's body** (the Lock 9 / Lock 13 SD-matrix + RT-catalog expansions landed only as SECURITY-doc edits; ADR-008's own count figures were never reconciled) — it discharges that obligation and adds the SELF-212 catalog entries in one move. Per the §4.4/§4.5 "additions require ADR-008 amendment" governance clause (Phase 6 lessons-learned path), the §4.5 RLS test catalog gains two entries, **authorized at their surface-introducing ADRs** per the established RT-22 ([ADR-011](#adr-011) Decision 17) / RT-26 ([ADR-011](#adr-011) Decision 4 + [ADR-016](#adr-016)) pattern — ADR-008 remains the canonical **index**; the authorizing rationale + per-entry contract live in the surface-introducing ADR:

- **RT-27** — SELF-212 app→worker credential-admission channel (network-exposure/config layer); authorized at **[ADR-027](#adr-027) amendment (hh)**, which also moves the **[ADR-011](#adr-011) Decision 4 §10 catalogued-instance count 2→3** (RT-22 first / RT-26 second / RT-27 third). HIGH + V1-SHIP-BLOCK. **[§10 2→3 flip PERFORMED at F/CTO ratify 2026-07-19 — [ADR-011](#adr-011) Decision 4 now reads count 3 (RT-22 first / RT-26 second / RT-27 third); this annotation indexes the move.]**
- **RT-28** — Plaid Link CSP posture (per-route nonce-mode CSP hook); authorized at **ADR-028**. MEDIUM, a normal RT-catalog entry — **NOT §10-catalogued** (frontend browser-fetch surface; does not touch the §10 defense-in-depth ledger).

**Stale-count supersession (neutralize-and-defer; effected inline at both origin sites).** Decision 3's "fifteen entries / RT-01–RT-15 / 14 active" figure and the Decision-5 immutability-boundary bullet's "14-entry matrix / 15-entry catalog" figures are **SUPERSEDED** (marked inline at both origins above): they captured the V1-lock snapshot and were never updated as the SD-matrix (→ SD-23) and RT catalog (→ RT-28) grew via their surface-introducing ADRs. **The live canonical tally defers to the SECURITY §4.5 / §4.4 rows** (Sec-owned — §4.5 highest-ID RT-28, §4.4 highest-ID SD-23) plus the highest-ID pointers here. The **immutability discipline itself is unchanged** — the column shape, severity rubric, closed-enum value sets, and the "new canonical references require ADR-008 amendment" rule all still bind; only the frozen **counts** are reconciled (they were always meant to track the catalog).

**Scope (index-only, deliberately minimal).** No change to the §4.5 7-column shape / severity rubric / closed-enum values (no catalog *structure* change); no new SD class (no §4.4 structure change); NO line-item reconciliation of the historical RT-16→RT-26 / SD-14→SD-23 rows (out of SELF-212 scope — a separate doc-hygiene task). The §10 catalogued-instance ledger is moved by [ADR-027](#adr-027) (hh), not by this annotation (RT-28 is non-§10).

**§10 3-axis cross-check (Path B — reference [Decision 4](#adr-011), do not restate the numbered list; Decision 4 read verbatim before drafting):** (i) numbering — RT-22 first / RT-26 second unchanged; RT-27 was appended third at (hh), performed at F/CTO ratify 2026-07-19 (Decision 4 now reads count 3); (ii) layer-attribution — no re-attribution of RT-22 (infra-credential-presence) or RT-26 (code-layer); RT-27's network-exposure/config layer is authored at (hh); (iii) Decision 4 linked, not restated. **De-conflation note:** the §4.5 RLS-test-catalog count (highest-ID RT-28) is a DISTINCT ledger from the §10 catalogued-instance count (now 3) — the former is the full RLS test catalog, the latter the §10 defense-in-depth-instance subset (RT-22 + RT-26 + RT-27); not conflated.

**Governance-visible ratify flag:** this amendment marks figures worded "immutable canonical references" (Decision 5 boundary bullet) as count-superseded — a deliberate, conscious act justified as landing the owed-but-unlanded Lock-9 ADR-008 amendment (the immutability *discipline* is untouched; only frozen counts move). Surfaced for F/CTO ratify at the terminal gate.

**Cross-refs:** [ADR-027](#adr-027) (hh) (RT-27 authorization + §10 2→3, RATIFIED 2026-07-19) · ADR-028 (RT-28 authorization) · [ADR-016](#adr-016) Decision 2 (surface-introducing-ADR authorization precedent) · [ADR-011](#adr-011) Decision 4 (§10 ledger — moved at (hh), indexed here) + Decision 13 / Lock 9 (the owed-but-unlanded ADR-008 amendment this discharges). Rides the SELF-212 build PR; Sec joint-review clean + F/CTO-ratified 2026-07-19.

---

## ADR-007 — Amendment to ADR-002 Finding (b): tax-loss-harvesting recommendations reclassified from V2+ candidate to permanent non-goal

**Date:** 2026-05-17
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 Finding (b) per F/CTO 2026-05-17 ratification during §5 V2 deferred candidates structure proposal)

**Context.** ADR-002 Finding (b) enumerates four explicit V2 candidates: Tax planning (estimated payments), Monte Carlo longevity modeling, Lot-level tax features, and Stock screening (with "possibly a separate tool" hedge). The consolidated V2+ deferred list in ADR-002 §2.0 expanded those four into a broader ~18-item enumeration during the Phase 1 Step 2 ratification; that consolidated list specifically named "Lot-level tax features (per 1.7: lot-level UI, FIFO/LIFO/specific-ID matching, wash-sale detection, **tax-loss harvesting**)" — folding tax-loss harvesting under the lot-level-tax-features V2+ banner.

During Phase 1 Step 3 §5 (V2 deferred candidates) structure-proposal review, the §5/§6 axis surfaced TLH recommendations as advisor-shaped rather than observational. The §5/§6 axis is sharp: §5 enumerates capabilities on the eventual product trajectory (locked-as-V2+ in V1 to preserve scope, but anticipated as legitimate later work); §6 enumerates capabilities that are not in this PRD's universe at all (ADR-002 §3.0 permanent non-goals — public sign-up, money movement, advisor / fiduciary role, real-time price quotes, mobile-native app). PM lean at the §5 structure proposal flagged TLH as a §5/§6 reroute candidate with PM-lean toward §6: "TLH as conceived in Finding (b) — recommend a tax-action against a position — is advisory-shaped output, not observational; sits closer to ADR-002 §3.0 advisor-role non-goal than to V2 trajectory."

F/CTO ratified the PM lean 2026-05-17. This ADR documents the amendment.

**Decision.** F/CTO lock 2026-05-17 (per PM-lean Q3a accepted at §5 structure-proposal ratify gate):

**Amendment to ADR-002 Finding (b) (and the §2.0 consolidated V2+ deferred list's "Lot-level tax features" clause):** Remove "Tax-loss harvesting recommendations" from the V2+ trajectory enumeration. TLH is reclassified as **out-of-scope for this PRD lifecycle (§6 home)** under the advisor-role permanent-non-goal axis (ADR-002 §3.0).

**Rationale.** TLH as conceived in Finding (b) — "recommend a tax-action against a position" — is advisory-shaped output. The recommendation is action-prescriptive ("you should sell holding X to harvest a $Y loss against your realized gains"); it implies tax-timing-and-realization advice with a held-position recommendation as its operative output. This crosses the ADR-002 §3.0 advisor / fiduciary role boundary that the V1 PRD treats as a permanent product-identity non-goal — not a deferral, an identity statement.

Distinguishing TLH from the observational tax surfaces that V1 / V2+ legitimately span: §2.5 Estimated Taxes (V1), §3.2 Metric 2 (mixed `tax_treatment` + jurisdictions capability metric), and §3.3 §2.5 parity test all surface tax obligations and computations as **information** ("here's what you owe, here's how much was realized, here's the bracket-aware projection"). TLH would generate **prescriptive recommendations** ("you should sell X to harvest a $Y loss"). The information-vs-prescription axis is what §6's advisor-role boundary protects.

**Distinction from observational tax-tool extensions that REMAIN on the V2+ trajectory list.** Two ADR-002 §1.7 / Finding (b) clauses are retained as V2+ candidates in §5.5 and do not move with this amendment:

- **Lot-level tax features (FIFO / LIFO / specific-ID lot-matching).** These compute cost basis with more precision and provide lot-level reporting surfaces; they do not generate buy / sell recommendations. Remain V2+ in §5.5 per ADR-002 §1.7 + ADR-004 Decision D V2+ enumeration.
- **Wash-sale auto-detection.** Flags wash-sale rule application on existing realized transactions as an informational annotation on past activity; does not recommend future trades. Remains V2+ in §5.5 per ADR-002 §1.7 V2+ enumeration. V1 already ships user-marked wash-sale flag as an information surface; auto-detection is a refinement of that information surface, not a prescription.

The TLH amendment is narrow: only the "recommend tax-actions against unrealized losses" framing is reclassified to §6. Information-surface extensions of the tax domain (more-precise cost basis, more-accurate identification of wash-sale rule application, multi-state expansion, fiscal-year flexibility, etc.) remain V2+ trajectory items.

**§5/§6 placement consequence.** TLH lands in §6 alongside the existing ADR-002 §3.0 permanent non-goals (public sign-up, money movement, advisor / fiduciary role, real-time price quotes, mobile-native app). §6 body drafting in a future thread will enumerate TLH as one of the listed items under the advisor-role axis. §5.5 (estimated-tax deferrals) does not list TLH; this is the body-level consequence of the ADR-007 reclassification and is reflected in the §5 bulk-closeout body landed alongside this ADR.

**Sec note.** ADR-007 carries no new sensitive-data class and no new credential-handling surface. The amendment narrows V2+ scope rather than expanding it; no Sec posture change. (Parallel to ADR-005 / ADR-006 Sec one-line notes for amendment ADRs that don't expand the data or credential surface.)

**Consequences.**

- **PRD §5.5 (V2 deferred candidates — estimated-tax deferrals) does not list TLH.** The §5 body landed alongside this ADR omits TLH from §5.5. Future readers seeking TLH's V1 PRD home should reference §6 (out-of-scope for this PRD lifecycle) and the §6 enumerated permanent-non-goal list under the advisor-role axis.
- **PRD §6 will enumerate TLH at §6 body drafting time.** §6 is currently a stub on PRD.md; §6 drafting in a future thread lands TLH alongside the existing ADR-002 §3.0 permanent non-goals.
- **ADR-002 Finding (b)'s remaining V2+ enumeration stands.** Monte Carlo longevity modeling remains V2+ (landed in §5.5 as observational projection surface per F/CTO Q3b ratify). Stock screening remains V2+ with the "possibly a separate tool" hedge preserved verbatim (landed in §5.5 with hedge per F/CTO Q3b ratify). Tax planning (estimated payments) was already promoted to V1 by ADR-004 Decision D and operationalized by ADR-006; no change. Lot-level tax features remain V2+ minus TLH per this amendment.
- **ADR-007 supersedes nothing; amends ADR-002 Finding (b) specifically.** Parallel to how ADR-005 amended ADR-002 §1.2 (planning targets V1 static reference-value rendering carve-out) and ADR-006 amended ADR-004 Decision D (bracket-aware input layer). Narrow, surgical, with the parent ADR's other clauses unchanged. Future readers should read ADR-002 Finding (b) first, then ADR-007 to layer the TLH reclassification.
- **ADR-007 reinforces the §5/§6 axis-as-product-identity-boundary pattern.** When a V2+ candidate from an earlier ratification turns out on inspection to cross the §3.0 advisor / fiduciary / money-movement / public-distribution / real-time-quote / mobile-native axis, the resolution is to move it to §6 rather than carry it forward as a deferred V2+ trajectory item that the PRD would have to re-litigate at V2-scoping time. The §5/§6 distinction is the V1 PRD's mechanism for keeping product-identity decisions sharp; ADR-007 is the first amendment that exercises that mechanism.
- **No supersession of ADR-002 as a whole.** ADR-007 amends Finding (b) specifically; ADR-002's other findings (a / c / d / e / f) and §1.0 – §8.0 sub-decisions stand unchanged. Cross-reference: ADR-005 + ADR-006 also amended ADR-002 surgically without supersession; ADR-007 follows the same pattern.
- **No new Architect routing flag.** ADR-007 narrows scope; the V1 PRD has no TLH-touching surface to route to Architect Phase 3.
- **Future ADR housekeeping.** If a V2-scoping-phase review revisits ADR-007 (e.g., F/CTO at V2-scoping time wants to consider a tax-loss-harvesting *information* surface that flags wash-sale-eligible loss opportunities as an observational annotation rather than a prescriptive recommendation), that revisit would be a new ADR — not a supersession of ADR-007. The information-vs-prescription axis is the boundary; an information-surface TLH could in principle re-enter V2+ trajectory without violating the §6 advisor-role boundary.

---

## ADR-006 — Amendment to ADR-004 Decision D: V1 input-layer characterization (bracket schedules + tax_character enum)

**Date:** 2026-05-17
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-004 Decision D input-layer wording based on F/CTO 2026-05-17 correction surfaced during §2.5 body drafting, plus operationalization of the Sub-Cat tax-character attribute that the §2.5 surface needs)

**Context.** ADR-004 Decision D (2026-05-13) ratified V1 inclusion of estimated quarterly tax payment computation in "primitive form" with the following input-layer characterization: *"Federal marginal rate input"* and *"separate marginal rate input"* for Federal and California FTB. That wording was derived from the 2026-05-13 script audit's reading of the Asset Summary `Est Taxes` sheet (parity-matrix line 80: *"Marginal tax rate input, quarterly estimated payment computation…"*). During §2.5 body drafting, two pieces of evidence required revisiting the input-layer characterization:

1. **F/CTO 2026-05-17 correction on the bracket-aware shape:** F/CTO direct workflow knowledge surfaced that the existing Est Taxes sheet does not use a single marginal-rate input × income; it uses **marginal tax bracket tables + standard deduction**, with realized income for the year plugged into the bracket schedule and tax computed progressively against the deduction. F/CTO quote: *"existing flow with the google sheets has marginal tax brackets and rates listed on the est_taxes sheet. The income for the year get's plugged into that set of tables and estimates the real tax amount based on using the standard deduction. This is more accurate than just plugging in a marginal rate to use…"* The 2026-05-13 audit-derived ADR-004 wording was incomplete — the audit characterization was simplified relative to the actual sheet, and the ADR's "marginal rate input" framing was a re-narration of that incomplete audit reading rather than a deliberate F/CTO scope decision.

2. **§2.5.1 ζ-2 lock on Sub-Cat tax-character attribute:** §2.5.1 body drafting surfaced the need for the per-Sub-Cat tax-character attribute as a V1 input layer alongside the bracket schedules — to route qualified dividends to the Federal LT CG schedule, exclude tax-exempt interest from Federal computation, and provide forward-compat for V2+ tax-character refinements. F/CTO locked ζ-2 at 2026-05-17: a `tax_relevant` boolean + `tax_character` enum with 5 V1 values (`ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`) on each Sub-Cat in the §2.3.1 + §2.2.1 taxonomies.

The audit-derived "marginal rate input" wording would, under a strict reading, justify a less-accurate V1 (single rate × income) than the F/CTO existing system actually uses. A practical reading — anchored in F/CTO direct workflow knowledge — confirms the existing system's bracket-aware computation as the V1 baseline. This ADR documents the amendment.

**Decision.** F/CTO lock 2026-05-17 (per CoS-relayed §2.5 v2 structure proposal + §2.5.1 / §2.5.2 body drafting):

**Amendment to ADR-004 Decision D (two-axis amendment):**

### Axis 1 — V1 input layer: bracket schedules + standard deduction (§2.5.2-scope)

The Decision D input-layer wording "Federal marginal rate input" / "separate marginal rate input" is amended to:

> **V1 input layer (per-jurisdiction bracket tables + standard deduction, user-entered):**
> - Federal **ordinary-income bracket schedule** (multi-row rate + threshold table)
> - Federal **separate LT capital-gains bracket schedule** (typical: 3 rows 0% / 15% / 20%)
> - Federal **standard deduction** scalar
> - California FTB **ordinary-income bracket schedule** (single schedule; CA treats LT capital gains as ordinary income, no separate CA LT CG schedule in V1)
> - California **standard deduction** scalar
> - Single-filing-status V1 (F/CTO's filing status fixed at seed time)
> - **User-entered, manual update at tax-year rollover** — no live tax-data API in V1

**V1 quarterly estimated payment computation is bracket-aware progressive** against these schedules with standard deduction applied to ordinary-routed income before the bracket walk. Live tax-data API ingestion of bracket tables is V2+.

### Axis 2 — V1 input layer: Sub-Cat tax-character attribute (§2.5.1-scope)

Additive to Decision D's input-layer characterization:

> **Each Sub-Cat in the §2.3.1 cash-flow taxonomy and the §2.2.1 asset taxonomy that holds securities subject to capital-gain realization carries:**
> - `tax_relevant` boolean — gates whether the Sub-Cat contributes to §2.5.1 tax-relevant income decomposition
> - `tax_character` enum with 5 V1 values: `ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`

**Federal routing rules per the enum (applied by §2.5.3 computation engine):**

| §2.5.1 column | `tax_character` enum | Federal schedule routed to |
|---|---|---|
| Ordinary Income | `qualified_dividend` | LT CG |
| Ordinary Income | `tax_exempt_interest` | (excluded from Federal computation) |
| Ordinary Income | `ordinary` / `short_term_only` / `long_term_capital_gain_eligible` / default | Ordinary |
| ST CG | any | Ordinary |
| LT CG | any | LT CG |

California FTB routing collapses to a single ordinary schedule per (κ) — all non-excluded contributions route to the CA ordinary schedule.

**Both attributes seeded at V1 bootstrap** from the F/CTO existing system (parallel to ADR-004 Decision C taxonomy seeding) and editable via migration only in V1; user-editable Sub-Cat tax-attribute CRUD UI is V2+ as an extension to §2.3.1 + §2.2.1 broader taxonomy CRUD V2+.

### Decision D "Primitive means" boundary — unchanged

Both axes operationalize Decision D's "Primitive means" framing rather than expanding it. The following remain V2+ per the original Decision D verdict (unchanged by this amendment):

- Multi-state tax handling (any non-California state)
- Non-US tax handling (RRSP, ISA, foreign tax credits, etc.)
- Lot-level tax features (FIFO/LIFO/specific-ID lot-matching; wash-sale auto-detection; Section 1256 auto-detection; tax-loss harvesting recommendations) — per ADR-002 §1.7 + ADR-004 D
- Monte Carlo longevity modeling — per ADR-002 Finding (b)

### F/CTO V1-simplification scope choices (locked alongside ADR-006)

The §2.5 body drafting surfaced two additional V1-simplification scope choices that operationalize Decision D's "Primitive means" framing **without expanding Decision D's V1 scope** (and therefore don't require ADR-006 amendment surface — documented here for decision-history completeness):

- **μ-2 (Realized side at §2.5.3): bracket-derived expected-annual ÷ 4 only; no safe-harbor floor computation in V1.** Tax Balance Prior Year row appears as informational reference only. Safe-harbor computation (Federal 100%/110%-of-prior-year + CA FTB rules) is V2+. F/CTO 2026-05-17 deliberate scope choice for V1 simplicity.
- **ο-a (Unrealized side at §2.5.4): simplified marginal × aggregate G/L per F/CTO Task #2 close verification (2026-05-14).** Federal_LT_CG_top_bracket_rate × `aggregate_unrealized_G/L_taxable` + CA_top_marginal_rate × `aggregate_unrealized_G/L_taxable`. No ST/LT split; no tax_character enum routing on Unrealized; no §2.5.3 engine reuse for Unrealized. **Federal_top_marginal_rate sourced from Federal LT CG top-bracket row per F/CTO 2026-05-17 override** (less-conservative parity choice over PM's conservative-default ordinary top-bracket; aligns with existing-system Est Taxes sheet treatment per F/CTO direct-workflow-knowledge clarification of the Task #2 "marginal-rate" factor). Bracket-aware-as-if-realized refinements (ο-b full / ο-c hybrid-LT-only) are V2+.

**Sec sensitivity note.** Sec at-lock 2026-05-17: *"Sec-class implications: data class #1 (tax-bracket-revealing data — §2.5.2 bracket schedules + standard deduction) sensitivity incrementally higher post-amendment vs. the original Decision D scalar-rate framing; storage / access-control posture unchanged."*

**Consequences.**

- **PRD §2.5 body content traces to ADR-006** for the input-layer scope characterization. The bracket schedules + standard deduction at §2.5.2 + the Sub-Cat tax-character enum at §2.5.1 are direct downstream of ADR-006's two-axis amendment. §2.5.3 computation consumes both axes; §2.5.4 Realized consumes via §2.5.3; §2.5.4 Unrealized under ο-a consumes only the top-marginal-rate values from §2.5.2 (a specific top-bracket row read per jurisdiction, not the full schedule or the tax_character routing).

- **ADR-006 supersedes nothing; amends ADR-004 Decision D specifically.** Parallel to how ADR-005 amended ADR-002 §1.2 — narrow, surgical, with the parent ADR's other clauses unchanged. Future readers should read ADR-004 Decision D first, then ADR-006 to layer the input-layer amendment.

- **ADR-006 reinforces the audit-derived-ADR-text feedback pattern** (memory entry 2026-05-17): when audit notes are re-narrated into ADR text, the resulting ADR wording can over-simplify relative to the actual artifact. The 2026-05-13 script audit reading of the Est Taxes sheet as "marginal rate input" was an over-simplification; F/CTO direct workflow knowledge surfaced the actual bracket-aware computation during §2.5 body drafting. Future ADRs that re-narrate audit findings should be verified against direct artifact inspection at body-drafting time, not assumed to be deliberate scope decisions.

- **PRD §2.5.2 + §2.5.1 settings-store and taxonomy schema additions surface as Architect routing flags** (§2.5 routing-flags block items (a) Sub-Cat tax_character schema, (e) bracket-table-update cadence, (f) §2.5.2 settings store dedup, (g) bracket-schedule routing logic location). Architect Phase 3 picks the implementation shape for both axes; the V1 PRD commitment is the user-facing shape per ADR-006, the storage / query / caching shapes are downstream.

- **§2.5.2 settings store extends §2.3.2 planning-targets settings store per ADR-005.** The richer field shape (multiple bracket rows × multiple schedules × per-jurisdiction × standard deduction scalar, vs. §2.3.2's two scalars) is a new Architect Phase 3 dedup-vs-separate decision. Sec re-engagement on the settings-UI plumbing was already triggered at §2.3.2 lock per Sec Task #23 forward-looking comment #3; §2.5.2 extends the surface additively, not as a new trigger.

- **Sec sensitive-data class #1 (tax-bracket-revealing data) sensitivity upgraded incrementally** post-amendment. The original Decision D scalar-rate framing exposed a single-scalar-per-jurisdiction rate; the amended framing exposes per-jurisdiction multi-row bracket schedules + standard deduction scalar. Sec storage / access-control posture commitment from §2.3.2 settings-UI tenant-scoping carries; no new storage / access-control surface. ADR-006 records this as a Sec-recorded note rather than a new Sec routing flag.

- **No supersession of ADR-004 as a whole.** ADR-006 amends Decision D's input-layer characterization specifically; ADR-004's other Decisions (A target visualization, B multi-scope ownership, C multi-level taxonomy) stand unchanged. ADR-002 amendments via ADR-004 stand unchanged.

- **F/CTO V1-simplification scope choices μ-2 + ο-a documented here for decision-history; not separately ADR-ratified.** μ-2 (safe-harbor V2+ on Realized side) and ο-a (simplified marginal × G/L on Unrealized side) are operationalizations within Decision D's "Primitive means" framing — they don't expand V1 scope beyond what Decision D already authorized, and they pre-existed in F/CTO's existing-system Est Taxes sheet per F/CTO direct-workflow-knowledge. Documenting them in ADR-006 preserves the decision history without elevating them to amendment-shape (they're refinements of Decision D's existing primitive-form scope, not amendments).

- **Future ADRs touching tax-domain inputs route to ADR-006** as the input-layer characterization anchor. Future V2+ amendments (e.g., live tax-data API; multi-state expansion; lot-level features) reference ADR-006 + ADR-004 Decision D as the V1 baseline they're expanding from.

---

## ADR-005 — Amendment to ADR-002 §1.2: planning-targets V1 static reference-value rendering

**Date:** 2026-05-14
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 §1.2 V1 non-goals based on §2.3 drafting evidence and PDF-inspection of the canonical Finance_Report)

**Context.** ADR-002 §1.2 ratified specific V1 non-goals for spending categorization, including *"budget targets per category, category-level trend charts, custom user-defined categories, recurring-transaction detection, and category alerts/notifications."* During §2.3.2 (cross-account multi-period cash-flow rollup) drafting, two pieces of evidence required revisiting the budget-targets non-goal:

1. **Parity-matrix lines 178 + 199:** the existing Finance_Report renders the Founder/CTO's authored income and expense target values as static caption text under the Income and Expenses section headers, alongside the actual cash-flow totals — used as reference values for visual comparison, not as tracked-budget-with-variance.
2. **F/CTO direct PDF inspection of `Finance_Report_2026_04.pdf` page 6:** confirmed the targets appear as inline caption text ("Pre-tax income from all sources… Target is [value]:" and "Discretionary spending… Budget is [value]:"); no variance computation, no alert mechanic, no per-category target breakdown — only two aggregate values (income target as annual, expense target as monthly).

A strict reading of §1.2's "budget targets per category" non-goal would exclude any V1 rendering of target values. A practical reading — surfaced by the §2.3-drafting evidence — distinguishes between *static reference-value rendering* (parity with existing Finance_Report) and *budget-tracking mechanics* (variance computation, threshold alerts, per-category rolling budgets). The original §1.2 non-goal targeted the latter; the former is parity-preserve.

**Decision.** F/CTO lock 2026-05-14 (Option (a)(i) per CoS-surfaced options framing during §2.3.2 drafting):

**Amendment to ADR-002 §1.2:** the V1 non-goal on "budget targets per category" applies to budget *tracking* mechanics — actual-vs-target variance computation, threshold alerts, category-level rolling budgets, per-category target authoring beyond aggregate values. These remain V1 non-goals.

**V1 includes:** static reference-value rendering of two user-authored aggregate targets (one income target, one expense target) as inline caption text alongside the §2.3.2 cross-account cash-flow rendering — parity-preserve with the existing Finance_Report. **No variance computation, no alert mechanic, no per-category target breakdown.**

**Edit mode (Option (i) per F/CTO lock):** V1 includes a settings UI for user-editing of the two target values — the first concrete V1 surface needing a user-editable settings store. (Alternative considered: seeded-at-bootstrap with edit-via-migration-only — rejected on F/CTO call.)

**Consequences.**

- **PRD §2.3.2** describes the planning-targets caption-text rendering as V1; trace anchors to this ADR for the V1/V2 boundary on tracking mechanics.
- **New V1 settings-UI surface** — introduced solely by this amendment. Architect routing flag #4 in §2.3's Open routing flags block covers the plumbing (generalized settings/preferences table vs planning-targets-specific storage); Sec re-engagement triggered when that plumbing surfaces (per Sec Task #23 forward-looking comment #3 — write-path validation, audit trail, tenant-scoping of the settings store).
- **New Architect flag on planning-targets storage shape** (flag #5 in §2.3's block): likely one income-target total + one expense-target total, period-typed (annual / monthly); Architect Phase 3 confirms.
- **Other §1.2 V1 non-goals unchanged:** category-level trend charts (now partially superseded by §2.3.4 Historical Expenditures expenses-only chart — this is a separate amendment surface, see WORKFLOW v1.9 entry for §2.3.4's "capability not in original parity-matrix V1 enumeration" framing; ADR-005 does not amend the trend-charts non-goal); custom user-defined categories (V2 per ADR-004 Decision C taxonomy CRUD V1/V2 split — already amended); recurring-transaction detection (covered as recurring-vendor inference V1 per §2.3.1 inference-layer lock 2026-05-14 — this is also a §1.2 amendment in shape, captured in §2.3.1's trace + routing-flag #2 not in this ADR); category alerts/notifications (remain V1 non-goal).

**Scope note on §1.2 amendments not in this ADR.** The §2.3.1 recurring-vendor inference V1 inclusion and the §2.3.4 expenses-only time-series chart V1 inclusion are both technically §1.2 amendments in shape (the original §1.2 listed "recurring-transaction detection" and "category-level trend charts" as V1 non-goals). They are not consolidated into this ADR because: (a) §2.3.1's inference layer is a sub-decision within the V1-required transaction-to-bucket assignment UI (the alternative is unworkable per F/CTO's archetype), not a stand-alone V1 surface expansion; and (b) §2.3.4 was caught via PDF inspection as a parity-grounded existing-system surface F/CTO already uses, not a V1 expansion. Their V1/V2 boundaries are documented in the §2.3 PRD section's per-story traces and the §2.3 routing-flags block; this ADR documents only the planning-targets amendment because it introduces a genuinely new V1 user-facing capability (the settings UI) not present in the original ADR-002 §1.2 framing.

---

## ADR-004 — Phase 1 Step 3 script-audit amendments to ADR-002

**Date:** 2026-05-13
**Status:** Accepted
**Phase:** 1 (Step 3; amends ADR-002 ratification verdicts based on a mid-Step-3 functional audit of the Founder/CTO's existing manual-spreadsheet financial system)

**Context.** Phase 1 Step 3 began as PRD section drafting under the original Phase 1 model: preliminary findings → PM-led generative drafting → F/CTO sign-off section-by-section. The §2.1 (net worth) drafting completed and landed on disk under that model. §2.2 (asset allocation) opened with a framing question, and partway into the §2.2 sub-decision sequence the Founder/CTO surfaced an existing two-level asset-categorization taxonomy in active use and declared it a hard V1 backend requirement (with explicit "100% duplicated work to implement a dumbed-down version" reasoning).

That moment exposed a drift: the abstract-from-preliminary-findings drafting was generating requirements the F/CTO already had concrete, system-grounded answers for. The Founder/CTO paused the section-drafting flow and reframed Step 3 around a script-audit-first approach — anchor V1 in functional parity with the existing system, defer to V2 only what F/CTO genuinely doesn't use today, drop only what F/CTO explicitly removes.

Between 2026-05-13 and the same date, the Chief of Staff (with subagent assistance for large-file digesting) audited five artifacts:

1. **`MoskoFinance`** — Google Apps Script with two custom Sheets functions (`calculateHoldings`, `calculateSales`). Holdings + realized-capital-gains compute layer.
2. **Master** Google Sheet — central reference data with 5 load-bearing sheets (`AssetDB`, `AssetPriceHist`, `Asset Categories`, `Cash Flow Categories`, `Account Types`) soft-linked into per-account workbooks.
3. **Fidelity Brokerage (Rich)** — representative per-account workbook with 5 displayed sheets (Summary, Cash Flow, Transactions, Holdings, Sales) and 6 soft-link reference sheets (`_assetdb`, `_assetpricehist`, `_assetcat`, `_cfCat`, `_accounttype`, `_targetaloc`).
4. **Asset Summary** — central cross-account aggregator with 8 in-scope sheets (Account Totals, Nav History, Nav Chart, Asset Allocations, Cash Flow rollup, Est Taxes, `_salesCG`, `_cfMonth`/`_cfQ*`) plus several explicitly-dropped or out-of-scope sheets (Big Ticket Fund, `_Nav_History_MoskoLiu`, `_Est_Taxes_Year`, Account Info, Logins).
5. **Finance_Report** — Google Doc, the canonical V1 deliverable (monthly trust-labeled, full-household-scoped report).

The full audit findings and capability-by-capability V1/V2/drop status are captured in `docs/v1-parity-matrix.md`. This ADR consolidates the four ADR-002 amendments those findings require.

**Decisions.**

### Decision A — Amendment to ADR-002 §1.1: rebalance-target visualization is V1

ADR-002 §1.1 ratified: *"observational allocation visualization is V1; rebalancing suggestions are V2+."* The audit found target-vs-actual allocation with `$ ReAlloc` dollar deltas is currently in active V1-equivalent use across both per-account workbooks (Summary sheet's Asset Allocation Dashboard) and the Asset Summary aggregator (Asset Allocations sheet). The free-text "Rebalancing Targets" section in the monthly Finance_Report is human-curated action commentary derived from this visualization, not generated by the system.

**Amendment:** V1 includes target % vs. actual % allocation visualization with `$ ReAlloc` dollar-delta computation across the allocation surface. This is the visualization-of-the-gap layer. Auto-generated rebalance *suggestions* (system-recommended buy/sell actions) remain V2+ per the original §1.1 intent.

The distinction:

- **V1 (this amendment):** "Your target is 65% equities, you're at 51%, that's $381,642 underweight. Here's the gap as a number." Composes naturally with the multi-level taxonomy (Decision C below) — the gap is visible at top-level Cat and at Sub-Cat resolution.
- **V2+ (unchanged from original §1.1):** "Sell $X of VTI and buy $Y of VOO to bring you into target." The recommendation engine, tax-lot-awareness, account-type-awareness, brokerage-workflow adjacency is the V2 surface.

Monthly Finance_Report's "Rebalancing Targets" free-text commentary is V1-authored-by-user, not auto-generated. V1 ships a free-text field for the user to author monthly action items; auto-generation against the gap visualization is V2+.

### Decision B — Extension to ADR-002 §1.4: multi-scope ownership within multi-tenant

ADR-002 §1.4 ratified multi-tenant-from-day-one with single-user V1 usage and forward-compatibility. The audit surfaced an orthogonal capability not addressed by §1.4: the Founder/CTO has accounts under multiple legal ownership scopes (personal "Rich", "RichMoskoTrust" 2023 trust, retirement custodial accounts IRA/HSA) and tracks allocations and reports by scope. The `RichMoskoTrust Titled?` flag in the Account Info sheet plus six distinct `$ Alloc` columns in Asset Summary's Asset Allocations sheet are evidence of scope-aware data.

**Extension:** ADR-002 §1.4's multi-tenant-from-day-one verdict stands unchanged. Additionally, **the V1 data model supports multi-scope ownership as a first-class attribute on accounts** within a single tenant. Scopes are user-defined ownership labels (examples from F/CTO's system: "Rich personal", "RichMoskoTrust", "Retirement-IRA", "Retirement-HSA"). Allocation and reporting aggregations support scope-filtering.

**V1 default report scope:** full-household (all scopes aggregated). This matches the Finance_Report's current behavior — the document header carries the trust name as administrative identification, but content includes all household accounts regardless of scope.

**V2+ deferred:** per-scope reporting surfaces (one report per scope), scope-aware UI filtering, CRUD UI for managing scopes. Data model supports it from V1; visible product surfaces wait.

Multi-scope ownership is distinct from the household-vs-individual question deferred in ADR-002 §1.4 / §7.0. Households are not in scope (out of PRD lifecycle); multi-scope-within-a-user-household is in scope as a data attribute.

### Decision C — Amendment to ADR-002 §1.8: multi-level user-meaningful asset taxonomy in V1

ADR-002 §1.8 ratified: *"uniform transaction-level handling, security type as categorization attribute, mechanics deferred V2+."* The Founder/CTO's mid-audit input was unambiguous: the existing 6×~35 two-level taxonomy (Cat: Cash / Bonds / Equity / Alternatives / Liabilities / RealEstate × Sub-Cat: FDIC, SIPC, T-bill, CD, IGL, IGI, HYI, INTL, US-01-Basic_Materials through US-10-Utilities, ExUS-Developed_Market, ExUS-Emerging_Market, US-Index_Non_Sector, US-Growth_Non_Sector, REIT, Crypto-Fx, Commodities-Other, Volatility-Hedges, Volatility-60/40, Credit-Balance, EstTaxes-Pending, Loan-Balance, Residential, Commercial, Remodel-Equity, Vehicle, Misc) is a hard V1 backend requirement on the grounds that (a) deferring would create unbounded migration cost (table rewrites), and (b) a single-level surface would be unusable for the V1 instance.

**Amendment:** V1 includes a two-level user-meaningful asset taxonomy (top-level Cat × Sub-Cat). The operationalization is **hybrid** (Option 3 from the Product Manager's pre-pause analysis):

- **V1 data model:** user-scoped multi-level taxonomy tables (one taxonomy per tenant; per-user in V2+ if needed). Forward-compatible for multi-user V2 — no migration debt.
- **V1 seeded with the Founder/CTO's taxonomy** as a migration/seed file at V1 single-user-instance bootstrap.
- **V1 holding-to-bucket assignment UI** — required for V1 active workflow. Users assign holdings to Cat/Sub-Cat buckets through the product, not via direct database access.
- **V1 does NOT ship a user-editable taxonomy CRUD UI** (create / rename / delete categories or sub-categories). Editing the taxonomy in V1 happens via migration / direct database access.
- **V2 adds the editing UI.** Backend is V1-ready; UI is the V2 add.

The original §1.8 verdict's "mechanics deferred V2+" clause stands for securities mechanics specifically (Greeks, intrinsic value, complex lifecycle events for derivatives; YTM, duration, accrued interest for bonds; tax-character decomposition for REITs/MLPs; structured-product specifics). Multi-level taxonomy is not a "mechanic" in that sense — it is a categorization-grammar layer that the existing system has demonstrated is load-bearing.

### Decision D — Amendment to ADR-002 §2.0 (Finding b): estimated quarterly tax payments in V1

ADR-002 §2.0 listed "Tax planning (estimated payments)" as a V2 candidate (Finding b). The audit found the existing Asset Summary contains an `Est Taxes` sheet with: marginal tax rate input, quarterly estimated payment computation, an "IRS" account row tracking actual estimated payments sent vs. estimated obligation, and parallel Federal + State (California Franchise Tax Board) computation tables. The Founder/CTO described this as "works in this primitive form" — sufficient for V1 single-user use, not polished.

**Amendment:** V1 includes estimated quarterly tax payment computation in primitive form:

- Federal marginal rate input
- Federal quarterly estimated payment computation derived from realized income (interest, dividends, bond premiums, capital gains)
- An "IRS" account (or equivalent settable label) for tracking actual estimated tax payments made
- **Parallel California FTB state tax computation** — separate marginal rate input, separate quarterly payment tracking, separate FTB account
- Realized vs Unrealized Tax Liabilities line items derivable from the estimated-tax surface

**"Primitive" means:** V1 supports Federal + California only (the Founder/CTO's jurisdictions). Multi-state tax-engine sophistication, non-US tax handling, lot-level tax features (Federal or state), and tax-loss-harvesting recommendations remain V2+ per the original Finding (b) bucket.

**Remaining ADR-002 Finding (b) items unchanged:** Monte Carlo longevity modeling, lot-level tax features (FIFO/LIFO/specific-ID lot-matching, wash-sale auto-detection, tax-loss harvesting recommendations), and stock screening all remain V2+.

**Consequences.**

- **PRD §2 scope expands.** The §2 user-stories section now needs at least six subsections, not the three originally implied by ADR-002 §1.0:
  - §2.1 Net worth (already drafted; needs extension under Decisions A, B, C and the NAV-with-tax-liability definition)
  - §2.2 Asset allocation (drafted under Decision C operationalization with Decision A `$ ReAlloc` visualization)
  - §2.3 Spending and income categorization (multi-period views, scope-aware aggregations under Decision B)
  - §2.4 Cross-cutting (manual entry, Plaid re-auth, AcctSetup non-cash events, capital gains compute)
  - §2.5 Estimated taxes — **NEW SECTION** per Decision D
  - §2.6 Monthly Report output — **NEW SECTION**; the canonical V1 deliverable

- **Existing on-disk PRD content needs cross-check.** `PRD.md` currently contains §1 (vision + archetype + deferrals) and §2.1 (six user stories). Both were drafted from preliminary findings, not from script-grounded truth. PM cross-checks §1 (specifically §1.2 attribute #4, which a queued reframe addresses) and §2.1 (extend NAV definition, extend headline-delta to multi-horizon × inflation-adjusted, add scope-awareness to the "net worth is mine, not anyone else's" story) under Decision B / Decision C / Decision D context.

- **PRD adds a new §8 — V1 milestone framing.** The expanded post-ADR-004 V1 scope (six §2 subsections plus new capability areas) makes a single "ship V1" event impractical. §8 establishes a V1 sub-version convention (V1.0 → V1.x → V1.final), criteria for what makes each sub-version shippable, and the drop-replace migration pattern (V1.x backend becomes the data source for residual existing-system Google Sheets views during transition, so the Founder/CTO's monthly-finance workflow continues uninterrupted as the data plane shifts underneath). §8 frames the milestone scaffolding; specific sub-version sequencing and per-version capability boundaries remain Phase 4 (Scoping) / Linear-backlog work. §8 also serves as the answer to ADR-002 §7.0 item 7 (*"'V1 done' definition"*): **V1 done = all existing-system capabilities replaced + ADR-004 scope delivered.** PM drafts §8 in late-Step-3, after §1–§7 are substantively settled.

- **`docs/v1-parity-matrix.md` is the V1 capability scope artifact.** PM works from the parity matrix's "PRD §2 mapping" table for what each subsection covers. Open product decisions (the 12-item list in the parity matrix) become the new sub-decision queue PM surfaces to F/CTO one at a time.

- **ADR-002 §8.0 Architect routing flags grow.** The audit surfaced several new Architect items (CPI-U inflation source — manual entry vs. live API; IMPORTRANGE-equivalent cross-account aggregation pattern in V1 SaaS; multi-scope-aware schema; multi-level user-scoped taxonomy data model with seed-on-first-use; live-vs-manual price-source segregation; date-window toggle persistence; freshness/staleness signaling). These get appended to the parity matrix's routing-flag inventory; the PRD references them in the relevant section traces.

- **ADR-002 §6.0 cost target is at risk.** The ≤ $50/month V1 cost target was scoped to a Transactions-only V1. The expanded V1 (Plaid Transactions + Plaid Investments + multi-level taxonomy + estimated taxes + multi-scope data model + monthly-report generation) likely changes the architectural cost shape. Flag for Architect Phase 3 review; the *target* constraint is still F/CTO-policy, but the *bill* gets reconciled in ARCHITECTURE.md.

- **Engagement model: PM resumes section-by-section pacing.** The Founder/CTO has confirmed the per-section sub-decision pacing established in PRD §2.1 drafting continues post-audit. The script audit doesn't change the pacing rhythm — only changes the *grounding* of what PM proposes (script-grounded V1 scope, not preliminary-findings-derived V1 scope).

- **No supersession of ADR-002.** ADR-004 amends specific verdicts; it does not supersede ADR-002 as a whole. The unamended verdicts in ADR-002 stand. Future readers should read ADR-002 first, then ADR-004 to layer the amendments.

- **No supersession of ADR-003.** ADR-003's team-mode engagement pattern is unaffected; team-mode coordination continues to be the Step 3 mechanism. The audit was Chief-of-Staff-led (not PM-led) and proceeded as a CoS-orchestration step within the same team.

- **Future ADR housekeeping:** When PM begins §2 revision, individual sub-decisions that meaningfully alter scope (e.g., NAV definition lock, Rebalancing Targets V1-shape, multi-scope reporting V1-vs-V2) may warrant their own ADR entries. ADR-004 is the consolidated *amendment* ADR; individual *new product decisions* during §2 revision belong in ADR-005 onward.

---

**Date:** 2026-05-11
**Status:** Accepted
**Phase:** 1 (decision made between Step 2 close and Step 3 entry; applies Step 3 onward)

**Context.** Phase 1 Step 2 ratification exercised mosko-fintech's subagent setup at depth: the Product Manager subagent was invoked three times (full ratification report, focused income-categorization V1 check, post-override scope-implication assessment). Two friction points became clear during that work:

1. **No SendMessage available in this harness.** The Agent tool's documented "continue an existing agent" mechanism isn't loaded by default in Claude Desktop. Each PM consultation therefore had to be a fresh spawn with full re-briefing — a real cost when the PM has accumulated 5,000-word ratification context to re-acquire each turn.
2. **Orchestrator-mediated relay has its limits.** Founder/CTO expressed wanting to "meet with the PM" directly, surfacing a gap between the agent-roster vision ("work with my PM") and the subagent mechanic ("one-shot delegations through me as orchestrator"). The CoS-as-relay pattern works but adds friction for any multi-turn agent conversation.

**Claude Code Agent Teams** (experimental, gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) was evaluated as an alternative. Documentation: `https://code.claude.com/docs/en/agent-teams`. A smoke test in Claude Desktop confirmed:

- **Compatibility:** spawn succeeds; teammates load their agent-file system prompts correctly; SendMessage works for lead↔teammate communication; team config persists at `~/.claude/teams/{name}/`.
- **Backend:** in-process only (split-pane requires tmux/iTerm2, which Claude Desktop doesn't provide). Lead and teammates are co-located in one Claude Desktop window; user navigates between them via session cycling.
- Three friction points surfaced during the smoke test; mitigations captured below.

**Decisions.**

1. **Engagement-pattern catalog.** mosko-fintech operates with three subagent engagement patterns, used for different work shapes:
   - **Task mode** — one-shot `Agent` invocation. Used for: a focused deliverable from a single role with no follow-up turns expected. Example uses: Phase 0.5 smoke tests; one-shot research lookups via claude-code-guide; mechanical drafting work.
   - **Meeting mode** — multi-turn back-and-forth with a single persistent subagent. In this harness (no SendMessage at the orchestrator level), this is approximated by re-spawning fresh subagents with re-briefing, accepting the friction. Used for: when one agent needs an extended conversation but other agents aren't involved.
   - **Team mode** — Agent Teams with multiple persistent teammates, peer-to-peer messaging, optional direct user-to-teammate cycling. Used for: multi-agent coordination on a single phase or step, especially when peer consultation between agents (PM ↔ Architect ↔ Security Reviewer) is needed.

2. **Phase-specific engagement model.**
   - **Phase 0:** not applicable (no agents).
   - **Phase 0.5:** task mode (smoke tests of individual agent files).
   - **Phase 1 Step 1–2** (completed under prior model): task mode + approximated meeting mode (orchestrator-mediated, fresh respawn each turn).
   - **Phase 1 Step 3 onward (PRD drafting through phase exit):** **team mode** with PM as workhorse, Architect and Security Reviewer spawn-on-need within the same team.
   - **Phase 2 (UX & Design):** team mode with UX Designer and Visual Designer as primary teammates.
   - **Phase 3 (Architecture):** team mode with Architect as workhorse, Security Reviewer mandatory.
   - **Phase 4 (Scoping):** task mode likely sufficient (PM decomposes; not multi-agent-coordination-heavy).
   - **Phase 5+ (Workshop / Build):** revisit at Phase 5 when build-time agents are defined.

3. **Team-mode operational conventions (smoke-test friction mitigations).**
   - **Agent-file preamble.** Every agent file used as a teammate gets a one-line opening clause at the top of its System prompt section: *"You may be running as a team member. If so, your communication primitive is SendMessage — load it via ToolSearch as your first action before responding to messages from the team lead. Plain-text output is invisible to other team members."* Applied to: product-manager, architect, security-reviewer, ux-designer, visual-designer. Not applied to chief-of-staff (CoS-as-main-session is always the lead, never a teammate).
   - **TaskList not relied upon.** Agent Teams docs reference TaskCreate / TaskUpdate / TaskList as the coordination layer; those tools don't surface in the Claude Desktop harness. Coordination falls back to SendMessage between teammates plus orchestrator-coordinated invocations. The `~/.claude/tasks/{team-name}/` directory may be used for ad-hoc shared files but not as a documented coordination primitive.
   - **Long-context model specified at spawn.** Teammates default to `claude-opus-4-7` (non-1M-context variant). For roles that need to read large composite contexts (PM reading full WORKFLOW + DECISIONS + accumulated PRD; Architect reading full ARCHITECTURE + migrations; Security Reviewer reading full PRD + ARCHITECTURE + source), explicitly specify the 1M-context variant when spawning.
   - **One team per active phase / step.** Team naming convention: `phase-<N>-<step-or-purpose>` (e.g., `phase-1-step-3-drafting`). Created at phase/step entry, torn down at phase/step exit via `TeamDelete` (or direct removal of `~/.claude/teams/{name}/` and `~/.claude/tasks/{name}/` if the calling session lacks team context, as observed during smoke-test cleanup). No cross-phase teams.
   - **Lead is always the orchestrator session (CoS-as-main-session).** The session that calls `TeamCreate` becomes the lead; lead is immutable per the docs. The Chief of Staff role lives in the main session per CLAUDE.md ("default to CoS behavior") and is never spawned as a teammate within its own team.
   - **Experimental flag prerequisite.** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set in `.claude/settings.local.json` (or shell env) at session start. The personal-override settings file is gitignored; not committed.

4. **Fallback to orchestrator-mediated pattern.** Team mode is experimental. If a session experiences team-mode breakage (TeamCreate fails, SendMessage errors, teammates fail to load), the orchestrator-mediated subagent pattern from Step 2 is the fallback — task mode for focused work, approximated meeting mode (fresh respawn with re-briefing) for multi-turn agent work. Fallback isn't a regression; it's the documented backup. Any breakage gets noted in the relevant phase's lessons-learned for future ADR revision.

**Consequences.**

- **Agent files get a preamble edit** applied to PM, Architect, Security Reviewer, UX Designer, Visual Designer. CoS file unchanged.
- **WORKFLOW.md's "Subagent invocation pattern" subsection** in Phase 1 needs a small revision noting that Step 3 onward uses team mode (versus the task-mode pattern used in Steps 1–2). Captured in the same transition commit as the agent-file preambles.
- **Smoke-test artifacts already cleaned up** prior to this ADR: `~/.claude/teams/smoketest-agent-teams/` and `~/.claude/tasks/smoketest-agent-teams/` removed.
- **Per-phase team naming** lets us trace team lifecycle to project phases — e.g., the team for Step 3 drafting will be `phase-1-step-3-drafting`, spawned at Step 3 entry, torn down at Step 3 exit.
- **Experimental-flag dependency** means Founder/CTO must have a Claude Code session running with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled to engage in team mode. The `.claude/settings.local.json` file in this worktree was created for this purpose; a parallel file at the main repo's `.claude/` would enable team mode for main-repo sessions too if F/CTO wants that.
- **A future `docs/agent-engagement.md`** could expand on team-spawn commands, model-selection patterns, troubleshooting. Drafted lazily as patterns emerge during Phase 1 Step 3 rather than upfront.
- **ADR-003 supersedes nothing**; complements ADR-001 (Phase 0.5 process resolutions) and ADR-002 (Phase 1 Step 2 ratification).

---

## ADR-002 — Phase 1 Step 2 ratification of preliminary product findings

**Date:** 2026-05-11 (ratification spanned 2026-05-09 through 2026-05-11)
**Status:** Accepted
**Phase:** 1

**Context.** Phase 1 Step 2 is the ratification pass over the six preliminary product findings captured in WORKFLOW.md → "Project framing → Preliminary product findings" — V1 surfaces, V2 candidates, permanent non-goals, stack, architectural constraints, operating cost expectations. Those findings were captured during Phase 0 as Phase 1 inputs, not as locked product decisions. WORKFLOW.md → Phase 1 → Detailed Steps mandates a focused PM-led ratification pass before PRD section drafting begins: each finding receives one of three verdicts (confirmed, revised, rejected), with revisions and rejections logged as ADRs before drafting. This ADR records the F/CTO-signed-off verdicts for all six findings, plus the accumulated sub-decisions that surfaced during the ratification.

The pass took longer than a single session due to scope expansion within Finding (a) — F/CTO's transaction-tracking scope override (section 1.3 below) triggered a cascade of bounded follow-up decisions and one substantial new V1 product-surface addition (manual non-Plaid accounts and manual transaction entry, section 1.5). The PM agent was invoked three times during this pass: once for the full ratification report, once for a focused income-categorization V1 check, and once for a scope-implication assessment after the transaction-tracking override.

**Terminology clarification adopted during the pass** (per F/CTO refinement, 2026-05-11): items previously labeled "permanent non-goals" are now labeled **"out-of-scope for this PRD lifecycle"** — they will not ship within the current PRD's scope; revisiting them requires an explicit PRD-scope revision. Distinct from **"V2+ deferred"**, which is already anticipated within this PRD as future scope expansion.

**Decisions.**

### Finding (a) — V1 surfaces: revised and substantially expanded

**1.0 — V1 surfaces (ratified, 2026-05-09 through 2026-05-11).** The V1 *initiative* comprises three core user-facing surfaces:

1. **Net worth over time**
2. **Asset allocation visualized against target** (market-value-based, with separate buckets per security type)
3. **Spending and income categorization with monthly per-category summations**

Powered by uniform transaction-level ingest from Plaid Transactions + Investments across depository, credit-card, investment, loan-balance, and crypto-exchange accounts, supplemented by manual non-Plaid accounts and manual transaction entry for holdings Plaid doesn't surface. Implementation boundaries captured in subsections 1.1 through 1.9.

**1.1 — V1 surface splits within Finding (a) (ratified, 2026-05-09).** The original Finding (a) packed two compound capabilities that required splitting:

- "Asset allocation vs. target with rebalancing suggestions" → **observational allocation visualization is V1**; **rebalancing suggestions are V2+** (recommendation engine logic, tax-lot-awareness, account-type awareness, brokerage workflow adjacency).
- "Categorized spending and budget tracking" → **spending and income categorization with monthly per-category summations is V1**; **budget tracking (goal-setting, targets, variance, alerts) is V2+**.

*Considered and rejected:* keeping both rebalancing suggestions and budget tracking in V1 — rejected on scope-discipline grounds; the recommendation engine and goal-setting UI surfaces are each large enough to warrant V2 treatment.

**1.2 — Category summation V1 non-goals (ratified, 2026-05-09).** The following adjacent features are explicit V1 non-goals on the category summations surface, to prevent re-litigation at PRD-drafting time:

- Budget targets per category (already V2+ per 1.1)
- Category-level trend charts
- Category drill-down to transaction list with edit
- Custom user-defined categories
- Recurring-transaction detection
- Category alerts / notifications
- Non-monthly default periods (weekly, quarterly, YTD) — V2+
- Custom user-defined periods — V2+

**1.3 — Transaction-tracking scope expansion (ratified, 2026-05-09; F/CTO override of PM's tight scope guardrail).** PM proposed a tight V1 income/transaction bound limiting V1 to depository-account transactions only. F/CTO overrode on the grounds that depository-only V1 has no viable use case even as a feature-limited product.

**Revised V1 transaction-tracking scope:** mosko-fintech V1 ingests and persists transaction-level activity from Plaid across both depository accounts (checking, savings) and investment accounts (taxable brokerage, IRA, 401(k), HSA where Plaid-supported), via the **Plaid Transactions** product (depository inflows/outflows, credit-card activity) and the **Plaid Investments** product (investment transactions: buy, sell, dividend, interest, transfer, fee, cash; and investment holdings for position-level state). Income recognition in V1 is the union of (a) depository inflows classified by Plaid's transaction categorization and (b) investment-transaction types `dividend` and `interest`. Tax-treatment differentiation is not a V1 calculation requirement, only a stored attribute (per 1.6).

**Transfer tagging** in V1: the system surfaces transactions Plaid flags as transfers (or that the system heuristically pairs across linked accounts) and exposes a per-transaction UI affordance for the user to confirm/override the transfer designation, so transfers are excluded from income and spending aggregations. Auto-detection is best-effort; the user-facing override is the contract.

Plaid Income product remains a V1 non-goal. Manual entry of historical or missing transaction data is available via 1.5 (manual transaction entry) but is not the primary V1 income source.

**1.4 — Multi-tenant V1 (ratified, 2026-05-10).** V1 ships with a multi-tenant data model (tenant_id on user-data tables, RLS policies enforced) and multi-tenant-capable auth infrastructure from day one. The V1 *usage model* is explicitly single-user — UI exercises one tenant, API testing assumes one user, friends-and-family onboarding is not a V1 milestone. **Forward-compatibility commitment:** adding the second user in V2+ requires no data migration of V1 user data.

*Reasoning:* data migrations on real financial data are unbounded-risk operations; the bounded cost of multi-tenant infrastructure from day one is preferable to that risk. *Considered and rejected:* single-tenant V1 with migration when the second user onboards (PM pushback) — rejected on one-way-door reasoning.

**1.5 — Manual-asset and manual-transaction support (ratified, 2026-05-11).** Manual capabilities are in scope for the V1 *initiative* (not V2):

- **Manually-tracked accounts** for non-Plaid assets — car, house, boat, RV, personal holdings, private equity, anything Plaid doesn't surface. Each manual account has a name, type, current value, and updateable value history. Counts toward net worth.
- **Manual transaction entry** on any account (Plaid-connected or manual). Covers: cost-basis overrides, historical backfill predating Plaid's ~24-month window, missed/edited transactions.
- **External valuation integrations** (Zillow, KBB, etc.) are explicit V2-or-later non-goals; V1 manual asset valuation is user-updated.
- **Milestone sequencing** (V1.0 vs V1.1 split) is Phase 4 work; natural split is V1.0 ships with manual *balances* + Plaid-sourced data, V1.1 adds full manual transaction-level entry. Real risk to monitor: V1.1 ending up far enough out that "shippable V1.0" becomes "the product the owner can't really use yet."

**1.6 — Tax-treatment three-way tagging (ratified, 2026-05-10).** Each account is tagged with one of three tax-treatment classifications — **taxable**, **tax-deferred**, **tax-free** — stored as an account-level attribute. V1 income surface includes all dividend/interest income across all account types, undifferentiated for V1 calculation purposes. Tag is available for future V2 surfaces (tax planning, spendable-income views, tax-character splits) without data backfill.

*Flagged for PRD drafting:* HSA's medical-withdrawal constraint may need a sub-flag or a fourth bucket ("tax-free conditional"). Not deciding now.

**1.7 — Cost basis and gain/loss handling (ratified, 2026-05-10 through 2026-05-11).**

**V1 includes:**
- Lot-level cost basis captured at buy time (each `buy` transaction = one lot with its implicit cost basis preserved)
- Aggregate cost basis per position computed from lot data
- Unrealized gain/loss per position (market value − aggregate cost basis)
- Realized gain/loss on sales — uses Plaid-provided `cost_basis` when populated; falls back to average-per-share cost basis with UX-level "estimated" indicator when not
- User cost-basis override mechanism (delivered via 1.5 manual transaction entry capability)

**V1 does NOT include:**
- Per-lot UI (no lot tables, no holding-period indicators)
- Tax-loss harvesting suggestions
- FIFO / LIFO / specific-ID lot-matching for tax purposes
- Wash-sale detection or basis-transfer adjustment

*Flagged for PRD drafting (UX language):* (a) "estimated cost basis" UX label on average-cost-fallback positions, with disclaimer ("Estimated — not for tax filing; consult your 1099-B"); (b) wash-sale caveat in any V1 tax-planning-adjacent surface.

This decision is a meaningful expansion vs. PM's "strict V2 deferral" recommendation. F/CTO's framing: cost basis on buy transactions is implicit (the buy cost itself) and should be logged; aggregate cost basis can be computed with relative ease; unrealized gains follow trivially.

**1.8 — Securities handling general principle (ratified, 2026-05-10).** V1 treats all Plaid-surfaced investment activity uniformly at the **transaction level** — buy, sell, dividend, interest, fee, transfer, cash, etc. — with **security type stored as a categorization attribute** (equity, ETF, mutual fund, derivative, bond/treasury, ADR, crypto, etc.). All positions valued at market value (Plaid's `institution_value`). Asset allocation surface treats different security types as different buckets.

The **underlying mechanics** of complex instruments are explicit V2+ candidates: greeks / intrinsic-value / notional exposure for derivatives; yield-to-maturity / coupon scheduling / duration / accrued interest for bonds; tax-character decomposition for REITs/MLPs; structured-product specifics. Architect feasibility check still needed to confirm Plaid Investments coverage across F/CTO's specific brokerages and instrument types.

This is the scalable framing F/CTO surfaced as a generalization of the options-handling discussion (1.9): treat all Plaid-surfaced security types uniformly at the transaction-and-position level, defer "underlying mechanics" to V2+.

**1.9 — Account-type and transaction-detail decisions (ratified, 2026-05-10 through 2026-05-11).** Per-account-type V1 boundaries:

- **Credit-card accounts:** ingested via Plaid Transactions for the spending surface. Plaid Liabilities product (APR, statement balance, minimum payment, payoff projections) is NOT in V1; deferred to V2+.
- **Loan accounts:** balances ingested via Plaid's standard accounts endpoint for the net-worth liabilities side. Plaid Liabilities product (principal/interest split, escrow, payoff projections) is NOT in V1; deferred to V2+.
- **Brokerage cash sweep / money-market positions:** treated as "cash" bucket in asset allocation; sweep interest counts toward income surface (consistent with the broader interest-income rule). User-configurable per-security allocation classification is V2+.
- **Reinvested dividends (DRIP):** V1 treats Plaid's paired `dividend` + `buy` transactions independently. Dividend counts toward income surface (matches tax reality — DRIP dividends are taxable income). The corresponding `buy` records as a normal investment purchase creating a new lot. No DRIP-pair detection logic in V1. "Income realized in cash" vs "income reinvested" display split is V2+.
- **Tax-deferred account income** (Traditional 401(k)/IRA dividends and interest): included in V1 income surface, undifferentiated by tax treatment in calculations (per 1.6).
- **Options / futures / derivatives:** included under the 1.8 general principle. Tracked at transaction level (buy/sell), valued at market (Plaid's `institution_value`), classified as a "derivatives" bucket in asset allocation. Greeks, intrinsic-value decomposition, complex lifecycle events (assignment mechanics, exercise→shares relationship tracking) are V2+.
- **Bonds and treasuries:** included under the 1.8 general principle. Coupons surface as `interest` transactions (already in V1 income scope per 1.3).
- **Crypto:** included under the 1.8 general principle, for Plaid-supported exchanges (Coinbase confirmed in F/CTO's accounts; others if Plaid adds them). Off-exchange wallet holdings, on-chain transactions, mining/staking-as-income mechanics are V2+.

### Finding (b) — V2 candidates: confirmed

**2.0 — V2 candidates (ratified, 2026-05-11).** The four explicit V2 candidates in Finding (b) are confirmed as stated:

- **Tax planning (estimated payments)**
- **Monte Carlo longevity modeling**
- **Lot-level tax features**
- **Stock screening** (with "possibly a separate tool" hedge preserved verbatim — documents that this V2 line is not a commitment to ship within mosko-fintech, only that it's not V1)

*Reasoning:* prefer a broad V2 candidate list now, whittle down based on V1 learnings rather than pre-judging.

**Consolidated V2+ deferred list (combining Finding (b) with accumulated sub-decision deferrals):**

- Tax planning (estimated payments)
- Monte Carlo longevity modeling
- Lot-level tax features (per 1.7: lot-level UI, FIFO/LIFO/specific-ID matching, wash-sale detection, tax-loss harvesting)
- Stock screening (possibly a separate tool)
- Rebalancing suggestions (per 1.1)
- Budget tracking with goal-setting (per 1.1)
- Non-monthly category periods (weekly/quarterly/YTD) and custom user-defined periods (per 1.2)
- Plaid Liabilities product detail (APR, statement balance, principal/interest split, payoff projections) (per 1.9)
- Plaid Income product (per 1.3)
- External valuation integrations (Zillow, KBB, etc.) (per 1.5)
- Per-security user-configurable allocation classification (per 1.9)
- Derivative underlying mechanics — greeks, intrinsic value, complex lifecycle events (per 1.8, 1.9)
- Bond underlying mechanics — YTM, duration, accrued interest, coupon scheduling (per 1.8)
- Tax-character decomposition for REITs / MLPs (per 1.8)
- Off-exchange crypto wallets, on-chain transactions, mining/staking-as-income mechanics (per 1.9)
- Multi-currency (per 3.0)
- "Income realized in cash" vs "income reinvested" display split for DRIP (per 1.9)
- HSA-specific "tax-free conditional" classification refinement (per 1.6)

### Finding (c) — Out-of-scope items for this PRD lifecycle: revised

**3.0 — Out-of-scope reframing (ratified, 2026-05-11).** Terminology clarification adopted: items previously labeled "permanent non-goals" are now labeled "out-of-scope for this PRD lifecycle." Substance unchanged; the relabel removes the false weight of "permanent" while preserving the discipline (revisiting these items requires an explicit PRD-scope revision, not a casual feature addition).

**Items confirmed as out-of-scope for this PRD lifecycle:**

- **Public sign-up** — fundamentally changes regulatory posture (KYC, fraud, identity verification) and product identity. mosko-fintech is invite-only.
- **Money movement** — initiating transfers, trades, or payments puts mosko-fintech into money-transmitter and/or brokerage territory with significant regulatory implications.
- **Advisor role / fiduciary relationship with users** — becoming a fiduciary requires RIA registration and fiduciary duty obligations.
- **Real-time price quotes** (live tick-level market data) — daily-snapshot data model is the product's data shape; live market data would meaningfully expand both product surface area and data-provider integrations. Technically achievable (F/CTO has existing live price sources) but not load-bearing for any V1 or V2 surface.
- **Mobile-native application** (separate iOS, Android, or React-Native-style app) — the V1 product is delivered as a web application. Mobile-responsive design (web app works correctly in mobile browsers) is expected V1 behavior; specific responsive commitments to be locked during Phase 2 (UX/Design).

**Item reclassified to V2+ deferred:** multi-currency. Multi-currency is not a permanent non-goal — the "in V1" qualifier in the original finding made it a deferral, not an identity statement. Mixing deferrals into the out-of-scope list weakens the discipline of both buckets.

### Finding (d) — Stack: routed out of PRD scope

**4.0 — Finding (d) routed out of PRD scope (ratified, 2026-05-11).** Finding (d)'s content (Supabase, Coolify, VPS, Plaid-as-aggregator, swap-able abstraction layer, frontend framework, background worker architecture) is routed out of PRD scope entirely. Stack is a Phase 3 (Architecture) input. Content migrates verbatim to WORKFLOW.md's Phase 3 inputs list. PRD may reference user-observable consequences of stack choices (e.g., "users access mosko-fintech via web browser") but does not lock the stack itself.

*Reasoning:* per the Product Manager agent's behavioral guideline — *"Never embed architectural decisions in the PRD."* Ratifying this finding for PRD inclusion would either embed architectural decisions in PRD content (violating role boundaries) or lock architectural decisions before the Architect has reviewed them (undermining Phase 3). The Architect agent ratifies this content in Phase 3.

### Finding (e) — Architectural constraints: routed out of PRD scope, with carve-outs

**5.0 — Finding (e) routed out of PRD scope, with carve-outs (ratified, 2026-05-11).** Items routed out of PRD entirely as Phase 3 / Phase 5 territory:

- **Boring monolith** — Phase 3 architectural pattern decision. Migrates to WORKFLOW.md's Phase 3 inputs list.
- **Secrets never in repo** — already authoritative in CLAUDE.md (root); no need to restate in PRD.
- **Migrations in code** — already authoritative in CLAUDE.md (root); no need to restate in PRD.

**Carve-out items previously ratified as PRD-locked product forward-compatibility commitments:**

- Multi-tenant schema from day one — captured in section 1.4 above.
- Lots captured in schema from day one (with lot-level UI deferred to V2+) — captured in section 1.7 above.

### Finding (f) — Operating cost: revised

**6.0 — Operating cost as a PRD-locked constraint (ratified, 2026-05-11).** mosko-fintech V1 is constrained to remain operable at hobby-tier cost — target ceiling **≤ ~$50/month total operating cost** for the V1 single-user-plus-Plaid-data-cost baseline. Specific cost breakdowns (Plaid product pricing, VPS, Coolify, etc.) are Phase 3 outputs in ARCHITECTURE.md, **not** PRD-locked numbers. If Architect cost analysis shows the ≤$50/month target is infeasible given V1's Plaid product mix (Transactions + Investments minimum), the constraint returns to F/CTO for revision before Phase 3 locks.

*Reasoning:* Finding (f)'s original dollar figures ($0/month Trial, $10–40/month family network) were scoped to a Transactions-only V1. The 1.3 transaction-tracking expansion adds Plaid Investments to V1, and Investments is separately metered from Transactions — likely changing the cost shape. The PRD-locked constraint is the cost *target*; the specific dollar bill is an architectural output.

### Missing PRD content gaps: deferred to Step 3

**7.0 — Missing PRD content gaps (deferred to Step 3, 2026-05-11).** Nine content gaps surfaced during ratification that the preliminary findings do not cover. Their resolution is part of PRD section drafting (Step 3), not Step 2 ratification:

1. Sharper target-user definition — user-story-grade specificity needed (persona, finance sophistication, current tools, what they value).
2. Success metrics — what "V1 success" measurably looks like.
3. Trust model and household-vs-individual data — friends-and-family use raises shared-account / household-rollup / strict-siloing questions. Partially constrained by 1.4 multi-tenant ratification.
4. Security and compliance posture scope — needs Security Reviewer pass before lock.
5. Data retention expectations — how long V1 keeps transaction history; delete-my-data control.
6. Offline / availability tolerance — uptime expectations and sync error handling rigor.
7. "V1 done" definition — bar for V1 build phase completion.
8. Accessibility / device support floor — mobile-responsive commitment level; accessibility commitments.
9. Plaid-specific user-facing implications — re-auth flow (Plaid Link expires; tokens need refresh) needs PRD treatment of the user-visible event.

### Routing flags for Step 3 (consolidated)

**8.0 — Architect and Security Reviewer routing flags surfaced during ratification (logged, 2026-05-11).** The following routing flags must be addressed during Step 3 (PRD drafting). Architect flags marked **(F/CTO-led)** indicate F/CTO will own the consultation directly rather than routing through PM.

**Architect routing flags:**

- (F/CTO-led) Plaid product mix and per-product pricing — Transactions, Investments, possibly Auth/Identity for verification (per 1.3, 6.0).
- (F/CTO-led) Sync cadence and webhook architecture for two Plaid products (Transactions + Investments) (per 1.3).
- (F/CTO-led) Holdings-vs-transactions reconciliation strategy and unified transaction-stream data model across depository / credit / investment / loan-balance / crypto account types (per 1.3, 1.8, 1.9).
- (F/CTO-led) Plaid Investments coverage for F/CTO's specific brokerages and instrument types — particularly Treasuries, individual bonds, options (per 1.8).
- Period-aggregation data model: precomputed monthly rollups vs. on-demand aggregation; timezone handling for month boundaries; how categorization recategorization invalidates summaries (per 1.0).
- Income data source boundary: schema must support 1.3's expansion without rewrite when V2 sources are added.
- Asset-allocation persistence model: target allocation storage shape (per 1.0).
- Spending-categorization data model: rule persistence, override persistence, possible merchant-name normalization (per 1.0).
- Multi-tenant infrastructure: RLS policy design that exercises (not bypasses) multi-tenant enforcement on the single-user V1 test path (per 1.4).
- Manual transaction / manual account data model: manual-vs-Plaid-sourced flag on transactions and accounts; conflict-resolution when Plaid contradicts a manual entry; audit trail for user-entered data (per 1.5).

**Security Reviewer routing flags (mandatory before the corresponding PRD sections lock):**

- V1 surfaces section: all three V1 surfaces consume Plaid data; mandatory Security Reviewer pass before lock (per 1.0).
- Multi-tenant carve-out: RLS / data-isolation posture is foundational; mandatory Security Reviewer pass (per 1.4).
- Security and compliance posture section: end-to-end ownership (per 7.0 item 4).
- Broader Plaid OAuth scope and credential surface introduced by Investments product (per 1.3).
- Broader stored-data surface: holdings, position values, tax-deferred account contents; PII implications of holdings data (specific tickers + quantities can identify trading patterns) (per 1.3, 1.9).
- Transfer-tagging UI: user-mutable transaction metadata requires RLS and audit-trail review (per 1.3).
- Manual transaction / manual account write path: user-entered financial data requires different validation/integrity than Plaid ingest (per 1.5).

**Consequences.**

- **V1 scope is materially expanded** vs. the original preliminary findings. The transaction-tracking scope expansion (1.3) and the manual-asset / manual-transaction surface (1.5) are the two largest expansions, both driven by F/CTO product judgment after PM's tighter-scope recommendations were considered and overridden.
- **V1 Plaid product surface** is now Transactions + Investments (minimum) — separately metered. Plaid Liabilities and Plaid Income remain out of V1. Finding (f)'s original Trial-tier $0/month assumption is no longer reliable; the constraint is the *target* (6.0), not the specific bill.
- **The V2+ deferred bucket** has grown to ~18 items beyond Finding (b)'s original four (consolidated list in 2.0).
- **Multiple Architect and Security Reviewer flags accumulated** for Step 3 PRD drafting (8.0); none block ratification but all must be addressed before the corresponding PRD sections lock.
- **Manual-asset / manual-transaction milestone sequencing** is deferred to Phase 4 — natural split is V1.0 ships with manual balances + Plaid-sourced data, V1.1 adds full manual transaction-level entry. Real risk to monitor: V1.1 ending up far enough out that "shippable V1.0" becomes "the product the owner can't really use yet."
- **Terminology refinement** (3.0): "out-of-scope for this PRD lifecycle" vs "V2+ deferred" — two distinct buckets adopted across the PRD.
- **Process refinements surfaced but not formalized in this ADR:** (i) subagent engagement patterns (task mode vs. meeting mode vs. roundtable mode) and (ii) one-question-at-a-time pacing for interactive decision passes. Both warrant a follow-up ADR-003 on subagent engagement, and possibly a `docs/agent-engagement.md` operational reference. Out of scope for ADR-002.
- **WORKFLOW.md updates required as part of phase-exit bookkeeping (Step 6):** preliminary findings subsection replaced with a pointer to PRD; Phase 3 inputs section receives the migrated stack and architectural-pattern items; Phase 1 status to update from "in progress" → "complete" at phase exit (after PRD lock, not now).

---

## ADR-001 — Phase 0.5 process resolutions: PR strategy, agent-file template, smoke-test format

**Date:** 2026-05-08
**Status:** Accepted
**Phase:** 0.5

**Context.** The Phase 0.5 plan flagged three open process choices to be confirmed before drafting the six Phase 1–4 agent files: how to package PRs, whether to lock the proposed agent-file template as-is, and whether to archive smoke-test transcripts. Founder/CTO resolution needed before drafting could begin.

**Decisions.**

1. **PR strategy: one bundled PR for all six agent files.** The roster is reviewed as a set, and landing it atomically matches how WORKFLOW.md frames Phase 0.5 as one phase output. Considered and rejected: one PR per drafting step (4 PRs) — adds review surface without atomicity benefit at this scale.
2. **Agent-file template: locked as proposed.** Header (Phase scope / Reports to / Engagement model / Owns), then sections for System prompt, Behavioral guidelines, Decision rules, Tool scope, Linear permission policy, Handoff & escalation triggers. All six files share this skeleton. Considered and rejected: shrinking before drafting — better to validate the template against concrete content and revisit via lessons-learned at phase exit.
3. **Smoke tests: run live in conversation; not archived.** The value is the live signal that the agent stays in role, not the transcript. Considered and rejected: persisting to `/notes/agent-smoke-tests.md` — premature documentation; if a future phase wants regression checks, build them deliberately.

**Consequences.**

- Phase 0.5 ships as a single PR from `phase/0.5-agent-roster` → `main`.
- Template changes mid-phase must propagate to all already-drafted files. Friction is intentional — discourages template churn once drafting begins.
- No persistent record of smoke tests. Future regression mechanisms must be built deliberately, not mined from chat transcripts.
