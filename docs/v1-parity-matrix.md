# V1 Parity Matrix — mosko-fintech

**Status:** Draft — Phase 1 / Step 3 (script-audit findings)
**Last updated:** 2026-05-13
**Owner:** Chief of Staff (audit lead); Product Manager (translator into `PRD.md`); Founder/CTO (decider)

## Purpose

This document is the consolidated output of the **script-audit pivot** taken mid-Phase 1 / Step 3. Phase 1's original drafting model (preliminary findings → PRD generative drafting) drifted toward inventing V1 requirements abstractly when the Founder/CTO had concrete answers already implemented in an existing manual-spreadsheet system. The pivot re-anchors V1 on **functional parity with the existing system**, with V2 reserved for genuine expansion.

The matrix maps every observed capability from the existing system to one of four statuses:

- **V1 preserve** — capability is in V1 PRD scope as a hard requirement.
- **V1 new-decision** — F/CTO needs to make a product call before the capability locks (e.g., simpler-than-existing vs. parity-with-existing).
- **V2 defer** — capability is real but explicitly deferred; data model must remain forward-compatible.
- **Drop** — capability is in the existing system but F/CTO has explicitly removed it from scope.

Audit source artifacts:

1. **MoskoFinance** — Google Apps Script (`moskoFinance.gs`); `calculateHoldings` and `calculateSales` custom functions.
2. **Master** Google Sheet — reference data layer (5 load-bearing sheets + 1 archived + 1 reconciliation TMP).
3. **Fidelity Brokerage (Rich)** — representative per-account workbook (5 displayed sheets + 6 soft-link reference sheets).
4. **Asset Summary** — central cross-account aggregator (10 in-scope sheets + 3 ignored + soft-links).
5. **Finance_Report** — Google Doc; the canonical V1 output deliverable (monthly trust-labeled, full-household-scoped report).

## Reading order

1. The **Architectural layers** section (below) gives the system's three-layer shape — reference data, per-account workbooks, central aggregator — plus the output (monthly report). The PRD's data-model and feature-scope decisions trace to this.
2. The **Capability matrix** is the line-by-line list. Use it to verify nothing was lost in translation between existing-system and V1 PRD.
3. The **ADR-002 verdict status** table summarizes which Phase 1 Step 2 verdicts hold, which need amendment, and which need new ADR entries.
4. The **Capabilities new to PRD** section enumerates V1 surfaces that weren't anticipated by the preliminary findings at all.
5. The **PRD §2 mapping** section shows where each capability lands in the PRD section structure.
6. The **Open product decisions** section lists what F/CTO still needs to decide before PRD §2 can lock.

---

## Architectural layers (the system's shape)

The existing system has a clean three-layer architecture plus an output. V1 should preserve the conceptual separation:

### Layer 1 — Reference data (`Master`)

Centralized lookup data shared across all accounts. Soft-linked into each per-account workbook with `_`-prefixed mirror sheets.

| Master sheet | Purpose | Soft-link in per-account workbook |
|---|---|---|
| **AssetDB** | Symbol → (Cat, Sub-Cat, Description) master registry | `_assetdb` |
| **AssetPriceHist** | Date-indexed price grid; `Has-Formula` flag for live vs manual; includes real estate, delisted stocks tagged with Maturity-Date | `_assetpricehist` |
| **Asset Categories** | Cat → Sub-Cat lookup (6×~35 taxonomy) | `_assetcat` |
| **Cash Flow Categories** | Income / Expenses / OtherCF / AcctSetup taxonomy with sub-cats | `_cfCat` |
| **Account Types** | Account type definitions with Taxable / Tax-Deferred / Allocate-to-Liabilities boolean flags | `_accounttype` |

### Layer 2 — Per-account workbooks (×12 today)

One workbook per financial institution / account. Each contains: transaction ledger, locally-computed views (Summary, Cash Flow, Holdings, Sales), and soft-link mirrors to Master + Asset Summary.

**Displayed sheets in a per-account workbook (5):**

