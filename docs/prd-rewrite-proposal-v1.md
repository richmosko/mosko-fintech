# PRD.md editorial rewrite — target-shape proposal (Phase 1 Step 3.5)

> **Status:** Working PM proposal returned 2026-05-18 for F/CTO ratification. Will be obsoleted (archived or deleted) once Phase 1 Step 3.5 ships. Decisions ratified from this proposal land in `WORKFLOW.md` v1.19.

[PM]:

## Premise

The PRD has accumulated to ~1,090 lines / ~37k tokens across 8 top-level sections, with the body composed mostly of long blockquoted user stories, inline `Traces to:` rationale paragraphs, and dense routing-flag blocks. F/CTO's rubber-stamp concern at the §6 / §7 / §8 + §4 posture surfaces is structurally explainable: the late sections re-state framing already locked elsewhere, and rationale is interleaved with the actual locked statement at a 5:1 ratio (rough eyeball — a one-sentence commitment routinely carries a five-sentence rationale tail). The reader cannot scan; they can only read linearly.

This proposal is **presentation-only**. No substance changes. The deliverable is a structurally lighter PRD that surfaces every locked commitment with less prose around it, pushing rationale and structured-data appendices to dedicated locations. ADRs in DECISIONS.md stay where they are; the PRD points to them by ID rather than re-narrating them.

---

## 1. Current PRD.md structural map

The PRD has 8 top-level sections + 2 appendix stubs. Sizes and content character below.

| § | Title | Approx. lines | Sub-sections | Content character | Density note |
|---|---|---|---|---|---|
| 1 | Vision and target user | 47 | 4 (1.1–1.4) | Prose paragraphs; archetype attributes; deferral list. | Moderate. Light cleanup target. |
| 2.1 | Net worth | 54 | 5 primary + 2 supporting stories + flags | Blockquoted user stories + inline `Traces to:` rationale paragraphs per story | High. Each story is paired with a multi-sentence trace block. |
| 2.2 | Asset allocation | 41 | Primary + supporting + flags | Same as 2.1 | High. |
| 2.3 | Spending and income categorization | 50 | Primary + supporting + flags | Same as 2.1 | High. |
| 2.4 | Cross-cutting (onboarding, manual, re-auth) | 69 | Primary + supporting + flags | Same as 2.1 | High. |
| 2.5 | Estimated taxes | 165 | Primary + supporting + flags | Same as 2.1 — **largest §2 sub-section**; carries the ADR-006 bracket-aware substructure | Very high. Hardest to scan. |
| 2.6 | Monthly report | 198 | Primary + supporting + flags | Same as 2.1 — **largest section overall**; carries report-composition contract + snapshot store + staleness | Very high. |
| 3 | Success metrics | 80 | 5 (3.1–3.5) | Three-axis framing + 6 capability metrics + 6 parity tests + 3 migration criteria + 7 non-metrics + flags | Moderate. Mostly bulleted-with-framing already; routing flags 6 items. |
| 4 | Security and compliance posture | 127 | 6 (4.1–4.6) | **Mixed shape**: bulleted-with-framing posture (4.1–4.3 + 4.6) + 2 markdown tables (4.4 14×8 sensitive-data matrix; 4.5 15×7 RLS test catalog); 11 active + 5 boundary-note routing flags | Very high. Tables are the densest single surface in the PRD; posture sub-sections have rationale-heavy bullets. |
| 5 | V2 deferred candidates | 110 | 7 (5.1–5.7) | Sub-grouped V2+ inventory; 6 routing flags | Moderate-high. |
| 6 | Out-of-scope for this PRD lifecycle | 40 | 5 (6.1–6.5) | One axis per sub-section; framing paragraph + 1–2 bullets each | Moderate. Five framings re-state product-identity axes; some redundancy with §1.4 / ADR-002 §3.0 / ADR-007. |
| 7 | Constraints | 44 | 3 (7.1–7.3) | Cost / scale / usage-model bullets; 5 routing flags | Light. |
| 8 | V1 milestone framing | 47 | 3 (8.1–8.3) | Sub-version convention + drop-replace + V1-done cross-reference; 5 boundary-note flags | Light. |
| App A | Traceability to ADR-002 verdicts | 0 (stub only) | — | Stub; "Appendix A absorption deferred" per §4 housekeeping convention | Empty. |
| App B | Open routing flags (Architect / Sec) | 0 (stub only) | — | Stub | Empty. |

**Dense surfaces driving overload (rank-ordered):**

1. **§2.6 + §2.5 user-story trace tails.** Each blockquoted story carries a multi-sentence `Traces to:` paragraph that cites ADR sub-sections by ID *and* re-narrates the ADR's reasoning. The re-narration is the bulk; the citation is the load-bearing part.
2. **§4.4 + §4.5 tables.** Structurally correct (matrices belong in tables), but they sit in the middle of the document where a scanning reader will not encounter them in context. They're reference data, not narrative.
3. **§4 posture sub-sections (4.1–4.3 + 4.6).** Bulleted-with-framing, but each bullet is a paragraph. The §4.6 retention/availability/incident-handling bullets in particular each pack 5–8 sentences of rationale around a single commitment.
4. **Routing-flag blocks under every section.** Each section ends with an `Open routing flags affecting §N` block of 3–11 items. These items are heterogeneous (Architect flags, Sec flags, V1-blocker flags, boundary-note closures) but visually flat — the reader cannot distinguish "this blocks V1 ship" from "this documents that X closes Y."
5. **`#### Acceptance flags` blocks under every section.** Each section ends with a process-narrative paragraph block: lock date, ratification counts, pattern-divergence notes, PR shipping plan. This is operating-record content that belongs in WORKFLOW.md, not PRD.md.
6. **§6 framing-paragraph-per-axis.** Each of 6.1–6.5 opens with a framing paragraph that re-states the axis already named in §1.4 / ADR-002 §3.0 / ADR-007. Five framings doing the same work.
7. **§2.x supporting-story `Traces to:` paragraphs.** Same shape as primary stories but the underlying capability is itself less load-bearing — supporting stories are often single-sentence in commitment but multi-paragraph in trace.

