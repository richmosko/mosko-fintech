# PR 3 body-gate-1 — §2.1 (Net worth) body preview

> Standalone preview of the proposed rewritten §2.1 + new Appendix C creation, extracted from PR 3 body-gate-1 PM deliverable for rendered viewing.
>
> **PM judgment call:** Under Q-S4 = β (opener-prelude removed), PM evaluated three shape options and picked **Option 2 (capability-statement extraction)** as default — preserves V1 commitment in PRD body in declarative product-voice ("V1 surfaces…", "V1 renders…") rather than user-voice ("As the Independent Investor, I want…"). Pure Option 1 (title + trace marker only) would have stripped capability content from PRD body to a navigation-index shape; PM judged that fails the PRD-as-source-of-truth test.
>
> **VP-5 surfaced:** under Q-S4 = β + Option 2, the term "Independent Investor" appears zero times in rewritten §2 body. Archetype name lives in §1.3 PRD body + §2.x Appendix C trace content (verbatim source preservation). PM proposes Q-B2 (add one-line framing line at top of §2 re-anchoring to §1.3).

---

## §2.1 body draft (proposed for PRD.md integration)

### 2.1 Net worth

#### Primary stories

**2.1.1 Current net worth (Net Asset Value).**

V1 surfaces the user's current total net worth as **Net Asset Value (NAV)**, defined as **Gross Asset Value** (sum of all asset balances including Real Estate) **minus Debt** (sum of all liability balances) **minus Realized Tax Liabilities** (accrued Federal + California estimated-tax obligation net of payments already made) **minus Unrealized Tax Liabilities** (estimated tax owed if all current unrealized capital gains were realized today). A single trustworthy whole-position number, conservatively adjusted for tax obligations the position carries, without cross-institution arithmetic.

*Traces: see Appendix C → 2.1.1.*

**2.1.2 Net worth over time.**

V1 renders net worth as a time-series chart with a **monthly default** and on-demand weekly or daily granularity, plus an **inflation-adjusted overlay** rendered as a second NAV line on the same chart — normalized to today's $ value using a CPI-U price-index series, visually distinct from the nominal line, over a 60-month rolling window, drawn simultaneously rather than behind a toggle. Together these show whether overall position is improving, holding, or declining over a meaningful horizon in both nominal and real-purchasing-power terms; shorter-period drill-down supports investigation of specific inflection points. The 60-month rolling window is fixed in V1; user-configurable rolling windows are V2+.

*Traces: see Appendix C → 2.1.2.*

**2.1.3 Multi-horizon NAV-delta panel.**

V1 displays NAV alongside a panel of delta measurements over five fixed time horizons — **Month** (vs. one month ago), **YTD** (vs. most recent year-end), **1-Year** (trailing 12 months), **3-Year** (trailing 36 months), and **5-Year** (trailing 60 months) — each shown as both dollar and percentage change, with an **Inflation Adjusted** column displayed side-by-side covering the three multi-year horizons (1-Year, 3-Year, 5-Year) and referenced to the prior Year-End (Month and YTD have no Inflation Adjusted value). Together these answer whether position is moving in the expected direction over both the normal monthly decision cadence and the longer horizons that matter for compounding and retirement planning, and prevent a multi-year nominal gain that inflation has consumed from reading as growth. The horizon set is fixed in V1; user-configurable horizons are V2+.

*Traces: see Appendix C → 2.1.3.*

**2.1.4 NAV at three reference dates.**

V1 displays NAV at three fixed reference dates: **This Month** (current), **Prior Month** (one month ago), and **Prior Year-End** (most recent December close). Each NAV value renders in two columns — **NAV** (nominal dollars) and **NAV — Prior Yr $** (the same value expressed in prior-Year-End dollars after inflation adjustment). Together these give a quick read of NAV at the anchor dates that frame monthly review and tax-year context, in both nominal and inflation-adjusted terms. The reference-date set is fixed in V1; user-defined reference dates are V2+.

*Traces: see Appendix C → 2.1.4.*

**2.1.5 Net worth composition.**

V1 renders NAV decomposed in a single integrated table that builds up from individual account rows through explicit subtotal lines to the final NAV. Each account row shows both **current value** and **unrealized gain/loss**, grouped by account-type category within the asset half of the table (depository, investment, retirement, crypto, manual/other), with Real Estate accounts forming their own group adjacent to the non-RE asset categories. Buildup subtotals run in order: **Total Non-RE** (sum of non-Real-Estate asset accounts) → **Gross Total** (Total Non-RE + Real Estate) → **Debt** (sum of liability accounts) → **Realized Tax Liabilities** (accrued Federal + California estimated-tax obligation net of payments) → **Unrealized Tax Liabilities** (estimated tax on current unrealized gains) → **Net Assets Value (NAV)** at the foot. Any account-type category expands one level to show individual contributing accounts. The table makes the four-component NAV definition from 2.1.1 (`Gross − Debt − Realized Tax Liab − Unrealized Tax Liab`) visually traceable from its parts; the single headline number doesn't hide its structure, and category- or subtotal-level drivers of total or change are visible at a glance.

