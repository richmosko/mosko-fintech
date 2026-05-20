# WORKFLOW.md

**Project:** mosko-fintech
**Current version:** v1.29
**Last updated:** 2026-05-19
**Current phase:** Phase 1 — Product Definition (PRD), in progress. Step 3 (PRD section drafting) **substantively complete** (all 12 PRD sections LOCKED across §2 series + §3/§4/§5/§6/§7/§8); **Step 3.5 (PRD editorial rewrite) substantively complete** — PR 1 kickoff (archive + README + Step 3.5 declaration) landed at v1.19; **PR 2 / §1 rewrite landed at v1.20 with §1 β override EXERCISED**; **PR 3 / §2 rewrite landed at v1.21 (first sub-section-gates PR; Appendix C extracted with 32 story traces)**; **PR 4 / §3 rewrite landed at v1.22 (second bulk-closeout PR; default-to-source-shape correction landed mid-PR — see `memory/feedback_rewrite_convention_drops_blockquotes.md`)**; **PR 5 / §4 rewrite landed at v1.23 (second sub-section-gates PR; first Sec-as-primary-author PR since PR 1 kickoff; Q-S5=γ F/CTO override on §4.2 voice conversion)**; **PR 6 / §5 rewrite landed at v1.24 (third bulk-closeout PR; first PR to exercise β shape-discipline aggressively under Q-S2=β F/CTO override; +57% line-count expansion vs source; 20 lead bullets extracted into 77 new sub-bullets)**; **PR 7 / §6 rewrite landed at v1.26 (fourth bulk-closeout PR; smallest section under rewrite at 39 source body lines; 4-for-4 PM α structure-gate acceptance; -10.3% line-count compression; first team-mode dispatch under v1.25 operating-model convention)**; **PR 8 / §7 rewrite landed at v1.27 (fifth bulk-closeout PR; 5-for-6 PM acceptance with 1 F/CTO override at Q-S6 = β narrowly scoped to §7.3 b2; -19% line-count compression; first PR to exercise Acceptance-flag recap block convention at WORKFLOW.md per PR 4 / v1.22 precedent)**; **PR 9 / §8 rewrite landed at v1.28 (sixth bulk-closeout PR; LAST PM-led drafting task in Phase 1 Step 3; 5-for-7 PM acceptance with 2 F/CTO overrides — Q-S6 = β on §8.3 b3 single-bullet-narrow + Q-S7 = α-extended symbolic conversion of all 10 PRD.md:NNN refs in §8 body; first PR to surface a section-drift cross-ref correction (§1.3 → §1.4 V1-correctness content relocation from PR 2 / §1 rewrite, caught + fixed at Q-S7 audit); -39% body-line compression)**; **PR 10 / Step 3.5 closure landed at v1.29 (closure PR; structurally distinct from PR 2–9 §-rewrites; 7-for-8 PM acceptance with 1 F/CTO override at Q-S3 = β to include PRD overview/preamble; critical audit finding — full Appendix B consolidation surface = 114 entries, NOT the 19-entry post-PR-6 running total the brief framed; 114-entry App B body lifted + classified with 5-tag convention [Architect Phase 3 / Sec V2-implementation / Architect-Sec joint / Boundary note / Closure-trace process-record]; 87 active forward-pointers + 27 resolved process-records; Appendix A defer-note added; 12 in-body italic markers updated)**. Original Step 3.5 framing — F/CTO surfaced late-phase rubber-stamp risk under cumulative PRD density (see `memory/feedback_late_phase_density_overload.md`); rewrite plan locked at 7-Q ratify pass (see v1.19 changelog) — presentation-only restructure preserving all locks, source archived at `docs/archive/PRD-v1.18-source.md`, ~10 PR sequence (PR 1 kickoff + PR 2–9 sections §1 → §8 in source order + PR 10 overview/appendices); 7 PM-flagged rubber-stamp candidates deferred to dedicated post-rewrite verify pass before Step 4 entry. Step 4 (Architectural overview consult; Architect lead; Phase 3 entry gate) gated by Step 3.5 closure + post-rewrite verify pass. After Step 4 ratifies, Phase 2 (UX/Visual) becomes available; Phase 1 closes. Team-mode (`phase-1` team) per ADR-003 active. (Step 2 ratification complete at ADR-002; Step 3 prior state preserved in v1.18 changelog.)

---

## Changelog

### v1.29 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 10 / Step 3.5 closure (overview refresh + Appendix B consolidation + housekeeping).** Closure PR for Step 3.5 editorial rewrite sequence. **Structurally distinct from PR 2–9 §-rewrite PRs**: PR 10 adds new top-level content (overview/preamble, Appendix B body, Appendix A defer-note) and applies 12 in-body italic-marker surgical edits across §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6 / §3 / §4 / §5 / §6 / §7 / §8. After PR 10 lands, **post-rewrite verify pass** (Q7 = γ queue 17 entries) gates **Step 4 entry** (Architectural overview consult; Architect lead). Phase 1 starts closing after Step 4 ratifies.

**Critical audit finding (PR 10 structure proposal).** Appendix B consolidation surface was **~114 entries, NOT the 19-entry post-PR-9 running total** the PR 10 brief initially framed. The "19 entries" framing was a counter convention the changelog established at PR 7 / v1.26, anchored on "6 entries post-PR-6" without back-summing PR 3 (73 entries from §2.1–§2.6 routing-flag blocks) / PR 4 (6 entries) / PR 5 (16 entries). All 12 in-body italic markers across §2.1–§8 explicitly stated "see Appendix B (created in PR 10; pending consolidation)"; consolidating only 19 entries would have left 95 markers dangling against a partial App B body — re-creating the forward-pointer-without-closure problem Step 3.5 closed. **F/CTO Q-S1 = α (full consolidation)** addressed the audit finding directly.

**Structure-gate decisions (Q-S1 through Q-S8)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — full ~114-entry consolidation | α |
| Q-S2 | **α** — by source-§ shape | α |
| Q-S3 | **β** (F/CTO override) — include tight PRD overview/preamble (~12 lines) before §1 | α (out of scope) |
| Q-S4 | **α** — symbolic-ref convention extended to App B entries per PR 9 Q-S7 precedent | α |
| Q-S5 | **β** — defer Appendix A consolidation with explicit italic note under heading | β |
| Q-S6 | **α** — consistent type-tag prefix (`[Architect Phase 3]` / `[Sec V2-implementation]` / `[Architect / Sec joint]` / `[Boundary note]` / `[Closure-trace process-record]`) | α |
| Q-S7 | **α** — inline `[RESOLVED-AT-§X]` tag on closure-trace entries alongside type-tag | α |
| Q-S8 | **α** — update 12 in-body italic markers to drop "(created in PR 10; pending consolidation)" qualifier | α |

**7-for-8 PM acceptance; 1 F/CTO override at Q-S3 = β.**

**5-tag classification convention.** PM introduced a fifth tag value `[Architect / Sec joint]` during body draft (12 entries: §2.3 (d)(f), §2.4 (b)(g)(h)(j)(k), §2.6 (m)(n)(p)(q)(r), §4 (a)(b)(c)(i)(j)) on top of the four enumerated in Q-S6 = α. F/CTO ratified the 5-tag scheme at Q-B1 = α; without it, joint flags would collapse to either Architect-only (losing Sec dimension) or Sec-only (mis-classifying as V2-gate).

**App B consolidation totals (114 entries)**

| Source-§ | Entries | Source PR |
|---|---|---|
| §2.1 | 5 | PR 3 / v1.21 |
| §2.2 | 7 | PR 3 / v1.21 |
| §2.3 | 11 | PR 3 / v1.21 |
| §2.4 | 12 | PR 3 / v1.21 |
| §2.5 | 17 | PR 3 / v1.21 |
| §2.6 | 21 | PR 3 / v1.21 |
| §3 | 6 | PR 4 / v1.22 |
| §4 | 16 | PR 5 / v1.23 |
| §5 | 6 | PR 6 / v1.24 |
| §6 | 3 | PR 7 / v1.26 |
| §7 | 5 | PR 8 / v1.27 |
| §8 | 5 | PR 9 / v1.28 |
| **Total** | **114** | — |

**Classification breakdown (114 entries)**

- **`[Architect Phase 3]`** — 65 entries. Largest category; dominates §2.x + §4.
- **`[Architect / Sec joint]`** — 12 entries. Joint Phase 3 + mandatory Sec PR-time review.
- **`[Sec V2-implementation]`** — 4 entries. Consolidated V2-ship-gate inventory.
- **`[Boundary note]`** — 6 entries. Forward-operative cross-§ documentation markers.
- **`[Closure-trace process-record]`** — 27 entries. Resolved at downstream §-locks; preserved for traceability.

**Resolved-vs-active counts**

- **Active forward-pointers:** 87 (65 + 12 + 4 + 6) — primary payload for Architect Step 4 + Phase 3 consumption.
- **Resolved process-records:** 27 — historical record; filterable via `[RESOLVED-AT-§X]` tag.

**Symbolic-ref conversion sweep (Q-S4 = α)**

- Zero `PRD.md:NNN` numerics remain in Appendix B. ~14 in-body section refs converted to symbolic form during lift (primarily §2.2 / §2.3 line-NN refs to "§X routing flag (Y)" form).
- DECISIONS.md numerics preserved verbatim per PR 9 Q-S7 scope ruling.

**Line-count outcome**

- PM α projection: ~291–401 lines net PRD growth under Q-S1 = α + Q-S5 = β + Q-S8 = α.
- Q-S3 = β override added ~12 lines for overview.
- **Realized:** PRD.md grew from 1340 → 1610 lines (+270 lines / +20%). Within projected range.

**Pattern divergence — PR 10 is structurally distinct from PR 2–9.** PR 2–9 were §-rewrite PRs (replace §N body, preserve substance). PR 10 is a closure / consolidation PR (add new top-level content, lift entries verbatim, apply housekeeping surgical edits). **Verbatim-lift attestation surface** replaces the §-body-rewrite attestation: every App B entry's substance is preserved from its source location with symbolic-ref conversion + classification-line addition.

**Acceptance-flag recap (PR 10 / Step 3.5 closure)**

- **Step 3.5 substantively complete as of 2026-05-19** (per PR 10 merge). Step 3.5 produced: archived PRD-v1.18 source; 8 §-rewrite PRs (§1 → §8); closure PR 10 with App B consolidation (114 entries), PRD overview/preamble (NEW per Q-S3 = β), Appendix A defer-note, and 12 in-body marker updates. **PM-lean track final: 30-for-38 across Step 3.5.** Eight F/CTO overrides — six β at structure gates (PR 3 Q-S4, PR 4 Q-S2, PR 5 Q-S5 γ, PR 6 Q-S2, PR 8 Q-S6, PR 9 Q-S6, PR 10 Q-S3) + two α-extended (PR 9 Q-S7) + one β at PR 10 Q-S3.
- **No new ADR for PR 10.** Verbatim consolidation only. **Step 3.5 produced zero new ADRs by construction** (presentation-only restructure); the only ADR-related event was the §1 substance amendments at PR 2 / v1.20 under §1's still-mutable carve-out (Amendment C was a PRD-internal rename with zero DECISIONS.md occurrences).
- **Substance verify-pass (Q7 = γ) queue total: 17 entries** carried forward. PR 10 surfaces zero new VP candidates (verbatim consolidation; no substance discrepancies during lift). **Verify-pass resolution is explicitly outside PR 10 scope.** Post-PR-10 sequence: (i) verify pass opens; (ii) each VP entry walked; (iii) any substance issue lands as ADR amendment; (iv) Step 4 (Architectural overview consult) opens after verify pass closes; (v) Phase 1 closes after Step 4 ratifies; Phase 2 (UX/Visual) becomes available.
- **Post-PR-10 in-body markers point exclusively to consolidated Appendix B.** 12 markers updated per Q-S8 = α; zero references to "pending consolidation" remain in PRD body. **The Step 3.5 forward-pointer-without-closure pattern closes at PR 10 merge.**
- **Step 4 entry payload:** 87 active forward-pointers (65 Architect + 12 Architect/Sec joint + 4 Sec V2-implementation + 6 boundary notes) + §4.4 14-class sensitive-data matrix + §4.5 15-row RLS test catalog + §8 → Phase 4 handoff anchor (Appendix B → §8 routing flag (d)). Step 4 produces ARCHITECTURE.md as Phase 3 entry payload.

**Team-mode operational note (fourth dispatch under v1.25 convention)**

- `pm-pr10-structure@phase-1` teammate handled both structure proposal and body draft turns. Third consecutive idle-before-deliverable timing event surfaced (idle notification arrived without sign-off; `ls` showed only structure proposal); resolved via diagnostic ping per `memory/feedback_team_mode_idle_before_deliverable.md`. **Memory pattern validated three times** across PR 8 / PR 9 / PR 10. The largest body draft of Step 3.5 (~280-line App B body + overview + recap + 12 marker triples + v1.29 changelog) completed cleanly with the diagnostic-ping resolution.

**Substance preservation**

- 0 substance amendments. Verbatim-lift consolidation only. Every App B entry byte-equivalent to its source after symbolic conversion + classification-line addition.
- ~14 symbolic-ref retargets applied across App B entries.
- 12 in-body italic-marker surgical edits applied; zero §-body content changed.

**No new ADR.** PR 10 is presentation/consolidation only; follows PR 2–9 precedent. **Step 3.5 closes with zero new ADRs across the entire 10-PR sequence.**

---

### v1.28 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 9 / §8 (V1 milestone framing) rewrite.** Sixth bulk-closeout PR under Step 3.5 cadence (continues PR 8 / §7 + PR 7 / §6 + PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6–8. **§8 is the last PM-led drafting task in Phase 1 Step 3** — post-§8 lock, only PR 10 (overview / appendices / Appendix B consolidation) remains for Step 3.5 closure, then post-rewrite verify pass gates Step 4 entry. **Third PR to invoke a F/CTO β override at structure gate** (parallel to PR 8 / §7 Q-S6 = β at §7.3 b2 + PR 6 / §5 Q-S2 = β broad shape-discipline sweep; PR 9's β scope is also single-bullet-narrow at §8.3 b3). **First PR to invoke a F/CTO α-extended override at cross-ref retarget gate (Q-S7)** — symbolic conversion of all `PRD.md:NNN` numeric refs in §8 body to future-proof against further line drift in PR 10. **First PR to surface a section-drift cross-ref correction** (§1.3 → §1.4 V1-correctness content relocation during PR 2 / §1 rewrite, surfaced and corrected at PR 9 / §8 Q-S7 audit — would have propagated into Step 4 Architect consult if missed).

**Section rewritten**

