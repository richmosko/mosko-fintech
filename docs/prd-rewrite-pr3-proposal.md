# PR 3 — §2 (V1 user stories) rewrite — PM structure proposal

> **Status:** Working PM deliverable returned 2026-05-18 for F/CTO structure-gate ratification (Q-S1 through Q-S6). Will be obsoleted (archived or deleted) once PR 3 ships. Per-§2.N body drafts deliver per body-gate cadence after structure gate locks.

[PM]:

# PR 3 — §2 (V1 user stories) rewrite — structure proposal

PR 3 is the largest and most pattern-setting PR in Step 3.5. Five sub-decisions warrant structure-gate ratify (Q-S1 through Q-S5) before any §2.x body drafts, plus a sixth (Q-S6) surfaced for routing-flag handling. **§2 is strictly presentation-only** per WORKFLOW.md v1.18 lock — no §2 β override available; any substance candidates I encounter route to Q7 = γ post-rewrite verify pass via Part 8 flag-only entries.

**Pattern-divergence-check declaration:** PR 3 uses **sub-section-gates** pattern per Q3 = γ; rationale: §2 is the largest source surface (6 sub-sections, ~580 lines), within the sub-section-gates-required scope (§4 + §2). Per Q-S1 (below), the proposed cadence is 1 structure gate + 6 body gates (one per §2.N).

---

## Part 1 — Structure proposal

### Sub-section layout table

Source-order parity preserved per Q2 = β. Section-title rewrites: zero proposed (the §2.x titles are already terse and accurate; no §1.3/§1.4-style rewrites warranted).

| Sub-§ | Title | Source line range | Sub-stories (primary + supporting) | Routing flags | Source character |
|---|---|---|---|---|---|
| 2.1 | Net worth | 78–130 | 5 primary (2.1.1–2.1.5) + 2 supporting (2.1.6, 2.1.7) = 7 stories | 5 (4 Arch + 1 Sec) | "Simple-shape" reference: each story = opener + `Traces to:` paragraph |
| 2.2 | Asset allocation | 132–171 | Primary + supporting + flags (count at draft time) | TBD | Same shape as §2.1 |
| 2.3 | Spending and income categorization | 173–221 | Primary + supporting + flags | TBD | Same shape as §2.1 |
| 2.4 | Cross-cutting stories | 223–290 | 4 primary (2.4.1–2.4.4) + 1 supporting (2.4.5) = 5 stories | 11 (10 Arch/Sec joint + 1 Sec at-lock pass-record) | "Medium-shape": each story = opener + multiple in-body sub-blocks + dense `Traces to:` tail |
| 2.5 | Estimated taxes | 292–455 | Primary + supporting + flags | TBD | Carries ADR-006 bracket-aware substructure; medium-to-complex shape |
| 2.6 | Monthly report | 457–end-of-§2 | 6 primary (§2.6.1–§2.6.6) + flags | TBD | "Complex-shape": each story = opener + many in-body sub-blocks + **inline markdown tables inside blockquotes** + V1/V2 boundary block + dense `Traces to:` tail |

**Story-ID convention quirk:** §2.6 uses `**§2.6.N …**` with `§` prefix in source story headers; §2.1 – §2.5 use `**2.N.K …**` without `§`. Rewrite normalizes to **`**2.N.K …**` form without `§` prefix** for §2.6 (matches the dominant pattern across §2.1–§2.5). Flagged as presentation-only normalization in Part 4 attestation.

### Three story-shape categories surfaced from source inspection

**Shape A — "Simple-shape" stories (§2.1, most of §2.2, §2.3, §2.5 supporting, §2.4.5 supporting).** Source is opener + `Traces to:` paragraph only. Rewrite: story opener stays as blockquote (per Q-S4 ratify); trace paragraph extracts to Appendix C in full; in-body footer `*Traces: see Appendix C → 2.N.K.*` per the PR 2 marker convention. Net: each story body shrinks to opener block + footer marker.

**Shape B — "Medium-shape" stories (§2.4.1, §2.4.2, §2.4.3, §2.4.4; some §2.5 primary).** Source has body sub-blocks (bold-lead-paragraph clusters) between opener and `Traces to:`. The sub-blocks are **load-bearing PRD substance**, not trace prose. Rewrite: story opener stays as blockquote; **all bold-lead body sub-blocks stay in-body** (e.g., §2.4.1 keeps "Plaid Link initiation", "Account-selection share decision is authoritative", "Per-account attributes after share selection", "Initial sync surfaces new symbols", "V1/V2 boundary"); trace extracts to Appendix C; footer marker added. Net: body content visually unchanged; only dense `Traces to:` tail moves.