*Traces: see Appendix C → 2.1.5.*

#### Supporting stories

**2.1.6 Investment net worth uses current market value.**

V1 uses current market value for investment-account contributions to net worth, so net worth reflects what holdings are actually worth today — not what was paid for them.

*Traces: see Appendix C → 2.1.6.*

**2.1.7 Net worth is the user's, not anyone else's.**

V1 surfaces only the requesting user's own accounts and data in the net worth view; no possibility of another user's data appearing. Accounts aggregate into a single **full-household NAV by default**, spanning every ownership scope held (e.g., personal, trust, retirement custodial, HSA). The result is a number the user can trust absolutely, reflecting the entire household position the way the user thinks about it, honoring the system's multi-tenant commitment from day one even though V1 ships to a single user. Per-scope reporting (one NAV per scope) and scope-aware filtering UI are V2+, not V1; the data model carries scope on each account from V1 (per ADR-004 Decision B) so the V2 expansion ships without data migration.

*Traces: see Appendix C → 2.1.7.*

*Routing flags affecting §2.1: see Appendix B (created in PR 10; pending consolidation).*

---

## Appendix C creation (new appendix scaffolded at body-gate-1)

## Appendix C — Story Trace Index

Per-story trace records for §2 V1 user stories, extracted from in-body `Traces to:` clauses during Phase 1 Step 3.5 PRD editorial rewrite (PR 3). Each entry preserves the original trace content verbatim; the bold-prefixed story ID provides scan navigation. Stories appear in §2 source order. Created at PR 3 body-gate-1 (§2.1); subsequent body gates (§2.2 through §2.6) extend this appendix.

### §2.1 — Net worth

**2.1.1 — Current net worth (Net Asset Value).**

> *Traces to:* ADR-002 §1.0 (net worth ratified as a V1 surface); §1.3 + §1.5 + §1.9 (account-category coverage and per-account-type boundaries — every account category contributes to Gross or Debt); ADR-002 §1.7 (V1 carries aggregate cost basis and unrealized G/L per position — the input that drives Unrealized Tax Liabilities). **ADR-004 Decision D** (V1 includes estimated quarterly tax computation in primitive form with Federal + California FTB parallel marginal-rate inputs; "Realized vs Unrealized Tax Liabilities line items derivable from the estimated-tax surface" is bulleted as in-scope). **`docs/v1-parity-matrix.md` line 174** (existing-system NAV definition: `Gross + Real Estate − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities`) and **line 99** (the Finance_Report Account Holdings table layout) — V1 preserves the existing definition.

**2.1.2 — Net worth over time.**

> *Traces to:* Preliminary finding (a) "over time" framing, ratified in ADR-002 §1.0. Granularity hybrid (monthly default with weekly/daily override) is a V1 product expectation; architectural cost of supporting multiple granularities is acknowledged and routed to Architect (existing "period aggregation for the time series" flag in §2.1's Open routing flags block). **`docs/v1-parity-matrix.md` line 77** ("Nav Chart … inflation-normalized 60-month rolling window") and existing-report ground truth from F/CTO direct inspection of `Finance_Report_2026_04.pdf` page 3 "Category Totals" chart: two NAV lines overlaid on a single chart — black solid "NAV" (nominal) + red dashed "NAV (Inf-Norm)" (inflation-normalized to today's $); both lines drawn simultaneously, not toggled. The today's-$ normalization basis here is intentionally distinct from §2.1.3's prior-Year-End reference basis: the chart shows continuous purchasing-power trajectory while the §2.1.3 panel shows spot-delta comparisons against a tax-year anchor. The §2.1.2 chart, §2.1.3 panel, and §2.1.4 reference-values table all consume the same CPI-U series — sourcing (live API vs. manual entry) is the Architect routing flag already in §2.1's Open routing flags block (parity-matrix open product decision #10).

**2.1.3 — Multi-horizon NAV-delta panel.**

