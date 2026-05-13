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
- **Precise about categorization.** They maintain deliberate, multi-level taxonomies for the holdings they own and the activity they generate. A coarse-bucket tool that summarizes "you have $X in equities" without distinguishing US-sector / international / index-vs-growth would be unusable to them.
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

> **2.1.1 Current net worth.**
> As the self-directed multi-account owner, I want to see my current total net worth — the sum of all asset balances minus the sum of all liability balances, across every account I hold — so that I have a single trustworthy number that reflects my whole financial position at a glance, without doing the arithmetic across institutions myself.
>
> *Traces to:* ADR-002 §1.0 (net worth ratified as a V1 surface), §1.3 (V1 transaction-tracking expansion across depository, credit, investment, loan-balance, crypto accounts — every account category contributes), §1.5 (manual non-Plaid accounts contribute), §1.9 (per-account-type boundaries determine how each account's balance is sourced and signed).

> **2.1.2 Net worth over time.**
> As the self-directed multi-account owner, I want to see how my net worth has changed over time, displayed as a time series with a monthly default and the ability to view weekly or daily granularity on demand, so that I can understand whether my overall financial position is improving, holding, or declining over a meaningful horizon — and so I can drill into shorter periods when I'm investigating a specific inflection point.
>
> *Traces to:* Preliminary finding (a) "over time" framing, ratified in ADR-002 §1.0. Granularity hybrid (monthly default with weekly/daily override) is a V1 product expectation; the architectural cost of supporting multiple granularities is acknowledged and routed to Architect.

> **2.1.3 Net worth headline delta.**
> As the self-directed multi-account owner, I want my current net worth to be displayed alongside a headline delta — always at least a month-over-month delta (e.g., "$X net worth, ▲/▼ $Y vs. 1 month ago, Z%"), and additionally a delta matching the chart's current granularity when I've switched the chart to weekly or daily — so that I can see at a glance whether my position is moving in the direction I expect over my normal decision cadence, and so that when I'm investigating a specific recent change I get a matching delta without re-reading the chart.
>
> *Traces to:* ADR-002 §1.0 (net worth is a V1 surface); paired with the granularity hybrid in 2.1.2 (monthly default + weekly/daily override). The monthly delta is the always-on anchor; the second granularity-matched delta appears only when the chart is at non-monthly granularity. This is a V1 capability — explicit "compare vs. arbitrary date" surfaces are V2.

> **2.1.4 Net worth composition.**
> As the self-directed multi-account owner, I want to see what my net worth is composed of — broken down into assets vs. liabilities, and within assets, into the account-type categories (depository, investment, retirement, crypto, manual/other) — so that the single number in 2.1.1 doesn't hide its structure, and so I can see at a glance which categories are driving the total or its change. I want to be able to expand any category one level to see the individual accounts contributing to it, so that when a category is moving I can identify which specific account is responsible without leaving the composition view.
>
> *Traces to:* ADR-002 §1.9 (per-account-type boundaries are first-class), §1.0 (asset allocation is a V1 surface — composition view dovetails with allocation but is distinct: composition is "what kinds of *accounts* make up my net worth," allocation is "what *asset classes* my whole position is distributed across" per the §2.2 framing). Composition buckets are user-meaningful, not Plaid-derived (see Appendix A). Drill-down stops at the account level by design — holdings live in §2.2, transactions live in §2.3.

#### Supporting stories

> **2.1.5 Investment net worth uses current market value.**
> As the self-directed multi-account owner, I want my investment account contributions to net worth to use current market value, so that net worth reflects what my holdings are actually worth today — not what I paid for them.
>
> *Traces to:* ADR-002 §1.7. The cost-basis comparison surface lives in §2.2 or a future investment-detail view; net worth uses market value.

> **2.1.6 Net worth is mine, not anyone else's.**
> As the self-directed multi-account owner, I want my net worth view to show only my own accounts and their data, with no possibility of another user's data appearing in my view, so that I can trust the number absolutely and so the system honors its multi-tenant commitment from day one — even though V1 ships to a single user.
>
> *Traces to:* ADR-002 §1.4 (multi-tenant from day one); **flagged for Security Reviewer** per §8.0 (multi-tenant data isolation) — this section cannot move from draft to locked without a Security Reviewer pass.

#### Open routing flags affecting §2.1

- **Architect — manual-vs-Plaid sourcing for net-worth contribution.** When an account is manual (no Plaid coverage) or in re-auth, what value contributes to current net worth and to the time series — last-known-good, user-entered most recent, zero, omitted? ADR-002 §1.5 establishes manual contributes; the exact contribution rule is an architectural decision. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Architect — period aggregation for the time series.** The multi-granularity expectation (monthly default + weekly/daily override) means the storage model needs to support either pre-aggregated multiple-resolution storage or on-the-fly aggregation from a finer underlying resolution. Routing: ADR-002 §8.0 Architect flag, non-F/CTO-led.
- **Security Reviewer — multi-tenant isolation language (2.1.6).** Mandatory pass before §2.1 locks.

#### Acceptance flags

- Each story is a user-facing capability statement, not an implementation specification. Acceptance criteria (the testable conditions) get decomposed in Phase 4 / Linear, not in the PRD.
- §2.1 is **draft, not locked** until the Security Reviewer flag on 2.1.6 is cleared. The Architect flags can resolve in parallel during Phase 3; they do not block the PRD section from locking, but they need to be visible in Appendix B before sign-off.

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