**Shape C — "Complex-shape" stories (§2.6.1, §2.6.2, possibly §2.6.3+).** Source has body sub-blocks AND inline markdown tables inside blockquotes AND V1/V2 boundary blocks. Rewrite: story opener stays as blockquote; all bold-lead body sub-blocks stay in-body (composition contract scope / section list / cross-section data sources / owner-identification header / sections dropped / V1/V2 boundary); **inline markdown tables preserved verbatim including `>` blockquote prefix on table rows** (the source pattern works; the table renders correctly inside the blockquote; no shape change in PR 3); V1/V2 boundary block stays in-body (PRD substance, not trace); trace extracts to Appendix C; footer marker added.

**Trace-extraction classification triage (per PR 2 R2 mitigation).** For each story, the trace-tail is classified at draft time as:
- **(a) Pure trace** → moves to Appendix C verbatim (the common case).
- **(b) Embedded commitment** → stays in body as a bullet or sub-block (e.g., §2.4.5's "**Flagged for Security Reviewer** per §8.0" clause is half-trace, half-Sec-pass-record commitment — needs in-body retention).
- **(c) Routing-flag origin** → routes to Appendix B at PR 10 consolidation; in-body marker references §2.N's existing routing-flag block.

I will surface (b)/(c) classifications per sub-section in the per-sub-section structural-fidelity attestation at body-gate time. PR 2's R2 mitigation pattern carries forward unchanged.

### Routing-flag handling (Q-S6)

Each §2.N has an existing `#### Open routing flags affecting §2.N` block in source. Per the PR 2 marker convention, each §2.N's block stays in-body in the rewrite (it's already a structured list) — **the marker convention from PR 2 applies only when a section has zero routing flags or wants to consolidate into Appendix B at PR 10**. Two viable approaches for §2.N routing-flag handling:

- **(i) Keep routing-flag blocks in-body unchanged at PR 3; consolidate into Appendix B at PR 10 with in-body replacement to the marker.** Two-step: PR 3 preserves the blocks; PR 10 swaps them for `*Routing flags affecting §2.N: see Appendix B → flags 2.N-(a), 2.N-(b), …*` markers.
- **(ii) Move §2.N routing-flag blocks to Appendix B at PR 3 with in-body marker introduced immediately.** One-step: PR 3 extracts; PR 3 marker reads `*Routing flags affecting §2.N: see Appendix B (created in PR 10; pending consolidation).*` as PR 2 established.

**PM recommendation: (ii).** Reasons: (1) keeping routing flags in-body at PR 3 means §2 doesn't get the scannability improvement Step 3.5 is supposed to deliver until PR 10 ships; (2) the PR 2 marker convention explicitly bridges the not-yet-existing-Appendix-B case; (3) Appendix B consolidation at PR 10 has less work if the per-section extractions already happened; (4) two-step (i) creates additional editorial churn at PR 10 that PR 3 can absorb cleanly.

**Counterpoint:** option (i) keeps PR 3 strictly source-faithful and defers the consolidation editorial decision to PR 10 where Appendix B itself is being shaped. F/CTO has the call.

### Story-opener compression-form decision (Q-S4)

Per PR 2 Part 10 (i), two options:

**Option α — Preserve blockquote form with rename only.** Story openers stay as `> *As the Independent Investor, I want…*` blockquoted, story body stays as blockquote-prefixed paragraphs (status quo modulo rename).

**Option β — Compressed bullet form.** Remove the user-story prelude entirely; let context (§2.N position, story title in bold) carry the framing. Each story becomes a non-blockquote bullet block.

**PM recommendation: α.** Reasons: (1) source pattern is consistent across 30+ stories; β would re-shape every story even where source's user-story conventional form is the most useful affordance; (2) the user-story form ("As X, I want Y so that Z") is a recognized PRD convention that signals "this is a user-facing capability statement"; removing it makes the PRD less scannable for the audience that recognizes the convention; (3) β is a substance-adjacent change (removing the user-voice framing changes how the document reads) and on a presentation-only PR that risk-tier is too high; (4) α is the mechanical rename of 32 occurrences integrated into the no-other-body-changes pattern, matching the bounded reading from PR 2 Q-2 = α.

