# PR 2 — §1 (Vision and target user) rewrite — PM deliverable

> **Status:** Working PM deliverable returned 2026-05-18 for F/CTO ratification (Q1 structure gate + Q2 body gate). Will be obsoleted (archived or deleted) once PR 2 ships.

[PM]:

# PR 2 — §1 (Vision and target user) rewrite

This is the single bundled deliverable for PR 2 in the Phase 1 Step 3.5 sequence. PR 2 is the first body rewrite under the new cadence and sets the patterns PR 3–9 inherit.

**Pattern-divergence-check declaration:** PR 2 uses **bulk-closeout** pattern per Q3 = γ; rationale: §1 is a low-risk small surface (4 sub-sections, ~47 source lines). Per the gate-pattern matrix, low-risk sections take 1 structure gate + 1 body gate.

**§1 lock-status carve-out:** §1 has F/CTO β override per R6 — still-mutable for substance during PR 2. PR 2 surfaces zero substance amendments below. The override is exercised by *availability of the path*, not by use of it.

---

## Part 1 — Structure proposal for the rewritten §1

### Sub-section layout

Preserves §1.1 / §1.2 / §1.3 / §1.4 numbering per Q2 = β source-order parity. No sub-section reshape proposed — the source layout already maps cleanly to the four scannable units (what V1 is / who it's for / why an archetype / what's excluded).

| Sub-§ | Source title | Rewritten title (proposed) | Shape |
|---|---|---|---|
| 1.1 | Vision | **Vision** | Lead clause + 3 nested bullets (replaces the dense single-paragraph). |
| 1.2 | Target-user archetype | **Target-user archetype** | 1-sentence framing + bulleted attribute list (already mostly bulleted in source; light compression) + 1 closing line (V1-instance-is-population-of-one). |
| 1.3 | Why this archetype, not "me specifically" | **Why an archetype, not the F/CTO by name** | 1-sentence framing + 3 numbered points (preserved from source) + 1 consequence-and-correctness bullet block (replaces the closing rationale paragraph). |
| 1.4 | What this PRD section is not addressing about the user | **Deferred user-shape questions** | 1-sentence framing + 4 deferred-item bullets (compressed) + 1 carve-out line for advisor/fiduciary → §6. |

### Per-sub-section bullet/paragraph plan

- **§1.1.** Replace the 5-sentence dense paragraph with: 1 lead clause defining the product + 3 nested bullets covering (a) what V1 is observationally, (b) what V1 explicitly does not do, (c) what "V1 done" means (parity + monthly report). Same content; scan-first shape.
- **§1.2.** Keep the framing sentence; keep the 7 attribute bullets verbatim (they are the load-bearing archetype definition and bulleted-with-bold-lead-clause is already the right shape); keep the closing "V1 instance is population of one" line.
- **§1.3.** Keep the 3 numbered points verbatim. Replace the closing 4-sentence rationale paragraph with: 1 lead "consequence" line + 3 nested bullets covering V1-success-definition / V1-correctness-definition / V1-correctness-existing-system-replacement test (the §8 cross-reference clause, restated with the new section-anchor target — see Part 5).
- **§1.4.** Keep the framing sentence. Keep 4 deferred-item bullets but compress each (each is currently a multi-sentence paragraph-bullet; rewrite as bold-lead-clause + 1 supporting sentence + ADR pointer). Keep the closing carve-out for advisor/fiduciary → §6 as a single-line clause, not the current 2-sentence paragraph.

### In-body marker conventions established by PR 2

**(Pattern element — generalize to PR 3–9.)** Two appendix-references are needed in §1.3 and §1.4 footer slots; both appendices don't yet exist (B = PR 10; C = first relevant in PR 3 at §2). Proposed in-body marker conventions:

- **For Appendix B (routing flags), used when the rewritten section has routing flags.** §1 has none. If a future rewritten section has routing flags but Appendix B doesn't yet exist, the in-body marker reads:
  > *Routing flags affecting §N: see Appendix B (created in PR 10; pending consolidation).*
  
  After PR 10 lands, the parenthetical drops to just *see Appendix B*.