1. **Summary** — Asset Allocation Dashboard (% target vs % alloc + $ ReAlloc) + Bottom Line Summary (Total Value, Unrealized Gains, YTD ST/LT Cap Gains)
2. **Cash Flow** — Income / OtherCF / Expenses × {Month, Q1, Q2, Q3, Q4 [, YTD]} with `Report Date / Test Date / USE TEST ?` date-window toggle
3. **Transactions** — primary ledger with `Date | Cat | Sub-Cat | Symbol | Qty | Price | Ammount | Basis | Description | Open Date | (3 reconciliation columns) | Reconciled $`. Per-row Sheets-quirk dropdown validation (not a V1 carry-over).
4. **Holdings** — output of `calculateHoldings`
5. **Sales** — output of `calculateSales` with `Close Date | Cat | Sub-Cat | Symbol | Qty | Price | Total | Basis | Description | Open Date | L-Term ? | Gain/(Loss) | ST Gain | LT Gain | Wash Sale ?`

**Soft-link sheets (6):** `_assetdb`, `_assetpricehist`, `_assetcat`, `_cfCat`, `_accounttype` (from Master); `_targetaloc` (from Asset Summary).

### Layer 3 — Central aggregator (`Asset Summary`)

Cross-account roll-up via IMPORTRANGE pulls from every per-account workbook's Summary tab. Holds NAV time-series, multi-horizon return analytics, allocation targets, cash-flow rollups, capital-gains rollups, and estimated tax computation.

**Active sheets (8 + soft-links):**

| Sheet | Purpose |
|---|---|
| **Account Totals** | Per-account dashboard widget; one row per account with $ Value, Unrealized Gains, Eval Date, freshness flag |
| **Nav History** | Precalculated monthly NAV by asset category (Real Estate / Cash / Bonds / Equities / Alternatives / Liabilities / NAV) since 12/2015. CPI-U entered manually. Stored in $K. |
| **Nav Chart** | Chart visualization that feeds Finance_Report Google Doc (inflation-normalized 60-month rolling window) |
| **Asset Allocations** | Cross-account allocation roll-up; target % per Sub-Cat across 6 ownership scopes (`$ Alloc` columns) — source for per-account `_targetaloc` |
| **Cash Flow** | Selected Month + all Quarters + YTD displayed; roll-up across all 12 accounts |
| **Est Taxes** | Marginal tax rates → quarterly estimated payment computation; "IRS" account tracks actual payments; Federal + State (CA FTB) parallel tables |
| `_salesCG` | Capital-gains itemization rollup across accounts (internal compute) |
| `_cfMonth` / `_cfQ*` | Per-period cash-flow rollup across accounts (internal compute) |

**Ignored / dropped:**

- **Big Ticket Fund** — F/CTO call: drop from V1.
- `_Nav_History_MoskoLiu` — pre-divorce historical normalization (ignore).
- `_Est_Taxes_Year` — prior years' estimated tax tracking (ignore).
- **Account Info** — personal bookkeeping (account numbers, credentials); out of PRD scope.
- **Logins / Personal_ID** — personal bookkeeping (credentials); out of PRD scope.

### Output layer (`Finance_Report`)

Google Doc, monthly. Generated from Asset Summary + per-account workbook data. The canonical V1 deliverable. Document header reads "THE RICHARD MELVIN MOSKO, JR. 2023 TRUST" (administrative label, not scoping filter — content is full-household).

**Sections:**

1. **OVERVIEW** — title block, month/year stamp
2. **Account Holdings** table — per-account values + unrealized gains, grouped, with subtotals: Total Non-RE, Gross Total, Debt, **Realized Tax Liabilities (est. tax pending)**, **Unrealized Tax Liabilities**, **Net Assets Value (NAV)**
3. **NAV Performance** — comparison anchor (This Month / Prior Month / Prior YE) with nominal + prior-year-$ inflation-adjusted columns; multi-horizon delta panel (Month / YTD / 1-Yr TR / 3-Yr TR / 5-Yr TR) with inflation-adjusted variants for multi-year horizons
4. **Asset Allocation** — Non-Real-Estate Allocation table + US Sector Allocation table, each with `% Target / % Alloc / $ Target / $ Alloc / $ ReAlloc`
5. **Rebalancing Targets** — **free-text** action-item commentary by F/CTO each month (Cash / Bonds / Equity / Alternatives sub-sections)
6. **Cash Flow → Income** — Category × Month/Q1/Q2/Q3/Q4/YTD; planning target: $150k/year
7. **Cash Flow → Expenses** — same shape; budget: $13,000/month
8. **Historical Expenditures** — section header only in current example (placeholder?)
9. **Amortized Expenses (Big Ticket Fund)** — references the Big Ticket Fund; **DROP per F/CTO**
10. **Estimated Taxes → Income** by category split into Income / ST CG / LT CG columns
11. **Federal Income Taxes** — Tax Balance Prior Year, Estimated Tax Payments by quarter, Sub-Total, YTD paid (IRS), Estimated Funds Due (IRS)
12. **State Income Taxes (CA)** — same structure as Federal