> *Traces to:* ADR-002 §1.0 (net worth is a V1 surface). **`docs/v1-parity-matrix.md` lines 100, 156, 157, 219** (existing-system multi-horizon NAV-delta panel with inflation-adjusted variants for multi-year horizons — V1 preserve; "Multi-horizon trailing returns" listed as a capability new to PRD). Existing-report ground truth from F/CTO direct inspection of `Finance_Report_2026_04.pdf` page 3 ("Net Assets Value (NAV) Performance" panel): two columns `NAV Delta` | `Inflation Adjusted`; five rows `Delta Month` / `Delta YTD` / `Delta 1-Yr (TR)` / `Delta 3-Yr (TR)` / `Delta 5-Yr (TR)`; Inflation Adjusted populated for 1-Yr / 3-Yr / 5-Yr only with a prior-Year-End reference basis per section footnote ("*Inflation Adjustment referenced to prior Year-End*"). Horizon set: fixed V1, user customization V2+. Historical NAV depth: V1 imports the existing Google Sheet's monthly NAV history (Dec-2015 forward) so the 5-Year horizon is meaningful at launch — F/CTO has locked the *whether*; the *how* is routed to Architect (Phase 3). CPI-U series and chart-overlay shape are queued as §2.1.2 downstream-extension flags; the §2.1.3 panel and §2.1.2 chart both consume the same CPI-U series.

**2.1.4 — NAV at three reference dates.**

> *Traces to:* ADR-002 §1.0 (net worth is a V1 surface). **`docs/v1-parity-matrix.md` lines 100 and 158** (existing-system comparison anchor: "comparison anchor (This Month / Prior Month / Prior YE) with nominal + prior-year-$ inflation-adjusted columns" — V1 preserve; "Comparison anchor (This Mo / Prior Mo / Prior YE) — Asset Summary Summary panel — V1 preserve — Used in monthly report — Maps to PRD §2.1"). Existing-report ground truth from F/CTO direct inspection of `Finance_Report_2026_04.pdf` page 3, top sub-surface within the "Net Assets Value (NAV) Performance" section: three rows `Assets (This Month)` / `Assets (Prior Month)` / `Assets (Prior Year-End)`; two columns `NAV` | `NAV - Prior Yr $`; all six cells populated. Inflation reference basis is prior Year-End — consistent with §2.1.3's Inflation Adjusted column; same CPI-U series. This story is a sibling to §2.1.3 (the multi-horizon NAV-delta panel) within the same Finance_Report "Net Assets Value (NAV) Performance" section; together they answer "what is my NAV at the anchor dates that frame my review?" (this story) and "how much has my NAV changed over horizons?" (§2.1.3). CPI-U source decision remains the §2.1.2 downstream-extension Architect flag in §2.1's Open routing flags block.

**2.1.5 — Net worth composition.**

> *Traces to:* ADR-002 §1.9 (per-account-type boundaries are first-class); ADR-002 §1.0 (composition view dovetails with §2.2 asset allocation but is distinct: composition shows the buildup of *accounts* into NAV; allocation shows the distribution of *asset classes* across the position). ADR-002 §1.7 (per-position unrealized G/L is V1 — feeds the per-row unrealized gain/loss column). **ADR-004 Decision D**: Realized + Unrealized Tax Liabilities subtractions on the buildup trace to the Federal + California estimated-tax surface and the §2.1.1 NAV definition. F/CTO verified at Task #2 close that the Realized Tax Liab definition ("accrued Federal + California estimated-tax obligation, net of payments already made") and the Unrealized Tax Liab primitive form (marginal-rate × aggregate unrealized G/L, no ST/LT split) both match the existing Google Sheet's primitive calculation. **`docs/v1-parity-matrix.md` line 99** (existing Finance_Report Account Holdings table: "per-account values + unrealized gains, grouped, with subtotals: Total Non-RE, Gross Total, Debt, Realized Tax Liabilities (est. tax pending), Unrealized Tax Liabilities, Net Assets Value (NAV)" — V1 preserve). Composition buckets are user-meaningful, not Plaid-derived (see Appendix A). Drill-down stops at the account level by design — holdings live in §2.2, transactions live in §2.3. NAV at the foot of the table is the same NAV defined in §2.1.1; this section makes that definition visually concrete from its components.

**2.1.6 — Investment net worth uses current market value.**

> *Traces to:* ADR-002 §1.7. The cost-basis comparison surface lives in §2.2 or a future investment-detail view; net worth uses market value.

**2.1.7 — Net worth is the user's, not anyone else's.**

> *Traces to:* ADR-002 §1.4 (multi-tenant from day one — tenant_id isolation foundational); **ADR-004 Decision B** (multi-scope ownership Rich / Trust / IRA / HSA is a V1 data attribute on accounts within a single tenant; V1 default report scope = full-household; per-scope reporting surfaces and scope-aware UI filtering are V2+). Jurisdictional scope of the NAV calculation (Federal + California per ADR-004 Decision D, US-domiciled per §1.4 deferrals) is established in §2.1.1 and is not re-litigated here — this story addresses tenant isolation and household-scope aggregation, not jurisdictional scope. **Flagged for Security Reviewer** per §8.0 (multi-tenant data isolation) — this section cannot move from draft to locked without a Security Reviewer pass; the Security Reviewer pass should additionally confirm that the multi-scope data attribute (per Decision B) is treated as a user-owned data label and not as a V1 isolation boundary (scopes are not tenants).