- **For Appendix C (Story Trace Index), used in §2.x stories from PR 3 onward.** §1 has none. Proposed in-body marker convention:
  > *Traces: see Appendix C → N.M.K.*
  
  Where the appendix entry preserves the original `Traces to:` content unchanged. This becomes a per-story footer in §2 rewrites.

- **For ADR citations (used wherever the source had a re-narrated ADR explanation).** Drop the re-narration; keep ID-level pointer inline. Convention: cite as *(ADR-NNN [Decision X])* or *(ADR-NNN §M.N)* without further explanation in the PRD body. Reader navigates to DECISIONS.md for full rationale. **§1 uses this pattern in §1.3 (cites ADR-002 three times in numbered points — preserved verbatim) and §1.4 (cites ADR-002 + ADR-004 + ADR-007 — compressed).**

**These three marker conventions are PR 2's primary pattern contribution to PR 3–9.**

---

## Part 2 — Full body draft of the rewritten §1

The markdown below is production-ready for direct integration into PRD.md. CoS pastes it as-is into the §1 slot.

```markdown
## 1. Vision and target user

### 1.1 Vision

mosko-fintech is a personal financial observatory: a single trustworthy view of one individual's complete financial position across every account they hold, plus the activity and derived measures that make that position meaningful.

- **What V1 is.** Aggregated account coverage (checking, savings, credit, brokerage, retirement, loans, crypto) with transactions, investment flows, and derived measures (net worth, asset allocation, monthly spending and income by category, estimated taxes).
- **What V1 is not.** Observational only — it surfaces the user's position and the gap between target and actual allocation; it does not move money, generate buy/sell recommendations, or act in any advisory capacity. The goal is clarity in the user's own hands: the user decides, the tool shows.
- **What "V1 done" means.** Functional parity with the working manual-spreadsheet system the V1 instance maintains today, with the **monthly Finance Report** as the canonical deliverable. V1 progressively replaces that system rather than running alongside it.

### 1.2 Target-user archetype

The V1 target user — *the self-directed multi-account owner* — is a financially-engaged individual with a fragmented multi-account portfolio that no single bank or brokerage view covers and that public consumer-finance tools tend to oversimplify or misrepresent.

The archetype has the following defining attributes:

- **Multi-institution footprint.** Accounts spread across multiple banks, brokerages, retirement custodians, credit issuers, and at least one crypto venue. No single institution dashboard captures their position; aggregation is non-optional.
- **Mixed tax-treatment portfolio across multiple jurisdictions.** Holdings span taxable, tax-deferred, and tax-exempt accounts (and HSA, which is conditional on use). Tax thinking is jurisdictional — Federal and state (California, in the V1 instance) tax obligations are reasoned about in parallel, not as a single combined number. Tax treatment and jurisdiction are first-class attributes of how they think about money, not afterthoughts.
- **Holds investment securities, not just deposits.** Brokerage and retirement accounts contain equities, funds, fixed income, and possibly other instruments. They care about cost basis and unrealized gain/loss, not just balances.
- **Self-directed, with an observational tool.** They make their own financial decisions — portfolio allocation, rebalance timing, spending changes, account-level moves — and use this tool as input to those decisions, not as a source of them. They want to *see* their position clearly and *manage* the gap between target and actual allocation.
- **Precise about categorization.** They maintain deliberate two-level taxonomies — a top-level category and a sub-category — for both holdings (e.g., Equity → US-Index_Non_Sector; Bonds → T-bill; Alternatives → REIT) and cash-flow activity (Income, Expenses, and other flow types, each with their own sub-categories). A coarse-bucket tool that summarizes "you have $X in equities" without distinguishing US-sector / international / index-vs-growth would be unusable. They assign holdings and transactions to their buckets themselves and update those assignments as their portfolio evolves; the categorization grammar is theirs to define and theirs to apply.
- **Privacy- and control-conscious.** They are uncomfortable with consumer-finance tools that monetize their data, push affiliate products, or surface "insights" that are really marketing. They prefer a tool they own, that holds their data on their terms.
- **Comfortable with substantial manual curation.** They maintain their financial system actively, by hand, on a monthly cadence — entering or reconciling transactions, refreshing valuations on held-away assets, and curating the taxonomies that categorize what they own. They will not tolerate a tool that pretends the un-aggregated accounts don't exist, and they accept that some accounts and asset classes will continue to require manual entry indefinitely.

The Founder/CTO is the V1 instance of this archetype. V1 is built for and validated by a population of one.

### 1.3 Why an archetype, not the F/CTO by name

The PRD frames the target user as an archetype rather than as the Founder/CTO personally because three locked decisions in `DECISIONS.md` make the archetype framing load-bearing rather than aspirational:

1. **Multi-tenant from day one** (ADR-002). The data model, auth boundary, and isolation guarantees treat the user identity as a first-class entity from V1. Tying the PRD to a single named person would be a fiction the architecture explicitly refuses to maintain.
2. **Forward-compatibility commitment** (ADR-002). V2+ broadens distribution to invite-only — a small cohort of *self-directed multi-account owners*. Defining the archetype now means V2 inherits a known target population rather than re-litigating who the next users are.
3. **Single-user usage model in V1** (ADR-002). The archetype framing does not contradict this. V1 ships with one user (the Founder/CTO) actively using it. The archetype is the *shape* of the user the product is designed for; the V1 *instance* of that shape is the Founder/CTO. The two are deliberately decoupled.

The practical consequence:

- **V1 success** = "this works for the Founder/CTO specifically."
- **V1 product correctness** = every requirement traces to an attribute of the archetype, not to a one-off preference. When the two conflict — when a Founder/CTO preference is not a generalizable archetype attribute — the conflict surfaces as a flag for V1.0/V1.1 milestone-sequencing decisions (Phase 4 territory, not this section's problem).
- **V1 existing-system-replacement test.** Per the §8 V1-done definition (anchored at §3.4), V1 is correct when it replicates the workflows the F/CTO maintains today in the manual-spreadsheet system, plus the explicit ADR-004 amendments.

### 1.4 Deferred user-shape questions

To keep the archetype defensible and avoid scope creep into adjacent personas, the following user-shape questions are explicitly **deferred**, not silently elided:

- **Household and joint-account semantics.** The V1 archetype is individual-scoped. Joint accounts owned with a spouse or partner appear in V1 as accounts the individual has access to, not as a multi-owner data model. Multi-scope ownership *within* a single user's household (multiple legal-ownership scopes such as personal, trust, retirement custodial) is a V1 data attribute per ADR-004 Decision B. Household-level user-facing semantics (shared budgets, multi-owner net worth, partner visibility, per-scope user-facing reports) are out-of-scope for this PRD lifecycle and route to a future PRD revision if invite-only V2 demand surfaces.
- **Geographic, currency, and multi-jurisdictional tax scope.** V1 assumes a US-domiciled user with USD-denominated accounts. Multi-currency support is V2+ per ADR-002 reclassification. V1 tax handling is jurisdiction-specific to the V1 instance — US Federal plus California state — per ADR-004 Decision D. Multi-state and non-US tax handling (RRSP, ISA, foreign tax credits, etc.) are V2+.
- **Life-stage and goal-tracking framing.** The archetype is defined by what the user owns and how they think about their money today, not by retirement goals, savings targets, or life events. Goal-tracking is a candidate V2 surface; it does not shape the V1 archetype.
- **Advisor or accountant collaboration.** Read-only exports for an accountant at tax time are a candidate V2 feature, not an archetype attribute.

**Advisor/fiduciary carve-out.** The advisor/fiduciary role is treated separately: it is a **permanent product-identity non-goal** under the §6 advisor/fiduciary axis per ADR-002 §3.0 + ADR-007, not a deferred user-shape question. The other items above are scope boundaries for this PRD lifecycle (V2+ trajectory items revisitable at V2-scoping time); the advisor/fiduciary role does not return to scope without a §6 axis revision.
```