---

## Capability matrix

### Reference data capabilities

| Capability | Today | V1 status | Rationale | Cross-ref |
|---|---|---|---|---|
| Asset categories: 6 top-level × ~35 sub-categories | Master.AssetCategories + AssetDB | **V1 preserve (hard requirement)** | F/CTO's lock — "100% duplicated work to implement a dumbed-down version" | ADR-002 §1.8 needs amendment |
| Account type taxonomy with Taxable / Tax-Deferred / Allocate-to-Liabilities flags | Master.AccountTypes | **V1 preserve** | Drives tax-aware aggregations; consistent with ADR-002 §1.6 three-way tagging | ADR-002 §1.6 holds; AccountTypes flags are the same idea at account-level |
| Cash flow categories (Income / Expenses / OtherCF / AcctSetup) with sub-cats | Master.CashFlowCategories | **V1 preserve** | Categorization grammar for cash-flow surface; Mint-style buckets | Maps to PRD §2.3 |
| Symbol registry with Cat/Sub-Cat/Description | Master.AssetDB | **V1 preserve** | Foundation for holdings + allocation; soft-link pattern target | Maps to data model; no PRD lock |
| Date-indexed price history with live-vs-manual flag | Master.AssetPriceHist; `Has-Formula` column | **V1 preserve** | Required for net worth time-series and current-value computation | Maps to data model |
| Real estate + delisted stocks in price history (Maturity-Date overloaded as disposal date) | Master.AssetPriceHist | **V1 preserve** | Non-securities net-worth tracking | Consistent with ADR-002 §1.5 manual entries |
| Live price feed integration (GoogleFinance-style) | Master.AssetPriceHist; `Has-Formula = TRUE` rows | **V1 preserve** | Existing functionality | Architecture decision (Phase 3) |
| Soft-link reference architecture | All per-account workbooks | **V1 preserve as conceptual pattern** | In SaaS terms: shared reference tables with FK from per-account data | Architecture decision (Phase 3) |

### Per-account workbook capabilities

