# PR 2 — §1 rewrite body preview (round 2, post §1 β override)

> Standalone preview of the proposed rewritten §1, extracted from Part 2 of `docs/prd-rewrite-pr2-proposal.md` (round 2) for rendered viewing.
>
> **Round 2 incorporates 4 substance amendments per the §1 β override** (WORKFLOW.md v1.19 R6 carve-out):
> - NEW §1.1 "Problem statement" sub-section
> - Renumbered §1.1–§1.4 → §1.2–§1.5
> - Archetype rename: "self-directed multi-account owner" → **"Independent Investor"**
> - Cross-ref retargets cascade (PRD.md:47 → §1.4; PRD.md:58 → §1.5)
>
> This is the markdown that will land in `PRD.md` §1 on PR 2 merge. Compare against `docs/archive/PRD-v1.18-source.md` §1 (archive lines 17–58) to verify presentation-fidelity in §1.2–§1.5; §1.1 is NET-NEW substance with no source equivalent.

---

## 1. Vision and target user

### 1.1 Problem statement

The **Independent Investor** spends too much time on the manual mechanics of compiling their financial picture — pulling balances, reconciling transactions, applying their own categorization across institutions, and assembling the inputs that produce the metrics they actually reason about — before any of that work yields the clarity it's supposed to support.

- **What gets calculated by hand today.** Cash-flow rollups across many accounts, asset-allocation aggregations against personal taxonomies, net-worth composition adjusted for tax obligations, and quarterly estimated-tax obligations — each derived from raw transaction and holdings data that no single institution dashboard captures.
- **What the manual process costs.** Time spent assembling and reconciling rather than reviewing and deciding; data and process errors introduced by spreadsheet-and-formula plumbing whose correctness depends on the user maintaining it perfectly month after month; loss of confidence in derived metrics when the assembly mechanics drift.
- **What mosko-fintech aims to be.** A streamlined personal financial observatory that does the assembly and reconciliation work, surfacing the metrics — net worth, asset allocation against target, monthly categorized cash flow, estimated tax obligations — in a form the user can review and act on, without performing the underlying mechanics themselves.

### 1.2 Vision

mosko-fintech is a personal financial observatory: a single trustworthy view of one individual's complete financial position across every account they hold, plus the activity and derived measures that make that position meaningful.

- **What V1 is.** Aggregated account coverage (checking, savings, credit, brokerage, retirement, loans, crypto) with transactions, investment flows, and derived measures (net worth, asset allocation, monthly spending and income by category, estimated taxes).
- **What V1 is not.** Observational only — it surfaces the user's position and the gap between target and actual allocation; it does not move money, generate buy/sell recommendations, or act in any advisory capacity. The goal is clarity in the user's own hands: the user decides, the tool shows.
- **What "V1 done" means.** Functional parity with the working manual-spreadsheet system the V1 instance maintains today, with the **monthly Finance Report** as the canonical deliverable. V1 progressively replaces that system rather than running alongside it.

### 1.3 Target-user archetype

The V1 target user — the **Independent Investor** — is a financially-engaged individual with a fragmented multi-account portfolio that no single bank or brokerage view covers and that public consumer-finance tools tend to oversimplify or misrepresent.

The archetype has the following defining attributes:

- **Multi-institution footprint.** Accounts spread across multiple banks, brokerages, retirement custodians, credit issuers, and at least one crypto venue. No single institution dashboard captures their position; aggregation is non-optional.
- **Mixed tax-treatment portfolio across multiple jurisdictions.** Holdings span taxable, tax-deferred, and tax-exempt accounts (and HSA, which is conditional on use). Tax thinking is jurisdictional — Federal and state (California, in the V1 instance) tax obligations are reasoned about in parallel, not as a single combined number. Tax treatment and jurisdiction are first-class attributes of how they think about money, not afterthoughts.
- **Holds investment securities, not just deposits.** Brokerage and retirement accounts contain equities, funds, fixed income, and possibly other instruments. They care about cost basis and unrealized gain/loss, not just balances.
- **Self-directed, with an observational tool.** They make their own financial decisions — portfolio allocation, rebalance timing, spending changes, account-level moves — and use this tool as input to those decisions, not as a source of them. They want to *see* their position clearly and *manage* the gap between target and actual allocation.
- **Precise about categorization.** They maintain deliberate two-level taxonomies — a top-level category and a sub-category — for both holdings (e.g., Equity → US-Index_Non_Sector; Bonds → T-bill; Alternatives → REIT) and cash-flow activity (Income, Expenses, and other flow types, each with their own sub-categories). A coarse-bucket tool that summarizes "you have $X in equities" without distinguishing US-sector / international / index-vs-growth would be unusable. They assign holdings and transactions to their buckets themselves and update those assignments as their portfolio evolves; the categorization grammar is theirs to define and theirs to apply.
- **Privacy- and control-conscious.** They are uncomfortable with consumer-finance tools that monetize their data, push affiliate products, or surface "insights" that are really marketing. They prefer a tool they own, that holds their data on their terms.
- **Comfortable with substantial manual curation.** They maintain their financial system actively, by hand, on a monthly cadence — entering or reconciling transactions, refreshing valuations on held-away assets, and curating the taxonomies that categorize what they own. They will not tolerate a tool that pretends the un-aggregated accounts don't exist, and they accept that some accounts and asset classes will continue to require manual entry indefinitely.