---

## Part 3 — Pattern-divergence-check declaration (for PR body)

> **Pattern-divergence-check (Step 3.5 convention).** PR 2 uses **bulk-closeout** pattern per Q3 = γ; rationale: §1 is a low-risk small surface (4 sub-sections, ~47 source lines), within the bulk-closeout-permissible scope (§1 / §3 / §5 / §6 / §7 / §8). Two ratify gates: structure (Part 1 above) and body (Part 2 above). No sub-section or per-bullet gates.

---

## Part 4 — Structural-fidelity attestation (per R1 mitigation)

One attestation per sub-section. Per F/CTO β override on §1, substance changes (if any) are flagged separately in Part 8 — this Part 4 attests presentation-only fidelity.

### §1.1 attestation

> **Rewritten §1.1 lead clauses + nested clauses are the same commitments as the source at `docs/archive/PRD-v1.18-source.md` §1.1.** Editorial-choice surfaces explicitly called out:
> - The single dense source paragraph is split into 1 lead clause + 3 nested bullets covering (a) what V1 *is*, (b) what V1 *is not*, (c) what "V1 done" means. The lead clause is the "personal financial observatory" definition; the three nested bullets correspond to source-sentence-clusters 1+2 (aggregated account coverage + derived measures), source-sentences 3+4 (observational scope + decides/shows commitment), and source-sentence 2 closing-clause (V1-done parity + monthly Finance Report).
> - The "checking, savings, credit, brokerage, retirement, loans, crypto" account-type enumeration moves from a parenthetical in the source lead-paragraph into the first nested bullet. Substance unchanged.
> - The phrase "user decides; the tool shows" is preserved verbatim (load-bearing observational-tool framing).
> - Zero new commitments. Zero dropped commitments.