| Capability | Today | V1 status | Rationale | Cross-ref |
|---|---|---|---|---|
| Transaction ledger with Cat/Sub-Cat/Symbol/Qty/Price/Amount/Basis/Description | Per-account Transactions sheet | **V1 preserve** | Source of truth for all derived views | Maps to data model |
| AcctSetup non-cash events (Add-Item / Remove-Item) for stock splits, transfers-in-kind | Per-account Transactions; AcctSetup Cat | **V1 preserve** | Lifecycle events that affect holdings without cash | Maps to PRD §2 (likely §2.4 cross-cutting) |
| Open Date column on sell transactions for LT/ST determination | Per-account Sales | **V1 preserve** | Required for capital gains computation | Consistent with ADR-002 §1.7 |
| Wash-Sale flag on sells (manually maintained) | Per-account Sales | **V1 preserve** | LT/ST classification correction | Consistent with ADR-002 §1.7 |
| Reconciled $ running balance column | Per-account Transactions | **V1 new-decision** | Quality-check tool; useful but not strictly required | Likely V1 |
| Holdings computation (point-in-time, sub-cat scaling, cash special handling) | MoskoFinance.calculateHoldings | **V1 preserve** | Core function of the system | Maps to PRD §2.1 net worth + §2.2 allocation |
| Sub-category quantity scaling rules (bonds × 1/100, options × 100) | MoskoFinance.calculateHoldings | **V1 preserve** | Implicit business rules from existing | Architecture detail (Phase 3) |
| Realized capital gains (LT/ST split, holding-period rule, wash-sale handling) | MoskoFinance.calculateSales | **V1 preserve** | Existing functionality | Consistent with ADR-002 §1.7 realized G/L |
| Section 1256 (Volatility-60/40) 60% LT / 40% ST handling | MoskoFinance.calculateSales | **V1 preserve** | Specialized tax handling F/CTO uses | Consistent with ADR-002 §1.7 |
| T-bill sales broken out (Schwab reporting quirk) | MoskoFinance.calculateSales | **V1 preserve as capability**, but architectural detail | "Broker reporting compatibility" | Architecture (Phase 3) |
| Asset Allocation Dashboard (% target vs % alloc + **$ ReAlloc**) | Per-account Summary sheet | **V1 preserve** — was V2 in ADR-002, F/CTO uses today | Target-vs-actual is core to F/CTO's decision-making | **ADR-002 §1.1 needs amendment** |
| Bottom Line Summary KPIs (Total Value, Unrealized Gains, YTD ST/LT CG) | Per-account Summary sheet | **V1 preserve** | Top-level number widget; same as Asset Summary's headline | Maps to PRD §2.1 |
| Cash Flow by month/quarter/YTD with Report-Date/Test-Date toggle | Per-account Cash Flow sheet | **V1 preserve** | Used today for monthly review and year-end reconciliation | Maps to PRD §2.3 (extends "monthly summations") |
| As-of-date reporting toggle (`USE TEST ?`) | Per-account Cash Flow sheet | **V1 new-decision** | Useful but adds UI surface; could be V2 | F/CTO call |
| Per-row dropdown validation (Cat → Sub-Cat dependent) | Per-account Transactions; Sheets quirk | **Drop (platform quirk)** | Sheets workaround; V1 implements as proper dependent-select UI | Not a data-model concern |

### Central aggregator capabilities (Asset Summary)

