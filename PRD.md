---
artifact: PRD.md
project: mosko-fintech
version: 0.1
status: draft — Phase 1 / Step 3 (section-by-section)
owner: Product Manager (agent) on behalf of Founder/CTO
last-updated: 2026-05-12
source-of-truth-for: V1 product scope, user stories, success metrics, non-goals
upstream: DECISIONS.md (ADR-001, ADR-002), WORKFLOW.md
downstream: ARCHITECTURE.md (Phase 3), Linear initiatives/projects (Phase 4)
---

# Product Requirements — mosko-fintech V1

> **Reading order:** this PRD is the single source of truth for what mosko-fintech V1 is. Architectural and infrastructure decisions live in `ARCHITECTURE.md` (Phase 3); backlog decomposition lives in Linear (Phase 4+). Anything locked here flows downstream; anything locked downstream must trace back to a requirement here.

## 1. Vision and target user

### 1.1 Vision

mosko-fintech is a personal financial observatory: a single, trustworthy view of one individual's complete financial position across every account they hold — checking, savings, credit, brokerage, retirement, loans, crypto — plus the activity (transactions and investment flows) and derived measures (net worth, asset allocation, monthly spending and income by category, estimated taxes) that make the position meaningful. V1 progressively replaces the working manual-spreadsheet system the V1 instance maintains today; the V1 done bar is functional parity with that system, with the **monthly Finance Report** as the canonical deliverable. V1 is observational in scope: it surfaces the user's position and the gap between their target allocation and actual allocation, but it does not move money, generate specific buy/sell recommendations, or act in any advisory capacity. The goal is clarity in the user's own hands — the user decides; the tool shows.

### 1.2 Target-user archetype

The V1 target user — *the self-directed multi-account owner* — is a financially-engaged individual with a fragmented multi-account portfolio, someone who has accumulated, over years, a mix of account types that no single bank or brokerage view covers and that public consumer-finance tools tend to oversimplify or misrepresent.

The archetype has the following defining attributes:

- **Multi-institution footprint.** Accounts spread across multiple banks, brokerages, retirement custodians, credit issuers, and at least one crypto venue. No single institution dashboard captures their position; aggregation is non-optional.
- **Mixed tax-treatment portfolio across multiple jurisdictions.** Holdings span taxable, tax-deferred, and tax-exempt accounts (and HSA, which is conditional on use). Their tax thinking is jurisdictional — they reason about Federal and state (California, in the V1 instance) tax obligations in parallel, not as a single combined number. Tax treatment and jurisdiction are first-class attributes of how they think about money, not afterthoughts.
- **Holds investment securities, not just deposits.** Brokerage and retirement accounts contain equities, funds, fixed income, and possibly other instruments. They care about cost basis and unrealized gain/loss, not just balances.
- **Self-directed, with an observational tool.** They make their own financial decisions — portfolio allocation, rebalance timing, spending changes, account-level moves — and they use this tool as input to those decisions, not as a source of them. They want to *see* their position clearly and *manage* the gap between their target allocation and their actual allocation.
- **Precise about categorization.** They maintain deliberate, two-level taxonomies — a top-level category and a sub-category — for both the holdings they own (e.g., Equity → US-Index_Non_Sector; Bonds → T-bill; Alternatives → REIT) and the cash-flow activity their accounts generate (Income, Expenses, and other flow types, each with sub-categories of their own). A coarse-bucket tool that summarizes "you have $X in equities" without distinguishing US-sector / international / index-vs-growth would be unusable to them. They assign holdings and transactions to their buckets themselves and update those assignments as their portfolio evolves; the categorization grammar is theirs to define and theirs to apply.
- **Privacy- and control-conscious.** They are uncomfortable with consumer-finance tools that monetize their data, push affiliate products, or surface "insights" that are really marketing. They prefer a tool they own, that holds their data on their terms.
- **Comfortable with substantial manual curation.** They maintain their financial system actively, by hand, on a monthly cadence — entering or reconciling transactions, refreshing valuations on held-away assets, and curating the taxonomies that categorize what they own. They will not tolerate a tool that pretends the un-aggregated accounts don't exist, and they accept that some accounts and asset classes will continue to require manual entry indefinitely.