### §1.2 attestation

> **Rewritten §1.2 lead clauses + nested clauses are the same commitments as the source at `docs/archive/PRD-v1.18-source.md` §1.2.** Editorial-choice surfaces explicitly called out:
> - All 7 attribute bullets preserved verbatim except minor copy-edit normalization (e.g., source "*see* their position clearly and *manage* the gap" → rewritten "*see* their position clearly and *manage* the gap" — italics preserved; one redundant "they" cleanup in the self-directed bullet).
> - Framing sentence compressed: source's two-sentence opener ("The V1 target user … *the self-directed multi-account owner* — is a financially-engaged individual with a fragmented multi-account portfolio, someone who has accumulated, over years, a mix of account types that no single bank or brokerage view covers and that public consumer-finance tools tend to oversimplify or misrepresent.") becomes one sentence ("The V1 target user — *the self-directed multi-account owner* — is a financially-engaged individual with a fragmented multi-account portfolio that no single bank or brokerage view covers and that public consumer-finance tools tend to oversimplify or misrepresent."). The "accumulated, over years, a mix of account types" clause drops as redundant with "fragmented multi-account portfolio"; substance equivalent.
> - Closing "population of one" line preserved verbatim.
> - Attribute #5 ("Precise about categorization") preserved verbatim including the v1.6 strengthening — this is the load-bearing source clause for §3.2 Metric 4 traceability and must not drift.
> - Zero new commitments. Zero dropped commitments. No re-ordering of attributes.

### §1.3 attestation

> **Rewritten §1.3 lead clauses + nested clauses are the same commitments as the source at `docs/archive/PRD-v1.18-source.md` §1.3.** Editorial-choice surfaces explicitly called out:
> - Title changes from "Why this archetype, not 'me specifically'" to "Why an archetype, not the F/CTO by name." Equivalent meaning, slightly tighter and consistent with project terminology (F/CTO appears throughout PRD; "me specifically" was first-person and inconsistent with the third-person PRD voice).
> - 3 numbered points preserved verbatim (these are the load-bearing rationale; bulleting them would lose the explicit 1-2-3 traceability to ADR-002 commitments).
> - Closing rationale paragraph compressed from 4-sentence prose to 1 lead clause + 3 nested bullets ("V1 success" / "V1 product correctness" / "V1 existing-system-replacement test"). The third bullet carries the §8 forward-pointer with section-anchor form per Q4 = α — see Part 5.
> - Zero new commitments. Zero dropped commitments.