### In-body marker plan

| Marker | Used at | Form |
|---|---|---|
| Appendix B (routing flags) | Per §2.N (if Q-S6 = ii) | `*Routing flags affecting §2.N: see Appendix B (created in PR 10; pending consolidation).*` |
| Appendix C (Story Trace Index) | Per story footer | `*Traces: see Appendix C → 2.N.K.*` |
| ADR citation | Inline in body (anywhere) | `(ADR-NNN [Decision X])` or `(ADR-NNN §M.N)` — no re-narration |

### Sub-section gate cadence proposal (Q-S1)

**Recommendation: one body gate per §2.N.** Total PR 3 ratify gates: 1 structure (this proposal with Q-S1–Q-S6 sub-questions) + 6 body gates (one per §2.1, §2.2, §2.3, §2.4, §2.5, §2.6).

Each body gate ships a single sub-section's full rewrite: compressed openers per Q-S4 / §-prefix normalization (§2.6 only) / in-body sub-blocks preserved (categories B + C) / routing-flag handling per Q-S6 / Appendix C entries for that sub-section's stories.

Rationale: simpler than bundling §2.1+§2.2 or splitting §2.6 across multiple gates; matches "sub-section" granularity in the Q3 = γ pattern; gives F/CTO clean per-sub-section verify points for the largest and densest source section in the PRD.

**Alternative cadences considered and rejected:**
- 2-gate-per-§2.6 split (open-shape stories at one gate; tables-and-V1/V2 stories at another): adds two gates total for marginal value; §2.6 is large but coherent.
- §2.1 + §2.2 bundle (small sections together): saves one gate; loses the per-sub-section signal at body gate.
- Per-story gates (~30+ gates): over-corrected. β-pattern from PR 2 Q3.

### CoS integration notes

PR 3 will be the **largest PR of the rewrite** by file diff. Expected per-sub-section diff sizes (presentation-only; line counts approximate):
- §2.1: ~55 source lines → ~25 rewritten body lines + ~7 App C entries
- §2.2: ~40 → ~20 body + ~5 App C
- §2.3: ~50 → ~25 body + ~7 App C
- §2.4: ~70 → ~50 body + ~5 App C (category B preserves more in-body)
- §2.5: ~165 → ~100 body + ~10 App C
- §2.6: ~200 → ~150 body + ~10 App C (category C preserves the most)
- **Total: ~580 source lines → ~370 rewritten body lines + ~44 App C entries** (~30% body reduction; trace-tail content relocates to App C)

Plus Appendix C creation (PRD-internal or external per Q-S2) and per-§2.N routing-flag handling per Q-S6.

Likely multi-session given size. Per-§2.N body gate ratify + integrate-as-you-go cadence is feasible.

---

## Part 2 — Body draft

**Drafted incrementally per sub-section gate cadence.** This structure proposal commits to drafting §2.1 first (smallest, simplest-shape, lowest-risk for pattern establishment); §2.2 through §2.6 follow F/CTO sub-section gate ratifies one at a time.

**§2.1 body draft will be delivered at body-gate-1** after the five structure-gate Qs (Q-S1 through Q-S5) lock. Q-S6 also locks at structure gate (it informs routing-flag handling on §2.1 body draft).

Drafting §2.1 first lets us validate every Q-Sn decision against concrete content before applying patterns to the larger §2.4, §2.5, §2.6.

---

## Part 3 — Pattern-divergence-check declaration (for PR body)

> **Pattern-divergence-check (Step 3.5 convention).** PR 3 uses **sub-section-gates** pattern per Q3 = γ; rationale: §2 is the largest source surface (6 sub-sections, ~580 source lines), within the sub-section-gates-required scope (§4 + §2). Cadence: 1 structure gate + 6 body gates (one per §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6). First PR in the rewrite to exercise sub-section gates; establishes the per-§2.N body-gate cadence that PR 5 (§4) inherits. **No bulk-closeout, no per-bullet gates, no per-story gates.** §2 is strictly presentation-only per WORKFLOW.md v1.18 lock; no §2 β override path available.

---

## Part 4 — Structural-fidelity attestation (framework)

Six per-sub-section attestations to be delivered at each body gate. Each attestation will cover:

1. **Story-opener compression preserving substance.** Each story's opener (the "As the Independent Investor, I want…" sentence) rewritten per Q-S4-locked form; substance preserved verbatim modulo rename.
2. **Trace-tail extraction completeness.** Every `Traces to:` clause classified as (a) pure trace → App C, (b) embedded commitment → in-body, (c) routing-flag origin → App B at PR 10. Per-story classification breakdown listed.
3. **Body sub-block preservation.** For category B + C stories, all bold-lead in-body sub-blocks preserved verbatim except for normalization (e.g., §-prefix removal on §2.6 story IDs; if any source paragraph carries the archetype name in non-opener position, rename applied).
4. **Rename instance count per §2.N.** Verification that exact count of "Independent Investor" instances in rewritten §2.N matches the count of "self-directed multi-account owner" instances in source §2.N (i.e., complete + faithful rename, no extras introduced, no instances missed).
5. **Routing-flag handling per Q-S6.** Per-sub-section routing-flag block disposition documented (extracted to App B per (ii) / preserved in-body per (i)).
6. **Zero substance amendments per Step 3.5 constraint on §2.** Substance candidates (if any) routed to Part 8 (Q7 = γ post-rewrite verify-pass flags), not landed mid-rewrite.

PR 2's R1 mitigation pattern carries forward: each attestation explicitly calls out editorial-choice surfaces (e.g., §-prefix normalization on §2.6 story IDs; table-blockquote-prefix preservation).

---

## Part 5 — Cross-reference sweep (per Q4 = α)

### PRD.md:NNN line refs inside §2 source range (archive lines 60–end-of-§2 ≈ line 635)

Greppped WORKFLOW.md + DECISIONS.md for line-anchored refs. **Zero hits in §2 range.**

Surviving line refs in WORKFLOW.md are `PRD.md:689` (§3.4) and `PRD.md:820` (§5.7) — both outside §2 scope. DECISIONS.md `§1.X` references are to ADR-002 internal numbering, not PRD §1.x.

**Zero retargets needed in PR 3.** This is a clean result — §2 was drafted under the per-sub-section pacing pattern with cross-references rendered as section-anchors (`§2.1.5`, `§2.4.4`, etc.) rather than line numbers, so the Q4 = α sweep has nothing to do for PR 3.

### Repo-wide archetype-name rename completion

Per PR 2 Q-2 = α bounded reading: PR 3 completes the §2.x archetype rename (32 instances). Full per-line list (current PRD.md on main, post-PR-2 merge):

| §2.N | Story | Line |
|---|---|---|
| §2.1 | 2.1.1 | 83 |
| §2.1 | 2.1.2 | 88 |
| §2.1 | 2.1.3 | 93 |
| §2.1 | 2.1.4 | 98 |
| §2.1 | 2.1.5 | 103 |
| §2.1 | 2.1.6 | 110 |
| §2.1 | 2.1.7 | 115 |
| §2.2 | 2.2.1 | 137 (verify at body draft) |
| §2.2 | 2.2.2 | 142 |
| §2.2 | 2.2.3 | 147 |
| §2.2 | 2.2.4 | 154 |
| §2.3 | 2.3.1 | 178 |
| §2.3 | 2.3.2 | 183 |
| §2.3 | 2.3.3 | 188 |
| §2.3 | 2.3.4 | 193 |
| §2.3 | 2.3.5 | 200 |
| §2.4 | 2.4.1 | 228 |
| §2.4 | 2.4.2 | 243 |
| §2.4 | 2.4.3 | 248 |
| §2.4 | 2.4.4 | 261 |
| §2.4 | 2.4.5 | 268 |
| §2.5 | 2.5.1 | 297 |
| §2.5 | 2.5.2 | 316 (verify) |
| §2.5 | 2.5.3 | 353 (verify) |
| §2.5 | 2.5.4 | 382 (verify) |
| §2.5 | 2.5.5 | 412 (verify) |
| §2.6 | 2.6.1 | 462 |
| §2.6 | 2.6.2 | 499 |
| §2.6 | 2.6.3 | 526 |
| §2.6 | 2.6.4 | 555 |
| §2.6 | 2.6.5 | 584 |
| §2.6 | 2.6.6 | 607 |

