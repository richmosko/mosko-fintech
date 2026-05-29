# Phase 2 — UX Flow Document: §2.3 Spending & Income Categorization Cluster

**Cluster:** §2.3 — Spending and income categorization (cash-flow taxonomy + transaction-to-bucket assignment; cross-account multi-period rollup; per-account drill-down with as-of-date toggle; Historical Expenditures chart).
**Author:** UX Designer (`phase-2-ux-design` team).
**Status:** DRAFT — flows only. Pre-wireframe. Pre-PM-traceability-consult.
**Phase 2 step:** Step 2 (cluster 4 of 6, dependency order; depends on §2.4 accounts/transactions + the §2.3.1 cash-flow taxonomy).
**Date:** 2026-05-28.
**Companions:** §2.4 (transactions, entry, `stale-data-marker`, AcctSetup), §2.1 (CPI-U normalization basis), §2.2 (P5 planning-value surface sibling; per-symbol-vs-per-transaction assignment contrast). Global decision log: `temp/phase-2-decisions-log.md`.

---

## 0. Scope, inputs, and load-bearing constraints

### 0.1 PRD stories in this cluster
- **2.3.1** — Two-level cash-flow taxonomy (Cats: Income / Expenses / OtherCF / AcctSetup; Sub-Cats) + **per-transaction** bucket assignment (Plaid category as suggested default; recurring-vendor inference; user authoritative).
- **2.3.2** — Cross-account multi-period rollup: **Income** + **Expenses** sections, Sub-Cat rows × {Month / Q1 / Q2 / Q3 / Q4 / YTD}; authored income/expense **target reference values** shown inline in section captions (static — no variance); single Total row per section.
- **2.3.3** — Per-account cash-flow drill-down: select an account → **Income / OtherCF / Expenses** sections × the same period columns; **as-of-date toggle**; no planning targets here.
- **2.3.4** — Historical Expenditures chart: rolling **5-year** monthly expense bars + **12-month rolling-average** overlay, both **inflation-normalized to today's $** (same CPI-U basis as §2.1.2).
- **2.3.5** *(supporting)* — Cash-flow categorization is the user's; full-household by default. *(Constraint — no scope-filter UI in V1.)*