---

## 2. Proposed new top-level outline

The rewritten PRD keeps section-numbering parity with the source so that all existing external references (WORKFLOW.md, DECISIONS.md, the parity matrix) continue to resolve. Below the §-number, the **shape** changes: every section becomes scan-first.

```
PRD.md (rewritten)

  [Document overview]               NEW — see §3 of this proposal
  [Reading guide]                   NEW — 4-line orientation block
  [Section index]                   NEW — TOC with one-line summary per §

  §1 Vision and target user          (preserved; cleaned up; framing kept)
    §1.1 Vision                       1 paragraph
    §1.2 Target user archetype        bulleted attributes; one bullet per
    §1.3 Why archetype, not "me"      3 numbered points
    §1.4 Deferred user-shape items    bulleted; cross-ref §6 only

  §2 V1 user stories                 (preserved; per-story shape changes)
    §2.1 Net worth                    user stories as compact bullets,
    §2.2 Asset allocation             trace tails moved to Appendix C
    §2.3 Spending and income          (Story Trace Index)
    §2.4 Cross-cutting
    §2.5 Estimated taxes
    §2.6 Monthly report

  §3 Success metrics                 (preserved; bulleted-with-framing
                                      already; light trim)
    §3.1 Framing
    §3.2 Capability-delivery metrics
    §3.3 Parity metrics
    §3.4 Migration-completion / V1-done
    §3.5 Explicit non-metrics

  §4 Security and compliance posture (preserved structure; tables stay
                                      in body — they're load-bearing
                                      reference data the body cites)
    §4.1 Tenant isolation             posture statements as bullets
    §4.2 Credential / external API    posture statements as bullets
    §4.3 Derivative-persistence       posture statements as bullets
    §4.4 Sensitive-data classification matrix     (table; unchanged)
    §4.5 Phase 3 RLS test catalog                 (table; unchanged)
    §4.6 Cross-cutting commitments    retention/availability/incident
                                      as bullets; V2-ship-gate inventory
                                      as compact list

  §5 V2 deferred candidates          (preserved; sub-section trims)

  §6 Out-of-scope for this PRD       (preserved; per-axis trims —
   lifecycle                          one framing line, not paragraph)

  §7 Constraints                     (preserved; minor trims)

  §8 V1 milestone framing            (preserved; minor trims)

  Appendix A — ADR-002 verdict traceability    (stays a stub or absorbed
                                                in housekeeping PR — out
                                                of scope for this rewrite)
  Appendix B — Open routing flags              NEW content: consolidated
                                               Architect / Sec routing-
                                               flag index, sourced from
                                               per-section blocks
  Appendix C — Story Trace Index               NEW: per-§2-story
                                               `Traces to:` content,
                                               moved out of inline body
  Appendix D — Process and lock record         NEW: per-section
                                               Acceptance flags content
                                               consolidated; PR list;
                                               ratification record
                                               (candidate: relocate
                                               entirely to WORKFLOW.md —
                                               see Q5)
```

**Mapping from current to proposed:**

| Current location | Proposed location | Notes |
|---|---|---|
| Frontmatter + opening reading-order note | New `[Document overview]` + `[Reading guide]` + `[Section index]` | Expanded from 2 lines to ~25-line head block. |
| §1.1–§1.4 body | §1.1–§1.4 (same) | Light cleanup. |
| §2.x primary/supporting stories | §2.x bullets | Story format compressed. |
| §2.x inline `Traces to:` paragraphs | **Appendix C — Story Trace Index** | Extracted; cited by story ID inline. |
| §3.1–§3.5 body | §3.1–§3.5 (same) | Light trim. |
| §4.1–§4.3 + §4.6 bullets | §4.1–§4.3 + §4.6 (same shape, lighter bullets) | Rationale-paragraph bullets compressed. |
| §4.4 + §4.5 tables | §4.4 + §4.5 (unchanged — tables already structured) | Tables are the load-bearing reference; they stay. |
| §5.1–§5.7 body | §5.1–§5.7 (same) | Light trim. |
| §6.1–§6.5 framing paragraphs | §6.1–§6.5 (one-line framing + bulleted commitment) | Reduce paragraph framing to one line per axis. |
| §7.1–§7.3 body | §7.1–§7.3 (same) | Light trim. |
| §8.1–§8.3 body | §8.1–§8.3 (same) | Light trim. |
| Per-section `Open routing flags` blocks | **Appendix B — Open routing flags** (consolidated) | In-body marker: "Routing flags affecting §N: see Appendix B." |
| Per-section `Acceptance flags` blocks | **Appendix D — Process and lock record** (or relocate to WORKFLOW.md) | See Q5. |
| Appendix A stub | Appendix A stub (unchanged) | Housekeeping PR territory; not this rewrite. |

---

## 3. Overview section shape

The `[Document overview]` block at the document head answers the four questions a scanning reader has in the first 30 seconds. It is bulleted-with-framing — the format the project has quintuple-confirmed for PM-led sections. Target length: ~150 words.

**Contents (bulleted):**

- **What mosko-fintech V1 is, in one sentence.** A personal financial observatory — single trustworthy view of one user's complete position, observational not advisory, that progressively replaces an existing manual-spreadsheet system. (Synthesized from §1.1.)
- **Who V1 is for.** The self-directed multi-account owner archetype; V1 instance is the Founder/CTO (population of one). Pointer: §1.2.
- **The three V1 user-facing surfaces.** Net worth, asset allocation vs. target, spending and income categorization — powered by Plaid Transactions + Investments + manual entry; canonical V1 deliverable is the **monthly Finance Report**. Pointers: §2.1–§2.6.
- **The V1 boundary.** Multi-tenant infrastructure from day one + single-user usage; observational only — no money movement, no advisor role, no public sign-up. Pointers: §6 (out-of-scope axes), §7 (constraints).
- **How V1 ships.** Sub-version sequence V1.0 → V1.x → V1.final; drop-replace migration pattern preserves the F/CTO's monthly workflow during data-plane transition. Pointer: §8.
- **V1 done definition.** Three migration-completion criteria (parity-matrix V1-preserve complete, ADR-004/005/006 amendments delivered, existing-system retired for N=2 consecutive months). Pointer: §3.4.
- **Where decisions live.** This PRD is locked product scope; ADRs in `DECISIONS.md` carry the reasoning per ID (ADR-002 ratification + ADR-004 script-audit amendments + ADR-005/006/007 surgical amendments + ADR-008 V1 Sec canonical reference). Architecture decisions live in `ARCHITECTURE.md` (Phase 3 territory, not this document).