| Capability | Today | V1 status | Rationale | Cross-ref |
|---|---|---|---|---|
| Per-account roll-up (1 row per account, current $ Value + Unrealized Gains + Eval Date + freshness flag) | Account Totals | **V1 preserve** | The canonical "list of accounts" view | Maps to PRD §2.1 net worth (composition) |
| Net worth time-series by category (monthly, Dec-2015 → present) | Nav History; full-household | **V1 preserve** | Core net-worth-over-time surface | Consistent with ADR-002 §1.0; maps to PRD §2.1.2 |
| Trust-scoped NAV time-series (parallel to full-household) | Nav History (Sheet 6 in subagent's view) | **V1 new-decision** | Multi-scope data is real, but not currently exercised in monthly report. Latent capability. | Discussed below |
| CPI-U inflation series (manual BLS entry) | Nav History (paired with NAV) | **V1 preserve** | Required for inflation-adjusted variants | Architecture (Phase 3): source of CPI data |
| Trailing returns (1-Mo, YTD, 1-Yr, 3-Yr, 5-Yr TR) with inflation-adjusted variants | Nav History return columns | **V1 preserve** — new vs. ADR-002 | F/CTO uses today | **New PRD capability** |
| Period-over-period delta dashboard (multi-horizon × inflation-adjusted) | Asset Summary Summary panel; Finance_Report NAV Performance | **V1 preserve** — extends prior §2.1.3 headline-delta story | Five horizons + inflation adjustment vs. prior single delta | Extends PRD §2.1.3 |
| Comparison anchor (This Mo / Prior Mo / Prior YE) | Asset Summary Summary panel | **V1 preserve** | Used in monthly report | Maps to PRD §2.1 |
| Cross-account allocation roll-up with multi-scope `$ Alloc` columns | Asset Allocations | **V1 preserve** — multi-scope is new | Existing system tracks Rich vs M-Trust vs IRA vs HSA separately | **New PRD capability + ADR-002 §1.1 amendment** |
| Cash Flow rollup across all accounts | Cash Flow + `_cfMonth` / `_cfQ*` | **V1 preserve** | Core to monthly report | Maps to PRD §2.3 |
| Capital-gains rollup across accounts | `_salesCG` | **V1 preserve** | Compute layer feeding Estimated Taxes | Consistent with ADR-002 §1.7 |
| Estimated quarterly tax computation (marginal rates → estimated payment) | Est Taxes | **V1 preserve** — was V2 in ADR-002, F/CTO uses today in primitive form | "Primitive but works"; load-bearing for cash-flow management | **ADR-002 §2.0 (Finding b) needs amendment** |
| "IRS" account for tracking estimated tax payments | Est Taxes | **V1 preserve** | Real account that tracks actual cash sent to IRS | Maps to data model |
| Federal + State (CA FTB) parallel tax tracking | Est Taxes | **V1 preserve** — new vs. ADR-002 | Multi-jurisdictional tax is real | **New PRD capability** |
| Big Ticket Fund slush tracker | Big Ticket Fund sheet | **DROP** | F/CTO call: "isn't really useful TBH" | Remove from V1 PRD |
| IMPORTRANGE-style cross-account aggregation mechanism | Asset Summary pulls from sibling workbooks | **V1 preserve as concept**; architecture detail | In V1 SaaS: SQL aggregation across user's accounts | Architecture (Phase 3) |
| Freshness flag (TRUE/FALSE on each per-account pull) | Account Totals | **V1 preserve** | Data-staleness signal for the user | Maps to PRD (sync status surface) |

### Output layer capabilities (Finance_Report)

| Capability | Today | V1 status | Rationale | Cross-ref |
|---|---|---|---|---|
| Monthly report as standalone artifact (PDF / Doc / page) | Google Doc, monthly | **V1 preserve** | Canonical V1 deliverable | **New PRD capability — "Monthly Report"** |
| NAV definition = Gross + Real Estate − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities | Finance_Report Account Holdings section | **V1 preserve** | F/CTO's canonical NAV definition; richer than ADR-002 anticipated | **PRD §2.1 needs to specify NAV definition** |
| Realized Tax Liabilities line (current Fed + State liability after est. taxes paid) | Finance_Report | **V1 preserve** | Derived from Est Taxes | Consistent with Est Taxes V1 |
| Unrealized Tax Liabilities line (tax owed if all unrealized gains realized) | Finance_Report | **V1 preserve** | Conservative tax-adjusted net worth | Consistent with ADR-002 §1.7 |
| Rebalancing Targets as free-text commentary | Finance_Report Rebalancing Targets section | **V1 new-decision** | Free-text by user vs. auto-generated from `$ ReAlloc` deltas vs. hybrid | F/CTO call |
| Income / expense planning targets ($150k / $13k mo) | Finance_Report (static text) | **V1 new-decision** | V1-stored config vs. out-of-scope vs. user-editable settings | F/CTO call |
| Trust-named report header (configurable owner identification) | Finance_Report top of doc | **V1 preserve** — config field, not hardcoded | Each user's report has their own legal/notional owner string | Maps to user settings in PRD |
| Multi-scope reporting (per-scope reports) | Data exists (trust-scoped NAV), but not currently exercised | **V1 new-decision (likely V2 defer)** | Latent capability; current monthly report is full-household only | F/CTO call |

### Cross-cutting capabilities

| Capability | Today | V1 status | Rationale | Cross-ref |
|---|---|---|---|---|
| Multi-scope ownership data model (Rich / M-Trust / IRA / HSA per account) | `RichMoskoTrust Titled?` flag + 6× `$ Alloc` columns | **V1 preserve** (data model only; reporting V2-deferred per above) | One user, multiple legal-ownership scopes; not household-vs-individual | **New PRD capability + ADR-002 §1.4 extension** |
| Sub-category numeric prefix sortable convention (`US-01-...` through `US-10-...`) | Master.AssetCategories + AssetDB | **V1 preserve** | UX-relevant sort order | Architecture/UX detail |
| Currency: USD only, US-domiciled assumption | All sheets | **V1 preserve** | Consistent with ADR-002 §3.0 multi-currency-V2 + §1.4 deferral | Holds |
| Typos preserved as canonical names ("Ammount", "Comercial", "Cryptocurrecy") | All sheets | **V1 new-decision** | Migrate-and-correct vs. preserve compatibility | F/CTO call (V1 design) |

---

## ADR-002 verdict status

| ADR-002 § | Verdict | Status post-audit | Action |
|---|---|---|---|
| §1.0 | V1 surfaces: net worth + asset allocation + spending/income categorization | **Holds**, with caveats: all three are V1, but each is richer than the abstract description (multi-level allocation, multi-horizon returns, multi-period cash flow) | Refine §2 PRD content; ADR-002 verdict itself doesn't change |
| §1.1 | Rebalancing suggestions = V2+ | **Needs amendment** — F/CTO uses `$ ReAlloc` rebalance dashboard today | Draft ADR-004 amending §1.1: rebalancing-targets-visualization (target % vs actual % vs ReAlloc $) is V1; auto-generated rebalance *prompts/suggestions* remain V2+ |
| §1.2 | Spending/income categorization V1 non-goals (budget targets, alerts, etc.) | **Holds** with one caveat: $13k/month expense budget is referenced in report as static text — V1-tracked-budget is a new decision | Decide budget tracking V1 inclusion |
| §1.3 | V1 transaction-tracking across all account types (Plaid Trans + Inv) | **Holds** — existing system covers all these account types via manual entry; V1 will add Plaid automation | No change |
| §1.4 | Multi-tenant from day one; single-user usage; forward-compat | **Holds + extends** — also need multi-scope-ownership within a single tenant | Draft ADR-005 adding multi-scope ownership to §1.4 data model |
| §1.5 | Manual non-Plaid accounts and manual transaction entry in V1 | **Holds** — existing system is 100% manual today | No change |
| §1.6 | Three-way tax tagging (taxable/tax-deferred/tax-free) at account level | **Holds** — exists today as Master.AccountTypes flags | No change |
| §1.7 | Cost basis + unrealized G/L V1; lot-level UI V2; wash-sale, Section 1256 handling | **Holds** — exists today | No change |
| §1.8 | Securities general principle: uniform transaction-level handling, security_type as categorization attribute, mechanics V2+ | **Needs amendment** — existing system uses multi-level user-meaningful taxonomy (Cat → Sub-Cat) that goes beyond security_type | Draft ADR-006 amending §1.8: multi-level taxonomy is V1 (already locked verbally) |
| §1.9 | Per-account-type boundaries (credit, loans, brokerage cash sweep, DRIP, options, bonds, crypto) | **Holds** | No change |
| §2.0 | V2 candidates: tax planning, Monte Carlo, lot-level tax, stock screening | **Needs amendment** — tax planning (estimated payments) is V1, not V2 | Roll into ADR-004 or separate: tax planning V1 in primitive form |
| §3.0 | Out-of-scope for this PRD lifecycle: public sign-up, money movement, advisor, real-time quotes, mobile-native | **Holds** | No change |
| §4.0 | Stack content routed out of PRD scope (Phase 3) | **Holds** | No change |
| §5.0 | Architectural constraints in PRD; multi-tenant + lots-in-schema | **Holds** | No change |
| §6.0 | ≤ ~$50/month V1 cost target | **At risk** — existing system uses Google Sheets for free; V1 SaaS infra cost is the real budget. Confirm with Architect in Phase 3. | Flag for Architect |
| §7.0 | 9 content gaps for Step 3 drafting | Some answered by audit (target user is clearer; multi-scope is new; tax/Plaid implications are clearer); some still open (success metrics, data retention, accessibility, "V1 done" definition) | PM addresses remaining gaps when re-engaged |
| §8.0 | Architect / Security Reviewer routing flags | **Holds**; audit added several new routing items (CPI source, IMPORTRANGE equivalent, multi-scope data model, etc.) | Append to §8.0 when ADRs draft |

---

## Capabilities new to PRD (not in any ADR-002 verdict)

1. **Multi-horizon trailing returns** (1-Mo, YTD, 1-Yr TR, 3-Yr TR, 5-Yr TR) with inflation-adjusted variants
2. **Period-over-period delta dashboard** (multi-horizon × inflation-adjusted)
3. **Multi-scope ownership data model** (Rich / M-Trust / IRA / HSA scopes within one user)
4. **Estimated quarterly tax computation** with Federal + State (CA FTB) parallel tracking
5. **NAV definition with Unrealized Tax Liabilities subtraction**
6. **Asset Allocation Dashboard with `$ ReAlloc` column** (target-vs-actual rebalance visualization)
7. **Monthly Finance Report as a standalone V1 deliverable** with configurable owner-identification header
8. **Income / expense planning targets** as static or tracked config ($150k / $13k mo)
9. **Inflation series (CPI-U) ingestion** for inflation-adjusted views
10. **Live-vs-manual price-source segregation** (`Has-Formula` flag)
11. **AcctSetup non-cash events** (stock splits, transfers-in-kind)
12. **As-of-date toggle** (`USE TEST ?`) for historical reconciliation

---

## PRD §2 mapping (where each capability lands)

| PRD section | Content shape |
|---|---|
| **§2.1 Net worth** | Current NAV, NAV time-series, NAV composition by account, NAV definition with tax-liability subtractions, headline delta dashboard (multi-horizon, inflation-adjusted), Account Holdings table view, multi-scope-aware data model |
| **§2.2 Asset allocation** | Multi-level taxonomy (6 top × ~35 sub), allocation roll-up across accounts, target % vs actual %, $ ReAlloc visualization, US Sector sub-allocation, multi-scope `$ Alloc` views, asset allocation history |
| **§2.3 Spending and income categorization** | Cash flow categories taxonomy, Income/Expenses/OtherCF buckets, Month/Quarter/YTD multi-period views, Cash Flow rollup across accounts, as-of-date toggle, planning targets (decision pending) |
| **§2.4 Cross-cutting** | Account onboarding flow, manual entry (accounts + transactions), Plaid re-auth flow, AcctSetup non-cash events, capital gains computation (LT/ST + wash-sale + Section 1256), Symbol registry maintenance |
| **§2.5 Estimated taxes (NEW)** | Marginal rate input, quarterly est-payment computation, Federal + State (CA FTB) parallel tracking, IRS account for actual payments, Realized vs Unrealized Tax Liabilities |
| **§2.6 Monthly Report output (NEW)** | Report generation, sections (Account Holdings, NAV Performance, Asset Allocation, Rebalancing Targets, Cash Flow, Estimated Taxes), configurable owner-identification header, free-text rebalancing commentary |

---

## Open product decisions (queued for F/CTO)

These are sub-decisions the PM will need answers to before §2 stories can lock. Listed in rough order of consequence.

1. **NAV definition lock**: full = `Gross + Real Estate − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities`, or simplified for V1?
2. **Rebalancing Targets in V1**: (a) free-text monthly commentary by user, (b) auto-generated from `$ ReAlloc` deltas, (c) hybrid.
3. **Multi-scope reporting V1 or V2**: data model preserves multi-scope; do we ship per-scope reports in V1, or only full-household with multi-scope deferred?
4. **As-of-date toggle V1 or V2**: data layer supports it; UI cost is real.
5. **Income / expense planning targets**: V1-stored config vs. out-of-scope vs. user-editable.
6. **Budget tracking V1 inclusion**: $13k/month is referenced; do we track variance against it in V1?
7. **Reconciled $ running balance**: V1 capability or out-of-scope?
8. **Typo handling**: migrate-and-correct ("Amount", "Commercial") or preserve compatibility?
9. **Big Ticket Fund** report section: drop entirely from V1 report or stub for future reintroduction?
10. **CPI-U source**: live API or manual entry in V1?
11. **Wash-sale flag**: V1 user-marked or auto-detect (auto-detect is V2 per ADR-002 §1.7)?
12. **Section 1256 handling**: V1 expects user-classified at the security level (via Sub-Cat `Volatility-60/40`)?

---

## What's not in this matrix

- **PRD §1 (Vision + target user)** — already on disk; revisit during PM re-engagement to cross-check against script-grounded user model. The "self-directed multi-account owner" archetype was drafted from preliminary findings; the audit shows the archetype actually values **precision in categorization** (multi-level taxonomy) and **active rebalance management** (Asset Allocation Dashboard usage). §1.2 attribute #4 reframe is queued.
- **PRD §3–§7** — not yet drafted; will be drafted post-§2 using parity matrix as input.
- **Architecture** — Phase 3 work. Many capabilities here (IMPORTRANGE equivalent, CPI source, multi-tenant scope-aware schema, soft-link pattern translation) become Architect routing items.
- **Build sequencing** — Phase 4 work (Linear backlog decomposition).

---

*End of v1-parity-matrix.md draft.*