### 0.2 Load-bearing constraints
- **PERMANENT NON-GOAL: no budgeting / variance / alerts / limits (ADR-002 §1.2).** This is the strongest fence in the cluster — **not a V2 deferral, a permanent product-identity non-goal.** The authored income/expense targets are displayed as **static reference numbers** alongside actuals. **Do NOT design:** variance computation (actual−target deltas), over-budget warnings, threshold alerts, progress bars/scoring, spending limits, or any "you're over/under" affordance. §2.3 is **categorization + historical rollup, not budgeting.** The target is a number in a caption; that is the entire interaction.
- **Assign to the SEEDED cash-flow taxonomy only; no taxonomy CRUD in V1 (2.3.1).** User classifies transactions into **existing** seeded Cats/Sub-Cats (seeded from F/CTO's Master.CashFlowCategories). **No create/rename/delete Cat or Sub-Cat** in V1 (CRUD is V2+). No user-authored rules-engine beyond the recurring-vendor inference (V2+).
- **OtherCF + AcctSetup rendering rules (2.3.2 / 2.3.3 — exact, asymmetric).** The cross-account rollup (§2.3.2) renders **Income + Expenses ONLY.** **OtherCF does NOT render in the rollup** but **DOES render in the per-account drill-down (§2.3.3).** **AcctSetup renders in NEITHER** §2.3 surface (it's non-cash; lives in §2.4 territory). This asymmetry is intentional (parity with the existing per-account workbooks) — preserve it exactly.
- **Expenses-only history; no income-over-time (2.3.4).** Historical Expenditures charts **discretionary expenses only** (excludes tax cash flows). **No income time-series, no multi-year historical income chart (V2+)** — the asymmetry is intentional + parity-justified (income entangles with realization decisions). Differential retention per flag (i): expenses ≥5yr, income current-year-only.
- **Single full-household cash flow; no scope-filter UI (2.3.5 / §7.3).** One aggregated household view across all ownership scopes. **No scope toggle.** Own data only. Per-scope rendering is V2+.
- **Density-first (§1.3).** The archetype maintains deliberate cash-flow taxonomies and reasons at Sub-Cat × period granularity. Dense tabular precision is the point.
- **Non-silent staleness — D1 (global, settled).** Already ratified: every derived aggregation consuming stale-account data carries the `stale-data-marker`. **Applied to §2.3.2 rollup + §2.3.3 drill-down + §2.3.4 chart here without re-flagging** (per team-lead).

### 0.3 Appendix B §2.3 — Architect/Sec Phase-3 dependencies (NOT my surface; they constrain these flows)
- **(a)** Cash-flow taxonomy data model (seed-on-bootstrap from Master.CashFlowCategories; per-transaction assignment storage; shares table set with §2.2.1 — Architect dedupes).
- **(b)** Transaction-classification heuristic (Plaid category as suggested default + recurring-vendor inference; implementation shape — merchant-string lookup vs. classifier — Architect's).
- **(c)** Cross-account per-period aggregation query path (Sub-Cat × {Month,Q1–Q4,YTD} × Income/Expenses; OtherCF + AcctSetup excluded from this surface's output).
- **(d)** **V1 settings UI plumbing for planning-target values — Architect / Sec joint.** "First concrete V1 surface needing a user-editable settings store." Sec re-engagement on **write-path validation + audit trail + tenant-scoping** (Task #23 #3). → ARCH handoff H1 (§8A); the **P5** target-edit surface.
- **(e)** Planning-targets storage shape (simple V1: one income-target value [annual-typed] + one expense-target value [monthly-typed]; no Sub-Cat breakdown).
- **(f)** **As-of-date as system-wide query-time parameter — Architect / Sec joint.** Exposed as the §2.3.3 toggle but plausibly a query-path abstraction threading all dated paths (incl. §2.6). **Sec Phase-3 RLS test obligation** (Task #23 #1 — tenant_id enforcement independent of the date filter; no parameter-manipulation bypass). → ARCH handoff H2 (§8A); the as-of pin (§1).
- **(g)** Per-account scoping query path (single-account filter; 3 sections; shares backbone with (c)).
- **(h)** Drill-down view capability (general vs. hardcoded) — parallel to §2.2.3.
- **(i)** **Differential data retention** — expenses ≥5yr (for the chart), income current-year-only. UX consequence: the 5-yr chart has data; income-over-time is structurally absent in V1.
- **(j)** CPI-U sourcing — cross-ref §2.1 flag (d); §2.3.4 is the 4th surface consuming the same series. No new flag.
- **(k)** RESOLVED — Sec §2.3.5 isolation + scope-attribute pass + **as-of-date toggle axis** (Task #23, product-level pass; the Phase-3 RLS obligation rides flag (f)).

No open *product* (PM) decisions remain from Phase 1. Items below are flow-level + the WORKFLOW-named info-hierarchy decision + the parked P5.

---

## 1. As-of-date pin (Lock 15) + cross-cluster consistency — load-bearing

> Parallel to §2.1's value-semantics pin and §2.2's consistency pin. §2.3.3 is **the** legitimate free as-of-toggle surface in V1 (the §2.4 Sec note flagged §2.3.3 + §2.6 as the only client-toggle as-of surfaces); its behavior must be pinned precisely because it's a user-supplied query-time parameter on a multi-tenant data path.

### 1.1 The §2.3.3 as-of-date toggle (the one free as-of surface)
- **Default = today** (current state). The user toggles to a chosen **historical as-of-date** to view that account's cash flow **as it stood on that date** — the documented use case is **year-end reconciliation** in the existing workflow.
- **Semantics = Lock 15 dual-column read** (`transaction_date ≤ as_of` AND `created_at ≤ as_of`): the view shows the state **as it was known on that date** — retroactive edits/inserts made *after* the as-of date are excluded, and Lock 5 reverse-and-replace chains resolve by construction (a correction entered later doesn't appear in a past as-of view). This is a *historical reconstruction*, not a re-render of current data filtered by event-date alone.
- **Validation (Lock 15 mod #2):** `2015-12-01 ≤ as_of_date ≤ CURRENT_DATE`. **No future dates** (no V1 use case); floor is the NAV-history anchor. Invalid/out-of-range input → app-layer DATE validation error (Lock 15 battery).
- **UX honesty:** when an as-of date other than today is active, the view **clearly labels "as of <date>"** so a historical reconstruction is never mistaken for current state. Returning to today is one action.
- **Security (ARCH handoff H2):** tenant isolation is enforced **independently of the date filter** — the as-of parameter must not become a cross-tenant bypass vector (Sec Task #23 RLS obligation). UX surfaces a date picker; the isolation guarantee is Architect/Sec Phase-3.
- **Scope:** the as-of toggle lives **only** on §2.3.3 (per-account drill-down) in this cluster. §2.3.2 rollup + §2.3.4 chart are **current-state** (no free as-of toggle); §2.6 is the other as-of surface (its own cluster). §2.1 has **no** free as-of toggle (fixed reference dates only).

### 1.2 Cross-cluster consistency
- **Same transactions as §2.4.3.** The rollup, drill-down, and chart read the **same transaction ledger** the §2.4.3 entry/edit/reconcile flows write. Per-transaction Sub-Cat (2.3.1) is the cash-flow analog of §2.2.1's per-symbol assignment — but **per-event, not per-instrument** (each transaction carries its own bucket).
- **OtherCF/AcctSetup discipline** (see §0.2) is the consistency rule between §2.3.2 (Income+Expenses) and §2.3.3 (Income+OtherCF+Expenses) and §2.4 (AcctSetup).
- **CPI-U basis (flag (j)).** §2.3.4's inflation normalization uses the **same CPI-U series and "today's $" basis as §2.1.2** — the two inflation-adjusted surfaces must normalize identically (no divergent basis).
- **Transaction list ≠ cash-flow surface.** The raw transaction list lives on `Account Detail` (§2.4); the §2.3 surfaces are **aggregations** of that ledger, not the ledger itself. (Relevant to the info-hierarchy decision, §8.)

---

## 2. Cash Flow surface — region inventory

The cluster lives in a **Cash Flow** destination (top-level surface; nav model deferred to Step 3).

| Region | Story | Content |
|---|---|---|
| `cashflow-rollup` | 2.3.2 | Cross-account: Income + Expenses sections, Sub-Cat rows × {Month / Q1 / Q2 / Q3 / Q4 / YTD}; Month emphasized; Total row per section; target reference values inline in section captions (static). |
| `cashflow-account-drilldown` | 2.3.3 | Per-account: Income / OtherCF / Expenses sections × same columns; as-of-date toggle; no targets. |
| `historical-expenditures-chart` | 2.3.4 | 5-yr monthly expense bars + 12-mo rolling-average line; inflation-normalized. |
| `cashflow-target-edit` | 2.3.2 / flag(d) | The income/expense target-editing surface (PRD says "V1 settings UI"; the *affordance shape* is the P5 cross-cluster decision — §8). |

**Info-hierarchy note:** unlike §2.2, §2.3 **does** carry a WORKFLOW-Step-3-named information-hierarchy decision (the "spending surface" primary presentation) — see **Open Decision 1 (§8)**. The region *content* is PRD-prescribed (the multi-period tables); what's open is which presentation anchors the surface.

---

## 3. FLOW F-2.3.A — Classify / reclassify a transaction
**Traces:** 2.3.1. **Entry:** (i) at manual transaction entry (§2.4.3 — the Sub-Cat field IS this assignment); (ii) per-row reclassify on a transaction in `Account Detail`'s `transaction-list` or in the drill-down.

### Screen list
| Screen | Type | Role |
|---|---|---|
| `Transaction Entry` | panel/modal (reused from §2.4.3) | Sub-Cat assigned at entry (manual transactions). |
| `Reclassify Transaction` | inline/panel | Set/change a transaction's Sub-Cat after the fact (Plaid or manual). |

### Steps
1. **Default classification.** Plaid-pulled transactions arrive with **Plaid's category as a suggested default**; **recurring-vendor inference** suggests the Sub-Cat last assigned to the same merchant. *The user's two-level taxonomy is authoritative — suggestions are never binding.*
2. **Assign / override.** User picks a Sub-Cat from the **seeded** pick-list (Income / Expenses / OtherCF Sub-Cats; AcctSetup is set via the §2.4.3 AcctSetup path, not here). No "+ new Sub-Cat" (CRUD is V2+).
   - *System:* writes the per-transaction Sub-Cat; rollup/drill-down/chart recompute.
   - **Decision point — source:** Plaid transaction → suggested default pre-filled, user overrides per-transaction · manual transaction → Sub-Cat set at entry (§2.4.3), editable later.
3. **Reclassify** any transaction later (portfolio/category evolves) via `Reclassify Transaction`.

### Key asymmetry vs. §2.2 symbols (no classification queue)
- Unlike §2.2.1 symbols (which arrive **`Unsorted`** and drive a notification queue), Plaid **transactions arrive WITH a suggested category** — so there is **no forced-uncategorized state** and **no transaction-classification notification queue** in V1. Classification is a per-row, in-context affordance + entry-time assignment. *(If a transaction's Plaid category doesn't map to a seeded Sub-Cat, see Flag PM-2.)*

### Error / edge states
- **Unmappable Plaid category** (Plaid category has no seeded Sub-Cat equivalent) → **Flag PM-2** (fallback Sub-Cat? a seeded "Uncategorized"/catch-all? or user must pick at review?). Not designed in.
- **Deferred classification** → transaction retains its suggested default until the user overrides; never blocks aggregation (the suggested bucket is always *some* bucket).

### Out of scope — V1/V2 per 2.3.1
Taxonomy CRUD (V2+). User-authored rules-engine / regex auto-categorization beyond recurring-vendor inference (V2+). Per-account taxonomy overrides (V2+).

---

## 4. FLOW F-2.3.B — Review cross-account cash flow (rollup)
**Traces:** 2.3.2. **Entry:** app nav → `Cash Flow` → `cashflow-rollup`.

### Steps
1. **View the rollup.** `cashflow-rollup` renders **two sections — Income and Expenses** — each a table of **Sub-Cat rows** (flat; no Cat-group header rows — the two-section layout expresses the Cat structure) across six period columns: **Month** (current, visually emphasized), **Q1, Q2, Q3, Q4, YTD**. Each section foots in a single **Total** row. Single full-household aggregation (2.3.5); no scope chrome. **OtherCF + AcctSetup do NOT appear here** (§0.2).
2. **Read targets inline (static — NON-GOAL fence).** Each section caption shows the user's authored **target reference value** — **income target as an annual figure, expense target as a monthly figure** — displayed alongside the section's actual totals. **This is a static reference only:** no variance, no delta, no alert, no over/under indicator (ADR-002 §1.2 permanent non-goal).
3. **Drill to an account.** Selecting/choosing an account opens `cashflow-account-drilldown` (F-2.3.C).

### Sub-flow — Edit the planning targets (the 2nd P5 planning-value surface)
- The PRD names a **"V1 settings UI"** for the income/expense target reference values ("the settings UI is part of this story's surface"). Storage is simple (flag (e): one annual income value + one monthly expense value).
- **P5 (parked for Step 3, cross-cluster):** the target-edit *affordance shape* is decided **coherently** across the three planning-value surfaces (§2.2 allocation targets + this §2.3.2 income/expense targets + §2.5.2 tax brackets). **Note the cross-cluster signal:** §2.3.2 and §2.5.2 PRD text both specify a **settings UI**, while §2.2 was silent (I'd leaned inline-cell) — so settings-UI is the stronger coherent-P5 signal; my §2.2 inline-cell lean should be reconciled against it at Step 3 (see §8 + the §2.2 doc). **Not deciding here.**
- *System (on edit):* persists the target (flag (e) storage; write-path validation per ARCH handoff H1, §8A); the caption reference value updates. **No downstream variance computation** (non-goal).

### Error / edge states
- **Stale / re-auth account contribution** (D1) → `stale-data-marker` on affected Sub-Cat rows + section Totals; never silently fresh.
- **Target unset** → caption shows "no target set" (or omits the reference) — never a 0-target that could read as "budget = 0." No alerting either way (non-goal).
- **Empty Sub-Cat / period** → renders 0/blank per the existing-system convention; no special state.

### Out of scope — V1/V2 per 2.3.2
Variance / alerts / budget-tracking — **permanent non-goal** (not V2 — never). Per-scope rendering (V2+). OtherCF section in the rollup (intentionally absent). Rule-based auto-categorization beyond recurring-vendor inference (V2+).

---

## 5. FLOW F-2.3.C — Drill into a single account's cash flow
**Traces:** 2.3.3. **Entry:** `cashflow-rollup` → select account → `cashflow-account-drilldown`.

### Steps
1. **Select the account**, then view its cash flow in isolation as **three sections — Income, OtherCF, Expenses (in that order)** — each a Sub-Cat-row table using the same columns as §2.3.2 (**Category | Month | Q1 | Q2 | Q3 | Q4 | YTD**, Month emphasized), each footing a Total row. **OtherCF renders here** (the intentional asymmetry vs. §2.3.2). **AcctSetup does NOT render.** **No planning targets here** (targets are aggregate, attached to §2.3.2 only).
2. **Toggle as-of-date** (the §1.1 pin). Default = today; the user picks a historical as-of-date for year-end reconciliation; the view reconstructs the account's cash flow **as it was known on that date** (Lock 15 dual-column) and clearly labels "as of <date>."
   - **Decision point — as-of:** today (default) ↔ chosen historical date (within `2015-12-01 … today`).
3. **Return** to `cashflow-rollup`.

### Error / edge states
- **As-of before data start** (pre-2015-12 / pre-account-history) → empty/"insufficient history for this date"; not fabricated.
- **As-of in the future / invalid date** → blocked by validation (Lock 15: no future dates; DATE battery).
- **Stale / re-auth account** (D1) → `stale-data-marker` on the drill-down (note: an as-of *historical* view of a now-stale account shows the historical reconstruction; the staleness marker applies to the *current-state* default view).
- **OtherCF/AcctSetup discipline** preserved exactly (§0.2) — a misrender here would break parity.

### Out of scope — V1/V2 per 2.3.3
Per-scope drill-down (V2+). Per-account taxonomy overrides (V2+). Planning targets in this view (intentionally absent). Variance/alerts (permanent non-goal).

---

## 6. FLOW F-2.3.D — Review historical expenditures
**Traces:** 2.3.4. **Entry:** the `historical-expenditures-chart` region on the Cash Flow surface.

### Steps
1. **View the chart.** `historical-expenditures-chart` renders a **rolling 5-year window of monthly expense bars** (the §2.3.2 Expenses scope — **excludes tax cash flows**) with a **12-month rolling-average overlay line drawn simultaneously**, so per-month magnitude and the smoothed trend read in one view. **Both bars and line are inflation-normalized to today's $** (same CPI-U basis as §2.1.2). 5-year horizon fixed.

### Error / edge states
- **Insufficient history** (<5yr of expense data; differential retention flag (i)) → chart truncates to the available range with a boundary note; the rolling-average line begins where ≥12 months exist.
- **CPI-U unavailable** (flag (j) / §2.1 flag (d)) → inflation normalization can't run; show the **nominal** series with an explicit "inflation-adjusted view unavailable" note (parallels §2.1.2). Never fabricate normalized values.
- **Stale / re-auth account contribution** in recent months (D1) → the affected recent bars carry the `stale-data-marker`.

### Out of scope — V1/V2 per 2.3.4
**No income time-series / multi-year historical income chart (V2+)** — expenses-only by design. Chart drill-down into specific months/Sub-Cats (V2+). Authored target reference line on the chart (V2+). User-configurable horizons (V2+).

---

## 7. Cross-cutting error / edge state matrix (V1 failure surfaces for §2.3)
| Edge / error | Where | Behavior |
|---|---|---|
| **Stale / pending-re-auth account** (D1 — settled) | rollup rows+Totals, drill-down, recent chart bars | `stale-data-marker`; never silently fresh. No re-flagging. |
| **Unmappable Plaid category** | `Reclassify Transaction` | Fallback behavior is **Flag PM-2** (catch-all seeded bucket vs. user-must-pick). |
| **Target unset** | `cashflow-rollup` caption | "no target set" / omit; never a 0 that reads as a budget. No alerting (non-goal). |
| **As-of before data start** | `cashflow-account-drilldown` | "insufficient history for this date"; not fabricated. |
| **As-of future / invalid** | `cashflow-account-drilldown` | Blocked by Lock 15 validation (no future dates; DATE battery). |
| **Insufficient chart history** (<5yr; flag (i)) | `historical-expenditures-chart` | Truncate to available range; rolling line starts at ≥12 mo. |
| **CPI-U unavailable** | `historical-expenditures-chart` | Show nominal + explicit note; never fabricate normalized values. |
| **Budget/variance "missing"** | — | **Not an error — a permanent non-goal.** No variance/alert/limit affordance exists by design (ADR-002 §1.2). |

---

## 7A. VISUAL HANDOFF — the non-goal fence is a component-spec instruction (LOAD-BEARING)
The ADR-002 §1.2 permanent non-goal (no budgeting / variance / alerts) must **survive the Visual pass**, not just the flow pass. "Target beside actual" is exactly the layout where a designer is tempted to add a comparative visual — so the prohibition is made explicit here to carry into the Visual handoff and the component spec:
- **`target-caption` (rollup, F-2.3.B):** the income/expense target renders as a **plain static reference number** beside the actual total. **NO comparative treatment** — no progress bar, no gauge/dial, no fill-line, no over/under **red/green color-coding**, no up/down arrow, no "% of target" badge, no conditional formatting keyed to actual-vs-target. It is styled like any other reference number.
- **`historical-expenditures-chart` (F-2.3.D):** **NO target reference line** on the chart (a V2+ item per 2.3.4 regardless — called out so it isn't added as "polish").
- **Scope:** this prohibition is a hard constraint on the Visual Designer's component spec for these two surfaces, not a stylistic preference. Flag back to UX if a layout seems to *need* a comparative element — do not add one.

---

## 8. Open decisions to surface to F/CTO (NOT decided unilaterally)

### Open Decision 1 — Spending-surface information hierarchy: category×period table vs. transaction-stream vs. calendar *(WORKFLOW-Step-3-named; ADR-bound)*
WORKFLOW Step 3 names the "spending surface" info-hierarchy decision (calendar vs. category-tree vs. transaction-stream as the primary). The PRD §2.3.2/§2.3.3 prescribe **category×period tables**, which largely resolves this toward the table form — but the decision is named, so I surface it for an explicit Step-3 call:
- **Option A — Category×period table primary (PRD-faithful; RECOMMENDED).** The §2.3.2 rollup (Sub-Cat × {Month,Q1–Q4,YTD}) anchors the Cash Flow surface; drill-down + Historical Expenditures are secondary. *Pro:* exactly what the PRD prescribes; matches the categorization-grammar archetype (§1.3); the existing-system parity surface. *Con:* none material — it's the PRD reading.
- **Option B — Transaction-stream primary.** A chronological transaction list anchors the surface; the category×period rollup is a summary. *Pro:* "where did the money go" chronologically. *Con:* the PRD does NOT describe a stream as primary; the raw transaction list already lives on `Account Detail` (§2.4); de-emphasizes the categorization grammar the archetype thinks in.
- **Option C — Calendar primary.** A spending calendar/heatmap. *Pro:* day-level intuition. *Con:* not PRD-described; poor fit for a Sub-Cat-precise archetype; no period-column structure the PRD requires.
- **Recommendation: Option A.** The PRD has effectively superseded the calendar/stream alternatives by prescribing the category×period tables; confirming A at Step 3 closes the WORKFLOW-named decision. Parked for the Step 3 walk-through alongside the §2.1 net-worth-hierarchy + nav-model decisions (one coherent pass). *(ADR captured at Step 3.)*

### Open Decision 2 — P5 (planning-value editing affordance) — §2.3.2 is the 2nd surface
The income/expense target-edit affordance shape (settings-panel vs. inline) is the **cross-cluster P5** decision (parked for Step 3 with §2.2 + §2.5.2). **Cross-cluster signal recorded:** §2.3.2 + §2.5.2 PRD text both specify a **settings UI**; §2.2 was silent (inline-cell lean). Settings-UI is therefore the stronger coherent-P5 candidate. **Not deciding here** — surfaced so Step 3 has the full signal.

---

## 8A. Phase 3 ARCH handoffs (from §2.3 PM consult)
Captured for cross-team routing when Phase 3 spins up (per ADR-012). Backend/architecture/security concerns, NOT UX surfaces.

- **H1 — Planning-target write-path (flag (d); Architect / Sec joint).** §2.3.2's target settings store is "the first concrete V1 user-editable settings store." Sec re-engagement on **write-path validation + audit trail + tenant-scoping** (Task #23 #3). Storage simple per flag (e) (annual income + monthly expense scalars). Composes with §2.2's H1 (allocation targets) + §2.5.2 (brackets) as the planning-value settings family.
- **H2 — As-of-date parameter tenant-isolation (flag (f); Architect / Sec joint).** The §2.3.3 as-of toggle is a user-supplied query-time parameter on a multi-tenant path. **Sec Phase-3 RLS test obligation:** tenant_id enforcement must be **independent of the date filter** — no parameter-manipulation cross-tenant bypass (Task #23 #1; RT-25). Lock 15 app-layer DATE battery (`2015-12-01 ≤ as_of ≤ today`, no future, strict regex) is the input fence. **Product-level already passed by Sec at Task #23** — this is the Phase-3 implementation obligation, not a fresh product question (see §9 note to team-lead).
- **H3 — Cash-flow seed catch-all "Uncategorized" Sub-Cat (PM recommendation → ADR-004 / Architect bootstrap).** PM recommends the seeded cash-flow taxonomy include a catch-all `Uncategorized` Sub-Cat so unmappable Plaid transactions land in a **visible** bucket (parallel to §2.2's `Unsorted`) — this is what makes the "no review queue" decision (PM-1) robust. Seed-content, not a Phase-2 UX surface; routed here so it isn't lost. The UX renders whatever catch-all the seed provides.
- *(Taxonomy data model (a) + classification heuristic (b) + retention (i) are Architect-only; noted in §0.3.)*

---

## 9. Scope-creep / ambiguity flags for PM *(route to PM, not designed around)*

### Flag PM-1 — Is there a "needs-review / uncategorized transactions" surface in V1? — ✅ **RESOLVED (F/CTO): NO review queue**
**Resolution (F/CTO):** **No review queue.** Per-row reclassify + entry-time assignment is the complete V1 surface; **the §2.3.2 category×period rollup IS the monthly review surface** (F/CTO reviews categorizations there, not in a dedicated queue). Closed — no pending nod; **do not carry into sitting 2 or the decision pass.**
- *Original asymmetry (retained):* unlike §2.2.1 symbols (which arrive `Unsorted` → queue), transactions arrive *with* a Plaid-suggested category, so there's no forced-uncategorized state — which is why "no queue" is the answer. PM-2's recommended catch-all (below) is what makes "no queue" robust.

### Flag PM-2 — Fallback when a Plaid category doesn't map to a seeded Sub-Cat. — **PM RECOMMENDS a seeded catch-all (→ ADR-004/Architect bootstrap)**
Parallel to §2.2's PM-2 but for cash flow. **PM actively recommends the cash-flow seed taxonomy INCLUDE a catch-all "Uncategorized" Sub-Cat** — unmappable Plaid transactions land in a **visible catch-all** (parallel to §2.2's `Unsorted` row), which is precisely what makes PM-1's "no queue" robust (nothing vanishes; the user sees what needs attention in-context).
- *Routed (not my surface):* the catch-all is **seed-content** — an **ADR-004 / Architect Phase-3 bootstrap** decision, captured in §8A handoffs. The UX surface simply renders whatever catch-all the seed provides as a visible bucket; no CRUD escape (taxonomy CRUD is V2+).

### Flag PM-3 — Confirm the NON-GOAL fence holds at the target-caption surface. *(confirmation — high-importance)*
The income/expense targets are displayed statically beside actuals. Confirm there is **no** expectation of *any* variance/delta/alert/progress affordance (ADR-002 §1.2 permanent non-goal). I have designed **zero** budgeting affordances; flagging explicitly because a "target beside actual" layout is exactly where budget-tracking tends to creep in.

### Note to team-lead — as-of-date is Sec-touched but already product-passed *(not a fresh Sec spawn, surfaced per your guidance)*
The §2.3.3 as-of-date toggle is the one security-load-bearing item in this cluster (user-supplied query-time parameter on multi-tenant data). **Sec already gave it a product-level pass at Task #23**, attaching a Phase-3 RLS test obligation (H2). So per your "flag if security-load-bearing surfaces" steer: it's flagged, but it's **already Sec-blessed at product level** — my read is **no fresh Sec spawn needed** for §2.3 (the obligation is a Phase-3 implementation test, not an open product question). Your call if you want a Sec re-touch on the *UX shape* of the toggle.

---

## 10. Provisional screen / surface inventory (for the eventual Visual handoff — NOT final until Step 3 lock)
| # | Surface / region | Type | Flow | Traces |
|---|---|---|---|---|
| 1 | `Cash Flow` | full screen (surface) | container | 2.3.* |
| 2 | `cashflow-rollup` | region (two-section period table) | F-2.3.B | 2.3.2 |
| 3 | `cashflow-account-drilldown` | region (three-section period table + as-of toggle) | F-2.3.C | 2.3.3 |
| 4 | `historical-expenditures-chart` | region (bars + rolling line) | F-2.3.D | 2.3.4 |
| 5 | `cashflow-target-edit` | settings surface OR inline (P5) | F-2.3.B | 2.3.2 |
| 6 | `Reclassify Transaction` | inline/panel | F-2.3.A | 2.3.1 |
| 7 | `Transaction Entry` | panel/modal (reused from §2.4.3) | F-2.3.A | 2.3.1 / 2.4.3 |
| 8 | as-of-date toggle (`asof-date-picker`) | interaction control | F-2.3.C | 2.3.3 |

Cross-cutting components: `stale-data-marker` (consumed, D1), `asof-date-picker` + "as of <date>" state-label, period-column-table-row, section-Total-row, target-caption (static, non-alerting), inflation-normalized chart treatment (shared basis w/ §2.1.2), seeded-Sub-Cat pick-list (no-CRUD). Cross-links: `Reclassify Transaction` / `Transaction Entry` ← §2.4.3 ledger; `cashflow-rollup` → `cashflow-account-drilldown`; raw transactions live on `Account Detail` (§2.4), not here.

---

## 11. PRD §2.3 story → flow traceability (for the PM consult)
| PRD story | Covered by | Notes |
|---|---|---|
| 2.3.1 Cash-flow taxonomy + per-transaction assignment | F-2.3.A | Seeded buckets only; Plaid-default + recurring-vendor inference (suggestions); per-transaction (vs §2.2 per-symbol). |
| 2.3.2 Cross-account multi-period rollup | F-2.3.B (`cashflow-rollup`) | Income+Expenses ×6 periods; static target captions (non-goal fence); OtherCF/AcctSetup excluded; target edit = P5. |
| 2.3.3 Per-account drill-down + as-of toggle | F-2.3.C (`cashflow-account-drilldown`) | Income/OtherCF/Expenses ×6 periods; Lock 15 as-of toggle (§1.1); no targets. |
| 2.3.4 Historical Expenditures | F-2.3.D (`historical-expenditures-chart`) | 5-yr expense bars + 12-mo rolling avg; inflation-normalized; expenses-only. |
| 2.3.5 Cash flow is the user's (full-household) | §0.2 constraint (all flows) | Single aggregated household; no scope UI; own data only. Not a screen. |

**No flow exceeds its PRD story.** V1/V2 + permanent-non-goal boundaries respected (no budgeting/variance/alerts ever; no taxonomy CRUD; no rules-engine; no income-time-series; OtherCF/AcctSetup discipline exact; no scope UI). D1 applied without re-litigation. PM items isolated as Flags PM-1/2/3; info-hierarchy + P5 surfaced for Step 3, not designed in.

---

## 12. Status / next
- **✅ §2.3 LOCKED (2026-05-28):** PM traceability PASS; D1 applied; all flags closed. **PM-1 RESOLVED by F/CTO — NO review queue** (the §2.3.2 rollup is the monthly review surface); no pending nod remains. Fold-ins landed: §7A Visual non-goal-fence prohibition (component-spec); PM-2 → §8A H3 catch-all "Uncategorized" seed recommendation; PM-1/PM-3 status updated.
- **Draft coverage:** flow structure complete; as-of-date pin (§1.1, Lock 15) + cross-cluster consistency (§1.2); all V1 failure surfaces in §7; **permanent NON-GOAL fence enforced through flows AND the Visual handoff (§7A)**.
- **Carried to Step 3 walk-through:** Open Decision 1 — spending-surface info-hierarchy (rec. Option A, PRD-faithful). P5 — §2.3.2 targets (2nd planning-value surface; settings-UI signal recorded; affordance parked).
- **Flags status:** PM-1 ◑ PM-closed-no-queue (F/CTO nod pending, non-blocking); PM-2 → PM-recommends-catch-all (§8A H3); PM-3 → non-goal fence (confirmed; carried to Visual via §7A).
- **ARCH handoffs (§8A):** H1 (planning-target write-path, Architect/Sec joint) + H2 (as-of-date tenant-isolation RLS, Architect/Sec joint) + H3 (catch-all seed-content → ADR-004/Architect bootstrap).
- **Next:** §2.5 estimated taxes (cluster 5 of 6) → §2.6 monthly report → Step 3 walk-through → wireframing (Step 4).
- **No wireframing** until the Step 3 gate confirms the flow set.