- **§8** (V1 milestone framing) — 3 sub-sections preserved (§8.1 V1 sub-version convention / §8.2 Drop-replace migration pattern / §8.3 V1-done cross-reference and Phase 4 handoff) per Q-S1 = α source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §8 (lines 1039–1084; 46 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §8 (L1145–1181, 37 lines including foot markers; ~28 visible body content lines excluding markers + blank padding; net body-line compression of **-39%** under α-for-α/N-A/α/α/α/β/α-extended structure-gate ratify with §8.3 b3 β extraction adding ~4 sub-bullet lines).

**Structure-gate decisions (Q-S1 through Q-S7)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §8 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §8 prelude tightened (process-record drop + ADR-rationale compress); §8.1 prelude tightened (ADR-004 rejected-alternatives compress); §8.2 + §8.3 sub-§ preludes verbatim | α |
| Q-S4 | **α** — 5 routing flags (a)–(e) → App B; all boundary-notes (4 resolved-closure-trace + 1 forward-operative handoff anchor) | α |
| Q-S5 | **α** — 6 process-record acceptance flags (b2–b7) → WORKFLOW.md `Acceptance-flag recap (PR 9 / §8)` block; b1 dropped as redundant with routing flag (d) | α |
| Q-S6 | **β** (F/CTO override) — extract §8.3 b3 (Phase 4 handoff) into 4 sub-bullets (i)–(iv); §8.1 b3 / §8.1 b4 / §8.2 b2 / §8.3 b1 surfaced as candidates but preserve verbatim per single-bullet-narrow scoping (mirrors PR 8 Q-S6 = β shape) | α |
| Q-S7 | **α-extended** (F/CTO override) — symbolic conversion of all `PRD.md:NNN` numeric refs in §8 body (4 distinct refs × 10 instances: `PRD.md:689` × 3 → "§3.4 closing line" / "§3.4 → §8 forward-pointer" / dropped where redundant; `PRD.md:47` × 3 → "§1.4 V1 existing-system-replacement test bullet" / "§1.4 → §8 forward-pointer" **with §1.3 → §1.4 section-drift correction**; `PRD.md:808` × 2 → dropped, "§4.6 shadow-workflow tear-down cross-reference" carries pointer; `PRD.md:805` × 2 → dropped, "§4.6 availability posture" carries pointer). DECISIONS.md numeric refs preserved verbatim per F/CTO scope ruling | α (numeric retargets only) |

**5-for-7 PM acceptance; 2 F/CTO overrides at Q-S6 + Q-S7.**

**Q-S7 convention divergence flag.** PR 9 is the first PR to convert PRD.md numeric refs to fully symbolic form within a §-body. Prior PRs (PR 4–8) kept PRD.md numerics verbatim and accepted post-rewrite drift as bookkeeping. F/CTO chose Q-S7 α-extended to future-proof against further line drift in PR 10 / overview consolidation; future PRs touching cross-ref-dense surfaces may continue this convention or revert to numeric form at F/CTO discretion. **DECISIONS.md numerics remain in body verbatim** — DECISIONS.md is a stable append-only ADR ledger; numeric drift is structurally constrained.

**β extraction sweep — 1 extraction (single-bullet scope)**

- Systematic sweep across 10 source body bullets. 4 strong candidates surfaced at structure proposal (§8.1 b3 V1.final 3-criteria; §8.1 b4 "shippable in framing terms" 3-element; §8.2 b2 §4.6 tear-down 4 quoted commitments; §8.3 b1 §3.4 3-criteria restated; §8.3 b3 §8 → Phase 4 (i)–(iv)).
- **1 bullet extracted per F/CTO Q-S6 = β override:** §8.3 b3 (§8 → Phase 4 handoff boundary). 4 Phase 4 territory items lifted into 4 sub-bullets: (i) Criterion-to-sub-version mapping; (ii) Per-sub-version capability boundaries; (iii) Dependency ordering across §2 / §4 / §7 surfaces; (iv) Per-sub-version acceptance criteria at one-session-granularity per Linear issue convention. Lead bullet framing (§8 → Phase 4 handoff boundary + ADR-004 `DECISIONS.md:353` verbatim cite) preserved.
- **9 bullets preserved verbatim** per F/CTO single-bullet-narrow scoping.

**App B running total post-PR 9 = 19 entries**

- PR 9 adds 5: (a) §3.4 → §8 forward-pointer closure at §8.3 + (b) §1.4 → §8 forward-pointer closure at §8.3 (with §1.3 → §1.4 section-drift correction noted) + (c) ADR-002 §7.0 gap #4 milestone-framing dimension closure at §8.3 + (d) §8 → Phase 4 / Linear backlog handoff anchor + (e) §8 ↔ §4.6 cross-reference shape.
- Running total: 14 (post-PR 8) + 5 (PR 9) = 19.

**Q7 verify-pass queue total post-PR 9 = 17**

- No PR-9-VP candidates added (VP-§8-1 wording-fidelity check resolved inline by Q-S7 α-extended scope).
- Running queue: 17 (post-PR 8) + 0 (PR 9) = 17.

**Acceptance-flag recap (PR 9 / §8)**

- **§8 locked 2026-05-19** (per PR 9 merge). Per-sub-§ locks: §8.1 (1 framing paragraph + 4 bullets covering V1.0 / V1.x / V1.final / "shippable in framing terms"; illustrative V1.0 = Plaid+balances and V1.1 = full manual transaction entry examples preserved as illustrative-not-normative per ADR-004); §8.2 (1 framing paragraph + 3 bullets covering drop-replace mechanic / §4.6 tear-down cross-reference / §4.6 availability + §2.4.4 non-silent-staleness cross-reference); §8.3 (1 framing paragraph + 3 bullets covering §3.4 criteria reciprocation / §1.4 forward-pointer closure / §8 → Phase 4 handoff with (i)–(iv) sub-bullet extraction per Q-S6 = β). No Sec at-lock pass required (no credential / auth / new posture surface). No Architect at-lock pass required (framing-shaped, no V1 architecture surface). Five boundary-note routing flags (a)–(e); zero Architect flags; zero Sec flags; zero V1-block flags either side. Smallest routing-flags block of any locked PRD section to date (5 boundary notes).
- **No new ADR for §8 lock.** All §8 content is verbatim-derivable from ADR-004 (`DECISIONS.md:353`); the sub-version convention, drop-replace mechanic, and §3.4 V1-done cross-reference are explicit ADR-004 commitments. §8 is the PRD-side surfacing of ADR-004's milestone framing, not a new scope decision. Joins §3 / §6 / §7 in the "no-new-ADR lock" pattern; §8 is the fourth such instance.
- **No cross-section surgical edits at §8 lock.** §3.4 closing line and §1.4 V1 existing-system-replacement test bullet are already correctly forward-shaped; §8.3's reciprocation closes both forward-pointers without requiring upstream body edits. §4.6 cross-references at §8.2 are one-way (§8 → §4.6); no §4.6 body revision required. §8 is purely additive to upstream sections. **Section-drift correction note:** source-§8 referenced §1.3 V1-correctness; the V1-correctness content moved to §1.4 during PR 2 / §1 rewrite. Section-drift correction applied at §8.3 + routing flag (b) per PR 9 Q-S7 α-extended override; no §1.4 body revision required (§1.4 already correctly forward-shaped).
- **Forward-pointer closures at §8 lock:** (a) §3.4 → §8 closes at §8.3; (b) §1.4 → §8 closes at §8.3 (corrected from source §1.3 ref per Q-S7 α-extended cross-ref retarget); (c) ADR-002 §7.0 gap #4 milestone-framing dimension closes at §8.3 (§3.4 already closed the criteria dimension at §3 lock). Three forward-pointer closures + §8 → Phase 4 handoff anchor established at routing flag (d).
- **PM-lean track now 23-for-30** post-§8 structure gate + body bundle acceptance. **Sixth confirmed bulk-closeout-from-structure-proposal pattern** (§3 → §5 → §6 → §7 → §8 — PR 9 / §8 is the sixth in the bulk-closeout sequence and the fifth in the PM-author-from-PR-6 series). **Smallest realized PRD section by body line count to date** post-relocation (~28 body lines + 4 sub-bullets from §8.3 b3 β extraction; vs §7's 35 body lines, §6's 35).
- **§8 is the last PM-led drafting task in Phase 1 Step 3.** Post-§8 lock, PR 10 (overview / appendices / App B consolidation) remains for Step 3.5 closure. Then post-rewrite verify pass (Q7 queue 17 entries) gates Step 4 entry. All PM-led PRD sections (§1 substantively drafted; §2.1–§2.6 locked; §3 locked; §5 locked; §6 locked; §7 locked; §8 locked) are complete; §4 Sec-primary-author locked at PR 5; PRD substantive content surface is complete pending Phase 1 Step 4 architectural overview consult. **PM hand-off to Architect for Step 4 follows post-rewrite verify-pass closure.**

**Team-mode operational note (third dispatch under v1.25 convention)**

- `pm-pr9-structure@phase-1` teammate handled both structure proposal and body draft turns. Second consecutive idle-before-deliverable timing event surfaced (idle notification arrived without sign-off; `ls` showed empty); resolved via diagnostic ping (per `memory/feedback_team_mode_idle_before_deliverable.md` saved earlier this session) rather than corrective re-poke. PM responded with case (4) — done, signals out-of-order — and full sign-off message arrived shortly after. Memory pattern validated on second exercise.

**Substance preservation**

- 0 substance amendments beyond the authorized §1.3 → §1.4 content-correctness fix (Q-S7 α-extended scope; would have propagated incorrect cross-ref into Step 4 Architect consult if missed). All locks preserved (ADR-002 / ADR-004 / ADR-005 / ADR-006 / §3.3 / §3.4 / §1.4 / §2.1 / §2.4.4 / §4.1 / §4.6).
- 10 cross-ref retargets applied (Q-S7 α-extended scope; 4 distinct PRD.md:NNN refs × 10 instances). Zero PRD.md numerics remain in §8 body post-rewrite.
- 7 DECISIONS.md numeric refs preserved verbatim (`:353` × 3 + `:484` × 2 + `:644` shorthand × 2) per F/CTO Q-S7 scope ruling.

**No new ADR.** PR 9 is presentation-only; all content grounded in already-locked ADRs (ADR-004 primarily). Follows PR 2 / 3 / 4 / 5 / 6 / 7 / 8 precedent. Joins §3 / §6 / §7 in "no-new-ADR lock" pattern.

---

### v1.27 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 8 / §7 (Constraints) rewrite.** Fifth bulk-closeout PR under Step 3.5 cadence (mirrors PR 7 / §6 + PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6 + PR 7. **Second PR to invoke a F/CTO β override at structure gate** — Q-S6 = β narrowly scoped to §7.3 b2 (parallel to PR 6 / v1.24 invoking β at Q-S2 across the broader shape-discipline sweep; PR 8's β scope is single-bullet-narrow). **First PR to exercise the Acceptance-flag recap block convention** at the dedicated WORKFLOW.md location per PR 4 / v1.22 explicit precedent.

**Section rewritten**

- **§7** (Constraints) — 3 sub-sections preserved (§7.1 Cost / §7.2 Scale / §7.3 Usage model) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §7 (lines 994–1037; 43 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §7 (35 body lines; net line-count compression of -8 lines / -19% under α-for-α/α/α/α/β structure-gate ratify).

**Structure-gate decisions (Q-S1 through Q-S6)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §7 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §7 prelude tightened by single-phrase drop (cross-§-pattern meta phrase); sub-§ preludes verbatim | α |
| Q-S4 | **α** — 5 routing flags (a)–(e) → App B; mix of closing-trace + forward-operative entries | α |
| Q-S5 | **α** — 4 process-record acceptance flags → WORKFLOW.md `Acceptance-flag recap (PR 8 / §7)` block; bullet 1 dropped as prelude-duplicate | α |
| Q-S6 | **β** — §7.3 b2 extracted (4 V2+ deferred surfaces lifted into sub-bullets); other 9 bullets preserved verbatim | α (F/CTO override) |

**5-for-6 PM acceptance; 1 F/CTO override at Q-S6 = β.**

**β extraction sweep — 1 extraction (single-bullet scope)**

- Systematic sweep of all 10 source body bullets across §7.1–§7.3 for three β triggers per PR 6 precedent. 3 multi-clause candidates surfaced at structure proposal (§7.2 b1 Historical-data depth; §7.2 b3 Plaid sync throughput; §7.3 b2 Invite-only forward-compat).
- **1 bullet extracted per F/CTO Q-S6 = β override:** §7.3 b2 (Invite-only forward-compat). 4 V2+ deferred surfaces (friends-and-family onboarding, invite-flow UI, multi-user auth gates, per-user data-access boundary checks) lifted from inline list into 4 indented sub-bullets. Lead bullet's primary commitment (V1 forward-compat + closed-and-invite-controlled framing + cross-refs to §5.7 / §6.1) preserved verbatim. Bold-inline `Invite-only forward-compat — V2 adds the second user without data migration.` preserved on lead bullet.
- **9 bullets preserved verbatim.** §7.2 b1 + §7.2 b3 surfaced as β candidates but preserved verbatim per F/CTO scoping (single-bullet-narrow override).

**Line-count outcome under α/α/α/α/α/β**

- PM α target at structure proposal: -32% compression (-12 lines).
- CoS β-reset estimate post-Q-S6 ratify: -25% to -28% compression.
- **Realized: -8 lines net / -19%** — below both projections. Compression source: routing-flags-block collapse + acceptance-flags-block lift to WORKFLOW.md + §7 prelude tightening. Offset: β extraction expansion on §7.3 b2 (+4 net lines: 1 source bullet → 1 lead + 4 sub-bullets). **Not a problem; net compression remains substantial; reset reported honestly per PR 6 / v1.24 precedent.**

**App B running total post-PR 8 = 14 entries**

- PR 8 adds 5: Sec V2-implementation closure-trace (flag (a); resolved at §4.6 V2-ship-gate inventory (iv) + closure at §4 (k)(iv)/(m)) + Architect Phase 3 forward-pointer (flag (b)) + §7.2 ↔ §6.4 cross-reference (flag (c)) + §5 flag (e) closure (flag (d); resolved-at-§7.3-lock process-record) + §7 ↔ §4 routing closure (flag (e); hybrid).
- Running total: 9 (post-PR 7) + 5 (PR 8) = 14.

**Q7 verify-pass queue total post-PR 8 = 17**

- PR-8-VP-§7-1 surfaced: §7's §4 forward-pointers cite §4's locked-content scope but do not explicitly cross-reference §4.6 V2-ship-gate Sec-consult inventory item (k)(iv); evaluate at Q7 = γ whether explicit `§4.6(k)(iv)` anchor citation is warranted. Marginal; not joint-mergeable with prior candidates.
- Running queue: 16 (post-PR 7 merged) + 1 (PR 8) = 17.

**Acceptance-flag recap (PR 8 / §7)**

- **§7 is locked as of 2026-05-18.** No Security Reviewer at-lock pass required — §7 has no credential-handling surface, no auth-flow surface, no multi-tenant-isolation primitive ratification, no Plaid integration surface ratification, no money-flow surface, and no financial-calculation-integrity claim; §7.1's spend-cap forward-consult is a V2-implementation flag (landed at §4.6 V2-ship-gate inventory item (iv)); §7.2's multi-tenant isolation-at-scale routing is a forward-pointer to §4 (landed at §4.1–§4.6).
- **Per-sub-section locks:**
  - **§7.1** — 1 target-ceiling commitment + 1 cost-shape at-risk flag + 1 per-line-item-out-of-scope boundary; ADR-002 §6.0 verbatim, no itemized vendor pricing.
  - **§7.2** — 3 Architect Phase-3 scale dimensions + 1 RLS query-shape forward-pointer + 1 §4-routed isolation-at-scale posture pointer.
  - **§7.3** — 1 single-user-V1-multi-tenant-day-one commitment + 1 invite-only-forward-compat commitment (lead bullet preserved verbatim; 4 V2+ deferred surfaces extracted under Q-S6 = β override); ADR-002 §1.4 + §5.7 verbatim.
- **Five routing flags (a)–(e) added** (1 Sec V2-implementation closure-trace, 1 Architect Phase 3 forward-pointer, 3 boundary notes — all relocated to App B per Q-S4 = α).
- **No new ADR for §7 lock.** §7 introduces no new scope decisions; all content is grounded in already-locked ADRs (ADR-002 §6.0 for §7.1; ADR-002 §1.4 + §5.7 for §7.3) or forward-points to Architect Phase 3 (§7.2). **No cross-section surgical edits** — §7's content is purely additive to upstream sections; no §1.4-line-58-style alignment required at §7 lock.
- **Closure-trace summary:** The Sec routing flag (a) closed at §4.6 lock (PR 5 / v1.23); the Architect routing flag (b) resolves at Phase 3 (ARCHITECTURE.md cost reconciliation + scale-dimension implementation), does not block §7 lock at the PRD level. Boundary notes (c), (d), (e) are documentation markers; (d) closes §5 routing flag (e) at this lock (PR 8 / §7.3); (e) is largely closed at §4 lock with residual forward-operative boundary-note semantics for post-hoc cross-§ navigation.

**Team-mode operational continuation**

- `pm-pr8-structure@phase-1` teammate handled both structure proposal and body draft turns under one continuous teammate (vs PR 7's structure-as-subagent + body-as-teammate split). Sync-mismatch pattern surfaced after Q-S ratify relay (teammate went idle without producing body deliverables on first turn); re-poke with "Not a re-fire" framing per `memory/feedback_pm_sync_mismatch_pattern.md` unblocked cleanly.

**Substance preservation**

- 0 substance amendments. Presentation-only rewrite. All locks preserved (ADR-002 §1.4 + §6.0 + Finding (a) + Finding (f) + §5.7 + §6.1 + §6.4 + §4.6 + §2.1.3 + §2.1 + §3).
- 1 cross-ref retarget (`PRD.md:820` → `§5 routing flag (e)` inside App B entry for flag (d); body itself has zero retargets — cleanest-sweep parallel to PR 3 + PR 6 + PR 7).
- 3 DECISIONS.md numeric refs preserved verbatim (`:275`, `:534`, `:541`).

**No new ADR.** PR 8 is presentation-only; all content grounded in already-locked ADRs. Follows PR 2 / 3 / 4 / 5 / 6 / 7 precedent.

---

### v1.26 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 7 / §6 (Out-of-scope for this PRD lifecycle) rewrite.** Fourth bulk-closeout PR under Step 3.5 cadence (mirrors PR 6 / §5 + PR 4 / §3 + PR 2 / §1). PM continues as primary author from PR 6. Smallest section under rewrite — 39 source body lines (including blank padding + routing-flags block) vs §5's 107. **First team-mode dispatch under v1.25 operating-model convention** — `pm-pr7-body@phase-1` teammate spawned for body draft, rendered in split-pane visible to F/CTO live.

**Section rewritten**

- **§6** (Out-of-scope for this PRD lifecycle) — 5 sub-sections preserved (§6.1 / §6.2 / §6.3 / §6.4 / §6.5) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §6 (lines 953–992; 39 inclusive body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §6 (35 body lines; net line-count *compression* of -4 lines / -10.3% under α-for-α structure-gate ratify).

**Structure-gate decisions (Q-S1 through Q-S5)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **N/A** — no blockquotes in §6 source (convention trivially satisfied) | N/A confirmation |
| Q-S3 | **α** — §6 prelude ADR-citation compresses to ID-only; per-sub-§ axis-framing preludes preserved verbatim | α |
| Q-S4 | **α** — §6 prelude §5/§6 + §3.5/§6 distinction preserved verbatim; VP-§6-1 joint-merged with VP-§5-2 at Q7 | α |
| Q-S5 | **α** — 3 routing flags (a)/(b)/(c) → App B; flag (a) as resolved-at-§6-lock process-record | α |

**4-for-4 PM acceptance** (Q-S2 = N/A trivially satisfied). No F/CTO override at structure gate. Cleanest ratify pass since PR 4.

**β extraction sweep — 0 extractions**

- Systematic sweep of all 6 source body bullets across §6.1–§6.5 for three β triggers per PR 6 precedent.
- **0 bullets extracted.** §6.3 b2 TLH bullet (strongest β candidate; 4 clauses jointly applying the information-vs-prescription axis to TLH-specific case) preserved verbatim per PM α default; F/CTO ratified α at Q-S2 = N/A bypass + Q-B1 = α body gate.
- All 6 bullets preserved verbatim. All 5 per-sub-§ axis-framing preludes preserved verbatim. Bold-inline emphasis preserved verbatim across 4 carve-out anchors (§6.2 b1 estimated-tax-payment + §6.3 axis-prelude information-vs-prescription + §6.3 b2 ADR-007 / information-vs-prescription / remain V2+ trajectory + §6.5 axis-prelude Explicit non-§6 carve-out).

**Line-count outcome under α**

- PM α target at structure proposal: -10% to -20% mild compression.
- Realized: **-4 lines net / -10.3%** — within projected range. Compression source: routing-flags-block collapse (-4 lines, 5-line `#### Open routing flags affecting §6` block → 1-line italic App B marker) + §6 prelude ADR-citation compression (~no net line, denser sentence 1). No β-driven expansion.

**App B running total post-PR 7 = 9 entries**

- PR 7 adds 3: §6 ↔ §1.4 framing alignment (resolved-at-§6-lock process-record per Q5-a; parallel to PR-4-App-B flag (f)) + §6 ↔ §5 distinction (forward-operative boundary note; mirrors §5's routing flag (d) TLH boundary note) + §6 ↔ §3.5 distinction (forward-operative boundary note).
- Running total: 6 (post-PR 6) + 3 (PR 7) = 9.

**Q7 verify-pass queue total post-PR 7 = 16**

- VP-§6-1 (§6 prelude — §5/§6 distinction symmetric mirror) joint-merged with VP-§5-2 (PR 6 candidate — §5 prelude's §6 contrast list partial-stale post-ADR-007/TLH) into a single bidirectional Q7 = γ candidate; single disposition resolves both sides post-PR 10.
- **No net growth from PR 7.** PR 6 carried 16; PR 7 surfaces 1 candidate merged with existing.

**Team-mode operational confirmation**

- `pm-pr7-body@phase-1` teammate dispatch worked as v1.25 convention specified: split-pane visible to F/CTO; async run; idle notification at turn end; rendered file extracted proactively + opened in One Markdown for Q-B1 review.
- Forward implication: PR 8 / §7 PM dispatch (next in Step 3.5 source order) follows same team-mode pattern.

**Substance preservation**

- 0 substance amendments. Presentation-only rewrite. All locks preserved (ADR-002 §3.0 + ADR-007 + ADR-002 Finding (c) relabel + §5 / §6 / §3.5 cross-§ distinction architecture + §1.2 archetype-attribute-#4 + §2.5.3 estimated-tax-payment cross-ref + §5.5 lot-level-cost-basis V2+ narrowness + §5.7 invite-only V2 expansion + §1.4 surgical-edit closing-trace).
- 0 cross-ref retargets (cleanest sweep — parallel to PR 3 / §2 + PR 6 / §5).

**No new ADR.** PR 7 is presentation-only; all content grounded in already-locked ADRs (ADR-002 §3.0 + ADR-007). Follows PR 2 / PR 3 / PR 4 / PR 5 / PR 6 precedent.

---

### v1.25 — 2026-05-19

**PR #[TBD] — Team-mode operational convention for agent dispatches.** Operating-model addendum locking forward execution-agent dispatches to Claude Code team-mode with `team_name` matching the active phase identifier (`phase-1` for Phase 1). Prior PRs (Step 3.5 PRs 1–6) ran with plain `Agent` subagent calls — work rendered in the orchestrator's pane, no split-pane visibility for the Founder/CTO. Convention shift surfaced mid-PR-7 when the PR 7 / §6 structure-proposal PM was dispatched as an inline subagent and Founder/CTO noted the missing pane against an earlier same-session split-pane test that had verified team-mode rendering works.

**Mechanic.** `team_name: phase-1` on `Agent` tool calls spawns the teammate into the `phase-1` team (created locally at `~/.claude/teams/phase-1/`), where it gets its own split-pane and runs asynchronously while the orchestrator stays free to handle other work. Teammates send idle notifications when their turn ends; F/CTO can watch progress live and intervene without waiting for the orchestrator to relay.

**Scope.** Convention applies to all execution-agent dispatches in the active phase — Product Manager, Architect, Security Reviewer, UX Designer, Visual Designer, and any future Phase 5+ roles when they activate. New phases create their own team under `phase-<N>` naming when phase entry locks; team creation is a one-time setup step per phase. ADR-003 already establishes phase teams conceptually; this is operational reinforcement, not a new ADR.

**Changes.**

- `WORKFLOW.md` — added "Team-mode for agent dispatches" paragraph at end of Operating model section (after Task tracking via Linear, before Agent roster); version bump v1.24 → v1.25.
- No PRD / DECISIONS.md / per-directory CLAUDE.md changes — purely operating-model surface.
- No header revision — line 6's existing "Team-mode (`phase-1` team) per ADR-003 active" wording is now genuinely operational.

**Forward implications.** PR 7 / §6 PM body draft (next dispatch in Step 3.5) is the first team-mode dispatch under this convention. All subsequent Phase 1 execution-agent dispatches use team-mode. When Phase 2 (UX/Visual) opens after Step 4 ratifies, a `phase-2` team gets created at phase entry; the same convention applies.

---

### v1.24 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 6 / §5 (V2 deferred candidates) rewrite.** Third bulk-closeout PR under Step 3.5 cadence (mirrors PR 2 / §1 + PR 4 / §3). PM resumes as primary author after PR 5 / Sec-primary-author. First PR to exercise **β shape-discipline aggressively** under F/CTO Q-S2 = β override — net line-count expansion (+61 lines vs. source / +57%) by design, distinct from the line-count-compression trajectory of prior bulk-closeout PRs.

**Section rewritten**

- **§5** (V2 deferred candidates) — 7 sub-sections preserved (§5.1 / §5.2 / §5.3 / §5.4 / §5.5 / §5.6 / §5.7) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §5 (lines 846–952; 107 source body lines including 0 blockquote lines).
- Rewritten: `PRD.md` §5 (168 lines; net line-count *expansion* of +61 lines / +57% under β extraction).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ inheritance (mirrors PR 2 + PR 4). Two F/CTO ratify gates: structure (5 Q-S) + body (Q-B1). Zero sub-section gates.
- **β shape-discipline applied aggressively** per F/CTO Q-S2 override — bullet-extraction within dense §5.4 / §5.5 / §5.6 / §5.7 bullets that contain inline `(a)/(b)/(c)` enumerations or multi-clause V2+ lists. 20 lead bullets extracted into 77 new sub-bullets across 7 sub-sections.

**Structure-gate decisions (Q-S1 through Q-S5)**

| Q | Locked answer | PM recommendation |
|---|---|---|
| Q-S1 | **α** — bulk-closeout cadence | α |
| Q-S2 | **β** — apply shape-discipline aggressively (bullet-extraction in dense §5.5 / §5.6 bullets) | α (F/CTO override) |
| Q-S3 | **α** — §5 prelude ADR-citation compresses to ID-only | α |
| Q-S4 | **α** — §5 prelude §6-contrast list preserved verbatim; VP-§5-2 carried to Q7 = γ | α |
| Q-S5 | **α** — routing flag (e) carries as resolved-at-§7.3-lock process-record (parallel to PR 4 flag (f)) | α |

**4-for-5 PM acceptance; 1 F/CTO override at Q-S2 = β.**

**β extraction-plan operationalization**

- Systematic sweep of all 65 source body bullets across §5.1–§5.7 for three β triggers: (A) inline (a)/(b)/(c) enumerations; (B) multi-clause V2+ lists separated by `;` or `/` each naming distinct V2+ commitments; (C) nested clauses with sub-deliverables.
- **20 bullets extracted:** §5.4 (b3 pre-emptive notification; b4 manual transaction entry; b6 Plaid product expansions; b7 Plaid coverage & instrument mechanics); §5.5 (b1 auto-cat + CRUD; b2 multi-year tax; b5 lot-level tax features incl. TLH carve-out; b7 live tax-data API; b13 quarterly-due-date reminders; b16 quarterly-installment-sizing; b18 bracket-aware Unrealized refinements); §5.6 (b1 section ordering; b4 Rebalancing editor; b5 generation-cadence; b8 alternative output formats; b11 snapshot retention; b13 staleness-marker); §5.7 (b1 multi-user expansion; b2 multi-currency).
- **45 bullets preserved verbatim** (β triggers not warranted — single-V2+-commitment shape integral to inline structure; splitting would dilute the unit-of-deferral).
- Bold-inline emphasis preserved verbatim across all extractions: `Sec consult required before V2 ship` (§5.4); `Tax-loss harvesting recommendations are NOT included…` (§5.5 — promoted to its own sub-bullet); `Forward-Sec-consult flag (carry-forward to V2 scoping):` (§5.6 × 2 — bullets not β-extracted; flags preserved as-is).

**Line-count expectations reset under β**

- PM α target at structure proposal: ~5–10% net compression (~95–100 rewritten lines).
- F/CTO Q-S2 = β override produced **+61 line net expansion** (168 rewritten lines, +57% vs. source). **Not a problem; expected under β; reset explicitly at body gate per F/CTO override caveat.**
- Word-count remains near-neutral (ADR-citation compression in prelude offsets bullet-extraction sub-bullet leads).

**PR 6 totals (§5)**

| Metric | §5 |
|---|---|
| Source body lines | 107 (lines 846–952) |
| Rewritten body lines | 168 |
| Line-count delta vs. source | **+61 lines / +57% (β expansion under Q-S2 override)** |
| Word-count compression | near-neutral (slight expansion) |
| Sub-sections preserved | 7 |
| Title rewrites | 0 |
| Blockquote lines | 0 → 0 (source has none) |
| Lead bullets preserved | 65 |
| Bullets extracted under β | 20 → 77 new sub-bullets |
| App B entries | 6 (5 forward-looking + 1 process-record resolved-at-§7.3-lock) |
| App C entries | 0 |
| First-person cleanups | 0 |
| §-prefix normalizations | 0 |
| Cross-ref retargets | **0** (cleanest sweep across PR 3 / PR 4 / PR 5 / PR 6) |
| In-body §-anchor retargets | 0 |
| ADR re-narration drops | 1 (§5 prelude per Q-S3 = α) |
| Substance amendments | **0** (presentation-only) |
| VP candidates surfaced | 3 (VP-§5-1, VP-§5-2, VP-§5-3 — all Q7 = γ deferred) |
| Q7 verify-pass queue total | **16** |
| Ratify gates | 2 (structure + body) |

**Acceptance-flags relocation (per Q1 = β)**

- §5 body has **no `#### Acceptance flags` block** in rewritten form.
- §5 body has **no `#### Open routing flags affecting §5` block** — replaced by italic Appendix B marker at §5 foot.
- §5 lock metadata preserved across: WORKFLOW.md v1.14 changelog (§5 lock + ADR-007) + this v1.24 entry.
- 6 App B entries (5 forward-looking + 1 process-record) carried forward in PR 6 body deliverable for PR 10 consolidation.

**VP candidates surfaced (Q7 = γ deferred)**

3 new VP candidates from PR 6, bringing Q7 verify-pass queue to **16 total** (7 from v1.19 + 3 from PR 4 + 3 from PR 5 + 3 from PR 6):

1. **PR-6-VP-§5-1** (§5.1 b4) — "user-driven historical correction workflows" may collide with §4.6 audit-log integrity posture (ADR-008 Decision 4 immutable audit-log retention).
2. **PR-6-VP-§5-2** (§5 prelude) — §6 contrast inline list duplicates §6 canonical enumeration and is already partially stale (ADR-007 added TLH but list does not include TLH); revisit after PR 8 §6 rewrite.
3. **PR-6-VP-§5-3** (§5.6 b5) — "in-app cron-failure notification to the user" V2+ commitment may overlap §4.6 V1 incident-handling baseline ("incident-log file at the F/CTO level").

**F/CTO ratification status**

- Structure gate (Q-S1 / Q-S2 / Q-S3 / Q-S4 / Q-S5): **5-for-5 ratified** with 1 F/CTO override at Q-S2 = β.
- Body gate (Q-B1): **α — accept body as drafted**.

**Patterns established / extended during PR 6**

- **β shape-discipline operationalization at bulk-closeout cadence.** First time an entire bulk-closeout PR ratifies β at structure-gate; sets precedent for future PRs where F/CTO wants to override PM α default on shape discipline.
- **β extraction-plan preamble as body-deliverable shape.** PM body draft for β PRs leads with the systematic sweep + bullet-by-bullet classification table before the rewritten body. Distinct from α PRs (which lead with the rewritten body directly).
- **Bold-inline emphasis preserved verbatim across extractions.** Bold-inline flags (Sec consult, TLH-not-in-V2+, Forward-Sec-consult prelude) preserve in extracted sub-bullets, not collapsed.
- **PR 6 cleanest cross-ref retarget sweep** (zero retargets, parallel to PR 3 §2; cleaner than PR 4 / PR 5).
- **Working artifacts to `temp/` from creation** (per `memory/feedback_working_artifacts_temp_not_docs.md`) — zero `docs/prd-rewrite*` files added by PR 6.
- **Body-gate standalone rendered file convention applied proactively** (per `memory/feedback_body_gate_rendered_extract.md`) — PM extracts to `temp/prd-rewrite-pr6-section5-rendered.md` before surfacing the body gate.
- **CoS-side typo correction at integration.** PM body deliverable carried 4 sweep-arithmetic / metadata typos (78→77 sub-bullets count; 62→65 source-body-bullet count; 42→45 preserved-bullet count; v1.17→v1.14 §5-lock citation). CoS corrected all four at transcription; rewritten §5 body content itself was unaffected. Pattern: CoS verifies sweep arithmetic + version citations against ground truth before transcribing PM-drafted changelog entries.

**Engagement notes**

- **PM workhorse** across 2 stages (structure proposal + body deliverable). 5 structure-gate Qs surfaced; 4 PM α accepted + 1 F/CTO β override.
- **Sec untouched** (no V1 Sec-at-lock surface in §5; routing flags (a)/(b)/(c) are forward-Sec-consult V2-ship gates, not V1 commitments — preserved as-is in App B carry-forward).
- **Architect untouched** (no architecture surface in PR 6; flag (f) carries to App B for V2-scoping-phase consumption, not Phase 3).
- **CoS bookkeeping** + 2 ratify gates with F/CTO via AskUserQuestion (5 structure-gate Qs + Q-B1 body gate, all one-question-at-a-time) + integration pass (PRD.md §5 swap + this v1.24 entry; **zero cross-ref retargets**) + 4 sweep-arithmetic/metadata typo corrections from PM body deliverable.

**Next thread:** **PR 7 — §6 (Out-of-scope for this PRD lifecycle) rewrite.** Bulk-closeout cadence per Q3 = γ (mirrors PR 6 + PR 4 + PR 2); §6 has 5 sub-sections (§6.1–§6.5) plus 3 routing flags (a)/(b)/(c) plus the lock-metadata block; low-density permanent-non-goal inventory. PM continues as primary author. PR 7 inherits PR 6's β operationalization precedent if F/CTO wants β again; PM α default if not pre-empted. Closes VP-§5-2 (§5 prelude §6-contrast list re-evaluation after §6 canonical list stabilizes).

### v1.23 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 5 / §4 (Security and compliance posture) rewrite.** Second sub-section-gates PR (mirrors PR 3 / §2 cadence). **First Sec-as-primary-author PR since PR 1 kickoff.** ADR-008-locked canonical-reference content (6 Sec axes; 14×8 SD classification matrix; 15×7 RLS test catalog; V1 retention/availability/incident-handling baseline; 2 pattern divergences) preserved verbatim by construction.

**Section rewritten**

- **§4** (Security and compliance posture) — 6 sub-sections preserved (§4.1 / §4.2 / §4.3 / §4.4 / §4.5 / §4.6) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §4 (lines 720–845; 126 source lines including 0 blockquote lines).
- Rewritten: `PRD.md` §4 (lines 803–901; ~99 lines; ~21% net line-count compression).

**Pattern divergence declaration**

- **Sub-section-gates** per Q3 = γ. 1 structure gate (6 sub-Qs Q-S1–Q-S6) + 6 body gates (1 per §4.N) = 7 ratify touchpoints.
- **Zero bulk-closeout, zero per-bullet gates.**

**Structure-gate decisions (Q-S1 through Q-S6)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — 1 structure + 6 body gates (mirror PR 3 §2 cadence) |
| Q-S2 | **α** — aggressive Shape-P compression (framing-prelude + bullet-tail rationale-trace) |
| Q-S3 | **α** — §4.4 matrix preserved verbatim; framing compress only |
| Q-S4 | **β** — §4.5 RT-07 orphan-ref `acceptance flag (ii) below` → `ADR-008 Decision 3 — reserved-vacant row consolidation rationale` |
| Q-S5 | **γ** — §4.2 line-ref retarget + redundant parenthetical drop + first-person voice conversion (F/CTO override of Sec β recommendation; rationale: §2.4.1 already rewritten to product-voice at PR 3, so verbatim-re-citation rationale no longer holds; γ maintains citation consistency rather than preserving stale citation form) |
| Q-S6 | **α** — §4.6 V2-ship-gate inventory preserved as nested bullets |

**PR 5 totals across §4.1–§4.6**

| §4.N | Source lines | Rewritten | Compression |
|---|---|---|---|
| §4.1 | ~9 | ~9 | minor |
| §4.2 | ~12 | ~11 | ~10% |
| §4.3 | ~11 | ~10 | minor |
| §4.4 | ~20 | ~20 | minor (table verbatim) |
| §4.5 | ~21 | ~21 | minor (table verbatim + Q-S4 RT-07 cell update) |
| §4.6 | ~46 | ~18 | **~60%** (largest single compression) |
| §4 prelude | ~3 | ~3 | preserved verbatim |
| **Total** | **126** | **~99** | **~21% net** |

**ADR-008 canonical-reference preservation (per Decisions 1 + 2 + 3 + 4 + 5)**

- **Decision 1** (6 canonical Sec axes i–vi): all preserved verbatim across §4.1 + §4.3.
- **Decision 2** (14×8 SD classification matrix): all 112 cells preserved verbatim character-for-character (cell-level verification performed at body-gate-4). Closed-enum values preserved verbatim (sensitivity-tier 3 / storage-protection 4 / retention-posture 4 incl. N=90). SD-13 `—` cross-cutting placeholder preserved across 3 cells.
- **Decision 3** (15×7 RLS test catalog): 104 of 105 cells preserved verbatim; 1 cell (RT-07 Surface) updated per documented Q-S4=β closure (orphan-ref → canonical-reference anchor). Closed-enum values preserved verbatim. V1-block threshold (`critical` severity only; RT-02 + RT-05) preserved.
- **Decision 4** (V1 retention/availability/incident-handling baseline): all preserved verbatim including "best-effort uptime, no SLO" / "incident-log file at the F/CTO level" / "No user-facing delete-my-data control as a V1 surface" / V2-trajectory ramp items (a)–(d).
- **Decision 5** (pattern divergences from PM-led default): preserved at WORKFLOW.md changelog + ADR-008 itself (no §4.6 body action required).

**Q-S5 = γ F/CTO override at §4.2 (single F/CTO override; treated as presentation-only)**

F/CTO chose γ over Sec's β recommendation at structure-gate Q-S5:

- Retarget `PRD.md:269` → `PRD.md §2.4.1` (§4.2 bullet 1).
- Drop redundant parenthetical re-narrating §2.4.1 content.
- **Convert first-person voice fragment** `the institution credentials I enter` → `the institution credentials the user enters`.

Rationale: §2.4.1 has already been rewritten to product-voice at PR 3 on `main`; the verbatim-re-citation rationale for Sec's β recommendation no longer holds. F/CTO override maintains citation consistency with the rewritten §2.4.1 rather than preserving a stale citation form. Treated as presentation-only (voice-cleanup to match upstream rewrite), not a substance amendment.

**Cross-reference retargeting (per Q4 = α)**

| File | Old | New |
|---|---|---|
| PRD.md (§4.2 bullet 1) | `` `PRD.md:269` `` | `` `PRD.md §2.4.1` `` |
| WORKFLOW.md (line 478, v1.X §7.3 changelog) | `` `PRD.md:820` `` | `` `PRD.md §5.7` `` |

2 retargets total: 1 in-body (§4.2) + 1 WORKFLOW.md. Zero DECISIONS.md retargets. Zero §1.N renumber retargets in §4 body. Zero §-prefix normalizations in §4 body (already clean).

**Acceptance-flags relocation (per Q1 = β)**

- §4 body has **no `#### Acceptance flags` block** in rewritten form.
- §4 body has **no `#### Open routing flags affecting §4` block** — replaced by italic Appendix B marker at §4 foot.
- §4 lock metadata preserved across: WORKFLOW.md v1.17 changelog (§4 lock) + ADR-008 + this v1.23 entry.
- 16 App B entries (11 forward-looking + 5 process-record) carried forward in PR 5 body deliverable for PR 10 consolidation.

**VP candidates surfaced (Q7 = γ deferred)**

3 new VP candidates from PR 5, bringing Q7 verify-pass queue to **13 total** (7 from v1.19 + 3 from PR 4 + 3 from PR 5):

1. **PR-5-VP-§4-1** (§4.2) — credential-error states (c)/(d) observational distinguishability at V1 user-facing surface (depends on Plaid webhook event taxonomy).
2. **PR-5-VP-§4-2** (§4.3 + §4.5 RT-13) — RT-13 staleness severity (high) vs. §2.6.5 account-name exposure dimension; potential revision to critical (would amend ADR-008 Decision 3 + raise V1-ship-blocker count to 3).
3. **PR-5-VP-§4-3** (§4.6) — V1 indefinite audit-log retention vs. V2 incident-handling-ramp clause-level tension.

**F/CTO ratification: 12-for-12 acceptance across structure + body gates** (5 Sec-recommended + 1 F/CTO override at Q-S5=γ + 6 body-gates accepted as drafted):

- Structure gate: Q-S1 = α / Q-S2 = α / Q-S3 = α / Q-S4 = β / Q-S5 = γ (override) / Q-S6 = α.
- Body gates: Q-B1 = α / Q-B2 = α / Q-B3 = α / Q-B4 = α / Q-B5 = α / Q-B6 = α.

**Patterns established / extended during PR 5**

- **Sec-as-primary-author cadence pattern established** for sub-section-gates. ADR-008 Decision 5 pattern-divergence-from-PM-led default exercised at PR 5 ship.
- **Default-to-source-shape = §2/§3 rewritten shape on `main`** convention (per `memory/feedback_rewrite_convention_drops_blockquotes.md`) — N/A for §4 since source had 0 blockquote lines, but convention applied at briefing.
- **Working artifacts to `temp/` from creation** (per `memory/feedback_working_artifacts_temp_not_docs.md`) — zero `docs/prd-rewrite*` files added by PR 5.
- **Body-gate standalone rendered file convention established** (per `memory/feedback_body_gate_rendered_extract.md`) — CoS proactively extracts each rewritten §4.N body to `temp/prd-rewrite-pr5-section4-N-rendered.md` and opens in One Markdown for F/CTO body-gate review. Established at body-gate-3 (F/CTO surfaced same need that appeared at PR 4 / §3); applied proactively at body-gates 4 / 5 / 6; retroactively extracted §4.1 + §4.2 at integration.
- **F/CTO γ-override at structure gate is presentation-only when matched by upstream rewrite** — Q-S5 γ override on first-person voice conversion was treated as presentation-only because §2.4.1 (the source-of-citation) had already been converted to product-voice at PR 3; γ on §4.2 maintains citation consistency, not substance amendment.

**Engagement notes**

- **Sec workhorse** across 7 stages (structure proposal + 6 body-gate deliverables). First Sec primary-author PR since PR 1 kickoff.
- **PM untouched** (PM not consulted for §4 body content per ADR-008 Decision 5 Sec-primary-author pattern; PM resumes at PR 6 / §5).
- **Architect untouched** (no architecture surface in PR 5; PR 5 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 12 ratify gates with F/CTO via AskUserQuestion (6 structure-gate Qs + 6 body-gate Qs, all one-question-at-a-time) + integration pass (PRD.md §4 swap + WORKFLOW.md `PRD.md:820` retarget + this v1.23 entry).
- **Sec agentId-based SendMessage continuation succeeded** across all 7 stages on the same agentId.

**Next thread:** **PR 6 — §5 (V2 deferred candidates) rewrite.** Bulk-closeout cadence per Q3 = γ (mirrors PR 2 / §1 + PR 4 / §3); §5 has 7 sub-sections (§5.1–§5.7) but is a low-density V2-trajectory inventory (not a high-density per-sub-§ lock content like §2 or §4). PM resumes as primary author. PR 6 inherits PR 5's ratification patterns (sub-section-gates is not the default for low-density sections).

---

### v1.22 — 2026-05-19

**PR #[TBD] — Phase 1 Step 3.5 PR 4 / §3 (Success metrics) rewrite.** Second bulk-closeout PR under Step 3.5 cadence (mirrors PR 2 / §1). First PR to inherit the **default-to-source-shape = §2 rewritten shape on `main`** correction (logged as feedback memory at structure-gate ratify — see "Pattern correction" below).

**Section rewritten**

- **§3** (Success metrics) — 5 sub-sections preserved (§3.1 / §3.2 / §3.3 / §3.4 / §3.5) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §3 (lines 639–718, 80 source lines including 20 blockquote lines).
- Rewritten: `PRD.md` §3 (~95–115 lines; net line growth from bullet-extraction despite ~5% word-count compression).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ (low-risk small section; 5 sub-sections / 80 source lines). Two F/CTO ratify gates only: structure + body.
- **Zero sub-section gates, zero per-bullet gates.** Matches PR 2 cadence.

**Structure-gate decisions (Q-S1 / Q-S2 / Q-S3)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — aggressive bullet-extraction across §3.2 (Binary test) + §3.3 (Cells/panels compared + Tolerance class triplets) |
| Q-S2 | **α** — no §3.3.N sub-sub-numbering; §3.3 preserved as one anchor; §2.N reference inside each parity-test lead clause is the navigation hook |
| Q-S3 | **α** — ADR-004 Decision-name strings preserved verbatim at §3.4(b); VP-§3-2 carried to Q7 = γ verify pass |

**PR 4 totals (§3)**

| Metric | §3 |
|---|---|
| Source lines | 80 |
| Rewritten (est) | ~95–115 |
| Word-count compression | ~5% net |
| Line-count delta vs. source | +15 to +35 lines (bullet-extraction expansion; word-count still compressed) |
| Sub-sections preserved | 5 |
| Title rewrites | 0 |
| Blockquote lines | 20 source → 0 rewritten |
| App B entries | 6 routing flags (a)–(f); 5 forward-looking + 1 process-record (resolved-at-§4-lock) |
| App C entries | 0 (§3 has no story-trace surface) |
| First-person cleanups | 0 (source already product-voice) |
| §-prefix normalizations | 0 (source already §-prefixed throughout) |
| Cross-ref retargets (in WORKFLOW.md) | 1 (`PRD.md:689` → `PRD.md §3.4`) |
| In-body §-anchor retargets (§1.N renumber) | ~13 (presentation-pointer-only per Q4 = α; silently applied) |
| ADR re-narration drops | 1 (§3.1 ¶1 ADR-002 §8) |
| Substance amendments | **0** (presentation-only) |
| VP candidates surfaced | 3 (VP-§3-1, VP-§3-2, VP-§3-3 — all Q7 = γ deferred) |
| Ratify gates | 2 (structure + body) |

**Pattern correction: default-to-source-shape = §2 rewritten shape on `main` (not v1.18 source shape)**

- PM's initial PR 4 structure proposal at structure-gate round 1 proposed preserving blockquote shape across §3.1–§3.4. F/CTO surfaced precedent inconsistency: PR 3 §2 dropped 234 source blockquote-lines to 0 in rewritten form; PR 4 inherits the convention.
- Re-proposed structure (round 2) drops all 20 §3 source blockquote-lines; ratify accepted 3-for-3 α at structure gate.
- **Feedback memory logged for PR 5–10:** "default-to-source-shape" now means "default to the most-recently-rewritten section on `main`," not v1.18 source. Future structure proposals (PR 5 onward) pre-empt the constraint.

**§3 lock status: STRICTLY PRESENTATION-ONLY**

- No §3 β override per WORKFLOW.md v1.18 lock; §3 not in §1's still-mutable carve-out.
- **Zero substance amendments. Zero new commitments. Zero dropped commitments.**
- 3 VP candidates surfaced and routed to Q7 = γ post-rewrite verify pass:
  - **VP-§3-1** — §3.1 ¶1 quotation/anchor mismatch (v1.18 §1.1 quote text not verbatim in post-PR 2 §1; anchor retargeted to §1.2 — new home of parity commitment substance — but quote preserved verbatim).
  - **VP-§3-2** — §3.4(b) ADR-004 Decision-name strings preserved verbatim per Q-S3 = α; Q7 = γ re-evaluates whether names are presentation re-narration or load-bearing traceability.
  - **VP-§3-3** — §3.5-vs-§6 boundary clause may need re-examination post-PR 8 §6 rewrite.

**In-body §-anchor retargets (silent, presentation-pointer-only per Q4 = α)**

§3 body had ~13 v1.18-numbered §1.N anchors (§1.1 / §1.2 / §1.3 / §1.4) that retarget to post-PR 2 §1 numbering (§1.2 / §1.3 / §1.4 / §1.5 respectively). Distribution:

- §1.2 archetype → §1.3 archetype (10+ occurrences across §3 framing prelude + §3.2 sub-section title + §3.2 Metric 1–6 lead clauses + §3.2 closing attribute-#4 note).
- §1.1 quotation anchor → §1.2 (1 occurrence at §3.1 ¶1).
- §1.3 ("V1 success means...") → §1.4 (1 occurrence at §3.1 ¶2).
- §1.4 ("what this PRD section is not addressing about the user") → §1.5 ("Deferred user-shape questions") (1 occurrence at §3.1 ¶2).

**Cross-reference retargeting (per Q4 = α)**

| File | Line | Old | New |
|---|---|---|---|
| WORKFLOW.md | (per current sweep) | `` `PRD.md:689` `` | `` `PRD.md §3.4` `` |

- **1 retarget** in WORKFLOW.md; 0 in DECISIONS.md (DECISIONS.md `§3` refs already in section-anchor form).
- Retargets are presentation-pointer-only per `docs/archive/README.md` Q4 = α carve-out.

**Acceptance-flags relocation (per Q1 = β)**

- §3 body has **no `#### Acceptance flags` block** in rewritten form.
- §3 body has **no `#### Open routing flags affecting §3` block** — replaced by italic Appendix B marker at §3 foot.
- §3 lock metadata preserved across: WORKFLOW.md v1.18 changelog (§3 at-lock recap) + this v1.22 entry.
- 6 App B entries (5 forward-looking + 1 process-record) carried forward in PR 4 body deliverable for PR 10 consolidation.

**F/CTO ratification: 4-for-4 acceptance across structure + body gates** (zero substance amendments, all "α — accept as drafted"):

1. Structure gate Q-S1 (bullet-extraction depth) = α
2. Structure gate Q-S2 (no §3.3.N sub-sub-numbering) = α
3. Structure gate Q-S3 (preserve ADR-004 Decision names verbatim) = α
4. Body gate Q-B1 = α — accept body as drafted

**Engagement notes**

- **PM workhorse** across 3 stages (initial structure proposal + revised structure proposal post-blockquote-correction + body deliverable).
- **Sec untouched** (no Sec surface in §3 — §3 has no credential-handling surface; Sec is §4 primary author at PR 5).
- **Architect untouched** (no architecture surface in §3; PR 4 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 4 ratify gates with F/CTO via AskUserQuestion + integration pass (PRD.md §3 swap + WORKFLOW.md `PRD.md:689` retarget + this v1.22 entry).

**Feedback memory landed mid-PR**

- **Default-to-source-shape = §2 rewritten shape on `main`** (logged 2026-05-19 at structure-gate revise round).

**Next thread:** **PR 5 — §4 (Security and compliance posture) rewrite.** Second sub-section-gates PR under Q3 = γ (mirrors PR 3 cadence; §4 has 6 sub-sections: §4.1 / §4.2 / §4.3 / §4.4 / §4.5 / §4.6). First PR where Sec re-engages as primary author per ADR-008 framing. PR 5 cadence: structure gate (likely 6+ sub-Qs) + 6 body gates (1 per §4.N). PR 5 inherits the default-to-source-shape correction landed at PR 4.

---

### v1.21 — 2026-05-18

**PR #[TBD] — Phase 1 Step 3.5 PR 3 / §2 (V1 user stories) rewrite.** Largest single PR in the rewrite sequence. First sub-section-gates PR under Q3 = γ. First exercise of Appendix C (Story Trace Index extraction); created in PR 3 with 32 per-story trace entries across §2.1–§2.6. Completes §2.x archetype rename (32 instances via opener-prelude-removal per Q-S4 = β + Option-2 capability-statement-extraction).

**Section rewritten**

- **§2** (V1 user stories) — 6 sub-sections preserved (§2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6) per Q2 = β source-order parity.
- Source: `docs/archive/PRD-v1.18-source.md` §2 (569 lines across §2.1–§2.6).
- Rewritten: `PRD.md` §2 (~439 lines body; ~23% overall compression).

**Pattern divergence declaration**

- **Sub-section-gates** per Q3 = γ. 1 structure gate (6 sub-Qs Q-S1–Q-S6) + 6 body gates (1 per §2.N) = 7 ratify gates + 1 structure-followup Q-B2 = 8 ratify touchpoints.
- **Zero bulk-closeout, zero per-bullet gates.** Body-gates 1–6 each ratified at α (PR 3 6-for-6 acceptance).

**Structure-gate decisions (Q-S1 through Q-S6 + Q-B2)**

| Q | Locked answer |
|---|---|
| Q-S1 | **α** — one body gate per §2.N (6 body gates) |
| Q-S2 | **α** — Appendix C in PRD.md |
| Q-S3 | **γ** — hybrid format (bold-prefix story ID + blockquote trace content) |
| Q-S4 | **β presentation-only** — opener-prelude removed; capability-statement-extraction (Option-2) preserved capability content |
| Q-S5 | **α** — structure accepted |
| Q-S6 | **(ii)** — routing-flag blocks extract to App B at PR 3 with bridge marker |
| Q-B2 | **β** — one-line §2-top framing line re-anchoring archetype (closes VP-5) |

**PR 3 totals across §2.1–§2.6**

| §2.N | Source lines | Rewritten | Compression | App C entries | App B entries |
|---|---|---|---|---|---|
| §2.1 | 53 | ~35 | 34% | 7 | 5 |
| §2.2 | 37 | ~22 | 40% | 4 | 7 |
| §2.3 | 49 | ~32 | 35% | 5 | 11 |
| §2.4 | 68 | ~50 | 26% | 5 | 12 |
| §2.5 | 164 | ~145 | 12% | 5 | 17 |
| §2.6 | 198 | ~155 | 22% | 6 | 21 |
| **Total** | **569** | **~439** | **~23%** | **32** | **73** |

**Archetype rename completion (per Q-2 = α bounded reading from PR 2)**

- 32 source instances of "self-directed multi-account owner" renamed across §2.1–§2.6 via opener-prelude-removal pattern (Q-S4 = β).
- **Zero "Independent Investor" occurrences in §2 body** — Q-B2 = β resolution at body-gate-1 added one-line §2-top framing line carrying archetype reference.
- Per VP-1 closure at body-gate-4: 16 silent `§`-prefix normalizations applied (5 at §2.4 + 5 at §2.5 + 6 at §2.6).

**§2 lock status: STRICTLY PRESENTATION-ONLY**

- No §2 β override per WORKFLOW.md v1.18 lock; substance candidates routed to Q7 = γ post-rewrite verify pass.
- **Zero substance amendments. Zero new commitments. Zero dropped commitments.**

**Patterns established during PR 3 (for PR 4–10 inheritance)**

- **Shape-A / Shape-B / Shape-C per-story shape categorization** — apply per-story shape pattern based on inspected source structure, not broad-stroke sub-section categorization.
- **Voice-cleanup of first-person references in preserved shape-B sub-blocks** — "I/me/my" → "the user / the user's" + product-voice; attested as presentation-only.
- **`§`-prefix normalization at first encounter** — VP-1 closure at body-gate-4.
- **"Mine/my → the user's" supporting-story title rewrite** — 6 consecutive instances across §2.1.7 / §2.2.4 / §2.3.5 / §2.4.5 / §2.5.5 / §2.6.6.
- **Shape-B-Supporting story shape** — §2.6.6 first instance (Supporting story with sub-blocks when elevating new Sec axes).
- **Inline structures preserved in story bodies** — markdown tables (§2.5.2 + §2.6.1); inline `(1)(2)(3)` numbered-step paragraphs (§2.5.3); fenced code blocks (§2.5.4); ordered lists (§2.6.1).
- **Cross-reference no-new-flag entries in App B** — §2.3-(j) CPI-U precedent; preserves Phase 3 traceability without duplication.
- **Process-records vs. forward-looking-flags in App B** — App B contains both entry types (12 process records across §2.5 + §2.6); PR 10 consolidation strategy will distinguish.

**Substance-flag candidates (VP-set, 14 total)**

- **Closed during body gates (6):** VP-1 (§-prefix normalization, body-gate-4); VP-3 (σ-1/σ-2/σ-3 framing preserved as shape-B sub-block, body-gate-6); VP-4 (V1/V2 boundary block confirmed standard shape-B structure, body-gate-6); VP-5 (zero-archetype-name-in-§2-body resolved via Q-B2 = β framing line, body-gate-1); VP-13 (markdown-table precedent confirmed at body-gate-6); VP-14 (code-block precedent confirmed at body-gate-6).
- **Verify-pass-deferred (8):** VP-2 + VP-11 (Sec-verdict-vs-story-trace duplication across §2.4 / §2.5 / §2.6); VP-12 (process-records in App B — broader consolidation strategy for PR 10); VP-7 + VP-9 (§3.3 parity-test framework interactions: §2.2.2 Liabilities Cat extension + §2.3.4 PDF-inspection-discovered surface); VP-6 + VP-8 + VP-10 (light trace editorial cleanup).

**Cross-reference retargeting (per Q4 = α)**

- **Zero `PRD.md:NNN` retargets in PR 3.** §2 source was drafted with section-anchor cross-references (§2.1.5, §2.4.4, etc.) rather than line refs. Clean Q4 = α sweep.

**Acceptance-flags relocation (per Q1 = β)**

- All 6 `#### Acceptance flags` blocks removed from §2.1–§2.6 rewritten bodies.
- §2.1–§2.6 lock metadata preserved across WORKFLOW.md v1.10–v1.15 entries + v1.18 §8-lock-time recap + this v1.21 entry.

**F/CTO ratification: 8-for-8 acceptance across structure + body gates** (zero substance amendments, all "α — accept as drafted"):
1. Structure gate Q-S1–Q-S6 (6 sub-questions): 5 PM-recommendation-accepted + 1 PM-override (Q-S4 from α to β with presentation-only followup confirmation)
2. Q-B2 sub-question at body-gate-1: F/CTO β = one-line §2-top framing line (VP-5 closure)
3. Body-gates Q-B1 / Q-B3 / Q-B4 / Q-B5 / Q-B6 / Q-B7: 6-for-6 α — accept as drafted

**Engagement notes**

- **PM workhorse** across 7 stages (structure proposal + 6 body-gate deliverables + PR 3 closure summary).
- **Sec untouched** (no Sec surface ratification in PR 3 — §2 already locked; presentation-only rewrite). Sec re-engages at §4 primary author per the Phase 1 Step 4 closure path.
- **Architect untouched** (no architecture surface in PR 3; PR 3 routing flags carried forward to App B for Phase 3 consumption).
- **CoS bookkeeping** + 8 ratify gates with F/CTO via AskUserQuestion + integration pass per body-gate (6 commits on `phase/1-step-3-5-section-2` branch — including 1 fix-up commit at body-gate-3 for integration error).
- **PM agentId-based SendMessage continuation** succeeded across all 7 stages on the same agentId.

**CoS integration error during body-gate-3 (transparency note)**

- Body-gate-3 (§2.3) integration produced a broken state — CoS's first Edit replaced only through the §2.3.2 heading, leaving orphaned source content; a follow-up Edit failed to find its target. Committed broken state as `9b8f293`; fix-up commit `91793a7` completed the §2.3 body swap. Pattern saved as a lesson: large multi-section Edits with content boundaries need verified before commit; sed-delete-then-Edit-insert pattern (used subsequently at body-gates 4 + 5 + 6) is more reliable than single-Edit replacement on long source blocks. Content unchanged from F/CTO-ratified deliverable; the fix was purely structural.

**Next thread:** **PR 4 — §3 (Success metrics) rewrite.** Low-risk shape-A section (80 source lines, 5 sub-sections); bulk-closeout cadence per Q3 = γ (mirrors PR 2). 2 ratify gates (structure + body). PR 4 cross-reference handling: `PRD.md:689` → `PRD.md §3.4` (1 retarget). PR 5 (§4) is the second sub-section-gates PR.

---

### v1.20 — 2026-05-18

**PR #[TBD] — Phase 1 Step 3.5 PR 2 / §1 (Vision and target user) rewrite. §1 β override EXERCISED.** First body-rewrite PR under Step 3.5 cadence; establishes patterns PR 3–9 inherit; landed 4 substance amendments per WORKFLOW.md v1.19 R6 carve-out (§1 still-mutable scope).

**Section rewritten**

- **§1** (Vision and target user) — **now 5 sub-sections** (was 4): §1.1 Problem statement / §1.2 Vision / §1.3 Target-user archetype / §1.4 Why an archetype, not the F/CTO by name / §1.5 Deferred user-shape questions.
- Source: `docs/archive/PRD-v1.18-source.md` §1 (lines 17–58, ~47 lines, 4 sub-sections).
- Rewritten: `PRD.md` §1 (~75 lines including NEW §1.1 + presentation reshape; line delta reflects content addition + bullet expansion).

**Pattern divergence declaration**

- **Bulk-closeout** per Q3 = γ (low-risk small section; in §1 / §3 / §5 / §6 / §7 / §8 bulk-closeout-permissible scope). Two F/CTO ratify gates: structure (Q1=α, round 1) + body re-round (Q-3=α, round 2 absorbing 4 substance amendments).
- Zero sub-section gates, zero per-bullet gates.

**§1 β override status: EXERCISED**

Four substance amendments landed (full enumeration in PR 2 body Part 8):

- **Amendment A** — NEW §1.1 Problem Statement sub-section. F/CTO direction with PM redraft. PM shifted three of F/CTO's source-paraphrase wordings: (i) "tax compliance" → "estimated-tax obligations" to avoid §6.3 advisor/fiduciary axis brush, (ii) "calculating cash flows" → "manual mechanics of compiling their financial picture" to cover stock concepts at §2.1 (NAV) + §2.2 (allocation), (iii) "suite of tools and dashboards" → singular "streamlined personal financial observatory" to avoid scope overstatement vs. V1's single Finance Report deliverable. F/CTO ratified γ at Q-1: PM shifts kept; closing foreshadowing paragraph removed; "Independent Investor" bolded in opening framing paragraph.
- **Amendment B** — Renumbering §1.1 → §1.2 / §1.2 → §1.3 / §1.3 → §1.4 / §1.4 → §1.5 (cascade from Amendment A).
- **Amendment C** — Archetype rename "self-directed multi-account owner" → "Independent Investor" (deliberately NOT "Independent accredited investor" — F/CTO ratified non-legal framing to avoid SEC Reg D Rule 501 legal-threshold inheritance). Sweep scope per Q-2 = α (bounded): PR 2 = §1 only (2 instances); §2.x rename (32 story-opener instances) defers to PR 3 as part of opener-compression pattern.
- **Amendment D** — Cross-reference retargets per renumbering (cascade from Amendment B): 3 line-anchored refs in WORKFLOW.md updated to section-anchor form.

**No ADR amendment.** DECISIONS.md has zero occurrences of the renamed archetype term (ADRs use "the V1 instance" / "the F/CTO" / "the user"); Amendment C is therefore a PRD-internal substance amendment that does NOT require an ADR-009 entry. Section-β-override path is currently §1-only per WORKFLOW.md v1.19 R6 carve-out; PR 3–10 remain strictly presentation-only.

**Cross-reference retargeting (per Q4 = α)**

| File | Pattern | Old | New |
|---|---|---|---|
| WORKFLOW.md | §8.3 forward-pointer closure | `` `PRD.md:47` `` | `` `PRD.md §1.4` `` |
| WORKFLOW.md | §8 forward-pointer closures list | `` `PRD.md:47` `` | `` `PRD.md §1.4` `` |
| WORKFLOW.md | §1.4 line-58 surgical edit reference | `` `PRD.md:58` `` | `` `PRD.md §1.5` `` |

3 retargets in WORKFLOW.md; 0 in DECISIONS.md (DECISIONS.md `§1.X` refs are to ADR-002 internal numbering, not PRD §1.x).

**Archetype-name rename-sweep scope (per Q-2 = α bounded reading)**

| Surface | Occurrences | Scope |
|---|---|---|
| `PRD.md` §1 | 2 | **IN — PR 2 (this PR)** |
| `PRD.md` §2.x story openers | 32 | IN at PR 3 (integrated into opener-compression) |
| `DECISIONS.md` | 0 | N/A — zero occurrences |
| `WORKFLOW.md` (line 383, v1.9-era changelog) | 1 | OUT — historical changelog; immutability convention |
| `docs/v1-parity-matrix.md` | 1 | OUT — historical artifact |
| `docs/prd-rewrite-proposal-v1.md` + `docs/prd-rewrite-pr2-proposal.md` + `docs/prd-rewrite-pr2-body-preview.md` | 6 total | OUT — historical artifacts |
| `docs/archive/PRD-v1.18-source.md` | 34 | OUT — frozen archive by construction |

Forward convention from v1.20 onward: new artifact text uses "Independent Investor."

**In-body marker conventions established (for PR 3–9)**

- **Appendix B marker** (when Appendix B does not yet exist): `*Routing flags affecting §N: see Appendix B (created in PR 10; pending consolidation).*` §1 has zero routing flags so convention is declared but first exercised at PR 3.
- **Appendix C marker** (first exercised PR 3): `*Traces: see Appendix C → N.M.K.*`
- **ADR citation convention:** drop ADR re-narration in PRD body; keep ID-level pointer inline as `(ADR-NNN [Decision X])` or `(ADR-NNN §M.N)`.

**Acceptance-flags relocation (per Q1 = β)**

- §1 body has **no `#### Acceptance flags` block** in rewritten form.
- §1 lock metadata preserved across: WORKFLOW.md v1.6 (§1.2-source attribute #5 strengthening), v1.15 (§1.4-source line-58 surgical edit), v1.20 (this entry — §1 rewrite + 4 substance amendments).
- Pattern: no Acceptance-flags block in any rewritten PRD body. PR 3–9 inherit.

**Structural-fidelity attestation summary**

- §1.1 (NET-NEW substance) — attested consistent with locked §1.2–§1.5 commitments; no ADR-002 §3.0 product-identity non-goal contradiction; no ADR-007 information-vs-prescription axis crossing.
- §1.2 (was §1.1) — preserved verbatim from PR 2 round 1; no rename touchpoint.
- §1.3 (was §1.2) — preserved + 1 rename instance in framing sentence; all 7 attribute bullets verbatim; "Independent Investor" replaces "*self-directed multi-account owner*" (bold replaces italic to reflect proper-noun shape).
- §1.4 (was §1.3) — preserved + 1 rename instance in numbered-point #2.
- §1.5 (was §1.4) — preserved verbatim; zero rename touchpoints.
- Zero dropped commitments across all 5 sub-sections.

**F/CTO ratification: 4-for-4 acceptance across 2 rounds**, with Q1 PM-recommendation accepted at round 1 + 3 explicit revision-or-accept calls at round 2:

1. Round 1 Q1 structure = α (sub-section preservation + bullet plan + in-body marker conventions + Q1=α-locked §1.4/§1.5 title rewrites; PM-recommendation accepted).
2. Round 2 Q-1 = γ (per-clause revisions on §1.1: PM shifts #1/#2/#3 kept; closing paragraph removed; "Independent Investor" bolded in opening — F/CTO editorial direction).
3. Round 2 Q-2 = α (rename-sweep bounded reading: PR 2 = §1 only; §2.x defers to PR 3 — PM-recommendation accepted).
4. Round 2 Q-3 = α (full body re-round acceptance — PM-recommendation accepted).

**Engagement notes — PR 2 across two rounds**

- PM workhorse: round 1 target-shape proposal + structure gate + initial body draft; round 2 substance-amendment redraft + repo-wide rename-sweep occurrence scan + cross-ref-cascade + updated attestations + v1.20 changelog draft.
- Sec untouched (no Sec surface in §1).
- Architect untouched (no architecture surface in §1).
- CoS bookkeeping + ratify-gate sequencing across 2 rounds + integration pass (PRD.md §1 swap + WORKFLOW.md 3-line retarget + WORKFLOW.md header + this v1.20 entry).
- **PM agentId-based SendMessage continuation succeeded** for round-1-to-round-2 transition; pattern fully reliable for mid-task PM re-engagement.

**Pattern implications for PR 3–10**

- **Substance amendments are demonstrated as exercisable mid-rewrite via section-β-override path.** Currently scoped to §1 only per WORKFLOW.md v1.19 R6 carve-out; PR 3–10 remain strictly presentation-only per Step 3.5 constraint.
- **Rename-sweep precedent established:** repo-wide grep + per-surface scope decisions (PRD body = in; ADRs = N/A here, would be case-by-case if non-zero; historical changelog / artifacts = out; forward convention from new version onward). Applies forward if any future term-evolution amendment lands.
- **Bulk-closeout pattern absorbed substance amendments cleanly** under §1's low-risk surface AND across a round-1 → round-2 re-iteration. PR 3 + 4 (§2 + §4 sub-section gates) test whether sub-section-gates cadence carries similar flexibility.
- **CoS-inline editorial revision pattern** — F/CTO's `§1.1 close-paragraph removal + bolding` revision applied directly by CoS without round-3 PM re-run (presentation-only edit on PM round-2 draft). Available for future PRs where F/CTO surfaces small editorial revisions that don't warrant a PM round-trip.

**Working artifacts (transient; remove or archive at Step 3.5 closure):**

- `docs/prd-rewrite-pr2-proposal.md` — PM round-1 target-shape proposal (round-2 deliverable preserved in PM task notification; round-2 wasn't saved as a separate artifact since the body preview and v1.20 changelog capture the relevant content).
- `docs/prd-rewrite-pr2-body-preview.md` — Standalone §1 body preview used for F/CTO body-gate review (incorporates Q-1=γ revisions).

**Next thread:** **PR 3 — §2 (V1 user stories) rewrite.** First sub-section-gates PR under Q3 = γ — §2 is high-risk (largest section, 6 sub-sections, ~580 lines). Cadence: structure gate + 6 sub-section body gates (one per §2.1 / §2.2 / §2.3 / §2.4 / §2.5 / §2.6). First exercise of Appendix C Story Trace Index extraction pattern. First exercise of Appendix B in-body marker convention (§2.x sub-sections all have routing flags). PR 3 also completes the §2.x archetype-rename (32 story-opener instances) integrated into the opener-compression pattern.

---

### v1.19 — 2026-05-18

**PR #26 — Phase 1 Step 3.5 declared and kicked off.** Editorial rewrite of `PRD.md` for scannability without altering locked substance. (Changelog entry deliberately modeled in the target scannable shape the rewrite is producing — bullets, tables, sub-headers; compare to v1.18 wall-of-prose to see the pattern shift.)

**Why Step 3.5 exists**

- F/CTO surfaced **late-phase rubber-stamp risk** post-§8 lock: by end of Phase 1 Step 3, F/CTO was accepting recommendations without engaging nuance because `PRD.md` (~37k tokens, 1,090 lines) had become too dense to read substantively.
- Step 3's "44-for-44 teammate-lean track" (per v1.18 changelog) reflects acceptance, not necessarily considered ratification. Highest-risk surfaces: §6 / §7 / §8 framing; parts of §4 posture.
- Memory captured: `~/.claude/projects/-Users-mosko-Projects-mosko-fintech/memory/feedback_late_phase_density_overload.md` — pace ratify gates smaller on dense late-phase work; treat N-for-N teammate-lean tracks as metric-to-watch not virtue-signal; editorial restructure passes are legitimate Phase sub-steps.

**Step 3.5 plan — presentation-only restructure with locked substance preserved**

- Source `PRD.md` archived at `docs/archive/PRD-v1.18-source.md` (frozen this PR).
- `docs/archive/README.md` documents historical line-ref resolution and the Q4 = α retargeting carve-out.
- Working artifact: `docs/prd-rewrite-proposal-v1.md` carries full PM target-shape proposal + R1–R8 risks/mitigations + §9 substance-flag detail. Will be archived or removed at Step 3.5 closure.

**Plan ratified 7-for-7 at per-question engagement (no bulk-closeout — explicit pattern divergence from Step 3):**

| Q | Topic | Locked answer |
|---|---|---|
| Q1 | Appendix scope | **β** — Appendix B (routing flags consolidated) + Appendix C (Story Trace Index for §2.x); per-section Acceptance flags content relocates entirely to WORKFLOW.md changelog |
| Q2 | Section order | **β** — Source order (§1 → §2 → §3 → §4 → §5 → §6 → §7 → §8 → overview/appendices) |
| Q3 | Gate pattern | **γ** — Hybrid: bulk-closeout for §1/§3/§5/§6/§7/§8; sub-section gates for §4 + §2 |
| Q4 | Cross-refs | **α** — Retarget `PRD.md:NNN` → `PRD.md §N.M.K` at rewrite time (each rewrite PR sweeps WORKFLOW.md + DECISIONS.md) |
| Q5 | (Process record shape) | Auto-skipped under Q1 = β |
| Q6 | Archive PR | **α** — Standalone kickoff PR (this PR) |
| Q7 | Substance flags | **γ** — Defer all 7 PM-flagged rubber-stamp candidates to dedicated post-rewrite verify pass before Step 4 entry |

**PM-recommendation track: 5-for-7.** Two deliberate F/CTO overrides:

- **Q2** — Source order over PM's smallest-first. F/CTO weighted predictability over PM's pattern-discovery sequencing.
- **Q4** — Retarget at rewrite over PM's accept-as-historical. F/CTO read the DECISIONS.md immutability convention as applying to ADR substance, not pointer form; per-PR retargeting is treated as presentation-pointer-only.

**7 substance flags deferred to post-rewrite verify pass** (full reasoning: `docs/prd-rewrite-proposal-v1.md` §9). Verify pass walks each flag sub-section-by-sub-section before Phase 1 Step 4 opens; any substance issue lands as ADR amendment:

1. **§4.2** credential-error states (c)/(d) — observational distinguishability at V1 user-facing surface
2. **§4.3** RT-13 staleness severity (high, not critical) — does it account for §2.6.5 account-name exposure dimension?
3. **§4.6** incident-handling V2-trajectory ramp vs. audit-log V1 commitment (potential clause-level tension)
4. **§6.3** TLH information-vs-prescription axis — elevate from TLH-clause-tail to explicit axis-level commitment?
5. **§7.2** single-tenant scale dimensions — V1 RLS verification scope (single-user-only vs. V2-cohort scale)
6. **§8.1** V1.0/V1.1 "illustrative-not-normative" — is this implicitly relaxing ADR-004's actual commitment?
7. **§8.2** drop-replace transition vs. §4.6 cutover commitment (could conflict)

**PR sequence — 11 PRs:**

- **PR 1 (this PR)** — kickoff: archive source + README + WORKFLOW.md v1.19 header + this changelog
- **PR 2–9** — §1 → §2 → §3 → §4 → §5 → §6 → §7 → §8 rewrites (source order per Q2)
- **PR 10** — document overview + reading guide + section index + Appendix B (routing flags consolidated)
- After PR 10 ships: **post-rewrite verify pass** (7 substance flags above)
- After verify pass: **Phase 1 Step 3.5 closes; Phase 1 Step 4** (Architectural overview consult; Architect lead; Phase 3 entry gate) **opens**

**Pattern divergence vs. Step 3** (deliberate; enforced by Q3 = γ):

- Per-PR ratify cadence is structure gate + per-sub-section body gates for §4 + §2 (high-risk).
- Bulk-closeout permissible only on low-risk small sections (§1/§3/§5/§6/§7/§8).
- Each rewrite PR includes a structural-fidelity attestation (per R1 mitigation in `docs/prd-rewrite-proposal-v1.md`).
- Each rewrite PR explicitly declares its gate pattern in the PR body ("this PR uses [bulk-closeout | sub-section gates]; rationale: …") — pattern-divergence-check is a first-class PR convention to prevent silent relapse to bulk-closeout.

**Engagement notes — Step 3.5 kickoff session:**

- **CoS-led** ratify gate sequencing (one-question-at-a-time per memory `feedback_one_question_at_a_time.md`).
- **PM workhorse** on the target-shape proposal (single bulk deliverable per task brief, returned as scannable structured markdown for F/CTO walkthrough); PM continues as primary author for PR 2–9 section rewrites.
- **Sec / Architect untouched** at kickoff (presentation-only rewrite; no posture or scope decisions); they re-engage at the post-rewrite verify pass (if flags raise substance) and at Phase 1 Step 4 (Architect overview consult against the polished + verified PRD).
- **No new ADRs at Step 3.5 kickoff.** Step 3.5 may produce an ADR if the post-rewrite verify pass surfaces a substance change; presentation-only restructure does not produce ADRs by construction.

**Next thread:** **PR 2 — §1 (Vision and target user) rewrite.** PM-led; first body rewrite under the new Step 3.5 cadence. Establishes the rewrite *pattern* — how to compress paragraph-bullets; how to handle routing-flag pointers to Appendix B which doesn't exist yet at PR 2 (in-body marker should bridge with "Routing flags affecting §1: see Appendix B (created in PR 10; pending consolidation)"); how to express the lock-status-block-relocated-to-WORKFLOW.md convention.

---

### v1.18 — 2026-05-18

**PRD §8 LOCKED** (2026-05-18) — sixth and smallest non-§2 PRD section locked; **last PM-led drafting task in Phase 1 Step 3**; closes PRD substantive content surface for Phase 1 Step 3. §8 (V1 milestone framing) drafted from no-stub to a 3-sub-section content section across PM tasks (structure proposal + bulk-closeout body draft) and the integration pass (PRD.md + this WORKFLOW.md entry). Smallest PRD section by content surface to date (3 framing paragraphs + 10 bullets + 5 boundary-note routing flags; matches §7's 3 sub-section count but smaller by routing-flag-mix and per-section bullet density). Post-§8 lock, **Phase 1 Step 4 (Architectural overview consult)** opens — Architect lead, Phase 3 entry gate.

**Structure: 3 sub-sections — §8.1 V1 sub-version convention / §8.2 Drop-replace migration pattern / §8.3 V1-done cross-reference + Phase 4 handoff.** Convention / mechanic / cross-reference grouping; matches §7's smallest-section shape (3 sub-sections); closes §3.4 + §1.3 forward-pointers cleanly at §8.3. **Format: bulleted enumeration + short framing paragraph per sub-section** (mirrors §5 / §6 / §7 / §4.6 inventory-section default; quintuple-confirms the bulleted-with-framing shape across §3 → §5 → §6 → §7 → §8).

**§8 framing paragraph** establishes milestone-sequencing-not-single-event framing per ADR-004 (the expanded post-ADR-004 V1 scope made single-event ship impractical); cites §3.4 ↔ §8 boundary (§3.4 owns V1-done criteria, §8 owns milestone-framing scaffolding); notes §8 as last PM-led Phase 1 Step 3 PRD section.

**§8.1** (1 framing paragraph + 4 bullets) — V1.0 → V1.x → V1.final naming convention + lifecycle framework. V1.0 = first shippable backend (data-plane foothold for drop-replace); V1.x = intermediate sub-versions; V1.final = sub-version at which all §3.4 criteria pass; "shippable in framing terms" anchored at §3.3 parity-testability + §4.1 RLS-enforced multi-tenant infrastructure + §4 V1 Sec posture commitments. Illustrative ADR-004 examples (V1.0 = Plaid + manual balances; V1.1 = full manual transaction entry) preserved as **illustrative-not-normative** — specific per-version capability boundaries are Phase 4 / Linear-backlog territory.

**§8.2** (1 framing paragraph + 3 bullets) — Drop-replace migration pattern as user-continuity guarantee during V1 data-plane transition. V1.x backend as data source for residual Google Sheets views during transition per ADR-004 verbatim (data-plane shifts underneath; presentation-plane migration is incremental as V1-native surfaces supersede residuals); §4.6 shadow-workflow tear-down cross-reference (drop-replace makes §4.6 tear-down user-survivable; §4.6 tear-down is what makes drop-replace terminate cleanly at §3.4(c) retirement); §4.6 availability + §2.4.4 non-silent-staleness cross-reference (stale-data surfacing applies symmetrically across residual Google Sheets views + V1-native surfaces during transition).

**§8.3** (1 framing paragraph + 3 bullets) — V1-done cross-reference to §3.4 + §1.3 forward-pointer closure + §8 → Phase 4 handoff boundary. Reciprocates §3.4's three migration-completion criteria + N=2-months commitment without re-litigating (§3.4 owns criteria definition; §8 owns milestone-framing scaffolding). Closes §1.3 V1-correctness forward-pointer (`PRD.md §1.4`) by anchoring V1-done at §3.4. Establishes §8 → Phase 4 (Scoping) / Linear-backlog handoff: Phase 4 owns criterion-to-sub-version mapping + per-sub-version capability boundaries + dependency ordering across §2 / §4 / §7 surfaces + one-session-granularity Linear acceptance criteria. **§8 does not pre-commit milestone-sequencing decisions** — the milestone-framing scaffolding is intentionally separated from the milestone-sequencing decisions to keep Phase 1 (PRD) and Phase 4 (Scoping) territorially clean.

**Routing-flags block: 5 boundary notes (a)–(e); zero Architect flags; zero Sec flags; zero V1-block flags either side.** Smallest routing-flags block of any locked PRD section to date by content type (pure boundary-note). Boundary notes: (a) §3.4 → §8 forward-pointer closure at §8.3; (b) §1.3 → §8 forward-pointer closure at §8.3; (c) ADR-002 §7.0 gap #4 milestone-framing dimension closure at §8.3 (the criteria dimension closed at §3.4 at §3 lock); (d) §8 → Phase 4 / Linear backlog handoff anchor; (e) §8 ↔ §4.6 cross-reference shape (one-way at §8 lock; §4.6 already commits to the posture, §8.2 names the transition mechanic that consumes it). Closure-documentation pattern for ADR-002 §7.0 gap #4 follows §4.6's closure-doc convention from §4 lock; Appendix A absorption deferred per §4 routing flag (o) housekeeping convention.

**No new ADR for §8 lock** per gate-1 forecast confirmed. All §8 content is verbatim-derivable from ADR-004 (`DECISIONS.md:353`); sub-version convention + drop-replace mechanic + §3.4 V1-done cross-reference are explicit ADR-004 commitments. §8 is the PRD-side surfacing of ADR-004's milestone framing, not a new scope decision. **Fourth instance** of the "no-new-ADR lock" pattern (joins §3 / §6 / §7). **No cross-section surgical edits** — §3.4 closing line and §1.3 V1-correctness line are already correctly forward-shaped; §8.3's reciprocation closes both forward-pointers without requiring upstream body edits; §4.6 cross-references at §8.2 are one-way (no §4.6 body revision required).

**No Sec at-lock pass for §8** — no credential-handling surface, no auth-flow surface, no new Sec posture by construction; §8.2's cross-references to §4.6 are reciprocations of already-locked §4.6 posture commitments, not new Sec surface. **No Architect at-lock pass for §8** — §8 is framing-shaped, no V1 architecture surface; specific milestone-sequencing decisions are Phase 4 / Linear territory by explicit §8 → Phase 4 handoff at routing flag (d).

**F/CTO ratification: 2-for-2 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides:
1. **Q1 structure** = 3 sub-sections (PM-lean over flat-single-section and 2-sub-section-collapse alternatives);
2. **Q2 format** = bulleted enumeration + short framing paragraph per sub-section (PM-lean over pure-prose alternative);
3. **Body-bundle as-drafted** accepted at section-level review; zero overrides on content or per-bullet professional-judgment calls (V1.0/V1.1 illustrative-not-normative framing; §8 → Phase 4 handoff boundary at (d); ADR-002 §7.0 gap #4 milestone-framing-dimension closure at (c)).

**PM-lean track now 23-for-23 across §3 + §5 + §6 + §7 + §8** (PM-led sections). Combined with Sec-lean 21-for-21 from §4: **44-for-44 teammate-lean record** across all locked Phase 1 Step 3 PRD sections (5 PM-led + 1 Sec-led), zero F/CTO overrides on PM- or Sec-led recommendations across the entire Phase 1 Step 3 lock work. **Fifth confirmed instance of bulk-closeout-from-structure-proposal pattern** (§3 → §5 → §6 → §7 → §8); pattern is stably the default for PM-led PRD inventory + framing sections of any scope.

**Forward-pointer closures at §8 lock:** §3.4 → §8 (`PRD.md §3.4`); §1.3 → §8 (`PRD.md §1.4`); ADR-002 §7.0 gap #4 milestone-framing dimension. Three forward-pointer closures + §8 → Phase 4 handoff anchor established at routing flag (d).

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — Q1/Q2 + cross-section reference scan + ADR forecast + cross-section surgical-edit forecast + pattern-divergence check; bulk-closeout body draft — opening framing + 3 sub-section bodies + 5 boundary-note routing flags + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 Sec posture; §4.6 cross-references at §8.2 are reciprocations of locked content). Architect untouched (no V1 architecture surface; §8 → Phase 4 handoff makes milestone-sequencing decisions Linear-backlog territory). CoS bookkeeping + 3 ratify gates with F/CTO via AskUserQuestion (Q1 standalone → Q2 standalone → body-bundle section-level acceptance). **PM agentId-based SendMessage continuation succeeded for the sixth confirmed time** (after v1.13 §3, v1.14 §5, v1.15 §6, v1.16 §7 structure + body, this session's §7 + §8); pattern is fully reliable for recently-completed PM agents across multiple session-spanning instances.

**Patterns extended this session** for forward sections: (a) **Quintuple-confirmed bulk-closeout-from-structure-proposal pattern** — now the durable default for PM-led PRD sections of any scope (§8 is smallest, §5 was largest; pattern fits both). (b) **Fourth instance of "no-new-ADR lock" pattern** (§3 / §6 / §7 / §8) — PM-led sections that close pre-committed forward-pointers without novel scope decisions or substantive ADR amendments do not produce ADRs; pattern is now reliably distinguishable from the ADR-producing locks (§5 → ADR-007; §4 → ADR-008). (c) **Closure-documentation pattern for ADR-002 §7.0 gap-closure** — §8 closes gap #4 milestone-framing dimension at §8.3 + routing flag (c), parallel to §4 closing gaps #4 + #6 + partial-#5 at §4.6 + routing flag (o); both follow the "closure documentation at locking-section's routing-flag-block; Appendix A absorption deferred to future housekeeping PR" convention. Lightweight pattern for downstream sections closing upstream gaps without amending the upstream ADR body. (d) **Section-to-Phase handoff anchor pattern** — §8 → Phase 4 handoff at routing flag (d) explicitly anchors the boundary between PRD-locked framing (Phase 1) and Linear-backlog-owned sequencing (Phase 4); future Phase-to-Phase handoffs at section locks can use the same anchor-as-routing-flag pattern.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **thirteenth real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #23 §7 lock, PR #24 §4 lock + ADR-008, PR #[TBD] §8 lock).

**Next thread:** **Phase 1 Step 4 — Architectural overview consult** (Architect lead). First Architect primary-author engagement in the project (prior Architect engagements were Phase 1 Step 2 ratification of ADR-002 + Phase 1 Step 3 cross-section feasibility consults). Step 4 consumes the accumulated routing-flag payload from §2 + §3 + §4 + §7 (11 §4 routing flags + 4 §3 routing flags + 6 §2.x Architect routing flags + §7.2 scale dimensions + §7.1 cost-shape at-risk flag + §8 → Phase 4 milestone-sequencing handoff) and produces the Phase 3 entry payload (ARCHITECTURE.md scoping decisions, migration design framing, RLS implementation strategy per §4.5 RT-NN catalog, snapshot-store + cron + PDF worker implementation framing, cost reconciliation per ADR-002 §6.0 / `DECISIONS.md:275` at-risk flag). After Phase 1 Step 4 ratifies, **Phase 2** (UX/Visual design) becomes available; Phase 1 closes. Expected: Architect-led structure-proposal-shape consult with PM + Sec joint-consult at relevant touchpoints (Sec joint on RLS implementation strategy; PM joint on any V1 scope ambiguities surfaced during architectural-feasibility review). Team-mode (`phase-1` team) per ADR-003 active throughout; team transitions to a phase-3-or-2 team upon Phase 1 closure (team mode decision deferred to Phase 1 closure thread).

### v1.17 — 2026-05-18

**PRD §4 LOCKED + ADR-008 ACCEPTED** (2026-05-18) — fifth and largest non-§2 PRD section locked; first Sec primary-authored PRD section in Phase 1 Step 3 (prior Sec engagements were six pass-with-comments at-lock verdicts on PM-authored §2 sections). §4 (Security and compliance posture) drafted from a 3-line stub to a six-sub-section content section across Sec tasks (gate 1 structure proposal + gate A §4.4 column shape + gate B §4.5 column shape + stage 2 row drafting + stage 3 posture bulk-closeout + stage 4 ADR-008 confirm + surgical-edit proposals) and the integration pass (PRD.md §4 + PRD.md §7.1 (a) surgical reciprocation + DECISIONS.md ADR-008 + this WORKFLOW.md entry). **Largest single Phase 1 Step 3 task by content size** (24 posture bullets + 14 SD matrix rows × 8 columns + 15 RT catalog entries × 7 columns + 11 active routing flags + 5 boundary notes + ADR-008 production-ready text).

**Structure: 6 sub-sections under Option A axis-grouped + dedicated consolidation pattern** (§4.1 Tenant isolation posture — axes i–iv / §4.2 Credential + external-API posture / §4.3 Derivative-persistence + staleness posture — axes v + vi / §4.4 Sensitive-data classification matrix / §4.5 Phase 3 RLS test catalog / §4.6 Cross-cutting posture commitments). Uses the six canonical Sec axes (earned through six §2.x at-lock passes) as the organizing principle; two dedicated consolidation sub-sections (§4.4 + §4.5) as deliberate forward-payloads for Phase 3 / Phase 6 consumption. **Format: hybrid F-A + F-B** — bulleted-with-framing for posture sub-sections (mirrors §5 / §6 / §7); markdown tables for consolidation sub-sections.

**§4.1** (5 bullets) — four canonical-clause posture commitments per axes i–iv (tenant_id isolation boundary / multi-scope as data attribute not boundary / tax_treatment as inclusion filter not boundary / write-path RLS symmetry) + isolation-at-scale forward-pointer landing per §7 routing flag (e). Sixth-consecutive-instance canonical formulation across §2.1.7 → §2.6.6 consolidated.

**§4.2** (7 bullets) — Plaid OAuth flow integrity + SD-03 credential-class storage + RT-05 webhook signature verification hard-line + four credential-error states + SD-01 credential-adjacent surface + no-third-party-security-master-API V1 posture + spend-cap V2-implementation Sec-consult forward-pointer. **Sec hard-line preserved**: V1 cannot ship with RT-05 webhook signature verification failing or unimplemented.

**§4.3** (6 bullets) — axes v (staleness-live-read cross-tenant signal leak, verified at RT-13) + vi (snapshot store SD-12 as derivative-persistence surface; SD-13 cross-cutting derivative-persistence axis with forward-applicability to V2+ derivative surfaces) + non-silent staleness as V1 user-facing availability commitment + snapshot regeneration race condition (RT-14) preserving staleness-marker coupling + PDF/cron worker tenant isolation (RT-09 + RT-10).

**§4.4** (14 rows × 8 columns sensitive-data classification matrix; 109 populated + 3 `—` annotation cells on SD-13) — Class ID / Class name / Source-§ / Sensitivity tier / Storage protection class / Retention posture / V1-acceptable disclosure surfaces / Phase 3 forward-pointer ID. SD-00 baseline (transactions/holdings/cost-basis) + SD-01 through SD-12 concrete classes + SD-13 cross-cutting derivative-persistence axis annotation (uses `—` cell convention). Three closed-enum columns (sensitivity tier 3-value: credential / high / medium; storage protection class 4-value: credential-class / tenant-scoped-with-app-encryption / tenant-scoped / tenant-scoped-derivative; retention posture 4-value: indefinite / bounded-Item-active-only / bounded-N-day-rolling / indefinite-with-V2-cold-storage-rollover with N = 90 days for SD-02 Plaid Item-state metadata).

**§4.5** (15 rows × 7 columns RLS test catalog; 14 active populated + RT-07 reserved-vacant per stage-2 consolidation rationale) — Test ID / Surface / Test description / Test category / Source-§ / Severity if violated / Related Class IDs. Source-§ traceability ordering: §2.4-elevated RT-01 through RT-05; §2.5-elevated RT-06 (+ RT-07 vacant); §2.6-elevated RT-08 through RT-14; §3-elevated cross-cutting RT-15. **V1-block threshold: `critical` severity only** — 2 critical-severity = V1-ship-blockers (RT-02 Plaid Item table RLS + RT-05 webhook signature verification); 10 high-severity = release-blockers for V1.x patch on regression; 3 medium-severity = V1-final-targeted with known-issue tickets acceptable at ship. Two closed-enum columns (test category 6-value: read-path-RLS / write-path-RLS / worker-context-isolation / input-sanitization / race-condition / test-environment-posture; severity 3-value: critical / high / medium). **Catalog-completion scan at gate B revised the count from 7 to 14** — original §2.6-lock running tally was the §2.6-elevated subset; gate-B scan surfaced 4 §2.4-elevated + 2 §2.5-elevated + 1 §3-elevated cross-cutting tests not folded into the §2.6 tally; webhook signature verification added at Q-Special-Cases-a as critical-severity row (catalog 14 → 15 with RT-07 vacant).

**§4.6** (6 bullets) — data retention class-by-class per §4.4 column (Q3a Option α, closes ADR-002 §7.0 gap #5 jointly with §2.6.4 χ-1) + availability/uptime best-effort no-SLO with §2.4.4 non-silent-staleness as V1 user-facing availability story (Q3b Option α, closes gap #6) + incident-handling V1 incident-log-file at F/CTO level with V2-trajectory ramp per §7.3 invite-only forward-compat (Q3c Option α, closes gap #4) + parity-fixture access-controlled storage + RT-15 test-environment posture (closes §3 (e) + §3 (b)) + shadow-workflow tear-down with read-only archive posture (closes §3 (d)) + V2-ship-gate Sec-consult inventory consolidating 4 items (pre-emptive Plaid re-auth / email-SMS delivery / shared-link delivery / spend-cap V2-implementation).

**Routing-flags block: 11 active flags (a)–(k) + 5 boundary notes (l)–(p)** — 6 pure Architect ((a) RLS implementation across §4.5; (d) encryption-at-rest evaluation; (e) Item-state 90-day prune mechanism; (f) audit-log architecture; (g) cron worker tenant-context binding; (h) PDF worker tenant isolation) + 3 Architect/Sec joint ((c) webhook sig verification; (i) snapshot regeneration race; (j) parity-fixture test-environment plumbing) + 2 Sec-led ((b) Plaid access-token storage shape; (k) V2-ship-gate Sec-consult inventory). Boundary notes document cross-reference closures: (l) §4.4 ↔ §4.5 bidirectional cross-reference validated; (m) §4 ↔ §7 reciprocation closes §7 (e); (n) §4.6 ↔ §2.6.4 χ-1 retention; (o) ADR-002 §7.0 gaps #4 + #6 + partial-#5 closed; (p) §3 (b) + (d) + (e) all close at §4 lock. **Zero V1-block flags beyond the existing Sec hard-line on RT-05** (carried as routing flag (c) with sign-off-before-V1-ship requirement). Largest routing-flags block of any locked PRD section to date (vs §7's 5, §6's 5, §5's 6, §3's 6, §2.6's 12+6).

**ADR-008 — V1 security posture canonical reference (pattern divergence (iii) confirmed; net-new ADR).** First Sec-authored ADR; consolidative-net-new shape (parallel to ADR-002 / ADR-003 / ADR-004 consolidation pattern, distinct from ADR-005 / ADR-006 / ADR-007 surgical-amendment pattern). 5 Decisions: (1) Six canonical Sec axes as V1-authoritative set; (2) Fourteen-entry sensitive-data classification matrix as V1 canonical classification with 3 closed-enum columns; (3) Fifteen-entry RLS test catalog with 2 closed-enum columns and critical-only V1-block threshold; (4) V1 retention / availability / incident-handling posture as baseline closing ADR-002 §7.0 gaps #4 + #6 + partial-#5; (5) Two pattern divergences from PM-led default ratified (hybrid format + two-stage hybrid drafting). **Establishes immutability boundary** for canonical-reference material — six axes / 14 classes / 15 tests / closed-enum values / N = 90 day Item-state retention window / three posture commitments are immutable once accepted; bullet-level posture commitments at PRD §4.1–§4.6 remain mutable through future PRD revisions if canonical references hold steady. **No supersession of any prior ADR**; ADR-002 §1.4 + §1.6 + §1.7 + §3.0 + §6.0 + §7.0 + §8.0 all stand and operationalize at §4 surfaces; ADR-003 / ADR-004 / ADR-005 / ADR-006 / ADR-007 all stand and operationalize at §4 surfaces.

**Three pattern divergences from quadruple-confirmed PM-led bulk-closeout pattern ratified at §4 drafting:**
1. **(i) Hybrid format** — markdown tables for §4.4 + §4.5; bulleted-with-framing for §4.1–§4.3 + §4.6. Tables are grep-able, diffable at V2-expansion, structurally cross-referenceable by ID.
2. **(ii) Two-stage hybrid drafting pattern** — per-table ratify gates for §4.4 + §4.5 column shape + severity rubric (gates A + B before stage-2 row drafting); bulk-closeout for posture sub-sections (stage 3). Matrix column-shape decisions are upstream-of-row-drafting (78/105 cells per table) and warrant explicit ratification.
3. **(iii) ADR-008 net-new** — V1 security posture canonical reference. §4 lands material consumed at Phase 3 / 5 / 6 / 7 implementations + reviews; ADR-grade citability matters in a way it didn't for §6 / §7 (which forward-pointed to existing ADRs).

**F/CTO ratification: 21-for-21 Sec-lean acceptance across four stages**, zero overrides:
- Gate 1 (6-for-6): Q3a retention mixed-α / Q3b availability best-effort-no-SLO-α / Q3c incident-log-V2-ramp-α / Q1 structure Option A / Q4 drafting D-A two-stage hybrid / Q2 format F-A+F-B hybrid.
- Gate A (5-for-5): Q-Col1 Col-A 8-column / Q-Class-ID 14-entries-with-SD-00-baseline-α / Q-Tier 3-tier credential-high-medium / Q-Storage 4-value enum / Q-Retention-N N=90-days.
- Gate B (6-for-6): Q-Catalog-Count 14-entries-full-V1-catalog (revising the §2.6-tally 7-count) / Q-RT-Ord source-§-traceability / Q-RT-Col1 RT-Col-A 7-column / Q-RT-Cat 6-value enum / Q-Sev Sev-α 3-tier critical-only-V1-block / Q-Special-Cases-a webhook-as-critical-§4.5-row + Q-Special-Cases-b parity-fixture-medium-severity.
- Stage 2 body bundle (§4.4 14-row × 8-col + §4.5 15-entry × 7-col + revised routing-flags block) accepted as-drafted; 7 per-row professional-judgment calls accepted (RT-01/06/08 consolidations + RT-07 vacant slot + RT-11/12 medium severity + SD-03 bounded-Item-active retention + SD-12 V2-cold-storage forward-compat + SD-13 cross-cutting annotation convention).
- Stage 3 posture bulk-closeout bundle (§4.1 5-bullet + §4.2 7-bullet + §4.3 6-bullet + §4.6 6-bullet = 24 posture bullets total) accepted as-drafted.
- Stage 4 ADR-008 + §4-whole content acceptance accepted as-drafted.

**Sec-lean track 21-for-21** — first non-PM-lean track in Phase 1 Step 3; pattern is now PM-lean 20-for-20 across §3 + §5 + §6 + §7 (PM-led sections) + Sec-lean 21-for-21 on §4 (Sec-led section). Combined teammate-lean track for Phase 1 Step 3 lock work: 41-for-41 across 5 non-§2 sections with zero F/CTO overrides on PM- or Sec-led recommendations.

**Engagement notes:** Sec workhorse across 6 tasks (gate-1 structure proposal — full framing + Option A 6-sub-section proposal + Q3 self-flag identification + Q1/Q2/Q4 + pattern-divergence flagging + ADR forecast; gate-A column-shape proposal — 5 sub-ratify questions + Class ID convention + N-day proposal; gate-B column-shape proposal — 6 sub-ratify questions + catalog-completion scan revising 7→14 + special-cases bundle; stage-2 row drafting — 217-cell two-table bundle + cross-reference validation pass + revised routing-flags block; stage-3 posture bulk-closeout — 24 bullets across 4 sub-sections; stage-4 ADR-008 confirm + production-ready ADR text + §7.1 (a) surgical edit text + content-readiness check). PM untouched (no PM-scope-shape consults surfaced; Q3a/b/c surfaces stayed within Sec posture territory; §4 didn't reveal V1 product-scope ambiguities). Architect untouched (no V1 architecture surface; §4 enumerates Sec posture and forward-points to Architect Phase 3 across 6 routing flags). CoS bookkeeping + 4 ratify-gate batches with F/CTO via AskUserQuestion (gate-1 6-question serialized; gate-A 5-question serialized; gate-B 6-question serialized; stages 2/3/4 single-acceptance gates each). **Sec agentId-based SendMessage continuation succeeded across all 6 stages** from CoS context; pattern is fully reliable for recently-completed agents regardless of agent type (PM or Sec).

**Patterns established or extended this session** for forward sections: (a) **First Sec primary-authored PRD section drafting pattern** — four-stage two-stage-hybrid pattern (gate-1 structure + retention/availability/incident self-flags → gate-A first-consolidation-table column-shape + sub-enums → gate-B second-consolidation-table column-shape + severity-rubric + catalog-completion scan → stage-2 row drafting → stage-3 posture bulk-closeout → stage-4 ADR confirm + integration prep) captured at ADR-008 Decision 5 as available for future Sec-primary-author sections (Phase 3 ARCHITECTURE.md, Phase 6 PR review). (b) **Pattern divergence (i) hybrid format** — markdown tables for structured-data consolidation surfaces; bulleted-with-framing for posture/narrative surfaces. Available to future sections whose content is mixed structured-data + posture-narrative. (c) **Pattern divergence (ii) two-stage hybrid drafting** — per-table ratify gates for content whose column-shape decisions are upstream of row-drafting (matrices, catalogs, indexes); bulk-closeout for content whose framing is upstream of bullets (posture sub-sections). Available to future sections with similar mixed-content shape. (d) **Pattern divergence (iii) ADR-008-grade canonical-reference layer** — ADR-grade material captured at ADR layer; bullet-level posture at PRD layer; the immutability boundary is named explicitly at ADR Decision 5 / Consequences. Available to future Sec-authored or Architect-authored ADRs that establish canonical reference layers. (e) **Catalog-completion scan during gate B** — Sec re-scanned upstream §2 + §3 with fresh §4.4 context and surfaced 7 additional V1-mandatory test surfaces not in the carried-forward running tally. Pattern surfaces that catalog-style sub-sections should include an explicit catalog-completion scan as part of their column-shape ratify gate; the upstream running tally may be partial. (f) **Closure-documentation-at-routing-flag pattern for ADR-002 §7.0 gap closures** — §4 closes gaps #4 + #6 + partial-#5 without amending ADR-002's body; closure documentation lives at §4 routing flag (o) + the corresponding §4.6 bullets; ADR-002 §7.0 traceability surface absorption (Appendix A) deferred to future housekeeping PR. Lighter-weight pattern than ADR-amendment for downstream sections that close upstream gaps.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **twelfth real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #23 §7 lock, PR #[TBD] §4 lock + ADR-008). **Largest PR diff to date** by content size (§4 body + ADR-008 body + §7.1 (a) reciprocation + WORKFLOW.md header + v1.17 changelog).

**Next thread:** **§8 V1 milestone framing draft** (PM-led, brief). §8 references §3.4 V1-done criteria (three migration-completion criteria including the N = 2 consecutive months parity-passing threshold on §3.4(c)); expected: brief structure proposal (likely 1-2 sub-sections or flat content) + body draft + integration pass. PM workhorse; Sec untouched (no §8 Sec surface — §8 is milestone framing, not a posture statement); Architect untouched (no V1 architecture surface at §8). After §8 lock, **Phase 1 Step 4** (Architectural overview consult) opens — Architect lead, Phase 3 entry gate; consumes the accumulated 11 §4 routing flags + 4 §3 routing flags + 6 §2.x routing flags + §7.2 + §7.1 cost-shape at-risk flag as Phase 3 entry payload. After Phase 1 Step 4 ratifies, **Phase 2** (UX/Visual design) becomes available; Phase 1 closes. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.16 — 2026-05-18

**PRD §7 LOCKED** (2026-05-18) — fourth non-§2 PRD section locked; closes the operating-envelope section and **closes all PM-led inventory sections in Phase 1 Step 3**. §7 (Constraints) drafted from a bare 4-line stub to a 3-sub-section content section across PM tasks (structure proposal + bulk-closeout body draft) and the integration pass (PRD.md + this WORKFLOW.md entry). Smallest PRD section locked to date (vs §6's 5 sub-sections, §3's 5, §5's 7); **§4 (Sec primary author) is the natural next thread now that all PM-led inventory sections are complete**.

**Structure: flat 3-sub-section enumeration** (§7.1 Cost / §7.2 Scale / §7.3 Usage model). Heterogeneous-constraint shape (financial / capacity / population-shape) — lightest grouping principle correct for the smallest section. Mirrors PRD stub one-to-one; rejected single "Operating envelope" axis collapse as artificial (§6's axis-grouping pattern works because product-identity boundaries are the *same kind of thing* per axis; §7's constraints are categorically distinct). **Format: bulleted enumeration + short framing paragraph per sub-section** (Format A — mirrors §5 / §6 / §3.5). Quadruple-confirms the bulleted-inventory shape.

**§7.1** (3 bullets) — target ceiling ≤ ~$50/month per ADR-002 §6.0 verbatim + cost-shape at-risk flag per `DECISIONS.md:275` (expanded V1 Plaid product mix changes architectural cost shape; target stays, bill reconciles at Architect Phase 3) + per-line-item out-of-PRD-scope boundary (Plaid product pricing / VPS / Coolify pricing live in ARCHITECTURE.md, not PRD). Honors dollar-figure redaction posture — ≤ $50/month target preserved verbatim (PRD-side locked commitment, not parity-evidence); no Plaid product pricing breakdowns or VPS line items.

**§7.2** (5 bullets) — historical-data depth (Dec-2015-forward NAV import per §2.1.3) + snapshot-store growth under daily-snapshot data shape (cross-reference §6.4) + Plaid sync throughput across two products on single tenant (per `DECISIONS.md:534`) + RLS query-shape forward-pointer (per `DECISIONS.md:541`) + multi-tenant isolation-at-scale posture forward-pointer to §4. V1 single-user by construction; "scale" is single-tenant scale dimensions, not multi-user-cohort scale. PRD commits to the posture (scale dimensions are first-class from day one even at single-user V1); implementation shapes are Architect Phase 3.

**§7.3** (2 bullets) — single-user V1 + multi-tenant infrastructure from day one per ADR-002 §1.4 verbatim + invite-only forward-compat per §5.7 (V2 adds second user without data migration of V1 user data). Reciprocates §5.7 cross-reference; closes §5 routing flag (e) (`PRD.md §5.7`).

**Routing-flags block: 5 items (a)-(e)** — one Sec V2-implementation forward-consult ((a) §7.1 spend-cap / API-quota alerting posture as cost-protection control: fires only if/when a runtime cost-protection mechanism is proposed); one Architect Phase-3 forward-pointer ((b) §7.2 scale dimensions + RLS query-shape resolve at ARCHITECTURE.md); three boundary notes ((c) §7.2 ↔ §6.4 daily-snapshot cross-reference, (d) §5 routing flag (e) closed at §7.3 lock, (e) §7 ↔ §4 routing for 3 forward-pointers). **Zero V1-block flags on either side.** Smallest routing-flags block to date alongside §6 (5 vs §6's 5; §3 and §5 both had 6).

**No new ADR for §7 lock.** §7 introduces no new scope decisions; all content is grounded in already-locked ADRs (ADR-002 §6.0 for §7.1; ADR-002 §1.4 + §5.7 for §7.3) or forward-points to Architect Phase 3 (§7.2). Follows §6 / §3 shape (lock without new ADR), not §5 / §2.3 / §2.5 shape (lock with amendment ADR). **Second consecutive section to lock without a new ADR** (after §6); pattern is settling that PM-led inventory sections that close pre-committed forward-pointers without introducing novel scope decisions do not produce ADRs.

**No cross-section surgical edits for §7 lock.** §7's content is purely additive to upstream sections; no §1.4-line-58-style alignment required (gate-1 PM scan confirmed). First section in the §3 → §5 → §6 → §7 sequence to lock without any cross-section edit (§5 had ADR-007 surgical amendment to ADR-002; §6 had §1.4 line-58 surgical edit).

**No Sec at-lock pass for §7** — §7 has no credential-handling surface, no auth-flow surface, no multi-tenant-isolation primitive ratification, no Plaid integration surface ratification, no money-flow surface, and no financial-calculation-integrity claim by construction (§7 enumerates the V1 operating envelope as declarative constraints). §7.1's spend-cap forward-consult is a V2-implementation flag, not a V1 surface; §7.2's multi-tenant isolation-at-scale routing is a forward-pointer to §4, not a §7 posture statement. Sec is **§4 primary author next**; §7's three forward-pointers to §4 (per routing flag (e)) consolidate into the §4 drafting scope.

**§7 / §4 boundary established as parallel pattern** to §5 / §6 (trajectory-vs-non-goal) and §3.5 / §6 (capability-vs-measurement): **§7 enumerates *constraints* (declarative envelope statements); §4 owns *postures* (incident handling, isolation posture, availability/uptime commitments)**. Spend-cap mechanism shape, availability commitments, and isolation-at-scale posture surface at §7 as forward-pointer flags for §4 to land. Q3 boundary lock makes this explicit at the section level; available as a clarifying lens at §4 drafting time.

**F/CTO ratification: 3-for-3 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides:
1. **Q3 boundary** = §4 owns postures, §7 = constraints only (PM-lean over §7.4 availability-expansion alternative). Eliminated §7.4 from Q1 options.
2. **Q1 structure** = flat 3-sub-section enumeration (PM-lean over single "Operating envelope" axis collapse).
3. **Q2 format** = bulleted enumeration + short framing paragraph per sub-section (PM-lean over §7.1-blockquote-hybrid alternative).
4. **Body-bundle as-drafted** accepted at section-level review; zero overrides on content or routing-flags wording.

**PM-lean track now 20-for-20** across §3 (4-for-4) + §5 (6-for-6) + §6 (5-for-5 structure + 1-for-1 body) + §7 (3-for-3 structure + 1-for-1 body). Bulk-closeout-from-structure pattern **quadruple-confirmed** (§3 → §5 → §6 → §7); pattern is now the durable default for PM-led inventory sections of any scope.

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — Q1/Q2/Q3 + forward-consult flag assessment + cross-section disposition scan + ADR forecast; bulk-closeout body draft — all 3 sub-section bodies + 5-item routing-flags block + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 surface). Architect untouched (no V1 architecture surface; §7.2 forward-pointers to Phase 3 only). CoS bookkeeping + 4 ratify gates with F/CTO via AskUserQuestion (Q3 standalone → Q1 standalone → Q2 standalone → body-bundle section-level acceptance). **Question-pacing precedent established**: interlocked gating questions can serialize cleanly with PM-recommended order (Q3 first as boundary settle → Q1 follows since boundary eliminates one option → Q2 standalone as format-independent decision), avoiding the §5 Q3b / §6 Q5-cluster aligned-bundle pattern when the interlock is one-way-elimination-shaped rather than aligned-disposition-shaped. **PM agentId-based SendMessage continuation succeeded a fourth time from CoS context** (after v1.13 §3, v1.14 §5, v1.15 §6 §7-structure-gate-spawn, this session's §7 body-draft continuation); pattern is fully reliable for recently-completed PM agents.

**Patterns established or extended this session** for forward sections: (a) **Quadruple-confirmed bulk-closeout-from-structure-proposal pattern** — now the durable default for PM-led inventory sections regardless of size. (b) **Two-consecutive-section no-ADR-lock pattern** (§6 → §7) — PM-led inventory sections that close pre-committed forward-pointers without novel scope decisions do not produce ADRs; ADR-producing locks (§5 → ADR-007) require novel scope decisions or substantive ADR amendments. (c) **Constraint-vs-posture §7/§4 boundary as third explicit boundary pattern** in Phase 1 Step 3 (alongside §5/§6 trajectory-vs-non-goal and §3.5/§6 capability-vs-measurement); each boundary clarifies what content belongs at which section, available as a lens at adjacent section drafting time. (d) **Question-pacing precedent extended** — three-way interlocked decisions can serialize with PM-recommended order when the interlock is one-way-elimination-shaped (Q3 elim'd Q1 option C without forcing Q1 itself), distinct from the aligned-bundle pattern where dispositions are genuinely coupled by content (§5 Q3b / §6 Q5-cluster).

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — **eleventh real use** of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #22 §6 lock, PR #[TBD] §7 lock).

**Next thread:** **§4 Security and compliance posture drafting** (Sec primary author). §4 is the largest single Phase 1 Step 3 task; lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes accumulated from §2.4 → §2.6 lock entries + 3 §7-side forward-pointers from §7 routing flag (e): §7.1 (a) spend-cap mechanism Sec-consult at V2-implementation time, §7.2 isolation-at-scale posture, and availability/uptime commitments per Q3 boundary lock. Sec primary engagement begins; PM consults on scope-shape questions if surfaced. Expected: substantially heavier structure-gate than any PM-led section (multi-axis Sec content with explicit §2-series surface dependencies); body-drafting pattern likely diverges from the quadruple-confirmed PM-led bulk-closeout shape. After §4 lock, **§8 V1 milestone framing** (PM-led, brief; references §3.4 V1-done criteria). After §8 lock, **Phase 1 Step 4** (Architectural overview consult) opens — Architect lead, Phase 3 entry gate. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.15 — 2026-05-17

**PRD §6 LOCKED** (2026-05-17) — third non-§2 PRD section locked; closes the smallest of the §3–§7 inventory sections. §6 (Out-of-scope for this PRD lifecycle) drafted from a bare stub to a 5-axis content section across PM tasks (structure proposal + bulk-closeout body draft including §1.4 line-58 surgical edit) and the integration pass (PRD.md + this WORKFLOW.md entry). **F/CTO chose to continue sequencing (a)** — drive lighter PM-led inventory sections before §4; §7 Constraints queued next.

**Structure: 5 axis sub-sections grouped by §3.0 product-identity axis** (§6.1 public-distribution / §6.2 money-movement / §6.3 advisor-fiduciary / §6.4 real-time-quote / §6.5 mobile-native). Mirrors ADR-007's axis-as-product-identity-boundary lock; each axis sub-section opens with a short axis-rationale paragraph + bullets per non-goal under the axis. **Format: §5-mirror bulleted enumeration** (Format A) with one-sentence "what specifically excluded" elaboration per item where the boundary is non-obvious (contested-axis items like TLH carry heavier elaboration; obvious items like public sign-up carry lighter elaboration). Section title preserved per ADR-002 Finding (c) verbatim relabel ("Out-of-scope for this PRD lifecycle"); epigraph rewritten to lock the permanent-non-goal-under-product-identity-axis framing per §5 + §3.5 + ADR-007.

**§6.1** (1 item) — public sign-up; ADR-002 §3.0 verbatim. Anchors public-distribution axis: KYC/fraud/identity-verification regulatory boundary; multi-tenant data model + V2 invite-only expansion are not stepping stones to public sign-up.

**§6.2** (1 item) — money movement; ADR-002 §3.0 verbatim. Light back-reference to §2.5.3's locked estimated-tax-payment recording-only surface (per Q5-b ratify) as the most-recently-pressure-tested example of the axis.

**§6.3** (2 items) — advisor/fiduciary role + TLH recommendations per ADR-007. Information-vs-prescription axis locked as the operative test; axis description carries general framing for shared-output-with-fiduciary-implication surfaces (per Q5-d ratify) without preemptively listing specific V2+ items (e.g., the §5.6 shared-link-delivery re-litigation flagged in §5 routing flag (c) lands here for future re-litigation, not as automatic V2 trajectory). §5.5 lot-level-features-stay-V2+ cross-reference preserved per ADR-007 narrowness; wash-sale auto-detection clarified as informational-annotation (V2+ trajectory) not prescriptive-recommendation.

**§6.4** (1 item) — real-time price quotes; ADR-002 §3.0 verbatim. Boundary framed as "data shape is daily snapshots," not "live data forbidden."

**§6.5** (1 item) — mobile-native application; ADR-002 §3.0 verbatim. Explicit non-§6 carve-out for mobile-responsive web as expected V1 behavior; specific responsive commitments queued for Phase 2 (UX/Design).

**§1.4 line-58 surgical edit** — `PRD.md §1.5` rewritten to align with §6 + ADR-007 framing: the advisor/fiduciary role carved out as the one §1.4 deferral that is a permanent §6 non-goal; geographic/multi-currency, life-stage/goal-tracking, and accountant read-only-export remain V2+ trajectory or future-PRD-revision per existing §1.4 prose. Terminology alignment to already-locked decisions, parallel to the surgical-amendment pattern of ADR-005/006/007; no new ADR (no novel scope decision; just alignment of pre-ADR-007 §1.4 framing).

**Routing-flags block: 3 boundary notes only** — (a) §6 ↔ §1.4 framing alignment (resolved at §6 lock per Q5-a surgical edit); (b) §6 ↔ §5 distinction (V2+ trajectory vs permanent non-goal; re-routes via surgical ADR amendment under §5/§6 axis-as-product-identity-boundary pattern; mirrors §5 flag (d) TLH boundary note from §5-side); (c) §6 ↔ §3.5 distinction (capability-shaped vs measurement-shaped; disjoint by construction). **Zero Sec V1-block flags, zero Architect V1-block flags, zero new V2-ship-gate forward-Sec-consult flags** (V2-ship-gate flags live at §5.6 + §5.4 per §5 lock). Smallest routing-flags block of any locked PRD section to date (vs §5's 6-item, §3's 6-item, §2.6's 12-Architect + 6-Sec).

**No new ADR for §6 lock.** ADR-007 (drafted alongside §5 lock) already lands the only structurally-novel addition (TLH reclassification). The §1.4 line-58 surgical edit per Q5-a is terminology-alignment, not a new scope decision (parallel to the pattern of surgical PRD edits at section locks that fold into existing ADRs without warranting their own ADR). First non-§2 section to lock without producing a new ADR amendment (§5 produced ADR-007; §3 produced no ADR — §6 follows §3's no-ADR shape, not §5's).

**No Sec at-lock pass for §6** — §6 has no credential-handling surface, no auth-flow, no multi-tenant-isolation primitive, no Plaid integration surface, no money-flow, no financial-calculation-integrity claim by construction (the section enumerates capabilities V1 does not build). Sec entries that touch axis territory (advisor/fiduciary axis description carries general framing for shared-output-with-fiduciary-implication V2-ship-gate items) are forward-pointers to §5's existing forward-Sec-consult flags, not new V1 Sec surfaces. Sec is **§4 primary author next** per the §2.6 / §3 / §5 lock framing.

**F/CTO ratification: 5-for-5 PM-lean acceptance at structure gate + 1-for-1 section-level body acceptance**, zero overrides at structure gate or body review:
1. **Q1 structure** = grouped by §3.0 product-identity axis (PM-lean over flat-enumeration / hybrid-tag alternatives);
2. **Q2 format** = §5-mirror bulleted enumeration (PM-lean over blockquote-per-item / hybrid alternatives);
3. **Q3 framing** = Q3-A epigraph rewrite + Q3-C section title preserved (PM-lean over keeping-stub-framing / rewriting-section-title alternatives);
4. **Q5-cluster** = accept all 4 PM-leans bundled (parallel to §5 Q3b 4-reroute pattern) — (a) surgical §1.4 line-58 edit no-new-ADR; (b) light back-reference to §2.5.3 in §6.2; (c) multi-owner data model stays at §1.4; (d) no preemptive shared-link listing at §6.3;
5. **Q7 bulk-closeout cadence** accepted per §3 / §5 scaling pattern (third instance);
6. **Body-bundle as-drafted** accepted at section-level review (including PM-default §6.3 axis-description language); zero overrides on content or §1.4 edit.

**PM-lean track now 16-for-16** across §3 (4-for-4) + §5 (6-for-6) + §6 (5-for-5 structure + 1-for-1 body acceptance). Bulk-closeout-from-structure pattern triple-confirmed (§3 → §5 → §6); pattern is now the default for PM-led inventory sections of comparable scope.

**Engagement notes:** PM workhorse across 2 tasks (structure proposal — full framing + 5-axis sub-section proposal + Q1/Q2/Q3 + Q5-cluster of 4 cross-section dispositions + Q7 cadence; bulk-closeout body draft — all 5 axis sub-sections + 3 boundary notes + §1.4 surgical edit + acceptance flags in one bundle). Sec untouched (no credential-handling surface, no V1 surface). Architect untouched (no V1 architecture surface; §6 enumerates non-built capabilities). CoS bookkeeping + 4 ratify gates with F/CTO via AskUserQuestion (Q1 standalone → Q2 + Q3 bundled → Q5-cluster + Q7 bundled → body-bundle section-level acceptance). **PM agentId-based SendMessage continuation succeeded again from CoS context** — third confirmed instance (after v1.13 §3 lock and §6 structure gate this session); pattern now reliable for recently-completed PM agents, full-brief re-spawn remains the fallback for finished-and-cleared agents.

**Patterns established this session** for forward sections: (a) **Triple-confirmed bulk-closeout-from-structure-proposal pattern** — pinned as default for PM-led inventory sections; §7 (next, smallest yet at 3 sub-sections) is the natural fourth instance. (b) **§6-shape sections lock without new ADRs** when the §6 inventory's only novel addition (TLH from §5 → §6 per ADR-007) was already covered in an upstream lock's ADR; the §1.4 line-58 surgical edit precedent shows section-locks can carry terminology-alignment edits to upstream sections without warranting their own ADR (parallel to the running pattern of fold-into-existing-ADR for non-scope-decision alignments). (c) **Axis-grouped structure for product-identity-boundary sections** (vs §5's §2.x-capability-area grouping for V2+ trajectory sections) — structure grouping follows what makes the section's organizing axis navigable; §5 needed source-section traceability, §6 needed axis-traceability. (d) **Q5-cluster bundle precedent extended** — §5's Q3b 4-reroute bundle is now joined by §6's Q5-cluster 4-disposition bundle; aligned-bundles can ratify in one question while genuinely-distinct decisions serialize one-question-at-a-time (preserves the pacing pin without over-serializing). (e) **Forward-pointer axis-description pattern** — §6.3 axis description carries general framing for shared-output-with-fiduciary-implication surfaces; future V2-scoping decisions land at the axis sub-section for re-litigation rather than at the V1 PRD; pattern available for §6.x sub-sections where V2+ items in adjacent §5 sub-sections may push against the axis at V2-scoping time.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — tenth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #21 §5 lock + ADR-007, PR #[TBD] §6 lock).

**Next thread:** **§7 Constraints drafting** per F/CTO sequencing choice (a). §7 is the last PM-led inventory section before §4 (Sec primary author). Three sub-sections per current PRD stub: §7.1 Cost / §7.2 Scale / §7.3 Usage model (references §5.7 multi-user V2 expansion). Expected: structure proposal (likely flat 3-sub-section or grouped-by-constraint-class) + bulk-closeout body (fourth instance of the triple-confirmed pattern) + acceptance flags. Sec consult on §7.1 / §7.2 may surface (cost/scale axes may touch §4 Sec posture surfaces — Plaid quota costs, multi-tenant RLS scale implications, etc.); to be assessed at structure-proposal time. Architect may have a forward-pointer flag for §7.2 Scale (Phase 3 territory). After §7 lock, **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6 lock entries). After §4 lock, §8 V1 milestone framing draft (references §3.4 V1-done criteria), then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.14 — 2026-05-17

**PRD §5 LOCKED + ADR-007 ACCEPTED** (2026-05-17) — second non-§2 PRD section locked; closes the V2 deferred candidates consolidation. §5 drafted from a bare stub to a 7-sub-section pure-inventory section across PM tasks (structure proposal + bulk-closeout body draft including ADR-007) and the integration pass (PRD.md + DECISIONS.md + this WORKFLOW.md entry). **F/CTO chose to continue sequencing (a)** at session open — drive lighter PM-led inventory sections before §4.

**Structure: 7 sub-sections grouped by §2.x capability area** (§5.1 net-worth / §5.2 allocation / §5.3 cash-flow / §5.4 cross-cutting onboarding-entry-re-auth / §5.5 estimated-tax / §5.6 monthly-report / §5.7 cross-cutting V2+). Mirrors PRD navigation model; one-step traceability from V2+ entry back to source §2.x V1/V2 clause; symmetric with §3 sub-section structure. **Format: bulleted enumeration per sub-section** (mirrors §3.5 non-metrics shape) — each V2+ item gets one bullet with capability summary + source-section/ADR trace + (optional) brief deferral rationale; no per-item blockquote paragraphs.

**§5.1** (4 net-worth deferrals) — user-configurable time-axis controls on NAV surfaces; per-scope NAV reporting + filtering UI (ADR-004 Decision B V2+); per-tenant CPI-U source override; historical NAV import beyond V1 Dec-2015-forward parity import.

**§5.2** (6 allocation deferrals) — asset-taxonomy CRUD UI (ADR-004 Decision C V2+); auto-generated rebalance suggestions (ADR-004 Decision A V2+); Ex-US sub-allocation drill-down; per-scope allocation views; per-account taxonomy overrides; general drill-down view capability.

**§5.3** (8 cash-flow deferrals) — cash-flow-taxonomy CRUD UI; budget tracking mechanics (variance + alerts + rolling budgets + per-category targets); rule-based auto-categorization beyond recurring-vendor; per-account taxonomy overrides; per-scope cash-flow rendering; income time-series + multi-year income recordkeeping ((α) lock); Historical Expenditures chart extensions; non-monthly + custom periods.

**§5.4** (8 cross-cutting deferrals) — auto-classification of new symbols; onboarding workflow extensions; pre-emptive notification surfaces (incl. **pre-emptive Plaid re-auth reminders with Sec consult required before V2 ship**); manual transaction entry extensions; external valuation integrations; Plaid Liabilities + Plaid Income product expansions; Plaid coverage / instrument-level mechanics (derivative Greeks / bond YTM / REIT-MLP K-1 / off-exchange crypto / DRIP-pair detection / per-security configurable classification); HSA "tax-free conditional" tax-treatment refinement.

**§5.5** (23 estimated-tax deferrals) — **TLH excluded per ADR-007**; preserves ADR-002 Finding (b) "possibly a separate tool" hedge verbatim on stock screening. Auto-categorization + user-editable CRUD on Sub-Cat tax attributes; multi-year tax surfaces; full Federal AGI-line decomposition (ζ-3); wash-sale + Section 1256 auto-detection; **lot-level tax features (FIFO/LIFO/specific-ID)** — explicitly carries forward MINUS TLH per ADR-007; in-state-vs-out-of-state municipal-bond differentiation; live tax-data API ingestion; multi-jurisdiction tax expansion (multi-state + non-US); filing-status enum; bracket-aware tax credits + above-the-line deductions; separate California LT CG schedule (if existing-system divergence surfaces); quarterly-installment-sizing refinements (safe-harbor floor + μ-1 + μ-3 + annualized-income method); withholding tracking; pre-emptive quarterly-payment reminders; refund/overpayment surfacing extensions (ν-2); penalty + prior-tax-year computation; bracket-aware Unrealized Tax Liability refinements (ο-b + ο-c + Federal-ordinary-top alternative); per-jurisdiction split rendering of Realized + Unrealized (ρ-2); tax-deferred withdrawal-tax-liability as fourth NAV-subtraction; REIT/MLP K-1 splits on unrealized G/L; multi-state Unrealized Tax Liability sourcing; Monte Carlo longevity modeling; stock screening with hedge.

**§5.6** (13 monthly-report deferrals) — user-configurable section ordering + composition (ω-2/ω-3); multi-scope reports; auto-generated + hybrid Rebalancing Targets commentary (σ-2/σ-3); Rebalancing Targets editor extensions (sub-section CRUD + markdown + auto-pre-populate + late-edit revision tracking); generation-cadence + trigger extensions; revision history for regenerated months (resolves §2.6.2-vs-§2.6.3 persistence-tension); **email/SMS delivery** with **forward-Sec-consult flag**; **shared-link delivery to external viewers** with **forward-Sec-consult flag + possible ADR re-litigation against §6 advisor-role boundary**; alternative output formats (Google Doc υ-3 / markdown / HTML email / JSON-CSV / scheduled storage export); drill-down from sections to source surfaces; live-rendered date-filtered views of historical months (φ-2/φ-3); snapshot-store retention + management extensions; owner-identification header extensions (ψ-2/ψ-3); staleness-marker extensions.

**§5.7** (2 cross-cutting V2+) — multi-user invite-only V2 expansion (ADR-002 §1.4 V1-to-V2 transition; data model carries V1, UI/auth gates V2+; §7.3 references this); multi-currency (ADR-002 §3.0 reclassification from non-goal to V2+ deferral).

**Routing-flags block: 6 items (a)-(f)** — three Sec forward-consult flags for V2-ship gates ((a) pre-emptive Plaid re-auth reminders carry-forward from §2.4.4; (b) email/SMS delivery; (c) shared-link delivery with possible ADR re-litigation); two boundary notes ((d) TLH home is §6 pending §6 body drafting; (e) §5 → §7.3 cross-reference); one Architect general flag ((f) V2+ schema/migration scope decisions at V2-scoping). Smaller routing-flags block than §3's 6-item block on Architect/Sec axes — §5 has zero V1 Architect blocks (V2-scoping defers all schema work).

**ADR-007 — Amendment to ADR-002 Finding (b): TLH reclassified from V2+ to permanent non-goal under advisor-role axis.** First amendment exercising the §5/§6 axis-as-product-identity-boundary pattern. The §5/§6 distinction is V1's mechanism for keeping product-identity decisions sharp; ADR-007 establishes the precedent that V2+ candidates from earlier ratifications can move to §6 when on-inspection they cross the §3.0 advisor / fiduciary / money-movement / public-distribution / real-time-quote / mobile-native axis. **Information-vs-prescription axis** locked as the operative distinction: TLH-as-prescriptive-recommendation crosses advisor-role boundary; observational tax-tool extensions (lot-level features, wash-sale auto-detection as informational annotation) remain V2+. ADR-007 narrowness: only the "recommend tax-actions against unrealized losses" framing moves; lot-level features and wash-sale auto-detection stay V2+ in §5.5. ADR-002 Finding (b)'s remaining V2+ enumeration (Monte Carlo longevity, stock screening with hedge, tax planning already promoted to V1) unchanged. Parallel to ADR-005 + ADR-006 surgical-amendment pattern (no supersession of ADR-002 as a whole).

**F/CTO ratification: 6-for-6 PM-lean acceptance, zero overrides**:
1. **Q1 structure** = grouped by §2.x capability area (PM-lean over flat / V2-release-cohort alternatives);
2. **Q2 format** = bulleted enumeration per sub-section (PM-lean over blockquote-per-item / hybrid alternatives);
3. **Q3a TLH home** = §6 (PM-lean — advisor-role boundary; required ADR-007 amendment to ADR-002 Finding (b));
4. **Q3b 4-reroute bundle** = accept all PM-leans — (a) category alerts → §5; (c) Monte Carlo → §5; (d) stock screening → §5 with hedge preserved verbatim; (e) email/SMS + shared-link → §5 with forward-Sec-consult flag;
5. **Bulk-closeout drafting cadence accepted** per §3 / §2.6 scaling pattern;
6. **Bulk-closeout body bundle + ADR-007 accepted as-drafted** at section-level review — zero overrides on content or ADR-007 scope.

**No Sec at-lock pass for §5** — §5 has no credential-handling surface, no auth-flow, no multi-tenant-isolation primitive, no Plaid integration surface, no money-flow, no financial-calculation-integrity claim. Sec entries that touch territory ((a) / (b) / (c) routing flags) are forward-Sec-consult flags for V2-ship gates, not V1 Sec at-lock surfaces. Sec is **§4 primary author next** per §2.6 lock framing.

**Engagement notes:** PM workhorse across 2 tasks (#55 structure proposal — comprehensive sweep of §2.x V1/V2 boundary clauses + ADR-002 Finding (b) consolidation + 3 ratify questions with 5 §5/§6 reroute candidates; #56 bulk-closeout body draft — all 7 sub-sections + 6 routing flags + acceptance-flags + ADR-007 in one bundle). Sec untouched (no credential-handling surface). Architect untouched (V2-scoping routing only). CoS bookkeeping + 6 ratify gates with F/CTO (Q1 / Q2 / Q3a / Q3b / bulk-closeout cadence / section-level review acceptance). **Bulk-closeout-from-structure-proposal pattern** reused successfully (second instance after §3) — F/CTO PM-lean tracking signal at structure gate triggers bulk closeout for body draft; no per-sub-section serialization needed.

**Patterns established this session** for forward sections: (a) **§5/§6 axis-as-product-identity-boundary pattern** — when a V2+ candidate crosses the §3.0 permanent-non-goal axis on inspection, the resolution is §6 reclassification via ADR amendment rather than carry-forward as a V2+ trajectory item; (b) **Surgical-amendment ADR precedent extended** — ADR-007 follows ADR-005 / ADR-006's narrow-scope amendment pattern (parent ADR's other clauses unchanged, no supersession of the parent ADR as a whole); fourth ADR amendment since Phase 1 Step 3 opened; (c) **Information-vs-prescription axis as scope-boundary mechanism** — explicit framing locked in ADR-007 rationale; available for future §5/§6 reroute decisions (e.g., if AI-assisted features surface at V2-scoping, the information-vs-prescription axis is the test); (d) **Bulk-closeout-from-structure-proposal pattern** — second instance after §3; pinned as default for PM-led inventory sections (§6 / §7 candidates given comparable scope + smaller-than-§2 footprint); (e) **Composite Q3 routing decisions** can be split — Q3a (contentious item with ADR consequences) surfaced separately, Q3b (4-item bundle of aligned reroutes) bundled as one ratify question; preserves one-question-at-a-time for genuinely-distinct decisions while avoiding over-serialization for aligned bundles.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — ninth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #19 §2.6 lock, PR #20 §3 lock, PR #[TBD] §5 lock + ADR-007).

**Next thread:** **§6 Out-of-scope for this PRD lifecycle drafting** per F/CTO sequencing choice (a). §6 is the smaller-still cousin of §5 — pure inventory of permanent non-goals from ADR-002 §3.0 + the new TLH addition per ADR-007. Expected: structure proposal (likely flat or short-grouped) + bulk-closeout body (likely shorter than §5 given §6's narrower scope) + acceptance flags. No new ADR expected (ADR-007 already lands TLH). Sec untouched. After §6 lock, **§7 Constraints** (7.1 Cost / 7.2 Scale / 7.3 Usage model — references §5.7 multi-user V2 expansion), then closing with **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6 lock entries). After §4 lock, §8 V1 milestone framing draft (references §3.4 V1-done criteria), then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.13 — 2026-05-17

**PRD §3 LOCKED** (2026-05-17) — **first non-§2 PRD section locked**; closes the smallest of the five §3–§7 sections queued at §2.6 lock. §3 (Success metrics) drafted from a bare stub to a five-sub-section content section via Tasks #55 (structure proposal) and #56 (bulk-closeout body draft + integration). **F/CTO chose sequencing (a) at session open** — drive lighter PM-led inventory sections (§3 → §5 → §6 → §7) before closing with §4 (Sec primary author).

**Structure: 5 sub-sections** (§3.1 framing / §3.2 capability-delivery / §3.3 parity / §3.4 migration-completion / §3.5 explicit non-metrics) — neither the §2-series Primary/Supporting split nor the §1-series flat-paragraph shape; the section is uniformly content sub-sections with no inter-sub-section role distinction. **Three-axis V1 success framing** (§3.1) — V1 success is the conjunction of (i) capability delivery against the §1.2 archetype, (ii) output parity against the existing manual-spreadsheet system, (iii) migration completion (F/CTO retires the existing system); failure on any axis means V1 is not done. Single-user calibration explicit per ADR-002 §1.4 + §1.3; SaaS-pattern measurement frames enumerated as explicit non-metrics in §3.5.

**§3.1** *Framing* — three blockquote paragraphs (three-axis success + single-user calibration + parity-grounded-not-aspirational); cites §1.1 V1-done bar + ADR-002 §8 no-fallback-to-existing-system; commits §3.3 hybrid-tolerance framing as the "matches the existing system" definition.

**§3.2** *Capability-delivery metrics (§1.2 attribute coverage)* — **6 binary-testable metrics + 1 non-metric note**, one per §1.2 archetype attribute with **observational-tool (#4) deliberately excluded** as non-goal-shape (measuring would be category error; §6 owns the surface). Metric 4 (§1.2 attribute #5 strengthened at v1.6 — two-level taxonomies on holdings AND cash-flow, user-assigned, user-defined grammar) is the **high-bar metric** — six-part binary test (a)-(f) including both holdings + cash-flow taxonomy + user-editable assignment UIs + no-coarser-bucket-only-fallback aggregation surfaces. Each metric names the §2.x story(ies) it exercises.

**§3.3** *Parity metrics* — **6 per-§2-story sub-blocks**, each defining (i) comparison fixture from F/CTO existing system (`Finance_Report_2026_04.pdf` + Asset Summary workbook sheets + per-account workbooks), (ii) cells/panels/charts compared, (iii) tolerance class from Q3 hybrid framing. **§2.6 parity test elevated as canonical end-to-end V1-replaces-existing-system test** — passing §2.6 parity for a given month is the strongest single signal that V1 reproduces the F/CTO's monthly Finance_Report workflow; transitively applies §2.1 / §2.2 / §2.3 / §2.5 numeric tolerances on every rendered cell. **Hybrid tolerance** locked: strict equality for categorical (taxonomy structure, account names, labels, `tax_character` enum, four §2.4.4 credential-error states); **≤ $1 absolute OR ≤ 0.01% relative, whichever is greater** numeric tolerance for derived dollar values (NAV / NAV-delta / unrealized-G/L / cash-flow rollups / Realized + Unrealized Tax Liability / quarterly est-payments / rendered report cells); structural equivalence for layout / panel-set / chart-presence (no pixel match required).

**§3.4** *Migration-completion ("V1 done" definition)* — **3 conjunctive criteria**: (a) every parity-matrix "V1 preserve" line has §2 story locked + §3.3 parity test passing; (b) every ADR-004 amendment (Decisions A/B/C/D + ADR-005 + ADR-006) has capability delivered and parity-tested; (c) F/CTO has run monthly review cycle on V1 alone, without consulting existing manual-spreadsheet system, for **N = 2 consecutive months** (calibrated as: long enough for one month of green to not be a fluke + second month surfaces month-boundary edge cases; short enough that V1-final isn't gated on a six-month soak). **§3.4 is home for "V1 done" definition** per F/CTO Q2 lock — answers ADR-002 §7.0 open content gap #4; **§8 V1 milestone framing references §3.4** + adds milestone-sequencing scaffolding (V1.0 → V1.x → V1.final per ADR-004); §3.4 commits to criteria, §8 sequences them.

**§3.5** *Explicit non-metrics for V1* — 7 enumerated measurement-frame exclusions (MAU/WAU/DAU; NPS/CSAT; conversion/sign-up funnel; D1/D7/D30 retention/churn; viral coefficient/K-factor/referral; ARR/MRR/ARPU/LTV/CAC; engagement-proxy time-on-page/session-length/feature-adoption %), each with one-line rationale anchored to single-user-V1 calibration. **§3.5-vs-§6 distinction explicit**: §6 is capability-shaped (surfaces V1 doesn't build); §3.5 is measurement-shaped (frames V1 doesn't apply); disjoint by construction.

**Routing-flags block: 6 items (a)-(f)** — three Architect-led ((a) §2.6 render latency thresholds; (b) parity-fixture test-environment plumbing Architect/Sec joint; (c) §3.2 binary-test data-model verification), two Sec-led for §4 ((d) shadow-workflow tear-down posture for existing-system retirement; (e) parity-fixture sensitive-data handling), and one boundary-marker (f) confirming §3 does NOT enumerate the 13-class sensitive-data inventory (§4 territory per §2.6 lock). Smaller routing-flags block than §2.6's 12-Architect + 6-Sec, reflecting §3's smaller scope.

**F/CTO ratification: 4-for-4 PM-lean acceptance, zero overrides**:
1. **Q1 structure** = 5 sub-sections (PM-lean over 4-section / 3-section alternatives);
2. **Q2 V1-done definition home** = §3.4 (PM-lean; §8 references §3.4 + adds milestone sequencing);
3. **Q3 parity tolerance framing** = hybrid (PM-lean; strict equality categorical + numeric tolerance dollars + structural equivalence layout, over strict-across-the-board / fuzzy-no-PRD-tolerance alternatives);
4. **Bulk-closeout drafting cadence accepted** at body-drafting gate per §2.6 scaling pattern (mirrors §2.6.4-§2.6.6 bulk closeout). **Bulk-closeout body bundle accepted as-drafted** at section-level review — zero overrides on the two explicit PM-lean numerics (§3.3 ≤ $1 / ≤ 0.01% tolerance and §3.4(c) N=2 months) and zero overrides on content.

**No ADR for §3 lock** — locks fold cleanly into PRD body + routing-flags per §2.6 precedent. §3.4's "V1 done" definition home in §3.4 (vs §8) is a PRD-internal scope clarification, not an ADR-grade decision; ADR-002 §7.0 item 7 framing remains satisfied via §3.4 + §8 cross-reference. §3 introduces no genuinely new V1 capability surface (vs ADR-005's §2.3.2 planning-targets settings UI which warranted dedicated ADR) — §3 measures delivery of surfaces already PRD-locked in §1.2 / §2.x.

**No Sec at-lock pass for §3** — §3 has no credential-handling surface, no auth flow, no multi-tenant-isolation primitive, no Plaid integration, no money-flow, no financial-calculation-integrity claim. Sec is **§4 primary author next** per §2.6 lock framing — largest single Sec task in Phase 1 where the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes land. Sec consult on §3 collapses into the Phase 1 Step 4 architectural-overview consult flagged at §2.6 lock (no separate Sec spawn for §3).

**Engagement notes:** PM workhorse across 2 tasks (#55 structure proposal — full framing + 5 sub-section proposal + 3 ratify questions; #56 bulk-closeout body draft — all 5 sub-sections + routing flags + acceptance flags). Sec untouched per "no credential-handling surface" rationale; Architect untouched (routing flags route to Phase 3, not Phase 1). CoS bookkeeping + 4 ratify gates with F/CTO (Q1 / Q2 / Q3 sub-decisions + bulk-closeout drafting cadence + bulk-closeout body section-level review). **Bulk-closeout from structure proposal directly to lock-quality bundle** (no per-sub-section serialization) — second instance of the §2.6 bulk-closeout pattern; first time used from structure-proposal forward rather than mid-section pivot. **Pattern pinned for forward sections** (§5 / §6 / §7 candidates given comparable scope + smaller-than-§2 footprint): if PM-leans track 2+ consecutive ratifications at structure gate, propose bulk-closeout-from-structure for body draft.

**PM agentId-based SendMessage continuation succeeded from CoS context** — counter-evidence to the prior memory pin asserting agentId continuation isn't addressable. The pin may apply only to finished-and-cleared agents (auto-cleanup state) rather than recently-completed ones; not updating memory until cross-session confirmation. Continued PM via `to: 'a77de9defd7482f87'` after `to: 'pm'` (name) failed.

**Patterns established this session** for forward sections: (a) **bulk-closeout-from-structure-proposal** as a scaling release valve when PM-leans track at structure gate (vs §2.6's bulk-closeout-mid-section pivot); (b) **PM agentId-based SendMessage continuation** addressable from CoS context for recently-completed PM agents (overrides prior memory pin's blanket non-addressable assertion; full-brief re-spawn remains the recovery path for finished-and-cleared agents); (c) **§3-shape non-§2 PRD sections** use flat 5-sub-section structure with no Primary/Supporting role distinction (vs §2.x's Primary/Supporting split); (d) **routing-flag (f) boundary-marker pattern** — when a §X section deliberately does not enumerate content that's owned by another section §Y, capture the boundary as a routing-flag entry rather than silence to prevent territorial drift at body-review.

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — eighth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #[prior] §2.6 lock, PR #[TBD] §3 lock).

**Next thread:** **§5 V2 deferred candidates drafting** per F/CTO sequencing choice (a). §5 is a PM-led inventory section drawing from the V2+ items surfaced across §2.1 → §2.6 V1/V2 boundary clauses (per-account taxonomy overrides; multi-user invite-only; auto-rebalance-suggestions per ADR-007 boundary; lot-level tax features per ADR-002 §1.7 + ADR-004 Decision D; user-editable taxonomy CRUD per ADR-004 Decision C V2+; revision history on monthly reports; etc.). Then **§6 Out-of-scope** (permanent non-goals from ADR-002 §3.0 + this-PRD-lifecycle deferrals), then **§7 Constraints** (7.1 Cost / 7.2 Scale / 7.3 Usage model), then closing with **§4 Security and compliance posture** (Sec primary author, largest single Phase 1 Step 3 task — lands the 7 Phase 3 RLS test candidates + 13-class sensitive-data matrix + 6 canonical Sec axes from §2.4 → §2.6). After §4 lock, §8 V1 milestone framing draft, then Phase 1 Step 4 (Architectural overview consult) opens. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.12 — 2026-05-17

**PRD §2.6 LOCKED** (2026-05-17) — sixth locked PRD section; closes the §2 V1 user stories series. §2.6 (Monthly Report — canonical V1 deliverable, Finance_Report-shape) drafted from a bare stub to a 5-Primary + 1-Supporting parity-grounded section across Tasks #45 (structure proposal), #46 (§2.6.1 body), #47 (§2.6.2 body), #48 (§2.6.3 body), #49 (§2.6.4 body v1), #50–#53 (bulk §2.6 closeout — §2.6.4 v1.1 reformatted + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags), #54 (Sec at-lock pass), and the integration pass (this WORKFLOW.md + PRD.md write).

**Structure: 5 Primary + 1 Supporting** (vs §2.4 / §2.5 4-Primary-1-Supporting pattern; §2.6 carries one additional Primary because the report-as-artifact has more genuinely-distinct V1 surfaces — composition + section ordering, Rebalancing Targets free-text capture, generation cadence/format, snapshot/retention/identity, and staleness-marker rendering are five non-overlapping content surfaces).

**§2.6.1** *Monthly report composition and section ordering* — ω-1 V1-fixed six-section sequence (Account Holdings → NAV Performance → Asset Allocation → Rebalancing Targets → Cash Flow → Estimated Taxes) parity-exact with existing Finance_Report layout; Historical Expenditures inline within Cash Flow (resolves parity-matrix line 105-106 placeholder ambiguity); owner-identification trust-name header at top; six-section composition map names §2.1.5 (Account Holdings), §2.1.2 + §2.1.3 + §2.1.4 (NAV Performance), §2.2.2 + §2.2.3 (Asset Allocation), §2.6.2 (Rebalancing Targets), §2.3.2 + §2.3.4 (Cash Flow inline), §2.5.1 + §2.5.3 (Estimated Taxes); §2.5.4 NAV-component lines render on Account Holdings via §2.1.5, not as separate Estimated Taxes rows; Big Ticket Fund / Amortized Expenses dropped per Phase 0.5 call; user-configurable section ordering (ω-2 / ω-3) deferred V2+.

**§2.6.2** *Rebalancing Targets free-text commentary* — σ-1 free-text user-authored (preserves ADR-004 Decision A V2+-only auto-rebalance-suggestions boundary; σ-2 auto-generated and σ-3 hybrid both rejected as ADR-007-triggering V2+ paths); V1-fixed four sub-sections (Cash / Bonds / Equity / Alternatives) parity-exact with parity-matrix line 102; §2.2.2 `$ ReAlloc` side-by-side reference data during authoring (rendering shape Architect Phase 3); plain text editor with line breaks preserved (markdown / rich-text V2+); blank-by-default new-month editor with explicit per-sub-section and global "copy from prior month" affordance (auto-pre-population V2+); author-before-generate capture timing as part of §2.6.3 generation flow; per-report persistence commitment; **write-path RLS commitment carried directly in §2.6.2 body** per §2.4.5 precedent (tenant-scoped commentary authoring; sixth instance of scope-attribute-not-isolation-boundary canonical clause); read-path covered by §2.6.6 Supporting.

**§2.6.3** *Report generation cadence, trigger, and output format* — τ-1 monthly cron + user-on-demand dual-trigger; υ-1 in-app rendered web page (canonical) + PDF export on demand (PDF generation server-side vs client-side = Architect Phase 3); cron schedule fixed at 1st-of-month-for-prior-month with last-day-prior-month data-as-of; user-on-demand target-month selection (prior-month default + current-month-in-progress as-of-today); pending-monthly-report in-app notification + queue affordance (parallel to §2.4.1 iv-1 notification queue pattern); author-before-generate honored under both trigger paths (§2.6.2 commentary editor opens first, blocks finalization); three-state `not-yet-triggered` / `pending` / `generated` lifecycle; overwrite-semantics regeneration with commentary pre-populated from prior snapshot (revision history V2+); PDF as transient download (not server-side persisted artifact; no PDF caching V1); cron failures logged at system level with on-demand trigger as manual fallback (in-app cron-failure notification V2+); per-tenant cron under ADR-002 §1.4. Deliberate §2.6.2-vs-§2.6.3 persistence-tension acknowledged in body: §2.6.2 "historical-month commentary survives unchanged" holds **between regenerations**, not absolutely permanently; revision-history V2+ resolves the tension fully.

**§2.6.4** *Snapshot, historical retention, and report identity* — φ-1 frozen-at-generation snapshot (parity-exact with existing-system PDF freeze-on-export behavior; φ-2 live-rendered and φ-3 toggle both V2+); χ-1 indefinite retention of every generated report (no V1 cleanup / archival / user-deletion; χ-2 current-month-only and χ-3 V2+-archive both rejected); ψ-1 single per-tenant owner-identification config string (multi-named-owner ψ-2 and per-report-override ψ-3 V2+); rendered-value-level snapshot shape (not source-data-level — snapshot does not re-compute when source data changes; detailed table/column shape Architect Phase 3); **owner-identification snapshot-not-live at render time** — historical reports keep the name as-of-generation; settings changes apply forward not retroactively, parallel to §2.5.2 bracket-schedule forward-not-retroactive analog; overwrite-semantics regeneration honoring §2.6.3; in-app reads snapshot directly + PDF re-generates per export (no PDF caching V1); **staleness-marker live-read carve-out** — §2.6.5 staleness markers read LIVE at render time from §2.4.4 credential-error state, NOT from snapshot (deliberate carve-out preserving §2.4.4 non-silent-staleness contract; analog of §2.3.2's "render the data but never lie about its provenance" discipline). ADR-005 settings store extension is the **third additive field** after §2.3.2 planning targets + §2.5.2 bracket schedules; dedup-vs-split is Architect Phase 3 parallel to §2.5.2 dedup flag.

**§2.6.5** *Staleness markers on report surfaces* — α′-1 generate-with-markers, not block-with-warning (preserves operational + integrity contracts: report renders, marker is per-section, user has full information; α′-2 block-with-warning and α′-3 generate-with-banner-only both rejected); marker visual shape = inline per-section indicator + report-level summary banner naming stale-contributing accounts (additive, not substitute; UX detail Architect/Design Phase 2/3); all four §2.4.4-distinguished credential-error states trigger markers uniformly (V1 no per-class subdivision); §2.6.2 Rebalancing Targets and §2.6.4 owner-identification header excluded from marking (non-account-derived); PDF export carries same markers as in-app view at click moment (live-read at export time per §2.6.4 carve-out); historical reports viewed today show CURRENT staleness state at view time (per §2.6.4 carve-out); cron-generated + user-on-demand reports identical marker behavior. **§2.6.5 is §2.4.4's contract enforced one layer up** — closes the §2.4.4 non-silent-staleness commitment §2.6 surface.

**§2.6.6** *Monthly report is mine, not anyone else's* (Supporting; sixth instance of named-surface-scoped tenant-isolation pattern across PRD §2: §2.1.7 + §2.2.4 + §2.3.5 + §2.4.5 + §2.5.5 + §2.6.6); read-path-shape framing (write-path RLS for §2.6.2 commentary carried in §2.6.2 itself, parallel to §2.5.2 settings-UI write-path excluded from §2.5.5); names §2.6.1 + §2.6.2 + §2.6.3 + §2.6.4 explicitly; §2.6.5 not named separately (its read path is §2.4.4 credential-error state, tenant isolation carried by §2.4.5, inherited here); **sixth instance of scope-attribute-not-isolation-boundary canonical clause** (verbatim-equivalent to §2.5.5 / §2.4.5 / §2.3.5 / §2.2.4 / §2.1.7); multi-scope V1 full-household-default per ADR-004 Decision B (closes parity-matrix line 180 per-scope reports V2+); **NEW — snapshot store as persisted derivative surface** of §2.5-grade sensitive-data classes flagged for §4 Sec attention (first derivative-surface persistence layer joining §2 surface inventory at lock; tri-axis tenant_id × scope × tax_treatment framing inherited where underlying classes carry tax-treatment, collapses to tenant_id × scope where no tax-treatment dimension).

**Routing-flags block: 12 Architect items (a)-(l) + 6 Sec items (i)-(vi) + 4 carry-forward bullets** (Sec product-disclaimer ratified PM-default; no new ADR for §2.6; Sec at-lock verdict recorded; PR # placeholder). Architect items densest §2 block to date (vs §2.4's 11 and §2.5's 13). Six Sec items mostly Sec-led (snapshot store tenant-scoping; owner-identification settings-store write-path validation; snapshot row as derivative-surface annotation; commentary write-path RLS; staleness-marker live-read cross-tenant signal-leak; cron job tenant-scoping).

**Sec Task #54 verdict: pass-with-comments, no veto, no required revisions** — sixth at-lock Sec pass + **first six-axis pass** with NEW derivative-surface-persistence axis elevated (axis (d) snapshot store as persisted derivative surface; Sec recommends §4 carries a dedicated "Derivative persistence surfaces" sub-section rather than annotating per-class). Five prior Sec axes hold: (a) tenant-isolation read-path framing (sixth instance); (b) multi-scope-ownership-as-data-attribute-not-isolation-boundary canonical clause (sixth verbatim-equivalent instance); (c) `tax_treatment`-attribute-as-inclusion-filter (where §2.6 inherits §2.5-grade classes); (e) write-path-RLS shape extended to §2.6.2 commentary per §2.4.5 precedent; (f) staleness-live-read cross-tenant-signal-leak as new verification surface at §2.6.5. **Sensitive-data classes update for §4 matrix:** §2.6 adds two new classes — (1) Rebalancing Targets free-text commentary (medium-to-high sensitivity; F/CTO strategy reasoning + actionable financial decisions; tenant-scoped; XSS surface on rendered commentary) + (2) owner-identification trust-name string (low individual sensitivity but identity-correlate when aggregated; rendered on every PDF; XSS surface on rendered header) — plus one cross-cutting derivative-surface annotation across multiple existing classes (snapshot store denormalizes Realized + Unrealized Tax Liability + marginal-rate scalars + tax-character categorization + aggregate unrealized G/L by tax_treatment + NAV + allocation deltas + cash flow into single rows; retention sprawl + blast-radius widening + render-time staleness join compound the per-class isolation requirements). Running total entering §3 / §4: thirteen entries (twelve effective classes plus the cross-cutting derivative-surface annotation). **Seven Sec forward-looking comments** for §4 drafting + Phase 3 RLS surfaces (vs §2.5's 5): cross-tenant snapshot store leak; cross-tenant staleness-state read leak verification (most subtle in §2.6 suite — render-time join from snapshot's account_id to §2.4.4 credential-error state must enforce tenant_id); cross-tenant cron worker context isolation; owner-identification settings-store write-path input sanitization (XSS / SQL injection / oversize PDF-OOM / Unicode control / RTL / homoglyph); commentary write-path input sanitization (same battery + copy-from-prior-month must re-validate not bypass); PDF-generation worker-process tenant-isolation (shared Puppeteer / wkhtmltopdf worker pool must not leak fonts / DOM / auth headers / metadata across tenant renders); snapshot regeneration race condition (concurrent regenerations on same (tenant_id, target-month) must produce exactly one row with last-writer-wins or transactional rejection; cross-tenant concurrency must not mix). **Sec product-disclaimer decision:** ratify PM-default — §2.6.5 marker IS the disclaimer; no additional static financial-product disclaimer on every report (would train banner-blindness + dilute marker signal value). Revisit if share-report affordance ever lands.

**F/CTO product-decision locks this session** (8 substantive headline + multiple sub-decision PM-defaults all accepted): (1) ω-1 V1-fixed six-section order + Historical Expenditures inline; (2) σ-1 free-text user-authored + V1-fixed four sub-sections + `$ ReAlloc` side-by-side reference + plain text editor + blank+copy + author-before-generate; (3) τ-1 monthly cron + user-on-demand + cron schedule + target-month + idempotency overwrite + 3-state lifecycle + cron failure handling; (4) υ-1 in-app + PDF export + PDF transient download + render-from-snapshot; (5) φ-1 frozen-at-generation snapshot; (6) χ-1 indefinite retention; (7) ψ-1 single per-tenant owner-ID + snapshot-not-live owner-ID at render + ADR-005 third additive field; (8) α′-1 generate-with-markers + all four §2.4.4 states trigger + §2.6.2/§2.6.4 excluded + live-read on historical + PDF live-read. **Zero PM-lean overrides across all six stories** — PM-lean acceptance rate 3-for-3 on per-story §2.6.1/§2.6.2/§2.6.3 ratification triggered the **bulk-section-review scaling pivot at §2.6.4** per F/CTO direction (mid-session process change documented below).

**Bulk-section-review scaling pivot surfaced this session** — F/CTO direction at §2.6.4 ratify gate: "PM-leans tracking 3-for-3 with zero overrides; the per-story serialization is finding nothing, just adding turns." Process change adopted mid-section: PM bulk-drafts §2.6.4 reformat + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags as a single bundle; F/CTO reviews as a section-level pass; v2 revision only if overrides surface. Bulk closeout succeeded — F/CTO accepted bundle as-drafted, zero overrides triggered. **Pattern pinned for future sections:** when PM-leans track well (2+ consecutive per-story ratifications with zero overrides), CoS proposes bulk closeout for the remainder; F/CTO can redirect to per-story if surface-specific signal warrants. The one-question-at-a-time pacing memory pin remains the *default* for exploratory turns + sections where overrides are likely; bulk closeout is the *scaling release valve* when PM-lean acceptance signals consistency.

**PM body-format normalization required** — §2.6.4 v1 emitted as single continuous paragraph rather than multi-paragraph blockquote with `>` blank-line separators (the §2.6.1/§2.6.2/§2.6.3 + §2.5.x pattern). CoS flagged at relay; PM reformatted as §2.6.4 v1.1 during bulk closeout. **Pattern pinned for future sections:** PM bodies must use multi-paragraph blockquote format with `>` blank-line separators between bold heading-phrases. PM-spawn retry occurred at bulk closeout when initial response emitted meta-statement without content — `agentId` continuation via SendMessage not addressable from CoS context; re-spawn with full brief was the recovery path.

**ADR-005 settings store now carries three additive fields** (§2.3.2 planning targets + §2.5.2 bracket schedules + §2.6.4 owner-identification config); each ADR-005-extending field accumulated additively without ADR amendment. Architect Phase 3 routing flag (e) at §2.6 dedupes or splits this store; Sec re-engagement on the settings-UI plumbing surface triggered at §2.3.2 lock per Sec Task #23 forward-looking comment #3 is the canonical re-engagement framing, with each subsequent additive field treated as an extension within scope rather than a new Sec trigger.

**Engagement notes:** PM workhorse across 9 tasks (#45 structure, #46-#49 §2.6.1-§2.6.4 v1 bodies, #50-#53 bulk closeout reformat + §2.6.5 + §2.6.6 + routing-flags + acceptance-flags; PM-spawn retry at #50-#53 for content emission); Sec single-touch at-lock pass #54 per spawn-on-need framing (no two-touch needed — no mid-draft credential-handling surface emerged; α′-1 staleness-marker decision was operationally substantial but not credential-handling-novel); CoS bookkeeping + 4 ratify gates with F/CTO (structure, §2.6.1, §2.6.2, §2.6.3 individually; §2.6.4-§2.6.5-§2.6.6 + routing + acceptance as bulk bundle per F/CTO direction). Multi-version-body-revision pattern from §2.5 did NOT surface at §2.6 — every PM-lean was ratified first-pass, no v2 body revisions needed. Format-normalization v1.1 (§2.6.4) is the only non-content revision pass.

**Patterns established this session** for forward sections: (a) **bulk-section-review scaling pivot** — process change when PM-leans track 2+ consecutive ratifications with zero overrides; CoS proposes bulk closeout; F/CTO can redirect; one-question-at-a-time remains default for exploratory turns; (b) **PM body-format normalization** as a CoS responsibility — multi-paragraph blockquote with `>` blank-line separators is the canonical PRD body format; flag and request reformat if PM emits continuous-paragraph variant; (c) **PM-spawn retry pattern** — agentId-based SendMessage continuation not addressable from CoS context; full-brief re-spawn is the recovery path when initial PM response emits meta-statement without content; (d) **Sec axis elevation criteria** — when an axis is "substantial enough to track as its own axis rather than fold into [prior axis]," elevate to first-class Sec axis rather than annotation (snapshot-store-as-derivative-surface at §2.6 is the precedent); (e) **§2-series structural completion** — six PRD §2 stories locked closes the V1 user-stories series; next thread is §3 (Success metrics) / §4 (Security and compliance posture, Sec primary author per Task #54 framing) / §5 (V2 deferred candidates) / §6 (Out-of-scope) / §7 (Constraints).

**PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — seventh real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #18 §2.5 lock + ADR-006, PR #[TBD] §2.6 lock).

**Next thread:** **§3 / §4 / §5 / §6 / §7 drafting** to close Phase 1 Step 3. Most substantial: **§4 Security and compliance posture (Sec primary author per Task #54 mandatory-next-engagement framing)** — Sec lands the seven Phase 3 RLS test candidates + thirteen-class sensitive-data matrix + six canonical Sec axes as §4 body content. **§3 Success metrics** is a smaller PM-led section; **§5 V2 deferred candidates** and **§6 Out-of-scope** are PM-led inventory sections drawing from prior §2.X V2+ lists; **§7 Constraints** has three sub-stubs (7.1 Cost / 7.2 Scale / 7.3 Usage model). After §3–§7 lock, **Phase 1 Step 4 (Architectural overview)** opens — Sec conditional consult per Task #54 framing. Team-mode (`phase-1` team) per ADR-003 active throughout.

### v1.11 — 2026-05-17

**PRD §2.5 LOCKED** (2026-05-17) — fifth locked PRD section; first locked under the team-mode-with-multi-version-revision pattern that surfaced this session. §2.5 (Estimated taxes — Federal + California FTB primitive form per ADR-004 Decision D) drafted from a bare stub to a 5-story parity-grounded section across Tasks #35 (structure v1), #36 (structure v2 — bracket-aware correction), #37 (§2.5.1 body), #38–#41 (§2.5.2 / §2.5.3 / §2.5.4 / §2.5.5 body drafts + multiple v-revisions integrating F/CTO sub-decision locks one at a time per memory pacing), #42 (Sec at-lock pass), #43 (routing-flags + acceptance-flags block), and #44 (this PRD.md / DECISIONS.md / WORKFLOW.md integration). **Structure: 4 Primary + 1 Supporting**, mirroring §2.4 / §2.3 precedent. §2.5.1 *Tax-relevant income decomposition (Income / ST CG / LT CG)* — three-column current-tax-year decomposition at Sub-Cat granularity; user-marked Sub-Cat `tax_relevant` boolean + `tax_character` enum (5 V1 values: `ordinary` / `qualified_dividend` / `tax_exempt_interest` / `long_term_capital_gain_eligible` / `short_term_only`) per ζ-2 F/CTO lock; Federal routing rules embedded in body (qualified_dividend → Federal LT CG; tax_exempt_interest → excluded; others → ordinary); holding-period via existing-system `calculateSales`-equivalent L-Term? mechanism per η-1; calendar-year V1 scope per θ-1; live recompute. §2.5.2 *Tax-bracket inputs (Federal + California FTB parallel)* — V1 settings UI holds per-jurisdiction bracket schedules + standard deduction; Federal carries two schedules (ordinary + separate LT CG) per λ-default; CA single ordinary schedule per κ-default (CA treats LT CG as ordinary income); single-filing-status V1 per ι-default; settings store extends §2.3.2 planning-targets store per ADR-005 with richer field shape; δ-2 brief echo lock — each §2.5.3 tax table carries one-line applied-rate caption ("Federal ordinary: X% / Federal LT CG: Y%"; "California: Z%") paralleling §2.3.2 planning-targets caption-text pattern. §2.5.3 *Quarterly estimated payment computation + IRS/FTB account tracking* — densest §2.5 story; per-jurisdiction parallel tables (Federal + CA) structured per Finance_Report §11/§12 with Tax Balance Prior Year informational row + four quarterly Estimated Tax Payments + Sub-Total + YTD Paid + Estimated Funds Due gap; **progressive bracket math with standard deduction** as the computation engine (Federal ordinary schedule + Federal LT CG schedule + CA ordinary schedule, routed per §2.5.1 tax_character enum); μ-2 F/CTO lock — V1 ships bracket-derived expected-annual ÷ 4 quarterly installments only; **no safe-harbor floor computation in V1** (Tax Balance Prior Year row informational-only; safe-harbor refinement V2+); ν-1 overpayment-as-negative-single-line + ξ-1 reactive due-date surfacing carry as PM-defaults; IRS + FTB accounts as V1 instances of §2.4.2 manual non-Plaid accounts with §2.4.3 manual-transaction payment recording. §2.5.4 *Realized + Unrealized Tax Liability line items (NAV components)* — closes the §2.1.1 NAV definition + §2.1.5 composition buildup cross-reference contract; Realized = Federal + CA Estimated Funds Due gaps summed (single combined scalar per ρ-default); **Unrealized via ο-a F/CTO-locked simplified marginal × aggregate G/L** (`Federal_LT_CG_top_bracket_rate × aggregate_unrealized_G/L_taxable + CA_top_marginal_rate × aggregate_unrealized_G/L_taxable`) preserving F/CTO Task #2 close verification 2026-05-14 verbatim; **F/CTO 2026-05-17 override on Federal_top_marginal_rate sourcing = Federal LT CG top-bracket rate** (less-conservative parity choice over PM-default ordinary-top; aligns with F/CTO existing Est Taxes sheet treatment); π-default tax-advantaged-account exclusion (V1 includes only `taxable` accounts in Unrealized aggregation per ADR-002 §1.6 three-way tagging; `tax-deferred` + `tax-free` excluded); ρ-default single-line-per-NAV-component rendering; Sec product-disclaimer integrated at V1 boundary clause ("This estimate may understate actual tax owed if any portion of unrealized gain would be realized at short-term rates (ordinary income); users should treat the Unrealized Tax Liability as an LT-aware floor estimate, not a precise tax forecast"). §2.5.5 *Tax surfaces are mine, not anyone else's* (Supporting; γ read-path lock) — fifth instance of named-surface-scoped tenant-isolation pattern across PRD §2 (§2.1.7 + §2.2.4 + §2.3.5 + §2.4.5 + §2.5.5); fourth consecutive read-path-shape framing (§2.4.5 was write-path divergence); names §2.5.1 / §2.5.3 / §2.5.4 explicitly (NOT §2.5.2 — settings-UI write surface stays out of Supporting per γ rationale); **new clarity axis surfaced — three orthogonal query-layer attributes at V1** (`tenant_id` isolation + `scope` data label + `tax_treatment` inclusion filter on §2.5.4 Unrealized aggregation); scope-attribute-not-isolation-boundary clause verbatim-equivalent to §2.3.5 / §2.4.5 canonical formulation per Sec Task #23 endorsement. **Routing-flags block: 13 Architect items (densest §2 block to date — vs §2.4's 11) + 1 dropped flag (n §2.5.3-engine-reuse-for-Unrealized) + 1 PDF-verify-resolved bullet + 1 ADR-006-queued bullet + 1 Sec product-disclaimer-integration bullet + 1 Sec at-lock verdict bullet.** Carry-forward Architect flags (e) bracket-table-update cadence + (f) §2.5.2 settings-store dedup + (g) bracket-schedule routing logic location + (h) filing-status handling; new Architect flags (i) §2.5.3 computation engine storage/caching shape (PM lean i-2 on-demand under μ-2 simpler scope) + (j) IRS/FTB account semantics (PM lean j-1 standard-account-with-overlay) + (l) aggregate unrealized G/L computation surface + (m) tax-advantaged exclusion mechanism; §2.5.1 origin flags (a) Sub-Cat tax_character schema + (b) cross-source join (cash-flow + Sales) + (c) tax-year boundary + (d) holding-period source-of-truth. **F/CTO 2026-05-17 bracket-aware correction surfaced during structure-proposal v2** — ADR-004 Decision D's "Federal marginal rate input" / "separate marginal rate input" wording was audit-derived re-narration of incomplete reading; F/CTO direct workflow knowledge revealed existing Est Taxes sheet uses marginal bracket tables + standard deduction (bracket-aware progressive computation). **ADR-006 drafted alongside §2.5 lock** — two-axis amendment to ADR-004 Decision D input-layer characterization: Axis 1 (§2.5.2-scope) bracket schedules + standard deduction; Axis 2 (§2.5.1-scope) Sub-Cat `tax_character` enum with 5 V1 values + Federal routing rules. Both axes operationalize Decision D's "Primitive means" rather than expanding it (multi-state, non-US, lot-level features stay V2+ unchanged). Sec one-line sensitivity note woven into ADR-006: "data class #1 sensitivity incrementally higher post-amendment; storage / access-control posture unchanged." ADR-006 supersedes nothing; amends ADR-004 specifically (parallel to ADR-005's amendment of ADR-002 §1.2). **Sec Task #42 verdict: pass-with-comments, no veto, no required revisions** — fifth dual-axis Sec pass + **first tri-axis Sec pass** (axis (c) `tax_treatment`-as-inclusion-filter-not-isolation-boundary clarification NEW this section; endorsed as canonical for §4 verbatim promotion). **Six sensitive-data classes for §4 matrix** at Sec primary-author engagement: (1) tax-bracket-revealing data (§2.5.2 — upgraded sensitivity per F/CTO 2026-05-17 bracket-aware correction from original scalar form); (2) tax-character categorization patterns (§2.5.1 Sub-Cat enum); (3) marginal-rate scalars (Federal LT CG top-bracket + CA ordinary top-bracket — §2.5.4 inputs); (4) Realized + Unrealized Tax Liability scalar values (§2.5.4 NAV-components); (5) aggregate unrealized G/L by tax_treatment (§2.5.4 input); (6) NEW sub-class — §2.5.3 quarterly est-payment ledger + IRS/FTB account ledger state (class-1 derivative + behavioral correlate). **Five Sec forward-looking comments** for §4 drafting + Phase 3 RLS surfaces (see PRD §2.5 routing-flags block). **PDF-verify pass skipped per F/CTO 2026-05-17 direction** — nine items originally surfaced as parity-verify-against-Finance_Report-PDF-and-Est-Taxes-sheet candidates (ε / ι / κ / λ / ν / ξ / π + Federal LT CG sourcing parity + California quarterly cadence) resolved as F/CTO PM-default acceptance via direct-workflow-knowledge; verification deferred to V1 implementation if divergence surfaces against existing-system behavior. **F/CTO product-decision locks this session** (7 substantive sub-decisions + 2 v-revision-driven overrides): (1) **bracket-aware correction** (structure proposal v2) — overrode PM's audit-derived "marginal-rate input" framing; (2) ζ-2 Sub-Cat tax-character enum with 5 V1 values + Federal routing; (3) η-1 holding-period source = existing `calculateSales`-equivalent L-Term?; (4) θ-1 calendar-year tax-year V1; (5) δ-2 brief echo on §2.5.3 tables; (6) μ-2 bracket-only quarterly installments (NOT PM-lean μ-1 max-with-safe-harbor — F/CTO chose simpler V1); (7) ο-a simplified marginal × aggregate G/L preserving Task #2 verification; (8) **Federal LT CG top-bracket sourcing override on §2.5.4** (rejected PM-default Federal ordinary top — F/CTO chose less-conservative parity over PM's conservative default); (9) PDF-verify skip per F/CTO 2026-05-17 direct-workflow-knowledge acceptance. **No ADR-006-superseding scope expansion** — both axes operationalize Decision D "Primitive means" rather than expanding it; μ-2 + ο-a + PDF-verify-skip are within-Decision-D-scope simplifications, not amendments. **Engagement notes:** PM workhorse across 9 tasks (#35 structure v1, #36 structure v2, #37 §2.5.1 body v1, #38 §2.5.2 body v1, plus mid-task v-revisions of §2.5.1/§2.5.2/§2.5.3/§2.5.4 integrating F/CTO sub-decision locks one at a time per one-question-at-a-time memory pacing — §2.5.4 reached v3 with the Federal LT CG sourcing override); Sec spawn-on-need for Task #42 at-lock pass — single touch (no two-touch consult anticipated absent mid-draft credential-handling surfaces, per §2.4 Task #33 framing for §2.5; framing held); CoS bookkeeping across all 9 tasks plus the §2.5-lock cleanup pass orchestration. **Multi-version-revision pattern surfaced** as a recurring §2.5 workflow shape — F/CTO sub-decision lock turns triggered v2 / v3 body revisions of already-sent bodies (vs §2.3 / §2.4 pattern where most body drafts landed in single-version form). Memory pinned: when F/CTO over-rides PM-defaults at body lock turns, expect mechanical-override-pass v-revision; full-revised-body-for-self-contained-F/CTO-confirmation is the working pattern. **Audit-derived-ADR-text feedback applied retroactively** — ADR-006 documents that the original ADR-004 Decision D "marginal rate input" wording was audit-derived re-narration, not a deliberate F/CTO scope decision; future ADRs re-narrating audit findings should be verified against direct artifact inspection at body-drafting time. **Patterns established this session** for forward sections: (a) multi-version body-revision shape when F/CTO sub-decision locks chain mid-section (PM workflow: full-revised-body-for-each-revision with deltas-vs-prior-version section at end); (b) PDF-verify-skip-via-F/CTO-direct-workflow-knowledge as a §2.5-lock cleanup variant (vs prior §2.X pattern of F/CTO PDF inspection during body drafting); (c) tri-axis Sec verdict shape (tenant_id + scope + tax_treatment as three orthogonal query-layer attributes); (d) Sec product-disclaimer routing as a §2.5-lock-cleanup integration item separate from at-lock Sec pass; (e) audit-derived-ADR-text-correction-via-amendment as an ADR pattern (parallel to ADR-005 amendment of ADR-002 §1.2 but motivated by audit-derived-wording rather than parity-evidence). **PR #[TBD]** to be shipped via `/ship-branch` after this WORKFLOW.md changelog lands — sixth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock, PR #[TBD] §2.5 lock + ADR-006). **Next thread:** §2.6 (Monthly Report — canonical V1 deliverable, Finance_Report-shape) drafting. §2.6 is the home of the monthly Finance_Report generation surface that consumes §2.1 / §2.2 / §2.3 / §2.5 rendering data into the canonical PDF-equivalent deliverable F/CTO produces monthly today; per ADR-004 Decision D consequences §2.6 was queued as a new §2 section to formalize the Finance_Report-shape V1 deliverable as a first-class product surface; Sec re-engagement standard at-lock per Sec Task #42 framing; §4 Security and compliance posture remains Sec primary author surface and may interleave with §2.6 drafting given the running data-class set is now 6 + Plaid + write-path classes from §2.4.

### v1.10 — 2026-05-15

**PRD §2.4 LOCKED** (2026-05-15) — fourth locked PRD section; first to lock on 2026-05-15 (§2.1/§2.2/§2.3 all locked 2026-05-14). §2.4 (Cross-cutting stories — account onboarding, manual entry, re-auth) drafted from a bare stub to a 5-story parity-grounded section in one extended session via Tasks #26 (structure), **#27 (Sec early consult — NEW two-touch pattern)**, #28/#29/#30/#31/#32 (4 Primary + 1 Supporting story bodies), #33 (Sec at-lock verdict), and #34 (routing-flags + acceptance-flags block). **Structure: 4 Primary + 1 Supporting**, no renumbering required mid-section (vs §2.3's option-(A) renumbering). §2.4.1 *Plaid account onboarding and new-symbol surfacing* (OAuth flow with server-side `/link/token/create` + `/item/public_token/exchange`; tenant-scoped access-token persistence; account-share-decision authoritative storage with **Sec-(b)-2 explicit opt-in for newly-available institution accounts**; per-account scope/tax-treatment/account-type attribute setting with Plaid metadata as recommendation; **(iv) iv-1 notification queue + iv-3 sync-time Unsorted-Sub-Cat default + Plaid-metadata-as-recommendation-at-assignment-time** for new-symbol surfacing; symbol-registry-maintenance folded here per structure proposal). §2.4.2 *Manual non-Plaid account onboarding* (guided flow with no Plaid Link / OAuth / credential prompt; scope/tax-treatment/account-type/initial-value-as-of-date/Sub-Cat attribute setting; **inactive-flag V1 inclusion per existing-system parity**; bulk-import V2+; initial-value entry implemented as synthetic AcctSetup-flagged transaction to keep data model uniform with §2.3.1's transaction-to-bucket-assignment shape). §2.4.3 *Manual transaction entry (cash and AcctSetup non-cash events)* — **densest §2.4 body**; three sub-flows (cash transaction entry + AcctSetup non-cash event entry + Plaid-vs-manual reconciliation) with all **(i) locks** applied (Axis A2 silent dedup + on-demand audit log; **Axis B1+B2 V1 reconcile with B3 V2+** — closes parity-matrix open product decision #7 "Reconciled $ running balance" as V1-capability; Axis C1 implicit skip via delete with deleted/skipped view; Axis D hash composition Architect-flagged with PM-rec embedded — Plaid `transaction_id` primary + content hash secondary, splits as parent-child) and **(iii) locks** applied (iii-A-1 generic AcctSetup mode in same manual transaction UI with event subtype enumeration; iii-B-3 Plaid-surfaced and user-entered AcctSetup events as peers via hash + reconcile pattern); data-model expansion (6 additive sibling fields to §2.3.1's Sub-Cat assignment: `plaid_transaction_id`, `content_hash`, `skip_flag`, `reconciled_flag`, `reconciled_at`, `event_subtype`); lot-level tax features explicitly routed to §2.5 not §2.4. §2.4.4 *Plaid re-authentication and credential lifecycle* — closes ADR-002 §7.0 item 9 V1 PRD gap; **(ii) reactive cadence + Sec-recommended persistent in-app banner UI**; all six Sec Task #27 early-consult body clauses landed (three veto-eligible: server-side token lifecycle, access-token credential-class protection, **non-silent staleness across every consuming surface — headline V1 product commitment naming §2.1.2 / §2.1.5 / §2.2.2 / §2.3.2 / §2.3.4 / §2.6 explicitly**); four credential-error states distinguishable at data-model level; per-account connection-state UI surface with last-successful-sync timestamp + banner re-auth affordance. §2.4.5 *Onboarding, entry, and re-auth write paths are mine, not anyone else's* (Supporting) — **first write-path-shape Supporting story across PRD §2** (vs §2.1.7 / §2.2.4 / §2.3.5 read-path framing); shape divergence intentional and parity-justified (§2.4 is write-heavy); names §2.4.1–§2.4.4 explicitly per named-surface-scoping pattern; **write-path RLS symmetry clause as PRD-locked product commitment** (closes Sec Task #23 forward-looking comment #3 for entire §2.4 write surface, not just the §2.3.2 settings-UI plumbing it was originally scoped to); multi-scope-attribute clause verbatim-equivalent to §2.3.5 canonical formulation (fourth consecutive continuity instance); manual-entry write-path elevated-integrity-risk acknowledged with concrete example (5-year-ago `buy` at arbitrary price → cost-basis cascade). **Routing-flags block: 11 Architect/Sec-joint items + 1 Sec pass-recorded bullet — densest §2 routing-flags block to date** (vs §2.1's 6, §2.2's 6, §2.3's 9+1). Five flags carry explicit Sec-joint or Sec-led tags (#2 account-share-decision joint; #7 access token storage shape Sec-led; #8 credential-error state model joint; #10 manual-entry write-path integrity joint; **#11 Plaid webhook signature verification Sec-led** — new from Sec Task #33 verdict, not surfaced in Task #27 consult or any body draft, mandatory before V1 ship) — first instance of Sec-led routing flags in PRD §2 alongside the established Architect-led pattern, reflecting §2.4's credential-handling + write-path density. **NEW two-touch Sec engagement pattern adopted for §2.4** at F/CTO acceptance of PM structure proposal — Task #27 was the first non-verdict Sec consult in Phase 1 (Task #8 / Task #14 / Task #23 were all standard at-lock verdicts). Sec consult input shaped §2.4.1 + §2.4.4 + §2.4.5 body drafts before they were authored; Task #33 at-lock verdict verified all twelve consult clauses (six veto-eligible + six non-veto) landed correctly. Sec Task #33 explicitly endorsed two-touch pattern as "tightest yet" — engagement pattern carried forward as available-on-demand for future sections (not mandatory; §2.5 will use standard spawn-on-need at lock unless mid-draft surfaces warrant earlier consult per Sec Task #33 framing). **Sec Task #33 verdict: pass-with-comments, no veto, no required revisions** — fourth dual-axis Sec pass with axis (a) tenant isolation extended for write-path framing (§2.4.5 elevates RLS-on-writes from inferred architectural detail to explicit PRD-locked product commitment, names §2.4.1 / §2.4.2 / §2.4.3 / §2.4.4 mutation paths) and axis (b) multi-scope-attribute clause continuity confirmed verbatim-equivalent to §2.3.5 canonical formulation. **Three new sensitive data classes** for running §4 matrix: Plaid access tokens (credential class, distinct from data class); Plaid Item-state metadata (low sensitivity individually, behavior-correlate when aggregated — sync patterns reveal financial-activity timing); Plaid account-share-decision data. **New Phase 3 RLS test surfaces**: write-path RLS tests on §2.4.1 / §2.4.2 / §2.4.3 / §2.4.4 mutation paths; per-tenant Plaid Item table RLS (access tokens + Item-state metadata); per-tenant account-share-decision table RLS; tenant-scoped read on §2.4.3 sync-history audit log. **F/CTO product-decision locks this session** (6 substantive + sub-decisions): (1) (i) Plaid-vs-manual conflict resolution four-axis compound — substantive workflow context F/CTO surfaced reshaped PM's original A/B/C framing into a mechanism-rich hash-skip-reconcile model, PM re-framed as four product-surface axes A/B/C/D, F/CTO locked PM-rec across all axes; (2) (ii) reactive re-auth cadence + persistent banner UI; (3) (iii) AcctSetup UX two-axis compound — iii-A-1 generic mode + iii-B-3 both paths peers; (4) (iv) new-symbol surfacing three-piece compound — iv-1 notification queue + iv-3 sync-time Unsorted + Plaid-metadata-as-recommendation-at-assignment-time (F/CTO-originated compound, not PM-proposed; "having Unsorted assets probably breaks a few of the widgets" + "a recommendation would be helpful... when the user goes through the notifications to assign the fields" shaped the recommendation-at-assignment-time framing); (5) Sec-(b)-2 explicit opt-in for newly-available institution accounts (per Sec recommendation); (6) §2.4.2 inactive-account V1 inclusion. **No ADR-006 needed** — all §2.4 locks fold cleanly into PRD body + routing-flags per CoS + PM concurrence: (i) data-model expansion is additive to §2.3.1 (no §1.4/§1.5/§1.7 displacement); (iii) AcctSetup operationalizes ADR-004 Decision C additively (no §1.8 / Decision C displacement); (iv) operationalizes Decision C's hybrid clause with Unsorted bootstrap addition; Sec-(b)-2 + (ii) close ADR-002 §1.3 / §7.0 item 9 framings without amendment surfaces. ADR-005 precedent for dedicated-ADR-over-section-lock-absorption was the §1.2 non-goal amendment introducing a genuinely new V1 user-facing capability (settings UI); §2.4 introduces no parallel surface. **Engagement notes**: PM workhorse across 8 tasks (#26 structure, #28/#29/#30/#31/#32 story bodies, #34 routing-flags + acceptance-flags); Sec engaged twice (Task #27 early consult + Task #33 at-lock verdict) — first §2 section with two Sec touches per ADR-003 spawn-on-need extended for the two-touch pattern; CoS bookkeeping for the F/CTO (iv) compound that PM re-constructed mid-flow. **Patterns established this session** for forward sections: (a) two-touch Sec engagement available on-demand for high-credential-density sections (§2.4 prototype; §2.5+ use spawn-on-need at lock as default); (b) write-path-shape Supporting story alongside the established read-path-shape pattern (§2.4.5 is the prototype); (c) Sec-led routing flags alongside the established Architect-led pattern (§2.4 flags #7 + #11); (d) **F/CTO-originated compound product decisions** (the (iv) iv-1+iv-3+Plaid-metadata-as-recommendation compound was F/CTO-authored not PM-proposed; future sections may surface similar compounds and PM/CoS should be ready to re-frame). **PR #17** shipped via `/ship-branch` — fifth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005, PR #17 §2.4 lock). **Next thread**: §2.5 (Estimated taxes — Federal + California FTB primitive form per ADR-004 Decision D) drafting. §2.5 is the home of estimated quarterly tax payment computation, parallel Federal + California FTB marginal-rate inputs, IRS / FTB account tracking, Realized + Unrealized Tax Liabilities line items (already referenced from §2.1.1 NAV definition), and the V1/V2 boundary on lot-level tax features (FIFO/LIFO/specific-ID, wash-sale detection, Section 1256 60/40 — V2+ per ADR-002 §1.7 + ADR-004 Decision D "Primitive means" clause). Sec re-engagement: standard at-lock pass (no two-touch anticipated unless external tax-data API surfaces during drafting per Sec Task #33 framing); §4 Security and compliance posture remains Sec primary author surface and may interleave with §2.5 drafting given the three §2.4-contributed data classes need landing in §4 matrix.

### v1.9 — 2026-05-14

**PRD §2.3 LOCKED** (2026-05-14) — third locked PRD section. §2.3 (Spending and income categorization) drafted from a bare stub to a 5-story parity-grounded section in one session via Tasks #16 (structure), #17/#18/#20/#21/#22 (4 Primary + 1 Supporting story bodies), #19 (page-3 re-inspection), #23 (Sec pass), #24 (routing-flags + acceptance-flags block), and #25 (ADR-005 draft + this changelog + PR). **Structure: 4 Primary + 1 Supporting** after option-(A) renumbering (per §2.1.4-insertion precedent at v1.6) when §2.3.5 Historical Expenditures was added mid-section: original 3+1 (§2.3.1/§2.3.2/§2.3.3 Primary + §2.3.4 isolation Supporting) became 4+1 (§2.3.1/§2.3.2/§2.3.3/§2.3.4 Primary + §2.3.5 Supporting); chart story moved into §2.3.4 slot and isolation Supporting renumbered to §2.3.5 to preserve "all Primary then all Supporting" ordering matching §2.1/§2.2. §2.3.1 *Two-level cash-flow taxonomy and transaction-to-bucket assignment* (Decision C cash-flow half parallel to §2.2.1's asset half; V1 data model + F/CTO-seeded Master.CashFlowCategories at bootstrap + V1 per-transaction Sub-Cat assignment UI + recurring-vendor inference V1 with Plaid-category-as-default; user-editable taxonomy CRUD V2+). §2.3.2 *Cash flow categorization across accounts by multi-period* (canonical Finance_Report page-6 surface — Income + Expenses two-section rendering with flat Sub-Cat rows; 7-column Category/Month/Q1-Q4/YTD shape with Month visual emphasis; OtherCF omitted from cross-account rollup but renders in §2.3.3 — asymmetry intentional per existing-system parity; **planning-targets static reference-value rendering V1 (per ADR-005)** as inline caption text under section titles with no variance/alert mechanic + V1 user-editable settings UI). §2.3.3 *Per-account cash-flow drill-down* (per-account-scoped peer of §2.3.2; **3 Cat sections** Income/OtherCF/Expenses adding OtherCF vs §2.3.2's 2-section; **as-of-date toggle V1** per F/CTO (a) lock with backend-replacement rationale; replacement-not-layered framing — §2.3.3 is V1 replacement for the existing per-account Cash Flow sheets, not a layered alternative). §2.3.4 *Historical Expenditures* (**expenses-only time-series chart** caught via PDF inspection during §2.3.2 work — rolling 5-year window of monthly bars + 12-month rolling-average overlay inflation-normalized to today's $ matching §2.1.2's chart-overlay convention; **F/CTO asymmetry rationale woven into V1/V2 clause** — capital-gains-from-rebalancing partially fund expenses → expense time-series isolates the expense signal cleanly while income mirror would entangle with realization decisions; **income time-series + multi-year historical income recordkeeping V2+** per (α) lock; cross-section structural parallel: §2.3.4 is to §2.3.2 what §2.1.2 is to §2.1.1). §2.3.5 *Cash flow categorization is mine, not anyone else's* (Supporting; third instance of named-surface-scoped tenant-isolation + multi-scope-aggregation pattern across §2 after §2.1.7 + §2.2.4; names §2.3.2 + §2.3.3 + §2.3.4 explicitly; **scope-attribute-not-isolation-boundary clause endorsed by Sec Task #23 as canonical for §4 verbatim**). **Routing-flags block:** 9 Architect items (cash-flow taxonomy data model with §2.2.1 overlap; transaction-classification heuristic mechanism per inference V1 lock; cross-account per-period cash-flow aggregation query path; V1 settings UI plumbing for planning targets — Sec re-engagement triggered; planning-targets storage shape; **as-of-date as system-wide query-time parameter — Phase 3 RLS test obligation attached**; per-account scoping query path; drill-down view capability paralleling §2.2.3 flag; V1 expense-transaction data retention horizon ≥ 5 years with differential retention by Cat) plus 1 CPI-U cross-ref (no new flag — four V1 surfaces now share one CPI-U source decision: §2.1.2 + §2.1.3 + §2.1.4 + §2.3.4) plus 1 Sec pass-recorded bullet. **Sec Task #23 verdict: pass-with-comments, no veto, no required revisions** — third dual-axis Sec pass, tightest yet; §2.3.5's scope-attribute clause endorsed verbatim for §4 promotion. New axis vs §2.1.7 + §2.2.4: §2.3.3 as-of-date toggle as first user-supplied query-time parameter on multi-tenant data path in V1 — product-level pass with Phase 3 RLS test obligation. **Three new sensitive data classes** added to running §4 matrix: (1) per-transaction merchant/vendor identifier data — highest-sensitivity addition (PII-adjacent + behavior-revealing); (2) user-authored planning targets per ADR-005; (3) derived cash-flow categorization patterns / assignment-history layer. **Three forward-looking comments captured**: Phase 3 explicit RLS test surface for as-of-date-parameterized query path (joins §2.1.5 composition-view + §2.2.1 per-tenant taxonomy registry test surfaces from prior passes); Architect storage-shape decision on merchant/vendor access controls beyond tenant RLS; Sec re-engagement when §2.3.2 settings-UI plumbing surfaces. Sec re-engagement mandatory at §2.4 + §4; Sec is primary author at §4. **ADR-005 — single ADR-002 §1.2 amendment** formalized: planning-targets V1 static reference-value rendering as parity-preserve with existing Finance_Report (no variance/alert/budget-tracking mechanics — those remain V1 non-goals) + V1 user-editable settings UI (first concrete V1 surface needing a user-editable settings store). CoS chose dedicated-ADR over section-lock-absorption for (a) DECISIONS.md discoverability and (b) consistency with ADR-004's amendment-by-ADR pattern. **Scope note on §1.2 amendments NOT in ADR-005**: §2.3.1 inference layer V1 and §2.3.4 expenses-only chart V1 are both technically §1.2 amendments in shape ("recurring-transaction detection" and "category-level trend charts" listed as V1 non-goals in original §1.2) — not consolidated because §2.3.1's inference is a sub-decision within a V1-required surface (not a stand-alone expansion) and §2.3.4 was caught via PDF inspection as parity-grounded existing-system surface (not a V1 expansion). Both documented in §2.3 PRD traces + routing-flags; ADR-005 covers only planning-targets because that introduces a genuinely new V1 user-facing capability (the settings UI). **Three PDF-inspection-first course-corrections in §2.3** — fourth/fifth/sixth instances of the lesson pattern across §2.1/§2.2/§2.3: (1) OtherCF rendering discrepancy between parity-matrix line 60 (3 Cats per-account) and lines 103-104 (only Income + Expenses enumerated as Finance_Report sections) resolved at §2.3.2 v1 via PM PDF inspection — OtherCF absent from page 6, present on §2.3.3 per-account drill-down; (2) F/CTO-surfaced page-3 income chart that didn't exist — PM full-PDF sweep ruled out income time-series in the canonical Finance_Report (page 3's "Category Totals" chart is §2.1.2 NAV-by-Cat asset-side with legend names Real Estate / Cash / Bonds / Equities / Alternatives / Liabilities; "Category" overloaded between asset Cat and cash-flow Cat mental models); F/CTO confirmed scenario (i) + (α) on follow-up clarification; (3) $30k Y-axis figure caught by CoS in §2.3.4 trace and redacted to structural framing per v1.8 redaction policy. **CoS-side learning captured**: page-range-scoped briefs miss cross-page topic content — my §2.3.2 brief scoped PDF inspection to pages 6+ (because §2.3 territory was understood as starting after §2.2 on pages 4-5) and missed the page-7 Expense Totals chart at first scan (caught at §2.3.2's PDF-inspection-first pass anyway, surfaced as §2.3.5 → §2.3.4 after F/CTO call). Forward briefs scope PDF inspection by topic, not by sequential page range. **Minor invention caught**: PM introduced "V2 user-editable per-account taxonomy overrides" V1/V2 boundary clause in §2.3.3 not parity-grounded (existing system soft-links Master.CashFlowCategories into all per-account workbooks; no per-account taxonomy variation in active use). CoS flagged for removal; F/CTO chose to keep as benign V2 boundary clause. Pattern: CoS scrutiny role caught non-parity-grounded scope drift; F/CTO retained editorial authority on the call. **F/CTO product-decision locks this session** (5 substantive): (1) planning-targets (a)(i) — V1 static reference rendering + V1 user-editable settings UI (formalized via ADR-005); (2) inference layer V1 — Plaid-category-as-default + recurring-vendor inference (per §2.3.1 accept-as-drafted); (3) as-of-date toggle V1 on §2.3.3 — with backend-replacement rationale (V1 replaces parts of Master / Per-Account Workbooks / Asset Summary per §8 drop-replace migration pattern → year-end reconciliation can't fall back to existing system in V1); (4) Historical Expenditures = §2.3.4 V1 Primary via option-(A) renumbering — F/CTO-confirmed scenario (i)/(α) ruled out income time-series chart in V1 with substantive rebalancing-realization-funds-expenses asymmetry rationale; (5) per-account-taxonomy-override V1/V2 sentence kept in §2.3.3 trace per F/CTO editorial call. **Engagement notes**: PM workhorse across 8 tasks (#16 structure, #17/#18/#20/#21/#22 story bodies, #19 page-3 re-inspect, #24 routing-flags + acceptance-flags block); Sec spawn-on-need for Task #23 only — Sec teammate spawned fresh in this session (vs §2.2's Task #14 where Sec was already-spawned-and-woken-via-SendMessage from §2.1's Task #8) reflecting fresh-session implication of in-process team store; engagement pattern (PM workhorse + Sec spawn-on-need-at-section-lock) per ADR-003 continues to scale. **PR #16** shipped via `/ship-branch` — fourth real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2 lock, PR #16 §2.3 lock + ADR-005). **Next thread**: §2.4 (Cross-cutting stories — account onboarding, manual entry, re-auth, AcctSetup non-cash events, Plaid-pulled-vs-manual transaction reconciliation, Plaid re-auth credential lifecycle, manual transaction entry mechanics) drafting. §2.4 has a heavier security surface than §2.1-§2.3 — touches authentication, OAuth/credential handling, and write paths — Sec re-engagement is mandatory at §2.4 lock per Sec Task #23 forward-looking note; Sec may need to engage earlier than section-lock if Plaid credential-handling sub-decisions surface during drafting.

### v1.8 — 2026-05-14
**PRD §2.2 LOCKED** (2026-05-14) — second locked PRD section. §2.2 (Asset allocation) drafted from a bare stub to a 4-story parity-grounded section in one session via Tasks #9 (structure), #10/#11/#12/#13 (4 story bodies), #15 (routing-flags + acceptance-flags drafting), and #14 (Sec Reviewer pass). PR #14 (`8272613`). **Structure: 3 Primary + 1 Supporting.** §2.2.1 *Two-level asset taxonomy and holding-to-bucket assignment* per ADR-004 Decision C (V1 taxonomy data model + F/CTO-seeded at bootstrap + V1 holding-assignment UI for per-symbol securities and per-account manual assets; V2 user-editable CRUD UI). §2.2.2 *Non-RE allocation table* per ADR-004 Decision A (5-column structure `% Target / % Alloc / $ Target / $ Alloc / $ ReAlloc`; sign convention positive = underweight; Sub-Cat granularity grouped under Cat-group headers per existing-system parity; Real Estate excluded per F/CTO's non-liquid-asset rationale; **Liabilities Cat group flagged as intentional V1 extension** with F/CTO "leverage options" rationale — not in existing Finance_Report's table; auto-suggestions V2+). §2.2.3 *US Equity sub-allocation* (drill-down into §2.2.2's "US - Sector Diversified" Sub-Cat row; 12 rows = 10 US sectors `[01] Basic Materials` through `[10] Utilities` plus 2 non-sector US Sub-Cats `Index Non-Sector` and `Growth Non-Sector`; denominator is Total US Equity; ex-US sub-allocation V2). §2.2.4 *Allocation is mine, not anyone else's* (Supporting, parallel to §2.1.7: tenant isolation per ADR-002 §1.4 + multi-scope full-household aggregation default per ADR-004 Decision B; per-scope reporting + scope-aware filtering UI V2+; references §2.2.2 + §2.2.3 by name in body — Sec verdict flagged this named-surface scoping as a positive tightening vs. §2.1.7's generic "net worth view" framing). **Routing-flags block:** 6 Architect items (multi-level user-scoped taxonomy data model from §2.2.1; Sub-Cat-aware holdings aggregation query path from §2.2.2 + §2.2.3; target allocation storage shape from §2.2.2 — bidirectional architectural-overlap note with the taxonomy flag; Real Estate / non-liquid Cat semantics from §2.2.2; Liabilities-as-Cat semantics from §2.2.2 — asymmetric data flow with §2.1.5 Debt subtotal; drill-down view capability from §2.2.3) plus 1 Security Reviewer pass-recorded bullet. **Sec Task #14 verdict: pass-with-comments, no veto, lighter than Task #8** as predicted; dual-axis assessment from Task #8 (tenant isolation per ADR-002 §1.4 + scope-attribute-not-isolation-boundary per ADR-004 Decision B) carried forward as precedent; both axes confirmed. Three cross-section notes (no flags) extend Task #8's forward-looking comment set: (1) §2.2.1 AssetDB-style symbol→Sub-Cat registry must be per-tenant in V1 — adds a second explicit Phase 3 RLS test surface alongside §2.1.5 composition-view query path; (2) target allocations per Sub-Cat are a new sensitive data class for PRD §4 data-sensitivity matrix — matrix now includes account balances + holdings/tickers/quantities + marginal tax rates + target allocations / portfolio strategy; (3) §2.2.2 Liabilities Cat group leverage-management surface exposes leverage strategy alongside current debt position — useful callout for §4 matrix. Sec's existing §2.4 / PRD §4 re-engagement triggers cover §2.2's data-class extensions; no new re-engagement triggers. **Mid-section PDF-inspection course-correction:** §2.2.2 v1 and §2.2.3 v1 proposals had three parity drifts (Cat-level vs Sub-Cat granularity; sectors-only vs US-Equity scope; sector-total vs Total-US-Equity denominator) plus a Liabilities-parity-claim drift (PM had presented Liabilities Cat as parity-grounded when it's an intentional V1 extension). F/CTO direct read of `Finance_Report_2026_04.pdf` pages 4-5 surfaced all four; v2 revisions of both stories landed before commit. Second instance of "PDF inspection-first" lesson after §2.1.3 v3; captured in task metadata for future reference. **New project-wide policy adopted in-session:** PRD parity-evidence redacts concrete $ figures from versioned artifacts (PRD.md is committed to GitHub; $s from F/CTO's existing personal financial data don't live in committed history). Structural detail (column structure, row names, %s, Cat/Sub-Cat names) retained. Memory-pinned at CoS for forward sessions. Applied retroactively (§2.2.2 v2 traces stripped of cell-level $ values during application); §2.1 verified clean. **Engagement notes:** PM as workhorse across 7 tasks (#9 structure, #10/#11/#12/#13 story bodies, #15 routing-flags block; plus v2 revisions of #11/#12 mid-flow); Sec re-engaged for Task #14 only (already-spawned teammate from Task #8 woken via SendMessage rather than re-briefed). Engagement pattern (PM workhorse + Sec spawn-on-need at section-lock) continues to scale per ADR-003. **PR #14** shipped via `/ship-branch` — third real use of the skill (PR #10 §2.1 cross-check, PR #12 §2.1 final lock, PR #14 §2.2). **Next thread:** §2.3 (Spending and income categorization) drafting — structurally similar to §2.2 with a parallel two-level taxonomy (Income / Expenses / OtherCF / AcctSetup per parity-matrix line 121) but cash-flow framing instead of allocation. Likely faster than §2.2 given the pattern is now established.

### v1.7 — 2026-05-14
**PRD §2.1 LOCKED** (2026-05-14) — first locked PRD section. Final-lock checklist from v1.6 cleared via Tasks #6/#7/#8 landing in PR #12 (`414a82d`). **Task #6 (§2.1.2 chart-overlay extension):** body extended from 1 sentence to 4 (granularity hybrid preserved + inflation-adjusted overlay clause added + combined rationale + V1/V2 boundary on rolling-window dimension). Overlay specifics: second NAV line on the same chart, normalized to today's $ value using CPI-U, visually distinct from the nominal line, 60-month rolling window, drawn simultaneously not toggled — direct parity with the existing Finance_Report Category Totals chart on page 3. Today's-$ basis explicitly distinguished from §2.1.3 / §2.1.4 prior-Year-End basis in traces: two different inflation surfaces, two different normalization points, both intentional in the existing system. Single CPI-U series feeds all three surfaces (§2.1.2 chart, §2.1.3 panel, §2.1.4 reference-values table); one Architect CPI-U sourcing decision serves all three. **Task #7 (§2.1.5 composition NAV-buildup extension):** §2.1.5 restated as a single integrated table matching the existing Finance_Report Account Holdings layout (parity-matrix line 99) — six-subtotal buildup sequence (Total Non-RE → Gross Total → Debt → Realized Tax Liabilities → Unrealized Tax Liabilities → Net Assets Value (NAV) at the foot); per-row format adds current value + unrealized gain/loss columns (parity-grounded V1 surface elevation, accepted into scope by F/CTO); Real Estate as distinct group within asset half (required for the Total Non-RE subtotal transition); drill-down preserved (collapsed-by-default, expand-on-demand) over strict-parity all-accounts-visible per F/CTO SaaS-UX justification. Makes the four-component NAV definition from §2.1.1 visually traceable from its parts. **Task #8 (Security Reviewer pass on §2.1.7):** first real Security-Reviewer-as-teammate exercise post-ADR-003 smoke-test. Verdict: **pass-with-comments, no veto, no required revisions.** Dual-axis assessment captured: (a) tenant-isolation language ("no possibility of another user's data appearing") holds against ADR-002 §1.4's tenant_id + RLS commitment when read as user-facing product expectation — the system must back the claim, which is Architect Phase 3 work; (b) multi-scope-attribute-not-isolation-boundary confirmed via three independent pieces of prose evidence — aggregation-as-default + ownership-label examples + explicit data-attribute framing. No conflation of scopes with tenants anywhere in §2.1 or §1.4 deferrals. **Three cross-section notes (no flags, no veto):** §2.1.1 Decision D marginal-rate storage as new sensitive-data class under standard RLS posture; §2.1.5 per-account drill-down + unrealized-G/L exposure under same tenant-isolation treatment; CPI-U series public reference data, no security surface. **Three forward-looking comments captured in Task #8 close metadata** for downstream phases: (1) §2.1.5 composition-view query path on the explicit test surface in Phase 3 (ARCHITECTURE.md RLS policy design per ADR-002 §8.0, not happy-path single-tenant smoke test only); (2) Decision D marginal-rate storage as an explicit callout in PRD §4 (Security & Compliance posture) when it drafts — "tax-bracket-revealing data" sub-class warrants explicit mention; (3) Sec re-engages for §2.4 (cross-cutting Plaid + manual entry) / PRD §4 (Security & Compliance posture) drafting; no re-review needed for §2.1.2 chart-overlay or §2.1.5 composition extensions unless drill-down semantics change. **Routing-flags block updates:** PM-follow-up bullet for §2.1.2 chart-overlay removed (obviated by Task #6). Security Reviewer bullet refreshed with dual-axis pass-recorded language (tenant isolation + scope-attribute-not-isolation-boundary; pass-with-comments stamp). Block stands at 4 Architect items + 1 Security Reviewer pass-recorded stub. **Acceptance flag** flipped from "draft, not locked" to "locked as of 2026-05-14 (Security Reviewer pass-with-comments per Task #8)" — Architect routing flags still resolve during Phase 3 and surface in Appendix B before Architect sign-off; they don't block §2.1 lock at the PRD level. **§2.1 section state at lock:** 7 stories (5 Primary: §2.1.1 NAV definition, §2.1.2 trajectory + chart overlay, §2.1.3 multi-horizon delta panel, §2.1.4 reference values, §2.1.5 composition NAV-buildup; 2 Supporting: §2.1.6 market value, §2.1.7 isolation + multi-scope aggregation). All stories parity-grounded to existing Finance_Report surfaces (with explicit V1/V2 boundaries on §2.1.2/§2.1.3/§2.1.4/§2.1.7) and to ADR-004 Decisions A/B/C/D where applicable. **Engagement notes:** Security Reviewer first real exercise as a teammate in the `phase-1` team — joined for Task #8 only, produced verdict in a single turn with comprehensive cross-section read. Engagement pattern (PM as workhorse + Sec spawn-on-need-at-section-lock) per ADR-003 worked cleanly. **PR #12** (`414a82d`) shipped via `/ship-branch`. Second §2.1-scoped PR in this two-PR pair (PR #10 = Tasks #1–#5 cross-check; PR #12 = Tasks #6–#8 final lock); v1.7 bump (this entry) is the v1.6-pattern companion. **Next thread:** §2.2 (asset allocation) drafting — the section whose original drafting attempt triggered the script-audit pivot back in v1.5. With ADR-004 grounding + parity-matrix authority + §2.1 lock pattern established, §2.2 should run smoother.

### v1.6 — 2026-05-14
Phase 1 Step 3 PM cross-check Tasks #1–#5 landed in a single PR (PR #10, `6955d73`); §2.1 expanded from 6 to 7 stories with renumbering; §2.1 final-lock checklist down to three parked items. **§1.2 attribute #5 strengthened** for ADR-004 Decision C user-side grounding — two-level Cat × Sub-Cat taxonomy made explicit with concrete examples (Equity → US-Index_Non_Sector; Bonds → T-bill; Alternatives → REIT), both asset and cash-flow taxonomies named, new active-assignment clause ("they assign holdings and transactions to their buckets themselves … the categorization grammar is theirs to define and theirs to apply") grounding the V1 holding-to-bucket assignment UI as an archetype property. F/CTO option-(a) routed Decision C grounding to attribute #5 (categorization) rather than attribute #4 (decisional posture), preserving #4 unchanged. **§2.1.1 NAV definition** extended to full tax-adjusted per Decision D: `Gross Asset Value − Debt − Realized Tax Liabilities − Unrealized Tax Liabilities`. NAV introduced as formal term in the story title; "net worth" retained as casual reading throughout §2.1. Parity verified against existing Google Sheet — Unrealized Tax Liab = marginal-rate × aggregate-unrealized-G/L primitive form; Realized Tax Liab = accrued Federal + California estimated-tax obligation net of payments already made. **§2.1.3 multi-horizon NAV-delta panel** landed after three revisions and one mid-task parity course-correction. Final shape: five fixed horizons (Month / YTD / 1-Year / 3-Year / 5-Year); both dollar and percent per horizon (V1 expansion beyond strict existing-system parity, F/CTO option-(b); existing system shows percent only); Inflation Adjusted column side-by-side for 1Y/3Y/5Y horizons only, prior-Year-End reference basis matching the existing panel footnote. **Parity course-correction:** PM v2 proposed dropping the panel inflation column entirely on the basis that parity-matrix line 100 looked like an audit-phrasing slip; F/CTO direct PDF inspection of `Finance_Report_2026_04.pdf` page 3 confirmed line 100 was accurate and PM's read was the error. Lesson noted: when ground-truth artifacts are available, prefer direct inspection over abstract reading of secondary descriptions. **§2.1.4 NEW Primary story** — *NAV at three reference dates* — landed. Three rows (This Month / Prior Month / Prior Year-End) × two dollar columns (`NAV` nominal + `NAV — Prior Yr $` inflation-adjusted to prior YE); all six cells populated. Surfaced as a candidate sibling during Task #3, queued as Task #5 after F/CTO confirmed sibling warrant rather than V2 deferral. **Option-(A) renumbering** applied: current §2.1.4 (composition) → §2.1.5; §2.1.5 (market value) → §2.1.6; §2.1.6 (isolation) → §2.1.7; two reference numbers updated in Open-routing-flags and Acceptance-flags blocks. Adjacency rationale: §2.1.3 and §2.1.4 are sub-surfaces within the same Finance_Report "NAV Performance" section and pair as deltas-over-horizons + values-at-anchor-dates. **§2.1.7** (was §2.1.6) extended for Decision B multi-scope full-household aggregation: V1 default = single full-household NAV across all ownership scopes the user holds (e.g., Rich / RichMoskoTrust / IRA / HSA); per-scope reporting and scope-aware filtering UI explicitly V2+; data model carries scope on each account from V1 so the V2 expansion ships without a data migration. Body split into four sentences (tenant isolation + multi-scope aggregation + combined rationale + V1/V2 boundary) for legibility post F/CTO density tweak. Security Reviewer flag scope expanded to additionally confirm scopes are treated as user-owned data labels, not as V1 isolation boundaries (scopes are not tenants). **Open routing flags block expanded** with three new items: Architect — historical NAV depth in V1 (whether locked V1 = yes — V1 imports the existing Google Sheet's monthly NAV history Dec-2015 forward so the 5-Year horizon is meaningful at launch; how routed to Architect Phase 3); §2.1.2 chart-overlay inflation-adjusted PM follow-up (single line normalized to today's $, 60-month rolling window per parity-matrix line 77); CPI-U source decision (live API vs. manual entry, parity-matrix open product decision #10, Architect). One CPI-U series feeds both §2.1.2 chart-overlay and §2.1.3 panel — one Architect decision serves both surfaces. **Conceptual axis division accepted** between Decision D (= §2.1.1 NAV-calculation jurisdiction, Federal + California) and Decision B (= §2.1.7 tenant/household scope); different axes, do not merge. **Engagement pattern:** first real team-mode exercise post-ADR-003 smoke-test. `TeamCreate phase-1` (generic name, persistent across remaining Phase 1 steps per F/CTO preference, not step-scoped); PM as workhorse teammate with persistent context across all five tasks; peer messaging via SendMessage; CoS as main-session team lead. Pattern worked as designed; relay format `[CoS]:` / `[PM]:` per memory feedback preserved. **§2.1 final-lock checklist** now stands at three parked items: (1) §2.1.2 chart-overlay extension (PM follow-up in PRD block), (2) §2.1.5 (renumbered composition) extension — Gross → Debt → Realized Tax Liab → Unrealized Tax Liab → NAV intermediate subtotals matching the existing Finance_Report Account Holdings layout (currently in Task #2 close metadata; promotes to PRD block at §2.1 lock per F/CTO confirmation), (3) Security Reviewer pass on §2.1.7 (mandatory before §2.1 locks; covers tenant isolation + scope-attribute-not-isolation-boundary review). **PR #10** shipped via the `/ship-branch` skill — first real use post-codification (PR #9, v1.5 bump cycle).

### v1.5 — 2026-05-13
Phase 1 Step 3 in progress with a mid-Step-3 script-audit pivot landed; re-orient infrastructure upgraded. **Script-audit pivot:** §2.2 (asset allocation) drafting under the preliminary-findings-grounded model exposed a drift when F/CTO surfaced an existing two-level asset-categorization taxonomy in active use as a hard V1 backend requirement, revealing that abstract-from-findings drafting was generating requirements F/CTO already had concrete system-grounded answers for. CoS-led functional audit of five existing-system artifacts (MoskoFinance Apps Script, Master Sheet, representative per-account workbook, Asset Summary aggregator, Finance_Report Google Doc) produced **`docs/v1-parity-matrix.md`** — 275-line authoritative V1 capability scope mapping every existing-system capability to V1 preserve / V1 new-decision / V2 defer / drop with rationale. **ADR-004** consolidated four amendments to ADR-002: Decision A (rebalance-target visualization — % target vs % actual + `$ ReAlloc` dollar-delta — is V1; auto-generated rebalance *suggestions* remain V2+); Decision B (multi-scope ownership Rich/Trust/IRA/HSA within a single tenant is a V1 data attribute; per-scope reporting V2+; default report scope full-household); Decision C (two-level user-meaningful asset taxonomy Cat × Sub-Cat in V1 via hybrid operationalization — backend-correct + F/CTO taxonomy seeded + V1 bucket-assignment UI + V2 CRUD UI); Decision D (estimated quarterly tax payments V1 in primitive form — Federal + California FTB parallel marginal-rate inputs, quarterly payment computation, IRS/FTB account tracking). **PRD draft state on disk:** §1 vision + 7-attribute *self-directed multi-account owner* target-user archetype + 4-subsection deferrals locked; §2.1 net worth six user stories drafted (§2.1 draft-not-locked pending Security Reviewer pass on multi-tenant isolation in story 2.1.6); §§2.2–§7 stubbed; §8 V1 milestone framing with drop-replace migration pattern queued per ADR-004 forward reference as the answer to ADR-002 §7.0 item 7 ("V1 done" definition). **PM cross-check queued** for resumption: §1.2 attribute #4 reframe (Decision C user-side grounding); §2.1 NAV-with-tax-liability definition extension, multi-horizon headline-delta × inflation-adjusted extension, scope-awareness on 2.1.6 (Decisions B / D). **Re-orient prompt v2** (`docs/handoff-prompts.md`, PR #7): main-anchored summary; reads `CLAUDE.md` → `WORKFLOW.md` → `DECISIONS.md` → `PRD.md` / `ARCHITECTURE.md` in CLAUDE.md's prescribed order; `git worktree list` + `git log --all --not main` scan with "list discrepancies and ask before merging" instruction. Motivated by a real miss earlier this session where the prior short-form prompt failed to surface the unmerged `claude/nice-bohr-80d2ec` branch containing PRD.md + ADR-004 because `git status` was clean on `main`. **Operational notes:** PM resumes section-by-section pacing post-audit; the script audit was CoS-orchestrated (not PM-led) within the same Phase 1 work; team-mode initialization (`TeamCreate phase-1` — generic per F/CTO preference for persistence across remaining Phase 1 steps, not step-scoped) deferred to the next session resuming §1/§2.1 cross-check.

### v1.4 — 2026-05-11
Phase 1 Step 2 closed; engagement pattern shifted for Step 3 onward. Step 2 ratification of preliminary product findings completed across 2026-05-09 through 2026-05-11; F/CTO-signed-off verdicts for all six findings plus twelve sub-decisions captured in ADR-002. Notable Step 2 expansions vs. PM's tighter scope recommendations: transaction-tracking expanded to cover Plaid Investments alongside Transactions across depository / credit / investment / loan-balance / crypto accounts (ADR-002 §1.3); manual non-Plaid accounts and manual transaction entry added as V1-initiative scope with V1.0/V1.1 sequencing deferred to Phase 4 (§1.5); cost basis and unrealized G/L pulled into V1 with average-cost-fallback realized G/L marked "estimated" (§1.7); securities general principle treating all Plaid-surfaced investment activity uniformly at the transaction level with type as a categorization attribute (§1.8); multi-tenant data model from day one (§1.4). Terminology refinement: "permanent non-goals" relabeled "out-of-scope for this PRD lifecycle" (§3.0). Subagent engagement pattern shifted for Step 3 onward: **ADR-003 adopts Claude Code Agent Teams** (experimental, gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) as the multi-agent coordination primitive. Smoke-tested in Claude Desktop (in-process backend; SendMessage works; TaskList not surfaced; teammates default to non-1M-context model — mitigations captured in ADR-003 §3). Five teammate-eligible agent files (PM, Architect, Security Reviewer, UX Designer, Visual Designer) received a "team-mode preamble" instructing them to load SendMessage via ToolSearch as first action when spawned as a teammate. Chief of Staff agent file unchanged — CoS-as-main-session is always the lead, never a teammate. The "Subagent invocation pattern" subsection in Phase 1 detailed steps revised to reference team mode for Step 3.

### v1.3 — 2026-05-09
SessionStart hook for automatic re-orientation. Added `.claude/settings.json` with a SessionStart hook that injects the *Subsequent sessions* re-orient prompt from `docs/handoff-prompts.md` as additional context at session start — so Claude performs the four-step orient (phase, role, next deliverable, changelog deltas, plus git status if a feature branch is active) before responding to the user's first message of each session, no manual prompt-pasting required. The hook re-reads `docs/handoff-prompts.md` at fire time; editing the prompt source changes auto-orient behavior without touching `settings.json`. Includes adaptive flagging: when WORKFLOW.md's header indicates a phase transition is pending, Claude appends a one-liner pointing at the phase-transition workflow prompt — detection happens in Claude's response, not in shell, so it's robust to header-format drift. `settings.json` is project-shared (committed); personal overrides belong in `.claude/settings.local.json` (gitignored). Operational gotcha discovered during validation and worth flagging for future-self: worktrees are materialized from the local `main` checkout's current commit, so failing to `git pull` main locally before opening a new Claude Code session means the new worktree won't include recently-merged `.claude/settings.json` or `.claude/agents/` files, and the hook can't fire — pull main locally before relying on settings or agents from a recent merge. Bookkeeping note: this entry is being added post-hoc — the SessionStart hook landed in PR #3 alongside the residual phase/1-prep branch but missed its WORKFLOW.md changelog companion at the time; v1.3 closes that gap.

### v1.2 — 2026-05-09
Phase 1 prep + agent wiring fix. Phase 0.5 produced six well-drafted agent definitions at `/agents/*.md`, but the location and format were wrong for Claude Code's project-scoped subagent system: files needed to live at `.claude/agents/*.md` with YAML frontmatter to be invokable as `subagent_type` values. Documentation existed; wiring did not. Phase 1 prep applied the smallest fix: prepended minimal frontmatter (`name`, `description`) to each of the six files and `git mv`'d them into `.claude/agents/`. Mechanical tool scoping (`tools:` allowlists matching the prose Tool scope sections) deliberately deferred to Phase 5, per the original Phase 5 plan. Path references updated repo-wide (WORKFLOW.md and chief-of-staff.md); two historical references in the v1.1 changelog and Phase 0.5 "as executed" steps preserved as `/agents/` for accuracy. Phase 0.5 lessons-learned amended retroactively with the documentation-vs-wiring lesson. Phase 1 "Detailed steps" subsection fleshed out, including an explicit subagent invocation pattern for the phase (Product Manager as workhorse; Architect surgical; Security Reviewer at section-lock; Chief of Staff at phase boundaries). **After committing this version, Claude Code must be restarted before Phase 1 work begins** — the subagent registry loads at session start, so newly added agents are not callable mid-session.

### v1.1 — 2026-05-09
Phase 0.5 complete. Six agent definition files committed to `/agents/`: Chief of Staff, Product Manager, Architect, Security Reviewer, UX Designer, Visual Designer. Each follows the template locked in ADR-001. Chief of Staff smoke-tested (orchestration-shaped response confirmed). DECISIONS.md carries ADR-001 (Phase 0.5 process resolutions). Header pointer advanced to Phase 1. Phase 0.5 status, detailed steps, and lessons learned filled in.

### v1.0 — 2026-05-08
First repo commit. Per WORKFLOW.md's own versioning rule ("First repo commit: v1.0"), bumped from v0.5 to v1.0 on landing in git. Content unchanged from v0.5 except for this changelog entry, the header version/date, and the footer (which had stalled at "End of WORKFLOW.md v0.1" through four revisions). `.gitignore` and `CLAUDE.md` committed alongside this version bump — the previous commit (`5e65712`) listed them in its message but did not actually include them. Phase 0.5 detailed steps now planned in `/Users/mosko/.claude/plans/i-m-starting-claude-delegated-scott.md`; phase entry is imminent.

### v0.5 — 2026-04-25
Backlog tooling cleanup. Linear was locked as the task tracker in v0.3 but `TASKS.md` references lingered in Phase 7 outputs and in the Open Questions section. Resolved: backlog lives **entirely in Linear**, no `TASKS.md` artifact exists. Added **`docs/linear-setup.md`** to the artifact list as the operational companion to WORKFLOW.md's Linear policy — installation steps, OAuth flow, label and milestone conventions, troubleshooting. WORKFLOW.md remains the single source of truth for the *decision and policy* around Linear; `docs/linear-setup.md` covers *how to actually set it up and use it*. Phase 5 outputs updated to include drafting `docs/linear-setup.md`. Phase 7 reference to `TASKS.md` corrected. Open Questions entry for backlog tooling marked resolved.

### v0.4 — 2026-04-25
Resolved a chicken-and-egg dependency in the original phase ordering: Phases 1–4 listed agents (PM, Architect, Security Reviewer, designers) as leads, but agent definition files were not produced until Phase 5. Inserted **Phase 0.5 — Agent Roster Definition** between Phase 0 and Phase 1, with scope limited to the agents active in Phases 1–4 plus formalization of the Chief of Staff role. Build-time agents (Backend Engineer, Frontend Engineer, QA, DevOps) remain deferred to Phase 5, where their context is real. Updates: Phase overview table inserts Phase 0.5; new Phase 0.5 section added with full detail; Phase 1 inputs now explicitly note that PM, Architect, and Security Reviewer agent definitions exist; Phase 5 outputs scoped down to build-time agent definitions plus workshop infrastructure; agent roster section adds a "Definition timing" note per agent.

### v0.3 — 2026-04-25
Two operating-model refinements. **(1)** Owner role retitled from "CTO" to **"Founder/CTO"** throughout, reflecting authority over both business and technical decisions, not just technical. **(2)** **Linear** locked as the project tracking tool, with agents granted scoped Linear access via the official Linear MCP server. Updates: Linear added to artifact list (replacing the deferred `TASKS.md`/Issues choice); Phase 4 outputs now reference Linear epics/projects/issues; Phase 5 adds Linear MCP setup as a deliverable; Phase 6 includes agents updating Linear status as part of the build loop; Glossary entry added; corresponding `[OPEN]` question resolved.

### v0.2 — 2026-04-24
Refocused Phase 0 on **discovery and operating model only** (mini-business / startup framing). Product-scope content (V1 features, Plaid choice, lots-vs-positions, multi-tenant schema) moved out of Phase 0 outputs and into Phase 1 inputs as **preliminary findings to be ratified**, not locked decisions. Phase 0 renamed from "Vision & Discovery" to "Discovery & Operating Model." Phase 1 stub expanded with explicit inherited inputs and a ratification step. Tone shift across Phase 0 and operating-model sections toward "small organization, founding-team agreement" rather than corporate process documentation.

### v0.1 — 2026-04-24
Initial draft. Captures discovery outcomes, nine-role agent roster (incl. Chief of Staff as meta-role), eight-phase structure with Phase 4.5 inserted between scoping and workshop setup, full detail on Phase 0, stubs for Phases 1–7. Open questions noted inline as `[OPEN]`.

---

## How to use this document

This is the **map and execution log** for the mosko-fintech project. It serves two roles simultaneously:

1. **The map** — read first, every session. Tells you what the project is, how it's structured, who does what, and where you currently are.
2. **The execution log** — updated as the project progresses. Phase statuses change, lessons learned accumulate, the changelog grows.

**Reading order for new context recovery** (e.g., returning after a break):

1. Header → confirm current phase
2. Changelog → scan recent revisions
3. Current phase section → read its detailed steps and status
4. `DECISIONS.md` → scan recent decisions
5. Open issues / current branch → resume work

**Update cadence:**

- Before entering a new phase: flesh out that phase's "Detailed steps" subsection. Bump version, update changelog, commit.
- After exiting a phase: update status to "complete," add lessons learned. Bump version, commit.
- Mid-phase, on meaningful workflow changes: bump version, update changelog, commit.
- Major restructuring (new phase, agent roster change, scope shift): major version bump.

**Versioning:** `vMAJOR.MINOR`. Pre-commit (during initial drafting in chat): v0.x. First repo commit: v1.0. Post-commit revisions: v1.x for routine updates, v2.0 for foundational changes.

---

## Project framing

**mosko-fintech is run as a mini-business with startup posture.** A single human (the owner) holds the **Founder/CTO** role — combined authority over business decisions (scope, cost, partnerships, posture) and technical decisions (stack, architecture, security) — and works alongside a defined roster of AI agents that play the other roles a small company would normally fill: PM, Architect, designers, engineers, security, QA, ops. The "company" is small, fast, and informal, but the discipline of role separation, written artifacts, and explicit decisions is treated seriously, because that's where solo projects usually fail.

This document is the founding agreement: how the team is structured, how decisions get made, what artifacts the project produces, and what phases the work moves through. **It deliberately does not contain product specification** — that's the first piece of work the team takes on (Phase 1, PRD).

**One-paragraph reason this project exists:** The owner runs a recurring set of personal finance tasks each month — net worth calculation, asset allocation review, spending categorization, and others — through a patchwork of manual scripts. mosko-fintech replaces that patchwork with a single Plaid-connected app, used initially by the owner and architected to support invite-only friends-and-family use later. The product specifics are formalized in `PRD.md` during Phase 1.

### Preliminary product findings (inputs to Phase 1)

The discovery conversation surfaced strong starting positions on product scope, stack, and architectural constraints. **These are inputs to Phase 1, not Phase 0 outputs** — Phase 1's first job is to ratify, refine, or revise them before they become locked PRD content. Listed here so anyone reading this document understands the project's current shape, not as commitments.

- **Likely V1 surfaces:** net worth over time; asset allocation vs. target with rebalancing suggestions; categorized spending and budget tracking.
- **Likely V2 candidates:** tax planning (estimated payments); Monte Carlo longevity modeling; lot-level tax features; stock screening (possibly a separate tool).
- **Likely out-of-scope (permanent):** public sign-up; money movement; advisor role; multi-currency in V1.
- **Likely stack:** self-hosted Supabase on Coolify on a VPS (existing); Plaid for aggregation behind a swap-able abstraction layer; frontend framework TBD; background worker + scheduler + webhooks for sync.
- **Likely architectural constraints:** boring monolith; multi-tenant schema from day one; lots captured in schema from day one with lot-level UI deferred to V2; secrets never in repo; migrations in code.
- **Operating cost expectations:** ~$0/month at single-user scale on Plaid Trial; ~$10–40/month range for small family network post-Trial.

These will be ratified or revised during Phase 1 (product) and Phase 3 (architecture). When they're locked, they migrate from this section into `PRD.md` and `ARCHITECTURE.md` respectively, and this section is reduced to a brief pointer.

---

## Operating model

mosko-fintech operates as a one-human-many-agents team. The human (the owner) holds the **Founder/CTO** role. The agents fill the rest.

**The Founder/CTO** owns final judgment on scope, tech choices, security, cost, and any decision that's expensive or impossible to reverse later. Co-pilots three agents directly (Product Manager, Architect, Security Reviewer) — meaning the agent proposes, the Founder/CTO decides, neither acts alone. Delegates the remaining roles with review.

**The agent roster** exists for a specific reason: solo work loses the friction of teammates pushing back on bad ideas. The roster recreates that friction by giving each agent a scoped role, scoped judgment, and scoped tools. **Roles do not collapse** — when an architectural question comes up, you talk to the Architect agent, not the omniscient generalist. The role separation is the whole point.

**How decisions get made:**

- For non-trivial decisions, agents present 2–3 options with tradeoffs. The Founder/CTO picks one and the choice goes into `DECISIONS.md` with a short rationale.
- For trivial decisions (naming, formatting, obvious right answers), agents just decide and execute.
- For decisions touching auth, money, data, or anything irreversible, the Security Reviewer reviews and the Founder/CTO signs off explicitly.
- The **Chief of Staff** agent maintains workflow and orchestrates phase transitions, but does not make execution decisions itself.

**Cadence:** Async, single-developer. Work happens in bursts, with multi-week gaps possible. The project must be reconstructable from `WORKFLOW.md` + `DECISIONS.md` + the open branch at any time. Nothing important lives only in the owner's head.

**Task tracking via Linear:** Project work is tracked in **Linear**, organized as initiatives → projects → issues. Agents are granted scoped access to Linear via the official Linear MCP server, so an agent picking up an assigned issue can read its full context (description, priority, labels, linked PRs), update its status as work progresses (Todo → In Progress → In Review → Done), and post comments capturing decisions or blockers. This closes the loop between planning and execution: issues created during Phase 4 scoping become the actual unit of work agents pick up in Phase 6, with status changes flowing back automatically rather than requiring manual sync. Agent permissions in Linear are scoped — agents may read, comment, and update status on issues assigned to their role; reassignment, priority changes, and issue creation outside their scope require Founder/CTO action. Specific permission policy per agent role is defined in Phase 5.

**Team-mode for agent dispatches.** Execution-agent dispatches in the active phase use Claude Code team-mode with `team_name` set to the current phase identifier (e.g., `phase-1` for Phase 1). Plain `Agent` calls without `team_name` spawn inline subagents whose work renders in the orchestrator's pane; team-mode spawns appear in their own split-pane, so the Founder/CTO can watch teammate progress live and intervene if work drifts. The convention is forward-looking — Step 3.5 PRs 1–6 ran without it (inline subagents); PR 7 onward uses team-mode. New phases create their own team under the same `phase-<N>` naming.

---

## Agent roster

Nine roles total. Each role has a corresponding `.claude/agents/<role>.md` file containing its system prompt, scoped tools, and behavioral guidelines. Agent definitions are split across two phases by when they're first needed: roles active in Phases 1–4 are defined in **Phase 0.5**; build-time roles activated in Phase 5+ are defined in **Phase 5** alongside the rest of workshop setup. The "Definition timing" note on each role below indicates which phase produces its definition file.

### Meta role

**Chief of Staff** (`.claude/agents/chief-of-staff.md`)
The orchestrator. Maintains WORKFLOW.md, ensures phase transitions are clean, escalates when execution agents drift outside their roles, and is the agent the Founder/CTO talks to when unsure which agent to engage. Does not execute on the build itself. Primary artifact: WORKFLOW.md.
*Definition timing:* Phase 0.5 (formalization of the role that has been operating informally since Phase 0).

### Execution roster

**Product Manager** (`.claude/agents/product-manager.md`)
Owns PRD.md. Translates owner intent into structured user stories and feature definitions. Pushes back on scope creep. Maintains the V1 vs. V2 boundary. Co-piloted by Founder/CTO; Founder/CTO has final say on scope.
*Definition timing:* Phase 0.5 (lead on Phase 1).

**Architect** (`.claude/agents/architect.md`)
Owns ARCHITECTURE.md. Proposes system designs, data models, service boundaries, and tech choices. Always presents options with tradeoffs. Flags one-way doors and migration debt. Defaults to boring patterns; requires justification for novel ones. Co-piloted by Founder/CTO; Founder/CTO signs off on all architectural decisions.
*Definition timing:* Phase 0.5 (consulted in Phase 1; lead on Phase 3).

**UX Designer** (`.claude/agents/ux-designer.md`)
Owns user flows and interaction patterns. Translates PRD user stories into navigable flows. Hands off to Visual Designer. Reviewed by Founder/CTO; substantive UX decisions confirmed before execution.
*Definition timing:* Phase 0.5 (lead on Phase 2).

**Visual Designer** (`.claude/agents/visual-designer.md`)
Owns the design system — typography, color tokens, component inventory, visual polish. Outputs code-ready tokens. Operates from UX flows. Fully delegated.
*Definition timing:* Phase 0.5 (lead on Phase 2).

**Security Reviewer** (`.claude/agents/security-reviewer.md`)
Non-optional for fintech. Reviews every PR touching auth, data handling, external APIs, secrets, or financial calculations. Has veto power. Co-piloted by Founder/CTO; Founder/CTO signs off on all security-flagged changes.
*Definition timing:* Phase 0.5 (consulted in Phase 1; lead reviewer on Phase 3 auth/data/secrets work).

**Backend Engineer** (`.claude/agents/backend-engineer.md`)
Implements API, data layer, Plaid integration, background workers. Operates against Architect's contracts. Reviewed by Founder/CTO; SQL and Python output specifically reviewed by Founder/CTO given owner fluency.
*Definition timing:* Phase 5 (build-time role; deferred until tech stack and patterns are real).

**Frontend Engineer** (`.claude/agents/frontend-engineer.md`)
Implements UI against the design system and API contracts. Fully delegated; Founder/CTO reviews PRs but does not co-pilot.
*Definition timing:* Phase 5 (build-time role; deferred until frontend framework and design system are real).

**QA** (`.claude/agents/qa.md`)
Generates and maintains test suites. Writes acceptance tests against PRD user stories. Founder/CTO defines acceptance criteria; QA agent operationalizes them.
*Definition timing:* Phase 5 (build-time role; deferred until test framework and acceptance patterns are real).

**DevOps** (`.claude/agents/devops.md`)
Owns CI/CD scaffolding, deployment pipeline, monitoring setup. Split: agent handles GitHub Actions and pipeline scaffolding; Founder/CTO handles VPS/Coolify directly given existing familiarity.
*Definition timing:* Phase 5 (build-time role; deferred until CI/CD scope is real).

The split is a direct response to a chicken-and-egg problem in earlier versions of this document: Phases 1–4 listed agents as leads, but agent definitions were only produced in Phase 5. Roles needed in Phases 1–4 are now defined upfront in Phase 0.5, with their context still concrete enough to write good prompts. Build-time roles wait for Phase 5 because their context (stack choice, design system, CI patterns) doesn't exist until then — defining them earlier would mean defining them with less context and reworking later.

---

## Artifact list

All artifacts live in the GitHub repo. Source of truth is the repo, not local files or chat history.

### Project-level documents (repo root)

| Artifact | Purpose | Owner | Update cadence |
|---|---|---|---|
| `WORKFLOW.md` | This document. Map and execution log. | Chief of Staff | Per phase transition; major workflow changes |
| `PRD.md` | Product requirements. V1 scope, user stories, success metrics. | Product Manager | Per scope decision; reviewed each phase |
| `ARCHITECTURE.md` | System design, data model, tech choices, security posture. | Architect | Per architectural decision; reviewed each phase |
| `DECISIONS.md` | Architectural Decision Records (ADRs). One entry per non-obvious choice. | Whoever made the decision | Per decision |
| **Linear** (external) | Backlog and active task tracking. Initiatives → projects → issues. Accessed by agents via Linear MCP. Single source of truth for what's being worked on; no `TASKS.md` artifact exists. | Product Manager (issue creation); execution agents (status updates) | Continuous during build phases |
| `docs/linear-setup.md` | Operational companion to WORKFLOW.md's Linear policy. Covers MCP installation, OAuth flow, label/milestone conventions, issue templates, troubleshooting. WORKFLOW.md owns the *decision and policy*; this doc owns the *how-to*. | DevOps (initial draft); Chief of Staff (kept current) | Per Linear configuration change |
| `README.md` | Project intro, setup instructions, contribution model (solo). | Founder/CTO | Rarely |
| `CLAUDE.md` (root) | Project conventions for Claude Code at the repo level. | Chief of Staff | Per workshop setup; refined during build |

### `/docs/` directory convention

Operational, how-to, and reference documents live in `/docs/`. The repo-root markdown files (`WORKFLOW.md`, `PRD.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `README.md`, `CLAUDE.md`) are the primary source-of-truth documents — read first, owned by named roles, version-controlled deliberately. Documents in `/docs/` supplement them with operational detail that would clutter the root docs if inlined. Examples include `docs/linear-setup.md` (Linear MCP setup and use), and over time will likely include `docs/plaid-setup.md`, `docs/coolify-deploy.md`, and similar. The pattern: root docs answer *what and why*; `/docs/` answers *how*.

### Per-directory CLAUDE.md files

`CLAUDE.md` files at directory level provide scoped context to Claude Code agents. Anticipated locations:

- `/supabase/CLAUDE.md` — migration patterns, schema conventions, RLS rules
- `/api/CLAUDE.md` — API conventions, error handling, Plaid integration patterns
- `/web/CLAUDE.md` — frontend conventions, design system usage, component patterns
- `/workers/CLAUDE.md` — background job patterns, sync logic, idempotency rules

### Agent definitions (`.claude/agents/`)

One file per role. See agent roster above.

### Skills (`/skills/`)

Custom Claude Code skills for repeated workflows. Anticipated examples:

- `add-plaid-account-type` — adding support for a new Plaid account type
- `create-react-component` — creating a new component matching the design system
- `add-api-endpoint` — adding a new API endpoint with auth, validation, tests
- `write-migration` — writing a new Supabase migration with rollback

Skills are drafted as patterns emerge during build, not all upfront.

### Design assets

Location and format TBD in Phase 2.

---

## Phase overview

| # | Phase | Status | Primary output |
|---|---|---|---|
| 0 | Discovery & Operating Model | ✅ Complete | Operating model + this document |
| 0.5 | Agent Roster Definition | ✅ Complete | Agent definition files for Phase 1–4 roles |
| 1 | Product Definition (PRD) | ⏳ Not started | `PRD.md` |
| 2 | UX & Design | ⏳ Not started | User flows + design system |
| 3 | Technical Architecture | ⏳ Not started | `ARCHITECTURE.md` (revised from existing schema) |
| 4 | Project Scoping | ⏳ Not started | Linear backlog (initiatives, projects, issues) |
| 4.5 | Agentic Flow Ramp | ⏳ Not started | Practice feature + workflow fluency |
| 5 | Workshop Setup | ⏳ Not started | `CLAUDE.md` files, build-time `.claude/agents/*.md`, `/skills/*.md`, CI/CD |
| 6 | Build Loop | ⏳ Not started | V1 product |
| 7 | Deploy & Iterate | ⏳ Not started | Live system + V2 backlog |

---

## Phase template

Each phase section below follows this structure:

- **Purpose** — what this phase exists to accomplish
- **Inputs** — what must exist before entering
- **Outputs** — what gets produced and committed
- **Agents involved** — who does what
- **Exit criteria** — how we know the phase is done
- **Status** — not started / in progress / complete
- **Detailed steps** — fleshed out just-in-time before phase entry
- **Lessons learned** — added retrospectively after phase exit

---

## Phase 0 — Discovery & Operating Model

**Purpose:** Stand up the mini-business. This phase establishes *how* mosko-fintech operates — the team structure, decision rights, workflow, and foundational documents — before any product work happens. Think of it as the founding meeting of a small startup: agreement on roles, cadence, and what artifacts the company produces, separate from what the company will eventually build.

Discovery happens here too, but in a specific sense: a structured conversation that surfaces preliminary product thinking and the owner's existing assets (infrastructure, prior work, domain knowledge). That thinking becomes **input** to Phase 1, where it gets ratified into a real PRD. Product scope is not locked in this phase.

**Inputs:**

- Owner's prior thinking and existing manual workflow
- Existing self-hosted Coolify/VPS infrastructure
- Existing Supabase schema work (acknowledged as a v0.5 starting point)
- Owner's background and constraints (skills, time, solo, GitHub-deployed)

**Outputs:**

- This document (`WORKFLOW.md`) defining the operating model, agent roster, artifact list, and eight-phase structure
- Preliminary product findings captured (in "Project framing" above) and explicitly marked as Phase 1 inputs awaiting ratification
- Agreement on the mini-business posture: small team, fast cadence, written artifacts, role separation taken seriously

**Agents involved:**

- Chief of Staff (lead — orchestrating discovery, drafting the operating model, owning the workflow document)
- Founder/CTO (the human — deciding on operating model, agent roster, and workflow structure)

**Exit criteria:**

- The owner can articulate the operating model without referring to docs (one human as Founder/CTO, defined agent roster, role separation, decision rights)
- `WORKFLOW.md` exists and contains the agent roster, artifact list, eight-phase structure, and Phase 0 detail
- Preliminary product findings from discovery are captured *as Phase 1 inputs*, not as locked product decisions
- The owner has a clear answer to "what do I do next?" (enter Phase 1, draft the PRD)

**Status:** ✅ Complete (2026-04-24)

**Detailed steps (as executed):**

1. **Frame the project as a mini-business, not a coding project.** The opening exchange reframed "where do I start, Claude Code or Claude Design?" as the wrong question — the right starting point is defining how the team operates, not which tool to open first. Tooling follows definition.

2. **Surface owner context through sequential discovery questions.** Four foundational questions, asked one at a time with reflection after each: scope of users, primary use case, owner's experience and existing assets, team composition. Sequential framing (rather than a bulk questionnaire) allowed each answer's implications to be absorbed before the next question, producing sharper answers and surfacing cross-cutting consequences.

3. **Sketch the operating model.** Owner role defined as Founder/CTO — judgment and decisions, not omniscient execution. Agent roster sketched at eight execution roles (PM, Architect, UX, Visual, Backend, Frontend, Security, QA, DevOps). Founder/CTO co-pilots three of those (PM, Architect, Security) and delegates the rest with review.

4. **Add the Architect agent with Founder/CTO sign-off pattern.** Owner's EE and algorithms background gives strong judgment but not fintech-specific architectural patterns. Resolved by structuring the Architect agent as a *proposing* entity (always presents 2–3 options with tradeoffs) and the Founder/CTO as a *deciding* entity. Pattern generalizes to any role where the human has judgment but not pattern library.

5. **Name the Chief of Staff role.** Late in discovery the question came up: "what role is the AI playing in this conversation?" Honest answer: a fused meta-role doing PM + Architect + workflow design simultaneously. Named the role explicitly as Chief of Staff and added it as a ninth role distinct from the execution roster. Its scope is orchestration and workflow maintenance, not execution.

6. **Define the eight-phase workflow.** Phase 0 (Discovery & Operating Model), Phase 1 (PRD), Phase 2 (UX & Design), Phase 3 (Architecture), Phase 4 (Scoping), Phase 4.5 (Agentic Flow Ramp — added based on owner's unfamiliarity with the agentic loop), Phase 5 (Workshop Setup), Phase 6 (Build Loop), Phase 7 (Deploy & Iterate).

7. **Decide WORKFLOW.md plays a dual role.** Both stable map (read first, every session) and living execution log (updated as phases complete). Resolved with a structure where stable scaffolding is fully drafted from v0.1 and per-phase detail is expanded just-in-time before each phase entry.

8. **Capture preliminary product thinking as Phase 1 inputs, not Phase 0 outputs.** During discovery, substantial product thinking surfaced (V1 cluster scope, Plaid choice, lots-in-schema, multi-tenant from day one). Rather than lock these as Phase 0 outputs, they were explicitly marked as **starting positions for Phase 1 to ratify**. This keeps Phase 0 focused on *how* the team operates and Phase 1 focused on *what* the team builds.

**Lessons learned:**

- **Sequential discovery beats bulk questionnaires.** Asking one foundational question at a time, with reflection after each, surfaces the cross-cutting consequences that bulk questionnaires miss. Worth replicating in any future "definitional" phase (e.g., the start of Phase 1).
- **Naming roles explicitly prevents collapse.** When an unnamed meta-agent does several roles at once, the role separation discipline silently dissolves. Naming the Chief of Staff role late in discovery resolved a real ambiguity. Lesson: when working with agents, periodically ask "what role is this agent playing right now?"
- **Solo work demands more writing, not less process.** The instinct to skip documentation because "it's just me" is the classic solo-founder regret. Phase 0 leaned into the opposite — heavier on written artifacts because there's no team to externalize coordination.
- **Existing infrastructure is a meaningful asset.** The owner already had Supabase on Coolify on a VPS, plus partial schema work and a Claude Code trial under their belt. That compresses Phase 3 (architecture becomes *revision* rather than from-scratch design) and Phase 5 (workshop setup builds on existing GitHub habits). Worth surfacing existing assets explicitly rather than starting as if from zero.
- **Separate "how the team operates" from "what the team builds."** Discovery naturally produced both, and the v0.1 draft of this document conflated them. The v0.2 revision separated them: operating model and workflow stay in Phase 0; product scope and tech choices migrate to Phases 1 and 3 as inputs awaiting ratification. Cleaner mental model, and matches how an actual startup would sequence the work.

---

## Phase 0.5 — Agent Roster Definition

**Purpose:** Stand up the team. Phase 0 defined *what* the agent roster is at a high level; Phase 0.5 produces the actual agent definition files (`.claude/agents/*.md`) for the roles that will be active in Phases 1–4. Each definition contains the agent's system prompt, scoped tools, behavioral guidelines, escalation patterns, and Linear permission policy. After this phase, when Phase 1 says "Product Manager leads," there is a real PM agent file to invoke.

Build-time roles (Backend Engineer, Frontend Engineer, QA, DevOps) are deliberately deferred to Phase 5, where their context (stack, framework, design system, CI patterns) is real. Defining them here would mean writing prompts in a vacuum and rewriting them later.

**Inputs:**

- Operating model and agent roster from Phase 0 (this document)
- Linear MCP setup decisions from v0.3 (Linear is the task tracker; agents access via the official Linear MCP server with scoped permissions)
- Owner's understanding of how each role behaves in practice (refined informally during Phase 0)

**Outputs:**

- `.claude/agents/chief-of-staff.md` — formalizes the role that has been operating informally since Phase 0 began
- `.claude/agents/product-manager.md` — Phase 1 lead
- `.claude/agents/architect.md` — Phase 1 consultant, Phase 3 lead
- `.claude/agents/security-reviewer.md` — Phase 1 consultant, Phase 3 reviewer
- `.claude/agents/ux-designer.md` — Phase 2 lead
- `.claude/agents/visual-designer.md` — Phase 2 lead
- `DECISIONS.md` entries for any non-obvious choices in agent prompt design (e.g., scope of veto power, escalation triggers, when an agent must present options vs. just decide)

**Agents involved:**

- Chief of Staff (lead — drafts its own definition first, then uses it to draft the rest)
- Founder/CTO (reviews and signs off on each definition; veto on any prompt that gives an agent more authority than intended)

**Exit criteria:**

- Six agent definition files exist in `.claude/agents/`, each containing: role description, system prompt, scoped tools, behavioral guidelines, escalation triggers, Linear permission policy
- Chief of Staff agent can be invoked and produces orchestration-style responses, not execution-style responses
- Each Phase 1–4 agent can be invoked and stays within its role boundaries (validated by a brief test prompt for each)
- Founder/CTO has reviewed every prompt and signed off
- `DECISIONS.md` exists (created here if not earlier) and contains entries for any contentious prompt-design choices

**Status:** ✅ Complete (2026-05-09)

**Detailed steps (as executed):**

1. **Pre-work (prior session).** `/agents/` directory created. `DECISIONS.md` bootstrapped with ADR-001, resolving the three open process choices: single bundled PR for all six files, agent-file template locked as proposed, smoke tests run live and not archived.

2. **Chief of Staff drafted and reviewed.** Drafted first so the role doing the definition work is formalized before drafting the others. One minor flag surfaced during review (engagement model wording "Co-piloted" vs. WORKFLOW.md's list of three explicitly co-piloted roles); Founder/CTO confirmed it as acceptable shorthand. Smoke test run: invoked on "What phase are we in and what's next?" — produced an orchestration-shaped response (named state, sequenced remaining steps, flagged a stale WORKFLOW.md status, ended with a routing question rather than an action). Passed.

3. **Product Manager + Architect drafted as a pair.** Pairing surfaced the handoff contract early: PM flags requirements with architectural cost → Architect consults → infeasible requirements route back to PM → Founder/CTO decides if stuck. Non-obvious design choices: PM's "flag, don't embed" rule for security decisions (prevents architectural decisions from leaking into PRD user stories); Architect owns `/supabase/migrations/` in tool scope (migration files are the primary Phase 3 build artifact, not just prose in ARCHITECTURE.md); Architect's "boring by default" behavioral guideline. No ADR entries needed — all aligned with existing WORKFLOW.md framing.

4. **Security Reviewer drafted.** Non-obvious design choice: three-level severity system (veto / flag / note) rather than binary veto/pass. Rationale: a bare veto on every concern inflates noise; the three levels let the agent calibrate without softening findings. Veto still requires Founder/CTO sign-off before work proceeds. No ADR entry — Founder/CTO did not flag this as contentious.

5. **UX Designer + Visual Designer drafted as a pair.** Pairing surfaced the handoff contract: UX hands off with screen list, component inventory, interaction states, and error states; Visual operates from that inventory and flags gaps back rather than designing around them. Mid-draft, Founder/CTO directed adding a mandatory palette-and-typography checkpoint to Visual Designer — engagement model updated from "Fully delegated" to "Delegated with review" to reflect this. All four affected locations in the file updated consistently.

6. **WORKFLOW.md updated, PR opened.** This step.

**Lessons learned:**

- **Draft the meta-role first.** Formalizing the Chief of Staff before drafting the other agents was the right call — the smoke test served as a live self-consistency check that the prompt matched the role's actual behavior during the session.
- **Pair roles that share a phase.** Drafting PM + Architect together, and UX + Visual together, surfaced handoff contract gaps that sequential drafting would have missed. The asymmetry between them (PM escalates to Architect for feasibility; Architect escalates back to PM for scope ambiguity) was cleaner to see when both files were open.
- **Template held.** The template locked in ADR-001 needed no changes across six files. The upfront lock cost one decision; the savings were six consistent files without retrofit churn.
- **Behavioral guardrails are the hard part.** The structural sections (tool scope, Linear policy, escalation triggers) were straightforward. The behavioral guidelines — "boring by default," "flag, don't embed," "flows first wireframes second" — are where the real prompt design work happened. These are the constraints that prevent the most common agent failure modes and deserve the most review attention.
- **Engagement model granularity matters.** "Fully delegated" and "co-piloted" are too coarse. The Visual Designer revision mid-phase (adding a mandatory checkpoint) shows that "delegated with review" covers a range. Future agent definitions may benefit from naming the specific checkpoints explicitly rather than relying on the engagement model label alone.
- **ADR bar is higher than expected.** None of the individual prompt design choices during this phase cleared the bar for a DECISIONS.md entry — they were either aligned with WORKFLOW.md framing or resolved without meaningful alternatives. ADR-001 (the process decisions) was the only entry. Future phases: an ADR belongs when the Founder/CTO would otherwise be unable to reconstruct *why* a choice was made, not just *what* was chosen.
- **Documentation ≠ wiring (added retroactively in v1.2).** Phase 0.5 produced six well-drafted agent definitions but at `/agents/*.md`, without YAML frontmatter — a path and format that Claude Code's project-scoped subagent system does not load. The files were documentation, not invokable subagents. The gap was invisible from inside Phase 0.5 because the smoke test validated *role behavior* (does the prompt produce orchestration-shaped responses?) via in-session roleplay, not *invocation mechanics* (can `subagent_type: chief-of-staff` actually be called?). Phase 1 prep surfaced it; the minimal fix was applied in v1.2 (frontmatter prepended, files moved to `.claude/agents/`, mechanical tool scoping deferred to Phase 5). Lesson for any future agent-definition phase: every smoke test must include an actual `Task`/`Agent` invocation by `subagent_type`, not just "Claude reads the file and roleplays." Prose-correctness and call-mechanics-correctness are independent checks.

---

## Phase 1 — Product Definition (PRD)

**Purpose:** First real piece of work the mini-business takes on. Convert the preliminary product findings from Phase 0 into a structured, reviewable Product Requirements Document. This is where product scope is *actually* locked — Phase 0's findings are starting positions, not commitments. The PRD becomes the source of truth for all downstream work; every architectural decision, every UX flow, every task in the backlog must trace back to a PRD requirement.

**Inputs:**

These come from the "Preliminary product findings" section of this document. They are explicit Phase 0 outputs, but they enter Phase 1 as starting positions to be ratified, refined, or revised — not as locked requirements.

- **Likely V1 surfaces** to evaluate and lock: net worth over time; asset allocation vs. target with rebalancing suggestions; categorized spending and budget tracking
- **Likely V2 candidates** to confirm as deferred: tax planning; Monte Carlo longevity modeling; lot-level tax features; stock screening
- **Likely permanent non-goals** to confirm: public sign-up; money movement; advisor role; multi-currency in V1
- **Likely user model** to confirm: solo owner initially with invite-only friends-and-family path; multi-tenant from day one in data model; UI single-user-only until a second user actually onboards
- **Likely operating cost shape** to confirm: ~$0/month single-user on Plaid Trial; ~$10–40/month range for small family network
- **Agent definitions for Phase 1 roles** (from Phase 0.5): `.claude/agents/product-manager.md`, `.claude/agents/architect.md`, `.claude/agents/security-reviewer.md`, `.claude/agents/chief-of-staff.md` all exist and are signed off
- Owner's domain knowledge of personal finance workflows
- Any insights from owner's existing manual scripts (worth reviewing as PRD input — they encode requirements)

**Outputs:**

- `PRD.md` committed to repo at v1.0
- Updates to `DECISIONS.md` for any preliminary findings that get revised or refined
- Updated "Project framing" section in this document — preliminary findings replaced with a brief pointer to `PRD.md`

**Agents involved:**

- Product Manager (lead — drafting, structuring, ratifying preliminary findings)
- Founder/CTO (deciding on scope, signing off on each section)
- Architect (consulted on technical feasibility of requirements; flags requirements that have major architectural cost)
- Security Reviewer (consulted on security and compliance posture sections; flags fintech-specific obligations)

**Exit criteria:**

- All preliminary findings from Phase 0 have been explicitly ratified, refined, or revised — and any revisions logged in `DECISIONS.md`
- PRD covers: vision, target user, user stories, V1 features, V2 deferred candidates, permanent non-goals, success metrics, security and compliance posture, and constraints
- Every V1 feature has at least one user story
- Non-goals are explicit (not just absent)
- Success metrics are measurable
- Founder/CTO signs off on the document as v1.0

**Status:** ⏳ Not started

**Detailed steps:**

1. **Session prerequisites (Founder/CTO + CoS).** Before kicking off Phase 1 work, **restart Claude Code** so the six subagents from `.claude/agents/*.md` are loaded into the session's registry. Verify by attempting an explicit subagent invocation (e.g., `Task` with `subagent_type: product-manager` and a trivial smoke prompt). If the subagents do not appear, **do not proceed** — stop and debug the wiring before drafting any PRD content. Mandatory pre-reading for the session: `WORKFLOW.md`, `DECISIONS.md`, and the four agent files active in this phase (`.claude/agents/chief-of-staff.md`, `.claude/agents/product-manager.md`, `.claude/agents/architect.md`, `.claude/agents/security-reviewer.md`).

2. **Ratification pass over Phase 0's preliminary findings (PM-led, CoS-orchestrated).** Invoke the Product Manager subagent for a focused working session whose only goal is to ratify, refine, or reject each preliminary finding currently captured in WORKFLOW.md's "Preliminary product findings" subsection. For each finding, the PM produces one of three verdicts: **(a) confirmed** — finding becomes a V1 PRD requirement as-is; **(b) revised** — new framing recorded as a DECISIONS.md ADR; **(c) rejected** — rationale recorded as an ADR. Founder/CTO signs off on each verdict explicitly. PM does NOT begin PRD section drafting until ratification is complete — ratification first, drafting second.

3. **PRD section drafting in agreed order (PM-led, with consultations).** Once findings are ratified, the PM agent drafts `PRD.md` section-by-section, invoking other subagents only when their role is triggered:
   - Vision and target user (PM only)
   - User stories per V1 surface, in priority order: net worth → asset allocation → spending categorization (PM; consult Architect via `subagent_type: architect` when a story implies non-trivial architectural cost)
   - Success metrics (PM; Founder/CTO signs off on what's measurable)
   - **Security and compliance posture** (PM drafts, then **mandatory Security Reviewer pass** via `subagent_type: security-reviewer` before locking — covers auth, multi-tenant data isolation, Plaid integration boundaries, secrets handling, financial calculation integrity)
   - V2 deferred candidates (PM only)
   - Permanent non-goals (PM; Founder/CTO sign-off)
   - Constraints — cost, scale, single-user vs. invite-only (PM)

4. **Cross-cutting reviews on the full PRD draft.** Once a draft PRD exists end-to-end:
   - **Architect feasibility pass** — invoke `subagent_type: architect` to review the full PRD and flag any requirement with significant architectural cost. Architect presents 2–3 options for each flag; Founder/CTO decides; decisions recorded in DECISIONS.md.
   - **Security Reviewer pass** — invoke `subagent_type: security-reviewer` to review the full PRD with veto authority on auth, money flows, secrets, Plaid integration, multi-tenant isolation. Any veto requires PRD revision before proceeding to lock.

5. **Founder/CTO sign-off on PRD v1.0.** Read the full PRD in one sitting. Confirm scope, non-goals, success metrics, security posture. Sign off explicitly in chat — silence is not approval.

6. **Phase exit (CoS-led).** After PRD lock at v1.0:
   - Replace WORKFLOW.md's "Preliminary product findings" subsection with a brief pointer to `PRD.md`.
   - Add Phase 1 "Lessons learned" subsection.
   - Update Phase 1 status to "✅ Complete" with completion date.
   - Bump WORKFLOW.md (likely v1.3) and write the changelog entry.
   - Commit and merge via PR. Move header pointer to Phase 2.

**Subagent invocation pattern for the whole phase** (per ADR-003):

- **Step 1–2 used the task-mode subagent pattern**: orchestrator-mediated, one-shot invocations via `Agent(subagent_type=...)` with full re-briefing each turn. That work is complete (ADR-002 records the Step 2 ratification verdicts).
- **Step 3 onward uses team mode** (per ADR-003): `TeamCreate phase-1-step-3-drafting` at Step 3 entry; teammates spawned via the `Agent` tool with `team_name` and persistent context; peer-to-peer communication via `SendMessage`. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `.claude/settings.local.json`. Fallback to task mode is documented in ADR-003 §4 if team mode breaks mid-session.
- **Product Manager** is the workhorse — primary teammate, persistent context across all of Step 3.
- **Architect** is surgical — spawn-on-need within the same team for feasibility questions. Long-context model variant recommended when reading large composite contexts (full WORKFLOW + DECISIONS + accumulated PRD draft).
- **Security Reviewer** is mandatory at section-lock time on auth / data / Plaid / multi-tenant sections. Veto authority means: do not lock those sections without an explicit Security Reviewer pass.
- **Chief of Staff** is always the team lead — CoS-as-main-session calls TeamCreate, manages team lifecycle, tears down at phase/step exit. Never spawned as a teammate within its own team.
- **Founder/CTO is the decider.** Co-piloted agents (PM, Architect, Security Reviewer) propose; Founder/CTO disposes. Don't let any subagent close out a non-trivial decision unilaterally.

**Lessons learned:** *To be added after phase exit.*

---

## Phase 2 — UX & Design

**Purpose:** Translate PRD requirements into navigable user flows, then into wireframes, then into a coherent visual design system. Flows first, visual polish last — designing components before knowing the flows leads to component bloat.

**Inputs:**

- Locked PRD.md
- Stack constraints (frontend framework decision, if made)

**Outputs:**

- User flow diagrams (one per primary user journey)
- Wireframes for each major screen
- Design system spec: typography, color tokens, spacing, component inventory
- Design system implemented as code-ready tokens (format TBD)

**Agents involved:**

- UX Designer (lead on flows and wireframes)
- Visual Designer (lead on design system)
- Product Manager (consulted on flow-to-PRD traceability)
- Founder/CTO (reviewing flows; light touch on visual design)

**Exit criteria:**

- Every PRD user story has a corresponding flow
- Every flow has wireframes for its key screens
- Design system spec exists and is unambiguous
- Design tokens are in a format consumable by the chosen frontend framework

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 3 — Technical Architecture

**Purpose:** Produce a concrete, decided technical architecture that reflects the locked PRD and stack. For this project specifically, this is a *revision* of the owner's existing Supabase schema and infrastructure setup against V1 requirements, not a from-scratch design.

**Inputs:**

- Locked PRD.md
- Owner's existing Supabase schema (v0.5)
- Existing Coolify + VPS deployment
- Plaid documentation and data model
- UX flows (helpful but not required to start)

**Outputs:**

- `ARCHITECTURE.md` committed to repo at v1.0, covering:
  - System overview and component diagram
  - Data model (tables, relationships, RLS policies)
  - Plaid integration architecture (sync flow, webhook handling, abstraction layer)
  - API surface
  - Auth strategy (leveraging Supabase Auth)
  - Background worker architecture
  - Deployment topology
  - Security model
  - Backup and disaster recovery
  - Operational runbook starter
- Initial migration files in `/supabase/migrations/`
- ADR entries in `DECISIONS.md` for major choices

**Agents involved:**

- Architect (lead, proposing all designs)
- Founder/CTO (deciding on every proposal; final sign-off)
- Security Reviewer (reviewing security model, auth, secrets handling)
- Backend Engineer (consulted on implementation feasibility)

**Exit criteria:**

- All V1 PRD requirements have an architectural answer
- Every major decision has an ADR in DECISIONS.md
- Schema migrations exist and apply cleanly to a fresh Supabase instance
- Security Reviewer signs off on auth, RLS, and secrets handling
- Founder/CTO signs off on the document as v1.0

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 4 — Project Scoping

**Purpose:** Decompose the PRD and architecture into an actionable backlog. Each task should be small enough that an AI agent can complete it in one focused session with a clear acceptance criterion. Milestones group related tasks into shippable increments.

**Inputs:**

- Locked PRD.md
- Locked ARCHITECTURE.md
- Design system and flows (for frontend tasks)

**Outputs:**

- Linear **initiatives** for major V1 themes (typically 1–2: e.g., "V1 launch")
- Linear **projects** for each epic (3–7 total, mapping to PRD feature areas)
- Linear **milestones** within each project (each shippable in days-to-weeks)
- Linear **issues** at one-session granularity, each with description, acceptance criteria, agent role label, and milestone assignment
- Issues are pre-prioritized and sequenced; first milestone is small and confidence-building

**Agents involved:**

- Product Manager (lead on decomposition; creates the Linear initiatives, projects, and issues)
- Architect (consulted on task ordering and dependencies)
- Founder/CTO (sequencing milestones, deciding what's in V1.0 vs. V1.1 vs. V2; final issue prioritization)

**Exit criteria:**

- Every PRD requirement traces to at least one Linear issue
- Every issue has an acceptance criterion in its description
- Every issue has an agent-role label (`role:backend`, `role:frontend`, etc.)
- Milestones are sequenced in Linear with explicit dependencies
- First milestone is small and confidence-building
- Linear MCP integration is verified working (can be deferred to Phase 5 if not yet set up)

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 4.5 — Agentic Flow Ramp

**Purpose:** Build owner fluency with Claude Code's agentic workflow before committing it to real V1 work. A throwaway practice feature, executed end-to-end through the full agent roster and tooling, so that the workflow patterns are internalized rather than learned-while-building.

**Inputs:**

- Workshop setup (Phase 5) does NOT need to be complete — this phase deliberately predates it to surface what the workshop needs to provide.
- A small, self-contained practice problem (TBD; should be related-but-not-V1, e.g., a standalone admin tool, a one-off data import script)

**Outputs:**

- A working throwaway feature (not committed to V1 codebase)
- Owner fluency with: plan mode, edit-test-commit loop, subagent invocation, skill authoring, CLAUDE.md scoping
- A `/notes/agentic-flow-lessons.md` capturing what worked and what didn't, used as input to Phase 5

**Agents involved:**

- Chief of Staff (orchestrating the practice)
- Founder/CTO (the human doing the learning)
- Whatever execution agents the practice feature requires

**Exit criteria:**

- Owner can describe the plan-edit-test-commit loop without referring to docs
- Owner has authored at least one custom skill
- Owner has invoked a subagent at least once and seen the role separation work
- Notes captured for Phase 5 input

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 5 — Workshop Setup

**Purpose:** Build the development environment itself as a deliverable. Repo conventions, build-time agent definitions, skills, CLAUDE.md files, CI/CD, hooks, branch protection. The output of this phase is the *machine that builds the product*. Phase 1–4 agent definitions already exist from Phase 0.5; this phase adds the build-time agents (Backend Engineer, Frontend Engineer, QA, DevOps) plus the surrounding infrastructure, and refines the existing agent definitions if needed based on lessons from Phases 1–4.

**Inputs:**

- Locked PRD, ARCHITECTURE, backlog
- Existing agent definitions from Phase 0.5 (`.claude/agents/chief-of-staff.md`, `.claude/agents/product-manager.md`, `.claude/agents/architect.md`, `.claude/agents/security-reviewer.md`, `.claude/agents/ux-designer.md`, `.claude/agents/visual-designer.md`)
- Lessons from Phase 4.5
- Owner's existing GitHub setup

**Outputs:**

- Root `CLAUDE.md` with project conventions
- Per-directory `CLAUDE.md` files for `/supabase`, `/api`, `/web`, `/workers` (or analogous structure)
- **Build-time agent definitions** added: `.claude/agents/backend-engineer.md`, `.claude/agents/frontend-engineer.md`, `.claude/agents/qa.md`, `.claude/agents/devops.md` — each with system prompt, tool scopes, behavioral guidelines, and **Linear permission scope** (which issues it may read, comment on, update status on, or create)
- **Refinements to Phase 0.5 agent definitions** if Phases 1–4 surfaced gaps (e.g., escalation triggers that need adjustment, behavioral guidelines that need clarification) — version-bumped, with changes logged in `DECISIONS.md`
- Initial set of `/skills/*.md` files for known repeated workflows
- **Linear MCP server connected** to Claude Code (`claude mcp add --transport http linear https://mcp.linear.app/mcp`), with OAuth completed and access verified
- **Linear workspace configured**: agent-role labels (`role:backend`, `role:frontend`, `role:architect`, etc.), milestone structure, issue templates per agent role
- **`docs/linear-setup.md` drafted**: documents the MCP installation steps, OAuth flow, agent-role label conventions, milestone structure, issue templates, and troubleshooting. Becomes the operational reference for any future Linear setup or onboarding.
- GitHub Actions CI pipeline (lint, test, type-check)
- Branch protection rules
- Pre-commit hooks
- Secrets management approach implemented (`.env` patterns, secrets in Coolify env)

**Agents involved:**

- Chief of Staff (lead on build-time agent definitions, CLAUDE.md files, and any refinements to Phase 0.5 agent definitions; defines per-agent Linear permission scope)
- DevOps (lead on CI/CD, hooks, and Linear MCP setup) — note that DevOps' own definition is being drafted in this same phase, an intentional bootstrapping moment handled by Chief of Staff drafting first
- Founder/CTO (signing off on new agent prompts, refinements to existing prompts, conventions, security posture of CI, and Linear permission policy)
- Each build-time agent (consulted on its own definition file as it gets drafted)

**Exit criteria:**

- A new task can be assigned to any execution agent and completed end-to-end without ad-hoc setup
- CI passes on a clean checkout
- Branch protection prevents direct pushes to main
- Agent definitions exist for all nine roles (six from Phase 0.5, four added here), each with explicit Linear permission scope
- Any Phase 0.5 agent definitions that needed refinement have been updated and re-signed-off
- Owner can invoke any agent by name and get role-appropriate behavior
- An agent invoked with a Linear issue ID can read the issue, do the work, update status, and comment back — verified end-to-end on a test issue

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 6 — Build Loop

**Purpose:** The repeating heartbeat of the project. Pick a task, delegate to the right agent, review, merge, update docs. Continues until V1 ships.

**Inputs:**

- Workshop setup complete
- Backlog populated and prioritized
- Owner availability for review cycles

**Outputs:**

- V1 product, milestone by milestone
- Continuously updated PRD, ARCHITECTURE, DECISIONS as scope or design evolves
- Skills library grows organically as patterns emerge

**Agents involved:**

- All execution agents, per task assignment
- Security Reviewer on every PR touching sensitive surfaces
- Chief of Staff on phase-level retrospectives between milestones
- Founder/CTO on review and merge

**Exit criteria:**

- All V1 milestones complete
- All V1 PRD requirements have shipped and passed acceptance
- Test coverage meets standards defined in Phase 5
- Security Reviewer signs off on V1 as a whole

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Phase 7 — Deploy & Iterate

**Purpose:** Get V1 to production, validate it with real use, then close the loop back to PRD for V2.

**Inputs:**

- V1 build complete
- Production VPS ready
- Plaid Production credentials (upgrade from Sandbox/Trial as needed)

**Outputs:**

- Live V1 system in production
- Monitoring and alerting configured
- Backup and recovery validated
- V2 backlog informed by real V1 use
- Updated PRD with V2 candidates promoted from "deferred" to "planned"

**Agents involved:**

- DevOps (lead on deployment)
- Security Reviewer (final pre-production sign-off)
- Founder/CTO (production decisions, monitoring posture)
- Product Manager (V2 planning based on actual use)
- Chief of Staff (project retrospective)

**Exit criteria:**

- V1 is in production, used by owner for at least one full monthly cycle
- Backups have been tested via restore
- Monitoring catches at least one synthetic failure correctly
- V2 backlog exists as Linear initiatives/projects (V2 candidates promoted from PRD's "deferred" section into Linear)
- Project retrospective committed as `/notes/v1-retrospective.md`

**Status:** ⏳ Not started

**Detailed steps:** *To be fleshed out before phase entry.*

**Lessons learned:** *To be added after phase exit.*

---

## Glossary

**Aggregator** — A service that connects to financial institutions and exposes their data via API (e.g., Plaid, Teller, MX). The "abstraction layer" we plan to build sits between our app and the chosen aggregator so it can be swapped.

**ADR (Architectural Decision Record)** — A short document capturing a single non-obvious decision: what was chosen, what was considered, why. Lives in `DECISIONS.md` (or `/decisions/`).

**Agent** — In this project, a Claude Code subagent with a scoped system prompt, scoped tools, and a defined role. Distinct from a generic "AI assistant" — agents have role-specific behavior.

**Chief of Staff** — The meta-role that orchestrates the project, maintains WORKFLOW.md, and ensures phase transitions are clean. Does not execute on the build itself.

**CLAUDE.md** — A markdown file Claude Code reads automatically to get context. Can exist at the repo root (project-wide conventions) or in subdirectories (scoped conventions).

**Founder/CTO** — The owner's role in this project. Co-pilots Product, Architecture, and Security agents; delegates execution; decides on scope, cost, and one-way doors.

**Item (Plaid)** — One user's connection to one financial institution. Billed as the unit for subscription products (Transactions, Investments).

**Lot** — A specific purchase of a security at a specific price on a specific date. Tracking lots vs. positions matters for tax-loss harvesting and cost basis precision. We capture lots in schema from V1 but don't expose them in V1 UI.

**MCP (Model Context Protocol)** — Protocol for connecting external tools and data sources to Claude. Mentioned only if relevant; no MCP integrations planned for V1.

**One-way door** — A decision that's expensive or impossible to reverse later. Architect agent flags these explicitly. Examples: choice of database engine, lot vs. position-only schema, choice of aggregator.

**PRD** — Product Requirements Document. Lives as `PRD.md`. Source of truth for what we're building.

**RLS (Row-Level Security)** — Postgres feature, surfaced through Supabase, that enforces access policies at the row level. Critical for multi-tenant data isolation.

**Skill (Claude Code)** — A custom workflow Claude Code can invoke by name. Defined in `/skills/<skill-name>/SKILL.md`. Used for repeated patterns.

**Subagent** — A Claude Code agent invoked from within a Claude Code session, with its own system prompt and scope. Used to enforce role separation in this project.

**V1 / V2** — V1 is the locked initial scope. V2 is the next round after V1 ships. Anything labeled "V2" in this doc is deferred, not committed.

---

## Open questions

These are tracked here in v0.1 and resolved in subsequent versions. When resolved, move from this section into the relevant body section and reference in the changelog.

- ~~`[OPEN]` Agent prompt files (`.claude/agents/*.md`) — slated for Phase 5 drafting. Confirm timing or pull earlier if needed.~~ **Resolved in v0.4:** split across Phase 0.5 (Phase 1–4 roles) and Phase 5 (build-time roles). See agent roster section.
- `[OPEN]` Frontend framework choice — deferred to Phase 3 Architect proposal.
- `[OPEN]` Background worker technology — deferred to Phase 3 Architect proposal.
- ~~`[OPEN]` Backlog tooling: `TASKS.md` vs. GitHub Issues — deferred to Phase 4 entry.~~ **Resolved in v0.3:** Linear chosen, accessed via the official Linear MCP server. Operational details in `docs/linear-setup.md` (drafted in Phase 5). Cleanup of stale `TASKS.md` references completed in v0.5.
- `[OPEN]` Phase 4.5 practice feature — to be selected at Phase 4.5 entry.
- `[OPEN]` Design tokens format — deferred to Phase 2 entry, depends on frontend choice.

---

*End of WORKFLOW.md v1.0*