`[Reading guide]` block (~4 lines): which audience reads which sections — Architect reads §4 + Appendix B; Sec reads §4 + Appendix B; Phase 4 / Linear scoping reads §2 + §8 + Appendix C; F/CTO and future-self read this overview + §1 + §3.

`[Section index]` block: section-by-section one-line TOC. Eight entries plus appendices.

---

## 4. Appendix structure

Four appendix slots proposed; two are existing (A, B-stub), two are net-new (C, D). The distinction the user's task asks about — citation-pointers vs. rationale-extraction — applies as follows:

**Citation-pointers only (in-body):**

- **ADR references.** Every PRD body bullet that today carries a rationale paragraph citing an ADR keeps the ID-level pointer (e.g., "per ADR-004 Decision B") but drops the re-narration. Full rationale stays in `DECISIONS.md`. **Distinguishes from rationale-extraction:** the reasoning is not relocated; it's already in DECISIONS.md by design, the PRD just stops duplicating it.
- **Forward-pointer closures.** Today these are written out as multi-clause sentences ("closes the §3.4 → §8 forward-pointer at `PRD.md:689` at this lock per routing flag (a) below"). In the rewrite: short closure-table entries in Appendix B, with in-body marker "§N closes forward-pointers to §M (see App B)."
- **Cross-section commitments (e.g., §8.2 cross-references §4.6).** Body keeps the cross-reference; rationale for *why* the cross-reference holds drops to one line.

**Rationale-extraction to appendices:**

- **Appendix C — Story Trace Index.** Today every §2.x user story has a 4–10-sentence `Traces to:` paragraph immediately below it. Proposal: extract these into Appendix C as a flat list keyed by story ID (2.1.1, 2.1.2, …, 2.6.N). Each entry has the original `Traces to:` content unchanged. In-body marker: each story footed with "Traces: see App C → 2.1.1." This is the single largest editorial change by line-count delta — roughly 350–450 lines of trace prose move to one place. **Why appendix not deletion:** the trace content carries verified F/CTO-system-grounded sourcing (parity-matrix line numbers, page references in the existing Finance_Report PDF, F/CTO-direct-inspection notes) that needs to stay reachable; it just doesn't need to interrupt the story-by-story scan.
- **Appendix B — Open routing flags.** Per-section routing-flag blocks consolidate into Appendix B with three columns: flag ID / target (Architect / Sec / Architect+Sec joint / Boundary note) / status (V1-block / V1-locked-at-PR-review / V2-gate / Phase-3 / Closed). In-body marker: "Routing flags affecting §N: see App B → flags (a)–(e)." **Why appendix not in-body:** routing flags are a Phase 3 / Phase 6 consumption surface that Architect and Sec re-read in those phases as a working index, not a section-by-section bag. A consolidated index is what they actually need; the per-section spread is artifact of the section-by-section drafting cadence, not how the content gets consumed.
- **Appendix D — Process and lock record (candidate; see Q5).** Per-section `Acceptance flags` blocks today carry: lock date, ratify count (e.g., "PM-lean 23-for-23"), pattern-divergence notes, PR number, Sec/Architect at-lock-pass status. This is operating-record content; it is duplicated in WORKFLOW.md changelog v1.13–v1.18 entries. Two options live in Q5.

**Structured data (tables) — stays in body:**

- **§4.4 sensitive-data classification matrix** (14×8). Tables are scannable by construction; they're load-bearing reference data the §4.1 / §4.3 body cites. They stay.
- **§4.5 Phase 3 RLS test catalog** (15×7). Same.

**Long-paragraph rationale that should be bulleted in body (not extracted):**

- **§4.1 + §4.3 axis-clause bullets.** Each clause today is a 3–6-sentence paragraph-bullet. Rewrite shape: lead clause sentence + 2–3 nested sub-bullets covering boundary cases + 1 cross-reference line. Same content; structurally scannable.
- **§4.2 credential-error states bullet.** Today: one mega-bullet listing 4 error states inline. Rewrite shape: 4 sub-bullets, one per state.
- **§4.6 retention/availability/incident bullets.** Each today is a 5–8 sentence paragraph. Rewrite shape: lead commitment line + 3–4 nested sub-bullets covering canonical values + cross-references + closure citations.
- **§6 per-axis framing paragraphs.** Today: ~3-sentence framing paragraph above each axis bullet. Rewrite shape: one framing sentence + bullet of the actual commitment. Eliminates repeated boundary-restating.

---

## 5. Rewrite-section ordering

Recommended order: **smallest-first**, with one adjustment.

**Proposed sequence:**

1. **§8 Milestone framing** (47 lines, 3 sub-sections, mostly cross-references)
2. **§7 Constraints** (44 lines, 3 sub-sections, mostly bullets already)
3. **§6 Out-of-scope** (40 lines, 5 axis sub-sections)
4. **§1 Vision and target user** (47 lines, 4 sub-sections, framing-heavy)
5. **§3 Success metrics** (80 lines, 5 sub-sections, bulleted-with-framing)
6. **§5 V2 deferred candidates** (110 lines, 7 sub-sections)
7. **§4 Security and compliance posture** (127 lines, 6 sub-sections, mixed table+prose)
8. **§2 user stories** (~580 lines across 6 sub-sections — largest)
9. **Document overview + reading guide + section index** (NEW, lands last after structure of body is locked)
10. **Appendices B + C + D** (NEW or consolidated, last)

**Rationale for smallest-first:**