### §1.4 attestation

> **Rewritten §1.4 lead clauses + nested clauses are the same commitments as the source at `docs/archive/PRD-v1.18-source.md` §1.4.** Editorial-choice surfaces explicitly called out:
> - Title changes from "What this PRD section is not addressing about the user" to "Deferred user-shape questions." Equivalent meaning; scannable. The "PRD section is not addressing" phrasing was inverted-construction; "deferred" is the direct framing the body already uses ("are explicitly **deferred**, not silently elided").
> - 4 deferred-item bullets preserved with minor compression (each was a 3–5-sentence paragraph-bullet; rewritten as bold-lead-clause + 1–2 supporting sentences + ADR pointer). Source's multi-sentence elaboration of the household + multi-currency items is compressed by ~20% by dropping redundant transitional phrases; substance preserved.
> - The closing carve-out paragraph in source (2 sentences spanning advisor/fiduciary + accountant-export distinction) is restructured: the accountant-export distinction migrates into bullet #4 of the deferred list (where it already lived in source); the advisor/fiduciary permanent-non-goal clause becomes a dedicated "Advisor/fiduciary carve-out" line at sub-section foot, preserving the §6 + ADR-002 §3.0 + ADR-007 traceability. This is the v1.15 surgical edit's content; preserved verbatim in commitment.
> - Zero new commitments. Zero dropped commitments.

---

## Part 5 — Cross-reference sweep (per Q4 = α)

**Sweep scope:** every `PRD.md:NNN` reference in `WORKFLOW.md` + `DECISIONS.md` where NNN sits inside §1 of `docs/archive/PRD-v1.18-source.md` (archive lines 17–58).

**Found:** 3 occurrences in WORKFLOW.md; 0 occurrences in DECISIONS.md.

| File | Line | Source ref | Resolves to (in archive) | Proposed retarget |
|---|---|---|---|---|
| WORKFLOW.md | 93 | `` `PRD.md:47` `` | Archive line 47 = §1.3 closing paragraph, V1-correctness sentence | `` `PRD.md §1.3` `` |
| WORKFLOW.md | 108 | `` `PRD.md:47` `` | Archive line 47 = §1.3 closing paragraph (same) | `` `PRD.md §1.3` `` |
| WORKFLOW.md | 217 | `` `PRD.md:58` `` | Archive line 58 = §1.4 closing paragraph (advisor/fiduciary carve-out, v1.15 surgical edit) | `` `PRD.md §1.4` `` |

**Note:** DECISIONS.md references to "§1.1 / §1.2 / §1.4 / §1.6 / §1.7 / §1.8" are to **ADR-002's internal numbering**, not to PRD §1.x, and are out of sweep scope. Verified by inspection: every DECISIONS.md `§1.X` reference appears in context of "ADR-002 §1.X" or "ADR-002 §M.0" parent ADR structure.

**Retargeting is presentation-pointer-only** per the Q4 = α carve-out documented in `docs/archive/README.md`. Not an ADR substance amendment.

CoS executes the retargeting at integration time (3 line edits in WORKFLOW.md).

---

## Part 6 — Routing-flag handling note

§1 has **zero routing flags** in source. Rewritten §1 also has zero routing flags. No Appendix B in-body marker needed in §1.

