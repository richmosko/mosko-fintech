# BACKLOG — mosko-fintech

V2+ deferred candidates plus the Linear overflow queue. **Created in PR B per [ADR-009](DECISIONS.md#adr-009) Decision 4** as the relocation home for PRD §5 content; serves a second role as the Linear overflow queue per ADR-009 Decision 7's feature-flow scheme (`[PRD §2 User Stories] → [BACKLOG.md] → [Linear ≤200 hot] → [Linear: Done] → [MILESTONES.md Completed]`).

**Conventions:**
- §5.x sub-section grouping mirrors PRD §2.x source order (§5.1 net-worth deferrals from §2.1 / §5.2 allocation from §2.2 / etc.).
- Every entry traces to an existing §2.x V1/V2 clause or an ADR-locked deferral (per §5 framing — §5 introduces no new V2+ items).
- **§5 / §6 distinction (sharp):** §5 = capabilities **on** the eventual product trajectory (locked V2+ in V1 to preserve drop-replace-migration scope); §6 = permanent product-identity non-goals (see [`docs/PRD/index.html` §6](docs/PRD/index.html#sec-6); not in this file).
- Last updated: 2026-05-23 (PR B migration; content frozen at PRD lock 2026-05-18 / v1.30).

---

## §5 framing — capabilities on the eventual trajectory

§5 is the consolidation home for the V2+ deferred capabilities surfaced across the V1 PRD lifecycle — every V1/V2 boundary clause in PRD §2.1 → §2.6 and the deferral surfaces created by the relevant ADRs (ADR-002 Finding (b); ADR-004 Decisions A–D; ADR-005; ADR-006; ADR-007). The §5/§6 axis is sharp: §5 enumerates capabilities that **are** on the eventual product trajectory — locked-as-V2+ in V1 to preserve the single-user drop-replace-migration scope but anticipated as legitimate later work; §6 enumerates capabilities that are **not** in this PRD's universe at all (see PRD §6 for the full axis enumeration — five permanent product-identity axes per ADR-002 §3.0 + ADR-007). "Later" vs "not in this PRD's universe" is the operative distinction. §5 is to *capabilities* what §3.5 is to *measurement frames* — both make the V1 perimeter visible by its complement and prevent re-litigation of settled scope decisions. §5 introduces no new V2+ items; every entry traces to an existing §2.x V1/V2 clause or an ADR-locked deferral.

---

## §5.1 — Net-worth deferrals

- **User-configurable time-axis controls on NAV surfaces.** V1 fixes the §2.1.2 NAV-over-time rolling window (60 months), the §2.1.3 multi-horizon NAV-delta horizon set (Month / YTD / 1-Yr / 3-Yr / 5-Yr), and the §2.1.4 NAV-at-reference-dates set (This Month / Prior Month / Prior Year-End). User-configuration of any of these three V1-fixed sets is V2+ per the §2.1.2 / §2.1.3 / §2.1.4 V1/V2 clauses. Deferral rationale: V1 calibrates against the existing-system Finance_Report fixed shape for parity-grounded migration; configurability is post-parity-soak expansion.
- **Per-scope NAV reporting + scope-aware UI filtering.** §2.1.7 V1/V2 (ADR-004 Decision B). V1 data model carries scope on every account from V1 bootstrap so the V2 expansion ships without a data migration; V1 UI is full-household-only. Per-scope NAV views, per-scope NAV-over-time charts, and scope-filtering affordances on §2.1 surfaces are V2+.
- **Per-tenant CPI-U source override.** V1 settles on a single CPI-U sourcing decision per Architect Phase 3 routing flag at §2.1 (live API vs. user-managed seed); per-tenant override that lets the user choose between CPI-U sources or supply a custom inflation series is V2+. Deferral rationale: single-user V1 has no use case for per-tenant CPI-U divergence; V2+ multi-user expansion may surface it.
- **Historical NAV import beyond V1 Dec-2015-forward parity import.** V1 imports the F/CTO's existing Google Sheet monthly NAV history from Dec-2015 forward as the parity baseline (§2.1.3 trace; Architect routing flag at §2.1 for the import mechanism). User-facing historical NAV import surfaces beyond this V1 parity import (bulk CSV import of NAV history for new tenants in V2; user-driven historical correction workflows) are V2+.

---

## §5.2 — Allocation deferrals

- **User-editable asset-taxonomy CRUD UI.** §2.2.1 V1/V2 (ADR-004 Decision C). V1 seeds the F/CTO's two-level asset taxonomy (6 Cat × ~35 Sub-Cat) at bootstrap and ships the holding-to-bucket assignment UI, but taxonomy editing (create / rename / delete Cat or Sub-Cat) happens via migration / direct database access in V1. V2 adds the editing UI.
- **Auto-generated rebalance suggestions.** §2.2.2 V1/V2 (ADR-002 §1.1 + ADR-004 Decision A). V1 ships the visualization-only `$ ReAlloc` gap layer; the recommendation engine that says "sell $X of VTI and buy $Y of VOO" — including tax-lot-awareness, account-type awareness, brokerage-workflow adjacency — is V2+. Deferral rationale: archetype attribute #4 (decisional posture) treats V1 as observational tool; auto-generated rebalance suggestions cross into prescriptive surface that requires a separate scope expansion.
- **Ex-US sub-allocation drill-down.** §2.2.3 V1/V2. V1 ships only the US Equity sub-allocation table matching existing Finance_Report structure; a parallel drill-down for international equity Sub-Cats (ExUS-Developed_Market, ExUS-Emerging_Market) is V2+.
- **Per-scope allocation views + scope-aware filtering UI across §2.2 surfaces.** §2.2.4 V1/V2 (ADR-004 Decision B). Per-scope allocation tables, per-scope `$ ReAlloc` deltas, and scope-aware UI filtering across the allocation surface are V2+; V1 data model carries scope from V1 so V2 expansion ships without migration.
- **Per-account taxonomy overrides.** V1's two-level taxonomy is one-per-tenant (per ADR-004 Decision C hybrid operationalization); account-specific Sub-Cats unique to a single account's workflow are V2+. Parallel pattern to §5.3 per-account taxonomy override V2+.
- **General drill-down view capability across allocation surfaces.** §2.2.3 V1/V2 forward-compat consideration. Whether V1's allocation-view layer supports drill-down as a general capability (any Sub-Cat → own sub-rows) versus hardcoded US Equity special case is Architect Phase 3; user-extensible drill-down is V2+ regardless.

---

## §5.3 — Cash-flow deferrals

- **User-editable cash-flow-taxonomy CRUD UI.** §2.3.1 V1/V2 (ADR-004 Decision C). Parallel to §5.2's asset-taxonomy CRUD V2+; V1 seeds the cash-flow taxonomy (Income / Expenses / OtherCF / AcctSetup × user Sub-Cats) and ships the transaction-to-bucket assignment UI, but taxonomy editing happens via migration in V1.
- **Budget tracking mechanics.** §2.3.2 V1/V2 (ADR-002 §1.2 + ADR-005). V1 ships static reference-value rendering of two user-authored aggregate targets (one income, one expense) inline in §2.3.2 captions with no variance computation. V2+ delivers (per ADR-002 §1.1 broader budget-tracking-with-goal-setting surface):
  - Actual-vs-target variance computation.
  - Threshold alerts and category notifications (feature-class within this V2+ surface).
  - Category-level rolling budgets.
  - Per-category target authoring beyond aggregates.
  - The broader budget-tracking-with-goal-setting surface itself.
- **Rule-based auto-categorization beyond recurring-vendor inference.** §2.3.2 V1/V2. V1 ships Plaid-category suggested default + recurring-vendor inference (same-merchant → suggest last-assigned Sub-Cat per §2.3.1 ζ lock). User-authored category-assignment rules with regex / pattern matching beyond simple recurring-vendor inference are V2+.
- **Per-account taxonomy overrides.** §2.3.3 V1/V2. Account-specific Sub-Cats that don't exist in the global taxonomy are V2+.
- **Per-scope cash-flow rendering + scope-aware filtering UI.** §2.3.5 V1/V2 (ADR-004 Decision B). Per-scope rollups, per-scope drill-downs, and scope-aware filtering across §2.3.2 / §2.3.3 / §2.3.4 surfaces are V2+; data model carries scope from V1.
- **Income time-series chart + multi-year historical income recordkeeping.** §2.3.4 V1/V2 (F/CTO 2026-05-14 (α) lock). V1 ships expenses-only Historical Expenditures chart; mirror income time-series chart and the underlying multi-year income retention are V2+. Deferral rationale per §2.3.4 body: realized capital gains from rebalancing partially fund expenses, so an expenses-over-time chart isolates the expense signal cleanly while an income-over-time mirror would entangle income with realization decisions.
- **Historical Expenditures chart extensions.** §2.3.4 V1/V2. User-configurable chart horizon (V1 fixed at 5-year rolling), chart drill-down into specific months or Sub-Cats, and authored target reference line on the chart are V2+.
- **Non-monthly and custom-defined cash-flow periods.** ADR-002 §1.2 V2+ (pre-§2.3 lock). Weekly / quarterly / YTD defaults beyond V1's monthly default + V1-fixed Q1-Q4-YTD columns, and custom user-defined period scopes, are V2+.

---

## §5.4 — Cross-cutting onboarding / entry / re-auth deferrals

- **Auto-classification of new symbols from Plaid metadata.** §2.4.1 V1/V2. V1 surfaces Plaid security_type + description + ticker as recommendation hints in the notification-queue assignment UI but never auto-applies; full auto-classification without user confirmation is V2+ and requires metadata-accuracy evidence before the V1 commitment relaxes.
- **Onboarding workflow extensions.** §2.4.1 / §2.4.2 V1/V2. V1 ships single-account-at-a-time onboarding for both Plaid and manual paths. Bulk-connect-multiple-institutions (§2.4.1), bulk import for manual non-Plaid accounts (§2.4.2), and manual un-share of an already-shared Plaid account (§2.4.1) are V2+.
- **Pre-emptive notification surfaces.** §2.4.1 + §2.4.4 V1/V2. V1 ships in-app notification queue only for pending new-symbol assignments and persistent in-app banner only for re-auth state. Two distinct V2+ commitments with different Sec posture:
  - **Push / email / SMS notification of pending new-symbol assignments** (§2.4.1) is V2+. No Sec gate beyond standard V2 delivery-channel review.
  - **Pre-emptive Plaid re-auth reminders** (§2.4.4) are V2+ with **Sec consult required before V2 ship** — pre-emptive re-auth prompts expand the phishing-template surface (counterfeit re-auth prompt risk); per §2.4.4 lock the V1 reactive-only cadence trades a bounded stale-data window against a narrower phishing surface. Lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (i).
- **Manual transaction entry extensions.** §2.4.3 V1/V2. V1 ships single-transaction-at-a-time entry + generic AcctSetup mode. V2+:
  - CSV bulk-import of historical transactions.
  - Event-type-specific AcctSetup wizards (versus V1 generic AcctSetup).
  - Auto-reconcile on balance-match (B3 axis per F/CTO 2026-05-15 (i) lock).
  - Free-text rules-engine for auto-categorization beyond §2.3.1 recurring-vendor inference (cross-ref §5.3).
- **External valuation integrations (Zillow, KBB, etc.).** ADR-002 §1.5 V2+ (pre-§2.4 lock). V1 manual asset valuation is user-updated. External-source live valuation ingestion for held-away assets is V2+.
- **Plaid product expansions.** ADR-002 §1.3 + §1.9. Two distinct V2+ product surfaces:
  - **Plaid Liabilities** (APR, statement balance, principal / interest split, escrow, payoff projections — credit cards + loans).
  - **Plaid Income** (wage / income aggregation surface as primary V1 income source — V1 derives income from Plaid Transactions + Investments instead).
- **Plaid coverage and instrument-level mechanics.** ADR-002 §1.8 + §1.9 V2+. V1 treats all Plaid-surfaced security types uniformly at transaction-and-position level with security type as categorization attribute. V2+ instrument-level mechanics:
  - **Underlying instrument-mechanics axes** — derivative Greeks / intrinsic-value / complex lifecycle events; bond YTM / duration / accrued interest / coupon scheduling; tax-character decomposition for REITs / MLPs (K-1 partnership-character splits); structured-product specifics.
  - **Off-exchange crypto wallets, on-chain transactions, and mining / staking-as-income mechanics** (§1.9).
  - **DRIP-pair detection + "income realized in cash vs reinvested" display split** (§1.9).
  - **Per-security user-configurable allocation classification** (§1.9).
- **Tax-treatment refinements.** ADR-002 §1.6 V2+. HSA "tax-free conditional" classification refinement (sub-flag or fourth bucket reflecting medical-withdrawal constraint) is V2+; V1 three-way tagging (taxable / tax-deferred / tax-free) does not differentiate HSA's conditional shape.

---

## §5.5 — Estimated-tax deferrals

- **Auto-categorization and user-editable CRUD on tax attributes.** §2.5.1 V1/V2. V1 seeds Sub-Cat `tax_relevant` boolean + `tax_character` enum at bootstrap from F/CTO existing system (per ADR-006 Axis 2); editing is migration-only in V1. Two distinct V2+ surfaces:
  - **Auto-categorization of tax-relevant Sub-Cats** from Plaid metadata or heuristic.
  - **User-editable Sub-Cat tax-attribute CRUD UI** (additive to the broader §2.3.1 + §2.2.1 taxonomy CRUD V2+ surfaces).
- **Multi-year tax surfaces.** §2.5.1 + §2.5.2 V1/V2. V1 scopes the §2.5.1 three-column decomposition to current calendar year and holds a single current-tax-year bracket-schedule set in §2.5.2. V2+:
  - Multi-year historical Ordinary Income / ST CG / LT CG tracking + time-series chart (mirrors §5.3 income-time-series V2+).
  - Multi-tax-year bracket version history.
  - Bracket inheritance from prior tax-year.
  - Custom fiscal-year overrides.
- **Full Federal AGI-line decomposition (ζ-3).** §2.5.1 V1/V2. V1 ships the three-column Ordinary / ST CG / LT CG decomposition with `tax_character` routing per ADR-006 Axis 2; per-Sub-Cat mapping to Schedule B / Schedule D / Schedule E / etc. for full Federal AGI-line decomposition is V2+.
- **Wash-sale and Section 1256 auto-detection.** §2.5.1 V1/V2 (ADR-002 §1.7 + ADR-004 Decision D). V1 ships user-marked wash-sale flag and user-classification of Section 1256 60/40 via the `Volatility-60/40` Sub-Cat. Auto-detection of wash-sale rule application and Section 1256 60/40 classification is V2+.
- **Lot-level tax features.** ADR-002 §1.7 + ADR-004 Decision D V2+ (unchanged by ADR-006). V1 ships aggregate cost basis per position with average-cost-fallback realized G/L. V2+:
  - **FIFO / LIFO / specific-ID lot-matching** for tax purposes.
  - **Per-lot UI** (lot tables, holding-period indicators).
  - **Lot-level cost-basis reporting** on tax surfaces.
  - **Tax-loss harvesting recommendations are NOT included in this V2+ surface** — reclassified to §6 per ADR-007.
- **In-state-vs-out-of-state municipal-bond differentiation for CA FTB `tax_exempt_interest` routing.** §2.5.1 / §2.5.2 V1/V2. V1 treats all `tax_exempt_interest` uniformly for CA computation (excluded); California in-state-issuer vs. out-of-state-issuer differentiation is V2+.
- **Live tax-data API ingestion of bracket tables.** §2.5.2 V1/V2 (ADR-006 Axis 1). V1 user-manually updates Federal + California bracket schedules + standard deductions at tax-year rollover. V2+:
  - **Live API ingestion** (IRS / California FTB public rate-table sources).
  - **Diff / version-history awareness** on ingested bracket tables.
  - **Bracket-table import from external CSV / IRS publication sources.**
- **Multi-jurisdiction tax expansion.** ADR-002 §1.7 + ADR-004 Decision D V2+ (unchanged by ADR-006). Multi-state tax handling (any non-California state) and non-US tax handling (RRSP, ISA, foreign tax credits, etc.) are V2+. V1 supports Federal + California FTB only.
- **Filing-status enum.** §2.5.2 V1/V2 (ι lock). V1 carries a single standard-deduction scalar per jurisdiction applicable to F/CTO's current filing status (fixed at seed time). Filing-status enum (single / MFJ / HoH) with user-selectable filing-status at settings UI + multi-scalar standard deduction is V2+.
- **Bracket-aware tax credits and above-the-line deductions.** §2.5.2 V1/V2. V1 ships single standard deduction per jurisdiction; FTC, child tax credit, and other tax-credit handling beyond standard deduction are V2+.
- **Separate California LT CG schedule.** §2.5.2 V1/V2 (κ lock). V1 collapses CA LT CG to ordinary (no separate CA LT CG schedule); if existing-system divergence surfaces at V1 implementation, separate CA LT CG schedule is V2+.
- **Quarterly-installment-sizing refinements.** §2.5.3 V1/V2 (μ-2 lock). V1 ships bracket-derived expected-annual ÷ 4 only with no safe-harbor floor; Tax Balance Prior Year row appears as informational reference only. V2+:
  - **Safe-harbor floor computation** (Federal 100%/110%-of-prior-year + CA FTB safe-harbor rules).
  - **Alternative quarterly-installment-sizing** — μ-1 max-of bracket-derived-and-safe-harbor; μ-3 two-column rendering.
  - **Annualized-income installment method** (IRS Form 2210 method 2).
- **Withholding tracking.** §2.5.3 V1/V2. V1 simplification treats all incoming-tax-payments as "estimated payments" in the IRS / FTB ledgers; withholding (W-2 / 1099) tracked distinct from estimated payments is V2+.
- **Pre-emptive quarterly-payment-due-date reminders.** §2.5.3 V1/V2 (ξ-2 / ξ-3 V2+). V1 ships reactive in-table due-date surfacing with current-quarter visual emphasis. V2+:
  - **Pre-emptive in-app notifications** of quarterly due dates.
  - **Email reminders** of quarterly due dates.
  - **Calendar integration** for quarterly due dates.
- **Refund / overpayment surfacing extensions.** §2.5.3 V1/V2 (ν-2 V2+). V1 surfaces overpayment as negative single-line Estimated Funds Due (ν-1 lock). Separate "Refund Expected" line + distinct overpayment-status indicator is V2+.
- **Penalty computation and prior-tax-year computation surfaces.** §2.5.3 V1/V2. V1 ships no penalty computation; users responsible for understanding underpayment-penalty risk outside the system. Penalty computation against safe-harbor and prior-tax-year computation surfaces are V2+.
- **Bracket-aware Unrealized Tax Liability refinements.** §2.5.4 V1/V2 (ο-a lock). V1 Unrealized = simplified marginal × aggregate G/L per ο-a (Federal LT CG top-bracket rate × aggregate_unrealized_G/L_taxable + CA ordinary top-bracket rate × aggregate_unrealized_G/L_taxable; tax-advantaged accounts excluded per (π); `tax_character` enum routing NOT used on Unrealized; §2.5.3 engine NOT consumed by Unrealized). V2+:
  - **ο-b — Full bracket-aware as-if-realized.** Treat all aggregate unrealized G/L as if realized today, run through §2.5.3 progressive bracket computation engine with ST/LT split via §2.4.3 Open Date and `tax_character` enum routing.
  - **ο-c — Hybrid LT-only bracket-aware.** ST CG portion treated as marginal × G/L; LT CG portion runs through Federal LT CG bracket schedule.
  - **Federal-ordinary-top-bracket-rate as more-conservative alternative for the Federal_marginal_rate factor** — would treat unrealized G/L as marginal additional ordinary income rather than as LT capital gain.
- **Per-jurisdiction split rendering of Realized + Unrealized as separate lines.** §2.5.4 V1/V2 (ρ-2 V2+). V1 surfaces single combined-jurisdiction Realized scalar and single combined-jurisdiction Unrealized scalar on §2.1.5 composition. Per-jurisdiction Federal + CA split rendering on §2.5.4 + §2.1.5 is V2+.
- **Tax-deferred withdrawal-tax-liability as a fourth NAV-subtraction line.** §2.5.4 V1/V2. V1 (π) exclusion filters tax-deferred and tax-free accounts out of the `aggregate_unrealized_G/L_taxable` aggregation; tax-deferred account Unrealized "ordinary-income-on-withdrawal" treatment as a separate "deferred tax obligation" line, and withdrawal-tax-liability for tax-deferred accounts as a fourth NAV-subtraction line item, are V2+.
- **REIT / MLP K-1 partnership-character splits on unrealized G/L.** §2.5.4 V1/V2 (ADR-002 §1.8 V2+). Cross-ref §5.4 instrument-level mechanics deferral.
- **Multi-state Unrealized Tax Liability sourcing.** §2.5.4 V1/V2. Parallel to multi-jurisdiction tax expansion V2+.
- **Monte Carlo longevity modeling.** ADR-002 Finding (b). Projection / scenario surface for retirement / longevity planning; observational tool within §1.2 archetype attribute #4 framing.
- **Stock screening — possibly a separate tool rather than mosko-fintech scope.** ADR-002 Finding (b). The "possibly a separate tool" hedge from Finding (b) is preserved verbatim: this V2+ line is not a commitment to ship within mosko-fintech, only that it's not V1.

---

## §5.6 — Monthly-report deferrals

- **User-configurable section ordering and composition.** §2.6.1 V1/V2 (ω-2 / ω-3). V1 ships fixed six-section sequence (Account Holdings → NAV Performance → Asset Allocation → Rebalancing Targets → Cash Flow → Estimated Taxes). V2+:
  - **User-configurable section ordering** — add / remove / hide sections via settings UI + user-selectable section visibility per-report + user-defined custom sections beyond the six.
  - **Reintroduction of Big Ticket Fund / Amortized Expenses** if F/CTO revisits the Phase 0.5 drop.
  - **Alternative inline-vs-standalone placement of Historical Expenditures.**
  - **Alternative cross-section composition** that decouples report sections from §2.1 – §2.5 live-surface boundaries (e.g., year-over-year comparison view).
- **Multi-scope reports.** §2.6.1 + §2.6.6 V1/V2 (parity-matrix line 180; ADR-004 Decision B). V1 default report scope is full-household with a single per-tenant owner-identification header; per-scope report variants (one report per scope, each with its own owner-identification header per ψ-2 multi-named-owner config) are V2+.
- **Auto-generated and hybrid Rebalancing Targets commentary.** §2.6.2 V1/V2 (σ-2 / σ-3). V1 ships σ-1 free-text user-authored commentary under four V1-fixed sub-sections (Cash / Bonds / Equity / Alternatives). Auto-generated commentary from §2.2.2 `$ ReAlloc` positive-delta rows (σ-2) and hybrid-with-edit (σ-3) are V2+; both require ADR-004 Decision A amendment. Per-asset-class sub-section template prompts as authoring scaffolding are V2+.
- **Rebalancing Targets editor extensions.** §2.6.2 V1/V2. V2+:
  - **User-configurable sub-sections** (rename / add / remove / reorder) paralleling §2.2.1 taxonomy-CRUD V2+.
  - **Markdown / rich-text formatting affordances** on the editor (bold / italic / lists / headings / inline links).
  - **Auto-pre-population of new-month commentary editor from prior-month content** as default behavior, plus a settings toggle to choose blank-vs-auto-copy as per-tenant default.
  - **Late-edit / amend-after-generation flows** on historical-month commentary with explicit revision tracking.
- **Generation-cadence and trigger extensions.** §2.6.3 V1/V2. V2+:
  - **User-configurable cron schedule** (date + time-of-day).
  - **Per-jurisdiction tax-aware quarter-end adjustments to cron cadence.**
  - **Alternative cron cadences** (weekly / quarterly / annual companion artifacts).
  - **Automated cron-retry + partial-run recovery.**
  - **In-app cron-failure notification to the user.**
  - **Alerting / monitoring infrastructure beyond system-level logging.**
- **Revision history for regenerated months.** §2.6.3 + §2.6.4 V1/V2. V1 ships overwrite-semantics regeneration (one snapshot per `(tenant, target-month)`, last-writer-wins, no prior revision retained). Revision-history-aware snapshot storage and "regenerate with revision-history" user-triggered flow are V2+. Resolves the §2.6.2-vs-§2.6.3 persistence-tension noted at §2.6.3 lock.
- **Alternative delivery channels — email / SMS.** §2.6.3 V1/V2. **Forward-Sec-consult flag (carry-forward to V2 scoping):** email / SMS delivery of generated reports introduces a new delivery channel V1 does not exercise — report content rendered into transit message body is a new sensitive-data exfiltration surface (especially over SMS, which is plaintext); Sec re-engagement required before V2 ship. Lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (ii).
- **Alternative delivery channels — shared-link to external viewers.** §2.6.3 V1/V2. **Forward-Sec-consult flag (carry-forward to V2 scoping):** shared-link delivery intersects multi-tenant + access-control scope and may overlap §6 advisor-role boundary; Sec re-engagement + possible ADR re-litigation against §6 advisor-role boundary required before V2 ship. Lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (iii).
- **Alternative output formats.** §2.6.3 V1/V2. V1 ships in-app rendered web page + on-demand PDF export (υ-1). V2+:
  - **Google Doc parity-exact** (the rejected υ-3 path, documented as V2+ optional companion if F/CTO revisits Google Workspace integration).
  - **Markdown export.**
  - **HTML email body.**
  - **Structured-data export** (JSON / CSV).
  - **Scheduled PDF auto-export to user storage** (Drive / Dropbox / S3 / etc.).
- **Drill-down from report sections to source surfaces.** §2.6.3 V1/V2. Drill-down from a section in the in-app view to its source PRD story / current-state surface (e.g., click NAV Performance → land on §2.1.2) is V2+.
- **Live-rendered date-filtered views of historical months.** §2.6.4 V1/V2 (φ-2 / φ-3). V1 ships φ-1 frozen-at-generation snapshot (parity-exact with existing-system Finance_Report PDF behavior); live-rendered date-filtered views of historical months and the φ-2 / φ-3 toggle complexity that supports them are V2+.
- **Snapshot-store retention and management extensions.** §2.6.4 V1/V2. V1 χ-1 retains every generated report indefinitely with no retention-window cleanup, archival-tier migration, or user-initiated deletion. V2+:
  - **User-initiated deletion of historical reports.**
  - **Automated retention windows** (e.g., retain 5 years then archive to cold storage).
  - **Archival-tier migration.**
  - **PDF caching.**
  - **Source-data-level snapshots** (re-renderable from underlying transactions, versus V1 rendered-value-level snapshots).
- **Owner-identification header extensions.** §2.6.4 V1/V2 (ψ-2 / ψ-3). V1 ships ψ-1 single per-tenant owner-identification string driving every report's header. Multi-named-owner config (ψ-2), per-report header override at generation time (ψ-3), and multi-line / rich-text owner-identification headers are V2+. ψ-2 specifically anticipates V2+ multi-scope reports.
- **Staleness-marker extensions.** §2.6.5 V1/V2. V1 ships α′-1 generate-with-markers with inline per-section indicator + report-level summary banner, uniform across all four §2.4.4 credential-error states, with live-read at render time. V2+:
  - **Per-credential-error-class differentiated marker visuals.**
  - **"Block with warning" mode** as user-selectable preference.
  - **User-initiated dismiss / acknowledge of staleness markers per report.**
  - **Staleness-history layer** showing when an account went stale relative to the report's as-of date.
  - **Marker-state snapshotting** — recording staleness state at generation time alongside the snapshot for a historical-audit V2+ feature.

---

## §5.7 — Cross-cutting V2+

- **Multi-user invite-only V2 expansion.** ADR-002 §1.4 V1-to-V2 transition. V1 ships to a single user (the F/CTO) on a multi-tenant data model with `tenant_id` on every user-data table, RLS policies enforced, and multi-tenant-capable auth infrastructure from day one. V2 adds the second user via invite-only onboarding; the V1 forward-compatibility commitment is that no data migration of V1 user data is required when the second user lands. V2+:
  - **Friends-and-family onboarding.**
  - **Invite-flow UI.**
  - **Multi-user auth gates.**
  - **Per-user data-access boundary checks.**
  - Cross-reference: §7.3 (usage model: single-user V1, invite-only forward-compat) references this entry.
- **Multi-currency.** ADR-002 §3.0 reclassification from non-goal to V2+ deferral. The "in V1" qualifier in the original finding made multi-currency a deferral, not an identity statement; mixing it into the out-of-scope list was rejected as weakening the discipline of both buckets. V1 is USD-denominated. V2+:
  - **Multi-currency holdings.**
  - **Multi-currency transactions.**
  - **FX conversion surfaces.**
  - **Per-tenant base-currency selection.**

---

## Linear overflow queue

Per ADR-009 Decision 7's feature-flow scheme, BACKLOG.md doubles as the overflow queue *above* Linear's ≤200-hot working set:

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

**Promotion mechanic.** `/sync-backlog` (adopted now per ADR-009 Decision 7 skill-suite phasing) promotes batches from this file into Linear at sprint boundaries. The §5.x deferrals above become the seed pool of V2-trajectory candidates the overflow queue draws from once V1 ships and V2-scoping work begins. Until V2-scoping, the §5 sub-sections function as forward-looking catalog only — no entries promote to Linear during M0/M1.

**Cross-references.**
- [PRD §2 user stories](docs/PRD/index.html#sec-2) — the intent funnel above this queue.
- [MILESTONES.md](MILESTONES.md) — the post-promotion state ledger (compact head; live state of done work).
- [DECISIONS.md ADR-009](DECISIONS.md#adr-009) Decision 7 — feature-flow scheme + initial milestones.
- [docs/SECURITY/index.html](docs/SECURITY/index.html) §4.6 — Sec V2-ship-gate inventory (subset of §5 entries above with mandatory Sec-consult-before-V2-ship gates).

**Forward-routing flags** (from PRD §5 lock, preserved for traceability):

- **§5 routing flag (a) — Sec V2-implementation:** Pre-emptive Plaid re-auth reminders pre-V2 ship (lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (i)).
- **§5 routing flag (b) — Sec V2-implementation:** Email / SMS delivery of monthly reports pre-V2 ship (lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (ii)).
- **§5 routing flag (c) — Sec V2-implementation:** Shared-link delivery of reports pre-V2 ship (lands at [docs/SECURITY](docs/SECURITY/index.html) §4.6 V2-ship-gate inventory item (iii)).
- **§5 routing flag (d) — Closure-trace:** TLH home is §6 (advisor/fiduciary axis) per ADR-007; reclassified from V2+ trajectory to permanent non-goal. Not listed in §5; see [PRD §6.3](docs/PRD/index.html#sec-6-3).
- **§5 routing flag (e) — Closure-trace:** §5 → §7.3 cross-reference closed at §7.3 lock (§5.7 multi-user expansion intersects §7.3 usage-model framing).
- **§5 routing flag (f) — Architect V2-scoping:** V2+ items requiring schema or migration scope decisions — general flag for Architect assessment at V2-scoping time (post-V1 ship). No V1 block.

---

*Last updated: 2026-05-23 (PR B migration; §5 content frozen at v1.30 PRD lock 2026-05-18). Edit via `/start-doc-update <slug>` per ADR-009 Decision 9 (`meta/` branch prefix — BACKLOG.md is a state-ledger file).*
