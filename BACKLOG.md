# BACKLOG — mosko-fintech

Two-purpose backlog per [ADR-009](DECISIONS.md#adr-009) Decision 4 + Decision 7 and [ADR-017](DECISIONS.md#adr-017):

1. **§5 — V2+ deferred candidates** (PRD §5 relocation home; created in PR B per ADR-009 Decision 4). Capabilities on the eventual product trajectory but locked-as-V2+ in V1 to preserve drop-replace-migration scope.
2. **§7 — V1 staging queue** (going-forward from Wave 6 per [ADR-017](DECISIONS.md#adr-017) Decision 2). Per the narrowed feature-flow scheme: `[PRD §2 User Stories] → [BACKLOG.md §7] → [Linear: current + next milestone only] → [Linear: Done] → [MILESTONES.md Completed]`. Existing V1.0–V1.4 issues already in Linear (SELF-181 → SELF-269) stay there; milestone rotation handles them at Phase 5 implementation start. Wave 6 (V1.5) onward decompositions land in §7 with full Source / Acceptance criterion / Dependencies specs, then promote to Linear at milestone-rotation time.

**Conventions:**
- §5.x sub-section grouping mirrors PRD §2.x source order (§5.1 net-worth deferrals from §2.1 / §5.2 allocation from §2.2 / etc.).
- Every §5 entry traces to an existing §2.x V1/V2 clause or an ADR-locked deferral (per §5 framing — §5 introduces no new V2+ items).
- §7 entries carry the same fields a Linear issue would (Source / Acceptance criterion / Dependencies); promotion to Linear is verbatim with the entry marked "Promoted to Linear at SELF-N" as durable historical reference.
- **§5 / §6 / §7 distinctions:** §5 = V2+ capabilities on the eventual trajectory; §6 = permanent product-identity non-goals (see [`docs/PRD/index.html` §6](docs/PRD/index.html#sec-6); not in this file); §7 = V1 staging queue (going-forward, repo-versioned V1 work-spec for milestones not currently active in Linear).
- Last updated: 2026-06-03 ([ADR-017](DECISIONS.md#adr-017) §7 staging-queue framing added; §5 content frozen at PRD lock 2026-05-18 / v1.30).

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
  - Generic free-text "other" AcctSetup non-cash event entry (reserved per [ADR-033](DECISIONS.md#adr-033) Decision 3). Once **split** (→ `corp_action`) and **transfer-in-kind** (→ journal `group_type='transfer_in_kind'`) claim their cases, no distinct V1 "other" use case survives — a generic non-cash event reduces to a `standard` §2.3.1 cash-flow row classified by its Sub-Cat (Suspense-floored if uncategorized), so there is nothing distinct to build. V2+ if a genuine generic-event surface is later scoped.
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
  - **Sec re-consult MANDATORY at adoption** (per [ADR-011](DECISIONS.md#adr-011) Decision 18 / Lock 14 mod #8 advisory forward-compat fence). V2+ live-tax-API ingestion is a future privileged-context-write surface (§6 meta-pattern per ADR-011 Decision 1); inherits Lock 11 mod #2 cron tenant-binding + Lock 13 `TenantBoundConnection` discipline automatically when the surface lands. Activates the cross-tenant FK-bypass family chain (per ADR-011 Decision 3) on `pfin.tax_bracket_schedule.users_id` column (V1-safe by-construction since V1 settings writes are user-session-bounded) — at V2+ adoption, the Lock 12 mod #2 pattern (immutability DB-trigger fencing tenant-anchor `users_id` UPDATE post-creation) becomes V1-SHIP-BLOCK for that V2+ surface.
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
- **Stock screening — possibly a separate tool rather than mosko-fintech scope.** ADR-002 Finding (b). The "possibly a separate tool" hedge from Finding (b) is preserved verbatim: this V2+ line is not a commitment to ship within mosko-fintech, only that it's not V1. **Candidate P3 disposition at Phase 1 Step 4 close (per [ADR-011](DECISIONS.md#adr-011) Decision 20 / Lock 16):** V1-default — `pfin_back_etl` FMP API ingestion continues (incumbent); stock-screening tables accumulate in `pfin_dash` schema; V1 UI does NOT expose stock-screening surface. V2+ trajectory: if the surface lands in mosko-fintech scope, existing ingestion provides backfilled data; if it ships as a separate tool, the FMP ingestion can be repurposed or wound down. The candidate-P3 incumbent-exceeds-V1 review (per `feedback_incumbent_exceeds_v1_review` memory) ratified V1-default at Lock 16 with F/CTO disposition; no V1 PRD-scope expansion. *[Annotation 2026-06-02 — Phase 4 entry-gate close per [ADR-011](DECISIONS.md#adr-011) Decision 20:* the deferred candidate-P3 PM consult was performed a second time at Phase 4 entry (Phase 4 Step 1 entry-gate PM ratify-pass; PM verdict CONFIRM under Option A F/CTO ratification at v1.44 joint-close) and **re-confirms the V1-default disposition** with no scope change. PRD §2 grep verified zero V1 stories depend on stock-screening; ARCH `sec-2-fmp-note` verified ingestion-only topology; existing BACKLOG entries verified durably codified. Disposition unchanged; this entry stands as the V2-trajectory canonical anchor. *Last fresh consult before V2 scoping.*]

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
- **FMP API cost-saving levers** (per [ADR-011](DECISIONS.md#adr-011) Decision 20 / Lock 16 / Flag #11 cost-feasibility Outcome 1). V1 retains FMP starter plan per F/CTO ratification. Two V2+ cost-saving levers captured for future evaluation if V1 cost-shape pressures emerge:
  - **(b) FMP free tier downgrade** — $0/mo subscription IF the free tier's rate limits hold for V2+ needs. May degrade ingestion frequency or coverage; Phase 3 + V1.1+ verifies feasibility against query shape.
  - **(c) Yahoo / Google Finance scrape replacement** — $0/mo subscription cost replacement of FMP entirely. **Risk-flagged:** TOS ambiguity for commercial use; rate-limiting unpredictable; format-change breakage; data-quality concerns vs. structured FMP API. Sec re-consult MANDATORY before adoption (terms-of-service + data-quality posture); Architect re-consult for ingestion-code rewrite.
- **Stock-screening UI surface** (per [ADR-011](DECISIONS.md#adr-011) Decision 20 / Lock 16 candidate P3 V2+ trajectory). V1 ingests FMP data into `pfin_dash` stock-screening tables (incumbent) but exposes NO V1 UI surface. V2+ candidate: surface stock-screening capability (per-equity profile / EOD-price chart / statement viewer / screener UI). Cross-ref §5.5 above "Stock screening" line for the V2+ disposition narrative. PM consult required at V2-scoping time to scope the surface within the mosko-fintech-vs-separate-tool framing per ADR-002 Finding (b) hedge. *[Annotation 2026-06-02 — Phase 4 entry-gate close per [ADR-011](DECISIONS.md#adr-011) Decision 20:* the deferred candidate-P3 PM consult was performed a second time at Phase 4 entry (Phase 4 Step 1 entry-gate PM ratify-pass; PM verdict CONFIRM under Option A F/CTO ratification at v1.44 joint-close) and **re-confirms the V1-default disposition** with no scope change. PRD §2 grep verified zero V1 stories depend on stock-screening; ARCH `sec-2-fmp-note` verified ingestion-only topology; existing BACKLOG entries verified durably codified. Disposition unchanged; this entry stands as the V2-trajectory canonical anchor. *Last fresh consult before V2 scoping.*]
- **Hetzner cax21 → cax31 / cax41 VPS tier escalation path** (per [ADR-011](DECISIONS.md#adr-011) Decision 20 / Lock 16 + `reference_hetzner_cax21` memory). V1 ships on incumbent Hetzner cax21 (8 ARM vCores + 16 GB RAM + 160 GB disk at €9.50/mo). Phase 3 stress-test verifies headroom under full Lock 13 worker stack (Puppeteer + ETL + Supabase + Plaid concurrent load). V2+ escalation path: cax31 (~€18/mo; 2× headroom) → cax41 (~€36/mo; 4× headroom). Architect Phase 3 + first-quarter actual cost-tracking monitors squeeze-point; cost-feasibility re-review at V2 ship if cax21 no longer fits.
- **Promote `account_type` from `TEXT`+`CHECK` to a `pfin.account_type` lookup table** (per [ADR-022](DECISIONS.md#adr-022) account_type-taxonomy-rationale; SELF-187 migration `003`). ADR-022 records the V1 decision to model `pfin.account.account_type` as a fixed `TEXT`+`CHECK` 7-member enumeration (depository / investment / retirement / crypto / manual_other / real_estate / liability) rather than a lookup table, because `account_type` is a **closed, code-coupled taxonomy** — per [ADR-002](DECISIONS.md#adr-002) §1.9 each type drives ingest path + NAV grouping ([PRD §2.1.5](docs/PRD/index.html#story-2-1-5) composition membership) + asset-allocation bucket + income treatment — so a lookup table buys nothing in V1: adding a type is a **code event, not a data event** (a one-line `CHECK` alter). **Re-assessment trigger:** reconsider promotion when a type needs *per-type metadata* the schema would otherwise have nowhere to hold — display label, icon, default `tax_treatment`, Plaid-product mapping, sort order — i.e. when there is something for the table to *hold* beyond the bare type name. **Migration shape (contained, no data loss):** create `pfin.account_type`, seed the existing 7 members, swap the `CHECK` constraint for an FK on `pfin.account.account_type`, backfill — additive, no row loss. **Contrast — user-extensible taxonomy already has its home:** distinct from the user-editable Cat × Sub-Cat taxonomy in `pfin.user_taxonomy` per [ADR-004](DECISIONS.md#adr-004) Decision C (per-user, user-editable, seed-only in V1); `account_type` is the *closed* counterpart and stays code-coupled. **Honest scope:** a tracked re-assessment trigger, *not* a committed V2 ship — promotion happens only if/when the per-type-metadata need actually materializes.

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

## §7 framing — V1 staging queue

§7 holds going-forward V1 issue decompositions for milestones NOT currently in Linear per [ADR-017](DECISIONS.md#adr-017) Decision 2 (Linear holds current + next milestone only; everything else stages here with full Linear-grade specs). Promotion to Linear happens at Phase 5 milestone-rotation — when current completes, next becomes current, and the milestone after next promotes from §7 → Linear verbatim with the §7 entry marked **Promoted to Linear at SELF-N** as durable historical reference.

**Wave 6 (V1.5 + V1.final) — staged 2026-06-03.** Decomposed at Phase 4 Step 5 Wave 6 close per F/CTO ratify of 6 gates (Gate A unified helper per Wave 5 precedent → PM Issues 1+6+9 absorbed into Arch substrate; Gate B Option C — 4 named TEXT commentary columns on `monthly_report`; Gate C V1.x Platform scope for PDF worker; Gate D single calendar-gated V1.final issue; Gate E separate Sec PR post-Wave-6 for SECURITY §4.4 derivative-surface annotation; Gate F Option α native Coolify cron container). 18 issues total. Detail: [CHANGELOG v1.46 — TBD](CHANGELOG.md).

### §7.1 — Architect substrate (Platform / Cross-cutting V1.x; 8 items)

**A1. `pfin.monthly_report` header table + 4-named-TEXT commentary columns (Lock 11; Gate B Option C).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) verbatim; [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) header + §2.6.2 commentary persistence per Wave 6 Gate B Option C F/CTO ratify (4 named TEXT cols `commentary_cash` + `commentary_bonds` + `commentary_equity` + `commentary_alternatives` on header table — Lock 14 family stays at 5; no JSONB per forward-compat fence; PRD §2.6.2 fixed 4-sub-section verbatim count).
- **AC.** Schema with `users_id` UUID + `target_month` DATE + `generation_status` Lock-11-vocab enum (`draft`/`final`/`superseded`; PRD `not-yet-triggered`/`pending`/`generated` mapped at presentation) + `data_as_of` DATE + `generated_at` TIMESTAMPTZ + 4 commentary TEXT columns + `created_at` + `updated_at`; UNIQUE(users_id, target_month, generation_status) for `final`; Lock 11 9-mod inventory (INSERT-new-version regeneration per Lock 11 mod #2 Decision 15; supersession via SECURITY DEFINER `fn_supersede_monthly_report`; matched-tenant trigger on users_id FK per Decision 3 family — 6th instance; Lock 15 server-derived-only fence on data_as_of). RLS WITH CHECK `users_id = auth.uid()`. Sec joint-review on supersession mechanism + INSERT-new-version trigger.
- **Dependencies.** Upstream: SELF-232 fn_refresh_updated_at + SELF-233 settings write-path hardening. Downstream: A2, A3, A7, PM #2 in-app UI, PM #4 commentary editor.

**A2. `pfin.monthly_report_account_snapshot` sibling child table (Lock 12).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 16 / Lock 12](DECISIONS.md#adr-011) verbatim; PRD §2.6.4 snapshot historical retention.
- **AC.** Child table FK to A1 monthly_report; per-account snapshot rows (NAV components + balances + tax_treatment + scope at snapshot time); Lock 12 8-mod inventory including 3 V1-SHIP-BLOCK: (i) matched-tenant trigger on FK to parent (Decision 3 family — 7th instance); (ii) parent users_id + target_month immutability fence; (iii) service_role bypass DB-trigger on child. RT-21 HIGH + SD-12 child sub-class addendum. Read-only post-write per Lock 10 pattern adjacent. RLS via JOIN to A1.
- **Dependencies.** Upstream: A1, Wave 1 B4 account_trans, SELF-214 nav_daily, SELF-201 manual accounts. Downstream: A3, A7 cron worker.

**A3. SECURITY INVOKER read-composition helper (3 entry paths; absorbs PM Issue 1 per Gate A unified).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 15 / Lock 11](DECISIONS.md#adr-011) verbatim Lock 11 SECURITY INVOKER read-composition pattern; F/CTO Gate A Option B unified per Wave 5 precedent.
- **AC.** `pfin.fn_render_monthly_report(p_users_id UUID, p_target_month DATE, p_data_as_of DATE) RETURNS JSONB`. Composes 6-section report tree per PRD §2.6.1 verbatim section ordering: Account Holdings (consumes SELF-225 §2.1.5) + NAV Performance (SELF-218/219/220) + Asset Allocation (SELF-237/240 §2.2.2/§2.2.3) + Rebalancing Targets (reads A1 commentary cols) + Cash Flow (SELF-250/255 §2.3.2/§2.3.4) + Estimated Taxes (SELF-260/261 §2.5.1 + SELF-262 `fn_compute_tax_liability(p_data_as_of)` §2.5.3+§2.5.4). §2.5.4 NAV-components render on Account Holdings via §2.1.5 buildup NOT as Estimated Taxes rows per PRD §2.6.1 verbatim. SECURITY INVOKER preserves RLS at JWT-user-session layer (`auth.uid()` predicate composes across all upstream surfaces). 3 entry paths: in-app render (SSR), PDF render (via A5 endpoint), historical-month view. Sec joint-review on cross-tenant leak surface analysis (mirrors Wave 1 B5 + SELF-262 patterns).
- **Dependencies.** Upstream: A1 + A2 + SELF-262 (Wave 5 unified tax helper) + SELF-214 (nav_daily) + SELF-231 (user_taxonomy) + all Wave 1-5 NAV/allocation/cashflow substrate. Downstream: PM #2 in-app UI, PM #8 PDF export, A7 cron worker invocation.

**A4. Node PDF worker container scaffold (V1.x Platform scope per Gate C).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011) verbatim hybrid worker location; F/CTO Gate C V1.x Platform scope. RT-22 by construction (Lock 13 mod #2 verbatim "no SUPABASE_* env vars; no Postgres client installed in Dockerfile" — credential-absence by construction).
- **AC.** Node container scaffold with Puppeteer for headless Chrome PDF rendering; Dockerfile excludes Postgres client + `SUPABASE_*` env vars; reads JWT-bearer-token + composes HTML from JSON payload at `/internal/pdf-render` (A5); deploys on cax21 alongside `pfin_back_etl` per `reference_hetzner_cax21`. Coolify→Discord notification per `reference_coolify_discord_notifications` incumbent. NO database access by design (Lock 13 mod #2). Note: TenantBoundConnection fence (Wave 1 E2) applies to `pfin_back_etl` Python; PDF worker has NO DB connection so no TBC fence needed (per Architect Wave 6 v2 brief-drift catch #1).
- **Dependencies.** Upstream: cax21 incumbent + Wave 1 E2 (CI fence on pfin_back_etl, distinct). Downstream: A5 endpoint, A6 RT-22 audit fence, PM #8 PDF export.

**A5. V1 app `/internal/pdf-render` endpoint + RT-21 JWT verification battery.** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011) verbatim 10-mod inventory.
- **AC.** SvelteKit `/api/internal/pdf-render` route accepts JWT-bearer signed by V1 app + JSON payload (composed report); validates JWT signature + tenant binding via `SET LOCAL request.jwt.claims` (Arch-locked binding mechanism per RT-21(e) no-service_role-escalation); invokes A4 PDF worker; returns PDF bytes. RT-21 (a)–(g) full verification battery: (a) JWT signature; (b) nonce replay protection; (c) tenant claim presence; (d) expiry; (e) no service_role escalation; (f) audience check; (g) issuer check. Sec joint-review mandatory on JWT verification battery (RT-21 HIGH).
- **Dependencies.** Upstream: A4. Downstream: PM #8 PDF export.

**A6. RT-22 Dockerfile audit CI fence script (closes catalogued §10 instance #1; deferred from Wave 1).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 17 / Decision 4](DECISIONS.md#adr-011) verbatim; RT-22 catalogued §10 instance #1 per Decision 4 catalogued numbered list.
- **AC.** CI script greps A4 PDF worker Dockerfile for forbidden patterns: `SUPABASE_*` env vars (other than `SUPABASE_URL`); Postgres client packages (`postgresql-client`, `libpq-dev`, etc.); explicit Postgres binary `RUN` statements. CI fails build if violation found. Closes RT-22 catalogued §10 instance #1 (Wave 1 E1 closed RT-26 #2 instance; both catalogued instances now have V1 CI automation). Sec joint-review on grep pattern coverage.
- **Dependencies.** Upstream: A4. Downstream: V1 deployability gate.

**A7. monthly_report cron worker on `pfin_back_etl` (Native Coolify cron container per Gate F α; absorbs PM Issue 6 per Gate A).** [V1-SHIP-BLOCK]
- **Source.** [ADR-011 Decision 15 + Decision 17 / Lock 11 + Lock 13](DECISIONS.md#adr-011) verbatim hybrid worker location; F/CTO Gate F Option α native Coolify cron container ratify 2026-06-03.
- **AC.** Native Coolify cron container on cax21 schedules monthly invocation (1st-of-month per PRD §2.6.3 verbatim). Cron container invokes Python worker in `pfin_back_etl` which loops over tenants (via service_role-bounded query for tenant list) + invokes A3 helper per-tenant via SECURITY INVOKER tenant-binding (NOT service_role for report data composition; only for tenant enumeration). Lock 11 mod #4 cron tenant-binding pattern; Lock 13 mod #4 audit log. Coolify→Discord on completion or error. `p_data_as_of` server-derived from cron context (1st-of-month - 1 day = end-of-prior-month) per Lock 15 server-derived-only fence. Sec joint-review on cron tenant-binding + service_role isolation.
- **Dependencies.** Upstream: A3, A4 (worker location parallel), `pfin_back_etl` incumbent infra. Downstream: PM #2 in-app rendering shows cron-generated reports; PM #7 on-demand UI.

**A8. `pfin.owner_identification` settings table (closes Lock 14 5/5 + Settings ramp 4/4).**
- **Source.** [ADR-011 Decision 18 / Lock 14](DECISIONS.md#adr-011) verbatim "four per-domain tables" — last originally-committed member; [ADR-013 P5](DECISIONS.md#adr-013) Settings 4th-of-four occupant.
- **AC.** Schema: `users_id` UUID + `owner_id_header_text` TEXT + `created_at` + `updated_at`; UNIQUE(users_id) per Lock 14 per-domain-table pattern. Lock 14 family closes at 5 named tables (planning_target + cashflow_target + tax_bracket_schedule + tax_bracket_row + owner_identification). RLS WITH CHECK `users_id = auth.uid()`. Reuses SELF-232 fn_refresh_updated_at + SELF-233 settings write-path hardening shared layer. Sec advisory (not joint-review — single-column user-scoped table with no chain).
- **Dependencies.** Upstream: SELF-232 + SELF-233. Downstream: PM #10 Settings 4th occupant editor; A3 helper reads for §2.6.1 report header.

### §7.2 — PM V1.5 domain + V1.final close (10 items)

**P2. §2.6.1.b Monthly report in-app rendering UI.** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) verbatim composition + section ordering.
- **AC.** SvelteKit page at `/reports/monthly/{target_month}` invokes A3 helper via `+page.server.ts` SSR. Renders 6-section report: Account Holdings + NAV Performance + Asset Allocation + Rebalancing Targets (reads A1 commentary cols) + Cash Flow + Estimated Taxes (per PRD §2.6.1 verbatim ordering). NO inline edit per ADR-013 P5; "Edit commentary" button routes to P4. Live-recompute on upstream surface changes when viewing latest report; historical reports immutable post-final per Lock 11 mod #2.
- **Dependencies.** Upstream: A3 helper. Downstream: V1-SHIP-BLOCK V1.5 close.

**P3. §2.6.2.b Commentary editor UI (4 named text areas per Gate B Option C).** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.2](docs/PRD/index.html#story-2-6-2) verbatim 4-sub-section Rebalancing Targets free-text; ADR-013 INV-1 plain-text-only commentary is security-load-bearing (NO markdown sanitization at V1).
- **AC.** 4 plain text areas (Cash / Bonds / Equity / Alternatives) at `/reports/monthly/{target_month}/commentary`; reads A1 commentary cols; saves via REPLACE-all SERIALIZABLE write semantics (parallel to Lock 14 settings write pattern). Lock 14 V1-SHIP-BLOCK Sec mods applied: Zod `.strict()` + numeric-input adversarial battery (TEXT-input variant: control-char/length/encoding); mass-assignment prevention (users_id from auth.uid()). NO markdown rendering; plain-text-only per INV-1.
- **Dependencies.** Upstream: A1 (commentary cols). Downstream: P4 trigger integration.

**P4. §2.6.2.c Author-before-generate trigger integration.** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.2](docs/PRD/index.html#story-2-6-2) verbatim author-before-generate flow.
- **AC.** Cron worker (A7) checks for commentary presence per-tenant before generating monthly report; if all 4 commentary cols NULL/empty for target_month, skips report generation + sends Coolify→Discord notification "Awaiting commentary for {month}"; if commentary present, proceeds with generation. On-demand UI (P5) blocks "Generate" button if commentary empty + routes user to P3 commentary editor.
- **Dependencies.** Upstream: P3 commentary editor + A7 cron + P5 on-demand UI.

**P5. §2.6.3.b On-demand UI + pending queue.** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.3](docs/PRD/index.html#story-2-6-3) verbatim manual-trigger flow.
- **AC.** Page at `/reports/monthly/generate` lets user trigger on-demand generation outside cron cadence; pending queue shows reports queued/in-flight/done; on-demand invokes A3 helper via `/api/reports/generate` endpoint (NOT cron worker direct invocation per RLS + tenant-binding isolation). Blocks if commentary missing per P4. Reuses Lock 11 INSERT-new-version semantic.
- **Dependencies.** Upstream: A1 + A3 + P4. Downstream: PDF export P6.

**P6. §2.6.3.c PDF export via PDF worker container.** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.3](docs/PRD/index.html#story-2-6-3) verbatim PDF output format; [ADR-011 Decision 17 / Lock 13](DECISIONS.md#adr-011).
- **AC.** "Download PDF" button on P2 in-app render page invokes A5 endpoint with composed JSON payload + JWT-bearer; receives PDF bytes; serves as download. Filename pattern: `mosko-monthly-{target_month}-{generated_at}.pdf`. Layout matches in-app render (P2) via shared HTML template.
- **Dependencies.** Upstream: A4 + A5 + P2 in-app UI. Downstream: V1-SHIP-BLOCK V1.5 close.

**P7. §2.6.4.b Owner-identification Settings editor (4th-of-four occupant ramp closes).** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.1](docs/PRD/index.html#story-2-6-1) header owner-id; [ADR-013 P5](DECISIONS.md#adr-013) Settings 4th-of-four occupant.
- **AC.** SvelteKit Settings route at `/settings/owner-id`; single TEXT input for `owner_id_header_text` (e.g., "The Mosko Household"); replace-all SERIALIZABLE write to A8 table via Lock 14 V1-SHIP-BLOCK Sec mods (Zod `.strict()` + adversarial battery + mass-assignment prevention via SELF-233 hardening shared layer). Closes Settings area ramp at 4/4 (SELF-242 V1.2 + SELF-252 V1.3 + SELF-265 V1.4 + this V1.5).
- **Dependencies.** Upstream: A8 table + SELF-233 + SELF-242 shell. Downstream: A3 helper reads for report header.

**P8. §2.6.5 Staleness markers on §2.6 surfaces (SELF-208/229/243/258 framework extension).** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.5](docs/PRD/index.html#story-2-6-5) verbatim + [PRD §2.4.4](docs/PRD/index.html#story-2-4-4) verbatim staleness-ramp list naming §2.6 monthly report.
- **AC.** Generate-with-markers per α′-1 PRD §2.4.4 verbatim: when stale-Plaid-item constituents present at generation time, report renders with `<StaleConstituentBadge>` adjacent to affected section headers + per-row stale icon. Cron worker (A7) generates report regardless of staleness (NOT block); badges communicate degraded confidence. Extends SELF-208 (V1.0 framework) + SELF-229 (V1.1 NW) + SELF-243 (V1.2 §2.2) + SELF-258 (V1.3 §2.3) per ADR-013 D1.
- **Dependencies.** Upstream: SELF-208 + A3 helper. Downstream: V1-SHIP-BLOCK V1.5 close.

**P9. §2.5.x Staleness ramp to §2.5 surfaces (Wave 5 Gate D absorbed).** [V1-SHIP-BLOCK]
- **Source.** F/CTO Wave 5 Gate D ratify (defer §2.5 staleness ramp to V1.5 monthly-report close); ADR-013 D1 illustrative-not-exhaustive.
- **AC.** Extends SELF-208/229/243/258 framework to §2.5.1 / §2.5.3 / §2.5.4 surfaces (3-col tax decomposition table at SELF-264; quarterly tax tables at SELF-266; NAV composition Tax Liab rows at SELF-268). Per-row stale-constituent icon + section-header badge consuming `pfin.fn_aggregation_has_stale_constituent()` primitive.
- **Dependencies.** Upstream: SELF-208 framework + SELF-264 + SELF-266 + SELF-268. Downstream: V1-SHIP-BLOCK V1.5 close (paired with P8).

**P10. §2.6.6 RLS verification battery (V1.5 close-gate; tri-axis tenant × scope × tax_treatment + snapshot derivative-surface).** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.6.6](docs/PRD/index.html#story-2-6-6) verbatim "Monthly report is the user's, not anyone else's"; mirrors SELF-209/228/244/257/269 pattern.
- **AC.** RLS test battery covers A1+A2+A3+A5+A7+A8+P3 backend surfaces: cross-tenant injection rejected; SECURITY INVOKER A3 helper cross-tenant leak analysis; Lock 12 snapshot derivative-surface Sec annotation (NOT new SD class; snapshots of §2.5-grade values); A7 cron tenant-binding isolation; A5 PDF endpoint JWT-bearer tenant-binding; owner-id A8 cross-tenant; commentary P3 cross-tenant. Tri-axis orthogonality (tenant × scope × tax_treatment) verified per PRD §2.6.6 verbatim. V1.5 close-gate — no V1.5 issue closes until battery passes. Sec review pass + verdict recorded per SELF-269 precedent.
- **Dependencies.** Upstream: All Wave 6 issues. **V1.5 close-gate.**

**P11. V1.final §3.4 close-gate verification protocol (calendar-gated N=2 consecutive months).**
- **Source.** [PRD §3.4](docs/PRD/index.html#sec-3) verbatim (a)/(b)/(c) all-pass; [docs/MILESTONE-FRAMING.md §8.3](docs/MILESTONE-FRAMING.md) routing flag (d) handoff anchor.
- **AC.** Verification-protocol issue spanning N=2 consecutive months (structurally different from implementation issues per F/CTO Gate D ratify single-issue framing). Three sub-criteria: (a) PRD trace exit criterion = all 32 stories have ≥1 issue closed in Linear (post-rotation); (b) ARCH §10 SD+RT mapping verified post-implementation; (c) N=2 consecutive months of monthly report generation + commentary authoring + RLS clean. Closes V1 ship-gate per §8.3 routing flag (d) + drop-replace termination per §8.2. Decompose into (a)/(b)/(c)-month-1/(c)-month-2/V1.final-close-PR sub-issues at Linear promotion time IF F/CTO prefers finer granularity (per Gate D framing).
- **Dependencies.** Upstream: ALL V1 issues (V1.0+V1.1+V1.2+V1.3+V1.4+V1.5) + 2 calendar months of operation. **V1.final close-gate; final V1 issue.**

### §7.3 — GL-substrate stream (later V1.x; 2 items)

*Later-V1.x GL-substrate work decomposed out of the V1.0 §2.4 manual-entry track per [ADR-033](DECISIONS.md#adr-033) — GL-engine edits (net-new `fn_gl_entries` contra branches) that are a distinct work-class from the manual-entry INSERT-path slices. Milestone target (M4-GL-adjacent later V1.x) confirmed by F/CTO 2026-07-26; the exact product-V1.x label is pending roadmap sequencing with Architect. Promotes to Linear at milestone-rotation when the GL-substrate milestone becomes current + next.*

**G1. Manual in-kind transfer entry (`group_type='transfer_in_kind'` + net-new in-kind clearing contra).** [V1-SHIP-BLOCK]
- **Source.** [PRD §2.4.3.b](docs/PRD/index.html#story-2-4-3) (AcctSetup non-cash event entry — transfer-in-kind subtype) + [ADR-033 Decision 4](DECISIONS.md#adr-033) (transfer-in-kind deferral to its own SELF issue).
- **AC.** In-kind transfer entry modeled as journal `group_type='transfer_in_kind'` (`033`) over two `standard` security legs (out-leg + in-leg): (1) capture source account + destination account + position + cost-basis carry-over preserving original basis; (2) two `standard` legs — P1 cash branch skips (no cash), P2 emits a `trade_position` leg on each side; (3) **author the net-new in-kind clearing contra** in `fn_gl_entries` so the two legs offset (in-kind legs currently have no clearing contra → they park in Suspense, unlike cash transfers which get P3's Journal-Clearing contra via the `Transfer + journal_id` branch); (4) cost-basis carry-over + multi-lot reconcile; (5) per-security `Σ(quantity)=0` conservation enforced at close by `fn_journal_close_balance` (`037`); (6) **Sec-joint-review-mandatory** (GL/money-flow edit — a `fn_gl_entries` contra-branch change); (7) QA two-tenant pgTAP battery on the new contra branch + the conservation law.
- **Dependencies.** Upstream: [ADR-033](DECISIONS.md#adr-033) Decision 4 + GL machinery (`033` `journal.group_type` + `035`/`037` `fn_gl_entries` + `037` `fn_journal_close_balance` + `019` holdings). **Blocked-by:** the net-new in-kind clearing contra must be authored (net-new `fn_gl_entries` work; not present in the current engine). Evaluate for a Decision-3 fence at its migration (per ADR-033 Consequences). Sec joint-review gate. Downstream: completes the §2.4.3.b transfer-in-kind capability deferred from SELF-203.

**G2. Per-lot stock-split precision (lot-linkage substrate + per-lot `fn_create_stock_split`).** [refinement]
- **Source.** [ADR-033 Decision 2](DECISIONS.md#adr-033) + SELF-203 OWD-1. F/CTO chose per-lot (2026-07-26); the Architect feasibility pass established per-lot as a **substrate project, not a `039` line item**, so SELF-203 shipped POSITION-LEVEL (v1.114) and per-lot is deferred here.
- **AC.** Per-lot stock-split recording — one book-neutral `corp_action` row per open buy lot (vs SELF-203's position-level single row): (1) a lot-linkage self-FK on `account_trans` (e.g. `lot_parent_trans_id`) — a **NEW Decision-3 cross-tenant FK-bypass instance** (matched-tenant + matched-security fence, Sec-joint-review-mandatory) on the immutable ledger; (2) an authoritative DB open-lot-as-of read (`fn_open_lots_as_of`) — **depends on `lot_match` (036) matching inference being complete/authoritative** (currently Backend/worker-inferred, non-authoritative at write time — a DB open-lot read miscomputes until matching has run); (3) per-lot `fn_create_stock_split` computing per-lot deltas; (4) reverse-and-replace the SELF-203 position-level rows to per-lot (bounded — splits are rare). Sec-joint-review-mandatory.
- **Dependencies.** **Blocked-by:** authoritative lot-matching substrate (`lot_match` completeness — not built) + the lot-linkage FK. Architect feasibility memo: `temp/039-stock-split-design.md`. Note: per-lot tax-character precision is itself a deferred tax-layer refinement (`037` Option A), so the book GL loses nothing under position-level today. Downstream: upgrades SELF-203 position-level splits to per-lot precision.

### §7.4 — V1.6 reconciliation / statement tie-out stream (1 item)

*Read-only reconciliation work re-homed from the retired V1.0 §2.4.3 per-transaction reconcile mechanism per [ADR-035](DECISIONS.md#adr-035). Distinct work-class from §7.3 GL-engine edits: this is a read-only DETECTOR over existing SECURITY INVOKER helpers + service_role-populated checkpoints — it authors no `fn_gl_entries` contra branch and writes nothing to the immutable ledger. Homed in the dedicated **V1.6 — Reconciliation / statement tie-out** milestone (F/CTO-approved 2026-07-27; Platform/Cross-cutting project). The comparand substrate it reads is already shipped (see R1 Dependencies), so this is a standalone read-only feature over landed objects — not a pending substrate wave. **SELF-205 retains its ID, re-scoped to this entry.***

**R1. Period statement-vs-GL reconciliation control tie-out (read-only detector).**
- **Source.** [ADR-035](DECISIONS.md#adr-035) (supersedes SELF-205's per-transaction `reconciled_flag` / B1 / B2 mechanism; successor = statement control tie-out) + [PRD §2.4.3](docs/PRD/index.html#story-2-4-3) verbatim reconciliation prose.
- **AC.** Read-only DETECTOR, no auto-action: per reporting-period × account, compare the **GL-derived** as-of balance (cash, via `pfin.fn_compute_nav` cash-leg) and holdings (via `pfin.fn_holdings_as_of`) against the **statement-snapshot** comparands (`pfin.account_balance_checkpoint` cash snapshot + `pfin.holdings_checkpoint` per-asset snapshot + `pfin.reconciliation_event.statement_balance` / `.statement_quantity`); surface each mismatch (balance and per-position quantity) for the user to investigate. **No `reconciled_flag` / `reconciled_at` column, no B1 per-transaction trigger, no B2 bulk "reconcile mode"** — the reconciled verdict is an append-only `reconciliation_event` / `reconciliation_event_trans` row (`005`), not mutable row-state on the immutable `account_trans` ledger. Precise terminology (binding per ADR-035): this is a **statement-vs-GL account reconciliation control tie-out at period boundaries** — NOT a bare internal "trial balance check" (near-vacuous, since the double-entry GL already balances by construction at close via `fn_journal_close_balance` `037`). **Auto-reconcile on balance-match (B3) stays V2+** (per §5 auto-reconcile deferral) — the detector flags; it never auto-clears. Detection-only, consistent with the SELF-204 sync-dedup gate ([ADR-034](DECISIONS.md#adr-034)); SELF-204 DETECTS / SELF-205 INTERPRETS boundary preserved.
- **Dependencies.** Upstream: the comparand substrate — **already shipped** under Platform/Cross-cutting: `pfin.fn_compute_nav` / `pfin.fn_holdings_as_of` (`019` / SELF-277, SECURITY INVOKER, `set search_path=''`, Lock 11 read-composition), `pfin.account_balance_checkpoint` (`018` / SELF-276), `pfin.holdings_checkpoint` + `pfin.reconciliation_event.statement_balance` / `.statement_quantity` (`005` / SELF-188). The tie-out is therefore a standalone read-only feature over landed objects, not a pending substrate wave. **Build-time caveat:** verify whether the `005`-deferred `holdings_checkpoint` fan-out INSERT writer (the per-asset checkpoint populator) is fully covered by `018` or still outstanding — the holdings side of the tie-out needs populated checkpoints to compare against; if the writer is a gap, it carries its own migration + QA battery + Sec joint-review. **Sec joint-review + QA two-tenant pgTAP battery travel with this build** (read over the reconciliation substrate; not waived per ADR-035 Consequences). Downstream: closes the §2.4.3 external-agreement reconciliation commitment. **Re-scopes SELF-205** (retains ID; re-milestoned **V1.6 — Reconciliation / statement tie-out**; AC rewritten to this read-only-detector shape per ADR-035).

---

*Last updated: 2026-06-03 (Phase 4 Step 5 Wave 6 close — §7 V1 staging queue framing added per [ADR-017](DECISIONS.md#adr-017) Decision 2 + Wave 6 18 issues staged: 8 Architect substrate (A1-A8) + 10 PM domain (P2-P11; PM Issues 1+3+6+9 collapsed per F/CTO Gate A unified + Gate B Option C 4-col absorption); Settings area ramp closes at 4/4; Lock 14 family closes at 5/5; cumulative PRD §2 trace = 32/32 stories = Phase 4 exit criterion 1 fully discharged). [2026-07-26 — §7.3 GL-substrate stream added: **G1** transfer-in-kind follow-on staged per [ADR-033](DECISIONS.md#adr-033) Decision 4 handoff (later V1.x; decomposed out of SELF-203).] [2026-07-27 — SELF-203 stock-split entry LANDED (v1.114, POSITION-LEVEL); **G2** per-lot precision refinement staged (deferred as a substrate project — needs a lot-linkage FK + authoritative `lot_match`). Related SELF-203 follow-ups (also in PR #244 + CHANGELOG v1.114): **SELF-204** should promote the `fn_create_stock_split` source-of-truth guard to a BEFORE INSERT trigger once provider corp-action ingestion lands (Sec note); **UX Designer** copy pass for the entry-form empty-state/error strings.] [2026-07-27 — §7.4 V1.6 reconciliation / statement tie-out stream added: **R1** period statement-vs-GL reconciliation control tie-out (read-only detector) staged per [ADR-035](DECISIONS.md#adr-035); re-homes the retired V1.0 §2.4.3 per-transaction reconcile mechanism (`reconciled_flag` / B1 / B2 superseded — reconciled-by-construction via the double-entry GL); comparand substrate already shipped (`005`/`018`/`019`); homed in the new **V1.6 — Reconciliation / statement tie-out** milestone; SELF-205 re-scoped (retains ID, re-milestoned V1.6).] Edit via `/start-doc-update <slug>` per ADR-009 Decision 9.*