The Founder/CTO is the V1 instance of this archetype. V1 is built for and validated by a population of one.

### 1.3 Why this archetype, not "me specifically"

The PRD frames the target user as an archetype rather than as the Founder/CTO personally because three locked decisions in `DECISIONS.md` make the archetype framing load-bearing rather than aspirational:

1. **Multi-tenant from day one** (ADR-002). The data model, auth boundary, and isolation guarantees treat the user identity as a first-class entity from V1. Tying the PRD to a single named person would be a fiction the architecture explicitly refuses to maintain.
2. **Forward-compatibility commitment** (ADR-002). V2+ broadens distribution to invite-only — a small cohort of *self-directed multi-account owners*. Defining the archetype now means V2 inherits a known target population rather than re-litigating who the next users are.
3. **Single-user usage model in V1** (ADR-002). The archetype framing does not contradict this — V1 ships with one user (the Founder/CTO) actively using it. The archetype is the *shape* of the user the product is designed for; the V1 *instance* of that shape is the Founder/CTO. The two are deliberately decoupled.

The practical consequence: V1 success means "this works for the Founder/CTO specifically." V1 product correctness means "every requirement traces to an attribute of the archetype, not to a one-off preference." When the two conflict — when a Founder/CTO preference is not a generalizable archetype attribute — the conflict surfaces as a flag for V1.0/V1.1 milestone-sequencing decisions (Phase 4 territory, not this section's problem). Post-script-audit, *V1 correctness* also carries an existing-system-replacement test: per the §8 V1-done definition, V1 is correct when it replicates the workflows the F/CTO maintains today in their manual-spreadsheet system, plus the explicit ADR-004 amendments.

### 1.4 What this PRD section is not addressing about the user

To keep the archetype defensible and avoid scope creep into adjacent personas, the following user-shape questions are explicitly **deferred**, not silently elided:

- **Household and joint-account semantics.** The V1 archetype is individual-scoped. Joint accounts owned with a spouse or partner appear in V1 as accounts the individual has access to, not as a multi-owner data model. Multi-scope ownership *within* a single user's household — multiple legal-ownership scopes (e.g., personal, trust, retirement custodial) held by one person — is a V1 data attribute per ADR-004 Decision B; the data model carries it. But household-level user-facing semantics (shared budgets, multi-owner net worth, partner visibility, per-scope user-facing reports) are out-of-scope for this PRD lifecycle and are routed to a future PRD revision if and when invite-only V2 demand surfaces.
- **Geographic, currency, and multi-jurisdictional tax scope.** V1 assumes a US-domiciled user with USD-denominated accounts. Multi-currency support is V2+ (ADR-002 reclassification). V1 tax handling is jurisdiction-specific to the V1 instance's situation — US Federal plus California state — per ADR-004 Decision D. Multi-state tax handling (a user with non-California state obligations) and non-US tax handling (RRSP, ISA, foreign tax credits, etc.) are V2+, not just non-USD currency.
- **Life-stage and goal-tracking framing.** The archetype is defined by what they own and how they think about their money today, not by retirement goals, savings targets, or life events. Goal-tracking is a candidate V2 surface; it does not shape the V1 archetype.
- **Advisor or accountant collaboration.** The advisor/fiduciary role is out-of-scope for this PRD lifecycle (ADR-002). Read-only exports for an accountant at tax time are a candidate V2 feature, not an archetype attribute.

These deferrals are not non-goals in the permanent sense; they are scope boundaries for this PRD lifecycle.

## 2. V1 user stories

### 2.1 Net worth

#### Primary stories

> **2.1.1 Current net worth (Net Asset Value).**
> As the self-directed multi-account owner, I want to see my current total net worth — formally my **Net Asset Value (NAV)**, defined as **Gross Asset Value** (the sum of all asset balances, including Real Estate) **minus Debt** (the sum of all liability balances) **minus Realized Tax Liabilities** (my current accrued Federal and California estimated-tax obligation, net of estimated payments already made) **minus Unrealized Tax Liabilities** (the estimated tax that would be owed if all current unrealized capital gains were realized today) — so that I have a single trustworthy number that reflects my whole financial position at a glance, conservatively adjusted for the tax obligations my position carries, without doing the arithmetic across institutions myself.
>
> *Traces to:* ADR-002 §1.0 (net worth ratified as a V1 surface); §1.3 + §1.5 + §1.9 (account-category coverage and per-account-type boundaries — every account category contributes to Gross or Debt); ADR-002 §1.7 (V1 carries aggregate cost basis and unrealized G/L per position — the input that drives Unrealized Tax Liabilities). **ADR-004 Decision D** (V1 includes estimated quarterly tax computation in primitive form with Federal + California FTB parallel marginal-rate inputs; "Realized vs Unrealized Tax Liabilities line items derivable from the estimated-tax surface" is bulleted as in-scope). **`docs/v1-parity-matrix.md` line 174** (existing-system NAV definition: `Gross + Real Estate − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities`) and **line 99** (the Finance_Report Account Holdings table layout) — V1 preserves the existing definition.

> **2.1.2 Net worth over time.**
> As the self-directed multi-account owner, I want to see how my net worth has changed over time, displayed as a time series with a monthly default and the ability to view weekly or daily granularity on demand, so that I can understand whether my overall financial position is improving, holding, or declining over a meaningful horizon — and so I can drill into shorter periods when I'm investigating a specific inflection point.
>
> *Traces to:* Preliminary finding (a) "over time" framing, ratified in ADR-002 §1.0. Granularity hybrid (monthly default with weekly/daily override) is a V1 product expectation; the architectural cost of supporting multiple granularities is acknowledged and routed to Architect.

> **2.1.3 Multi-horizon NAV-delta panel.**
> As the self-directed multi-account owner, I want my current NAV displayed alongside a panel of delta measurements over five fixed time horizons — **Month** (vs. one month ago), **YTD** (vs. the most recent year-end), **1-Year** (trailing 12 months), **3-Year** (trailing 36 months), and **5-Year** (trailing 60 months) — each shown as both a dollar change and a percentage change, with an **Inflation Adjusted** column displayed side-by-side covering the three multi-year horizons (1-Year, 3-Year, 5-Year) and referenced to the prior Year-End (Month and YTD have no Inflation Adjusted value), so that I can see at a glance whether my position is moving in the direction I expect over both my normal monthly decision cadence and the longer horizons that matter for compounding and retirement planning, and so that a multi-year nominal gain that inflation has consumed doesn't read as growth. The horizon set is fixed in V1; user-configurable horizons are V2+.
>
> *Traces to:* ADR-002 §1.0 (net worth is a V1 surface). **`docs/v1-parity-matrix.md` lines 100, 156, 157, 219** (existing-system multi-horizon NAV-delta panel with inflation-adjusted variants for multi-year horizons — V1 preserve; "Multi-horizon trailing returns" listed as a capability new to PRD). Existing-report ground truth from F/CTO direct inspection of `Finance_Report_2026_04.pdf` page 3 ("Net Assets Value (NAV) Performance" panel): two columns `NAV Delta` | `Inflation Adjusted`; five rows `Delta Month` / `Delta YTD` / `Delta 1-Yr (TR)` / `Delta 3-Yr (TR)` / `Delta 5-Yr (TR)`; Inflation Adjusted populated for 1-Yr / 3-Yr / 5-Yr only with a prior-Year-End reference basis per section footnote ("*Inflation Adjustment referenced to prior Year-End*"). Horizon set: fixed V1, user customization V2+. Historical NAV depth: V1 imports the existing Google Sheet's monthly NAV history (Dec-2015 forward) so the 5-Year horizon is meaningful at launch — F/CTO has locked the *whether*; the *how* is routed to Architect (Phase 3). CPI-U series and chart-overlay shape are queued as §2.1.2 downstream-extension flags; the §2.1.3 panel and §2.1.2 chart both consume the same CPI-U series.

> **2.1.4 NAV at three reference dates.**
> As the self-directed multi-account owner, I want my NAV displayed at three fixed reference dates: **This Month** (current), **Prior Month** (one month ago), and **Prior Year-End** (the most recent December close). I want each of those NAV values shown in two columns — **NAV** (nominal dollars) and **NAV — Prior Yr $** (the same value expressed in prior-Year-End dollars after inflation adjustment). Together these give me a quick read of my NAV at the anchor dates that frame my monthly review and tax-year context, in both nominal and inflation-adjusted terms. The reference-date set is fixed in V1; user-defined reference dates are V2+.
>
> *Traces to:* ADR-002 §1.0 (net worth is a V1 surface). **`docs/v1-parity-matrix.md` lines 100 and 158** (existing-system comparison anchor: "comparison anchor (This Month / Prior Month / Prior YE) with nominal + prior-year-$ inflation-adjusted columns" — V1 preserve; "Comparison anchor (This Mo / Prior Mo / Prior YE) — Asset Summary Summary panel — V1 preserve — Used in monthly report — Maps to PRD §2.1"). Existing-report ground truth from F/CTO direct inspection of `Finance_Report_2026_04.pdf` page 3, top sub-surface within the "Net Assets Value (NAV) Performance" section: three rows `Assets (This Month)` / `Assets (Prior Month)` / `Assets (Prior Year-End)`; two columns `NAV` | `NAV - Prior Yr $`; all six cells populated. Inflation reference basis is prior Year-End — consistent with §2.1.3's Inflation Adjusted column; same CPI-U series. This story is a sibling to §2.1.3 (the multi-horizon NAV-delta panel) within the same Finance_Report "Net Assets Value (NAV) Performance" section; together they answer "what is my NAV at the anchor dates that frame my review?" (this story) and "how much has my NAV changed over horizons?" (§2.1.3). CPI-U source decision remains the §2.1.2 downstream-extension Architect flag in §2.1's Open routing flags block.

> **2.1.5 Net worth composition.**
> As the self-directed multi-account owner, I want to see what my net worth is composed of — broken down into assets vs. liabilities, and within assets, into the account-type categories (depository, investment, retirement, crypto, manual/other) — so that the single number in 2.1.1 doesn't hide its structure, and so I can see at a glance which categories are driving the total or its change. I want to be able to expand any category one level to see the individual accounts contributing to it, so that when a category is moving I can identify which specific account is responsible without leaving the composition view.
>
> *Traces to:* ADR-002 §1.9 (per-account-type boundaries are first-class), §1.0 (asset allocation is a V1 surface — composition view dovetails with allocation but is distinct: composition is "what kinds of *accounts* make up my net worth," allocation is "what *asset classes* my whole position is distributed across" per the §2.2 framing). Composition buckets are user-meaningful, not Plaid-derived (see Appendix A). Drill-down stops at the account level by design — holdings live in §2.2, transactions live in §2.3.

#### Supporting stories

> **2.1.6 Investment net worth uses current market value.**
> As the self-directed multi-account owner, I want my investment account contributions to net worth to use current market value, so that net worth reflects what my holdings are actually worth today — not what I paid for them.
>
> *Traces to:* ADR-002 §1.7. The cost-basis comparison surface lives in §2.2 or a future investment-detail view; net worth uses market value.

> **2.1.7 Net worth is mine, not anyone else's.**
> As the self-directed multi-account owner, I want my net worth view to show only my own accounts and their data, with no possibility of another user's data appearing in my view. I want those accounts aggregated into a single full-household NAV by default, spanning every ownership scope I hold (e.g., personal, trust, retirement custodial, HSA). Together these give me a number I can trust absolutely, that reflects my entire household position the way I do today, and that honors the system's multi-tenant commitment from day one even though V1 ships to a single user. Per-scope reporting (one NAV per scope) and scope-aware filtering UI are V2+, not V1; the data model carries scope on each account from V1 (per ADR-004 Decision B) so the V2 expansion ships without a data migration.
>
> *Traces to:* ADR-002 §1.4 (multi-tenant from day one — tenant_id isolation foundational); **ADR-004 Decision B** (multi-scope ownership Rich / Trust / IRA / HSA is a V1 data attribute on accounts within a single tenant; V1 default report scope = full-household; per-scope reporting surfaces and scope-aware UI filtering are V2+). Jurisdictional scope of the NAV calculation (Federal + California per ADR-004 Decision D, US-domiciled per §1.4 deferrals) is established in §2.1.1 and is not re-litigated here — this story addresses tenant isolation and household-scope aggregation, not jurisdictional scope. **Flagged for Security Reviewer** per §8.0 (multi-tenant data isolation) — this section cannot move from draft to locked without a Security Reviewer pass; the Security Reviewer pass should additionally confirm that the multi-scope data attribute (per Decision B) is treated as a user-owned data label and not as a V1 isolation boundary (scopes are not tenants).

#### Open routing flags affecting §2.1

- **Architect — manual-vs-Plaid sourcing for net-worth contribution.** When an account is manual (no Plaid coverage) or in re-auth, what value contributes to current net worth and to the time series — last-known-good, user-entered most recent, zero, omitted? ADR-002 §1.5 establishes manual contributes; the exact contribution rule is an architectural decision. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Architect — period aggregation for the time series.** The multi-granularity expectation (monthly default + weekly/daily override) means the storage model needs to support either pre-aggregated multiple-resolution storage or on-the-fly aggregation from a finer underlying resolution. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Architect — historical NAV depth in V1 (how, not whether).** V1 imports the existing Google Sheet's monthly NAV history (Dec-2015 forward) so the 5-Year horizon in 2.1.3 is meaningful at launch — F/CTO has locked the *whether*. Open architectural questions: import mechanism, validation strategy, schema location, and whether per-asset-category NAV breakdown imports alongside total NAV. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Architect — CPI-U source.** Live API (e.g., FRED, BLS public API) vs. manual user entry, with cadence, historical depth back to the Dec-2015 NAV anchor, and freshness expectations. Required for both the §2.1.3 panel Inflation Adjusted column and the §2.1.2 chart-overlay inflation-adjusted view. Parity-matrix open product decision #10. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Security Reviewer — multi-tenant isolation language (2.1.7).** Mandatory pass before §2.1 locks.
- **PM follow-up — §2.1.2 chart-overlay inflation-adjusted clause (parked for §2.1 lock).** §2.1.2 currently has no inflation-adjusted clause. Needs extension to add a chart-overlay view (single line, normalized to today's $, 60-month rolling window per parity-matrix line 77) consuming the CPI-U series flagged above. Pickup at §2.1 lock time.

#### Acceptance flags

- Each story is a user-facing capability statement, not an implementation specification. Acceptance criteria (the testable conditions) get decomposed in Phase 4 / Linear, not in the PRD.
- §2.1 is **draft, not locked** until the Security Reviewer flag on 2.1.7 is cleared. The Architect flags can resolve in parallel during Phase 3; they do not block the PRD section from locking, but they need to be visible in Appendix B before sign-off.

### 2.2 Asset allocation

### 2.3 Spending and income categorization

### 2.4 Cross-cutting stories (account onboarding, manual entry, re-auth)

## 3. Success metrics

## 4. Security and compliance posture

> **Locking precondition:** Security Reviewer pass required before this section moves from draft to locked.

## 5. V2 deferred candidates

## 6. Out-of-scope for this PRD lifecycle

> Per ADR-002 §3.0, items here are scoped out of the current PRD lifecycle, not declared permanent non-goals.

## 7. Constraints

### 7.1 Cost

### 7.2 Scale

### 7.3 Usage model (single-user V1, invite-only forward-compat)

## Appendix A — Traceability to ADR-002 verdicts

## Appendix B — Open routing flags (Architect / Security Reviewer)

## Changelog