- §8, §7, §6 are the rubber-stamp-risk sections F/CTO flagged. Touching them first lets F/CTO see the rewrite *pattern* applied to high-risk surfaces while the surfaces are small enough to read with full nuance.
- Body shape decisions made on small sections (e.g., how to compress a paragraph-bullet, how to handle a routing-flag pointer) become the **patterns** the larger sections inherit. This is the inverse of the Step 3 drafting order (which went forward through §3 → §5 → §6 → §7 → §8 then circled back to §4); the rewrite benefits from the reverse because pattern-discovery happens on small surfaces.
- §2 last because (a) the Story Trace Index extraction is the largest mechanical change and benefits from the appendix pattern being already proven elsewhere, (b) the §2 trace tails are the densest single content surface, and (c) by the time §2 is rewritten the routing-flag and acceptance-flag patterns are already settled.

**Adjustment from pure-smallest-first:** §1 promotes from natural fourth-smallest (47 lines tied with §8) to a slot **after the V2/non-goal/constraints sub-sections are rewritten**, because §1.4's deferred-user-shape items cross-reference §6 and §5; rewriting §1.4 against rewritten §6 + §5 is cleaner than rewriting it twice. (Slot 4 in the sequence above already reflects this.)

**Alternative — match source order:** rewrite §1 → §2 → ... → §8 in order. Considered and rejected for two reasons: (a) the largest section first (§2's ~580 lines via 6 sub-sections) means the rewrite pattern itself gets debated under maximum content surface; (b) §2 trace-tail extraction depends on Appendix C existing, and Appendix C shape benefits from pattern-discovery on smaller appendix candidates (Appendix B routing-flag consolidation, which depends on having seen routing flags in §6/§7/§8 first).

**Alternative — risk-priority-first (§6 + §7 + §8 + §4 posture first):** considered. Overlaps largely with smallest-first proposal above; the only meaningful change would be inserting §4 posture sub-sections (§4.1 / §4.2 / §4.3 / §4.6) into the sequence early. Rejected because §4 carries the most cross-references in/out of every other section — touching it before §6/§7/§8 are settled means re-touching it after.

---

## 6. Per-section PR cadence

Recommendation: **one PR per rewritten top-level section**, matching the Phase 1 Step 3 lock-PR cadence (PRs #20 / #21 / #22 / #23 / #24 / #25 each landed exactly one top-level section). Estimated PR count: 8 section PRs + 1 overview/appendix-A/B/C/D PR + 1 archive-source PR = ~10 PRs total.

**Why the per-section cadence holds:**

- Each PR is reviewable in one sitting. The smallest source-section is ~40 lines + rewrite delta; the largest is ~580 lines + rewrite delta with Appendix C extraction = comparable to PR #24 (§4 + ADR-008 = largest Step 3 PR per WORKFLOW.md v1.17). PRs of that size were reviewed successfully in Step 3.
- F/CTO ratify cadence stays compatible with the existing pattern. Each section-PR can have its own structure ratify gate (Q1) + body ratify gate (Q2) before merging, mirroring §3 → §5 → §6 → §7 → §8.
- Rollback granularity matches scope-of-change. If any one section's rewrite re-litigates substance accidentally, that PR reverts cleanly without disturbing others.

**Two PRs deserve special handling:**

- **PR 1 (kickoff): archive source.** Before any rewrite PR opens, ship `docs/archive/PRD-v1.18-source.md` as a frozen copy of current PRD.md. Per the task's kickoff constraint. This PR is mechanical, zero-substance.
- **PR N (final): overview + appendices + reading guide + section index.** The document head and appendices land after body sections are all rewritten — they reference content that needs to exist first. Splitting overview from appendices possible; recommended to bundle since none can ratify until the body is settled.

**Alternative — single mega-PR:** rejected. Would be ~1000-line diff with structure decisions, body rewrites, appendix extractions, and forward-reference updates all tangled. Un-reviewable.

**Alternative — two-PR (structure-only PR + content-rewrite PR):** considered. Means a first PR that lands the new skeleton with all bodies as `TBD` placeholders + a second PR that fills the bodies. Rejected because the body-rewrite PR carries the load — splitting structure-vs-body doesn't shrink the riskiest review surface, it just adds a no-op PR.

---

## 7. Cross-reference handling

The PRD body, WORKFLOW.md changelog, and DECISIONS.md ADR-002 / ADR-004 / ADR-008 currently carry **line-anchored references** like `PRD.md:47`, `PRD.md:689`, `PRD.md:269`, `PRD.md:808`, `PRD.md:805`, `PRD.md:820`. Rough count from grep: 12+ such references across the three documents pointing at PRD.md line numbers that will shift in the rewrite.

**Three options:**

- **(a) Retarget to section refs at rewrite time.** Each rewrite PR scans WORKFLOW.md + DECISIONS.md for `PRD.md:NNN` references where NNN sits inside the section being rewritten, and replaces them with `PRD.md §N.M.K` section-anchor references. Tradeoff: more work per PR; result is stable across future PRD edits (section-anchor doesn't shift on line-number drift).
- **(b) Update line refs at end of rewrite.** Each rewrite PR leaves cross-references stale; final PR (or a housekeeping pass after the last body PR) sweeps the line numbers to point at the new content's actual lines. Tradeoff: less work per PR but creates a transient broken-pointer state across the rewrite; one bulk-sweep PR that's high-risk for off-by-one errors.
- **(c) Accept as historical pointing at v1.18-era line numbers.** WORKFLOW.md / DECISIONS.md entries are immutable operating history; the line refs were correct when written. Combine with `docs/archive/PRD-v1.18-source.md` to make the refs resolvable. New cross-references created during or after the rewrite use section-anchor form. Tradeoff: zero rewrite-time work; future readers must know that `PRD.md:47` refers to the v1.18 source, not current.

**Recommendation: (c) with a clarification.** Three reasons.

- The line refs sit inside `DECISIONS.md` and WORKFLOW.md entries that are documenting historical lock state at specific dates. Editing those entries to retarget references would mean editing immutable operating record. ADR-002 + ADR-004 + ADR-008 all carry the immutability convention explicitly (DECISIONS.md head: "Entries are immutable once accepted — supersede via a new entry rather than rewriting an old one").
- The archived source (`docs/archive/PRD-v1.18-source.md`) lands as the kickoff PR. Once it exists, `PRD.md:47` is unambiguously a reference to v1.18-source-line-47, not current. The archive serves the resolution function.
- New cross-references created during or after the rewrite *should* use section-anchor form, not line-anchor. This is a forward convention worth establishing; the rewrite is the natural moment to land it.

**Clarification step in rewrite kickoff PR (the archive PR):** add a short note to `docs/archive/README.md` (or a comment block in the archived file head): "WORKFLOW.md / DECISIONS.md entries dated on or before 2026-05-18 use `PRD.md:NNN` line references. Resolve those references against this archived file. PRD.md was structurally rewritten in Phase 1 Step 3.5; new references use section-anchor form (`§N.M.K`)."

**Carve-out:** if a specific line reference in WORKFLOW.md / DECISIONS.md becomes load-bearing in a future ADR amendment (i.e., a new ADR cites it as part of its own reasoning), that ADR can choose to retarget at amendment time. Not a rewrite-time concern.

---

## 8. Pattern divergences from Step 3 patterns

Step 3 quintuple-confirmed the **bulk-closeout-from-structure-proposal** pattern (§3 → §5 → §6 → §7 → §8: structure proposal ratified at one gate, full body landed as a single bundle at section-level acceptance, zero per-bullet ratify gates). WORKFLOW.md v1.18 explicitly names this pattern as the surface that drove F/CTO rubber-stamping. The rewrite must not use it.

**The shape that broke down:** at body-bundle acceptance time, F/CTO is reading ~50–200 lines of new content in one ratify gate. Per the user's framing, "44-for-44 teammate-lean track" = "F/CTO accepted every bundle as-drafted" but does *not* = "F/CTO considered every clause as-drafted." Bulk-closeout incentivizes pattern-matching and structure-trust over clause-by-clause read.

**Replacement pattern for the rewrite: sub-section gates at finer granularity.** Three variants live in Q3 with tradeoffs.

**Option α — sub-section gate per sub-section.** Each rewrite PR has N ratify gates where N = sub-sections in that top-level section. §6 rewrite gets 5 gates (one per axis). §4 rewrite gets 6 gates (4.1 through 4.6 — tables included). §2 rewrite gets 6 gates (2.1 through 2.6). PR-internal pacing: structure proposal → sub-section 1 body → ratify → sub-section 2 body → ratify → ... → integration. Estimated F/CTO ratify gates per PR: 1 structure + N body = 4–7 depending on section.

**Option β — sub-section gate per bullet cluster.** Even finer. Each sub-section's body is itself rewritten as a sequence of bullet-cluster ratify gates (e.g., §4.6 retention bullet is one gate, availability bullet is another, incident bullet is another, parity-fixture bullet another, etc.). Estimated F/CTO gates per §4 PR: 1 structure + ~20–25 body. Per §2.5 PR: ~15. Per §2.6 PR: ~20. Total ratify gates across the rewrite: 100+.

**Option γ — sub-section gates only for high-risk sections; bulk-closeout for low-risk sections.** §8 / §7 / §6 / §1 / §3 / §5 use bulk-closeout (smallest-and-not-rubber-stamp-flagged or already-scannable surfaces); §4 + §2 use Option α sub-section gates. Hybrid; matches risk profile.

**Recommendation: γ (hybrid).** The rubber-stamp risk concentrates at §4 + §2 by content density and lock-pattern history (§4 had the §4.6 retention/availability/incident bulk-closeout; §2.5 + §2.6 were the largest §2 sub-sections drafted under per-decision-point ratify gates that aren't applied at presentation rewrite time). The low-risk surfaces (§6, §7, §8, §1, §3, §5) can survive bulk-closeout because (a) their content is already settled and the rewrite is mechanical compression, and (b) they're small enough that one ratify gate per section is itself a tractable read.

**Why not β (every bullet):** the rewrite is presentation-only by constraint. β re-opens substance by forcing F/CTO to ratify every bullet's compressed form. If a compressed bullet is structurally faithful to its source, the ratify is overhead; if it isn't structurally faithful, the bullet has crossed into substance and the structure gate should catch it.

---

## 9. Rubber-stamp re-review candidates

Reading §6 / §7 / §8 + §4 posture closely, **the following specific paragraphs look like verify-rather-than-trust surfaces** — content that landed under bulk-closeout and that warrants a clause-by-clause F/CTO read during the rewrite, separate from the presentation rewrite itself. I am **flagging only**, not proposing substance changes. Each item below is presented with the source location and the specific reason for the flag.

**§4.2 — credential-error state #4 wording (PRD.md line 741).** The bullet reads "(d) user-side grant revoked at the institution (user revoked Plaid on the institution's portal; user re-authorizes there before re-auth here can complete)." The substance distinction between (c) "institution-side grant revoked" and (d) "user-side grant revoked at the institution" was elevated to a four-state model at §2.4.4 lock; whether (c) vs. (d) is observationally distinguishable in the V1 user-facing surface (separate from being technically distinguishable in Plaid's API responses) is a flag worth verifying — bulk-closeout absorbed the four-state model verbatim from §2.4.4 without re-checking whether the (c)/(d) split shipped a useful distinction at V1.

**§4.3 — staleness-live-read race classification severity (PRD.md line 750).** RT-13 is classified `race-condition` test category, **high-severity** not critical. The §4.3 narrative justifies non-critical because "failure-mode is cross-tenant signal correlation (which accounts at tenant A are stale leaks behavior to tenant B), not cross-tenant credential or financial-data exposure." Reasonable reasoning, but worth a clause-level verify against the §2.6.5 staleness-marker semantics: at §2.6.5 the staleness markers expose *account names* (per-section + report-banner naming stale accounts at render time per §2.6.5 lock). Account-name exposure across tenants is a credential-adjacent surface in the way SD-01 Plaid account-share-decision data is. The severity decision plausibly holds; whether F/CTO considered the account-name dimension at the severity classification is worth re-confirming.

**§4.6 — incident-handling V2-trajectory ramp (PRD.md line 806).** The "V2-trajectory ramp to formal incident-response shape if/when the second user lands per §7.3 invite-only forward-compat" commits V1 to no on-call rotation / no severity rubric beyond §4.5 Sev-α / no postmortem template. The reasoning ("single-user-F/CTO incident response is what V1 ships; the conventional incident-response shape would be ceremony without value at this scale") landed as part of Q3c Option α at gate 1. Worth verifying: does the V2-trajectory ramp commitment also commit to V1 *not* shipping any audit-log surface that future incident response would consume — or is the audit-log architecture (routing flag (f) at §4.6 + ADR-008 Decision 4 "audit logs … indefinite at-V1 with V2 cold-storage rollover forward-compat") an upstream commitment to *do* ship audit logs at V1? Two clauses are arguably in tension; the rewrite is a natural moment to re-read whether the tension is real or only apparent.

**§6.3 — TLH information-vs-prescription axis carve-out (PRD.md line 974).** Per ADR-007 future-housekeeping clause, "If a V2-scoping review wants to consider a TLH-shaped *information* surface ... that surface would be a new ADR — the information-vs-prescription axis is the boundary, not the tax-domain content." This is correct per ADR-007 but the §6.3 bullet ships it as a clause buried inside the TLH treatment, not as an axis-level explicit commitment. If F/CTO intends "the test is information-vs-prescription, not the tax-domain content" as an axis-level test that applies to other §6.3 sub-questions (e.g., observational annotation of wash-sale-eligible unrealized losses; observational annotation of asset-location-suboptimal holdings; observational annotation of bracket-edge income realization opportunities), that axis-level commitment plausibly deserves its own bullet rather than being a TLH-clause-tail. Editorial elevation candidate.

**§7.2 — single-tenant scale dimensions framing (PRD.md line 1008).** The framing "the scale dimensions inherent to a single-tenant, daily-snapshot, multi-product-Plaid data product with ten years of historical NAV depth on import" enumerates **single-tenant** scale as the V1 scope but commits to "the multi-tenant infrastructure exercises (not bypasses) RLS enforcement at single-user-V1 test paths." The clause-level question: does V1 commit to V2-scale RLS performance verification at V1 ship (test the RLS posture *holds* at V2 user-count assumptions) or only to V1-single-user RLS exercise? The §4.1 axis-i commitment is "multi-tenant infrastructure exercised on the single-user-V1 test path"; the §4.5 RT-NN tests verify under "two-tenant SQL fixture." §7.2 reads as a forward-pointer to Architect Phase 3 for scale verification, which is consistent — but the two-tenant fixture vs. V2-target-cohort scale is itself a tier of ambiguity worth surfacing.

**§8.1 — V1.0 illustrative-not-normative scoping (PRD.md line 1047).** The bullet preserves ADR-004's example "V1.0 = Plaid-sourced data + manual *balances* (manual accounts with current-balance entry but without full transaction-level entry)" as "illustrative example per ADR-004 / ADR-002 Consequences ... The specific V1.0 capability scope is Phase 4 territory." The illustrative-vs-normative distinction at §8.1 is structurally correct (Phase 4 owns sequencing per the §8 → Phase 4 handoff at routing flag (d)). The flag: ADR-004 Consequences (`DECISIONS.md:484`) reads as a more committed example than "illustrative" (the original ADR-004 entry says "natural split is V1.0 ships with manual *balances* + Plaid-sourced data, V1.1 adds full manual transaction-level entry"). Whether §8.1's "illustrative-not-normative" framing accurately captures ADR-004's actual commitment level, or whether ADR-004 *did* lock the V1.0 / V1.1 split and §8.1 is implicitly relaxing it, is a clause-level verify worth doing.

**§8.2 — drop-replace transition mechanic at routing flag (e) (PRD.md line 1074).** The boundary note "§8 ↔ §4.6 cross-reference shape" commits to "Reciprocation is one-way at §8 lock (§8 → §4.6); no §4.6 body revision required because §4.6 already commits to the posture, §8.2 just names the transition mechanic that consumes it." Worth a re-read against §4.6's actual posture text at PRD.md:808 — does §4.6 commit to "the historical NAV import from the existing system per §2.1 Architect routing flag terminates at V1 schema population — the import is a one-time event, not an ongoing sync" *during* the drop-replace transition or *at V1.final cutover*? The §8.2 commitment to "V1.x backend as data source for residual Google Sheets views during transition" plausibly creates a window where the existing-system data is *being* migrated, not yet *terminated*; the §4.6 commitment is to terminal cutover. The two are reconcilable but worth a clause-level verify that §4.6 + §8.2 don't accidentally commit to incompatible mechanics.

I have surfaced 7 specific clause-level flags above. **None of these proposes a substance change.** Each is a re-read candidate that the rewrite is the natural moment to surface. F/CTO's call on whether to engage with any of them — including the choice to defer all 7 to a future verify-not-trust pass after the rewrite ships, treating the rewrite itself as strictly presentation-only.

---

## 10. Risks and open questions

**R1 — Presentation vs. substance brushing.** Compressing a paragraph-bullet to a lead sentence + nested bullets is a presentation operation in principle. In practice, choosing *which* sentence is the lead and *which* clauses become nested is an editorial judgment that can subtly change emphasis. The clause-level rubber-stamp candidates in §9 above demonstrate that the locked content already carries embedded editorial choices (illustrative-vs-normative, severity classification, axis-level vs. clause-level commitments) that the rewrite would have to preserve faithfully. **Mitigation:** every rewrite PR diff includes a "structural-fidelity check" — a one-paragraph attestation that the rewritten section's lead clauses and nested clauses are the same commitments as the source, with explicit callouts of any editorial-choice surfaces (e.g., "in §4.6 retention bullet, the lead is the class-by-class commitment, nesting carries the per-class enum values"). F/CTO ratifies the attestation alongside the body.

**R2 — Story Trace Index extraction completeness.** Appendix C is the largest single editorial move. If a story's trace tail contains a load-bearing clause that *isn't* pure trace (e.g., a clause that's actually a V1 commitment dressed as a trace — see §2.1.7's "Flagged for Security Reviewer per §8.0" inline clause, which is half-trace half-commitment), the extraction has to leave that clause in-body, not in Appendix C. **Mitigation:** the §2 rewrite PRs (slot 8 in the sequence) each include a per-sub-section clause classification pass — every trace-tail clause classified as (a) pure trace → moves to App C, (b) embedded commitment → stays in body as a bullet, (c) routing-flag origin → moves to App B. Classification is itself a ratify-able surface.

**R3 — Architect engagement at Step 4 timing.** F/CTO target-shape constraint says "Architect must read the polished version." If the rewrite stretches across many session PRs, there's an ambiguous window where Step 4 opens but the rewrite isn't done. **Mitigation:** Step 4 entry waits until the rewrite is fully landed. Phase 1 Step 3.5 closes (rewrite shipped) → Phase 1 Step 4 opens (Architect engagement). WORKFLOW.md header reflects Step 3.5 as an explicit intermediate step between §8 lock and Step 4 entry, mirroring Step 2 / Step 3 / Step 4 phrasing.

**R4 — Process-record content relocation (Q5).** Appendix D vs. WORKFLOW.md as the home for per-section `Acceptance flags` content is a non-obvious decision (see Q5). Whichever home wins, the rewrite has to commit to one. If both keep it, content duplicates; if neither, content vanishes.

**R5 — Routing-flag consolidation in Appendix B.** Per-section routing flags use varying alphabet conventions ((a), (b), ... per section, sometimes (i), (ii), (iii) nested, sometimes Greek for sub-decision IDs). Consolidating into Appendix B means inventing a global flag ID scheme (e.g., `§4.6-(k)(iii)` for the V2-ship-gate inventory item iii) and updating in-body markers. Mechanical but tedious; one rewrite PR's worth of work concentrated in the appendix-construction PR (slot 9). **Mitigation:** Appendix B uses `§N.M-(letter)` as the global ID scheme; in-body markers reference by global ID; the Appendix B index sorts by source-section.

**R6 — Locked-vs-not-locked ambiguity in non-§4 sections.** §4 has the `#### Acceptance flags` block convention ("locked as of 2026-05-18"); §1, §3, §5, §6, §7, §8 also have it; §2.1–§2.6 each have it. But §1 specifically has no formal lock date in its acceptance-flags surface (§1 is "substantively drafted, §1.2 attribute #5 strengthened at v1.6, §1.4 line-58 surgical edit at §6 lock"). The rewrite has to commit to either treating §1 as "locked as of v1.18 by accumulation" or carving it out as still-mutable. **Mitigation:** F/CTO ratify question at Step 3.5 kickoff — does §1 count as locked or as substantively-drafted-pending-final-lock? (Not a Q in this proposal; surfaces at PR-1 kickoff.)

**R7 — Source archive cross-references.** The kickoff archive PR drops `docs/archive/PRD-v1.18-source.md` and (per Q7 recommendation) adds a `docs/archive/README.md` clarification. Risk: future readers of `docs/archive/PRD-v1.18-source.md` may try to edit it as if it were live (it isn't — it's the frozen source-of-truth for historical line-anchored references). **Mitigation:** archived file head carries an explicit "Frozen 2026-MM-DD; do not edit — line-anchored references in WORKFLOW.md / DECISIONS.md resolve against this file" comment block.

**R8 — Bulk-closeout pattern relapse.** The pattern that drove rubber-stamping is the project's default by deep grooves at this point. The rewrite has to consistently use Option γ hybrid gates (per Q3) and not slide back into single-gate body bundles. **Mitigation:** each rewrite-PR has a pattern-divergence-check checkbox in the PR body — "this PR uses [bulk-closeout | sub-section gates | per-bullet gates]; rationale: [...]". The check forces explicit pattern declaration at every PR.

---

## Ratify questions for F/CTO

The following questions are sequenced one-at-a-time per project pacing memory. Each presents 2–3 specific options with tradeoffs.

---

**Q1 — New top-level structure: appendix scope.**

Three named appendices proposed (B, C, D) plus the existing-stub Appendix A. Which appendix set should ship in the rewrite?

- **Option α — All three new appendices (B, C, D).** Appendix B (routing flags consolidated index), Appendix C (Story Trace Index for §2.x), Appendix D (Process and lock record consolidated from per-section Acceptance flags). Most aggressive presentation cleanup; largest mechanical effort; cleanest scannable PRD body.
- **Option β — B + C only; relocate D content to WORKFLOW.md.** Appendix B and C as above; per-section Acceptance flags content (process-narrative, ratify counts, PR shipping plans) moves entirely to WORKFLOW.md changelog where most of it is already duplicated. PRD has no process-record content. Cleanest separation of artifact responsibilities (PRD = product scope; WORKFLOW.md = execution record).
- **Option γ — B + C only; preserve Acceptance flags in-body as compact lock-status block.** Acceptance flags content stays under each section but compresses to a 2–3 line lock-status block (lock date + ratify-track + ADR/PR-pointer) without the pattern-divergence-narrative tail. Less aggressive cleanup; preserves at-a-glance lock-state visibility per section.

PM recommendation: **β.** Per CLAUDE.md "Documents are the memory" and the operating distinction that WORKFLOW.md is the execution log while PRD.md is the source-of-truth for product scope. Acceptance-flag process content belongs to the execution log; it has already been written there. γ is a viable middle ground if F/CTO wants per-section lock-state visibility in the PRD itself.

---

**Q2 — Rewrite-section ordering.**

- **Option α — Smallest-first with §1-after-§5/§6/§7/§8 promotion.** Sequence: §8 → §7 → §6 → §1 → §3 → §5 → §4 → §2 → overview/appendices. Per §5 recommendation in the body.
- **Option β — Match source order (§1 → §2 → ... → §8).** Standard top-to-bottom rewrite. Predictable; sequential matches reader-eye order; means rewriting the largest section (§2 ~580 lines + Story Trace Index extraction) early, before rewrite patterns are settled.
- **Option γ — Risk-priority-first.** Sequence: §4 posture → §6 → §7 → §8 → §1 → §3 → §5 → §2 → overview/appendices. Tackles rubber-stamp-flagged surfaces first; means §4 posture is rewritten before §4 tables; means §4 is touched twice (once for posture sub-sections, once for table-context-cross-references when §4.4 / §4.5 settle in their own PR).

PM recommendation: **α.** Smallest-first with the §1 promotion lets the rewrite pattern settle on low-risk surfaces (§8, §7, §6, §1) before the high-risk surfaces (§4, §2) inherit them. Source-order rewrite (β) opens the largest section first under un-settled patterns. Risk-priority-first (γ) is plausible but means §4 gets touched in two passes.

---

**Q3 — Ratify gate pattern.**

The rewrite must not use the bulk-closeout pattern that drove rubber-stamping (per WORKFLOW.md v1.18). Three sub-section-gate options:

- **Option α — Sub-section gate per sub-section (uniform).** Each rewrite PR has structure proposal + N body gates where N = sub-sections in the section. Estimated ratify gates per PR: 4–7. Estimated total gates across rewrite: ~35.
- **Option β — Sub-section gate per bullet cluster (finer).** Each sub-section's body is itself rewritten as bullet-cluster ratify gates. Estimated ratify gates per PR: 10–25. Estimated total gates across rewrite: ~100+. Strongest scope discipline; highest ratify-fatigue risk; risk that ratify-fatigue itself drives a second-order rubber-stamping cycle.
- **Option γ — Hybrid: bulk-closeout for low-risk sections (§8 / §7 / §6 / §1 / §3 / §5); sub-section gates for high-risk sections (§4 / §2).** Estimated total gates across rewrite: ~25.

PM recommendation: **γ.** Matches gate density to substance-risk concentration. β is over-corrected against the bulk-closeout pattern and likely produces ratify-fatigue at scale.

---

**Q4 — Cross-reference handling (line-anchored → section-anchored).**

WORKFLOW.md / DECISIONS.md carry ~12+ `PRD.md:NNN` line references that will shift in the rewrite.

- **Option α — Retarget to section-anchor at rewrite time.** Each rewrite PR sweeps WORKFLOW.md / DECISIONS.md for line references inside its section and updates them to `PRD.md §N.M.K` form. Means editing immutable operating-history entries (ADR-002, ADR-004, ADR-008 bodies + WORKFLOW.md v1.x changelog entries).
- **Option β — Accept as historical, archive resolves.** New convention from rewrite forward: section-anchor only. Existing line refs resolve against `docs/archive/PRD-v1.18-source.md` per kickoff PR. Clarification note in `docs/archive/README.md` or the archived file head.
- **Option γ — End-of-rewrite bulk-update PR.** All retargeting happens in one PR after every body section is rewritten. Means transient broken-pointer state across the rewrite + high-risk single-PR off-by-one errors.

PM recommendation: **β.** Honors the DECISIONS.md / WORKFLOW.md immutability convention. Archive serves the historical-resolution function. Forward references use section-anchors as new convention.

---

**Q5 — Process-record relocation (only fires if Q1 = α or γ).**

If Acceptance flags content stays in-PRD (Q1 α or γ), what shape does it take?

- **Option α — Full Acceptance-flags content preserved in Appendix D.** Per-section ratify-track records, pattern-divergence notes, PR pointers, Sec/Architect at-lock-pass status — all migrate to Appendix D, indexed by section. PRD body has no process content.
- **Option γ — Compressed lock-status block in body (matches Q1 γ).** Each section's body ends with a 2–3 line lock-status block: lock date, ratify-track summary (e.g., "PM-led, 2-for-2 PM-lean"), ADR reference if any, PR number. No pattern-divergence narrative.

Skip this question if Q1 = β.

PM recommendation: **γ if Q1 = γ; α if Q1 = α.** Match Q1's appendix scope.

---

**Q6 — Source archive kickoff PR.**

Per task constraints, `docs/archive/PRD-v1.18-source.md` ships in the first rewrite PR before any rewrite content touches main.

- **Option α — Standalone kickoff PR (just the archive + a `docs/archive/README.md`).** Single-purpose, zero-substance, fast review. First PR of the rewrite, lands before any body-rewrite PR opens.
- **Option β — Bundle archive into first body-rewrite PR (§8 per Q2 α).** Archive + §8 rewrite ship together. One fewer PR; archive is colocated with first rewrite content. Smaller process overhead.

PM recommendation: **α.** Single-purpose PRs are easier to review and easier to revert. The archive is mechanically a different operation from a rewrite; bundling them creates a no-substance-but-large-line-count diff. Standalone kickoff PR also lets the `docs/archive/README.md` clarification note be reviewed on its own merits.

---

**Q7 — Rubber-stamp re-review candidates (§9 above).**

Seven specific clause-level surfaces are flagged in §9 as verify-rather-than-trust candidates. What's the engagement model with them?

- **Option α — Engage with all 7 during the rewrite.** Each flag becomes a dedicated F/CTO ratify gate in the relevant section's rewrite PR. Substance-mutation possible (and explicit) if any clause turns out to be wrong.
- **Option β — Engage only with the highest-risk subset (PM identifies 2 of 7).** PM-recommended high-risk subset: §4.6 incident-handling V2-trajectory ramp vs. audit-log V1 commitment (potential clause-level tension) + §8.1 illustrative-vs-normative V1.0/V1.1 framing (potential implicit ADR-004 relaxation). Other 5 flags defer to post-rewrite verify pass.
- **Option γ — Defer all 7 to post-rewrite verify pass.** The rewrite is strictly presentation-only by constraint; substance verify happens in a separate dedicated pass after the rewrite ships, before Phase 1 Step 4 opens.

PM recommendation: **γ.** The task constraint is presentation-only; engaging with substance flags during a presentation rewrite mixes scopes. A dedicated verify pass after the rewrite has the right shape — strict substance focus, no presentation noise, can use proper sub-section-by-sub-section pacing. Architect engagement at Step 4 still proceeds against polished + verified content. Worst case if γ is wrong: rewrite ships, verify pass surfaces a real clause-level issue, ADR amendment lands as part of the verify pass.