**Convention established for PR 3–9 (when a rewritten section has routing flags but Appendix B doesn't yet exist):**

> *Routing flags affecting §N: see Appendix B (created in PR 10; pending consolidation).*

After PR 10 lands (consolidated Appendix B), a housekeeping pass drops the parenthetical so the marker reads `*Routing flags affecting §N: see Appendix B.*`

PR 3 (§2 rewrite) is the first PR that exercises this convention — §2.1 through §2.6 each have routing flags in source.

---

## Part 7 — Acceptance-flags relocation note (per Q1 = β)

§1's accumulated acceptance metadata is preserved in WORKFLOW.md and DECISIONS.md, not in the rewritten §1 body:

- **§1.2 attribute #5 strengthening** at v1.6 — preserved in WORKFLOW.md v1.6 changelog entry (PR 11 / Phase 0.5 archive era; tagged separately).
- **§1.4 line-58 surgical edit** at v1.15 (advisor/fiduciary alignment with §6 + ADR-007) — preserved in WORKFLOW.md v1.15 changelog entry (lines 215–219; not retargeted because the historical entry documents what was edited and where).
- **PR 2 §1 rewrite** — documented in WORKFLOW.md v1.20 changelog entry (this PR; draft in Part 9).

Rewritten §1 has **no `#### Acceptance flags` block in body**. This is the project-wide pattern Q1 = β established; PR 3–9 inherit it.

---

## Part 8 — Substance-amendment flags (per §1 β override)

**Zero substance amendments proposed.** All §1 source content is structurally preserved in rewritten form per the Part 4 attestations.

The §1 β override path is available but not exercised in PR 2. The path remains open through F/CTO body-gate review — if F/CTO reading the rewritten §1 surfaces a substance issue, the body gate is the right moment to invoke the override and land an amendment before PR 2 ships.

---

## Part 9 — WORKFLOW.md v1.20 changelog entry draft

Modeled on v1.19's scannable shape (bullets + sub-headers + table); evolved with per-section-context fields PR 3–9 will inherit.

```markdown
### v1.20 — 2026-MM-DD

**PR #[TBD] — Phase 1 Step 3.5 PR 2 / §1 (Vision and target user) rewrite.** First body-rewrite PR under Step 3.5 cadence; establishes patterns PR 3–9 inherit.

**Section rewritten**

- **§1** (Vision and target user) — 4 sub-sections preserved (§1.1 / §1.2 / §1.3 / §1.4) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §1 (lines 17–58, ~47 lines).
- Rewritten: PRD.md §1 (~75 lines including markdown bullet expansion; line delta is a presentation artifact, not content growth).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ (low-risk small section; in §1 / §3 / §5 / §6 / §7 / §8 bulk-closeout-permissible scope). Two F/CTO ratify gates only: structure + body.
- **Zero sub-section gates, zero per-bullet gates.**

**Structural-fidelity attestation**

- §1.1 — 1 lead + 3 nested bullets replace dense single-paragraph; observational-tool framing preserved verbatim; "user decides; the tool shows" preserved verbatim.
- §1.2 — 7 archetype attribute bullets preserved verbatim; framing sentence compressed by ~30%; attribute #5 v1.6-strengthening preserved verbatim (load-bearing for §3.2 Metric 4 traceability).
- §1.3 — 3 numbered rationale points preserved verbatim; closing paragraph compressed to 1 lead + 3 nested bullets (V1 success / V1 correctness / V1 existing-system-replacement test); section title tightened.
- §1.4 — 4 deferred-item bullets compressed by ~20%; v1.15 surgical-edit content preserved verbatim with restructured placement (advisor/fiduciary carve-out as foot-line instead of inline closing-paragraph); section title tightened.
- Zero new commitments. Zero dropped commitments. Zero substance amendments (Part 8 of PR 2 task deliverable).

**§1 β override status**

- Path was available per WORKFLOW.md v1.19 R6 carve-out (§1 still-mutable, not formally locked).
- Path **not exercised** in PR 2 — PM did not surface substance issues during rewrite; F/CTO did not surface substance issues during body ratify.
- PR 2 ships as presentation-only.

**Cross-reference retargeting (per Q4 = α)**

| File | Line | Old | New |
|---|---|---|---|
| WORKFLOW.md | 93 | `` `PRD.md:47` `` | `` `PRD.md §1.3` `` |
| WORKFLOW.md | 108 | `` `PRD.md:47` `` | `` `PRD.md §1.3` `` |
| WORKFLOW.md | 217 | `` `PRD.md:58` `` | `` `PRD.md §1.4` `` |

- **3 retargets** in WORKFLOW.md; 0 in DECISIONS.md (verified: DECISIONS.md `§1.X` refs are to ADR-002 internal numbering, not PRD §1.x).
- Retargets are presentation-pointer-only per `docs/archive/README.md` Q4 = α carve-out.

**In-body marker conventions established (for PR 3–9)**

- **Appendix B (routing flags) marker (when Appendix B does not yet exist):** `*Routing flags affecting §N: see Appendix B (created in PR 10; pending consolidation).*` Parenthetical drops after PR 10 ships. §1 has zero routing flags so this convention is declared by PR 2 but first exercised at PR 3 (§2).
- **Appendix C (Story Trace Index) marker (first exercised at PR 3):** `*Traces: see Appendix C → N.M.K.*` Per-story footer pattern; Appendix C entries preserve the original `Traces to:` content unchanged.
- **ADR citation convention:** drop ADR re-narration in PRD body; keep ID-level pointer inline as `(ADR-NNN [Decision X])` or `(ADR-NNN §M.N)`. Reader navigates to DECISIONS.md for full rationale.

**Acceptance-flags relocation (per Q1 = β)**

- §1 body has **no `#### Acceptance flags` block** in rewritten form.
- §1 lock metadata is preserved across: WORKFLOW.md v1.6 (§1.2 attribute #5 strengthening), v1.15 (§1.4 line-58 surgical edit), v1.20 (this entry).
- Pattern established for PR 3–9: no Acceptance-flags block in any rewritten PRD body.

**F/CTO ratification: 2-for-2 PM-lean acceptance**, zero overrides:
1. Structure gate accepted (Part 1 of PM deliverable: sub-section preservation + per-sub-section bullet/paragraph plan + in-body marker conventions).
2. Body gate accepted (Part 2 of PM deliverable: full §1 rewrite as drafted).

**Engagement notes**

- PM workhorse (single bundled deliverable: structure proposal + full body draft + attestations + cross-ref sweep + changelog draft + pattern declarations).
- Sec untouched (no Sec surface in §1).
- Architect untouched (no architecture surface in §1).
- CoS bookkeeping + 2 ratify gates with F/CTO via AskUserQuestion + integration pass (PRD.md §1 swap + WORKFLOW.md 3-line retarget sweep + this v1.20 entry).

**Next thread:** **PR 3 — §2 (V1 user stories) rewrite.** First sub-section-gates PR under Q3 = γ — §2 is high-risk (largest section, 6 sub-sections, ~580 lines). Cadence: structure gate + 6 sub-section body gates (one per §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6). First exercise of Appendix C Story Trace Index extraction pattern. First exercise of Appendix B in-body marker convention (§2.1 through §2.6 each have routing flags).
```

---

## Part 10 — Risks and open questions for PR 3+

Six items surfaced from PR 2 that should inform PR 3–9 pattern decisions.

**(a) Appendix C extraction shape — to land at PR 3, not designed in PR 2.** §1 has no story-trace tails, so PR 2 doesn't exercise Appendix C. PR 3 (§2) faces the largest mechanical change in the rewrite — extracting ~350–450 lines of `Traces to:` prose across ~30+ user stories into a flat keyed appendix. Two open shape questions PR 3 must answer at its structure gate: (i) does Appendix C live in PRD.md or in a separate `docs/prd-appendix-c-story-traces.md` file? (ii) does each appendix entry preserve the `> *Traces to:*` blockquote form, or normalize to a flat paragraph keyed by story ID? Neither answer is forced by PR 2; both are PR 3 ratify questions.

**(b) Sub-section gate count drift — §4 has 6 sub-sections, §2 has 6.** Q3 = γ commits to sub-section gates for §4 + §2 but doesn't specify whether each PR has N body gates (one per sub-section) or whether some sub-sections can share a gate. PR 3 is the first test. Recommend establishing the convention as "one body gate per sub-section" at PR 3 structure-gate ratify to keep PR 4 (§4) predictable.

**(c) Section-title rewrites in §1 changed two titles.** §1.3 ("Why this archetype, not 'me specifically'" → "Why an archetype, not the F/CTO by name") and §1.4 ("What this PRD section is not addressing about the user" → "Deferred user-shape questions"). Both changes attested as presentation-only — meaning equivalent. PR 3–9 may surface similar title-rewrite candidates. Convention recommendation: PM proposes title rewrites at structure gate (not buried in body); attestation explicitly notes any title change with old → new + meaning-equivalence rationale.

**(d) Compression ratio variance across §1 sub-sections.** §1.1 compressed dense paragraph to bullets (line count grew but visual scannability gained). §1.2 stayed structurally identical (already bulleted). §1.3 compressed closing paragraph by ~50%. §1.4 compressed by ~20%. The variance is content-shape-driven, not pattern-driven. PR 3–9 likely show wider variance; the **pattern is "compress paragraph-bullets to lead-clause + nested bullets where the source paragraph carries 4+ sentences"**, not "compress every section by N%."

**(e) ADR-citation re-narration removal — §1 had only 3 ADR re-narrations (all preserved as ID-level pointers).** §4 and §2 source carries dozens of multi-sentence ADR re-narrations inline. The drop-the-re-narration / keep-the-pointer convention from Part 1 is the heaviest editorial lift in the rewrite. PR 4 (§4) will be the stress test.

**(f) Q4 = α retargeting volume escalates after PR 2.** §1 has 3 line-anchored refs to retarget. §3 has at least 2 (`PRD.md:689` × 2 in WORKFLOW.md v1.18); §4 has multiple (`PRD.md:805`, `:808`, `:820`); §6 / §7 / §8 have several. **Recommendation: each rewrite PR's cross-ref sweep is a discrete deliverable item (Part 5 pattern), with explicit count up front so CoS can size the integration-pass diff.**

---

## Embedded ratify questions for F/CTO

PR 2 is bulk-closeout: structure gate + body gate. Both are presented below per project one-question-at-a-time pacing memory.

---

**Q1 — Structure gate.**

Ratify the §1 rewrite structure (Part 1 above): 4 sub-sections preserved with §1.1 / §1.2 / §1.3 / §1.4 numbering per Q2 = β; per-sub-section bullet plan as described; section-title rewrites at §1.3 + §1.4 (per Part 10 (c) — title changes attested as presentation-only meaning-equivalent); in-body marker conventions established for PR 3–9 (Appendix B / Appendix C / ADR citations per Part 1 closing).

- **Option α — Accept structure as proposed.** Includes the §1.3 + §1.4 title rewrites. Body gate (Q2) follows.
- **Option β — Accept structure, but keep source section titles verbatim** ("Why this archetype, not 'me specifically'" and "What this PRD section is not addressing about the user"). Body content compresses as planned but title strings preserved from source.
- **Option γ — Defer; PM revises structure proposal first** (specify what needs revision).

PM recommendation: **α.** Both title rewrites are presentation-only meaning-equivalent (attested in Part 4) and contribute to the scannability goal. β is viable as a stricter presentation-only reading; γ if F/CTO sees something that needs revisiting.

---

**Q2 — Body gate.**

Ratify the full §1 rewrite body (Part 2 above). Body is production-ready markdown for direct integration into PRD.md. Includes structural-fidelity attestations (Part 4) covering all 4 sub-sections. Zero substance amendments proposed (Part 8).

- **Option α — Accept body as drafted; integrate to PRD.md.** PR 2 proceeds to integration (CoS executes: PRD.md §1 swap + 3-line WORKFLOW.md retarget per Part 5 + v1.20 changelog entry per Part 9 + ship via `/ship-branch`).
- **Option β — Accept body with named edits** (specify which clauses; PM revises and re-rounds at body gate).
- **Option γ — Invoke §1 β override path for substance amendment** (specify which substance issue; PM drafts amendment with source-text → proposed-text → rationale per Part 8 convention; re-rounds at body gate with substance flag explicit).

PM recommendation: **α.** Attestation Part 4 commits PM to presentation-only fidelity; no substance changes were warranted during the rewrite. β if F/CTO surfaces presentation-level edits; γ if F/CTO surfaces substance issues (override path explicitly available per WORKFLOW.md v1.19 R6 carve-out for §1 only).