The Founder/CTO is the V1 instance of this archetype. V1 is built for and validated by a population of one.

### 1.4 Why an archetype, not the F/CTO by name

The PRD frames the target user as an archetype rather than as the Founder/CTO personally because three locked decisions in `DECISIONS.md` make the archetype framing load-bearing rather than aspirational:

1. **Multi-tenant from day one** (ADR-002). The data model, auth boundary, and isolation guarantees treat the user identity as a first-class entity from V1. Tying the PRD to a single named person would be a fiction the architecture explicitly refuses to maintain.
2. **Forward-compatibility commitment** (ADR-002). V2+ broadens distribution to invite-only — a small cohort of Independent Investors. Defining the archetype now means V2 inherits a known target population rather than re-litigating who the next users are.
3. **Single-user usage model in V1** (ADR-002). The archetype framing does not contradict this. V1 ships with one user (the Founder/CTO) actively using it. The archetype is the *shape* of the user the product is designed for; the V1 *instance* of that shape is the Founder/CTO. The two are deliberately decoupled.

The practical consequence:

- **V1 success** = "this works for the Founder/CTO specifically."
- **V1 product correctness** = every requirement traces to an attribute of the archetype, not to a one-off preference. When the two conflict — when a Founder/CTO preference is not a generalizable archetype attribute — the conflict surfaces as a flag for V1.0/V1.1 milestone-sequencing decisions (Phase 4 territory, not this section's problem).
- **V1 existing-system-replacement test.** Per the §8 V1-done definition (anchored at §3.4), V1 is correct when it replicates the workflows the F/CTO maintains today in the manual-spreadsheet system, plus the explicit ADR-004 amendments.

### 1.5 Deferred user-shape questions

To keep the archetype defensible and avoid scope creep into adjacent personas, the following user-shape questions are explicitly **deferred**, not silently elided:

- **Household and joint-account semantics.** The V1 archetype is individual-scoped. Joint accounts owned with a spouse or partner appear in V1 as accounts the individual has access to, not as a multi-owner data model. Multi-scope ownership *within* a single user's household (multiple legal-ownership scopes such as personal, trust, retirement custodial) is a V1 data attribute per ADR-004 Decision B. Household-level user-facing semantics (shared budgets, multi-owner net worth, partner visibility, per-scope user-facing reports) are out-of-scope for this PRD lifecycle and route to a future PRD revision if invite-only V2 demand surfaces.
- **Geographic, currency, and multi-jurisdictional tax scope.** V1 assumes a US-domiciled user with USD-denominated accounts. Multi-currency support is V2+ per ADR-002 reclassification. V1 tax handling is jurisdiction-specific to the V1 instance — US Federal plus California state — per ADR-004 Decision D. Multi-state and non-US tax handling (RRSP, ISA, foreign tax credits, etc.) are V2+.
- **Life-stage and goal-tracking framing.** The archetype is defined by what the user owns and how they think about their money today, not by retirement goals, savings targets, or life events. Goal-tracking is a candidate V2 surface; it does not shape the V1 archetype.
- **Advisor or accountant collaboration.** Read-only exports for an accountant at tax time are a candidate V2 feature, not an archetype attribute.

**Advisor/fiduciary carve-out.** The advisor/fiduciary role is treated separately: it is a **permanent product-identity non-goal** under the §6 advisor/fiduciary axis per ADR-002 §3.0 + ADR-007, not a deferred user-shape question. The other items above are scope boundaries for this PRD lifecycle (V2+ trajectory items revisitable at V2-scoping time); the advisor/fiduciary role does not return to scope without a §6 axis revision.
