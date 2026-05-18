# DECISIONS.md

Architectural Decision Records for mosko-fintech. Each entry captures a non-obvious choice: what was decided, what was considered, why.

**Format.** One ADR per H2 heading, numbered sequentially. Newest at top. Entries are immutable once accepted — supersede via a new entry rather than rewriting an old one. Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNN`, `Deprecated`.

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