All 32 instances are user-story openers of the form `As the self-directed multi-account owner, I want…` (verified at PR 2's repo-wide grep). Rewrite: rename to `As the Independent Investor, I want…` per Q-S4 = α opener-preservation form. Per-§2.N rename counts recorded in per-sub-section attestation (Part 4).

**No DECISIONS.md edits.** Confirmed at PR 2: ADRs don't name the archetype.
**No WORKFLOW.md edits.** Historical entries (line 383 mention) stay per immutability convention.
**No docs/ historical-artifact edits.** Per PR 2 forward-convention.

---

## Part 6 — Routing-flag handling note

§2.N routing-flag counts (verified by inspection):

| §2.N | Routing flags in source |
|---|---|
| §2.1 | 5 (4 Architect + 1 Security Reviewer pass-with-comments record) |
| §2.2 | TBD at body draft (verify count) |
| §2.3 | TBD |
| §2.4 | 11 (10 Architect/Sec joint + 1 Security Reviewer at-lock verdict) |
| §2.5 | TBD |
| §2.6 | TBD |
| **Total estimated** | **~35–40** across §2 (largest routing-flag concentration in the PRD; many are Phase 3 Architect surfaces) |

**Handling per Q-S6 (locked at structure gate):**
- **If Q-S6 = (i):** Routing-flag blocks stay in-body unchanged at PR 3; PR 10 consolidates with in-body markers.
- **If Q-S6 = (ii):** Routing-flag blocks extract to Appendix B at PR 3 (deferred-consolidation form); in-body markers replace the blocks immediately.

PR 10 Appendix B consolidation strategy (regardless of Q-S6): global flag-ID scheme `§N.M-(letter)` per PM Q proposal in PR 2 ("section-anchor + letter"). For example, §2.4's flag (a) Architect — Plaid metadata recommendation engine becomes `§2.4-(a)` in Appendix B index.

**§2.4 routing-flag (k) special handling.** §2.4's flag (k) is a Security Reviewer at-lock verdict + two-touch consult pattern record — it's a process-record entry, not a forward-looking routing flag. Two options at Appendix B consolidation: (1) keep in App B as a routing-flag entry tagged "process record"; (2) relocate to WORKFLOW.md (per Q1 = β Acceptance-flags relocation convention). PM recommendation: option (2) — process records belong in WORKFLOW.md, not in PRD body or PRD appendix. **Flagged for PR 10 Appendix B consolidation decision; not a PR 3 decision.**

---

## Part 7 — Acceptance-flags relocation

Per Q1 = β: rewritten §2.N sub-sections carry **no `#### Acceptance flags` block** in PRD body. §2.1–§2.6 lock metadata preserved across WORKFLOW.md v1.10–v1.15 entries (the per-section lock changelogs) + v1.18 §8-lock-time recap. PR 3 adds v1.21 entry covering PR 3 ship.

For reference (verified from WORKFLOW.md header context): §2.1 lock = v1.10-era 2026-05-14; §2.2 lock = 2026-05-15; §2.3 lock = 2026-05-17; §2.4 lock = 2026-05-15; §2.5 lock = 2026-05-17; §2.6 lock = 2026-05-17. Each has Security Reviewer pass-with-comments verdicts recorded in the corresponding WORKFLOW.md changelog entries.

---

## Part 8 — Substance-flag candidates for post-rewrite verify pass

**Per Step 3.5 constraint: §2 is presentation-only. Substance flags route to Q7 = γ verify pass, not mid-rewrite amendments.**

Surfaced during this structure proposal's source inspection (more may surface during per-§2.N body drafts and will be added at each body-gate-time):

**Flag PR3-VP-1 — §2.6.1 story ID prefix inconsistency.**
- **Source text:** §2.6 story IDs use `**§2.6.N …**` form (§-prefix); §2.1 – §2.5 use `**2.N.K …**` form (no §-prefix).
- **Concern:** Formatting inconsistency only; not substance. PR 3 normalizes to no-§-prefix form per dominant pattern (presentation-only normalization documented in Part 4 attestation).
- **Recommended verify-pass treatment:** Not a verify-pass candidate — it's a presentation cleanup the rewrite handles directly. **Listed here for visibility only; deferring zero verify-pass surface.**

**Flag PR3-VP-2 — §2.4.5 supporting-story dual-classification.**
- **Source text:** §2.4.5 is the supporting story (write-path tenant isolation), and §2.4 routing-flag (k) (Security Reviewer at-lock verdict) duplicates substantial content from §2.4.5's trace tail (e.g., "(a) write-path RLS symmetry, (b) scope-attribute continuity, (c) manual-entry-as-elevated-risk acknowledgment" appears in both surfaces).
- **Concern:** Duplication between §2.4.5 trace and §2.4 routing-flag (k) process-record. Trace-extraction at PR 3 may surface the duplication explicitly; the right resolution (consolidate? attribute to canonical home?) is a substance call.
- **Recommended verify-pass treatment:** Verify-pass flag — the duplication is a presentation issue that *might* be a substance issue (which surface is authoritative for the §2.4.5 commitments?). PM defers the resolution call.

**Flag PR3-VP-3 — §2.6.2 σ-1 / σ-2 / σ-3 framing depth.**
- **Source text:** §2.6.2 "Free-text user-authored under σ-1" body sub-block describes σ-1 / σ-2 / σ-3 as locked product alternatives, with σ-1 (free-text) as the V1 lock and σ-2 (auto-generate) / σ-3 (hybrid) as rejected V2+ candidates.
- **Concern:** The σ-N nomenclature is internal-decision-shorthand, not user-facing PRD content. Source documents the rejection of σ-2 and σ-3 in detail. R1-mitigation classification: the σ-N rejection-narrative paragraph reads more like trace content (why σ-1 was chosen) than substance (the lock itself is one clause). The boundary between in-body-substance and `Traces to:` content is fuzzy here.
- **Recommended verify-pass treatment:** Verify-pass flag — at verify pass, F/CTO can confirm whether σ-N rejection narrative belongs in-body (PRD substance) or in trace (App C). PM defers; PR 3 preserves in-body verbatim to avoid mid-rewrite substance touch.

**Flag PR3-VP-4 — §2.6 stories include multi-paragraph V1/V2 boundary blocks (separate from `Traces to:`).**
- **Source text:** §2.6.1 and §2.6.2 each include an explicit `**V1/V2 boundary.**` body sub-block enumerating V1 commitments + V2+ deferrals.
- **Concern:** Other §2.N sub-sections incorporate V1/V2 boundaries inline within story openers or attribute footers; only §2.6 has the explicit boundary sub-block. Presentation inconsistency; might also indicate that §2.6 is treated as a higher-load-bearing canonical-reference layer than §2.1–§2.5.
- **Recommended verify-pass treatment:** Verify-pass flag — at verify pass, F/CTO can decide whether V1/V2 boundary blocks should propagate up to §2.1–§2.5 for consistency, or whether §2.6's treatment is correctly special. PM defers; PR 3 preserves §2.6's V1/V2 boundary blocks verbatim.

**Pending additions:** More VP flags may surface during per-§2.N body drafts (especially §2.5 + §2.6 per R8 rubber-stamp concentration). Each is added to Part 8 at the corresponding body gate, then the consolidated Part 8 lands in v1.21 changelog entry.

**PM scope discipline note:** none of the four VP flags above warrant mid-PR-3 substance amendments. All are presentation-adjacent observations that will benefit from verify-pass-stage F/CTO engagement under the dedicated substance-review cadence.

---

## Part 9 — WORKFLOW.md v1.21 changelog entry framework

Drafted at each body-gate per-§2.N cadence; consolidated entry lands at PR-3-ship-time. Framework follows v1.20 scannable shape (full draft template in PM deliverable — omitted here for brevity; will be filled in incrementally as body gates land).

---

## Part 10 — Risks and open questions for PR 4+

**(a) Sub-section-gate cadence proof-of-concept.** PR 3 is the first sub-section-gates PR. If the 6-body-gate cadence proves either too granular (gate fatigue) or too coarse (within-§2.N issues missed), PR 5 (§4) inherits the lesson and can adjust. PR 5 = §4 has 6 sub-sections + 2 markdown tables (§4.4 + §4.5); the table sub-sections might warrant their own gates (Q-S1-equivalent at PR 5 structure gate).

**(b) Appendix C scale.** PR 3 creates the largest single appendix. If F/CTO experiences Appendix C navigation friction (per Q-S2 lock = α or β), PR 5 may want to consider whether §4's `Traces to:` content also routes to App C (§4 has different trace patterns than §2; per-row table cross-references vs. per-story tail).

**(c) Routing-flag handling pattern (Q-S6 lock at PR 3 structure gate).** Whatever PR 3 locks at Q-S6 propagates as the convention for PR 4 (§3 has 6 flags), PR 5 (§4 has 11 active + 5 boundary), PR 6 (§5 has 6), PR 7 (§6 has 3), PR 8 (§7 has 5), PR 9 (§8 has 5 boundary). PR 3 sets the precedent for ~36 more routing flags across PR 4–9.

**(d) Story-opener form consistency.** If Q-S4 locks α (preserve-blockquote), the same form propagates through all §2.N body gates. If F/CTO discovers mid-rewrite that the opener form looks redundant on a specific story (e.g., §2.4.5 supporting story openers are arguably the weakest), the body-gate can flag without re-opening Q-S4 — preserve-form-but-note-as-VP-flag.

**(e) Section-title convention.** PR 3 proposes zero §2.N title rewrites. If F/CTO surfaces a title-rewrite candidate at any §2.N body gate, PR 3 can absorb it within that body gate (single body gate is the right surface to land per-§2.N micro-edits). PR 2's title-rewrite pattern (propose at structure; attest as meaning-equivalent) carries forward.

**(f) Q4 = α retargeting volume.** PR 3 = 0 retargets. PR 4 (§3) source has `PRD.md:689` → §3.4 retarget. PR 6 (§5) has `PRD.md:820` → §5.7 retarget. PR 5 (§4) has `PRD.md:805` / `:808` / `:820` per the original sweep — multiple retargets. PR 5 is the heaviest retarget PR; PR 3 is the lightest.

**(g) Pattern-implication: PR 3 establishes that "compressed" §2 is mostly *unchanged in-body* with the trace-tail extracted.** This is a less aggressive editorial lift than the PR 2 §1.1 paragraph-to-bullet compression. The compression-ratio variance per PR 2 R(d) continues to be content-shape-driven; PR 3 supplies the largest data point.

**(h) §2.4.5 ↔ §2.4 routing-flag (k) duplication (VP-2).** Surfaced in Part 8. PR 3 preserves both; verify-pass-stage F/CTO call. Pattern-implication: if other §2.N's have similar duplication (e.g., §2.2.4 / §2.3.5 supporting stories vs. their §2.N routing-flag verdict entries), PR 3 surfaces them as additional VP flags during per-§2.N body drafts.

**(i) §2.6 special-shape inheritance.** §2.6 has the densest, most complex source shape (category C: opener + many sub-blocks + tables + V1/V2 boundary + dense trace). PR 3 body-gate-6 (§2.6) will be the most editorially complex per-sub-section gate. If F/CTO wants to pre-split §2.6 into smaller gates (e.g., §2.6.1 alone; §2.6.2–§2.6.4; §2.6.5–§2.6.6), that's an alternative cadence-decision worth flagging at structure gate. **PM does not propose pre-splitting §2.6** — coherence of one-gate-per-sub-section convention is more valuable than per-§2.6 micro-pacing — but flagging as available if F/CTO wants finer pacing on the largest source surface.

---

## Embedded ratify questions for structure gate

Per project pacing memory, sequenced one-at-a-time. Six sub-questions: Q-S1–Q-S5 (per CoS brief) + Q-S6 (surfaced by PM during inspection).

---

**Q-S1 — Sub-section gate cadence.** Three options (α: one gate per §2.N; β: pair sub-sections; γ: split §2.6). PM recommendation: **α** (one gate per §2.N).

**Q-S2 — Appendix C location.** Two options (α: PRD-internal; β: separate file). PM recommendation: **α** (PRD-internal; single source of truth).

**Q-S3 — Appendix C entry format.** Three options (α: blockquote preserve; β: flat normalize; γ: hybrid bold-prefix + blockquote). PM recommendation: **γ** (hybrid; navigable as reference index, source-faithful in trace content).

**Q-S4 — Story-opener compression form.** Two options (α: preserve blockquote with rename; β: compressed bullet). PM recommendation: **α** (preserve PRD-convention user-story shape; lowest editorial risk on presentation-only PR).

**Q-S5 — Structure-gate acceptance.** Three options (α: accept; β: revise; γ: defer). PM recommendation: **α** (after Q-S1–Q-S4 + Q-S6 lock).

**Q-S6 — Routing-flag block handling at PR 3.** Two options ((i): preserve in-body, consolidate at PR 10; (ii): extract to App B now with bridge marker). PM recommendation: **(ii)** (one-step; §2 gets scannability improvement at PR 3; PR 10 becomes mechanical).
